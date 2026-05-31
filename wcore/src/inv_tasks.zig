//! Tasks + the fitness verifier (PLAN_INVENTION_ENGINE.md §4.3, §6).
//!
//! THE PRIME DIRECTIVE lives here: a candidate's fitness is produced ONLY by
//! running it on real data and measuring held-out performance. Nothing is ever
//! scored by plausibility. A program is `Setup`, then trained example-by-example
//! (`Predict` accumulates a prediction, `Learn` mutates the registers), then
//! measured on held-out examples it never learned from. Averaging over several
//! seeds rewards primitives that *generalise*, not ones overfit to one draw.
//!
//! A task is a **sum of K products**:  target(x) = Σ_p  x[p.i] · x[p.j].
//!   * K=1  → the single gate `x_i·x_j` (Phases 0–1).
//!   * K=2  → the double gate, K=4 → the quad gate (the compounding sweep): a
//!     family that shares the product motif and needs it applied K times.
//!
//! Two grading modes (the curriculum lever):
//!   * `.classify` — label = sign(target); fitness = held-out accuracy. This is
//!     the family's real objective, but it cannot tell a *product* gate from a
//!     *ratio* gate (`sign(a/b)=sign(a·b)`) — the Phase-2 underdetermination.
//!   * `.regress`  — fitness = held-out correlation with the *continuous* target.
//!     This DOES separate product from ratio, so a regression-graded bootstrap
//!     abstracts the TRUE product, which then composes correctly under summation.

const std = @import("std");
const sub = @import("inv_substrate.zig");
const Instr = sub.Instr;
const Program = sub.Program;
const Machine = sub.Machine;
const Macro = sub.Macro;

pub const MAX_PAIRS: usize = 4;

pub const Task = struct {
    dim: usize = 2,
    n_pairs: usize = 1,
    pairs: [MAX_PAIRS][2]usize = .{ .{ 0, 1 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },

    /// The continuous quantity the task is about: Σ x[i]·x[j] over the pairs.
    pub fn target(self: Task, x: []const f64) f64 {
        var acc: f64 = 0;
        for (0..self.n_pairs) |p| acc += x[self.pairs[p][0]] * x[self.pairs[p][1]];
        return acc;
    }
    pub fn label(self: Task, x: []const f64) f64 {
        return signf(self.target(x));
    }
    fn margin(self: Task, x: []const f64) f64 {
        return @abs(self.target(x));
    }
};

pub fn signf(v: f64) f64 {
    return if (v > 0) 1.0 else -1.0;
}

/// Single product gate `x_i·x_j`.
pub fn gate(dim: usize, i: usize, j: usize) Task {
    return multiGate(dim, &.{.{ i, j }});
}

/// Sum-of-products over the given index pairs.
pub fn multiGate(dim: usize, prs: []const [2]usize) Task {
    var t = Task{ .dim = dim, .n_pairs = prs.len };
    for (prs, 0..) |p, idx| t.pairs[idx] = p;
    return t;
}

pub const Grade = enum { classify, regress };

pub const Config = struct {
    n_train: usize = 100,
    n_test: usize = 100,
    n_seeds: usize = 3,
    base_seed: u64 = 0xC0FFEE,
    reject_margin: f64 = 0.05,
    grade: Grade = .classify,
};

fn sample(rng: std.Random, task: Task, buf: []f64, margin: f64) void {
    while (true) {
        for (0..task.dim) |d| buf[d] = rng.float(f64) * 2.0 - 1.0;
        if (task.margin(buf[0..task.dim]) >= margin) return;
    }
}

/// Running Pearson-correlation accumulator (for regression grading).
const Corr = struct {
    n: f64 = 0,
    sy: f64 = 0,
    st: f64 = 0,
    syt: f64 = 0,
    syy: f64 = 0,
    stt: f64 = 0,
    fn add(self: *Corr, y: f64, t: f64) void {
        self.n += 1;
        self.sy += y;
        self.st += t;
        self.syt += y * t;
        self.syy += y * y;
        self.stt += t * t;
    }
    fn pearson(self: Corr) f64 {
        const cov = self.n * self.syt - self.sy * self.st;
        const vy = self.n * self.syy - self.sy * self.sy;
        const vt = self.n * self.stt - self.st * self.st;
        const den = @sqrt(vy * vt);
        if (den < 1e-12) return 0; // ŷ (or t) constant → no correlation
        return cov / den;
    }
};

/// Fitness = mean held-out performance over seeds. Produced ONLY by execution.
/// NaN/inf during a trial discards that trial (worst score). Classification →
/// accuracy in [0,1]; regression → max(0, correlation) in [0,1].
pub fn evaluate(prog: *const Program, lib: []const Macro, task: Task, cfg: Config) f64 {
    var xbuf: [sub.MAX_D]f64 = undefined;
    var total: f64 = 0;

    for (0..cfg.n_seeds) |si| {
        var prng = std.Random.DefaultPrng.init(cfg.base_seed +% si *% 0x9E3779B97F4A7C15);
        const rng = prng.random();

        var m = Machine{};
        m.zero(task.dim);
        sub.run(&m, prog.setup.slice(), lib);
        if (m.bad) continue;

        // train: Predict then Learn, registers persist across examples
        var trained = true;
        for (0..cfg.n_train) |_| {
            sample(rng, task, &xbuf, cfg.reject_margin);
            const tgt = task.target(xbuf[0..task.dim]);
            const lbl = if (cfg.grade == .classify) signf(tgt) else tgt;
            m.loadInput(xbuf[0..task.dim]);
            m.s[sub.REG_Y] = 0; // label not visible at prediction time
            sub.run(&m, prog.predict.slice(), lib);
            m.s[sub.REG_Y] = lbl; // …appears only for Learn
            sub.run(&m, prog.learn.slice(), lib);
            if (m.bad) {
                trained = false;
                break;
            }
        }
        if (!trained) continue;

        // held-out: Predict only
        var correct: usize = 0;
        var corr = Corr{};
        var counted: usize = 0;
        for (0..cfg.n_test) |_| {
            sample(rng, task, &xbuf, cfg.reject_margin);
            const tgt = task.target(xbuf[0..task.dim]);
            m.loadInput(xbuf[0..task.dim]);
            m.s[sub.REG_Y] = 0;
            sub.run(&m, prog.predict.slice(), lib);
            if (m.bad) break;
            counted += 1;
            const yhat = m.s[sub.REG_YHAT];
            if (cfg.grade == .classify) {
                if (signf(yhat) == signf(tgt)) correct += 1;
            } else {
                corr.add(yhat, tgt);
            }
        }
        if (counted == cfg.n_test) {
            if (cfg.grade == .classify) {
                total += @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(cfg.n_test));
            } else {
                total += @max(0, corr.pearson());
            }
        }
    }
    return total / @as(f64, @floatFromInt(cfg.n_seeds));
}

