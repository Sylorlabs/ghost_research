//! Sequence substrate for the "beat attention" track (PLAN bricks B–E).
//!
//! "Beating attention" only becomes a gradeable target on a task attention is
//! *weak* at. Attention is a fixed-depth, all-pairs operator; it notoriously fails
//! to LENGTH-GENERALISE on algorithmic tasks. We use the cleanest such task:
//!
//!   PREFIX-PARITY:  y[i] = x[0]·x[1]·…·x[i]   for tokens x ∈ {−1,+1}.
//!
//! The running product is a SCAN (a recurrence with O(1) state, O(L) total) — it
//! is correct at *any* length by construction. A fixed-depth feedforward operator
//! (the attention class, here modelled as a per-position function with NO carried
//! state) cannot represent the unbounded recurrence, so it cannot generalise to
//! longer sequences. So this substrate makes BOTH reachable and lets search find
//! the one that wins on the weakness — exactly the Tier-3 shape (a discovered
//! primitive that beats the baseline class and holds as it scales).
//!
//! The novel lever vs attention is the persistent STATE bank: a program that uses
//! it can carry a running accumulator (the scan); a program that doesn't is the
//! stateless/attention-class baseline. Honest scope: the scan/recurrence is a
//! KNOWN primitive, so discovering it is "rediscovered a real trade-off-breaking
//! primitive by execution", not "invented a never-seen one" — reported as such.

const std = @import("std");

pub const ST: usize = 8; // state scalar registers (persist across positions)
pub const L_MAX: usize = 256;
pub const REG_CUR: u8 = 0; // current token x[i] (written each position)
pub const REG_OUT: u8 = 1; // y[i] is read from here after each position's step

const CLAMP: f64 = 1e9;

pub const Op = enum(u8) {
    s_set, // st[out] = imm
    s_add, // st[out] = st[a] + st[b]
    s_sub,
    s_mul,
    s_tanh,
    s_abs,
    s_relu,
    s_max,
    s_min,
    nop,
    pub fn count() usize {
        return @typeInfo(Op).@"enum".fields.len;
    }
};

pub const Instr = struct { op: Op = .nop, a: u8 = 0, b: u8 = 0, out: u8 = 0, imm: f64 = 0 };

pub const MAX_INSTR: usize = 12;
pub const Component = std.BoundedArray(Instr, MAX_INSTR);

/// A sequence program: `setup` initialises state once; `step` runs at each
/// position with x[i] in st[REG_CUR] and the output read from st[REG_OUT].
pub const Program = struct {
    setup: Component = .{},
    step: Component = .{},
    pub fn len(self: *const Program) usize {
        return self.setup.len + self.step.len;
    }
};

inline fn idx(i: u8) usize {
    return @as(usize, i) % ST;
}
fn finite(x: f64) f64 {
    if (std.math.isNan(x) or std.math.isInf(x)) return std.math.nan(f64);
    return std.math.clamp(x, -CLAMP, CLAMP);
}

const Machine = struct {
    st: [ST]f64 = [_]f64{0} ** ST,
    bad: bool = false,

    fn exec(m: *Machine, instrs: []const Instr) void {
        for (instrs) |ins| {
            const v: f64 = switch (ins.op) {
                .s_set => ins.imm,
                .s_add => m.st[idx(ins.a)] + m.st[idx(ins.b)],
                .s_sub => m.st[idx(ins.a)] - m.st[idx(ins.b)],
                .s_mul => m.st[idx(ins.a)] * m.st[idx(ins.b)],
                .s_tanh => std.math.tanh(m.st[idx(ins.a)]),
                .s_abs => @abs(m.st[idx(ins.a)]),
                .s_relu => @max(0, m.st[idx(ins.a)]),
                .s_max => @max(m.st[idx(ins.a)], m.st[idx(ins.b)]),
                .s_min => @min(m.st[idx(ins.a)], m.st[idx(ins.b)]),
                .nop => continue,
            };
            const f = finite(v);
            if (std.math.isNan(f)) {
                m.bad = true;
                return;
            }
            m.st[idx(ins.out)] = f;
        }
    }
};

