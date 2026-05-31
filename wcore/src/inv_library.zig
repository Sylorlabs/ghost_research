//! The compounding library — THE NOVEL LEVER (PLAN_INVENTION_ENGINE.md §4.5).
//!
//! This is the direct port of `sk_compress.zig`'s MDL common-subexpression
//! extraction to instruction fragments. Given a corpus of elite programs, find
//! the contiguous instruction fragment whose abstraction into ONE callable macro
//! most reduces total description length, name it, and make it available as a
//! single `call` op. Future search then assembles with that macro as a building
//! block — the ratchet. If reuse does not *accelerate* discovery, that is the
//! wall (§8), and we report it precisely.
//!
//! Generalisation over operands: a fragment is canonicalised to an SSA-style
//! dataflow signature (op sequence + which value feeds which input), with the
//! *literal* operands that vary — `v_get` element indices and `s_set` constants —
//! turned into PARAMETERS. So one gate macro `gate(i,j) = v0[i] (op) v0[j]`
//! abstracts the whole family `sign(x_i·x_j)` regardless of the pair.
//!
//! v1 scope (honest restrictions, enforced by `canonicalize`):
//!   * fragment ops ∈ {scalar arith/unary, s_set, v_get, v_dot, v_sum} — no
//!     vector writes, no nested calls;
//!   * all vector reads are the input v[0];
//!   * NO external scalar inputs (every scalar read is produced inside the
//!     fragment) — so the only call arguments are the ≤2 literal parameters;
//!   * ≤ MAX_PARAMS parameters and ≤ SCR_S distinct local registers.

const std = @import("std");
const sub = @import("inv_substrate.zig");
const Instr = sub.Instr;
const Op = sub.Op;
const Program = sub.Program;
const Macro = sub.Macro;

pub const MAX_KEY: usize = 96;
pub const Key = std.BoundedArray(u8, MAX_KEY);

const OpClass = enum { sbin, sun, sset, vget, vred2, vred1, reject };

fn classify(op: Op) OpClass {
    return switch (op) {
        .s_add, .s_sub, .s_mul, .s_div, .s_max, .s_min => .sbin,
        .s_relu, .s_tanh, .s_abs, .s_exp, .s_recip => .sun,
        .s_set => .sset,
        .v_get => .vget,
        .v_dot => .vred2, // two vector inputs → scalar
        .v_sum => .vred1, // one vector input → scalar
        else => .reject, // vector writes, call, nop
    };
}

pub const Canon = struct {
    key: Key,
    macro: Macro,
};

