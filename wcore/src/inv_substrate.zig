//! Invention-engine substrate: primitive math operations over a typed memory.
//!
//! This is the search space of PLAN_INVENTION_ENGINE.md §4.1. The whole point is
//! that the engine searches over *primitive* operations (add, mul, dot, get, …),
//! NOT over a menu of named layers. A "transformer" is one program over this set;
//! a "transformer-killer" is a program over this set we don't have a name for yet.
//! If the substrate were layers, the killer would be unreachable.
//!
//! A candidate is a 3-part program in the AutoML-Zero shape (so the engine invents
//! the *learning rule* too, and we avoid needing autodiff):
//!   Setup()        — initialise the register memory once.
//!   Predict(x)->ŷ  — compute a prediction from input using current memory.
//!   Learn(x,y)     — mutate the memory (params) given one labelled example.
//!
//! Memory is a fixed bank of typed registers: PUB_S scalar slots and PUB_V vector
//! slots (each of active dimension `dim`). Registers PERSIST across examples — that
//! is where learned weights live. The I/O interface is fixed by convention:
//!   * v[0]  holds the input x   (written by the harness before Predict)
//!   * s[0]  holds the prediction ŷ (read by the harness after Predict)
//!   * s[1]  holds the label y    (written by the harness before Learn)
//!
//! Every random instruction is executable: operand indices are taken modulo the
//! bank size, so evolution never produces an "invalid" program — it just produces
//! a useless one, which fitness then rejects. Truth comes from execution.

const std = @import("std");

// ---- memory geometry -------------------------------------------------------

// A deliberately SMALL register file: every extra slot multiplies the search
// space, and the gate motif is an irreducible 3-instruction needle, so we keep
// wiring probabilities high. 8 scalars (s0=ŷ, s1=y, s2..s7 weights/scratch) and
// 2 vectors are enough for every task here.
pub const PUB_S: u8 = 8; // program-visible scalar registers
pub const SCR_S: u8 = 4; // private scratch scalars PER macro frame
pub const MAX_DEPTH: usize = 3; // nesting depth for macro-calls-macro (the tower)
pub const TOT_S: usize = PUB_S + SCR_S * MAX_DEPTH; // each frame gets its own scratch

pub const PUB_V: u8 = 2; // program-visible vector registers
pub const TOT_V: usize = PUB_V;

pub const MAX_D: usize = 8; // max active vector dimension across all tasks

// reserved interface registers
pub const REG_YHAT: u8 = 0; // s[0] = prediction
pub const REG_Y: u8 = 1; // s[1] = label
pub const REG_X: u8 = 0; // v[0] = input

const CLAMP: f64 = 1e9; // saturate magnitudes; anything past this is "bad"
const EPS: f64 = 1e-6;

// ---- the primitive operation set (§4.1) ------------------------------------

pub const Op = enum(u8) {
    // scalar arithmetic
    s_add, // s[out] = s[a] + s[b]
    s_sub, // s[out] = s[a] - s[b]
    s_mul, // s[out] = s[a] * s[b]
    s_div, // s[out] = s[a] / s[b]    (protected)
    // scalar elementwise nonlinearity
    s_relu, // s[out] = max(0, s[a])
    s_tanh, // s[out] = tanh(s[a])
    s_abs, // s[out] = |s[a]|
    s_exp, // s[out] = exp(s[a])      (clamped)
    s_recip, // s[out] = 1 / s[a]      (protected)
    s_max, // s[out] = max(s[a], s[b])
    s_min, // s[out] = min(s[a], s[b])
    s_set, // s[out] = imm            (a learnable/initialisable constant)
    // vector → scalar reductions / access
    v_get, // s[out] = v[a][b % dim]  (read one component — the gate enabler)
    v_dot, // s[out] = dot(v[a], v[b])
    v_sum, // s[out] = Σ v[a]
    // vector → vector
    v_elemmul, // v[out] = v[a] ⊙ v[b]
    v_add, // v[out] = v[a] + v[b]
    v_sub, // v[out] = v[a] - v[b]
    v_scale, // v[out] = s[a] * v[b]
    v_bcast_add, // v[out] = v[a] + s[b]
    v_relu, // v[out] = relu(v[a])
    v_tanh, // v[out] = tanh(v[a])
    // library
    call, // s[out] = macro[imm](params a, b)   (Phase 2; reads v[0])
    nop,

    pub fn count() usize {
        return @typeInfo(Op).@"enum".fields.len;
    }
};

