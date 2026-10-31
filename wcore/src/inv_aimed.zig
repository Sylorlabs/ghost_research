//! AIMED FORGE — does coupling novelty pressure to the frontier pay? (round 2026-07-10b)
//!
//! Direct follow-up to A1–A6 (`inv_iterate.zig`, `docs/research/a1a6_iterated_promotion.md`):
//! that experiment found iterated atom promotion barely pays. Corrected held-out
//! reachability moved 3/18 -> 4/18 over 10 rounds because the novelty forge kept
//! re-drawing its OWN sampling distribution (6/8 raw flips were SELF matches: a
//! promoted atom happened to equal a decoy target) and NEVER touched the structured
//! family (distinct-count, hash-table, union + their compositions). Its verdict:
//! "the bottleneck is coupling the forge's novelty pressure to the frontier you
//! care about." This file builds that coupling and measures whether it works.
//!
//! ---- design -----------------------------------------------------------------
//!
//! F/E SPLIT (both fixed BEFORE round 1, disjoint, covering the same 18-target
//! battery as A1-A6 so results are apples-to-apples):
//!   F (FRONTIER, aimed at)      = distinct-count-centric family: distinct, hashtbl,
//!     union, and 6 compositions built from distinct-count + base atoms
//!     (dist->gxor, gadd->dist, dist->dist, shift->dist, shift->dist->gxor,
//!     dist->rmw). 9 targets.
//!   E (EVAL / transfer, NEVER aimed) = rmw-centric family: rmw, xorscan, and 4
//!     compositions built from rmw + base atoms (rmw->pkxor, pkadd->dist->pkadd,
//!     rmw->rmw->gadd, dist->shift->rmw), plus the 3 decoy sentinels (decoy1-3).
//!     9 targets. The fitness function never looks at any E target's behaviour —
//!     E measures whether atoms invented FOR F transfer to a family never aimed at
//!     (real generalisation), and the decoys inside E are reported separately as
//!     the SELF-match pathology sentinel (same role they played in A1-A6).
//!
//! THE AIMED FORGE: same population/generation/round/seed budget as inv_iterate
//! (pop 90, gens 45, 10 rounds, seeds 0xA70F / 0x5EED2 — the SAME seeds A1-A6
//! used). Selection (tournament) and archive admission are driven by a BLENDED
//! score: combined = (1-alpha)*novelty_normalised + alpha*residual, where residual
//! is the same behaviour-comparison primitive the certifier uses (fractional
//! per-symbol agreement over random streams, `chainAgreement`), computed between
//! the raw candidate program (depth 1) and every currently-UNSOLVED F target —
//! i.e. "does this candidate, alone, already resemble a hard target's behaviour?"
//! This is cheap (no depth-3 enumeration inside the inner loop) and gives a
//! continuous gradient toward F even for candidates that only partially match.
//! Three variants tried (all reported, per the round's "report whichever variants
//! you try" instruction):
//!   aimed_flat:     alpha fixed at 0.5 for every generation.
//!   aimed_annealed: alpha ramps 0 -> 0.85 across the 45 generations of EACH round
//!                   (pure novelty early = explore, residual-heavy late = exploit).
//!   aimed_promote:  aimed_flat's forge PLUS aim-coupled PROMOTION: among the
//!                   census's certified-irreducible candidates, promote the one
//!                   with the highest residual vs the unsolved F set (ties ->
//!                   shorter), instead of the shortest. Motivated by the
//!                   diagnosis probe (inv_aimed_probe.zig): for hashtbl/union the
//!                   residual landscape is fully climbable (hill-climb reaches
//!                   1.000), so if the first run's failure mode is the LENGTH-
//!                   sorted promotion gate discarding the F-proximal candidates
//!                   the pressure creates, this arm should convert them into
//!                   solves. Costs <=80 extra depth-1 residual comparisons per
//!                   round — negligible next to the census's exhaustive depth-3
//!                   certifications, so the budget stays comparable.
//! Everything else (archive cap, admission "alive"/"new-enough" gates, census over
//! the 80 shortest clean candidates, promotion of the shortest certified-
//! irreducible candidate, depth-3 certifier, A4-style reachability re-measurement,
//! A5/A6-style retro-reduction audit) is copied VERBATIM from `inv_iterate.zig`'s
//! protocol so the only experimental variable is the forge's selection pressure.
//!
//! ARM B (control) calls `open.search` UNCHANGED (pure novelty) with the identical
//! params/seeds inv_iterate used — this is a fresh re-run, not a re-quote of
//! yesterday's numbers, through the exact same harness so the F/E bucketing is
//! computed identically for both arms.
//!
//! This file is standalone: it imports inv_alien / inv_coevo / inv_open /
//! inv_atomforge / inv_frontier read-only (all pub) and PORTS the private
//! helpers it needs (chainAgreement, targetSolvable, the battery construction,
//! knnNovelty, minDistTo) from inv_iterate.zig / inv_open.zig, since Zig privacy
//! is file-scoped and those helpers are not `pub` there.
//!
//! Build:  zig build-exe -O ReleaseFast src/inv_aimed.zig -femit-bin=bin/inv_aimed
//! Run:    ./bin/inv_aimed <csv_path> [seed...] [--pop=N] [--gens=N] [--rounds=N]
//! Single-threaded. Deterministic given the seed list.