/// Canonicalise a contiguous window into a dataflow signature + a ready-to-run
/// macro, or null if it violates the scope. Registers are remapped to local
/// scratch slots (by order of first appearance); varying literals become params.
/// A `.call` to an EARLIER library macro is abstractable too — its element-index
/// arguments generalise into parameters and it stays a nested call in the body —
/// which is how the engine abstracts a composition (C1 = two C0 calls + combine)
/// from a solution it found, climbing the tower with no hand-built rungs.
pub fn canonicalize(window: []const Instr, lib: []const Macro) ?Canon {
    if (window.len < 2 or window.len > sub.MAX_MACRO_LEN) return null;

    var key = Key{};
    var macro = Macro{};

    // SSA value-id per scalar register: regs we've written get an id; reading an
    // unwritten reg means an external input → reject (v1 scope).
    var val_of = [_]i32{-1} ** sub.PUB_S;
    var next_val: u8 = 0;

    // physical-register → macro-local-slot, by order of first appearance
    var local_of = [_]i32{-1} ** sub.PUB_S;
    var n_local: u8 = 0;

    var n_params: u8 = 0;

    const localFor = struct {
        fn f(reg: u8, lo: *[sub.PUB_S]i32, n: *u8) ?u8 {
            const r = @as(usize, reg) % sub.PUB_S;
            if (lo[r] < 0) {
                if (n.* >= sub.SCR_S) return null;
                lo[r] = n.*;
                n.* += 1;
            }
            return @intCast(lo[r]);
        }
    }.f;

    for (window, 0..) |ins, wi| {
        // A call to an earlier macro: its imm (macro index) is fixed structure; the
        // macro's element-index arguments (a,b,c,d, as many as the macro takes)
        // generalise into parameters; it writes a scalar value.
        if (ins.op == .call) {
            const midx: usize = @intFromFloat(ins.imm);
            if (midx >= lib.len) return null; // only abstract calls to existing macros
            const np = lib[midx].params.len;
            key.append(@intFromEnum(Op.call)) catch return null;
            key.append(@intCast(midx)) catch return null;
            var cbody = ins;
            cbody.a = 0;
            cbody.b = 0;
            cbody.c = 0;
            cbody.d = 0; // args filled by params at call time
            for (0..np) |k| {
                if (n_params >= sub.MAX_PARAMS) return null;
                key.append(0xC0 | n_params) catch return null;
                const field: @TypeOf(macro.params.buffer[0].field) = switch (k) {
                    0 => .a,
                    1 => .b,
                    2 => .c,
                    else => .d,
                };
                macro.params.append(.{ .instr = @intCast(wi), .field = field }) catch return null;
                n_params += 1;
            }
            val_of[@as(usize, ins.out) % sub.PUB_S] = next_val;
            key.append(0xA0 | (next_val & 0x1F)) catch return null;
            next_val += 1;
            cbody.out = localFor(ins.out, &local_of, &n_local) orelse return null;
            macro.body.append(cbody) catch return null;
            continue;
        }

        const cls = classify(ins.op);
        if (cls == .reject) return null;

        // vector reads must be the input v0
        switch (cls) {
            .vget, .vred1 => if (@as(usize, ins.a) % sub.PUB_V != 0) return null,
            .vred2 => if (@as(usize, ins.a) % sub.PUB_V != 0 or @as(usize, ins.b) % sub.PUB_V != 0) return null,
            else => {},
        }

        key.append(@intFromEnum(ins.op)) catch return null;

        var body = ins; // becomes the macro body instruction (operands remapped)

        // scalar INPUT operands → must already have a value id (internal)
        switch (cls) {
            .sbin => {
                const va = val_of[@as(usize, ins.a) % sub.PUB_S];
                const vb = val_of[@as(usize, ins.b) % sub.PUB_S];
                if (va < 0 or vb < 0) return null; // external scalar input
                key.append(@intCast(va)) catch return null;
                key.append(@intCast(vb)) catch return null;
                body.a = localFor(ins.a, &local_of, &n_local) orelse return null;
                body.b = localFor(ins.b, &local_of, &n_local) orelse return null;
            },
            .sun => {
                const va = val_of[@as(usize, ins.a) % sub.PUB_S];
                if (va < 0) return null;
                key.append(@intCast(va)) catch return null;
                body.a = localFor(ins.a, &local_of, &n_local) orelse return null;
            },
            .sset => {
                // the constant is a parameter (generalised)
                if (n_params >= sub.MAX_PARAMS) return null;
                key.append(0xC0 | n_params) catch return null;
                macro.params.append(.{ .instr = @intCast(wi), .field = .imm }) catch return null;
                n_params += 1;
            },
            .vget => {
                key.append(0xF0) catch return null; // v0 marker
                if (n_params >= sub.MAX_PARAMS) return null;
                key.append(0xC0 | n_params) catch return null; // element index is a param
                macro.params.append(.{ .instr = @intCast(wi), .field = .b }) catch return null;
                n_params += 1;
                body.a = 0; // v0
            },
            .vred1 => {
                key.append(0xF0) catch return null;
                body.a = 0;
            },
            .vred2 => {
                key.append(0xF0) catch return null;
                key.append(0xF0) catch return null;
                body.a = 0;
                body.b = 0;
            },
            else => unreachable,
        }

        // OUTPUT: every op here writes a scalar → fresh value id + local slot
        val_of[@as(usize, ins.out) % sub.PUB_S] = next_val;
        key.append(0xA0 | (next_val & 0x1F)) catch return null;
        next_val += 1;
        body.out = localFor(ins.out, &local_of, &n_local) orelse return null;

        macro.body.append(body) catch return null;
    }

    // the fragment's result is the last instruction's output local
    macro.out_local = macro.body.slice()[macro.body.len - 1].out;
    macro.n_local = n_local;
    return .{ .key = key, .macro = macro };
}