/// MDL-adjusted fitness (§4.4): performance − λ·length.
pub fn adjusted(perf: f64, prog_len: usize, lambda: f64) f64 {
    return perf - lambda * @as(f64, @floatFromInt(prog_len));
}

// ---- reference programs (for the Phase-0 sanity gate) ----------------------

/// Hand-written KNOWN-GOOD program for the single gate: discover x_i·x_j, predict
/// ŷ = w·gate, learn w by a gradient step. If the verifier does not score THIS
/// high, the verifier is broken (§ Phase 0 sanity gate).
pub fn referenceGate(i: u8, j: u8) Program {
    var p = Program{};
    p.setup.appendAssumeCapacity(.{ .op = .s_set, .out = 2, .imm = 0.1 }); // w
    p.setup.appendAssumeCapacity(.{ .op = .s_set, .out = 3, .imm = 0.1 }); // lr
    p.predict.appendAssumeCapacity(.{ .op = .v_get, .a = 0, .b = i, .out = 4 });
    p.predict.appendAssumeCapacity(.{ .op = .v_get, .a = 0, .b = j, .out = 5 });
    p.predict.appendAssumeCapacity(.{ .op = .s_mul, .a = 4, .b = 5, .out = 6 }); // gate
    p.predict.appendAssumeCapacity(.{ .op = .s_mul, .a = 2, .b = 6, .out = 0 }); // yhat
    p.learn.appendAssumeCapacity(.{ .op = .s_sub, .a = 1, .b = 0, .out = 7 }); // err
    p.learn.appendAssumeCapacity(.{ .op = .s_mul, .a = 7, .b = 6, .out = 7 }); // err*gate
    p.learn.appendAssumeCapacity(.{ .op = .s_mul, .a = 7, .b = 3, .out = 7 }); // lr*err*gate
    p.learn.appendAssumeCapacity(.{ .op = .s_add, .a = 2, .b = 7, .out = 2 }); // w +=
    return p;
}