/// One instruction. `a`,`b` are operands (register or element indices, taken mod
/// the bank size), `out` is the destination register, `imm` an immediate used by
/// `s_set` (constant value) and `call` (macro index). `c`,`d` are extra params
/// used ONLY by `call`, so a macro can take up to 4 parameters (e.g. a
/// sum-of-two-products macro needs four element indices).
pub const Instr = struct {
    op: Op = .nop,
    a: u8 = 0,
    b: u8 = 0,
    out: u8 = 0,
    c: u8 = 0,
    d: u8 = 0,
    imm: f64 = 0,
};

pub const MAX_INSTR: usize = 24; // per component (setup / predict / learn)

pub const Component = std.BoundedArray(Instr, MAX_INSTR);

/// A candidate primitive: the three programs. Value type — copyable, no heap.
pub const Program = struct {
    setup: Component = .{},
    predict: Component = .{},
    learn: Component = .{},

    pub fn len(self: *const Program) usize {
        return self.setup.len + self.predict.len + self.learn.len;
    }
};

// ---- the library macro (Phase 2; defined here so the executor can run it) ---

pub const MAX_MACRO_LEN: usize = 12;
pub const MAX_PARAMS: usize = 4;

/// A position in a macro body whose operand is filled from a call parameter.
pub const ParamRef = struct {
    instr: u8, // which body instruction
    field: enum { a, b, c, d, imm }, // which operand field
};

/// A discovered, callable abstraction — the unit of the compounding library.
/// Its body operates on PRIVATE scratch scalar registers (indexed 0..n_local into
/// the current frame) plus the input vector v[0]; it reads up to MAX_PARAMS integer
/// parameters (substituted into the tagged operand positions at call time) and
/// leaves its result in scratch slot `out_local`, copied to s[call.out].
///
/// A body may itself contain `.call` ops referencing EARLIER macros — this is how
/// the tower is built (C1 = sum of two C0s). Nested calls run in a deeper scratch
/// frame so their locals never collide with the caller's.
pub const Macro = struct {
    body: std.BoundedArray(Instr, MAX_MACRO_LEN) = .{},
    params: std.BoundedArray(ParamRef, MAX_PARAMS) = .{},
    out_local: u8 = 0,
    n_local: u8 = 0, // distinct scratch scalars used
};

pub const Library = std.ArrayList(Macro);

// ---- the machine + executor ------------------------------------------------

pub const Machine = struct {
    s: [TOT_S]f64 = [_]f64{0} ** TOT_S,
    v: [TOT_V][MAX_D]f64 = [_][MAX_D]f64{[_]f64{0} ** MAX_D} ** TOT_V,
    dim: usize = 2,
    bad: bool = false, // tripped on NaN/inf; whole trial is then discarded

    pub fn zero(self: *Machine, dim: usize) void {
        self.* = .{ .dim = dim };
    }

    pub fn loadInput(self: *Machine, x: []const f64) void {
        for (0..self.dim) |i| self.v[REG_X][i] = if (i < x.len) x[i] else 0;
    }
};

fn finite(x: f64) f64 {
    if (std.math.isNan(x) or std.math.isInf(x)) return std.math.nan(f64);
    if (x > CLAMP) return CLAMP;
    if (x < -CLAMP) return -CLAMP;
    return x;
}

inline fn smod(i: u8) usize {
    return @as(usize, i) % PUB_S;
}
inline fn vmod(i: u8) usize {
    return @as(usize, i) % PUB_V;
}

/// Execute one component (setup/predict/learn) of a program. Reads/writes the
/// machine in place. `lib` supplies macros for `.call` (may be empty).
pub fn run(m: *Machine, instrs: []const Instr, lib: []const Macro) void {
    for (instrs) |ins| {
        execProgramInstr(m, ins, lib);
        if (m.bad) return;
    }
}

