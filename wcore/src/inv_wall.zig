//! CONJUNCTION-WALL ATTACK (round 2026-07-10c headline experiment).
//!
//! Predecessor: `inv_aimed.zig` + `inv_aimed_probe.zig` (round 2026-07-10b) measured
//! that the distinct-count family (7/9 of the aimed frontier F) sits behind a
//! CONJUNCTION WALL: its depth-1 behavioural-agreement residual has no climbable
//! gradient — pure greedy residual climb plateaus at 0.862 vs the 0.95 certification
//! bar (random-clean max 0.723). Behavioural-proximity pressure cannot cross it.
//! The aimed_forge verdict named two escape levers; this file builds and measures both:
//!
//! LEVER A — STEPPING-STONE CURRICULUM. Decompose the distinct-count mechanism
//! (5 coordinated instructions: seen-flag load, flag store, invert, accumulate, emit)
//! into intermediate behaviours designed to each have nonzero gradient from the
//! previous rung:
//!     S1 "membership"  : out[i] = 1 if syms[i] appeared before position i else 0
//!                        (mechanism: load mem[sym]; store mem[sym]=1 — a 2-instruction
//!                         sub-conjunction, structurally the hashtbl family, whose
//!                         residual landscape the probe measured fully climbable)
//!     S2 "noveltyflag" : out[i] = 1 on FIRST occurrence else 0 (= 1 XOR membership;
//!                        exactly ONE inserted instruction beyond S1 — note the trap
//!                        this ladder is designed around: S1 and S2 are behavioural
//!                        COMPLEMENTS (agreement 0.000) at mechanism edit-distance 1)
//!     S3 "distinct"    : the full target. DESIGNED PAYOFF: distinct = noveltyflag
//!                        chained into g_add (running sum of first-occurrence flags),
//!                        so once an S2-equivalent atom is PROMOTED, distinct and 4 of
//!                        its 6 hidden compositions become composable at depth <= 3
//!                        and flip by composition — no raw 5-instruction program needed.
//! The stone reference programs are used ONLY as behavioural oracles for residual
//! scoring (same status as the hidden battery targets). They are NEVER injected into
//! any population. Incumbent injection (the curriculum's transfer mechanism) uses
//! exclusively programs the forge itself found and promoted.
//!
//! LEVER B — MECHANISM-LEVEL DESCRIPTORS. Replace the behavioural-agreement residual
//! with TARGET-FREE structural credit M = m_rel * m_perm * m_dup:
//!     m_rel  : symbol-relabel invariance — outputs unchanged under a bijection of the
//!              symbol alphabet (set-cardinality mechanisms depend on EQUALITY only;
//!              kills g_xor/g_add/hashtbl-value mechanisms)
//!     m_perm : prefix-permutation invariance — tail outputs unchanged when the prefix
//!              is shuffled (order-free state; kills shift/positional mechanisms)
//!     m_dup  : duplicate-vs-fresh downstream sensitivity — adversarial stream pairs
//!              identical except one position holds a SEEN vs an UNSEEN symbol; scores
//!              the fraction of downstream outputs that differ (persistent-accumulator
//!              signature; kills constants and transient flags)
//! distinct-count is the unique known mechanism scoring ~1.0 on all three at once.
//! Per round-b's settled principle, M enters at the PROMOTION GATE (rank the
//! certified-irreducible census by M); the search keeps a 0.5-novelty blend exactly
//! like aimed_promote so the comparison to control isolates the gate signal.
//!
//! PHASES (separate invocations, each well under the 15-min cap):
//!   selftest              — instrument fidelity: stone oracles vs brute references,
//!                           chain identity noveltyflag->g_add == distinct, M table.
//!   probe <csv>           — the diagnosis-probe analogue: greedy climbs at equal
//!                           total budget (8 restarts x 90k evals, 2 seeds) for
//!                           control-agreement / curriculum / mech-pure / mech-blend.
//!                           Primary metric: best agreement vs distinct, against the
//!                           0.862 plateau and 0.95 bar.
//!   forge <arm> <csv>     — aimed_promote-style promotion rounds (pop 90 x gens 45 x
//!                           10 rounds, seeds 0xA70F/0x5EED2), arm in {ctrl,curr,mech}:
//!                           ctrl = no-curriculum aimed_promote at the unsolved WALL
//!                                  family (equal-budget control),
//!                           curr = lever A (stone ladder + incumbent injection),
//!                           mech = lever B (M at the gate).
//!                           All arms adopt the round-b settled +1-DEPTH PROMOTION GATE:
//!                           the gate winner must also survive depth-4 reducibleLib
//!                           (up to 3 fallback candidates). Full A5/A6 retro-audit
//!                           (prefix d4/d5, final-minus-self d3/d4) on every promotion.
//!
//! Build: cd wcore && zig build-exe -O ReleaseFast src/inv_wall.zig -femit-bin=bin/inv_wall
//! Run:   ./bin/inv_wall selftest
//!        ./bin/inv_wall probe ../results/conj_wall_2026_07_10.csv
//!        ./bin/inv_wall forge ctrl ../results/conj_wall_2026_07_10.csv
//!        ./bin/inv_wall forge curr ../results/conj_wall_2026_07_10.csv
//!        ./bin/inv_wall forge mech ../results/conj_wall_2026_07_10.csv
//! Single-threaded, deterministic given the seed list. CSV opens in APPEND mode so
//! the phases share one results file (header written on creation only).

const std = @import("std");
const alien = @import("inv_alien.zig");
const coevo = @import("inv_coevo.zig");
const open = @import("inv_open.zig");
const forge = @import("inv_atomforge.zig");
const fr = @import("inv_frontier.zig");

const V: usize = alien.CANON_BASE;
const DEPTH: usize = forge.COMPOSE_DEPTH; // production certifier depth = 3
const GATE_DEPTH: usize = DEPTH + 1; // the settled +1-depth promotion gate
const CENSUS_CAP: usize = 80;
const MATCH_SEQ: usize = 8;
const MATCH_L: usize = 28;
const RSEED: u64 = 0x0F17ED; // reachability-check seed (same as inv_iterate/inv_aimed)
const BATTERY_SEED: u64 = 0xBA77E71; // battery-definition seed (same)
const RESIDUAL_SEED: u64 = 0x2E51DA1; // residual seed (same as inv_aimed)
const MECH_SEED: u64 = 0x3C0DE5A1; // mechanism-descriptor stream seed (new, fixed)
const MECH_TRIALS: usize = 6;

// =============================================================================
// Battery (ported verbatim from inv_aimed.zig so results are apples-to-apples)
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

const F_IDX = [_]usize{ 0, 3, 4, 8, 9, 10, 12, 13, 14 };
const E_IDX = [_]usize{ 1, 2, 5, 6, 7, 11, 15, 16, 17 };
const DECOY_IDX = [_]usize{ 5, 6, 7 };
/// The measured conjunction-wall family: distinct + its 6 hidden compositions
/// (hashtbl/union deliberately EXCLUDED so control rounds cannot spend their
/// budget on the already-climbable half of F).
const WALL_IDX = [_]usize{ 0, 8, 9, 10, 12, 13, 14 };

