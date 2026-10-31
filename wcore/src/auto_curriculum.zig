//! AUTO-CURRICULUM: can BULK PARALLEL PROPOSAL discover a stepping-stone
//! decomposition for the distinct-count conjunction wall, with NO human-given
//! stones? (round 2026-07-10d headline experiment)
//!
//! Predecessor: `inv_wall.zig` (round 2026-07-10c) crossed the wall (f_reach
//! 0/9 -> 6/9) but ONLY with a HAND-DESIGNED two-rung curriculum
//! (S1 "membership" -> S2 "noveltyflag" -> distinct), whose stones were
//! written by a human who already knew the target mechanism (seen-flag load,
//! flag store, invert, accumulate, emit). Round c named auto-discovering that
//! decomposition as "the next frontier."
//!
//! THE TEST: replace the hand stones with a fully mechanism-agnostic
//! generate-and-filter loop. Every round:
//!   1. GENERATE many candidate intermediate behaviours, bulk/parallel, from
//!      two mechanism-blind sources:
//!        (a) fresh uniformly-random short programs (`alien.randProg`, the
//!            SAME proposer every arm in this arc uses — no load/store bias,
//!            no hint that memory ops matter);
//!        (b) every PROPER PREFIX of every member of this round's ordinary
//!            novelty+residual archive (`familySearch`, the exact ctrl-arm
//!            search ported from `inv_wall.zig`). Prefixing is a fully
//!            generic operation on ANY straight-line program (truncate the
//!            per-position instruction list) — it does not "know" the
//!            distinct-count mechanism is a 5-instruction chain, it just
//!            tries every cut point of whatever the ordinary search found.
//!            (Selftest #1 below confirms this operation IS expressive
//!            enough: applied to the real 5-instruction mechanism it exactly
//!            reproduces S1/S2 from round c — the representation can express
//!            the human answer. Whether BLIND bulk sampling ever LANDS on a
//!            program whose prefixes look like that is the empirical
//!            question this file answers.)
//!   2. FILTER each candidate through two mechanism-blind tests:
//!        (a) CLIMBABLE / CERTIFIABLE: not yet reducible from the current
//!            atom library at the settled +1-depth promotion gate (depth 3
//!            AND depth 4) — literally "would `aimed_promote` be willing to
//!            promote this," the exact bar every other arm in this arc uses.
//!        (b) PAYOFF: hypothetically append the candidate to the atom
//!            library and re-run the real reachability check
//!            (`targetSolvable`, depth <= 3) against every currently-unsolved
//!            member of the WALL family (distinct-count + its 6 hidden
//!            compositions, the same `WALL_IDX` as `inv_wall.zig`). If >= 1
//!            newly composable, the candidate is kept.
//!   3. If >= 1 candidate survives both filters, PROMOTE the best one for
//!      real (this is the auto-discovered stone) and log `auto_discovered`.
//!      Otherwise fall back to the plain ctrl-arm promotion (same archive,
//!      same census, same gate-polish) so every round still grows the
//!      library — the auto-loop is a strict superset of ctrl: if it NEVER
//!      finds a stone, its frontier reach must equal ctrl's (a built-in
//!      falsifiability check on this file's own correctness).
//!   4. Sweep the BULK parameter (how many fresh random candidates per round,
//!      source (a) above) to find whether there is a quantity threshold
//!      where discovery becomes reliable, or whether it never triggers.
//!
//! GENUINENESS CHECK: the hand-designed stones (`membershipProg`,
//! `noveltyFlagProg`) are ported here TOO, but used ONLY after a promotion,
//! to REPORT the discovered stone's behavioural agreement with them. They
//! are NEVER consulted by the generator, the certify test, or the payoff
//! test — the search cannot see them and cannot be steered toward them.
//!
//! Build: cd wcore && zig build-exe -O ReleaseFast src/auto_curriculum.zig -femit-bin=bin/auto_curriculum
//! Run:   ./bin/auto_curriculum selftest
//!        ./bin/auto_curriculum run <bulk> ../results/auto_curriculum_2026_07_10.csv [seed...] [--pop=][--gens=][--rounds=]
//! Single-threaded, deterministic given the seed list. CSV opens in APPEND
//! mode so multiple bulk sweeps share one results file.

const std = @import("std");
const alien = @import("inv_alien.zig");
const coevo = @import("inv_coevo.zig");
const open = @import("inv_open.zig");
const forge = @import("inv_atomforge.zig");
const fr = @import("inv_frontier.zig");