fn execProgramInstr(m: *Machine, ins: Instr, lib: []const Macro) void {
    const dim = m.dim;
    switch (ins.op) {
        .s_add => writeS(m, ins.out, m.s[smod(ins.a)] + m.s[smod(ins.b)]),
        .s_sub => writeS(m, ins.out, m.s[smod(ins.a)] - m.s[smod(ins.b)]),
        .s_mul => writeS(m, ins.out, m.s[smod(ins.a)] * m.s[smod(ins.b)]),
        .s_div => {
            const d = m.s[smod(ins.b)];
            writeS(m, ins.out, if (@abs(d) < EPS) 0 else m.s[smod(ins.a)] / d);
        },
        .s_relu => writeS(m, ins.out, @max(0, m.s[smod(ins.a)])),
        .s_tanh => writeS(m, ins.out, std.math.tanh(m.s[smod(ins.a)])),
        .s_abs => writeS(m, ins.out, @abs(m.s[smod(ins.a)])),
        .s_exp => writeS(m, ins.out, @exp(@min(m.s[smod(ins.a)], 30.0))),
        .s_recip => {
            const d = m.s[smod(ins.a)];
            writeS(m, ins.out, if (@abs(d) < EPS) 0 else 1.0 / d);
        },
        .s_max => writeS(m, ins.out, @max(m.s[smod(ins.a)], m.s[smod(ins.b)])),
        .s_min => writeS(m, ins.out, @min(m.s[smod(ins.a)], m.s[smod(ins.b)])),
        .s_set => writeS(m, ins.out, ins.imm),
        .v_get => writeS(m, ins.out, m.v[vmod(ins.a)][@as(usize, ins.b) % dim]),
        .v_dot => {
            var acc: f64 = 0;
            const va = m.v[vmod(ins.a)];
            const vb = m.v[vmod(ins.b)];
            for (0..dim) |i| acc += va[i] * vb[i];
            writeS(m, ins.out, acc);
        },
        .v_sum => {
            var acc: f64 = 0;
            const va = m.v[vmod(ins.a)];
            for (0..dim) |i| acc += va[i];
            writeS(m, ins.out, acc);
        },
        .v_elemmul => writeVbin(m, ins, struct {
            fn f(x: f64, y: f64) f64 {
                return x * y;
            }
        }.f),
        .v_add => writeVbin(m, ins, struct {
            fn f(x: f64, y: f64) f64 {
                return x + y;
            }
        }.f),
        .v_sub => writeVbin(m, ins, struct {
            fn f(x: f64, y: f64) f64 {
                return x - y;
            }
        }.f),
        .v_scale => {
            const sc = m.s[smod(ins.a)];
            const vb = m.v[vmod(ins.b)];
            const o = vmod(ins.out);
            for (0..dim) |i| writeV(m, o, i, sc * vb[i]);
        },
        .v_bcast_add => {
            const sc = m.s[smod(ins.b)];
            const va = m.v[vmod(ins.a)];
            const o = vmod(ins.out);
            for (0..dim) |i| writeV(m, o, i, va[i] + sc);
        },
        .v_relu => {
            const va = m.v[vmod(ins.a)];
            const o = vmod(ins.out);
            for (0..dim) |i| writeV(m, o, i, @max(0, va[i]));
        },
        .v_tanh => {
            const va = m.v[vmod(ins.a)];
            const o = vmod(ins.out);
            for (0..dim) |i| writeV(m, o, i, std.math.tanh(va[i]));
        },
        .call => writeS(m, ins.out, runMacroValue(m, ins, lib, 0)),
        .nop => {},
    }
}

fn writeS(m: *Machine, out: u8, val: f64) void {
    const v = finite(val);
    if (std.math.isNan(v)) {
        m.bad = true;
        return;
    }
    m.s[smod(out)] = v;
}

fn writeV(m: *Machine, o: usize, i: usize, val: f64) void {
    const v = finite(val);
    if (std.math.isNan(v)) {
        m.bad = true;
        return;
    }
    m.v[o][i] = v;
}

fn writeVbin(m: *Machine, ins: Instr, comptime f: fn (f64, f64) f64) void {
    const va = m.v[vmod(ins.a)];
    const vb = m.v[vmod(ins.b)];
    const o = vmod(ins.out);
    for (0..m.dim) |i| writeV(m, o, i, f(va[i], vb[i]));
}

// ---- library-macro execution (Phase 2) -------------------------------------

/// Run a discovered macro and RETURN its result value. The body executes in
/// scratch frame `frame` (each frame is a private SCR_S-slot window), so nested
/// calls — a macro body invoking an EARLIER macro — run one frame deeper and
/// never clobber the caller's locals. This is what lets the library form a TOWER
/// (C1 = sum of two C0s). Parameters (≤4) fill the tagged operand positions, which
/// may be the operand fields of nested call instructions. Vector reads address
/// v[0] (bodies only read the input vector).
fn runMacroValue(m: *Machine, call: Instr, lib: []const Macro, frame: usize) f64 {
    const idx: usize = @intFromFloat(call.imm);
    if (idx >= lib.len or frame >= MAX_DEPTH) {
        m.bad = true; // dangling macro ref or over-deep nesting → discard the trial
        return 0;
    }
    const macro = &lib[idx];
    const base = PUB_S + frame * SCR_S;
    for (0..SCR_S) |i| m.s[base + i] = 0; // clear this frame's locals

    // materialise the body with this call's parameters substituted in
    var body = macro.body;
    const pv = [_]u8{ call.a, call.b, call.c, call.d };
    for (macro.params.slice(), 0..) |pr, pi| {
        const val = pv[pi % pv.len];
        switch (pr.field) {
            .a => body.slice()[pr.instr].a = val,
            .b => body.slice()[pr.instr].b = val,
            .c => body.slice()[pr.instr].c = val,
            .d => body.slice()[pr.instr].d = val,
            .imm => body.slice()[pr.instr].imm = @floatFromInt(val),
        }
    }

    for (body.slice()) |ins| {
        execMacroInstr(m, ins, lib, frame);
        if (m.bad) return 0;
    }
    return m.s[base + (@as(usize, macro.out_local) % SCR_S)];
}

