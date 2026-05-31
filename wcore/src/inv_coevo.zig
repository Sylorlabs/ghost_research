//! Minimal coevolution with transfer (RESEARCH §23) — the frontier §22 pointed at.
//!
//! §22 named the deepest wall: the NOVELTY↔USEFULNESS tension. One fitness can reward
//! "be different" OR "be useful", not both. POET's answer is to COUPLE them — coevolve a
//! population of TASKS alongside solvers, with cross-task TRANSFER, so "useful" keeps
//! moving (each solver is optimised on its own task = useful; the task population supplies
//! the diversity = open-ended).
//!
//! We test the sharpest, most falsifiable consequence for our substrate: does TRANSFER
//! let coevolution ASSEMBLE a conjunction that direct search could not? The per-key
//! counter (`pk_add`, a 3-op read-modify-write) is exactly the mechanism §20's `fuse`
//! phase NEVER found in 16M evals, cold or curriculum-seeded. The bridge hypothesis: a
//! *different* per-key task (`pk_xor`, the same RMW shape but no constant needed) is
//! easier to discover; once found, transferring its solver to `pk_add` is ~1 mutation
//! away. If coevolution solves `pk_add` where INDEPENDENT search can't, transfer
//! demonstrably bridges a conjunction gap — a real POET win. If not, coevolution doesn't
//! escape the reliability wall either. Both are honest results.

const std = @import("std");
const alien = @import("inv_alien.zig");

const V: usize = alien.CANON_BASE; // symbol alphabet and output base (4)

pub const TaskKind = enum {
    g_xor, // global: t[i] = XOR of symbols 0..i           (1-op accumulator — easy)
    g_add, // global: t[i] = SUM of symbols 0..i  (mod V)  (1-op accumulator — easy)
    pk_xor, // per-key: t[i] = XOR of occurrences of sym[i] (RMW, no constant — hard)
    pk_add, // per-key: t[i] = COUNT of sym[i] so far (mod V)(RMW + constant — hardest; fuse never found it)
    pub fn name(k: TaskKind) []const u8 {
        return switch (k) {
            .g_xor => "g_xor (global parity)",
            .g_add => "g_add (global sum)   ",
            .pk_xor => "pk_xor (per-key xor) ",
            .pk_add => "pk_add (per-key count)",
        };
    }
};

fn target(k: TaskKind, syms: []const u8, out: []u8) void {
    const base: u8 = @intCast(V);
    switch (k) {
        .g_xor => {
            var acc: u8 = 0;
            for (syms, 0..) |s, i| {
                acc ^= s;
                out[i] = acc % base;
            }
        },
        .g_add => {
            var acc: usize = 0;
            for (syms, 0..) |s, i| {
                acc += s;
                out[i] = @intCast(acc % V);
            }
        },
        .pk_xor => {
            var mem = [_]u8{0} ** V;
            for (syms, 0..) |s, i| {
                mem[s] ^= s;
                out[i] = mem[s] % base;
            }
        },
        .pk_add => {
            var mem = [_]usize{0} ** V;
            for (syms, 0..) |s, i| {
                mem[s] += 1;
                out[i] = @intCast(mem[s] % V);
            }
        },
    }
}

/// Per-position agreement of a solver program with the task's target, over random
/// symbol streams. THE task fitness — produced only by execution.
pub fn taskFitness(prog: *const alien.Program, k: TaskKind, L: usize, n_seq: usize, seed: u64) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var tgt: [256]u8 = undefined;
    var got: [256]u8 = undefined;
    var correct: usize = 0;
    var total: usize = 0;
    for (0..n_seq) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        target(k, syms[0..L], tgt[0..L]);
        alien.runStream(prog, syms[0..L], got[0..L]);
        for (0..L) |i| {
            total += 1;
            if (got[i] == tgt[i]) correct += 1;
        }
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(total));
}

// ---- hand-written reference solvers (for the kill-test) --------------------