const std = @import("std");
const alien = @import("inv_alien.zig");
const coevo = @import("inv_coevo.zig");
const open = @import("inv_open.zig");
const forge = @import("inv_atomforge.zig");
const fr = @import("inv_frontier.zig");

const V: usize = alien.CANON_BASE;
const DEPTH: usize = forge.COMPOSE_DEPTH; // certifier / reachability depth budget = 3
const CENSUS_CAP: usize = 80;
const MATCH_SEQ: usize = 8;
const MATCH_L: usize = 28;
const RSEED: u64 = 0x0F17ED; // fixed reachability-check seed (same as inv_iterate)
const BATTERY_SEED: u64 = 0xBA77E71; // fixed battery-definition seed (same as inv_iterate)
const RESIDUAL_SEED: u64 = 0x2E51DA1; // fixed seed for the aimed forge's residual comparison

// =============================================================================
// Ported from inv_iterate.zig (private there): chain-vs-chain agreement and
// "is this hidden-lib chain composable from the search lib at depth <= D?".
// =============================================================================

fn chainAgreement(
    lib_a: []const alien.Program,
    a_idxs: []const usize,
    lib_b: []const alien.Program,
    b_idxs: []const usize,
    n: usize,
    L: usize,
    seed: u64,
) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var out_a: [256]u8 = undefined;
    var out_b: [256]u8 = undefined;
    var agree: usize = 0;
    var total: usize = 0;
    for (0..n) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        forge.applyChain(lib_a, a_idxs, syms[0..L], out_a[0..L]);
        forge.applyChain(lib_b, b_idxs, syms[0..L], out_b[0..L]);
        for (0..L) |i| {
            total += 1;
            if (out_a[i] == out_b[i]) agree += 1;
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total));
}

/// Is the hidden chain `t_idxs` (into `hidden`) composable from `lib` at depth <= max_depth?
fn targetSolvable(
    hidden: []const alien.Program,
    t_idxs: []const usize,
    lib: []const alien.Program,
    max_depth: usize,
    seed: u64,
    witness: []usize,
    wlen: *usize,
) bool {
    const n = lib.len;
    if (n == 0) return false;
    var d: usize = 1;
    while (d <= max_depth) : (d += 1) {
        var total: usize = 1;
        for (0..d) |_| total *= n;
        var idx: usize = 0;
        while (idx < total) : (idx += 1) {
            var idxs: [8]usize = undefined;
            var x = idx;
            for (0..d) |j| {
                idxs[j] = x % n;
                x /= n;
            }
            if (chainAgreement(hidden, t_idxs, lib, idxs[0..d], MATCH_SEQ, MATCH_L, seed) >= forge.MATCH_THRESHOLD) {
                for (0..d) |j| witness[j] = idxs[j];
                wlen.* = d;
                return true;
            }
        }
    }
    return false;
}

// =============================================================================
// Ported from inv_open.zig (private there): kNN novelty over a fingerprint set.
// =============================================================================

const MAXREF = 1024;