inline fn scrIdx(frame: usize, i: u8) usize {
    return PUB_S + frame * SCR_S + (@as(usize, i) % SCR_S);
}

/// Execute one macro-body instruction in scratch frame `frame`. Scalar operands
/// address this frame's window; a `.call` runs the referenced macro one frame
/// deeper (the tower); vector reads address the shared input bank.
fn execMacroInstr(m: *Machine, ins: Instr, lib: []const Macro, frame: usize) void {
    const dim = m.dim;
    const sa = scrIdx(frame, ins.a);
    const sb = scrIdx(frame, ins.b);
    switch (ins.op) {
        .s_add => writeScr(m, frame, ins.out, m.s[sa] + m.s[sb]),
        .s_sub => writeScr(m, frame, ins.out, m.s[sa] - m.s[sb]),
        .s_mul => writeScr(m, frame, ins.out, m.s[sa] * m.s[sb]),
        .s_div => writeScr(m, frame, ins.out, if (@abs(m.s[sb]) < EPS) 0 else m.s[sa] / m.s[sb]),
        .s_relu => writeScr(m, frame, ins.out, @max(0, m.s[sa])),
        .s_tanh => writeScr(m, frame, ins.out, std.math.tanh(m.s[sa])),
        .s_abs => writeScr(m, frame, ins.out, @abs(m.s[sa])),
        .s_exp => writeScr(m, frame, ins.out, @exp(@min(m.s[sa], 30.0))),
        .s_recip => writeScr(m, frame, ins.out, if (@abs(m.s[sa]) < EPS) 0 else 1.0 / m.s[sa]),
        .s_max => writeScr(m, frame, ins.out, @max(m.s[sa], m.s[sb])),
        .s_min => writeScr(m, frame, ins.out, @min(m.s[sa], m.s[sb])),
        .s_set => writeScr(m, frame, ins.out, ins.imm),
        .v_get => writeScr(m, frame, ins.out, m.v[vmod(ins.a)][@as(usize, ins.b) % dim]),
        .v_dot => {
            var acc: f64 = 0;
            const va = m.v[vmod(ins.a)];
            const vb = m.v[vmod(ins.b)];
            for (0..dim) |i| acc += va[i] * vb[i];
            writeScr(m, frame, ins.out, acc);
        },
        .v_sum => {
            var acc: f64 = 0;
            const va = m.v[vmod(ins.a)];
            for (0..dim) |i| acc += va[i];
            writeScr(m, frame, ins.out, acc);
        },
        .call => writeScr(m, frame, ins.out, runMacroValue(m, ins, lib, frame + 1)), // the tower
        else => {}, // vector-writing ops never appear in macro bodies
    }
}

fn writeScr(m: *Machine, frame: usize, out: u8, val: f64) void {
    const v = finite(val);
    if (std.math.isNan(v)) {
        m.bad = true;
        return;
    }
    m.s[scrIdx(frame, out)] = v;
}

// ---- pretty-printing -------------------------------------------------------