const V: usize = alien.CANON_BASE;
const DEPTH: usize = forge.COMPOSE_DEPTH; // production certifier / payoff depth = 3
const GATE_DEPTH: usize = DEPTH + 1; // the settled +1-depth promotion gate = 4
const CENSUS_CAP: usize = 80;
const MATCH_SEQ: usize = 8;
const MATCH_L: usize = 28;
const RSEED: u64 = 0x0F17ED; // reachability-check seed (same as inv_wall/inv_aimed/inv_iterate)
const BATTERY_SEED: u64 = 0xBA77E71; // battery-definition seed (same)
const RESIDUAL_SEED: u64 = 0x2E51DA1; // residual seed (same as inv_wall/inv_aimed)

// =============================================================================
// Battery (ported verbatim from inv_wall.zig — private there, so re-derived
// here from the same public primitives — so results are apples-to-apples)
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
/// (hashtbl/union deliberately EXCLUDED, same convention as inv_wall.zig, so
/// the loop cannot spend its budget/credit on the already-climbable half).
const WALL_IDX = [_]usize{ 0, 8, 9, 10, 12, 13, 14 };

fn inSet(set: []const usize, x: usize) bool {
    for (set) |v| if (v == x) return true;
    return false;
}

// =============================================================================
// Ported comparison / solvability primitives (private in inv_wall.zig)
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

/// True iff `t_idxs` (into `hidden`) is composable from `lib` at depth <= max_depth.
fn targetSolvable(
    hidden: []const alien.Program,
    t_idxs: []const usize,
    lib: []const alien.Program,
    max_depth: usize,
    seed: u64,
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
                return true;
            }
        }
    }
    return false;
}

// =============================================================================
// Hand-designed ladder stones — VERIFICATION-ONLY.
// These are ported from inv_wall.zig so the genuineness check has a fixed,
// independent oracle. They are NEVER used to generate candidates, NEVER used
// as fitness, and NEVER used in the certify/payoff tests below — only in
// `genuineness()`, called AFTER a promotion decision has already been made.
// =============================================================================

fn membershipProg() alien.Program {
    var p = alien.Program{};
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 6, .imm = 1 });
    p.step.appendAssumeCapacity(.{ .op = .a_load, .a = 0, .out = 3 });
    p.step.appendAssumeCapacity(.{ .op = .a_store, .a = 0, .b = 6 });
    return p;
}

fn noveltyFlagProg() alien.Program {
    var p = alien.Program{};
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 6, .imm = 1 });
    p.step.appendAssumeCapacity(.{ .op = .a_load, .a = 0, .out = 3 });
    p.step.appendAssumeCapacity(.{ .op = .a_store, .a = 0, .b = 6 });
    p.step.appendAssumeCapacity(.{ .op = .a_xor, .a = 3, .b = 6, .out = 3 });
    return p;
}

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

/// Behavioural agreement between an arbitrary candidate program and an arbitrary
/// oracle program (used only for the post-hoc genuineness report).
fn progAgreement(a: *const alien.Program, b: *const alien.Program, n: usize, L: usize, seed: u64) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var out_a: [256]u8 = undefined;
    var out_b: [256]u8 = undefined;
    var agree: usize = 0;
    var total: usize = 0;
    for (0..n) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        var ca = a.*;
        var cb = b.*;
        alien.runStream(&ca, syms[0..L], out_a[0..L]);
        alien.runStream(&cb, syms[0..L], out_b[0..L]);
        for (0..L) |i| {
            total += 1;
            if (out_a[i] == out_b[i]) agree += 1;
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total));
}

const Genuineness = struct { agree_s1: f64, agree_s2: f64 };

fn genuineness(cand: *const alien.Program) Genuineness {
    var s1 = membershipProg();
    var s2 = noveltyFlagProg();
    return .{
        .agree_s1 = progAgreement(cand, &s1, MATCH_SEQ, MATCH_L, RESIDUAL_SEED),
        .agree_s2 = progAgreement(cand, &s2, MATCH_SEQ, MATCH_L, RESIDUAL_SEED),
    };
}

// =============================================================================
// Family residual (mechanism-blind: best depth-1 agreement vs the CURRENTLY
// UNSOLVED wall family — the same signal the ctrl arm of inv_wall.zig uses)
// =============================================================================

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

fn agreeDistinct(hidden: []const alien.Program, cand: *const alien.Program) f64 {
    var single = [1]alien.Program{cand.*};
    const zero_idx = [_]usize{0};
    return chainAgreement(hidden, SPECS[0].idxs, single[0..1], &zero_idx, MATCH_SEQ, MATCH_L, RESIDUAL_SEED);
}

// =============================================================================
// familySearch — the ordinary ctrl-arm forge search (ported from inv_wall.zig's
// wallSearch, family mode only, no stone/mech ctx, no incumbent injection).
// This is the "diverse forge output" source: mechanism-blind novelty+residual
// evolutionary search, identical to what every arm in this arc already uses.
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

