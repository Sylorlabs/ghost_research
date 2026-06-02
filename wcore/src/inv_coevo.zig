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

// ===========================================================================
// The IRREDUCIBILITY TEST (§25) — the instrument the whole arc was missing.
//
// "Novel by the certifier" only ever meant "not identical to any single known atom",
// which any COMPOSITION satisfies. To certify a genuine NEW ATOM we need the opposite
// test: is a solver's BEHAVIOUR reproducible by a composition of KNOWN atoms? The known
// atoms here are exactly the stage set. A solver is REDUCIBLE if some stage-genome (up to
// a bounded depth) matches its input→output behaviour on a battery of streams; if none
// does, it is IRREDUCIBLE *relative to the declared atom set* — it does something no
// bounded composition of the known atoms can. That is the precondition for any honest
// novelty claim, and (unlike the fingerprint certifier) it can actually DETECT novelty.
// ===========================================================================

/// The agreement threshold at which a solver's behaviour counts as "the same function"
/// as a composed genome. 0.95 = the solve bar: tolerant of an evolved solver that isn't
/// bit-exact on held-out streams, but far above the ≤~0.5 a genuinely different function
/// scores (chance is 1/V = 0.25), so a true outsider is never matched by accident.
pub const MATCH_THRESHOLD: f64 = 0.95;

/// Does `prog`'s output agree with the composed `genome` target ≥ MATCH_THRESHOLD on `n`
/// random streams?
pub fn behaviorMatches(prog: *const alien.Program, genome: []const Stage, n: usize, L: usize, seed: u64) bool {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var tgt: [256]u8 = undefined;
    var got: [256]u8 = undefined;
    var agree: usize = 0;
    var total: usize = 0;
    for (0..n) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        composedTarget(genome, syms[0..L], tgt[0..L]);
        alien.runStream(prog, syms[0..L], got[0..L]);
        for (0..L) |i| {
            total += 1;
            if (got[i] == tgt[i]) agree += 1;
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total)) >= MATCH_THRESHOLD;
}

/// Instrument audit: EXACT behavioural equality (every symbol must match), with
/// caller-set sample budget. behaviorMatches uses MATCH_THRESHOLD=0.95, so it calls
/// a 95%-approximation a "match" -- which could mask a behaviour that is NOT exactly
/// a composition. This requires 100% agreement over n*L symbols.
pub fn behaviorMatchesExact(prog: *const alien.Program, genome: []const Stage, n: usize, L: usize, seed: u64) bool {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var tgt: [256]u8 = undefined;
    var got: [256]u8 = undefined;
    const ll = @min(L, 256);
    for (0..n) |_| {
        for (0..ll) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        composedTarget(genome, syms[0..ll], tgt[0..ll]);
        alien.runStream(prog, syms[0..ll], got[0..ll]);
        for (0..ll) |i| if (got[i] != tgt[i]) return false; // any mismatch => NOT equal
    }
    return true;
}

/// Exact-matching exhaustive reduction search (the audit twin of `reducible`).
pub fn reducibleExact(prog: *const alien.Program, max_depth: usize, seed: u64, n: usize, L: usize) ?Genome {
    const nstage = @typeInfo(Stage).@"enum".fields.len;
    var d: usize = 1;
    while (d <= max_depth) : (d += 1) {
        var total: usize = 1;
        for (0..d) |_| total *= nstage;
        var idx: usize = 0;
        while (idx < total) : (idx += 1) {
            var g = Genome{};
            var x = idx;
            for (0..d) |_| {
                g.appendAssumeCapacity(@enumFromInt(x % nstage));
                x /= nstage;
            }
            if (behaviorMatchesExact(prog, g.slice(), n, L, seed)) return g;
        }
    }
    return null;
}

/// Search every stage-genome up to `max_depth` for one that reproduces `prog`'s
/// behaviour. Returns the (shortest) matching genome (REDUCIBLE) or null (IRREDUCIBLE
/// relative to the stage atom set). Exhaustive: 5 + 25 + … stage-strings.
pub fn reducible(prog: *const alien.Program, max_depth: usize, seed: u64) ?Genome {
    const nstage = @typeInfo(Stage).@"enum".fields.len;
    var d: usize = 1;
    while (d <= max_depth) : (d += 1) {
        var total: usize = 1;
        for (0..d) |_| total *= nstage;
        var idx: usize = 0;
        while (idx < total) : (idx += 1) {
            var g = Genome{};
            var x = idx;
            for (0..d) |_| {
                g.appendAssumeCapacity(@enumFromInt(x % nstage));
                x /= nstage;
            }
            if (behaviorMatches(prog, g.slice(), 12, 32, seed)) return g;
        }
    }
    return null;
}