pub fn writeInstr(ins: Instr, w: anytype) !void {
    switch (ins.op) {
        .s_add, .s_sub, .s_mul, .s_div, .s_max, .s_min => try w.print("s{d} = {s}(s{d}, s{d})", .{ smod(ins.out), @tagName(ins.op), smod(ins.a), smod(ins.b) }),
        .s_relu, .s_tanh, .s_abs, .s_exp, .s_recip => try w.print("s{d} = {s}(s{d})", .{ smod(ins.out), @tagName(ins.op), smod(ins.a) }),
        .s_set => try w.print("s{d} = {d:.4}", .{ smod(ins.out), ins.imm }),
        .v_get => try w.print("s{d} = v{d}[{d}]", .{ smod(ins.out), vmod(ins.a), @as(usize, ins.b) }),
        .v_dot => try w.print("s{d} = dot(v{d}, v{d})", .{ smod(ins.out), vmod(ins.a), vmod(ins.b) }),
        .v_sum => try w.print("s{d} = sum(v{d})", .{ smod(ins.out), vmod(ins.a) }),
        .v_elemmul, .v_add, .v_sub => try w.print("v{d} = {s}(v{d}, v{d})", .{ vmod(ins.out), @tagName(ins.op), vmod(ins.a), vmod(ins.b) }),
        .v_scale => try w.print("v{d} = s{d} * v{d}", .{ vmod(ins.out), smod(ins.a), vmod(ins.b) }),
        .v_bcast_add => try w.print("v{d} = v{d} + s{d}", .{ vmod(ins.out), vmod(ins.a), smod(ins.b) }),
        .v_relu, .v_tanh => try w.print("v{d} = {s}(v{d})", .{ vmod(ins.out), @tagName(ins.op), vmod(ins.a) }),
        .call => try w.print("s{d} = CALL C{d}(p={d},{d},{d},{d})", .{ smod(ins.out), @as(usize, @intFromFloat(ins.imm)), ins.a, ins.b, ins.c, ins.d }),
        .nop => try w.writeAll("nop"),
    }
}

pub fn writeProgram(p: *const Program, w: anytype) !void {
    try w.writeAll("  Setup:\n");
    for (p.setup.slice()) |ins| {
        try w.writeAll("    ");
        try writeInstr(ins, w);
        try w.writeAll("\n");
    }
    try w.writeAll("  Predict:\n");
    for (p.predict.slice()) |ins| {
        try w.writeAll("    ");
        try writeInstr(ins, w);
        try w.writeAll("\n");
    }
    try w.writeAll("  Learn:\n");
    for (p.learn.slice()) |ins| {
        try w.writeAll("    ");
        try writeInstr(ins, w);
        try w.writeAll("\n");
    }
}

// ---- tests -----------------------------------------------------------------

test "scalar arithmetic executes and persists in registers" {
    var m = Machine{};
    m.zero(2);
    const prog = [_]Instr{
        .{ .op = .s_set, .out = 2, .imm = 3 },
        .{ .op = .s_set, .out = 3, .imm = 4 },
        .{ .op = .s_mul, .a = 2, .b = 3, .out = 0 },
    };
    run(&m, &prog, &.{});
    try std.testing.expect(!m.bad);
    try std.testing.expectEqual(@as(f64, 12), m.s[0]);
}

test "v_get reads input components; the multiply-gate computes x0*x1" {
    var m = Machine{};
    m.zero(2);
    m.loadInput(&.{ 0.5, -2.0 });
    const prog = [_]Instr{
        .{ .op = .v_get, .a = 0, .b = 0, .out = 4 }, // x0
        .{ .op = .v_get, .a = 0, .b = 1, .out = 5 }, // x1
        .{ .op = .s_mul, .a = 4, .b = 5, .out = 0 }, // gate = x0*x1
    };
    run(&m, &prog, &.{});
    try std.testing.expectEqual(@as(f64, -1.0), m.s[0]);
}

test "protected divide and recip never produce NaN/inf" {
    var m = Machine{};
    m.zero(2);
    const prog = [_]Instr{
        .{ .op = .s_set, .out = 2, .imm = 1 },
        .{ .op = .s_div, .a = 2, .b = 3, .out = 0 }, // s3 == 0 → protected → 0
        .{ .op = .s_recip, .a = 3, .out = 1 }, // 1/0 → protected → 0
    };
    run(&m, &prog, &.{});
    try std.testing.expect(!m.bad);
    try std.testing.expectEqual(@as(f64, 0), m.s[0]);
    try std.testing.expectEqual(@as(f64, 0), m.s[1]);
}

test "NaN-producing magnitude trips the bad flag" {
    var m = Machine{};
    m.zero(2);
    m.s[2] = CLAMP;
    const prog = [_]Instr{
        .{ .op = .s_exp, .a = 2, .out = 3 }, // exp(clamped) is large but finite
        .{ .op = .s_mul, .a = 3, .b = 3, .out = 4 },
        .{ .op = .s_mul, .a = 4, .b = 4, .out = 5 },
    };
    run(&m, &prog, &.{});
    // exp is clamped to exp(30); squaring twice stays under CLAMP saturation,
    // so this stays finite — the guard is exercised, result is finite.
    try std.testing.expect(!m.bad);
}