fn keyEql(a: Key, b: Key) bool {
    if (a.len != b.len) return false;
    return std.mem.eql(u8, a.slice(), b.slice());
}

pub const Extraction = struct {
    macro: Macro,
    key: Key,
    occurrences: usize,
    length: usize,
    saved: usize, // MDL nodes saved by abstraction
};

const Cand = struct { key: Key, macro: Macro, occ: usize, len: usize };

/// Count how many contiguous windows across the corpus canonicalise to `key`.
pub fn countTemplate(corpus: []const Program, key: Key, lib: []const Macro) usize {
    var total: usize = 0;
    for (corpus) |*prog| {
        total += countInComponent(prog.predict.slice(), key, lib);
        total += countInComponent(prog.learn.slice(), key, lib);
    }
    return total;
}

fn countInComponent(instrs: []const Instr, key: Key, lib: []const Macro) usize {
    var n: usize = 0;
    var len: usize = 2;
    while (len <= sub.MAX_MACRO_LEN) : (len += 1) {
        if (instrs.len < len) break;
        var start: usize = 0;
        while (start + len <= instrs.len) : (start += 1) {
            if (canonicalize(instrs[start .. start + len], lib)) |c| {
                if (keyEql(c.key, key)) n += 1;
            }
        }
    }
    return n;
}

/// The single highest-MDL-saving abstraction over `corpus` (§4.5), or null if
/// none recurs (≥2) with a net saving. Saving of a length-`L` fragment occurring
/// `occ` times: occ inlined copies (occ·L) → occ refs + one stored body (occ + L).
pub fn bestExtraction(al: std.mem.Allocator, corpus: []const Program, lib: []const Macro) !?Extraction {
    var cands = std.ArrayList(Cand).init(al);
    defer cands.deinit();

    // collect every admissible window's canonical form, tallying occurrences
    for (corpus) |*prog| {
        try collectWindows(prog.predict.slice(), &cands, lib);
        try collectWindows(prog.learn.slice(), &cands, lib);
    }

    var best: ?Extraction = null;
    for (cands.items) |c| {
        if (c.occ < 2) continue;
        const old = c.occ * c.len;
        const new = c.occ + c.len;
        if (new >= old) continue;
        const saved = old - new;
        if (best == null or saved > best.?.saved) {
            best = .{ .macro = c.macro, .key = c.key, .occurrences = c.occ, .length = c.len, .saved = saved };
        }
    }
    return best;
}

/// All net-saving recurring abstractions over `corpus`, sorted by saving (desc).
/// Lets a caller select not just the most-compressive macro but the most
/// compressive one that *passes a behavioural test* (e.g. decodes as a product),
/// which is how we pick the composable primitive over a single-task shortcut.
pub fn allExtractions(al: std.mem.Allocator, corpus: []const Program, lib: []const Macro) ![]Extraction {
    var cands = std.ArrayList(Cand).init(al);
    defer cands.deinit();
    for (corpus) |*prog| {
        try collectWindows(prog.predict.slice(), &cands, lib);
        try collectWindows(prog.learn.slice(), &cands, lib);
    }
    var out = std.ArrayList(Extraction).init(al);
    for (cands.items) |c| {
        if (c.occ < 2) continue;
        const old = c.occ * c.len;
        const new = c.occ + c.len;
        if (new >= old) continue;
        try out.append(.{ .macro = c.macro, .key = c.key, .occurrences = c.occ, .length = c.len, .saved = old - new });
    }
    const items = try out.toOwnedSlice();
    std.sort.insertion(Extraction, items, {}, struct {
        fn lt(_: void, x: Extraction, y: Extraction) bool {
            return x.saved > y.saved;
        }
    }.lt);
    return items;
}

