//! Regularized (aging) evolution over the primitive substrate (§4.6).
//!
//! The proposer is search + (in Phase 2) the discovered library — NEVER a learned
//! model (FORBIDDEN MOVE #1). Steering comes only from fitness + MDL + the library.
//! We keep a population, tournament-select a parent, mutate it (insert / delete /
//! modify an op, or call a library macro), evaluate the child by EXECUTION, and
//! replace the OLDEST individual. The random-search baseline samples programs
//! i.i.d.; comparing evals-to-target tells us whether evolution actually steers.

const std = @import("std");
const sub = @import("inv_substrate.zig");
const tasks = @import("inv_tasks.zig");
const Instr = sub.Instr;
const Op = sub.Op;
const Program = sub.Program;
const Macro = sub.Macro;

pub const Params = struct {
    pop_size: usize = 100,
    tournament: usize = 10,
    max_evals: usize = 30_000,
    target: f64 = 0.95,
    lambda: f64 = 0.003, // MDL weight (§4.4)
    immigrant_rate: f64 = 0.05, // fraction of new individuals that are fresh-random
    mutations_per_child: usize = 1, // how many edits per offspring
    // init program length ranges
    init_setup_max: usize = 3,
    init_predict_max: usize = 8,
    init_learn_max: usize = 8,
};

pub const Result = struct {
    best: Program,
    best_perf: f64,
    best_adj: f64,
    evals_to_target: ?usize, // null if target never reached
    total_evals: usize,
    lib_calls_in_best: usize, // how many library macros the champion invokes
};

// ---- random sampling of programs/instructions ------------------------------

const N_OPS_NO_CALL: usize = @intFromEnum(Op.call); // ops before .call in the enum

fn randImm(rng: std.Random) f64 {
    // a spread that covers learning rates, small weights, and unit-ish constants
    const choices = [_]f64{ -2, -1, -0.5, -0.1, -0.05, 0.01, 0.05, 0.1, 0.5, 1, 2 };
    if (rng.boolean()) return choices[rng.uintLessThan(usize, choices.len)];
    return (rng.float(f64) - 0.5) * 4.0;
}

fn randOp(rng: std.Random, n_lib: usize) Op {
    // when a library exists, give `call` a real (non-trivial) share of the mass
    if (n_lib > 0 and rng.uintLessThan(usize, 8) == 0) return .call;
    return @enumFromInt(rng.uintLessThan(usize, N_OPS_NO_CALL));
}

fn randInstr(rng: std.Random, n_lib: usize) Instr {
    const op = randOp(rng, n_lib);
    var ins = Instr{ .op = op, .a = rng.int(u8), .b = rng.int(u8), .out = rng.int(u8) };
    if (op == .s_set) {
        ins.imm = randImm(rng);
    } else if (op == .call) {
        ins.imm = @floatFromInt(rng.uintLessThan(usize, n_lib));
        ins.c = rng.int(u8); // extra params for macros that take >2 args
        ins.d = rng.int(u8);
    }
    return ins;
}

fn randComponent(rng: std.Random, n_lib: usize, max_len: usize) sub.Component {
    var c = sub.Component{};
    const n = rng.uintLessThan(usize, max_len + 1);
    for (0..n) |_| c.appendAssumeCapacity(randInstr(rng, n_lib));
    return c;
}

pub fn randProgram(rng: std.Random, n_lib: usize, p: Params) Program {
    return .{
        .setup = randComponent(rng, n_lib, p.init_setup_max),
        .predict = randComponent(rng, n_lib, p.init_predict_max),
        .learn = randComponent(rng, n_lib, p.init_learn_max),
    };
}

// ---- mutation --------------------------------------------------------------

fn pickComponent(rng: std.Random, prog: *Program) *sub.Component {
    return switch (rng.uintLessThan(usize, 3)) {
        0 => &prog.setup,
        1 => &prog.predict,
        else => &prog.learn,
    };
}