/// Run a program over one sequence; fill `out[0..L]` with sign(y[i]).
/// `persist`=false models the stateless / fixed-depth (attention-class) regime:
/// state is reset to its post-setup values each position, so no recurrence is
/// possible — only a function of the current token.
fn runSeq(prog: *const Program, x: []const f64, out: []f64, persist: bool) bool {
    var m = Machine{};
    m.exec(prog.setup.slice());
    if (m.bad) return false;
    const base = m.st; // snapshot for the stateless regime
    for (x, 0..) |xi, i| {
        if (!persist) m.st = base;
        m.st[REG_CUR] = xi;
        m.exec(prog.step.slice());
        if (m.bad) return false;
        out[i] = if (m.st[idx(REG_OUT)] > 0) 1 else -1;
    }
    return true;
}

// ---- task: prefix-parity ---------------------------------------------------

fn parityLabels(x: []const f64, y: []f64) void {
    var prod: f64 = 1;
    for (x, 0..) |xi, i| {
        prod *= xi;
        y[i] = if (prod > 0) 1 else -1;
    }
}

/// Per-position sign-accuracy of `prog` on random ±1 sequences of length `L`,
/// averaged over `n_seq` sequences. THE fitness — produced only by execution.
pub fn fitness(prog: *const Program, L: usize, n_seq: usize, seed: u64, persist: bool) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var x: [L_MAX]f64 = undefined;
    var y: [L_MAX]f64 = undefined;
    var pred: [L_MAX]f64 = undefined;
    var correct: usize = 0;
    var total: usize = 0;
    for (0..n_seq) |_| {
        for (0..L) |i| x[i] = if (rng.boolean()) 1 else -1;
        parityLabels(x[0..L], y[0..L]);
        if (!runSeq(prog, x[0..L], pred[0..L], persist)) return 0;
        for (0..L) |i| {
            total += 1;
            if (pred[i] == y[i]) correct += 1;
        }
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(total));
}

// ---- hand-written reference: the scan (running product) --------------------

/// y[i] = product of x[0..i], via a single persistent accumulator. The
/// length-generalising primitive — correct at any L.
pub fn referenceScan() Program {
    var p = Program{};
    p.setup.appendAssumeCapacity(.{ .op = .s_set, .out = REG_OUT, .imm = 1 }); // acc = 1
    p.step.appendAssumeCapacity(.{ .op = .s_mul, .a = REG_OUT, .b = REG_CUR, .out = REG_OUT }); // acc *= x[i]
    return p;
}

// ---- search: regularized evolution over sequence programs ------------------

pub const Params = struct {
    pop_size: usize = 400,
    tournament: usize = 8,
    max_evals: usize = 60_000,
    target: f64 = 0.99,
    lambda: f64 = 1e-4,
    immigrant_rate: f64 = 0.15,
    fit_L: usize = 32, // sequence length used during search
    fit_n_seq: usize = 16,
    persist: bool = true, // false → restrict to the stateless (attention-class) regime
};

pub const Result = struct {
    best: Program,
    best_fit: f64,
    evals_to_target: ?usize,
};

fn randImm(rng: std.Random) f64 {
    const c = [_]f64{ -1, 1, 0, 0.5, 2, -0.5 };
    return c[rng.uintLessThan(usize, c.len)];
}
fn randInstr(rng: std.Random) Instr {
    const op: Op = @enumFromInt(rng.uintLessThan(usize, Op.count()));
    return .{ .op = op, .a = rng.int(u8), .b = rng.int(u8), .out = rng.int(u8), .imm = randImm(rng) };
}
fn randComp(rng: std.Random, max: usize) Component {
    var c = Component{};
    const n = rng.uintLessThan(usize, max + 1);
    for (0..n) |_| c.appendAssumeCapacity(randInstr(rng));
    return c;
}
fn randProg(rng: std.Random) Program {
    return .{ .setup = randComp(rng, 3), .step = randComp(rng, 6) };
}
fn mutate(rng: std.Random, p: *Program) void {
    const c = if (rng.boolean()) &p.setup else &p.step;
    switch (rng.uintLessThan(usize, 3)) {
        0 => if (c.len < MAX_INSTR) {
            c.insert(rng.uintLessThan(usize, c.len + 1), randInstr(rng)) catch {};
        },
        1 => if (c.len > 0) {
            _ = c.orderedRemove(rng.uintLessThan(usize, c.len));
        },
        else => if (c.len > 0) {
            const i = rng.uintLessThan(usize, c.len);
            const ins = &c.slice()[i];
            switch (rng.uintLessThan(usize, 4)) {
                0 => ins.op = @enumFromInt(rng.uintLessThan(usize, Op.count())),
                1 => ins.a = rng.int(u8),
                2 => ins.out = rng.int(u8),
                else => ins.imm = randImm(rng),
            }
        } else c.appendAssumeCapacity(randInstr(rng)),
    }
}