fn inSet(set: []const usize, x: usize) bool {
    for (set) |v| if (v == x) return true;
    return false;
}

// =============================================================================
// Ported comparison / solvability primitives (private in inv_aimed/inv_iterate)
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
// LEVER A — the stone ladder (behavioural oracles only; never injected)
// =============================================================================

/// S1: membership / seen-before flag. out = mem[sym] read before marking.
fn membershipProg() alien.Program {
    var p = alien.Program{};
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 6, .imm = 1 }); // r6 = 1
    p.step.appendAssumeCapacity(.{ .op = .a_load, .a = 0, .out = 3 }); // r3 = mem[sym]
    p.step.appendAssumeCapacity(.{ .op = .a_store, .a = 0, .b = 6 }); // mem[sym] = 1
    return p;
}

/// S2: first-occurrence (novelty) flag. out = 1 XOR membership.
fn noveltyFlagProg() alien.Program {
    var p = alien.Program{};
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 6, .imm = 1 }); // r6 = 1
    p.step.appendAssumeCapacity(.{ .op = .a_load, .a = 0, .out = 3 }); // r3 = mem[sym]
    p.step.appendAssumeCapacity(.{ .op = .a_store, .a = 0, .b = 6 }); // mem[sym] = 1
    p.step.appendAssumeCapacity(.{ .op = .a_xor, .a = 3, .b = 6, .out = 3 }); // r3 ^= 1
    return p;
}

const StoneKind = union(enum) { prog: alien.Program, spec: usize };
const Stone = struct { name: []const u8, kind: StoneKind };

fn ladderStones() [3]Stone {
    return .{
        .{ .name = "S1_membership", .kind = .{ .prog = membershipProg() } },
        .{ .name = "S2_noveltyflag", .kind = .{ .prog = noveltyFlagProg() } },
        .{ .name = "S3_distinct", .kind = .{ .spec = 0 } },
    };
}

fn oracleOut(hidden: []const alien.Program, stone: *const Stone, syms: []const u8, out: []u8) void {
    switch (stone.kind) {
        .prog => |p| {
            var copy = p;
            alien.runStream(&copy, syms, out);
        },
        .spec => |si| forge.applyChain(hidden, SPECS[si].idxs, syms, out),
    }
}

/// Depth-1 agreement between a candidate program alone and a stone oracle.
fn stoneAgreement(hidden: []const alien.Program, stone: *const Stone, cand: *const alien.Program, n: usize, L: usize, seed: u64) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var out_a: [256]u8 = undefined;
    var out_b: [256]u8 = undefined;
    var agree: usize = 0;
    var total: usize = 0;
    for (0..n) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        oracleOut(hidden, stone, syms[0..L], out_a[0..L]);
        alien.runStream(cand, syms[0..L], out_b[0..L]);
        for (0..L) |i| {
            total += 1;
            if (out_a[i] == out_b[i]) agree += 1;
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total));
}

/// Is the stone's behaviour composable from `lib` at depth <= max_depth?
fn stoneSolvableLib(
    hidden: []const alien.Program,
    stone: *const Stone,
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
            if (chainVsOracle(hidden, stone, lib, idxs[0..d], MATCH_SEQ, MATCH_L, seed) >= forge.MATCH_THRESHOLD) {
                for (0..d) |j| witness[j] = idxs[j];
                wlen.* = d;
                return true;
            }
        }
    }
    return false;
}

fn chainVsOracle(hidden: []const alien.Program, stone: *const Stone, lib: []const alien.Program, idxs: []const usize, n: usize, L: usize, seed: u64) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var out_a: [256]u8 = undefined;
    var out_b: [256]u8 = undefined;
    var agree: usize = 0;
    var total: usize = 0;
    for (0..n) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        oracleOut(hidden, stone, syms[0..L], out_a[0..L]);
        forge.applyChain(lib, idxs, syms[0..L], out_b[0..L]);
        for (0..L) |i| {
            total += 1;
            if (out_a[i] == out_b[i]) agree += 1;
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total));
}

// =============================================================================
// LEVER B — the mechanism-level descriptor M = m_rel * m_perm * m_dup
// (target-free: no reference anywhere to distinct-count's outputs)
// =============================================================================

const Mech = struct { rel: f64, perm: f64, dup: f64, m: f64 };

fn mechScore(cand: *const alien.Program) Mech {
    var prng = std.Random.DefaultPrng.init(MECH_SEED);
    const rng = prng.random();
    const L: usize = 16;
    var syms: [L]u8 = undefined;
    var syms2: [L]u8 = undefined;
    var out_a: [L]u8 = undefined;
    var out_b: [L]u8 = undefined;

    // ---- m_rel: symbol-relabel invariance (equality-only mechanisms pass) ----
    var rel_agree: usize = 0;
    var rel_tot: usize = 0;
    for (0..MECH_TRIALS) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        var perm = [_]u8{ 0, 1, 2, 3 };
        rng.shuffle(u8, &perm);
        if (perm[0] == 0 and perm[1] == 1 and perm[2] == 2 and perm[3] == 3) {
            perm = .{ 1, 2, 3, 0 }; // never test the identity relabeling
        }
        for (0..L) |i| syms2[i] = perm[syms[i]];
        alien.runStream(cand, &syms, &out_a);
        alien.runStream(cand, &syms2, &out_b);
        for (0..L) |i| {
            rel_tot += 1;
            if (out_a[i] == out_b[i]) rel_agree += 1;
        }
    }
    const m_rel = @as(f64, @floatFromInt(rel_agree)) / @as(f64, @floatFromInt(rel_tot));

    // ---- m_perm: prefix-permutation invariance of the tail (order-free state) ----
    var pm_agree: usize = 0;
    var pm_tot: usize = 0;
    const H: usize = L / 2;
    for (0..MECH_TRIALS) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        @memcpy(&syms2, &syms);
        rng.shuffle(u8, syms2[0..H]);
        alien.runStream(cand, &syms, &out_a);
        alien.runStream(cand, &syms2, &out_b);
        for (H..L) |i| {
            pm_tot += 1;
            if (out_a[i] == out_b[i]) pm_agree += 1;
        }
    }
    const m_perm = @as(f64, @floatFromInt(pm_agree)) / @as(f64, @floatFromInt(pm_tot));

    // ---- m_dup: duplicate-vs-fresh downstream sensitivity (persistent set state) ----
    // Streams identical except position 5: a SEEN symbol vs an UNSEEN symbol; the
    // suffix uses only prefix symbols, so a set-cardinality state differs FOREVER
    // while flags/echoes differ only transiently and constants never differ.
    var dp_diff: usize = 0;
    var dp_tot: usize = 0;
    const P: usize = 5;
    const DL: usize = 14; // 5 prefix + 1 probe + 8 suffix
    for (0..MECH_TRIALS) |_| {
        var alpha = [_]u8{ 0, 1, 2, 3 };
        rng.shuffle(u8, &alpha);
        const a = alpha[0]; // seen
        const b = alpha[1]; // seen
        const f = alpha[2]; // fresh (never in prefix/suffix)
        var sa: [DL]u8 = undefined;
        sa[0] = a;
        sa[1] = b;
        for (2..P) |i| sa[i] = if (rng.boolean()) a else b;
        var sb: [DL]u8 = undefined;
        for (P + 1..DL) |i| sa[i] = if (rng.boolean()) a else b;
        @memcpy(&sb, &sa);
        sa[P] = if (rng.boolean()) a else b; // duplicate of a seen symbol
        sb[P] = f; // fresh unseen symbol
        var oa: [DL]u8 = undefined;
        var ob: [DL]u8 = undefined;
        alien.runStream(cand, &sa, &oa);
        alien.runStream(cand, &sb, &ob);
        for (P..DL) |i| {
            dp_tot += 1;
            if (oa[i] != ob[i]) dp_diff += 1;
        }
    }
    const m_dup = @as(f64, @floatFromInt(dp_diff)) / @as(f64, @floatFromInt(dp_tot));

    return .{ .rel = m_rel, .perm = m_perm, .dup = m_dup, .m = m_rel * m_perm * m_dup };
}

