//! G49 (extension) — cross-audit of the NATIVE prover path (AIG lowering +
//! structural hashing + miter + DPLL SAT) against a from-scratch independent
//! truth-table evaluator, on ~1000+ RANDOM cases (the 2026-07-05 G49 audit
//! used 99 hand-built cases vs libz3; this one uses an instrument that shares
//! ZERO code with the prover: direct recursive evaluation of the expression
//! tree over every assignment).
//!
//! Instrument under test (exact production pattern from z3_cross_audit.zig /
//! superoptimizer_search): lowerExpr -> Aig.createMiter -> toSat ->
//! addClause(litAssertTrue(miter)) -> solve(). SAT => different.
//! Also audited: the AIG sim-vector layer (getSimValue truth table vs the
//! independent evaluator, per side, per case).
//!
//! Case classes:
//!   R  random pair (mostly non-equivalent)
//!   E  template-equivalent pair (distributivity / absorption / xor-assoc /
//!      mux — structurally different, semantically equal; forces real DPLL
//!      UNSAT work, strash cannot collapse all of them)
//!   M  single-minterm flip (differ on exactly ONE assignment — adversarial
//!      for any sampling-based shortcut)
//!   H  handcrafted edge cases (constants, x vs ~~x, contradictions, ...)
//!
//! Build (from 04_verified_synthesis/):
//!   zig build-exe -O ReleaseFast --dep native_prover \
//!     -Mroot=src/g49_tt_cross_audit.zig \
//!     -Mnative_prover=../core/src/adapters/native_prover.zig \
//!     -femit-bin=zig-out/bin/g49_tt_cross_audit
//! Single thread; DPLL cases capped at <=18 AIG nodes (the native solver is a
//! full-enumeration backtracker: 2^nodes leaves).

const std = @import("std");
const prover = @import("native_prover");

// ------------------------------------------------------------ expressions --

const Expr = union(enum) {
    var_id: u8,
    c0,
    c1,
    not_e: *const Expr,
    and_e: [2]*const Expr,
    or_e: [2]*const Expr,
    xor_e: [2]*const Expr,
};

const Eb = struct {
    a: std.mem.Allocator,

    fn mk(self: *Eb, e: Expr) *const Expr {
        const p = self.a.create(Expr) catch unreachable;
        p.* = e;
        return p;
    }
    fn v(self: *Eb, id: u8) *const Expr {
        return self.mk(.{ .var_id = id });
    }
    fn c0(self: *Eb) *const Expr {
        return self.mk(.c0);
    }
    fn c1(self: *Eb) *const Expr {
        return self.mk(.c1);
    }
    fn not(self: *Eb, x: *const Expr) *const Expr {
        return self.mk(.{ .not_e = x });
    }
    fn land(self: *Eb, x: *const Expr, y: *const Expr) *const Expr {
        return self.mk(.{ .and_e = .{ x, y } });
    }
    fn lor(self: *Eb, x: *const Expr, y: *const Expr) *const Expr {
        return self.mk(.{ .or_e = .{ x, y } });
    }
    fn lxor(self: *Eb, x: *const Expr, y: *const Expr) *const Expr {
        return self.mk(.{ .xor_e = .{ x, y } });
    }
};

// INDEPENDENT instrument: recursive evaluation, no AIG, no SAT, no shared code.
fn evalExpr(e: *const Expr, assignment: u8) bool {
    return switch (e.*) {
        .var_id => |id| ((assignment >> @intCast(id)) & 1) != 0,
        .c0 => false,
        .c1 => true,
        .not_e => |p| !evalExpr(p, assignment),
        .and_e => |p| evalExpr(p[0], assignment) and evalExpr(p[1], assignment),
        .or_e => |p| evalExpr(p[0], assignment) or evalExpr(p[1], assignment),
        .xor_e => |p| evalExpr(p[0], assignment) != evalExpr(p[1], assignment),
    };
}

fn truthTable(e: *const Expr, num_vars: u8) u16 {
    var tt: u16 = 0;
    var a: u8 = 0;
    const n: u8 = @as(u8, 1) << @intCast(num_vars);
    while (a < n) : (a += 1) {
        if (evalExpr(e, a)) tt |= (@as(u16, 1) << @intCast(a));
    }
    return tt;
}

// ------------------------------------------------- instrument under test ----