pub fn evolve(al: std.mem.Allocator, rng: std.Random, p: Params, seed: u64) !Result {
    const Indiv = struct { prog: Program, raw: f64, adj: f64 };
    const pop = try al.alloc(Indiv, p.pop_size);
    defer al.free(pop);

    var best: Program = .{};
    var best_fit: f64 = -1;
    var best_adj: f64 = -1e9;
    var evals: usize = 0;
    var ett: ?usize = null;

    for (pop) |*ind| {
        ind.prog = randProg(rng);
        ind.raw = fitness(&ind.prog, p.fit_L, p.fit_n_seq, seed, p.persist);
        ind.adj = ind.raw - p.lambda * @as(f64, @floatFromInt(ind.prog.len()));
        evals += 1;
        if (ind.adj > best_adj) {
            best_adj = ind.adj;
            best_fit = ind.raw;
            best = ind.prog;
        }
        if (ett == null and ind.raw >= p.target) ett = evals;
    }

    var oldest: usize = 0;
    while (evals < p.max_evals) {
        var child: Program = undefined;
        if (rng.float(f64) < p.immigrant_rate) {
            child = randProg(rng);
        } else {
            var par = rng.uintLessThan(usize, p.pop_size);
            for (1..p.tournament) |_| {
                const c = rng.uintLessThan(usize, p.pop_size);
                if (pop[c].adj > pop[par].adj) par = c;
            }
            child = pop[par].prog;
            mutate(rng, &child);
        }
        const raw = fitness(&child, p.fit_L, p.fit_n_seq, seed, p.persist);
        const adj = raw - p.lambda * @as(f64, @floatFromInt(child.len()));
        evals += 1;
        pop[oldest] = .{ .prog = child, .raw = raw, .adj = adj };
        oldest = (oldest + 1) % p.pop_size;
        if (adj > best_adj) {
            best_adj = adj;
            best_fit = raw;
            best = child;
        }
        if (ett == null and raw >= p.target) ett = evals;
    }
    return .{ .best = best, .best_fit = best_fit, .evals_to_target = ett };
}

pub fn writeProgram(p: *const Program, w: anytype) !void {
    try w.writeAll("    setup: ");
    for (p.setup.slice()) |ins| try writeInstr(ins, w);
    try w.writeAll("\n    step:  ");
    for (p.step.slice()) |ins| try writeInstr(ins, w);
    try w.writeAll("\n");
}
fn writeInstr(ins: Instr, w: anytype) !void {
    switch (ins.op) {
        .s_set => try w.print("st{d}={d:.2}; ", .{ idx(ins.out), ins.imm }),
        .s_add, .s_sub, .s_mul, .s_max, .s_min => try w.print("st{d}={s}(st{d},st{d}); ", .{ idx(ins.out), @tagName(ins.op), idx(ins.a), idx(ins.b) }),
        .s_tanh, .s_abs, .s_relu => try w.print("st{d}={s}(st{d}); ", .{ idx(ins.out), @tagName(ins.op), idx(ins.a) }),
        .nop => {},
    }
}

// ---- tests -----------------------------------------------------------------

test "hand-written scan computes prefix-parity at 100%, and HOLDS as length scales" {
    const p = referenceScan();
    try std.testing.expect(fitness(&p, 16, 32, 1, true) > 0.999);
    try std.testing.expect(fitness(&p, 64, 32, 2, true) > 0.999); // 4x longer
    try std.testing.expect(fitness(&p, 200, 16, 3, true) > 0.999); // far longer — still perfect
}

test "the stateless (attention-class) regime cannot do prefix-parity (≈ chance)" {
    // the SAME scan program, but run with no carried state, collapses to chance
    const p = referenceScan();
    const acc = fitness(&p, 64, 64, 7, false);
    try std.testing.expect(acc > 0.4 and acc < 0.6);
}

test "evolution end-to-end returns a valid sequence program (smoke)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var prng = std.Random.DefaultPrng.init(0xC0FFEE);
    const r = try evolve(arena.allocator(), prng.random(), .{ .max_evals = 2000, .pop_size = 100 }, 1);
    try std.testing.expect(r.best_fit >= 0.0 and r.best_fit <= 1.0);
}