// =============================================================================
// Scoring context shared by search fitness, promotion gate, and the probe
// =============================================================================

const Mode = enum { stone, mech, family };

const Ctx = struct {
    hidden: []const alien.Program,
    mode: Mode,
    stone: ?Stone = null,
    family: []const usize = &.{},
    incumbent: ?alien.Program = null,
};

fn familyResidual(hidden: []const alien.Program, unsolved: []const usize, cand: *const alien.Program) f64 {
    if (unsolved.len == 0) return 0;
    var single = [1]alien.Program{cand.*};
    const zero_idx = [_]usize{0};
    var best: f64 = 0;
    for (unsolved) |ti| {
        const agree = chainAgreement(hidden, SPECS[ti].idxs, single[0..1], &zero_idx, MATCH_SEQ, MATCH_L, RESIDUAL_SEED);
        if (agree > best) best = agree;
    }
    return best;
}

fn ctxScore(ctx: *const Ctx, cand: *const alien.Program) f64 {
    return switch (ctx.mode) {
        .stone => stoneAgreement(ctx.hidden, &ctx.stone.?, cand, MATCH_SEQ, MATCH_L, RESIDUAL_SEED),
        .mech => mechScore(cand).m,
        .family => familyResidual(ctx.hidden, ctx.family, cand),
    };
}

/// Trajectory metric logged everywhere: best depth-1 agreement vs the distinct
/// singleton (SPECS[0]) — directly comparable to the probe's 0.862 plateau.
fn agreeDistinct(hidden: []const alien.Program, cand: *const alien.Program) f64 {
    var single = [1]alien.Program{cand.*};
    const zero_idx = [_]usize{0};
    return chainAgreement(hidden, SPECS[0].idxs, single[0..1], &zero_idx, MATCH_SEQ, MATCH_L, RESIDUAL_SEED);
}

// =============================================================================
// The forge search (aimed_flat structure from inv_aimed + incumbent injection)
// =============================================================================

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
    alpha: f64 = 0.5,
};

fn wallSearch(
    al: std.mem.Allocator,
    rng: std.Random,
    ctx: *const Ctx,
    p: AimParams,
    dseed: u64,
) !std.ArrayList(open.Member) {
    var sp = alien.Params{ .active_regs = p.active_regs };
    const empty = alien.Program{};
    const dead = open.infoDescriptor(&empty, dseed);

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
    for (pop, 0..) |*m, i| {
        if (ctx.incumbent != null and i < p.pop / 4) {
            // curriculum warm-start: the incumbent is a program the forge itself
            // found/promoted — never a hand-written oracle.
            m.prog = ctx.incumbent.?;
            if (i > 0) {
                const nm = 1 + rng.uintLessThan(usize, 3);
                for (0..nm) |_| alien.mutate(rng, &m.prog, &sp);
            }
        } else {
            m.prog = alien.randProg(rng, &sp);
        }
        m.fp = open.infoDescriptor(&m.prog, dseed);
        m.residual = ctxScore(ctx, &m.prog);
    }

    var combined_fps = std.ArrayList(fr.Fingerprint).init(al);
    defer combined_fps.deinit();
    const NOV_MAX: f64 = std.math.sqrt(@as(f64, @floatFromInt(fr.FP_N)));

    for (0..p.gens) |_| {
        combined_fps.clearRetainingCapacity();
        for (arch_fps.items) |f| try combined_fps.append(f);
        for (pop) |m| try combined_fps.append(m.fp);

        for (pop) |*m| {
            m.novelty = knnNovelty(m.fp, combined_fps.items, p.k);
            m.combined = (1 - p.alpha) * (m.novelty / NOV_MAX) + p.alpha * m.residual;
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
                if (ctx.incumbent != null and rng.boolean()) {
                    // keep the stepping stone alive as a variation source all round
                    c.prog = ctx.incumbent.?;
                    const nm = 1 + rng.uintLessThan(usize, 3);
                    for (0..nm) |_| alien.mutate(rng, &c.prog, &sp);
                } else {
                    c.prog = alien.randProg(rng, &sp);
                }
            } else {
                var best = rng.uintLessThan(usize, p.pop);
                for (1..p.tournament) |_| {
                    const cnd = rng.uintLessThan(usize, p.pop);
                    if (pop[cnd].combined > pop[best].combined) best = cnd;
                }
                c.prog = pop[best].prog;
                alien.mutate(rng, &c.prog, &sp);
            }
            c.fp = open.infoDescriptor(&c.prog, dseed);
            c.residual = ctxScore(ctx, &c.prog);
        }
        @memcpy(pop, next);
        al.free(next);
    }
    return archive;
}

// =============================================================================
// CSV plumbing (append mode: probe + 3 forge invocations share one file)
// =============================================================================

const CSV_HEADER = "phase,arm,seed,round,target,best_gate,best_agree_distinct,n_archive,n_clean,n_checked,n_irred,d4_rejects,promoted,promoted_len,stone_event,f_reach,e_reach,new_f,new_e,ms\n";

fn openCsv(path: []const u8) !std.fs.File {
    if (std.fs.cwd().openFile(path, .{ .mode = .write_only })) |f| {
        try f.seekFromEnd(0);
        return f;
    } else |_| {
        const f = try std.fs.cwd().createFile(path, .{});
        try f.writeAll(CSV_HEADER);
        return f;
    }
}

// =============================================================================
// PHASE: selftest — instrument fidelity before any experiment
// =============================================================================

fn refMembership(syms: []const u8, out: []u8) void {
    var seen = [_]bool{false} ** V;
    for (syms, 0..) |s, i| {
        out[i] = if (seen[s % V]) 1 else 0;
        seen[s % V] = true;
    }
}

fn refNovelty(syms: []const u8, out: []u8) void {
    var seen = [_]bool{false} ** V;
    for (syms, 0..) |s, i| {
        out[i] = if (seen[s % V]) 0 else 1;
        seen[s % V] = true;
    }
}