const SearchParams = struct {
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

fn familySearch(
    al: std.mem.Allocator,
    rng: std.Random,
    hidden: []const alien.Program,
    unsolved: []const usize,
    p: SearchParams,
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
    for (pop) |*m| {
        m.prog = alien.randProg(rng, &sp);
        m.fp = open.infoDescriptor(&m.prog, dseed);
        m.residual = familyResidual(hidden, unsolved, &m.prog);
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
            c.fp = open.infoDescriptor(&c.prog, dseed);
            c.residual = familyResidual(hidden, unsolved, &c.prog);
        }
        @memcpy(pop, next);
        al.free(next);
    }
    return archive;
}

// =============================================================================
// Gate-polish (ported from inv_wall.zig, family-residual only) — used ONLY in
// the ctrl-equivalent fallback path, to keep that baseline faithful to the
// measured ctrl arm (apples-to-apples "what if no stone is ever found").
// =============================================================================

// NOTE (compute-budget deviation, documented in auto_curriculum.md): inv_wall.zig's
// ctrl arm used POLISH_CHAINS=8 x (NEIGH=15000+GREEDY=15000) for full fidelity to
// round c. That is the dominant per-round cost here (measured ~50-90s/round) and
// this file needs headroom for the NEW bulk candidate-pool cert/payoff cost on top
// of it, across a bulk sweep, within the 15-min-per-run cap. The fallback path's
// exact strength does not affect the auto-discovery test itself (discovery never
// touches gate-polish); it only affects the ctrl-equivalent baseline's own E-transfer
// bookkeeping. Reduced 5x/2x here (same budget in EVERY bulk arm, so the bulk
// comparison stays apples-to-apples internally); round c's own ctrl numbers (0/9 F,
// reproduced under full budget) remain the external reference point.
const POLISH_CHAINS: usize = 4;
const POLISH_NEIGH: usize = 3_000;
const POLISH_GREEDY: usize = 3_000;
const LEN_GUARD: usize = 26;

const ClimbOut = struct { prog: alien.Program, score: f64 };