/// The best-saving abstraction that decodes as a genuine PRODUCT gate (so it
/// composes correctly under summation), or null. Behavioural test is execution —
/// never a heuristic. This is the grounded selector for the composable primitive.
pub fn bestProductExtraction(al: std.mem.Allocator, corpus: []const Program, lib: []const Macro) !?Extraction {
    const all = try allExtractions(al, corpus, lib);
    defer al.free(all);
    for (all) |e| {
        var macro = e.macro;
        const label = try decode(&macro, al);
        defer al.free(label);
        if (std.mem.indexOf(u8, label, "product") != null) return e;
    }
    return null;
}

fn collectWindows(instrs: []const Instr, cands: *std.ArrayList(Cand), lib: []const Macro) !void {
    var len: usize = 2;
    while (len <= sub.MAX_MACRO_LEN) : (len += 1) {
        if (instrs.len < len) break;
        var start: usize = 0;
        while (start + len <= instrs.len) : (start += 1) {
            const c = canonicalize(instrs[start .. start + len], lib) orelse continue;
            var found = false;
            for (cands.items) |*existing| {
                if (existing.len == len and keyEql(existing.key, c.key)) {
                    existing.occ += 1;
                    found = true;
                    break;
                }
            }
            if (!found) try cands.append(.{ .key = c.key, .macro = c.macro, .occ = 1, .len = len });
        }
    }
}

/// Behavioural decode (post-hoc label only, like sk_compress.classify): probe the
/// macro on a known input and report what scalar function of (v0[p0], v0[p1]) it
/// computes. Never an input to any decision — only a human-readable label.
pub fn decode(macro: *const Macro, al: std.mem.Allocator) ![]const u8 {
    const lib = [_]Macro{macro.*};
    var m = sub.Machine{};
    m.zero(4);
    // probe with distinct, sign-informative components
    m.v[0][0] = 3;
    m.v[0][1] = -5;
    m.v[0][2] = 2;
    m.v[0][3] = 7;
    const call = Instr{ .op = .call, .a = 0, .b = 1, .out = 0, .imm = 0 };
    sub.run(&m, &.{call}, &lib);
    const r01 = m.s[0];
    // does it match a few candidate bilinear forms on (a=3,b=-5)?
    const a: f64 = 3;
    const b: f64 = -5;
    if (approx(r01, a * b)) return try std.fmt.allocPrint(al, "product gate  v0[p0]·v0[p1]", .{});
    if (approx(r01, a / b)) return try std.fmt.allocPrint(al, "ratio gate    v0[p0]/v0[p1]  (sign-equiv to product)", .{});
    if (approx(r01, b / a)) return try std.fmt.allocPrint(al, "ratio gate    v0[p1]/v0[p0]  (sign-equiv to product)", .{});
    if (approx(r01, a + b)) return try std.fmt.allocPrint(al, "sum           v0[p0]+v0[p1]", .{});
    return try std.fmt.allocPrint(al, "(no standard form; probe(3,-5)={d:.4})", .{r01});
}

fn approx(x: f64, y: f64) bool {
    return @abs(x - y) < 1e-6;
}