fn knnNovelty(fp: fr.Fingerprint, others: []const fr.Fingerprint, k: usize) f64 {
    var dists: [MAXREF]f64 = undefined;
    var n: usize = 0;
    for (others) |o| {
        if (n >= MAXREF) break;
        dists[n] = fr.fpDist(fp, o);
        n += 1;
    }
    const kk = @min(k, n);
    var sum: f64 = 0;
    for (0..kk) |i| {
        var mi = i;
        for (i + 1..n) |j| if (dists[j] < dists[mi]) {
            mi = j;
        };
        const t = dists[i];
        dists[i] = dists[mi];
        dists[mi] = t;
        sum += dists[i];
    }
    return if (kk > 0) sum / @as(f64, @floatFromInt(kk)) else 0;
}

fn minDistTo(fp: fr.Fingerprint, set: []const fr.Fingerprint) f64 {
    var best: f64 = std.math.inf(f64);
    for (set) |o| {
        const d = fr.fpDist(fp, o);
        if (d < best) best = d;
    }
    return best;
}

// =============================================================================
// The held-out battery — IDENTICAL construction to inv_iterate.zig (same hidden
// library, same 18 targets, same fixed seeds) so the F/E split partitions the
// SAME battery A1-A6 measured against.
// =============================================================================

const HIDDEN_N: usize = 13;

fn buildHidden() [HIDDEN_N]alien.Program {
    var h: [HIDDEN_N]alien.Program = undefined;
    h[0] = coevo.refSolver(.g_xor);
    h[1] = coevo.refSolver(.g_add);
    h[2] = coevo.refSolver(.pk_xor);
    h[3] = coevo.refSolver(.pk_add);
    h[4] = forge.shiftAtom();
    h[5] = coevo.distinctCountProg();
    h[6] = alien.alienRMWCounter();
    h[7] = alien.alienXorScan();
    h[8] = alien.alienHashTable();
    h[9] = alien.alienUnion();
    var sp = alien.Params{ .active_regs = 8 };
    var prng = std.Random.DefaultPrng.init(BATTERY_SEED);
    const rng = prng.random();
    var n: usize = 10;
    while (n < HIDDEN_N) {
        const p = alien.randProg(rng, &sp);
        if (forge.clean(&p, BATTERY_SEED)) {
            h[n] = p;
            n += 1;
        }
    }
    return h;
}

const TSpec = struct { name: []const u8, idxs: []const usize };

const SPECS = [_]TSpec{
    .{ .name = "distinct", .idxs = &.{5} }, // 0
    .{ .name = "rmw", .idxs = &.{6} }, // 1
    .{ .name = "xorscan", .idxs = &.{7} }, // 2
    .{ .name = "hashtbl", .idxs = &.{8} }, // 3
    .{ .name = "union", .idxs = &.{9} }, // 4
    .{ .name = "decoy1", .idxs = &.{10} }, // 5
    .{ .name = "decoy2", .idxs = &.{11} }, // 6
    .{ .name = "decoy3", .idxs = &.{12} }, // 7
    .{ .name = "dist->gxor", .idxs = &.{ 5, 0 } }, // 8
    .{ .name = "gadd->dist", .idxs = &.{ 1, 5 } }, // 9
    .{ .name = "dist->dist", .idxs = &.{ 5, 5 } }, // 10
    .{ .name = "rmw->pkxor", .idxs = &.{ 6, 2 } }, // 11
    .{ .name = "dist->rmw", .idxs = &.{ 5, 6 } }, // 12
    .{ .name = "shift->dist", .idxs = &.{ 4, 5 } }, // 13
    .{ .name = "shift->dist->gxor", .idxs = &.{ 4, 5, 0 } }, // 14
    .{ .name = "pkadd->dist->pkadd", .idxs = &.{ 3, 5, 3 } }, // 15
    .{ .name = "rmw->rmw->gadd", .idxs = &.{ 6, 6, 1 } }, // 16
    .{ .name = "dist->shift->rmw", .idxs = &.{ 5, 4, 6 } }, // 17
};
const N_TARGETS: usize = SPECS.len;