fn polishChain(rng: std.Random, sp: *const alien.Params, hidden: []const alien.Program, unsolved: []const usize, start: alien.Program) ClimbOut {
    var best = start;
    var best_s = familyResidual(hidden, unsolved, &start);
    for (0..POLISH_NEIGH) |_| {
        var cand = start;
        const nm = 1 + rng.uintLessThan(usize, 2);
        for (0..nm) |_| alien.mutate(rng, &cand, sp);
        const s = familyResidual(hidden, unsolved, &cand);
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
        const s = familyResidual(hidden, unsolved, &cand);
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

fn polishRound(rng: std.Random, sp: *const alien.Params, hidden: []const alien.Program, unsolved: []const usize, starts: []const alien.Program) ?ClimbOut {
    if (starts.len == 0) return null;
    var best: ?ClimbOut = null;
    for (starts) |st| {
        const r = polishChain(rng, sp, hidden, unsolved, st);
        if (best == null or r.score > best.?.score) best = r;
    }
    return best;
}

// =============================================================================
// NEW — the auto-decomposition machinery.
// =============================================================================

/// Generic straight-line-program prefix: same `setup`, `step` truncated to the
/// first `k` instructions. Well-defined for ANY program (a later instruction
/// can only depend on earlier machine state, never the reverse), and it does
/// NOT know anything about distinct-count — it is applied identically to
/// every archive member, whatever behaviour that member happens to compute.
fn stepPrefix(p: *const alien.Program, k: usize) alien.Program {
    var np = alien.Program{ .setup = p.setup, .step = .{} };
    const src = p.step.slice();
    const kk = @min(k, src.len);
    for (0..kk) |i| np.step.appendAssumeCapacity(src[i]);
    return np;
}

const MAX_POOL: usize = 6000;

/// Build this round's candidate pool: every proper prefix of every archive
/// member (source B, "diverse forge output"), plus `n_random` fresh uniformly-
/// random short programs (source A, the bulk sweep parameter). Capped at
/// MAX_POOL for compute safety (archive-prefix count is naturally bounded by
/// archive size; only large `n_random` can hit the cap).
fn buildCandidatePool(
    rng: std.Random,
    sp: *const alien.Params,
    archive: []const open.Member,
    n_random: usize,
    pool: *std.ArrayList(alien.Program),
) !void {
    for (archive) |m| {
        const slen = m.prog.step.len;
        var k: usize = 1;
        while (k <= slen and pool.items.len < MAX_POOL) : (k += 1) {
            try pool.append(stepPrefix(&m.prog, k));
        }
    }
    var n: usize = 0;
    while (n < n_random and pool.items.len < MAX_POOL) : (n += 1) {
        try pool.append(alien.randProg(rng, sp));
    }
}

/// (a) CLIMBABLE / CERTIFIABLE, depth-3 half: genuinely new (not reducible from
/// the current library at the production certifier depth). Cost O(n^3) — the
/// cheap half of the gate, applied to the FULL bulk pool.
fn certifiableDepth3(cand: *const alien.Program, atoms: []const alien.Program, fseed: u64) bool {
    return !forge.reducibleLib(cand, atoms, DEPTH, fseed);
}

/// (a) CLIMBABLE / CERTIFIABLE, depth-4 half: survives the settled +1-depth
/// promotion gate too. Cost O(n^4) — the expensive half. Called ONLY on
/// candidates that already passed depth-3 AND have nonzero payoff (below),
/// which is a small fraction of the pool by construction (finding a stone is
/// rare) — this is what keeps the bulk sweep computationally tractable: the
/// O(n^4) cost is paid a handful of times per round, not `bulk` times.
fn certifiableDepth4(cand: *const alien.Program, atoms: []const alien.Program, fseed: u64) bool {
    return !forge.reducibleLib(cand, atoms, GATE_DEPTH, fseed);
}

const PayoffResult = struct {
    count: usize,
    hits: [WALL_IDX.len]usize = undefined, // absolute SPECS indices unlocked
};

/// True iff `idxs[0..d]` includes `new_idx` at least one position.
fn includesIdx(idxs: []const usize, new_idx: usize) bool {
    for (idxs) |v| if (v == new_idx) return true;
    return false;
}

/// (b) PAYOFF: hypothetically add `cand` to the library (appended at index
/// `new_idx = atoms.len`); how many currently-unsolved WALL members become
/// composable at depth <= 3? OPTIMIZED: `unsolved` is unsolved using `atoms`
/// ALONE (precondition upheld by the caller), so any depth<=3 combo that does
/// NOT touch `new_idx` is already known false — skip the (expensive) agreement
/// check for those combos instead of re-deriving a result we already know.
/// Measured necessity: at library size ~15, combos NOT touching the new atom
/// are ~80% of the (n+1)^3 enumeration — this is the difference between a
/// tractable and an intractable bulk sweep at the settled 15-min-per-run cap.
fn payoffTest(
    hidden: []const alien.Program,
    atoms: []const alien.Program,
    cand: *const alien.Program,
    unsolved: []const usize,
) PayoffResult {
    var trial = forge.AtomLib{};
    for (atoms) |a| trial.appendAssumeCapacity(a);
    trial.appendAssumeCapacity(cand.*);
    const lib = trial.slice();
    const new_idx = atoms.len;
    var res = PayoffResult{ .count = 0 };
    for (unsolved) |ti| {
        if (targetSolvableNew(hidden, SPECS[ti].idxs, lib, new_idx, DEPTH, RSEED)) {
            res.hits[res.count] = ti;
            res.count += 1;
        }
    }
    return res;
}

/// Like `targetSolvable`, but skips any depth<=max_depth combo that does not
/// include `new_idx` at least once (see `payoffTest` doc for why this is safe).
fn targetSolvableNew(
    hidden: []const alien.Program,
    t_idxs: []const usize,
    lib: []const alien.Program,
    new_idx: usize,
    max_depth: usize,
    seed: u64,
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
            if (!includesIdx(idxs[0..d], new_idx)) continue;
            if (chainAgreement(hidden, t_idxs, lib, idxs[0..d], MATCH_SEQ, MATCH_L, seed) >= forge.MATCH_THRESHOLD) {
                return true;
            }
        }
    }
    return false;
}

const FoundStone = struct {
    prog: alien.Program,
    payoff: usize,
    len: usize,
    hits: [WALL_IDX.len]usize,
    n_hits: usize,
};

/// Run the bulk generate-and-filter step once for a round. Returns the best
/// discovered stone (if any) by (payoff desc, length asc).
///
/// COST-ORDERED PIPELINE (cheapest filter first, so the O(n^4) gate check only
/// ever runs on the rare survivors, not on the full bulk pool):
///   1. certifiableDepth3 (O(n^3))          — the full pool pays this.
///   2. payoffTest, new-atom-only (O(n^2)ish) — only depth-3 survivors pay this.
///   3. certifiableDepth4 (O(n^4))          — only payoff-positive candidates
///      pay this (empirically a handful per round, often zero).
/// This is a pure performance reordering: a candidate is still required to
/// pass BOTH depth-3 and depth-4 irreducibility AND have payoff>0 to be kept —
/// nothing about what counts as a discovered stone has changed.
fn discoverStone(
    al: std.mem.Allocator,
    hidden: []const alien.Program,
    atoms: []const alien.Program,
    unsolved: []const usize,
    pool: []const alien.Program,
    fseed: u64,
    n_d3: *usize,
    n_payoff_pos: *usize,
    n_certified: *usize,
) !?FoundStone {
    _ = al;
    var best: ?FoundStone = null;
    var cnt_d3: usize = 0;
    var cnt_payoff: usize = 0;
    var cnt_cert: usize = 0;
    for (pool) |cand| {
        if (!certifiableDepth3(&cand, atoms, fseed)) continue;
        cnt_d3 += 1;
        const pr = payoffTest(hidden, atoms, &cand, unsolved);
        if (pr.count == 0) continue;
        cnt_payoff += 1;
        if (!certifiableDepth4(&cand, atoms, fseed)) continue;
        cnt_cert += 1;
        const cl = cand.len();
        const better = if (best) |b| (pr.count > b.payoff or (pr.count == b.payoff and cl < b.len)) else true;
        if (better) {
            best = .{ .prog = cand, .payoff = pr.count, .len = cl, .hits = pr.hits, .n_hits = pr.count };
        }
    }
    n_d3.* = cnt_d3;
    n_payoff_pos.* = cnt_payoff;
    n_certified.* = cnt_cert;
    return best;
}