/// One mutation: insert, delete, or modify a single instruction (§4.6).
pub fn mutate(rng: std.Random, prog: *Program, n_lib: usize) void {
    const choice = rng.uintLessThan(usize, 3);
    const c = pickComponent(rng, prog);
    switch (choice) {
        0 => { // insert at a random position
            if (c.len >= sub.MAX_INSTR) return;
            const pos = rng.uintLessThan(usize, c.len + 1);
            c.insert(pos, randInstr(rng, n_lib)) catch {};
        },
        1 => { // delete
            if (c.len == 0) return;
            _ = c.orderedRemove(rng.uintLessThan(usize, c.len));
        },
        else => { // modify one field of one instruction
            if (c.len == 0) {
                c.appendAssumeCapacity(randInstr(rng, n_lib));
                return;
            }
            const idx = rng.uintLessThan(usize, c.len);
            const ins = &c.slice()[idx];
            switch (rng.uintLessThan(usize, 6)) {
                0 => {
                    ins.op = randOp(rng, n_lib);
                    if (ins.op == .call) ins.imm = @floatFromInt(rng.uintLessThan(usize, @max(1, n_lib)));
                },
                1 => ins.a = rng.int(u8),
                2 => ins.b = rng.int(u8),
                3 => ins.out = rng.int(u8),
                4 => {
                    // the extra macro params (only meaningful for .call)
                    ins.c = rng.int(u8);
                    ins.d = rng.int(u8);
                },
                else => {
                    if (ins.op == .s_set) {
                        // perturb existing constant (gradient-friendly) or resample
                        if (rng.boolean()) ins.imm += (rng.float(f64) - 0.5) * 0.2 else ins.imm = randImm(rng);
                    } else if (ins.op == .call) {
                        ins.imm = @floatFromInt(rng.uintLessThan(usize, @max(1, n_lib)));
                    } else ins.imm = randImm(rng);
                },
            }
        },
    }
}

// ---- the two searches ------------------------------------------------------

const Indiv = struct { prog: Program, perf: f64, adj: f64 };

fn countCalls(prog: *const Program) usize {
    var n: usize = 0;
    for (prog.predict.slice()) |ins| {
        if (ins.op == .call) n += 1;
    }
    for (prog.learn.slice()) |ins| {
        if (ins.op == .call) n += 1;
    }
    return n;
}

pub fn runEvolution(
    al: std.mem.Allocator,
    rng: std.Random,
    task: tasks.Task,
    cfg: tasks.Config,
    p: Params,
    lib: []const Macro,
    elites_out: []Program, // filled with the top-N final-population programs (the library corpus)
) !Result {
    const pop = try al.alloc(Indiv, p.pop_size);
    defer al.free(pop);

    var best_perf: f64 = -1;
    var best_adj: f64 = -1e9;
    var best: Program = .{};
    var evals: usize = 0;
    var evals_to_target: ?usize = null;

    const consider = struct {
        fn f(prog: *const Program, perf: f64, adj: f64, bp: *f64, ba: *f64, bb: *Program) void {
            if (adj > ba.*) {
                ba.* = adj;
                bp.* = perf;
                bb.* = prog.*;
            }
        }
    }.f;

    // seed the population with random programs
    for (pop) |*ind| {
        ind.prog = randProgram(rng, lib.len, p);
        ind.perf = tasks.evaluate(&ind.prog, lib, task, cfg);
        ind.adj = tasks.adjusted(ind.perf, ind.prog.len(), p.lambda);
        evals += 1;
        consider(&ind.prog, ind.perf, ind.adj, &best_perf, &best_adj, &best);
        if (evals_to_target == null and ind.perf >= p.target) evals_to_target = evals;
    }

    var oldest: usize = 0;
    while (evals < p.max_evals) {
        var child: Program = undefined;
        if (rng.float(f64) < p.immigrant_rate) {
            // fresh blood: keeps diversity high so the population doesn't collapse
            // into a deceptive local optimum and abandon the path to the gate.
            child = randProgram(rng, lib.len, p);
        } else {
            // tournament selection + mutation
            var parent: usize = rng.uintLessThan(usize, p.pop_size);
            for (1..p.tournament) |_| {
                const c = rng.uintLessThan(usize, p.pop_size);
                if (pop[c].adj > pop[parent].adj) parent = c;
            }
            child = pop[parent].prog;
            for (0..p.mutations_per_child) |_| mutate(rng, &child, lib.len);
        }
        const perf = tasks.evaluate(&child, lib, task, cfg);
        const adj = tasks.adjusted(perf, child.len(), p.lambda);
        evals += 1;

        pop[oldest] = .{ .prog = child, .perf = perf, .adj = adj };
        oldest = (oldest + 1) % p.pop_size;

        consider(&child, perf, adj, &best_perf, &best_adj, &best);
        if (evals_to_target == null and perf >= p.target) evals_to_target = evals;
    }

    // expose the top elites as the corpus the compounding library extracts from
    if (elites_out.len > 0) {
        const order = try al.alloc(usize, p.pop_size);
        defer al.free(order);
        for (order, 0..) |*o, i| o.* = i;
        std.sort.insertion(usize, order, pop, struct {
            fn lt(pp: []Indiv, x: usize, y: usize) bool {
                return pp[x].adj > pp[y].adj;
            }
        }.lt);
        const n = @min(elites_out.len, p.pop_size);
        for (0..n) |i| elites_out[i] = pop[order[i]].prog;
    }

    return .{
        .best = best,
        .best_perf = best_perf,
        .best_adj = best_adj,
        .evals_to_target = evals_to_target,
        .total_evals = evals,
        .lib_calls_in_best = countCalls(&best),
    };
}