/// FRONTIER (aimed at): the distinct-count-centric structured family — the exact
/// family A1-A6 found NEVER flips unaimed (distinct, hashtbl, union + compositions).
const F_IDX = [_]usize{ 0, 3, 4, 8, 9, 10, 12, 13, 14 };
/// EVAL / transfer (never aimed at): the rmw-centric structured family + the 3
/// decoy sentinels (self-match pathology check, reported separately from
/// "transfer solves").
const E_IDX = [_]usize{ 1, 2, 5, 6, 7, 11, 15, 16, 17 };
const DECOY_IDX = [_]usize{ 5, 6, 7 };

fn inSet(set: []const usize, x: usize) bool {
    for (set) |v| if (v == x) return true;
    return false;
}

const TState = struct {
    first_round: ?usize = null,
    wlen: usize = 0,
    witness: [DEPTH]usize = undefined,
    self_flip: bool = false,
};

// =============================================================================
// The aimed forge: novelty search whose selection/admission score is BLENDED
// with a residual "how close is this raw candidate to an unsolved F target"
// signal, computed with the SAME behaviour-comparison primitive the certifier
// uses (chainAgreement), at depth 1 (the candidate alone).
// =============================================================================

fn residualScore(cand: *const alien.Program, hidden: []const alien.Program, unsolved: []const usize, seed: u64) f64 {
    if (unsolved.len == 0) return 0;
    var single = [1]alien.Program{cand.*};
    const zero_idx = [_]usize{0};
    var best: f64 = 0;
    for (unsolved) |ti| {
        const agree = chainAgreement(hidden, SPECS[ti].idxs, single[0..1], &zero_idx, MATCH_SEQ, MATCH_L, seed);
        if (agree > best) best = agree;
    }
    return best;
}

const AimParams = struct {
    pop: usize,
    gens: usize,
    k: usize = 12,
    add_threshold: f64 = 0.12,
    archive_cap: usize = 512,
    immigrant_rate: f64 = 0.20,
    tournament: usize = 3,
    active_regs: usize = 8,
    viable_eps: f64 = 0.15,
    alpha_flat: f64 = 0.5,
    alpha_max: f64 = 0.85,
};

/// Novelty search (structure copied from open.search) whose tournament-selection
/// AND archive-admission score is `combined = (1-alpha)*novelty + alpha*residual`
/// instead of pure novelty. `annealed=false` -> alpha fixed at alpha_flat every
/// generation. `annealed=true` -> alpha ramps 0 -> alpha_max across generations
/// (novelty-only exploration early, residual-heavy exploitation late).
fn aimedSearch(
    al: std.mem.Allocator,
    rng: std.Random,
    hidden: []const alien.Program,
    unsolved: []const usize,
    p: AimParams,
    annealed: bool,
    desc_seed: u64,
) !std.ArrayList(open.Member) {
    var sp = alien.Params{ .active_regs = p.active_regs };
    const empty = alien.Program{};
    const dead = open.infoDescriptor(&empty, desc_seed);

    var archive = std.ArrayList(open.Member).init(al);
    var arch_fps = std.ArrayList(fr.Fingerprint).init(al);
    defer arch_fps.deinit();

    const Cand = struct {
        prog: alien.Program,
        fp: fr.Fingerprint,
        novelty: f64 = 0,
        residual: f64 = 0,
        combined: f64 = 0,
    };
    const pop = try al.alloc(Cand, p.pop);
    defer al.free(pop);
    for (pop) |*m| {
        m.prog = alien.randProg(rng, &sp);
        m.fp = open.infoDescriptor(&m.prog, desc_seed);
        m.residual = residualScore(&m.prog, hidden, unsolved, RESIDUAL_SEED);
    }

    var combined_fps = std.ArrayList(fr.Fingerprint).init(al);
    defer combined_fps.deinit();
    const NOV_MAX: f64 = std.math.sqrt(@as(f64, @floatFromInt(fr.FP_N)));

    for (0..p.gens) |gen| {
        combined_fps.clearRetainingCapacity();
        for (arch_fps.items) |f| try combined_fps.append(f);
        for (pop) |m| try combined_fps.append(m.fp);

        const alpha: f64 = if (annealed)
            (if (p.gens <= 1) p.alpha_max else p.alpha_max * (@as(f64, @floatFromInt(gen)) / @as(f64, @floatFromInt(p.gens - 1))))
        else
            p.alpha_flat;

        for (pop) |*m| {
            m.novelty = knnNovelty(m.fp, combined_fps.items, p.k);
            m.combined = (1 - alpha) * (m.novelty / NOV_MAX) + alpha * m.residual;
            const alive = fr.fpDist(m.fp, dead) > p.viable_eps;
            const new_enough = arch_fps.items.len == 0 or minDistTo(m.fp, arch_fps.items) > p.add_threshold;
            if (alive and new_enough and m.combined > p.add_threshold and archive.items.len < p.archive_cap) {
                try archive.append(.{ .prog = m.prog, .fp = m.fp, .novelty = m.combined });
                try arch_fps.append(m.fp);
            }
        }

        const next = try al.alloc(Cand, p.pop);
        for (next) |*c| {
            if (rng.float(f64) < p.immigrant_rate) {
                c.prog = alien.randProg(rng, &sp);
            } else {
                var best = rng.uintLessThan(usize, p.pop);
                for (1..p.tournament) |_| {
                    const cnd = rng.uintLessThan(usize, p.pop);
                    if (pop[cnd].combined > pop[best].combined) best = cnd;
                }
                c.prog = pop[best].prog;
                alien.mutate(rng, &c.prog, &sp);
            }
            c.fp = open.infoDescriptor(&c.prog, desc_seed);
            c.residual = residualScore(&c.prog, hidden, unsolved, RESIDUAL_SEED);
        }
        @memcpy(pop, next);
        al.free(next);
    }
    return archive;
}