// =============================================================================
// CSV plumbing
// =============================================================================

const CSV_HEADER = "bulk,seed,round,pool_size,n_d3,n_payoff_pos,n_certified,n_stones_considered,best_payoff,event,promoted_len,agree_s1,agree_s2,f_reach,e_reach,new_f,new_e,ms\n";

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
// PHASE: selftest
// =============================================================================

fn runSelftest(out: anytype) !void {
    var prng = std.Random.DefaultPrng.init(0x7E57);
    const rng = prng.random();
    var syms: [64]u8 = undefined;
    var a: [64]u8 = undefined;
    var b: [64]u8 = undefined;

    // 1a. The prefix operation, applied to a program that routes its early
    //     instructions THROUGH the output register (r3/OUT_R) directly (the
    //     hand-designed noveltyFlagProg does this by construction: its own
    //     first two instructions ARE membershipProg), exactly reproduces the
    //     shorter rung. This confirms stepPrefix is well-formed and CAN
    //     express a ladder when register wiring routes through OUT_R early.
    var nfp = noveltyFlagProg();
    const pre2 = stepPrefix(&nfp, 2);
    var ok1 = true;
    for (0..200) |_| {
        for (&syms) |*s| s.* = @intCast(rng.uintLessThan(usize, V));
        refMembership(&syms, &a);
        var p2 = pre2;
        alien.runStream(&p2, &syms, &b);
        for (0..64) |i| if (a[i] % V != b[i]) {
            ok1 = false;
        };
    }
    try out.print("[selftest] stepPrefix(noveltyFlagProg,2) == membership reference: {s}\n", .{if (ok1) "PASS" else "FAIL"});

    // 1b. HONEST CAVEAT, discovered while writing this selftest: the TRUE
    //     hidden mechanism (`coevo.distinctCountProg`) does NOT route through
    //     OUT_R until its LAST instruction (it accumulates through r8/r7 and
    //     only `mov`s to r3 at the end) — so naively prefixing THE EXACT
    //     hidden program does NOT reveal S1/S2; every proper prefix is
    //     constant-zero on OUT_R. Prefixing only surfaces a useful stone when
    //     the archived/random candidate happens to wire an EARLY instruction
    //     straight to the output register — a real, additional bottleneck for
    //     bulk discovery beyond "contains the right instructions in the right
    //     order." Demonstrated here, not asserted:
    var dc = coevo.distinctCountProg();
    var dc_pre2 = stepPrefix(&dc, 2);
    var dc_pre3 = stepPrefix(&dc, 3);
    var all_zero_2 = true;
    var all_zero_3 = true;
    for (0..64) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
    alien.runStream(&dc_pre2, &syms, &b);
    for (0..64) |i| if (b[i] != 0) {
        all_zero_2 = false;
    };
    alien.runStream(&dc_pre3, &syms, &b);
    for (0..64) |i| if (b[i] != 0) {
        all_zero_3 = false;
    };
    try out.print("[selftest] stepPrefix(distinctCountProg,2/3) constant-zero on OUT_R (the real mechanism hides behind r8 until its last mov): k=2 {s}  k=3 {s}\n", .{ if (all_zero_2) "constant-0 (as expected)" else "non-trivial", if (all_zero_3) "constant-0 (as expected)" else "non-trivial" });

    // 2. Baseline wall reachability from base atoms alone == 0/7 (reproduces
    //    round c's control).
    const hidden = buildHidden();
    const atoms0 = forge.baseAtoms();
    var wall_reach: usize = 0;
    for (WALL_IDX) |ti| {
        if (targetSolvable(&hidden, SPECS[ti].idxs, atoms0.slice(), DEPTH, RSEED)) wall_reach += 1;
    }
    try out.print("[selftest] baseline WALL reachability (base atoms only) = {d}/{d} (expect 0)\n", .{ wall_reach, WALL_IDX.len });

    // 3. The trap, quantified through THIS file's own certify/payoff pipeline:
    //    membership ALONE must certify (genuinely new) but have ZERO payoff;
    //    noveltyflag ALONE must certify AND have nonzero payoff. This is the
    //    exact "S1 insufficient, S2 sufficient" fact from round c, re-derived
    //    from scratch through the auto-loop's own instruments (not asserted).
    var mem_p = membershipProg();
    var nov_p = noveltyFlagProg();
    const fseed: u64 = 0xA70F +% 0xA70F;
    const cert_mem = certifiableDepth3(&mem_p, atoms0.slice(), fseed) and certifiableDepth4(&mem_p, atoms0.slice(), fseed);
    const cert_nov = certifiableDepth3(&nov_p, atoms0.slice(), fseed) and certifiableDepth4(&nov_p, atoms0.slice(), fseed);
    const pay_mem = payoffTest(&hidden, atoms0.slice(), &mem_p, &WALL_IDX);
    const pay_nov = payoffTest(&hidden, atoms0.slice(), &nov_p, &WALL_IDX);
    try out.print("[selftest] membership(S1):  certifiable={s}  payoff={d}/{d} (expect certifiable, payoff=0 -- necessary but insufficient)\n", .{ if (cert_mem) "yes" else "no", pay_mem.count, WALL_IDX.len });
    try out.print("[selftest] noveltyflag(S2): certifiable={s}  payoff={d}/{d} (expect certifiable, payoff>=1 -- the sufficient stone)\n", .{ if (cert_nov) "yes" else "no", pay_nov.count, WALL_IDX.len });

    // 4. Genuineness instrument sanity: noveltyflag vs itself = 1.0, vs
    //    membership = 0.0 (behavioural complements, same fact round c measured).
    const gs = genuineness(&nov_p);
    try out.print("[selftest] genuineness(noveltyflag): agree_s1={d:.3} (expect ~0.000) agree_s2={d:.3} (expect 1.000, it IS s2)\n", .{ gs.agree_s1, gs.agree_s2 });

    try out.writeAll("[selftest] agreeDistinct/familyResidual sanity: distinctCountProg vs its own oracle:\n");
    const self_agree = agreeDistinct(&hidden, &dc);
    try out.print("             {d:.3} (expect 1.000)\n", .{self_agree});
}