fn lowerExpr(aig: *prover.Aig, e: *const Expr, env: []const prover.NodeId) !prover.NodeId {
    return switch (e.*) {
        .var_id => |id| env[id],
        .c0 => @as(prover.NodeId, 0),
        .c1 => @as(prover.NodeId, 1),
        .not_e => |p| aig.notNode(try lowerExpr(aig, p, env)),
        .and_e => |p| try aig.andNodes(try lowerExpr(aig, p[0], env), try lowerExpr(aig, p[1], env)),
        .or_e => |p| try aig.orNodes(try lowerExpr(aig, p[0], env), try lowerExpr(aig, p[1], env)),
        .xor_e => |p| try aig.xorNodes(try lowerExpr(aig, p[0], env), try lowerExpr(aig, p[1], env)),
    };
}

fn litAssertTrue(node: prover.NodeId) prover.Lit {
    const var_idx: prover.Lit = @intCast((node >> 1) + 1);
    return if ((node & 1) != 0) -var_idx else var_idx;
}

const NativeResult = struct {
    equiv: bool,
    nodes: usize,
    structural: bool, // miter collapsed to a constant, DPLL not needed
    sim_tt_left: u16,
    sim_tt_right: u16,
    oversize: bool, // DPLL skipped (node cap); only sim layer audited
};

fn checkNative(alloc: std.mem.Allocator, left: *const Expr, right: *const Expr, num_vars: u8, node_cap: usize) !NativeResult {
    var aig = prover.Aig.init(alloc);
    defer aig.deinit();

    // input sim patterns: assignment index a -> bit a of the sim vector
    var env: [4]prover.NodeId = undefined;
    const n_assign: u8 = @as(u8, 1) << @intCast(num_vars);
    var vi: u8 = 0;
    while (vi < num_vars) : (vi += 1) {
        env[vi] = try aig.createInput();
        var pat: u64 = 0;
        var a: u8 = 0;
        while (a < n_assign) : (a += 1) {
            if (((a >> @intCast(vi)) & 1) != 0) pat |= (@as(u64, 1) << @intCast(a));
        }
        aig.setInputSimValue(env[vi], pat);
    }

    const l = try lowerExpr(&aig, left, env[0..num_vars]);
    const r = try lowerExpr(&aig, right, env[0..num_vars]);
    const ttmask: u16 = @intCast((@as(u32, 1) << @intCast(n_assign)) - 1);
    const sim_l: u16 = @intCast(aig.getSimValue(l) & ttmask);
    const sim_r: u16 = @intCast(aig.getSimValue(r) & ttmask);

    const miter = try aig.createMiter(l, r);
    const nodes = aig.nodes.items.len;

    if (miter == 0 or miter == 1) {
        return .{
            .equiv = (miter == 0),
            .nodes = nodes,
            .structural = true,
            .sim_tt_left = sim_l,
            .sim_tt_right = sim_r,
            .oversize = false,
        };
    }
    if (nodes > node_cap) {
        return .{
            .equiv = false,
            .nodes = nodes,
            .structural = false,
            .sim_tt_left = sim_l,
            .sim_tt_right = sim_r,
            .oversize = true,
        };
    }
    var solver = try aig.toSat(alloc);
    defer solver.deinit();
    try solver.addClause(&[_]prover.Lit{litAssertTrue(miter)});
    const sat = solver.solve();
    return .{
        .equiv = !sat,
        .nodes = nodes,
        .structural = false,
        .sim_tt_left = sim_l,
        .sim_tt_right = sim_r,
        .oversize = false,
    };
}

// ------------------------------------------------------------- generator ----

fn randomExpr(eb: *Eb, rnd: std.Random, num_vars: u8, depth: u8) *const Expr {
    if (depth == 0) {
        const roll = rnd.uintLessThan(u8, 20);
        if (roll < 1) return eb.c0();
        if (roll < 2) return eb.c1();
        return eb.v(rnd.uintLessThan(u8, num_vars));
    }
    const roll = rnd.uintLessThan(u8, 10);
    if (roll < 2) return eb.not(randomExpr(eb, rnd, num_vars, depth - 1));
    if (roll < 5) return eb.land(randomExpr(eb, rnd, num_vars, depth - 1), randomExpr(eb, rnd, num_vars, depth - 1));
    if (roll < 8) return eb.lor(randomExpr(eb, rnd, num_vars, depth - 1), randomExpr(eb, rnd, num_vars, depth - 1));
    if (roll < 9) return eb.lxor(randomExpr(eb, rnd, num_vars, depth - 1), randomExpr(eb, rnd, num_vars, depth - 1));
    return eb.v(rnd.uintLessThan(u8, num_vars));
}