pub fn refSolver(k: TaskKind) alien.Program {
    var p = alien.Program{};
    switch (k) {
        .g_xor => p.step.appendAssumeCapacity(.{ .op = .a_xor, .a = 3, .b = 0, .out = 3 }),
        .g_add => p.step.appendAssumeCapacity(.{ .op = .a_add, .a = 3, .b = 0, .out = 3 }),
        .pk_xor => {
            p.step.appendAssumeCapacity(.{ .op = .a_load, .a = 0, .out = 3 });
            p.step.appendAssumeCapacity(.{ .op = .a_xor, .a = 3, .b = 0, .out = 3 });
            p.step.appendAssumeCapacity(.{ .op = .a_store, .a = 0, .b = 3 });
        },
        .pk_add => {
            p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 6, .imm = 1 });
            p.step.appendAssumeCapacity(.{ .op = .a_load, .a = 0, .out = 3 });
            p.step.appendAssumeCapacity(.{ .op = .a_add, .a = 3, .b = 6, .out = 3 });
            p.step.appendAssumeCapacity(.{ .op = .a_store, .a = 0, .b = 3 });
        },
    }
    return p;
}

// ---- evolution on a single task (with optional transfer seed) --------------

pub const Result = struct { best: alien.Program, fit: f64, ett: ?usize };

pub fn evolveTask(
    al: std.mem.Allocator,
    rng: std.Random,
    k: TaskKind,
    max_evals: usize,
    active_regs: usize,
    seed: u64,
    seed_prog: ?*const alien.Program,
) !Result {
    const Indiv = struct { prog: alien.Program, fit: f64 };
    const pop_size: usize = 400;
    const pop = try al.alloc(Indiv, pop_size);
    defer al.free(pop);
    var sp = alien.Params{ .active_regs = active_regs, .mem_bias = 0.25 };
    const lambda: f64 = 1e-4;
    const fit_L: usize = 32;
    const fit_n: usize = 12;

    var best: alien.Program = .{};
    var best_fit: f64 = -1;
    var best_adj: f64 = -1e9;
    var evals: usize = 0;
    var ett: ?usize = null;

    for (pop, 0..) |*ind, i| {
        if (seed_prog != null and i < pop_size / 4) {
            ind.prog = seed_prog.?.*;
            if (i > 0) alien.mutate(rng, &ind.prog, &sp);
        } else ind.prog = alien.randProg(rng, &sp);
        const raw = taskFitness(&ind.prog, k, fit_L, fit_n, seed);
        ind.fit = raw - lambda * @as(f64, @floatFromInt(ind.prog.len()));
        evals += 1;
        if (ind.fit > best_adj) {
            best_adj = ind.fit;
            best_fit = raw;
            best = ind.prog;
        }
        if (ett == null and raw >= 0.95) ett = evals;
    }
    var oldest: usize = 0;
    while (evals < max_evals) {
        var child: alien.Program = undefined;
        if (rng.float(f64) < 0.18) {
            child = alien.randProg(rng, &sp);
        } else {
            var par = rng.uintLessThan(usize, pop_size);
            for (0..7) |_| {
                const c = rng.uintLessThan(usize, pop_size);
                if (pop[c].fit > pop[par].fit) par = c;
            }
            child = pop[par].prog;
            alien.mutate(rng, &child, &sp);
        }
        const raw = taskFitness(&child, k, fit_L, fit_n, seed);
        const adj = raw - lambda * @as(f64, @floatFromInt(child.len()));
        evals += 1;
        pop[oldest] = .{ .prog = child, .fit = adj };
        oldest = (oldest + 1) % pop_size;
        if (adj > best_adj) {
            best_adj = adj;
            best_fit = raw;
            best = child;
        }
        if (ett == null and raw >= 0.95) ett = evals;
    }
    return .{ .best = best, .fit = best_fit, .ett = ett };
}