// =============================================================================
// PHASE: run — the auto-curriculum loop
// =============================================================================

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
    kind: []const u8, // "auto_discovered" | "fallback"
};

fn runAutoLoop(
    al: std.mem.Allocator,
    out: anytype,
    cw: anytype,
    seed: u64,
    hidden: []const alien.Program,
    bulk: usize,
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

    try out.print("\n================ AUTO-CURRICULUM  bulk={d}  seed=0x{X} ================\n", .{ bulk, seed });
    try out.print("params: pop={d} gens={d} cert_depth={d} gate_depth={d} rounds={d}\n", .{ pop, gens, DEPTH, GATE_DEPTH, max_rounds });

    // ---- round 0 baseline ----
    var f_reach: usize = 0;
    var e_reach: usize = 0;
    for (SPECS, 0..) |spec, ti| {
        if (targetSolvable(hidden, spec.idxs, atoms.slice(), DEPTH, RSEED)) {
            tstate[ti].first_round = 0;
            if (inSet(&F_IDX, ti)) f_reach += 1;
            if (inSet(&E_IDX, ti)) e_reach += 1;
        }
    }
    try out.print("[round 0] baseline: lib={d}  F {d}/{d}  E {d}/{d}\n", .{ atoms.len, f_reach, F_IDX.len, e_reach, E_IDX.len });
    try cw.print("{d},0x{X},0,0,0,0,0,0,0,baseline,0,0,0,{d},{d},0,0,0\n", .{ bulk, seed, f_reach, e_reach });

    var total_self: usize = 0;
    var total_composed: usize = 0;
    var round: usize = 1;
    while (round <= max_rounds) : (round += 1) {
        var timer = try std.time.Timer.start();

        var unsolved_buf: [WALL_IDX.len]usize = undefined;
        var n_unsolved: usize = 0;
        for (WALL_IDX) |ti| {
            if (tstate[ti].first_round == null) {
                unsolved_buf[n_unsolved] = ti;
                n_unsolved += 1;
            }
        }
        const unsolved_wall = unsolved_buf[0..n_unsolved];

        if (n_unsolved == 0 or atoms.len >= forge.MAX_ATOMS) {
            try out.print("[round {d}] wall family fully reached or atom cap hit -> stop\n", .{round});
            break;
        }

        // ---- 1. the ordinary ctrl-equivalent search (diverse forge output) ----
        var prng = std.Random.DefaultPrng.init(seed +% round *% 0x9E3779B97F4A7C15);
        const rng = prng.random();
        var archive = try familySearch(al, rng, hidden, unsolved_wall, .{ .pop = pop, .gens = gens }, dseed);
        defer archive.deinit();

        // ---- 2. bulk candidate pool: archive prefixes + n_random fresh draws ----
        var sp = alien.Params{ .active_regs = 8 };
        var pool = std.ArrayList(alien.Program).init(al);
        defer pool.deinit();
        try buildCandidatePool(rng, &sp, archive.items, bulk, &pool);

        // ---- 3. filter: certify + payoff, mechanism-blind ----
        var n_d3: usize = 0;
        var n_payoff_pos: usize = 0;
        var n_certified: usize = 0;
        const found = try discoverStone(al, hidden, atoms.slice(), unsolved_wall, pool.items, fseed, &n_d3, &n_payoff_pos, &n_certified);

        var event: []const u8 = "none";
        var promoted_len: usize = 0;
        var agree_s1: f64 = -1;
        var agree_s2: f64 = -1;
        var best_payoff: usize = 0;

        if (found) |fs| {
            // ---- AUTO-DISCOVERED: promote for real ----
            best_payoff = fs.payoff;
            const new_atom = fs.prog;
            atoms.appendAssumeCapacity(new_atom);
            try promoted.append(.{ .prog = new_atom, .round = round, .prefix_len = atoms.len - 1, .kind = "auto_discovered" });
            event = "auto_discovered";
            promoted_len = fs.len;
            const g = genuineness(&new_atom);
            agree_s1 = g.agree_s1;
            agree_s2 = g.agree_s2;
            try out.print("[round {d}] AUTO-DISCOVERED stone: len={d} payoff={d}/{d} agree_s1={d:.3} agree_s2={d:.3}\n", .{ round, fs.len, fs.payoff, unsolved_wall.len, agree_s1, agree_s2 });
            try out.writeAll("  program:\n");
            var wp = new_atom;
            try alien.writeProgram(&wp, out);
        } else {
            // ---- FALLBACK: plain ctrl-arm promotion from the same archive ----
            var cleanlist = std.ArrayList(open.Member).init(al);
            defer cleanlist.deinit();
            var bypass_admits: usize = 0;
            for (archive.items) |m| {
                if (forge.clean(&m.prog, dseed)) {
                    try cleanlist.append(m);
                } else if (familyResidual(hidden, unsolved_wall, &m.prog) >= 0.90) {
                    bypass_admits += 1;
                    try cleanlist.append(m);
                }
            }
            std.mem.sort(open.Member, cleanlist.items, {}, struct {
                fn lt(_: void, x: open.Member, y: open.Member) bool {
                    return x.prog.len() < y.prog.len();
                }
            }.lt);

            var starts_buf: [POLISH_CHAINS]alien.Program = undefined;
            var n_starts: usize = 0;
            {
                var best_g: f64 = -1;
                var best_p: ?alien.Program = null;
                for (archive.items) |m| {
                    const g = familyResidual(hidden, unsolved_wall, &m.prog);
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
            while (n_starts < POLISH_CHAINS) {
                var best_g: f64 = -1;
                var best_p: alien.Program = undefined;
                var got: usize = 0;
                var draws: usize = 0;
                while (got < 1000 and draws < 10_000) : (draws += 1) {
                    const p = alien.randProg(rng, &sp);
                    if (!forge.clean(&p, dseed)) continue;
                    got += 1;
                    const g = familyResidual(hidden, unsolved_wall, &p);
                    if (g > best_g) {
                        best_g = g;
                        best_p = p;
                    }
                }
                if (best_g < 0) break;
                starts_buf[n_starts] = best_p;
                n_starts += 1;
            }
            const polish: ?ClimbOut = polishRound(rng, &sp, hidden, unsolved_wall, starts_buf[0..n_starts]);

            const CensusCand = struct { prog: alien.Program, gate: f64 };
            var cert = std.ArrayList(CensusCand).init(al);
            defer cert.deinit();
            const n_checked = @min(CENSUS_CAP, cleanlist.items.len);
            for (cleanlist.items[0..n_checked]) |m| {
                if (!forge.reducibleLib(&m.prog, atoms.slice(), DEPTH, fseed)) {
                    try cert.append(.{ .prog = m.prog, .gate = familyResidual(hidden, unsolved_wall, &m.prog) });
                }
            }
            if (polish) |po| {
                const admit = forge.clean(&po.prog, dseed) or po.score >= 0.90;
                if (admit and !forge.reducibleLib(&po.prog, atoms.slice(), DEPTH, fseed)) {
                    try cert.append(.{ .prog = po.prog, .gate = po.score });
                }
            }
            std.mem.sort(CensusCand, cert.items, {}, struct {
                fn lt(_: void, x: CensusCand, y: CensusCand) bool {
                    if (x.gate != y.gate) return x.gate > y.gate;
                    return x.prog.len() < y.prog.len();
                }
            }.lt);

            var winner: ?CensusCand = null;
            for (cert.items, 0..) |c, ci| {
                if (ci >= 3) break;
                if (forge.reducibleLib(&c.prog, atoms.slice(), GATE_DEPTH, fseed)) continue;
                winner = c;
                break;
            }
            if (winner) |w| {
                atoms.appendAssumeCapacity(w.prog);
                try promoted.append(.{ .prog = w.prog, .round = round, .prefix_len = atoms.len - 1, .kind = "fallback" });
                event = "fallback_promote";
                promoted_len = w.prog.len();
                try out.print("[round {d}] fallback promotion (no stone found; pool={d} certified={d}): len={d} gate={d:.3}\n", .{ round, pool.items.len, n_certified, promoted_len, w.gate });
            } else {
                event = "no_promotion";
                try out.print("[round {d}] no promotion at all (no stone, no fallback candidate survives the gate)\n", .{round});
            }
        }

        // ---- battery re-measurement (full 18 targets, real atoms) ----
        var new_f: usize = 0;
        var new_e: usize = 0;
        var new_self: usize = 0;
        var new_comp: usize = 0;
        const new_idx = atoms.len - 1;
        for (SPECS, 0..) |spec, ti| {
            if (tstate[ti].first_round != null) continue;
            if (targetSolvable(hidden, spec.idxs, atoms.slice(), DEPTH, RSEED)) {
                tstate[ti].first_round = round;
                // witness recompute for self/composed bookkeeping
                var wit: [DEPTH]usize = undefined;
                var wl: usize = 0;
                const n = atoms.len;
                var d: usize = 1;
                outer: while (d <= DEPTH) : (d += 1) {
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
                        if (chainAgreement(hidden, spec.idxs, atoms.slice(), idxs[0..d], MATCH_SEQ, MATCH_L, RSEED) >= forge.MATCH_THRESHOLD) {
                            for (0..d) |j| wit[j] = idxs[j];
                            wl = d;
                            break :outer;
                        }
                    }
                }
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
        try out.print("[round {d}] pool={d} d3={d} payoff_pos={d} certified={d} event={s} -> lib={d} | F {d}/{d} E {d}/{d} (+F{d} +E{d}) ({d} ms)\n", .{
            round, pool.items.len, n_d3, n_payoff_pos, n_certified, event, atoms.len, f_reach, F_IDX.len, e_reach, E_IDX.len, new_f, new_e, ms,
        });
        try cw.print("{d},0x{X},{d},{d},{d},{d},{d},{d},{d},{s},{d},{d:.4},{d:.4},{d},{d},{d},{d},{d}\n", .{
            bulk, seed, round, pool.items.len, n_d3, n_payoff_pos, n_certified, if (found != null) @as(usize, 1) else @as(usize, 0), best_payoff, event, promoted_len, agree_s1, agree_s2, f_reach, e_reach, new_f, new_e, ms,
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

    // ---- retro-reduction audit (A5/A6-style, on every promoted atom) ----
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

        try out.print("  inv{d:<3} round {d:>2} len {d:>2} [{s:<16}] prefix_d4={s:<9} prefix_d5={s:<9} final-self_d3={s:<9} final-self_d4={s:<9}\n", .{
            k,
            pa.round,
            pa.prog.len(),
            pa.kind,
            if (p4) "REDUCED" else "holds",
            if (p5) |v| (if (v) "REDUCED" else "holds") else "skipped",
            if (f3) "REDUNDANT" else "holds",
            if (f4) "REDUNDANT" else "holds",
        });
    }

    const flips = total_self + total_composed;
    try out.print("\nbulk={d} seed 0x{X} summary: lib {d}->{d}  F {d}/{d}  E {d}/{d}  flips self={d} composed={d} (self-rate={d:.1}%)  leaks={d}/{d}  redundant={d}/{d}\n", .{
        bulk,
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
        try out.writeAll("usage: auto_curriculum selftest | run <bulk> <csv> [seed...] [--pop=N] [--gens=N] [--rounds=N]\n");
        return;
    }
    const mode = args[1];

    if (std.mem.eql(u8, mode, "selftest")) {
        try runSelftest(out);
        return;
    }

    if (std.mem.eql(u8, mode, "run")) {
        if (args.len < 4) {
            try out.writeAll("usage: auto_curriculum run <bulk> <csv> [seed...] [--pop=N] [--gens=N] [--rounds=N]\n");
            return;
        }
        const bulk = try std.fmt.parseInt(usize, args[2], 10);
        var seeds = std.ArrayList(u64).init(al);
        defer seeds.deinit();
        var pop: usize = 90;
        var gens: usize = 45;
        var rounds: usize = 10;
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
        for (seeds.items) |s| try runAutoLoop(al, out, cw, s, &hidden, bulk, pop, gens, rounds);
        return;
    }

    try out.writeAll("unknown mode\n");
}