// minterm for one assignment: AND of all literals
fn minterm(eb: *Eb, num_vars: u8, assignment: u8) *const Expr {
    var acc: ?*const Expr = null;
    var i: u8 = 0;
    while (i < num_vars) : (i += 1) {
        const lit = if (((assignment >> @intCast(i)) & 1) != 0) eb.v(i) else eb.not(eb.v(i));
        acc = if (acc) |a| eb.land(a, lit) else lit;
    }
    return acc.?;
}

// semantically-equal, structurally-different template pairs
fn templatePair(eb: *Eb, rnd: std.Random, num_vars: u8) [2]*const Expr {
    const A = randomExpr(eb, rnd, num_vars, 1);
    const B = randomExpr(eb, rnd, num_vars, 1);
    const C = randomExpr(eb, rnd, num_vars, 1);
    return switch (rnd.uintLessThan(u8, 6)) {
        0 => .{ eb.land(A, eb.lor(B, C)), eb.lor(eb.land(A, B), eb.land(A, C)) }, // distribute
        1 => .{ eb.lor(A, eb.land(A, B)), A }, // absorption
        2 => .{ eb.lxor(eb.lxor(A, B), C), eb.lxor(A, eb.lxor(B, C)) }, // xor assoc
        3 => .{ eb.lor(eb.land(A, B), eb.land(eb.not(A), B)), B }, // mux collapse
        4 => .{ eb.not(eb.lxor(A, B)), eb.lxor(A, eb.not(B)) }, // xnor forms
        else => .{ eb.lor(eb.not(A), eb.not(B)), eb.not(eb.land(A, B)) }, // De Morgan
    };
}