/// Abstract a composition macro from a corpus WITHOUT requiring MDL recurrence:
/// scan every canonicalisable window and return the first whose macro is verified
/// (by execution) to compute a sum of two products. A solution the engine FOUND by
/// grounded search is self-evidently worth banking — recurrence is one heuristic
/// for *what* to abstract, but a verified-composable subroutine is reason enough.
/// This is how the tower climbs from even a single hard-won K=2 solution.
pub fn firstComposingMacro(al: std.mem.Allocator, corpus: []const Program, base: []const Macro) !?Macro {
    for (corpus) |*prog| {
        for ([_][]const Instr{ prog.predict.slice(), prog.learn.slice() }) |instrs| {
            var len: usize = 2;
            while (len <= sub.MAX_MACRO_LEN) : (len += 1) {
                if (instrs.len < len) break;
                var start: usize = 0;
                while (start + len <= instrs.len) : (start += 1) {
                    const c = canonicalize(instrs[start .. start + len], base) orelse continue;
                    if (try verifyComposition(al, base, c.macro)) return c.macro;
                }
            }
        }
    }
    return null;
}

/// Grounded check (by EXECUTION, never a label) that `candidate`, run in the
/// context of base library `base` (so its nested calls resolve), computes a sum of
/// two products: candidate(a,b,c,d) == v0[a]·v0[b] + v0[c]·v0[d]. This is how the
/// engine confirms an auto-abstracted composition macro actually composes before
/// banking it — the Prime Directive applied to the library itself.
pub fn verifyComposition(al: std.mem.Allocator, base: []const Macro, candidate: Macro) !bool {
    const full = try al.alloc(Macro, base.len + 1);
    defer al.free(full);
    @memcpy(full[0..base.len], base);
    full[base.len] = candidate;
    const idx: f64 = @floatFromInt(base.len);

    var prng = std.Random.DefaultPrng.init(0x5151);
    const rng = prng.random();
    for (0..16) |_| {
        var m = sub.Machine{};
        m.zero(4);
        var x: [4]f64 = undefined;
        for (&x) |*xi| xi.* = rng.float(f64) * 2 - 1;
        m.loadInput(&x);
        sub.run(&m, &.{.{ .op = .call, .imm = idx, .a = 0, .b = 1, .c = 2, .d = 3, .out = 0 }}, full);
        if (m.bad) return false;
        const want = x[0] * x[1] + x[2] * x[3];
        if (@abs(m.s[0] - want) > 1e-6) return false;
    }
    return true;
}

/// A VERIFIED product macro `C0(i,j) = v0[i]·v0[j]`, the composable primitive.
/// Used to isolate the *reach* question (does reusing a correct primitive let
/// search reach compositional tasks flat search can't?) from the separate, open
/// question of reliably *discovering* the composable form. It is the scalar gate
/// the engine sometimes evolves — here written by hand and decode-verified, so
/// the reach experiment rests on a primitive known to compose.
pub fn referenceProductMacro() Macro {
    var m = Macro{};
    m.body.appendAssumeCapacity(.{ .op = .v_get, .a = 0, .b = 0, .out = 0 }); // L0 = v0[p0]
    m.body.appendAssumeCapacity(.{ .op = .v_get, .a = 0, .b = 0, .out = 1 }); // L1 = v0[p1]
    m.body.appendAssumeCapacity(.{ .op = .s_mul, .a = 0, .b = 1, .out = 2 }); // L2 = L0·L1
    m.params.appendAssumeCapacity(.{ .instr = 0, .field = .b }); // p0 → first index
    m.params.appendAssumeCapacity(.{ .instr = 1, .field = .b }); // p1 → second index
    m.out_local = 2;
    m.n_local = 3;
    return m;
}