fn runSelftest(out: anytype) !void {
    var prng = std.Random.DefaultPrng.init(0x7E57);
    const rng = prng.random();
    var syms: [64]u8 = undefined;
    var a: [64]u8 = undefined;
    var b: [64]u8 = undefined;

    // 1. stone oracles are exactly their brute references
    var s1 = membershipProg();
    var s2 = noveltyFlagProg();
    var ok1 = true;
    var ok2 = true;
    for (0..200) |_| {
        for (&syms) |*s| s.* = @intCast(rng.uintLessThan(usize, V));
        refMembership(&syms, &a);
        alien.runStream(&s1, &syms, &b);
        for (0..64) |i| {
            if (a[i] % V != b[i]) ok1 = false;
        }
        refNovelty(&syms, &a);
        alien.runStream(&s2, &syms, &b);
        for (0..64) |i| {
            if (a[i] % V != b[i]) ok2 = false;
        }
    }
    try out.print("[selftest] S1 membership == brute reference on 200x64 syms: {s}\n", .{if (ok1) "PASS" else "FAIL"});
    try out.print("[selftest] S2 noveltyflag == brute reference on 200x64 syms: {s}\n", .{if (ok2) "PASS" else "FAIL"});

    // 2. the designed payoff identity: noveltyflag -> g_add == distinct-count (mod V)
    var lib2 = [_]alien.Program{ noveltyFlagProg(), coevo.refSolver(.g_add) };
    const chain_idx = [_]usize{ 0, 1 };
    var ok3 = true;
    for (0..200) |_| {
        for (&syms) |*s| s.* = @intCast(rng.uintLessThan(usize, V));
        coevo.distinctCountTarget(&syms, &a);
        forge.applyChain(&lib2, &chain_idx, &syms, &b);
        for (0..64) |i| {
            if (a[i] != b[i]) ok3 = false;
        }
    }
    try out.print("[selftest] chain [noveltyflag, g_add] == distinctCountTarget: {s}\n", .{if (ok3) "PASS" else "FAIL"});

    // 3. the complement trap, quantified: agreement(S1 prog, S2 oracle)
    const hidden = buildHidden();
    const stones = ladderStones();
    const comp = stoneAgreement(&hidden, &stones[1], &s1, MATCH_SEQ, MATCH_L, RESIDUAL_SEED);
    try out.print("[selftest] agreement(S1 program, S2 oracle) = {d:.3} at mechanism edit-distance 1\n", .{comp});

    // 4. mechanism-descriptor table over the known mechanisms
    try out.writeAll("[selftest] mechanism descriptor M = m_rel * m_perm * m_dup:\n");
    try out.writeAll("             name           m_rel   m_perm  m_dup   M\n");
    const table = [_]struct { name: []const u8, prog: alien.Program }{
        .{ .name = "distinct", .prog = coevo.distinctCountProg() },
        .{ .name = "membership(S1)", .prog = membershipProg() },
        .{ .name = "noveltyflag(S2)", .prog = noveltyFlagProg() },
        .{ .name = "g_xor", .prog = coevo.refSolver(.g_xor) },
        .{ .name = "g_add", .prog = coevo.refSolver(.g_add) },
        .{ .name = "pk_xor", .prog = coevo.refSolver(.pk_xor) },
        .{ .name = "pk_add(rmw)", .prog = coevo.refSolver(.pk_add) },
        .{ .name = "shift", .prog = forge.shiftAtom() },
        .{ .name = "hashtbl", .prog = alien.alienHashTable() },
        .{ .name = "empty", .prog = alien.Program{} },
    };
    for (table) |row| {
        const m = mechScore(&row.prog);
        try out.print("             {s:<15}{d:.3}   {d:.3}   {d:.3}   {d:.3}\n", .{ row.name, m.rel, m.perm, m.dup, m.m });
    }

    // 5. agreement sanity: distinct prog vs its own spec oracle = 1.0
    var dc = coevo.distinctCountProg();
    const self_agree = agreeDistinct(&hidden, &dc);
    try out.print("[selftest] agreement(distinctCountProg, distinct oracle) = {d:.3}\n", .{self_agree});

    // 6. does the A1-A6 census "clean" filter (OUT_R entropy > 0.30) even ADMIT
    //    the target family? Saturating counters output near-constant streams at
    //    V=4, so this checks for a structural exclusion at the census entrance.
    try out.writeAll("[selftest] A1-A6 clean filter vs the distinct-count family (dseed=seed^0x1F0 of 0xA70F):\n");
    const dseed: u64 = 0xA70F ^ 0x1F0;
    const cf_table = [_]struct { name: []const u8, prog: alien.Program }{
        .{ .name = "distinctCountProg", .prog = coevo.distinctCountProg() },
        .{ .name = "membership(S1)", .prog = membershipProg() },
        .{ .name = "noveltyflag(S2)", .prog = noveltyFlagProg() },
        .{ .name = "hashtbl", .prog = alien.alienHashTable() },
        .{ .name = "pk_add(rmw)", .prog = coevo.refSolver(.pk_add) },
    };
    for (cf_table) |row| {
        const fp = open.infoDescriptor(&row.prog, dseed);
        try out.print("             {s:<20} OUT_R-entropy={d:.3}  clean={s}\n", .{ row.name, fp[1], if (forge.clean(&row.prog, dseed)) "PASS" else "REJECTED" });
    }
}

// =============================================================================
// PHASE: probe — greedy climbs at equal total budget (the 0.862 -> ? question)
// =============================================================================

const NEIGH_EVALS: usize = 15_000;
const GREEDY_EVALS: usize = 15_000;
const N_CHAINS: usize = 8;
const N_POOL: usize = 2000;
const N_RUNGS: usize = 3;

const ProbeArm = enum { ctrl_agree, curriculum, mech_pure, mech_blend };

fn probeArmName(a: ProbeArm) []const u8 {
    return switch (a) {
        .ctrl_agree => "probe_ctrl_agree",
        .curriculum => "probe_curriculum",
        .mech_pure => "probe_mech_pure",
        .mech_blend => "probe_mech_blend",
    };
}

const RungScore = struct {
    hidden: []const alien.Program,
    arm: ProbeArm,
    stone: ?*const Stone, // curriculum: the current rung's oracle
};

fn rungScore(rs: *const RungScore, cand: *const alien.Program) f64 {
    return switch (rs.arm) {
        .ctrl_agree => agreeDistinct(rs.hidden, cand),
        .curriculum => stoneAgreement(rs.hidden, rs.stone.?, cand, MATCH_SEQ, MATCH_L, RESIDUAL_SEED),
        .mech_pure => mechScore(cand).m,
        .mech_blend => 0.5 * mechScore(cand).m + 0.5 * agreeDistinct(rs.hidden, cand),
    };
}

const ClimbOut = struct { prog: alien.Program, score: f64 };