// ------------------------------------------------------------------ main ----

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    var eb = Eb{ .a = arena.allocator() };

    const w = std.io.getStdOut().writer();
    var prng2 = std.Random.DefaultPrng.init(0x6749_2026_0710_AA51);
    const rnd = prng2.random();
    var timer = try std.time.Timer.start();

    const node_cap: usize = 18;

    var total: usize = 0;
    var disagreements: usize = 0;
    var sim_mismatch: usize = 0;
    var structural_cnt: usize = 0;
    var dpll_cnt: usize = 0;
    var oversize_cnt: usize = 0;
    var equiv_cases: usize = 0;
    var per_class_total = [_]usize{0} ** 4;
    var per_class_dis = [_]usize{0} ** 4;
    const class_names = [_][]const u8{ "R random", "E template-equiv", "M minterm-flip", "H handcrafted" };

    try w.print("G49 extension: native prover vs from-scratch truth table\n", .{});
    try w.print("=========================================================\n", .{});

    // -------- class H: handcrafted edges (run first, fixed) --------
    {
        const x = eb.v(0);
        const y = eb.v(1);
        const cases = [_][2]*const Expr{
            .{ x, x },
            .{ x, eb.not(eb.not(x)) },
            .{ eb.land(x, eb.not(x)), eb.c0() },
            .{ eb.lor(x, eb.not(x)), eb.c1() },
            .{ eb.lxor(x, x), eb.c0() },
            .{ eb.c0(), eb.c1() },
            .{ x, y },
            .{ x, eb.not(x) },
            .{ eb.land(x, y), eb.land(y, x) },
            .{ eb.not(eb.land(x, y)), eb.lor(eb.not(x), eb.not(y)) },
            .{ eb.lxor(x, y), eb.lxor(y, x) },
            .{ eb.land(eb.c1(), x), x },
            .{ eb.lor(eb.c0(), x), x },
            .{ eb.land(eb.c0(), x), eb.c0() },
            .{ eb.lxor(x, eb.c1()), eb.not(x) },
            // consensus "identity" that is actually FALSE as equivalence:
            .{ eb.lor(eb.land(x, y), eb.land(eb.not(x), y)), eb.lor(x, y) },
        };
        for (cases) |pair| {
            const tt_l = truthTable(pair[0], 2);
            const tt_r = truthTable(pair[1], 2);
            const truth_equiv = (tt_l == tt_r);
            const res = try checkNative(gpa.allocator(), pair[0], pair[1], 2, node_cap);
            total += 1;
            per_class_total[3] += 1;
            if (res.structural) structural_cnt += 1 else if (!res.oversize) dpll_cnt += 1;
            if (truth_equiv) equiv_cases += 1;
            if (res.sim_tt_left != tt_l or res.sim_tt_right != tt_r) sim_mismatch += 1;
            if (!res.oversize and res.equiv != truth_equiv) {
                disagreements += 1;
                per_class_dis[3] += 1;
                try w.print("DISAGREE [H]: native={s} truth={s} ttL={b} ttR={b}\n", .{ if (res.equiv) "equiv" else "diff", if (truth_equiv) "equiv" else "diff", tt_l, tt_r });
            }
        }
    }

    // -------- classes R, E, M: randomized bulk --------
    var attempts: usize = 0;
    while (total < 5016 and attempts < 60_000) : (attempts += 1) {
        if (timer.read() > 780 * std.time.ns_per_s) break;
        const cls: usize = switch (rnd.uintLessThan(u8, 10)) {
            0, 1, 2, 3 => @as(usize, 0), // R
            4, 5, 6 => @as(usize, 1), // E
            else => @as(usize, 2), // M
        };
        const num_vars: u8 = 2 + rnd.uintLessThan(u8, 3); // 2..4
        var left: *const Expr = undefined;
        var right: *const Expr = undefined;
        switch (cls) {
            0 => {
                left = randomExpr(&eb, rnd, num_vars, 2);
                right = randomExpr(&eb, rnd, num_vars, 2);
            },
            1 => {
                const p = templatePair(&eb, rnd, num_vars);
                left = p[0];
                right = p[1];
            },
            else => {
                left = randomExpr(&eb, rnd, num_vars, 2);
                const a = rnd.uintLessThan(u8, @as(u8, 1) << @intCast(num_vars));
                right = eb.lxor(left, minterm(&eb, num_vars, a));
            },
        }

        const tt_l = truthTable(left, num_vars);
        const tt_r = truthTable(right, num_vars);
        const truth_equiv = (tt_l == tt_r);
        const res = try checkNative(gpa.allocator(), left, right, num_vars, node_cap);

        // sim layer is audited for every case, even oversize ones
        if (res.sim_tt_left != tt_l or res.sim_tt_right != tt_r) {
            sim_mismatch += 1;
            try w.print("SIM MISMATCH [{s}]: simL={b} ttL={b} simR={b} ttR={b}\n", .{ class_names[cls], res.sim_tt_left, tt_l, res.sim_tt_right, tt_r });
        }
        if (res.oversize) {
            oversize_cnt += 1;
            continue; // does not count toward the 1000+ SAT-audited cases
        }
        total += 1;
        per_class_total[cls] += 1;
        if (res.structural) structural_cnt += 1 else dpll_cnt += 1;
        if (truth_equiv) equiv_cases += 1;
        if (res.equiv != truth_equiv) {
            disagreements += 1;
            per_class_dis[cls] += 1;
            try w.print("DISAGREE [{s}] vars={d} nodes={d}: native={s} truth={s} ttL={b:0>16} ttR={b:0>16}\n", .{ class_names[cls], num_vars, res.nodes, if (res.equiv) "equiv" else "diff", if (truth_equiv) "equiv" else "diff", tt_l, tt_r });
        }
    }

    try w.print("\ncases audited (full path)   : {d}\n", .{total});
    try w.print("  equivalent / different    : {d} / {d}\n", .{ equiv_cases, total - equiv_cases });
    try w.print("  decided structurally      : {d} (miter collapsed by strash/AIG rules)\n", .{structural_cnt});
    try w.print("  decided by DPLL           : {d}\n", .{dpll_cnt});
    try w.print("  oversize skipped (sim-only): {d} (node cap {d}, naive DPLL is 2^nodes)\n", .{ oversize_cnt, node_cap });
    for (class_names, 0..) |cn, i| {
        try w.print("  class {s:<18}: {d} cases, {d} disagreements\n", .{ cn, per_class_total[i], per_class_dis[i] });
    }
    try w.print("sim-layer mismatches        : {d} (AIG getSimValue vs independent eval)\n", .{sim_mismatch});
    try w.print("DISAGREEMENTS (verdict)     : {d}\n", .{disagreements});
    const denom = if (total == 0) 1 else total;
    try w.print("agreement rate              : {d}/{d} = {d:.4}%\n", .{ total - disagreements, total, 100.0 * @as(f64, @floatFromInt(total - disagreements)) / @as(f64, @floatFromInt(denom)) });
    try w.print("wall time                   : {d} ms\n", .{timer.read() / std.time.ns_per_ms});
    try w.print("VERDICT: {s}\n", .{if (disagreements == 0 and sim_mismatch == 0) "PASS — instruments agree" else "FAIL — instrument bug, see disagreements above"});
}