// =============================================================================
// The iterated promotion loop (protocol copied from inv_iterate.zig), run once
// per arm x seed. The only experimental variable across arms is which function
// produces the round's archive.
// =============================================================================

const Arm = enum { unaimed, aimed_flat, aimed_annealed, aimed_promote };

fn armName(a: Arm) []const u8 {
    return switch (a) {
        .unaimed => "unaimed",
        .aimed_flat => "aimed_flat",
        .aimed_annealed => "aimed_annealed",
        .aimed_promote => "aimed_promote",
    };
}

fn forgeArchive(
    al: std.mem.Allocator,
    rng: std.Random,
    hidden: []const alien.Program,
    unsolved_f: []const usize,
    arm: Arm,
    dseed: u64,
    pop: usize,
    gens: usize,
) !std.ArrayList(open.Member) {
    return switch (arm) {
        .unaimed => open.search(al, rng, .{ .pop = pop, .gens = gens, .info = true, .seed = dseed }),
        .aimed_flat, .aimed_promote => aimedSearch(al, rng, hidden, unsolved_f, .{ .pop = pop, .gens = gens }, false, dseed),
        .aimed_annealed => aimedSearch(al, rng, hidden, unsolved_f, .{ .pop = pop, .gens = gens }, true, dseed),
    };
}

const PromotedAtom = struct {
    prog: alien.Program,
    round: usize,
    prefix_len: usize,
};