pub fn runRandomSearch(
    rng: std.Random,
    task: tasks.Task,
    cfg: tasks.Config,
    p: Params,
    lib: []const Macro,
) Result {
    var best_perf: f64 = -1;
    var best_adj: f64 = -1e9;
    var best: Program = .{};
    var evals_to_target: ?usize = null;

    var evals: usize = 0;
    while (evals < p.max_evals) {
        const prog = randProgram(rng, lib.len, p);
        const perf = tasks.evaluate(&prog, lib, task, cfg);
        const adj = tasks.adjusted(perf, prog.len(), p.lambda);
        evals += 1;
        if (adj > best_adj) {
            best_adj = adj;
            best_perf = perf;
            best = prog;
        }
        if (evals_to_target == null and perf >= p.target) evals_to_target = evals;
    }
    return .{
        .best = best,
        .best_perf = best_perf,
        .best_adj = best_adj,
        .evals_to_target = evals_to_target,
        .total_evals = evals,
        .lib_calls_in_best = countCalls(&best),
    };
}

// ---- tests -----------------------------------------------------------------

test "evolution runs end-to-end and returns a valid champion (smoke test)" {
    // The full solve takes ~10^5 evals (gradient-free needle) — too slow for a
    // debug-mode unit test, so this only checks the loop runs, tracks a champion,
    // and never produces an invalid/NaN program. The actual >>random solve is
    // demonstrated by `zig build run-invent -- phase1` and documented in TESTING.md.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();

    var prng = std.Random.DefaultPrng.init(0xC0FFEE);
    const task = tasks.gate(2, 0, 1);
    const cfg = tasks.Config{ .n_train = 40, .n_test = 60, .n_seeds = 2 };
    const p = Params{ .max_evals = 3000, .pop_size = 80 };

    const r = try runEvolution(al, prng.random(), task, cfg, p, &.{}, &.{});
    try std.testing.expect(r.best_perf >= 0.0 and r.best_perf <= 1.0);
    try std.testing.expectEqual(@as(usize, 3000), r.total_evals);
}

test "mutation never produces an out-of-bounds component" {
    var prng = std.Random.DefaultPrng.init(7);
    const rng = prng.random();
    var prog = randProgram(rng, 0, .{});
    for (0..2000) |_| {
        mutate(rng, &prog, 0);
        try std.testing.expect(prog.setup.len <= sub.MAX_INSTR);
        try std.testing.expect(prog.predict.len <= sub.MAX_INSTR);
        try std.testing.expect(prog.learn.len <= sub.MAX_INSTR);
    }
}