/// A linear model that CANNOT solve the single gate (no product feature).
pub fn referenceLinear() Program {
    var p = Program{};
    p.setup.appendAssumeCapacity(.{ .op = .s_set, .out = 2, .imm = 0.1 }); // w0
    p.setup.appendAssumeCapacity(.{ .op = .s_set, .out = 3, .imm = 0.1 }); // w1
    p.setup.appendAssumeCapacity(.{ .op = .s_set, .out = 4, .imm = 0.1 }); // lr
    p.predict.appendAssumeCapacity(.{ .op = .v_get, .a = 0, .b = 0, .out = 5 });
    p.predict.appendAssumeCapacity(.{ .op = .v_get, .a = 0, .b = 1, .out = 6 });
    p.predict.appendAssumeCapacity(.{ .op = .s_mul, .a = 2, .b = 5, .out = 7 });
    p.predict.appendAssumeCapacity(.{ .op = .s_mul, .a = 3, .b = 6, .out = 5 });
    p.predict.appendAssumeCapacity(.{ .op = .s_add, .a = 7, .b = 5, .out = 0 });
    p.learn.appendAssumeCapacity(.{ .op = .s_sub, .a = 1, .b = 0, .out = 7 });
    p.learn.appendAssumeCapacity(.{ .op = .s_mul, .a = 7, .b = 4, .out = 7 });
    p.learn.appendAssumeCapacity(.{ .op = .v_get, .a = 0, .b = 0, .out = 5 });
    p.learn.appendAssumeCapacity(.{ .op = .s_mul, .a = 7, .b = 5, .out = 5 });
    p.learn.appendAssumeCapacity(.{ .op = .s_add, .a = 2, .b = 5, .out = 2 });
    p.learn.appendAssumeCapacity(.{ .op = .v_get, .a = 0, .b = 1, .out = 6 });
    p.learn.appendAssumeCapacity(.{ .op = .s_mul, .a = 7, .b = 6, .out = 6 });
    p.learn.appendAssumeCapacity(.{ .op = .s_add, .a = 3, .b = 6, .out = 3 });
    return p;
}

// ---- tests -----------------------------------------------------------------

test "sanity gate: hand-written gate program scores high on the single gate" {
    const task = gate(2, 0, 1);
    const prog = referenceGate(0, 1);
    const cfg = Config{ .n_train = 200, .n_test = 200, .n_seeds = 4 };
    try std.testing.expect(evaluate(&prog, &.{}, task, cfg) > 0.95);
}

test "sanity gate: a linear model is stuck at chance on the single gate" {
    const task = gate(2, 0, 1);
    const prog = referenceLinear();
    const cfg = Config{ .n_train = 200, .n_test = 200, .n_seeds = 4 };
    try std.testing.expect(evaluate(&prog, &.{}, task, cfg) < 0.65);
}

test "sanity gate: an empty (garbage) program scores at chance" {
    const task = gate(2, 0, 1);
    const prog = Program{};
    const cfg = Config{ .n_train = 200, .n_test = 200, .n_seeds = 4 };
    const acc = evaluate(&prog, &.{}, task, cfg);
    try std.testing.expect(acc > 0.35 and acc < 0.65);
}

test "regression grading: the product gate correlates ~1, a linear model ~0" {
    const task = gate(2, 0, 1);
    const cfg = Config{ .n_train = 200, .n_test = 400, .n_seeds = 4, .grade = .regress };
    const prod = referenceGate(0, 1);
    const lin = referenceLinear();
    try std.testing.expect(evaluate(&prod, &.{}, task, cfg) > 0.95); // captures x0*x1
    try std.testing.expect(evaluate(&lin, &.{}, task, cfg) < 0.5); // can't
}

test "double gate target is the sum of two products" {
    const task = multiGate(4, &.{ .{ 0, 1 }, .{ 2, 3 } });
    const x = [_]f64{ 2, 3, -1, 5 }; // 2*3 + (-1)*5 = 1
    try std.testing.expectEqual(@as(f64, 1), task.target(&x));
    try std.testing.expectEqual(@as(f64, 1), task.label(&x));
}