/// Distinct-symbol count (a global SET cardinality) — provably NOT a composition of the
/// stage atoms (which are per-key / global linear reductions and a delay). The kill-test
/// behaviour that the irreducibility instrument MUST flag irreducible.
pub fn distinctCountTarget(syms: []const u8, out: []u8) void {
    var seen = [_]bool{false} ** V;
    var cnt: usize = 0;
    for (syms, 0..) |s, i| {
        if (!seen[s % V]) {
            seen[s % V] = true;
            cnt += 1;
        }
        out[i] = @intCast(cnt % V);
    }
}

/// A hand-written program that computes distinct-symbol count, via memory as seen-flags:
/// seen=mem[sym]; mem[sym]=1; counter += (seen XOR 1); output counter.
pub fn distinctCountProg() alien.Program {
    var p = alien.Program{};
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 6, .imm = 1 }); // r6 = 1
    p.step.appendAssumeCapacity(.{ .op = .a_load, .a = 0, .out = 8 }); // r8 = mem[sym]
    p.step.appendAssumeCapacity(.{ .op = .a_store, .a = 0, .b = 6 }); // mem[sym] = 1
    p.step.appendAssumeCapacity(.{ .op = .a_xor, .a = 8, .b = 6, .out = 8 }); // r8 = seen XOR 1
    p.step.appendAssumeCapacity(.{ .op = .a_add, .a = 7, .b = 8, .out = 7 }); // r7 += r8
    p.step.appendAssumeCapacity(.{ .op = .a_mov, .a = 7, .out = 3 }); // r3 = r7 (output)
    return p;
}

test "IRREDUCIBILITY instrument kill-tests: reducible catches compositions, flags a true outsider" {
    const seed: u64 = 0x133D;
    // the distinct-count program actually computes distinct count
    var syms = [_]u8{ 0, 1, 1, 2, 0, 3, 2 };
    var a: [7]u8 = undefined;
    var b: [7]u8 = undefined;
    distinctCountTarget(&syms, &a);
    alien.runStream(&distinctCountProg(), &syms, &b);
    try std.testing.expectEqualSlices(u8, &a, &b);

    // a known atom REDUCES (the RMW counter == the pk_add stage)
    const counter = refSolver(.pk_add);
    try std.testing.expect(reducible(&counter, 4, seed) != null);
    // a known atom REDUCES (the global parity == the g_xor stage)
    const par = refSolver(.g_xor);
    try std.testing.expect(reducible(&par, 4, seed) != null);
    // distinct-count is IRREDUCIBLE relative to the stage atom set (the real kill-test:
    // the instrument can DETECT a behaviour outside the known atoms' closure)
    try std.testing.expect(reducible(&distinctCountProg(), 4, seed) == null);
}

/// Greedily remove instructions that don't drop accuracy below the solve bar — the
/// minimal program for a composed task. Used to compare arrangements FAIRLY by length
/// (raw evolved programs carry junk; minimisation strips it so the length is the real cost).
pub fn minimizeForTask(prog: alien.Program, genome: []const Stage, seed: u64) alien.Program {
    var p = prog;
    var improved = true;
    while (improved) {
        improved = false;
        var i: usize = 0;
        while (i < p.step.len) {
            var q = p;
            _ = q.step.orderedRemove(i);
            if (taskFitnessComposed(&q, genome, 40, 20, seed) >= MATCH_THRESHOLD) {
                p = q;
                improved = true;
            } else i += 1;
        }
        i = 0;
        while (i < p.setup.len) {
            var q = p;
            _ = q.setup.orderedRemove(i);
            if (taskFitnessComposed(&q, genome, 40, 20, seed) >= MATCH_THRESHOLD) {
                p = q;
                improved = true;
            } else i += 1;
        }
    }
    return p;
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