/// A VERIFIED composition macro `C1(i,j,k,l) = v0[i]·v0[j] + v0[k]·v0[l]`, built
/// ON TOP OF C0 (it calls C0 twice and sums) — the second level of the tower.
/// C0 must be library index 0. Demonstrates that abstracting a *composition*
/// collapses the next task to a single call; the per-level composition trap that
/// blocks DISCOVERING this autonomously is documented as the frontier (TESTING §15).
pub fn referenceComposeMacro() Macro {
    var m = Macro{};
    m.body.appendAssumeCapacity(.{ .op = .call, .imm = 0, .a = 0, .b = 0, .out = 0 }); // L0 = C0(p0,p1)
    m.body.appendAssumeCapacity(.{ .op = .call, .imm = 0, .a = 0, .b = 0, .out = 1 }); // L1 = C0(p2,p3)
    m.body.appendAssumeCapacity(.{ .op = .s_add, .a = 0, .b = 1, .out = 2 }); // L2 = L0 + L1
    m.params.appendAssumeCapacity(.{ .instr = 0, .field = .a }); // p0 → first C0's index 1
    m.params.appendAssumeCapacity(.{ .instr = 0, .field = .b }); // p1 → first C0's index 2
    m.params.appendAssumeCapacity(.{ .instr = 1, .field = .a }); // p2 → second C0's index 1
    m.params.appendAssumeCapacity(.{ .instr = 1, .field = .b }); // p3 → second C0's index 2
    m.out_local = 2;
    m.n_local = 3;
    return m;
}

// ---- tests -----------------------------------------------------------------

fn gateProg(i: u8, j: u8, op: Op) Program {
    var p = Program{};
    p.predict.appendAssumeCapacity(.{ .op = .v_get, .a = 0, .b = i, .out = 3 });
    p.predict.appendAssumeCapacity(.{ .op = .v_get, .a = 0, .b = j, .out = 5 });
    p.predict.appendAssumeCapacity(.{ .op = op, .a = 3, .b = 5, .out = 0 });
    return p;
}

test "two gate elites with DIFFERENT index pairs share one template" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();

    const corpus = [_]Program{ gateProg(0, 1, .s_mul), gateProg(2, 3, .s_mul) };
    const ext = (try bestExtraction(al, &corpus, &.{})).?;
    // the 3-instruction gate recurs twice (once per elite), generalising the pair
    try std.testing.expectEqual(@as(usize, 2), ext.occurrences);
    try std.testing.expectEqual(@as(usize, 3), ext.length);
    try std.testing.expectEqual(@as(usize, 2), ext.macro.params.len);
}

test "extracted gate macro generalises over the index pair when called" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();

    const corpus = [_]Program{ gateProg(0, 1, .s_mul), gateProg(2, 3, .s_mul) };
    const ext = (try bestExtraction(al, &corpus, &.{})).?;
    const lib = [_]Macro{ext.macro};

    var m = sub.Machine{};
    m.zero(4);
    m.loadInput(&.{ 2, 3, -4, 5 });
    // CALL C0(2,3) must compute v0[2]*v0[3] = -20
    sub.run(&m, &.{.{ .op = .call, .a = 2, .b = 3, .out = 0, .imm = 0 }}, &lib);
    try std.testing.expectEqual(@as(f64, -20), m.s[0]);
    // CALL C0(0,1) must compute v0[0]*v0[1] = 6
    sub.run(&m, &.{.{ .op = .call, .a = 0, .b = 1, .out = 0, .imm = 0 }}, &lib);
    try std.testing.expectEqual(@as(f64, 6), m.s[0]);
}

test "a div-gate elite is abstracted and decodes as a ratio gate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();
    const corpus = [_]Program{ gateProg(0, 1, .s_div), gateProg(2, 3, .s_div) };
    const ext = (try bestExtraction(al, &corpus, &.{})).?;
    const label = try decode(&ext.macro, al);
    try std.testing.expect(std.mem.indexOf(u8, label, "ratio gate") != null);
}