/// One rung: neighbourhood scan around the seed point (1–2 edit copies; no drift),
/// then greedy climb (accept >=, neutral drift, track best-ever) from the scan's best.
fn climbRung(rng: std.Random, sp: *const alien.Params, rs: *const RungScore, start: alien.Program) ClimbOut {
    var best = start;
    var best_s = rungScore(rs, &start);
    for (0..NEIGH_EVALS) |_| {
        var cand = start;
        const nm = 1 + rng.uintLessThan(usize, 2);
        for (0..nm) |_| alien.mutate(rng, &cand, sp);
        const s = rungScore(rs, &cand);
        if (s > best_s) {
            best_s = s;
            best = cand;
        }
    }
    var cur = best;
    var cur_s = best_s;
    for (0..GREEDY_EVALS) |_| {
        var cand = cur;
        alien.mutate(rng, &cand, sp);
        const s = rungScore(rs, &cand);
        if (s >= cur_s) {
            cur = cand;
            cur_s = s;
            if (s > best_s) {
                best_s = s;
                best = cand;
            }
        }
    }
    return .{ .prog = best, .score = best_s };
}

fn runProbe(al: std.mem.Allocator, out: anytype, cw: anytype, seed: u64, hidden: []const alien.Program) !void {
    var sp = alien.Params{ .active_regs = 8 };
    const stones = ladderStones();

    try out.print("\n======== PROBE seed 0x{X} ========\n", .{seed});
    try out.print("budget per arm: {d} chains x {d} rungs x ({d} neigh + {d} greedy) evals\n", .{ N_CHAINS, N_RUNGS, NEIGH_EVALS, GREEDY_EVALS });

    // shared pool of random clean programs (one draw per seed, reused by all arms)
    const pool = try al.alloc(alien.Program, N_POOL);
    defer al.free(pool);
    {
        var prng = std.Random.DefaultPrng.init(seed ^ 0xD1A6);
        const rng = prng.random();
        var n: usize = 0;
        while (n < N_POOL) {
            const p = alien.randProg(rng, &sp);
            if (!forge.clean(&p, BATTERY_SEED)) continue;
            pool[n] = p;
            n += 1;
        }
    }

    const arms = [_]ProbeArm{ .ctrl_agree, .curriculum, .mech_pure, .mech_blend };
    for (arms) |arm| {
        var timer = try std.time.Timer.start();
        var prng = std.Random.DefaultPrng.init(seed ^ 0xC11B ^ @intFromEnum(arm));
        const rng = prng.random();

        // rung schedule: curriculum walks the ladder; every other arm repeats its
        // own criterion 3x (equal structure, equal total budget)
        var chains: [N_CHAINS]alien.Program = undefined;
        {
            // starts = top-N_CHAINS of the pool under the arm's FIRST-rung criterion
            var first_rs = RungScore{ .hidden = hidden, .arm = arm, .stone = &stones[0] };
            var scores: [N_CHAINS]f64 = .{-1.0} ** N_CHAINS;
            for (pool) |p| {
                const s = rungScore(&first_rs, &p);
                var mi: usize = 0;
                for (scores, 0..) |v, j| {
                    if (v < scores[mi]) mi = j;
                }
                if (s > scores[mi]) {
                    scores[mi] = s;
                    chains[mi] = p;
                }
            }
        }

        var final_best_agree: f64 = 0;
        for (0..N_RUNGS) |rung| {
            const rs = RungScore{
                .hidden = hidden,
                .arm = arm,
                .stone = if (arm == .curriculum) &stones[rung] else &stones[0],
            };
            var best_rung_score: f64 = -1;
            var best_rung_agree: f64 = 0;
            for (&chains) |*chain| {
                const res = climbRung(rng, &sp, &rs, chain.*);
                chain.* = res.prog;
                if (res.score > best_rung_score) best_rung_score = res.score;
                const ad = agreeDistinct(hidden, &res.prog);
                if (ad > best_rung_agree) best_rung_agree = ad;
                if (ad > final_best_agree) final_best_agree = ad;
            }
            const tgt_name = if (arm == .curriculum) stones[rung].name else "distinct";
            const ms = timer.read() / std.time.ns_per_ms;
            try out.print("  [{s}] rung {d} ({s}): best rung-score={d:.3}  best agree(distinct)={d:.3}\n", .{ probeArmName(arm), rung + 1, tgt_name, best_rung_score, best_rung_agree });
            try cw.print("probe,{s},0x{X},{d},{s},{d:.4},{d:.4},0,0,0,0,0,0,0,0,0,0,0,0,{d}\n", .{ probeArmName(arm), seed, rung + 1, tgt_name, best_rung_score, best_rung_agree, ms });
        }
        const ms = timer.read() / std.time.ns_per_ms;
        try out.print("  [{s}] FINAL best agree(distinct) = {d:.3}  ({s} 0.95 bar; plateau was 0.862)  [{d} ms]\n", .{ probeArmName(arm), final_best_agree, if (final_best_agree >= 0.95) "REACHES" else "BELOW", ms });
        try cw.print("probe,{s},0x{X},99,final,{d:.4},{d:.4},0,0,0,0,0,0,0,0,0,0,0,0,{d}\n", .{ probeArmName(arm), seed, final_best_agree, final_best_agree, ms });
    }
}

// =============================================================================
// PHASE: forge — aimed_promote-style promotion rounds, 3 arms
// =============================================================================

const ForgeArm = enum { ctrl, curr, mech };

/// GATE-POLISH (applied identically in ALL arms, so the levers stay isolated):
/// a bounded local-exploitation step at the promotion boundary. The forge round's
/// novelty archive is structurally biased against CONVERGING onto any one
/// behaviour (archive admission requires fingerprint distance > 0.12 from every
/// existing member, so refinements of an already-admitted behaviour are rejected
/// as "not new enough" — measured in the first no-polish forge run, where the
/// curriculum gate reached 0.906 agreement on S1 but could never reach 0.95).
/// Polish takes the arm's incumbent (best gate-score program seen so far, or the
/// current archive's best), runs a probe-style neighbourhood scan + greedy climb
/// on the arm's OWN gate signal, and offers the result to the census as ONE extra
/// candidate — which must still pass the clean-or-bypass filter, the depth-3
/// certifier, and the depth-4 promotion gate like everything else. Aim stays at
/// the selection boundary; the inner novelty loop is untouched.
const POLISH_CHAINS: usize = 8; // basins: incumbent, archive-best, 6x random-clean tops
const POLISH_NEIGH: usize = 15_000; // per chain (probe-matched: the config that reached 1.000)
const POLISH_GREEDY: usize = 15_000; // per chain
const LEN_GUARD: usize = 26; // neutral drift may not bloat past this (insert headroom)