// ===========================================================================
// OPEN-ENDED composition ladder (§24): tasks are GENERATED by composing stages,
// so the task space is unbounded. Difficulty = composition depth. The question:
// does mutation+transfer ratchet up depth, and do deep-composition solvers become
// UNRECOGNISABLE (novel by the certifier, not decomposable into known atoms)?
// ===========================================================================

pub const Stage = enum(u8) { st_gxor, st_gadd, st_pkxor, st_pkadd, st_shift };
pub const MAX_DEPTH: usize = 8;
pub const Genome = std.BoundedArray(Stage, MAX_DEPTH);

fn applyStage(stage: Stage, in: []const u8, out: []u8) void {
    const base: u8 = @intCast(V);
    switch (stage) {
        .st_gxor => {
            var acc: u8 = 0;
            for (in, 0..) |s, i| {
                acc ^= s;
                out[i] = acc % base;
            }
        },
        .st_gadd => {
            var acc: usize = 0;
            for (in, 0..) |s, i| {
                acc += s;
                out[i] = @intCast(acc % V);
            }
        },
        .st_pkxor => {
            var mem = [_]u8{0} ** V;
            for (in, 0..) |s, i| {
                mem[s % V] ^= s;
                out[i] = mem[s % V] % base;
            }
        },
        .st_pkadd => {
            var mem = [_]usize{0} ** V;
            for (in, 0..) |s, i| {
                mem[s % V] += 1;
                out[i] = @intCast(mem[s % V] % V);
            }
        },
        .st_shift => {
            var prev: u8 = 0;
            for (in, 0..) |s, i| {
                out[i] = prev;
                prev = s;
            }
        },
    }
}

/// Compose the genome's stages left-to-right over the input stream.
pub fn composedTarget(genome: []const Stage, syms: []const u8, out: []u8) void {
    var a: [256]u8 = undefined;
    var b: [256]u8 = undefined;
    const L = syms.len;
    @memcpy(a[0..L], syms);
    var cur: []u8 = a[0..L];
    var nxt: []u8 = b[0..L];
    for (genome) |stage| {
        applyStage(stage, cur, nxt);
        const t = cur;
        cur = nxt;
        nxt = t;
    }
    @memcpy(out, cur);
}

pub fn taskFitnessComposed(prog: *const alien.Program, genome: []const Stage, L: usize, n_seq: usize, seed: u64) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var tgt: [256]u8 = undefined;
    var got: [256]u8 = undefined;
    var correct: usize = 0;
    var total: usize = 0;
    for (0..n_seq) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        composedTarget(genome, syms[0..L], tgt[0..L]);
        alien.runStream(prog, syms[0..L], got[0..L]);
        for (0..L) |i| {
            total += 1;
            if (got[i] == tgt[i]) correct += 1;
        }
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(total));
}