fn runArm(
    al: std.mem.Allocator,
    out: anytype,
    cw: anytype,
    arm: Arm,
    seed: u64,
    hidden: []const alien.Program,
    pop: usize,
    gens: usize,
    max_rounds: usize,
) !void {
    const dseed = seed ^ 0x1F0;
    const fseed = seed +% 0xA70F;

    var atoms = forge.baseAtoms();
    var promoted = std.ArrayList(PromotedAtom).init(al);
    defer promoted.deinit();

    var tstate: [N_TARGETS]TState = .{TState{}} ** N_TARGETS;

    try out.print("\n================ ARM {s}  SEED 0x{X} ================\n", .{ armName(arm), seed });
    try out.print("params: pop={d} gens={d} depth_budget={d} census_cap={d} max_rounds={d}\n", .{ pop, gens, DEPTH, CENSUS_CAP, max_rounds });

    // ---- round 0: baseline reachability of the battery from the base atoms ----
    var reachable: usize = 0;
    var f_reach: usize = 0;
    var e_reach: usize = 0;
    for (SPECS, 0..) |spec, ti| {
        var wit: [DEPTH]usize = undefined;
        var wl: usize = 0;
        if (targetSolvable(hidden, spec.idxs, atoms.slice(), DEPTH, RSEED, &wit, &wl)) {
            tstate[ti].first_round = 0;
            tstate[ti].wlen = wl;
            tstate[ti].witness = wit;
            reachable += 1;
            if (inSet(&F_IDX, ti)) f_reach += 1;
            if (inSet(&E_IDX, ti)) e_reach += 1;
        }
    }
    try out.print("[round 0] baseline: lib={d} heldout {d}/{d} (F {d}/{d}  E {d}/{d})\n", .{ atoms.len, reachable, N_TARGETS, f_reach, F_IDX.len, e_reach, E_IDX.len });
    try cw.print("{s},0x{X},0,{d},{d},{d},0,0,0,0,0,0,{d},{d},{d},{d},0,0,0,0,0\n", .{ armName(arm), seed, DEPTH, atoms.len, atoms.len, f_reach, F_IDX.len, e_reach, E_IDX.len });

    var fixed_point = false;
    var round: usize = 1;
    var total_self: usize = 0;
    var total_composed: usize = 0;
    while (round <= max_rounds) : (round += 1) {
        var timer = try std.time.Timer.start();
        const lib_before = atoms.len;

        // which F targets remain unsolved right now (the frontier we aim at)
        var unsolved_buf: [F_IDX.len]usize = undefined;
        var n_unsolved: usize = 0;
        for (F_IDX) |ti| {
            if (tstate[ti].first_round == null) {
                unsolved_buf[n_unsolved] = ti;
                n_unsolved += 1;
            }
        }
        const unsolved_f = unsolved_buf[0..n_unsolved];

        var prng = std.Random.DefaultPrng.init(seed +% round *% 0x9E3779B97F4A7C15);
        var archive = try forgeArchive(al, prng.random(), hidden, unsolved_f, arm, dseed, pop, gens);
        defer archive.deinit();

        var cleanlist = std.ArrayList(open.Member).init(al);
        defer cleanlist.deinit();
        for (archive.items) |m| {
            if (forge.clean(&m.prog, dseed)) try cleanlist.append(m);
        }
        std.mem.sort(open.Member, cleanlist.items, {}, struct {
            fn lt(_: void, a: open.Member, b: open.Member) bool {
                return a.prog.len() < b.prog.len();
            }
        }.lt);

        const n_checked = @min(CENSUS_CAP, cleanlist.items.len);
        var n_irred: usize = 0;
        var first_irred: ?alien.Program = null; // shortest certified-irreducible (A1-A6 policy)
        var best_res_irred: ?alien.Program = null; // highest-residual certified-irreducible (aimed_promote)
        var best_res: f64 = -1;
        for (cleanlist.items[0..n_checked]) |m| {
            if (!forge.reducibleLib(&m.prog, atoms.slice(), DEPTH, fseed)) {
                n_irred += 1;
                if (first_irred == null) first_irred = m.prog;
                if (arm == .aimed_promote) {
                    const r = residualScore(&m.prog, hidden, unsolved_f, RESIDUAL_SEED);
                    // strictly-greater keeps the SHORTEST program at any given
                    // residual (cleanlist is length-sorted) — ties -> shorter.
                    if (r > best_res) {
                        best_res = r;
                        best_res_irred = m.prog;
                    }
                }
            }
        }
        if (arm == .aimed_promote and best_res_irred != null) first_irred = best_res_irred;

        if (first_irred == null or atoms.len >= forge.MAX_ATOMS) {
            const ms = timer.read() / std.time.ns_per_ms;
            try out.print("[round {d}] archive={d} clean={d} checked={d} irreducible=0 -> FIXED POINT ({d} ms)\n", .{ round, archive.items.len, cleanlist.items.len, n_checked, ms });
            try cw.print("{s},0x{X},{d},{d},{d},{d},{d},{d},{d},0,0,0,{d},{d},{d},{d},0,0,0,0,{d}\n", .{ armName(arm), seed, round, DEPTH, lib_before, atoms.len, archive.items.len, cleanlist.items.len, n_checked, f_reach, F_IDX.len, e_reach, E_IDX.len, ms });
            fixed_point = true;
            break;
        }

        const new_atom = first_irred.?;
        const new_idx = atoms.len;
        atoms.appendAssumeCapacity(new_atom);
        try promoted.append(.{ .prog = new_atom, .round = round, .prefix_len = lib_before });

        // ---- A4-style reachability re-measurement, over the FULL 18-target battery ----
        var new_f_flips: usize = 0;
        var new_e_flips: usize = 0;
        var new_self: usize = 0;
        var new_composed: usize = 0;
        for (SPECS, 0..) |spec, ti| {
            if (tstate[ti].first_round != null) continue;
            var wit: [DEPTH]usize = undefined;
            var wl: usize = 0;
            if (targetSolvable(hidden, spec.idxs, atoms.slice(), DEPTH, RSEED, &wit, &wl)) {
                tstate[ti].first_round = round;
                tstate[ti].wlen = wl;
                tstate[ti].witness = wit;
                const is_self = (wl == 1 and wit[0] == new_idx);
                tstate[ti].self_flip = is_self;
                if (is_self) new_self += 1 else new_composed += 1;
                if (inSet(&F_IDX, ti)) new_f_flips += 1;
                if (inSet(&E_IDX, ti)) new_e_flips += 1;
            }
        }
        reachable += new_f_flips + new_e_flips;
        f_reach += new_f_flips;
        e_reach += new_e_flips;
        total_self += new_self;
        total_composed += new_composed;

        const ms = timer.read() / std.time.ns_per_ms;
        try out.print("[round {d}] archive={d} clean={d} checked={d} irreducible={d} PROMOTE len={d} -> lib={d} | F {d}/{d} E {d}/{d} (+F{d} +E{d}: {d} self {d} composed) ({d} ms)\n", .{
            round, archive.items.len, cleanlist.items.len, n_checked, n_irred, new_atom.len(), atoms.len,
            f_reach, F_IDX.len, e_reach, E_IDX.len, new_f_flips, new_e_flips, new_self, new_composed, ms,
        });
        try cw.print("{s},0x{X},{d},{d},{d},{d},{d},{d},{d},{d},1,{d},{d},{d},{d},{d},{d},{d},{d},{d},{d}\n", .{
            armName(arm), seed, round, DEPTH, lib_before, atoms.len, archive.items.len, cleanlist.items.len, n_checked, n_irred,
            new_atom.len(), f_reach, F_IDX.len, e_reach, E_IDX.len, new_f_flips, new_e_flips, new_self, new_composed, ms,
        });
    }

    if (!fixed_point) {
        try out.print("[end] round cap {d} reached WITHOUT fixed point (library still growing)\n", .{max_rounds});
    }

    // ---- per-target table (tagged F/E, SELF/COMPOSED) ----
    try out.writeAll("\nheld-out battery (F = aimed frontier, E = eval/transfer, never aimed):\n");
    for (SPECS, 0..) |spec, ti| {
        const st = tstate[ti];
        const tag = if (inSet(&F_IDX, ti)) "F" else "E";
        const decoy = if (inSet(&DECOY_IDX, ti)) " [decoy-sentinel]" else "";
        if (st.first_round) |r| {
            try out.print("  [{s}] {s:<20} round {d:>2}  [", .{ tag, spec.name, r });
            for (0..st.wlen) |j| {
                if (j > 0) try out.writeAll(",");
                try out.print("{d}", .{st.witness[j]});
            }
            try out.print("]{s}{s}\n", .{ if (st.self_flip) "  (SELF)" else "  (COMPOSED)", decoy });
        } else {
            try out.print("  [{s}] {s:<20}  never{s}\n", .{ tag, spec.name, decoy });
        }
    }

    // ---- A5/A6-style retro-reduction audit ----
    try out.writeAll("\nretro-reduction audit (deeper certifier on every promoted atom):\n");
    var leaks: usize = 0;
    var redund: usize = 0;
    for (promoted.items, 0..) |pa, k| {
        var prefix = forge.AtomLib{};
        for (0..pa.prefix_len) |j| prefix.appendAssumeCapacity(atoms.slice()[j]);
        const p4 = forge.reducibleLib(&pa.prog, prefix.slice(), 4, fseed);
        const p5: ?bool = if (pa.prefix_len <= 13) forge.reducibleLib(&pa.prog, prefix.slice(), 5, fseed) else null;

        var minus = forge.AtomLib{};
        const self_idx = forge.BASE_ATOMS + k;
        for (0..atoms.len) |j| {
            if (j != self_idx) minus.appendAssumeCapacity(atoms.slice()[j]);
        }
        const f3 = forge.reducibleLib(&pa.prog, minus.slice(), 3, fseed);
        const f4 = forge.reducibleLib(&pa.prog, minus.slice(), 4, fseed);
        if (p4 or (p5 orelse false)) leaks += 1;
        if (f3 or f4) redund += 1;

        try out.print("  inv{d:<3} round {d:>2} len {d:>2}  prefix_d4={s:<9} prefix_d5={s:<9} final-self_d3={s:<9} final-self_d4={s:<9}\n", .{
            k,
            pa.round,
            pa.prog.len(),
            if (p4) "REDUCED" else "holds",
            if (p5) |v| (if (v) "REDUCED" else "holds") else "skipped",
            if (f3) "REDUNDANT" else "holds",
            if (f4) "REDUNDANT" else "holds",
        });
    }

    const total_flips = total_self + total_composed;
    try out.print("\narm {s} seed 0x{X} summary: lib {d}->{d}  F {d}/{d}  E {d}/{d}  flips self={d} composed={d} (self-rate={d:.1}%)  leaks={d}/{d}  redundant={d}/{d}\n", .{
        armName(arm),
        seed,
        forge.BASE_ATOMS,
        atoms.len,
        f_reach,
        F_IDX.len,
        e_reach,
        E_IDX.len,
        total_self,
        total_composed,
        if (total_flips > 0) 100.0 * @as(f64, @floatFromInt(total_self)) / @as(f64, @floatFromInt(total_flips)) else 0.0,
        leaks,
        promoted.items.len,
        redund,
        promoted.items.len,
    });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const al = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(al);
    defer std.process.argsFree(al, args);
    if (args.len < 2) {
        try out.writeAll("usage: inv_aimed <csv_path> [seed...] [--pop=N] [--gens=N] [--rounds=N]\n");
        return;
    }
    const csv_path = args[1];

    var seeds = std.ArrayList(u64).init(al);
    defer seeds.deinit();
    var pop: usize = 90;
    var gens: usize = 45;
    var rounds: usize = 10;
    for (args[2..]) |a| {
        if (std.mem.startsWith(u8, a, "--pop=")) {
            pop = try std.fmt.parseInt(usize, a[6..], 10);
        } else if (std.mem.startsWith(u8, a, "--gens=")) {
            gens = try std.fmt.parseInt(usize, a[7..], 10);
        } else if (std.mem.startsWith(u8, a, "--rounds=")) {
            rounds = try std.fmt.parseInt(usize, a[9..], 10);
        } else {
            try seeds.append(try std.fmt.parseInt(u64, a, 0));
        }
    }
    if (seeds.items.len == 0) {
        try seeds.append(0xA70F);
        try seeds.append(0x5EED2);
    }

    const csv = try std.fs.cwd().createFile(csv_path, .{});
    defer csv.close();
    const cw = csv.writer();
    try cw.writeAll("arm,seed,round,depth_budget,lib_before,lib_after,archive,n_clean,n_checked,n_irreducible,promoted,promoted_len,f_reachable,f_total,e_reachable,e_total,new_f_flips,new_e_flips,new_self,new_composed,round_ms\n");

    const hidden = buildHidden();
    try out.print("F/E split: F(aim)={d} targets  E(eval/transfer)={d} targets  total={d}\n", .{ F_IDX.len, E_IDX.len, N_TARGETS });
    try out.writeAll("F = distinct-count-centric family (distinct, hashtbl, union, dist->gxor, gadd->dist, dist->dist, dist->rmw, shift->dist, shift->dist->gxor)\n");
    try out.writeAll("E = rmw-centric family + decoys (rmw, xorscan, rmw->pkxor, pkadd->dist->pkadd, rmw->rmw->gadd, dist->shift->rmw, decoy1-3)\n");

    const arms = [_]Arm{ .unaimed, .aimed_flat, .aimed_annealed, .aimed_promote };
    for (arms) |arm| {
        for (seeds.items) |s| {
            try runArm(al, out, cw, arm, s, &hidden, pop, gens, rounds);
        }
    }
}