fn polishChain(rng: std.Random, sp: *const alien.Params, ctx: *const Ctx, start: alien.Program) ClimbOut {
    var best = start;
    var best_s = ctxScore(ctx, &start);
    for (0..POLISH_NEIGH) |_| {
        var cand = start;
        const nm = 1 + rng.uintLessThan(usize, 2);
        for (0..nm) |_| alien.mutate(rng, &cand, sp);
        const s = ctxScore(ctx, &cand);
        if (s > best_s) {
            best_s = s;
            best = cand;
        }
    }
    var cur = best;
    var cur_s = best_s;
    for (0..POLISH_GREEDY) |_| {
        var cand = cur;
        alien.mutate(rng, &cand, sp);
        const s = ctxScore(ctx, &cand);
        // probe-exact neutral drift (`>=`), plus a headroom guard: ties may not
        // bloat past LEN_GUARD or insert-mutations degenerate into no-ops at the
        // MAX_INSTR cap and the climb stalls (both failure modes were measured
        // in earlier polish variants)
        if (s > cur_s or (s == cur_s and cand.len() <= LEN_GUARD)) {
            cur = cand;
            cur_s = s;
            if (s > best_s) {
                best_s = s;
                best = cand;
            }
        }
    }
    return .{ .prog = best, .score = best_s };
}

/// Multi-restart polish: one chain per basin, same total budget as one long climb.
/// Single-basin polish measurably locks onto a shelf (0.893 for 6 straight rounds
/// in the smoke run) while the 8-restart probe reaches 1.000 — basin diversity,
/// not raw evals, is what the climb needs.
fn polishRound(rng: std.Random, sp: *const alien.Params, ctx: *const Ctx, starts: []const alien.Program) ?ClimbOut {
    if (starts.len == 0) return null;
    var best: ?ClimbOut = null;
    for (starts) |st| {
        const r = polishChain(rng, sp, ctx, st);
        if (best == null or r.score > best.?.score) best = r;
    }
    return best;
}

fn forgeArmName(a: ForgeArm) []const u8 {
    return switch (a) {
        .ctrl => "forge_ctrl",
        .curr => "forge_curr",
        .mech => "forge_mech",
    };
}

const TState = struct {
    first_round: ?usize = null,
    wlen: usize = 0,
    witness: [DEPTH]usize = undefined,
    self_flip: bool = false,
};

const PromotedAtom = struct {
    prog: alien.Program,
    round: usize,
    prefix_len: usize,
};