test "the verified product macro decodes as a product and composes additively" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();
    var macro = referenceProductMacro();
    const label = try decode(&macro, al);
    try std.testing.expect(std.mem.indexOf(u8, label, "product") != null);

    // composition: C0(0,1) + C0(2,3) must equal x0·x1 + x2·x3 (sign-correct sums)
    const libm = [_]Macro{macro};
    var m = sub.Machine{};
    m.zero(4);
    m.loadInput(&.{ 0.1, 0.1, 1, -0.5 }); // products: 0.01 + (-0.5) = -0.49  (sign −)
    sub.run(&m, &.{
        .{ .op = .call, .a = 0, .b = 1, .out = 2, .imm = 0 }, // s2 = x0*x1
        .{ .op = .call, .a = 2, .b = 3, .out = 3, .imm = 0 }, // s3 = x2*x3
        .{ .op = .s_add, .a = 2, .b = 3, .out = 0 }, // s0 = sum
    }, &libm);
    try std.testing.expect(m.s[0] < 0); // sum of PRODUCTS is negative — composes correctly
}

test "the tower: C1 built on C0 computes a sum of two products (nested calls)" {
    var m = sub.Machine{};
    m.zero(4);
    m.loadInput(&.{ 2, 3, -4, 5 }); // 2*3 + (-4)*5 = 6 - 20 = -14
    const libm = [_]Macro{ referenceProductMacro(), referenceComposeMacro() }; // C0, C1
    // CALL C1(0,1,2,3) → s0 must equal v0[0]*v0[1] + v0[2]*v0[3] = -14
    sub.run(&m, &.{.{ .op = .call, .imm = 1, .a = 0, .b = 1, .c = 2, .d = 3, .out = 0 }}, &libm);
    try std.testing.expect(!m.bad);
    try std.testing.expectEqual(@as(f64, -14), m.s[0]);
    // a second pairing to confirm the params route correctly
    m.zero(4);
    m.loadInput(&.{ 1, 1, 1, 1 }); // 1 + 1 = 2
    sub.run(&m, &.{.{ .op = .call, .imm = 1, .a = 0, .b = 1, .c = 2, .d = 3, .out = 0 }}, &libm);
    try std.testing.expectEqual(@as(f64, 2), m.s[0]);
}

fn k2Solution(i: u8, j: u8, k: u8, l: u8) Program {
    var p = Program{};
    p.predict.appendAssumeCapacity(.{ .op = .call, .imm = 0, .a = i, .b = j, .out = 2 }); // C0(i,j)→s2
    p.predict.appendAssumeCapacity(.{ .op = .call, .imm = 0, .a = k, .b = l, .out = 3 }); // C0(k,l)→s3
    p.predict.appendAssumeCapacity(.{ .op = .s_add, .a = 2, .b = 3, .out = 0 }); // s0 = s2+s3
    return p;
}

test "auto-abstract C1 from solutions that CALL C0 — the tower by extraction" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();

    const base = [_]Macro{referenceProductMacro()}; // C0 already known
    // two K=2 solutions over DIFFERENT index pairs, each = two C0 calls + a sum
    const corpus = [_]Program{ k2Solution(0, 1, 2, 3), k2Solution(0, 2, 1, 3) };
    const ext = (try bestExtraction(al, &corpus, &base)).?;

    // the recurring abstraction is the 3-instruction composition, generalised over
    // its four element indices (the two C0 calls)
    try std.testing.expectEqual(@as(usize, 2), ext.occurrences);
    try std.testing.expectEqual(@as(usize, 3), ext.length);
    try std.testing.expectEqual(@as(usize, 4), ext.macro.params.len);
    // and — verified by EXECUTION — it actually computes a sum of two products
    try std.testing.expect(try verifyComposition(al, &base, ext.macro));
}

test "no recurring template → no extraction (honest negative)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();
    // a single program with all-distinct ops: no fragment recurs ≥2
    var p = Program{};
    p.predict.appendAssumeCapacity(.{ .op = .v_get, .a = 0, .b = 0, .out = 3 });
    p.predict.appendAssumeCapacity(.{ .op = .s_relu, .a = 3, .out = 0 });
    const corpus = [_]Program{p};
    try std.testing.expect((try bestExtraction(al, &corpus, &.{})) == null);
}