/// Evolve a solver for a COMPOSED task (genome), optionally transfer-seeded.
pub fn evolveComposed(
    al: std.mem.Allocator,
    rng: std.Random,
    genome: []const Stage,
    max_evals: usize,
    regs: usize,
    seed: u64,
    seed_prog: ?*const alien.Program,
) !Result {
    const Indiv = struct { prog: alien.Program, fit: f64 };
    const pop_size: usize = 400;
    const pop = try al.alloc(Indiv, pop_size);
    defer al.free(pop);
    var sp = alien.Params{ .active_regs = regs, .mem_bias = 0.25 };
    const lambda: f64 = 1e-4;
    const fit_L: usize = 32;
    const fit_n: usize = 10;

    var best: alien.Program = .{};
    var best_fit: f64 = -1;
    var best_adj: f64 = -1e9;
    var evals: usize = 0;

    for (pop, 0..) |*ind, i| {
        if (seed_prog != null and i < pop_size / 3) {
            ind.prog = seed_prog.?.*;
            if (i > 0) alien.mutate(rng, &ind.prog, &sp);
        } else ind.prog = alien.randProg(rng, &sp);
        const raw = taskFitnessComposed(&ind.prog, genome, fit_L, fit_n, seed);
        ind.fit = raw - lambda * @as(f64, @floatFromInt(ind.prog.len()));
        evals += 1;
        if (ind.fit > best_adj) {
            best_adj = ind.fit;
            best_fit = raw;
            best = ind.prog;
        }
    }
    var oldest: usize = 0;
    while (evals < max_evals) {
        var child: alien.Program = undefined;
        if (rng.float(f64) < 0.18) {
            child = alien.randProg(rng, &sp);
        } else {
            var par = rng.uintLessThan(usize, pop_size);
            for (0..7) |_| {
                const c = rng.uintLessThan(usize, pop_size);
                if (pop[c].fit > pop[par].fit) par = c;
            }
            child = pop[par].prog;
            alien.mutate(rng, &child, &sp);
        }
        const raw = taskFitnessComposed(&child, genome, fit_L, fit_n, seed);
        const adj = raw - lambda * @as(f64, @floatFromInt(child.len()));
        evals += 1;
        pop[oldest] = .{ .prog = child, .fit = adj };
        oldest = (oldest + 1) % pop_size;
        if (adj > best_adj) {
            best_adj = adj;
            best_fit = raw;
            best = child;
        }
    }
    return .{ .best = best, .fit = best_fit, .ett = null };
}

pub fn mutateGenome(rng: std.Random, g: Genome) Genome {
    var ng = g;
    const r = rng.float(f64);
    const nstage = @typeInfo(Stage).@"enum".fields.len;
    if (r < 0.6 and ng.len < MAX_DEPTH) {
        ng.appendAssumeCapacity(@enumFromInt(rng.uintLessThan(usize, nstage))); // deepen
    } else if (r < 0.8 and ng.len > 0) {
        ng.slice()[rng.uintLessThan(usize, ng.len)] = @enumFromInt(rng.uintLessThan(usize, nstage)); // change
    } else if (ng.len > 1) {
        _ = ng.orderedRemove(rng.uintLessThan(usize, ng.len)); // shorten
    } else if (ng.len < MAX_DEPTH) {
        ng.appendAssumeCapacity(@enumFromInt(rng.uintLessThan(usize, nstage)));
    }
    return ng;
}

pub fn genomeEql(a: []const Stage, b: []const Stage) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (x != y) return false;
    return true;
}
pub fn stageChar(s: Stage) u8 {
    return switch (s) {
        .st_gxor => 'X',
        .st_gadd => 'A',
        .st_pkxor => 'k',
        .st_pkadd => 'c',
        .st_shift => '>',
    };
}

test "composed target: a single pk_add stage equals the standalone counting target" {
    var syms = [_]u8{ 1, 2, 1, 3, 1, 2 };
    var a: [6]u8 = undefined;
    var b: [6]u8 = undefined;
    composedTarget(&.{.st_pkadd}, &syms, &a);
    target(.pk_add, &syms, &b);
    try std.testing.expectEqualSlices(u8, &b, &a);
    // composition is non-trivial: a depth-2 genome differs from either stage alone
    var c2: [6]u8 = undefined;
    composedTarget(&.{ .st_pkadd, .st_gxor }, &syms, &c2);
    try std.testing.expect(!std.mem.eql(u8, &c2, &a));
}

test "coevo tasks: reference solvers solve their own task; g-solvers fail the per-key ones" {
    const L: usize = 40;
    inline for ([_]TaskKind{ .g_xor, .g_add, .pk_xor, .pk_add }) |k| {
        const ref = refSolver(k);
        try std.testing.expect(taskFitness(&ref, k, L, 32, 0xC0E0) > 0.95);
    }
    // a global accumulator cannot do per-key counting (needs addressed memory)
    const g = refSolver(.g_add);
    try std.testing.expect(taskFitness(&g, .pk_add, L, 32, 0xC0E0) < 0.65);
}