fn runForgeArm(
    al: std.mem.Allocator,
    out: anytype,
    cw: anytype,
    arm: ForgeArm,
    seed: u64,
    hidden: []const alien.Program,
    pop: usize,
    gens: usize,
    max_rounds: usize,
) !void {
    const dseed = seed ^ 0x1F0;
    const fseed = seed +% 0xA70F;
    const stones = ladderStones();

    var atoms = forge.baseAtoms();
    var promoted = std.ArrayList(PromotedAtom).init(al);
    defer promoted.deinit();

    var tstate: [N_TARGETS]TState = .{TState{}} ** N_TARGETS;

    var stone_i: usize = if (arm == .curr) 0 else stones.len; // non-curr arms: family mode
    var incumbent: ?alien.Program = null;
    var incumbent_score: f64 = -1;

    try out.print("\n================ FORGE ARM {s}  SEED 0x{X} ================\n", .{ forgeArmName(arm), seed });
    try out.print("params: pop={d} gens={d} cert_depth={d} gate_depth={d} census_cap={d} rounds={d}\n", .{ pop, gens, DEPTH, GATE_DEPTH, CENSUS_CAP, max_rounds });

    // ---- round 0 baseline reachability ----
    var f_reach: usize = 0;
    var e_reach: usize = 0;
    for (SPECS, 0..) |spec, ti| {
        var wit: [DEPTH]usize = undefined;
        var wl: usize = 0;
        if (targetSolvable(hidden, spec.idxs, atoms.slice(), DEPTH, RSEED, &wit, &wl)) {
            tstate[ti].first_round = 0;
            tstate[ti].wlen = wl;
            tstate[ti].witness = wit;
            if (inSet(&F_IDX, ti)) f_reach += 1;
            if (inSet(&E_IDX, ti)) e_reach += 1;
        }
    }
    try out.print("[round 0] baseline: lib={d}  F {d}/{d}  E {d}/{d}\n", .{ atoms.len, f_reach, F_IDX.len, e_reach, E_IDX.len });
    try cw.print("forge,{s},0x{X},0,baseline,0,0,0,0,0,0,0,0,0,none,{d},{d},0,0,0\n", .{ forgeArmName(arm), seed, f_reach, e_reach });

    var total_self: usize = 0;
    var total_composed: usize = 0;
    var round: usize = 1;
    while (round <= max_rounds) : (round += 1) {
        var timer = try std.time.Timer.start();
        const lib_before = atoms.len;

        // curriculum: skip stones already composable from the current library
        var stone_event: []const u8 = "none";
        if (arm == .curr) {
            while (stone_i < stones.len) {
                var wit: [DEPTH]usize = undefined;
                var wl: usize = 0;
                if (stoneSolvableLib(hidden, &stones[stone_i], atoms.slice(), DEPTH, RSEED, &wit, &wl)) {
                    try out.print("[round {d}] stone {s} already composable at depth {d} -> advance\n", .{ round, stones[stone_i].name, wl });
                    stone_event = "compose_advance";
                    stone_i += 1;
                    incumbent_score = -1; // re-anchor incumbent quality on the new rung
                } else break;
            }
        }

        // which wall-family targets remain unsolved (family-mode aim set)
        var unsolved_buf: [WALL_IDX.len]usize = undefined;
        var n_unsolved: usize = 0;
        for (WALL_IDX) |ti| {
            if (tstate[ti].first_round == null) {
                unsolved_buf[n_unsolved] = ti;
                n_unsolved += 1;
            }
        }
        const unsolved_wall = unsolved_buf[0..n_unsolved];

        var ctx = Ctx{ .hidden = hidden, .mode = .family, .family = unsolved_wall };
        var target_name: []const u8 = "wall_family";
        switch (arm) {
            .curr => {
                if (stone_i < stones.len) {
                    ctx = .{ .hidden = hidden, .mode = .stone, .stone = stones[stone_i], .incumbent = incumbent };
                    target_name = stones[stone_i].name;
                } else {
                    ctx = .{ .hidden = hidden, .mode = .family, .family = unsolved_wall, .incumbent = incumbent };
                }
            },
            .mech => {
                ctx = .{ .hidden = hidden, .mode = .mech };
                target_name = "mech_M";
            },
            .ctrl => {},
        }

        var prng = std.Random.DefaultPrng.init(seed +% round *% 0x9E3779B97F4A7C15);
        var archive = try wallSearch(al, prng.random(), &ctx, .{ .pop = pop, .gens = gens }, dseed);
        defer archive.deinit();

        // ---- gate-polish (identical machinery in every arm; see comment above) ----
        var sp = alien.Params{ .active_regs = 8 };
        const prng_rng = prng.random();
        var starts_buf: [POLISH_CHAINS]alien.Program = undefined;
        var n_starts: usize = 0;
        if (incumbent) |inc| {
            starts_buf[n_starts] = inc;
            n_starts += 1;
        }
        { // this round's archive-best by gate (a fresh basin every round)
            var best_g: f64 = -1;
            var best_p: ?alien.Program = null;
            for (archive.items) |m| {
                const g = ctxScore(&ctx, &m.prog);
                if (g > best_g) {
                    best_g = g;
                    best_p = m.prog;
                }
            }
            if (best_p) |bp| {
                starts_buf[n_starts] = bp;
                n_starts += 1;
            }
        }
        while (n_starts < POLISH_CHAINS) { // random-clean tops (best of 1000 draws each)
            var best_g: f64 = -1;
            var best_p: alien.Program = undefined;
            var got: usize = 0;
            var draws: usize = 0;
            while (got < 1000 and draws < 10_000) : (draws += 1) {
                const p = alien.randProg(prng_rng, &sp);
                if (!forge.clean(&p, dseed)) continue;
                got += 1;
                const g = ctxScore(&ctx, &p);
                if (g > best_g) {
                    best_g = g;
                    best_p = p;
                }
            }
            if (best_g < 0) break;
            starts_buf[n_starts] = best_p;
            n_starts += 1;
        }
        const polish: ?ClimbOut = polishRound(prng_rng, &sp, &ctx, starts_buf[0..n_starts]);

        // Census admission = A1-A6 clean filter OR aim-evidence bypass.
        // MEASURED NECESSITY (selftest #6): the clean filter (OUT_R entropy > 0.30)
        // structurally REJECTS the whole saturating-counter family at V=4 —
        // including the exact distinctCountProg (0.269) and both stones (0.207).
        // Without a bypass, no arm could ever certify a distinct-family atom even
        // if the search found it. The bypass is symmetric across arms (each arm's
        // own gate signal: agreement >= 0.90 for behavioural aims, M >= 0.5 for
        // the mechanism arm) and every bypass admission is logged.
        const bypass_bar: f64 = if (arm == .mech) 0.5 else 0.90;
        var bypass_admits: usize = 0;
        var cleanlist = std.ArrayList(open.Member).init(al);
        defer cleanlist.deinit();
        for (archive.items) |m| {
            if (forge.clean(&m.prog, dseed)) {
                try cleanlist.append(m);
            } else if (ctxScore(&ctx, &m.prog) >= bypass_bar) {
                bypass_admits += 1;
                try cleanlist.append(m);
            }
        }
        std.mem.sort(open.Member, cleanlist.items, {}, struct {
            fn lt(_: void, a: open.Member, b: open.Member) bool {
                return a.prog.len() < b.prog.len();
            }
        }.lt);

        // census: certify at depth 3, rank certified candidates by the gate score.
        // The polish result enters as ONE extra candidate, same filters as all others.
        const CensusCand = struct { prog: alien.Program, gate: f64 };
        var cert = std.ArrayList(CensusCand).init(al);
        defer cert.deinit();
        const n_checked = @min(CENSUS_CAP, cleanlist.items.len);
        var best_agree_census: f64 = 0;
        for (cleanlist.items[0..n_checked]) |m| {
            const ad = agreeDistinct(hidden, &m.prog);
            if (ad > best_agree_census) best_agree_census = ad;
            if (!forge.reducibleLib(&m.prog, atoms.slice(), DEPTH, fseed)) {
                const g = ctxScore(&ctx, &m.prog);
                try cert.append(.{ .prog = m.prog, .gate = g });
            }
        }
        if (polish) |po| {
            const ad = agreeDistinct(hidden, &po.prog);
            if (ad > best_agree_census) best_agree_census = ad;
            const admit = forge.clean(&po.prog, dseed) or po.score >= bypass_bar;
            if (admit and !forge.reducibleLib(&po.prog, atoms.slice(), DEPTH, fseed)) {
                try cert.append(.{ .prog = po.prog, .gate = po.score });
            }
        }
        std.mem.sort(CensusCand, cert.items, {}, struct {
            fn lt(_: void, a: CensusCand, b: CensusCand) bool {
                if (a.gate != b.gate) return a.gate > b.gate; // highest gate first
                return a.prog.len() < b.prog.len(); // ties -> shorter
            }
        }.lt);

        // incumbent update (all arms: polish start of the next round; injection
        // source only in the curriculum arm, via ctx.incumbent)
        if (polish != null and polish.?.score > incumbent_score) {
            incumbent = polish.?.prog;
            incumbent_score = polish.?.score;
        }
        if (cert.items.len > 0 and cert.items[0].gate > incumbent_score) {
            incumbent = cert.items[0].prog;
            incumbent_score = cert.items[0].gate;
        }

        if (cert.items.len == 0 or atoms.len >= forge.MAX_ATOMS) {
            const ms = timer.read() / std.time.ns_per_ms;
            try out.print("[round {d}] target={s} archive={d} clean={d} checked={d} irreducible=0 -> FIXED POINT ({d} ms)\n", .{ round, target_name, archive.items.len, cleanlist.items.len, n_checked, ms });
            try cw.print("forge,{s},0x{X},{d},{s},0,{d:.4},{d},{d},{d},0,0,0,0,{s},{d},{d},0,0,{d}\n", .{ forgeArmName(arm), seed, round, target_name, best_agree_census, archive.items.len, cleanlist.items.len, n_checked, stone_event, f_reach, e_reach, ms });
            break;
        }

        // Stone-mode promotion bar: while a stone is open, the curriculum arm
        // promotes ONLY candidates that actually solve it (gate >= 0.95).
        // MEASURED NECESSITY (polish smoke run): promoting a 0.906 approximant
        // poisons the well — the next round's 0.920 refinement is then flagged
        // "reducible" by the 0.95 statistical matcher AGAINST THE APPROXIMANT
        // and can never enter the library. Family-mode rounds keep the plain
        // aimed_promote always-promote semantics.
        const in_stone_mode = (arm == .curr and stone_i < stones.len);

        // the settled +1-depth promotion gate: winner must survive depth-4
        var d4_rejects: usize = 0;
        var winner: ?CensusCand = null;
        for (cert.items, 0..) |c, ci| {
            if (ci >= 3) break; // up to 3 gate attempts per round
            if (in_stone_mode and c.gate < forge.MATCH_THRESHOLD) break; // no approximant promotion
            if (forge.reducibleLib(&c.prog, atoms.slice(), GATE_DEPTH, fseed)) {
                d4_rejects += 1;
                continue;
            }
            winner = c;
            break;
        }

        if (winner == null) {
            const ms = timer.read() / std.time.ns_per_ms;
            const why: []const u8 = if (in_stone_mode and (cert.items.len == 0 or cert.items[0].gate < forge.MATCH_THRESHOLD))
                "stone open, no certified candidate at the 0.95 bar"
            else
                "top candidates all REDUCED at gate depth";
            try out.print("[round {d}] target={s} irred={d} polish={d:.3} -> NO PROMOTION ({s}) ({d} ms)\n", .{ round, target_name, cert.items.len, if (polish) |po| po.score else -1.0, why, ms });
            try cw.print("forge,{s},0x{X},{d},{s},{d:.4},{d:.4},{d},{d},{d},{d},{d},0,0,{s},{d},{d},0,0,{d}\n", .{ forgeArmName(arm), seed, round, target_name, cert.items[0].gate, best_agree_census, archive.items.len, cleanlist.items.len, n_checked, cert.items.len, d4_rejects, stone_event, f_reach, e_reach, ms });
            continue;
        }

        const new_atom = winner.?.prog;
        const new_idx = atoms.len;
        atoms.appendAssumeCapacity(new_atom);
        try promoted.append(.{ .prog = new_atom, .round = round, .prefix_len = lib_before });

        // curriculum: did this promotion solve the current stone?
        if (arm == .curr and stone_i < stones.len) {
            const sa = stoneAgreement(hidden, &stones[stone_i], &new_atom, MATCH_SEQ, MATCH_L, RSEED);
            if (sa >= forge.MATCH_THRESHOLD) {
                try out.print("[round {d}] STONE SOLVED: {s} (promoted-atom agreement {d:.3}) -> advance\n", .{ round, stones[stone_i].name, sa });
                stone_event = "stone_solved";
                stone_i += 1;
                incumbent = new_atom;
                incumbent_score = -1;
            }
        }

        // battery re-measurement (full 18 targets)
        var new_f: usize = 0;
        var new_e: usize = 0;
        var new_self: usize = 0;
        var new_comp: usize = 0;
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
                if (is_self) new_self += 1 else new_comp += 1;
                if (inSet(&F_IDX, ti)) new_f += 1;
                if (inSet(&E_IDX, ti)) new_e += 1;
            }
        }
        f_reach += new_f;
        e_reach += new_e;
        total_self += new_self;
        total_composed += new_comp;

        const ms = timer.read() / std.time.ns_per_ms;
        try out.print("[round {d}] target={s} archive={d} clean={d} (bypass={d}) checked={d} irred={d} d4_rej={d} polish={d:.3} PROMOTE len={d} gate={d:.3} bestAgree={d:.3} -> lib={d} | F {d}/{d} E {d}/{d} (+F{d} +E{d}: {d} self {d} comp) ({d} ms)\n", .{
            round,             target_name,       archive.items.len, cleanlist.items.len, bypass_admits, n_checked, cert.items.len, d4_rejects,
            if (polish) |po| po.score else -1.0,  new_atom.len(),    winner.?.gate,       best_agree_census, atoms.len, f_reach,
            F_IDX.len,         e_reach,           E_IDX.len,         new_f,               new_e,         new_self,  new_comp,       ms,
        });
        try cw.print("forge,{s},0x{X},{d},{s},{d:.4},{d:.4},{d},{d},{d},{d},{d},1,{d},{s},{d},{d},{d},{d},{d}\n", .{
            forgeArmName(arm), seed, round, target_name, winner.?.gate, best_agree_census, archive.items.len, cleanlist.items.len, n_checked, cert.items.len, d4_rejects, new_atom.len(), stone_event, f_reach, e_reach, new_f, new_e, ms,
        });
    }

    // ---- per-target table ----
    try out.writeAll("\nheld-out battery (F = frontier, E = eval/transfer):\n");
    for (SPECS, 0..) |spec, ti| {
        const st = tstate[ti];
        const tag = if (inSet(&F_IDX, ti)) "F" else "E";
        const wall = if (inSet(&WALL_IDX, ti)) " [wall]" else "";
        const decoy = if (inSet(&DECOY_IDX, ti)) " [decoy]" else "";
        if (st.first_round) |r| {
            try out.print("  [{s}] {s:<20} round {d:>2}  [", .{ tag, spec.name, r });
            for (0..st.wlen) |j| {
                if (j > 0) try out.writeAll(",");
                try out.print("{d}", .{st.witness[j]});
            }
            try out.print("]{s}{s}{s}\n", .{ if (st.self_flip) "  (SELF)" else "  (COMPOSED)", wall, decoy });
        } else {
            try out.print("  [{s}] {s:<20}  never{s}{s}\n", .{ tag, spec.name, wall, decoy });
        }
    }

    if (arm == .curr) {
        try out.print("\nladder status: {d}/{d} stones passed (", .{ stone_i, stones.len });
        for (stones, 0..) |s, i| {
            if (i > 0) try out.writeAll(", ");
            try out.print("{s}={s}", .{ s.name, if (i < stone_i) "done" else "open" });
        }
        try out.writeAll(")\n");
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

    const flips = total_self + total_composed;
    try out.print("\narm {s} seed 0x{X} summary: lib {d}->{d}  F {d}/{d}  E {d}/{d}  flips self={d} composed={d} (self-rate={d:.1}%)  leaks={d}/{d}  redundant={d}/{d}\n", .{
        forgeArmName(arm),
        seed,
        forge.BASE_ATOMS,
        atoms.len,
        f_reach,
        F_IDX.len,
        e_reach,
        E_IDX.len,
        total_self,
        total_composed,
        if (flips > 0) 100.0 * @as(f64, @floatFromInt(total_self)) / @as(f64, @floatFromInt(flips)) else 0.0,
        leaks,
        promoted.items.len,
        redund,
        promoted.items.len,
    });
}

// =============================================================================
// main
// =============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const al = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(al);
    defer std.process.argsFree(al, args);
    if (args.len < 2) {
        try out.writeAll("usage: inv_wall selftest | probe <csv> [seed...] | forge <ctrl|curr|mech> <csv> [seed...] [--pop=N] [--gens=N] [--rounds=N]\n");
        return;
    }
    const mode = args[1];

    if (std.mem.eql(u8, mode, "selftest")) {
        try runSelftest(out);
        return;
    }

    var seeds = std.ArrayList(u64).init(al);
    defer seeds.deinit();
    var pop: usize = 90;
    var gens: usize = 45;
    var rounds: usize = 10;

    if (std.mem.eql(u8, mode, "probe")) {
        if (args.len < 3) {
            try out.writeAll("usage: inv_wall probe <csv> [seed...]\n");
            return;
        }
        for (args[3..]) |a| try seeds.append(try std.fmt.parseInt(u64, a, 0));
        if (seeds.items.len == 0) {
            try seeds.append(0xA70F);
            try seeds.append(0x5EED2);
        }
        const csv = try openCsv(args[2]);
        defer csv.close();
        const cw = csv.writer();
        const hidden = buildHidden();
        for (seeds.items) |s| try runProbe(al, out, cw, s, &hidden);
        return;
    }

    if (std.mem.eql(u8, mode, "forge")) {
        if (args.len < 4) {
            try out.writeAll("usage: inv_wall forge <ctrl|curr|mech> <csv> [seed...] [--pop=N] [--gens=N] [--rounds=N]\n");
            return;
        }
        const arm: ForgeArm = if (std.mem.eql(u8, args[2], "ctrl"))
            .ctrl
        else if (std.mem.eql(u8, args[2], "curr"))
            .curr
        else if (std.mem.eql(u8, args[2], "mech"))
            .mech
        else {
            try out.writeAll("unknown arm (want ctrl|curr|mech)\n");
            return;
        };
        for (args[4..]) |a| {
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
        const csv = try openCsv(args[3]);
        defer csv.close();
        const cw = csv.writer();
        const hidden = buildHidden();
        for (seeds.items) |s| try runForgeArm(al, out, cw, arm, s, &hidden, pop, gens, rounds);
        return;
    }

    try out.writeAll("unknown mode\n");
}
