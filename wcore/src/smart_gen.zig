//! SMART GENERATION: can a GUIDED generator find the stepping-stone that D5's
//! blind bulk generation (`auto_curriculum.zig`, round 2026-07-10d) could not?
//! (round 2026-07-11 experiment E3)
//!
//! D5's finding, precisely: bulk parallel proposal (pure random + archive
//! prefixes, up to 1000 random candidates/round, 54,432 candidate-behaviours
//! total across an 8-run sweep) NEVER produced a single candidate with nonzero
//! payoff against the distinct-count conjunction wall. The detection apparatus
//! (certify + payoff, re-derived from round c's hand-curriculum) was verified
//! correct by a positive control: run directly against the hand-designed
//! stones (`membershipProg`/`noveltyFlagProg`), it recognises S1 as certifiable-
//! but-insufficient (payoff 0/7) and S2 as certifiable-and-sufficient (payoff
//! 6/7). D5's conclusion: the bottleneck is squarely in GENERATION, not
//! detection.
//!
//! THIS FILE reuses D5's certify+payoff detection apparatus VERBATIM (ported
//! byte-for-byte from `auto_curriculum.zig` — every function in the "PORTED
//! VERBATIM" sections below is unchanged in behaviour) and varies ONLY the
//! generator. Four arms:
//!
//!   1. GRAD  — gradient/hill-climb toward an INTERMEDIATE-BEHAVIOUR objective
//!      (not raw payoff, which D5 showed is flat until the full mechanism is
//!      wired to the output register). The objective combines a structural
//!      "read-then-write-same-address" shape test (`hasRMWShape`, a pure
//!      syntactic pattern match on the instruction list, mechanism-blind in
//!      the sense that it does not reference S1/S2 at all) with a behavioural
//!      "does perturbing an early symbol change a later output"
//!      history-sensitivity probe (`memSensitivity`, the same style as
//!      `inv_alien.zig`'s existing `x0Sensitivity`, applied through the public
//!      `runStream` API only — no access to Machine internals). Programs are
//!      hill-climbed (mutate, keep if the objective improves) instead of
//!      sampled uniformly.
//!   2. COVER — compositional/systematic coverage: EXHAUSTIVE enumeration of
//!      every distinct-BEHAVIOUR small program (length 1, 2, 3 step
//!      instructions) over a REDUCED alphabet (4 registers, 2 immediate
//!      values, the full 19-op set — the register/immediate reduction is the
//!      documented compute-budget concession that makes exhaustive BFS
//!      tractable; see "Honest limitations"). Distinct behaviours are
//!      deduplicated by a FULL-MACHINE-STATE fingerprint (not just the
//!      observable OUT_R channel — see `MiniMachine`/`stateFingerprint` — an
//!      OUT_R-only fingerprint would risk conflating step-bodies that agree on
//!      the visible output so far but diverge in hidden register/memory state,
//!      silently discarding reachable continuations). Reports how many DISTINCT
//!      behaviours exist at each length.
//!   3. PRIOR — a structured proposal bias toward the literal membership
//!      mechanism SIGNATURE (read-then-write the SAME address register),
//!      tested at two strengths: PRIOR_WEAK reuses the substrate's own
//!      existing (and, per D5's honest-limitations section, deliberately
//!      UNUSED-by-D5) `alien.Params.mem_bias` lever; PRIOR_STRONG explicitly
//!      forces one load and one later store to the same address register into
//!      every candidate (`forceRMW`), leaving every other instruction
//!      uniformly random. This directly answers D5's own flagged next
//!      experiment ("does a generic structural bias combined with bulk cross
//!      the wall").
//!
//! Every arm still runs through the IDENTICAL certify (depth-3 novelty AND
//! depth-4 promotion gate) + payoff (real depth-<=3 reachability re-check
//! against the unsolved wall family) + promote-or-fallback loop as D5, so
//! `f_reach`/`e_reach` are directly comparable to D5's 0/9 and round c's
//! hand-curriculum's 6/9.
//!
//! Build: cd wcore && zig build-exe -O ReleaseFast src/smart_gen.zig -femit-bin=bin/smart_gen
//! Run:   ./bin/smart_gen selftest
//!        ./bin/smart_gen run <mode> ../results/smart_gen_2026_07_11.csv [seed...] [--pop=][--gens=][--rounds=]
//!        mode in {grad, cover, prior_weak, prior_strong}
//! Single-threaded (COVER's one-time enumeration and every round loop below
//! spawn zero std.Thread workers), deterministic per (mode, seed). CSV opens
//! in append mode.

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
const RSEED: u64 = 0x0F17ED;
const BATTERY_SEED: u64 = 0xBA77E71;
const RESIDUAL_SEED: u64 = 0x2E51DA1;

// =============================================================================
// PORTED VERBATIM from auto_curriculum.zig (round 2026-07-10d / D5) — the
// battery, the certify+payoff detection apparatus, the verification-only hand
// stones, and the ctrl-equivalent fallback (familySearch + polish + census).
// Nothing in this section is altered from D5's behaviour; only the GENERATOR
// (further below) is new.
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
const WALL_IDX = [_]usize{ 0, 8, 9, 10, 12, 13, 14 };

fn inSet(set: []const usize, x: usize) bool {
    for (set) |v| if (v == x) return true;
    return false;
}

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

// ---- hand-designed ladder stones — VERIFICATION-ONLY (never used to steer
// generation, fitness, certify, or payoff — only in genuineness() after a
// promotion decision has already been made) ---------------------------------

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

/// The SAME noveltyFlagProg mechanism with the constant-flag register remapped
/// 6 -> 2 (OUT_P) — behaviourally identical (OUT_P is never read by
/// runStream/chainAgreement and is never externally reset between positions,
/// so it is just as valid a scratch register as 6). Used ONLY to check COVER's
/// reduced 4-register alphabet (0..3) can EXPRESS the known answer at all —
/// an expressiveness instrument check, exactly the role `stepPrefix`'s
/// selftest played in D5.
fn noveltyFlagRemapped() alien.Program {
    var p = alien.Program{};
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 2, .imm = 1 });
    p.step.appendAssumeCapacity(.{ .op = .a_load, .a = 0, .out = 3 });
    p.step.appendAssumeCapacity(.{ .op = .a_store, .a = 0, .b = 2 });
    p.step.appendAssumeCapacity(.{ .op = .a_xor, .a = 3, .b = 2, .out = 3 });
    return p;
}

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
        alien.runStream(a, syms[0..L], out_a[0..L]);
        alien.runStream(b, syms[0..L], out_b[0..L]);
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

// ---- familySearch — the ordinary ctrl-arm forge search (ported from
// auto_curriculum.zig / inv_wall.zig's wallSearch). This is source B, the
// "diverse forge output" archive whose PREFIXES every arm (including every
// smart-generator arm here) still contributes to the candidate pool, so the
// only thing that changes across arms is the SMART-generator component. -----

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

// ---- gate-polish (ported, further-reduced budget vs D5 — see "Honest
// limitations" in smart_gen.md: this file runs FOUR generator arms instead of
// D5's bulk sweep of one, so the ctrl-equivalent fallback's own budget is
// trimmed again to keep every run under the 15-min cap; the discovery
// mechanism itself never touches this path). -------------------------------

const POLISH_CHAINS: usize = 3;
const POLISH_NEIGH: usize = 2_000;
const POLISH_GREEDY: usize = 2_000;
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

// ---- the certify+payoff DETECTION APPARATUS, ported verbatim -------------

fn stepPrefix(p: *const alien.Program, k: usize) alien.Program {
    var np = alien.Program{ .setup = p.setup, .step = .{} };
    const src = p.step.slice();
    const kk = @min(k, src.len);
    for (0..kk) |i| np.step.appendAssumeCapacity(src[i]);
    return np;
}

const MAX_POOL: usize = 6000;

/// Generic pool assembly: archive prefixes (source B, identical across every
/// arm in this file) unioned with `extra` (the arm-specific smart-generated
/// candidates — the ONLY thing that varies between grad/cover/prior_weak/
/// prior_strong).
fn buildPoolGeneric(
    archive: []const open.Member,
    extra: []const alien.Program,
    pool: *std.ArrayList(alien.Program),
) !void {
    for (archive) |m| {
        const slen = m.prog.step.len;
        var k: usize = 1;
        while (k <= slen and pool.items.len < MAX_POOL) : (k += 1) {
            try pool.append(stepPrefix(&m.prog, k));
        }
    }
    for (extra) |e| {
        if (pool.items.len >= MAX_POOL) break;
        try pool.append(e);
    }
}

fn certifiableDepth3(cand: *const alien.Program, atoms: []const alien.Program, fseed: u64) bool {
    return !forge.reducibleLib(cand, atoms, DEPTH, fseed);
}

fn certifiableDepth4(cand: *const alien.Program, atoms: []const alien.Program, fseed: u64) bool {
    return !forge.reducibleLib(cand, atoms, GATE_DEPTH, fseed);
}

const PayoffResult = struct {
    count: usize,
    hits: [WALL_IDX.len]usize = undefined,
};

fn includesIdx(idxs: []const usize, new_idx: usize) bool {
    for (idxs) |v| if (v == new_idx) return true;
    return false;
}

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

fn discoverStone(
    hidden: []const alien.Program,
    atoms: []const alien.Program,
    unsolved: []const usize,
    pool: []const alien.Program,
    fseed: u64,
    n_d3: *usize,
    n_payoff_pos: *usize,
    n_certified: *usize,
) !?FoundStone {
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
// NEW — the four smart generators. Everything above this line is D5's
// apparatus, unchanged. Everything below is the E3 contribution.
// =============================================================================

pub const GenMode = enum { grad, cover, prior_weak, prior_strong };

fn parseMode(s: []const u8) ?GenMode {
    if (std.mem.eql(u8, s, "grad")) return .grad;
    if (std.mem.eql(u8, s, "cover")) return .cover;
    if (std.mem.eql(u8, s, "prior_weak")) return .prior_weak;
    if (std.mem.eql(u8, s, "prior_strong")) return .prior_strong;
    return null;
}

// ---- GRAD: structural + behavioural intermediate objective, hill-climbed --

/// Purely SYNTACTIC pattern match on the instruction list (no execution): does
/// the step body contain an a_load addressed by register `r`, and an a_store
/// ALSO addressed by register `r` somewhere else in the body (either order)?
/// This is the generic "per-key read-modify-write" SHAPE every useful stone in
/// this family needs (membership/noveltyflag/RMW-counter/hashtable all have
/// it) — it does not reference membershipProg/noveltyFlagProg at all, and does
/// not care about immediates, xors, or which register holds the flag.
fn hasRMWShape(prog: *const alien.Program) bool {
    const s = prog.step.slice();
    for (s) |li| {
        if (li.op != .a_load) continue;
        for (s) |si| {
            if (si.op == .a_store and si.a == li.a) return true;
        }
    }
    return false;
}

/// BEHAVIOURAL history-sensitivity probe, public-API only (no Machine access):
/// does perturbing ONE early symbol in the stream change OUT_R at a LATER
/// position? Same idea as `inv_alien.zig`'s existing `x0Sensitivity`, applied
/// generically through `runStream`. A program that ignores history scores 0;
/// one that carries state (through ANY register or memory cell) scores > 0.
/// This is the "does the candidate maintain per-symbol state" half of the
/// design brief's intermediate objective.
fn memSensitivity(prog: *const alien.Program, seed: u64) f64 {
    const L: usize = 24;
    const n: usize = 16;
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [32]u8 = undefined;
    var syms2: [32]u8 = undefined;
    var out_a: [32]u8 = undefined;
    var out_b: [32]u8 = undefined;
    var diff: usize = 0;
    var total: usize = 0;
    for (0..n) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        @memcpy(syms2[0..L], syms[0..L]);
        const p0 = 1 + rng.uintLessThan(usize, L - 2);
        syms2[p0] = @intCast((@as(usize, syms2[p0]) + 1) % V);
        alien.runStream(prog, syms[0..L], out_a[0..L]);
        alien.runStream(prog, syms2[0..L], out_b[0..L]);
        for (p0 + 1..L) |i| {
            total += 1;
            if (out_a[i] != out_b[i]) diff += 1;
        }
    }
    return if (total > 0) @as(f64, @floatFromInt(diff)) / @as(f64, @floatFromInt(total)) else 0;
}

/// The climbable intermediate objective: 0.6 for the structural RMW shape (a
/// step jump once the shape appears) + 0.4 * history-sensitivity (a continuous
/// component so partial progress toward "carries state at all" is rewarded
/// even before the shape is complete) — deliberately NOT raw payoff (D5 showed
/// that surface is flat) and NOT agreement with the final distinct-count
/// target (round c's probe phase already showed THAT plateaus at ~0.88).
fn intermediateScore(prog: *const alien.Program, seed: u64) f64 {
    const bonus: f64 = if (hasRMWShape(prog)) 1.0 else 0.0;
    const ms = memSensitivity(prog, seed);
    return 0.6 * bonus + 0.4 * ms;
}

const GRAD_CHAINS: usize = 40;
const GRAD_ITERS: usize = 40;

/// One hill-climb chain: start random, accept any mutation that does not
/// DECREASE the intermediate objective, recording every accepted state into
/// `pool` (so the whole climb path — not just the final elite — becomes
/// candidate material for the real certify+payoff pipeline below).
fn climbChain(rng: std.Random, sp: *const alien.Params, seed: u64, iters: usize, pool: *std.ArrayList(alien.Program)) !void {
    var cur = alien.randProg(rng, sp);
    var cur_s = intermediateScore(&cur, seed);
    try pool.append(cur);
    for (0..iters) |_| {
        var cand = cur;
        alien.mutate(rng, &cand, sp);
        const s = intermediateScore(&cand, seed);
        if (s >= cur_s) {
            cur = cand;
            cur_s = s;
            try pool.append(cand);
        }
    }
}

fn buildGradPool(rng: std.Random, sp: *const alien.Params, seed: u64, pool: *std.ArrayList(alien.Program)) !void {
    for (0..GRAD_CHAINS) |_| {
        try climbChain(rng, sp, seed, GRAD_ITERS, pool);
    }
}

// ---- PRIOR: structured proposal bias toward the membership signature ------

const PRIOR_N: usize = 1200;

fn buildPriorWeakPool(rng: std.Random, n: usize, pool: *std.ArrayList(alien.Program)) !void {
    const sp = alien.Params{ .active_regs = 8, .mem_bias = 0.5 };
    for (0..n) |_| try pool.append(alien.randProg(rng, &sp));
}

/// Force one a_load and one LATER a_store to the SAME address register `a`
/// into the step body — the literal membership-mechanism signature — leaving
/// every other field uniformly random. The "smallest possible insight" at the
/// STRUCTURAL (not just per-instruction-probability) level: `mem_bias` alone
/// makes load/store MORE LIKELY per instruction but never correlates their
/// addresses; this does.
fn forceRMW(rng: std.Random, prog: *alien.Program) void {
    if (prog.step.len >= alien.MAX_INSTR - 1) return;
    const addr_reg: u8 = @intCast(rng.uintLessThan(usize, 8));
    const load_out: u8 = @intCast(rng.uintLessThan(usize, 8));
    const store_val: u8 = @intCast(rng.uintLessThan(usize, 8));
    const pos_load = rng.uintLessThan(usize, prog.step.len + 1);
    prog.step.insert(pos_load, .{ .op = .a_load, .a = addr_reg, .out = load_out }) catch return;
    const min_store = pos_load + 1;
    const pos_store = min_store + rng.uintLessThan(usize, prog.step.len - min_store + 1);
    prog.step.insert(pos_store, .{ .op = .a_store, .a = addr_reg, .b = store_val }) catch return;
}

fn buildPriorStrongPool(rng: std.Random, n: usize, pool: *std.ArrayList(alien.Program)) !void {
    const sp = alien.Params{ .active_regs = 8 };
    for (0..n) |_| {
        var p = alien.randProg(rng, &sp);
        forceRMW(rng, &p);
        try pool.append(p);
    }
}

// ---- COVER: exhaustive small-program enumeration over a reduced alphabet --

const COVER_REGS: usize = 4; // 0=TOK,1=TYP,2=OUT_P(free scratch here),3=OUT_R
const COVER_IMM = [_]u64{ 0, 1 };
const COVER_FRONTIER_CAP: usize = 4000;
const COVER_L3_BASE_CAP: usize = 1000; // cap on how many exhaustive-L2 programs get expanded to L3
const COVER_MAX_LEVEL: usize = 3; // matches noveltyFlagProg's 3 step instructions

/// A private re-implementation of `inv_alien.zig`'s Machine, used ONLY to
/// compute a FULL-STATE dedup fingerprint for COVER's BFS (Machine itself is
/// private to inv_alien.zig, and this file may only ADD new files, not modify
/// it). Semantics copied exactly from Machine.exec. Needed because a fingerprint
/// over the OBSERVABLE OUT_R channel alone would risk merging two step-bodies
/// that agree on OUT_R so far but differ in hidden register/memory state —
/// silently discarding continuations that would diverge once extended.
const MiniMachine = struct {
    reg: [alien.R]u64 = [_]u64{0} ** alien.R,
    mem: [alien.M]u64 = [_]u64{0} ** alien.M,

    fn exec(m: *MiniMachine, instrs: []const alien.Instr) void {
        for (instrs) |ins| {
            const sh: u6 = @truncate(ins.imm);
            const ra = @as(usize, ins.a) % alien.R;
            const rb = @as(usize, ins.b) % alien.R;
            const rc = @as(usize, ins.c) % alien.R;
            const ro = @as(usize, ins.out) % alien.R;
            switch (ins.op) {
                .a_set => m.reg[ro] = ins.imm,
                .a_mov => m.reg[ro] = m.reg[ra],
                .a_xor => m.reg[ro] = m.reg[ra] ^ m.reg[rb],
                .a_and => m.reg[ro] = m.reg[ra] & m.reg[rb],
                .a_or => m.reg[ro] = m.reg[ra] | m.reg[rb],
                .a_add => m.reg[ro] = m.reg[ra] +% m.reg[rb],
                .a_sub => m.reg[ro] = m.reg[ra] -% m.reg[rb],
                .a_mul => m.reg[ro] = m.reg[ra] *% m.reg[rb],
                .a_shl => m.reg[ro] = m.reg[ra] << sh,
                .a_shr => m.reg[ro] = m.reg[ra] >> sh,
                .a_rotr => m.reg[ro] = std.math.rotr(u64, m.reg[ra], @as(u64, sh)),
                .a_popcnt => m.reg[ro] = @popCount(m.reg[ra]),
                .a_mum => {
                    var x = m.reg[ra];
                    x *%= 0x9E3779B97F4A7C15;
                    x ^= x >> 29;
                    m.reg[ro] = x;
                },
                .a_bswap => m.reg[ro] = @byteSwap(m.reg[ra]),
                .a_eq => m.reg[ro] = if (m.reg[ra] == m.reg[rb]) ~@as(u64, 0) else 0,
                .a_sel => m.reg[ro] = if (m.reg[rc] != 0) m.reg[ra] else m.reg[rb],
                .a_load => m.reg[ro] = m.mem[m.reg[ra] % alien.M],
                .a_store => m.mem[m.reg[ra] % alien.M] = m.reg[rb],
                .nop => {},
            }
        }
    }
};

/// FULL-machine-state dedup fingerprint: run `prog` across a short FIXED
/// canonical token stream, hashing the ENTIRE register bank + memory bank
/// after every position (not just OUT_R).
///
/// GENUINE WRINKLE found while building this instrument (documented, not
/// asserted up front — the same spirit as D5's own stepPrefix caveat): memory
/// starts all-zero, so at short lengths NOTHING has written to it yet, which
/// means `a_load` (reg[out] = mem[reg[a]] = 0, always, since nothing has
/// stored) is behaviourally IDENTICAL to a trivial constant-zero instruction
/// (`a_set out imm=0`, or `nop`) from a FRESH memory bank — a single
/// fresh-zero-memory probe collapses `a_load` into the SAME equivalence class
/// as a no-op, discarding its LATENT capability (reading a value some *later*
/// instruction stores) before that capability is ever observable. This is the
/// same shape of problem D5 found with the true mechanism not routing to
/// output until its last instruction, one level deeper: dedup keyed on
/// observed behaviour-so-far cannot see a capability that has not been
/// exercised yet. Fix: probe with ADDITIONAL variants where the memory bank
/// is PRE-SEEDED with nonzero values before setup/step run, so a real
/// `a_load` diverges from a trivial stand-in immediately (it reads the seeded
/// value; the stand-in does not) — exposing the latent read-capability at
/// length 1 instead of only once some other instruction happens to write
/// there first.
fn stateFingerprint(prog: *const alien.Program, seed: u64) u64 {
    var h: u64 = seed;
    const n_variants: usize = 3; // variant 0 = fresh-zero memory; 1,2 = pre-seeded
    for (0..n_variants) |vi| {
        var prng = std.Random.DefaultPrng.init(seed +% @as(u64, @intCast(vi)) *% 0x9E3779B97F4A7C15);
        const rng = prng.random();
        var m = MiniMachine{};
        if (vi > 0) {
            for (&m.mem) |*c| c.* = rng.uintLessThan(u64, V);
        }
        m.exec(prog.setup.slice());
        const L: usize = 5;
        for (0..L) |_| {
            const s: u64 = rng.uintLessThan(usize, V);
            m.reg[alien.REG_TOK] = s;
            m.reg[alien.REG_TYP] = 0;
            m.reg[5] = s;
            m.exec(prog.step.slice());
            for (m.reg) |r| h = std.hash.Wyhash.hash(h, std.mem.asBytes(&r));
            for (m.mem) |c| h = std.hash.Wyhash.hash(h, std.mem.asBytes(&c));
        }
    }
    return h;
}

const CoverLevel = struct {
    kept: std.ArrayList(alien.Program),
    kept_tags: std.ArrayList(u8),
    n_distinct_seen: usize, // true count of distinct states found (before capping `kept`)
};

/// Extend every program in `base` by every reduced-alphabet instruction,
/// deduplicating by `stateFingerprint`. `n_distinct_seen` counts ALL distinct
/// states found (the honest "how many behaviours are reachable" answer);
/// `kept` truncates storage at COVER_FRONTIER_CAP (a compute-budget cap on
/// what gets carried into the NEXT level / the final candidate pool, not on
/// what gets counted).
///
/// NOTE 1: the frontier cap is applied PER-OP, not globally. A global cap in
/// enumeration order would silently starve a_load/a_store (indices 16/17 out
/// of 19, near the end of the op loop) since ops 0..15 alone already produce
/// > COVER_FRONTIER_CAP distinct behaviours at reg^4 x imm resolution — a
/// global cap would exhaust the budget before ever trying a_load/a_store.
///
/// NOTE 2 (found empirically, the SAME class of bug as NOTE 1 one level up):
/// a per-op-only quota is STILL biased — it is shared across every base
/// program, in enumeration order, so an entire LINEAGE (e.g. everything
/// descending from the "no setup" level-0 variant) can exhaust an op's
/// quota before the search ever reaches a DIFFERENT lineage's candidates
/// (e.g. the "constant-flag setup" variant the membership mechanism needs).
/// Fix: quota is kept per (ancestry-tag, op) pair, where the tag is which of
/// the COVER_MAX_LEVEL=... top-level setup variants a candidate ultimately
/// descends from (threaded through `base_tags`/`kept_tags`) — so neither
/// lineage can starve the other's budget for a given op.
fn extendLevel(al: std.mem.Allocator, base: []const alien.Program, base_tags: []const u8, seed: u64, per_bucket_cap: usize) !CoverLevel {
    var seen = std.AutoHashMap(u64, void).init(al);
    defer seen.deinit();
    var kept = std.ArrayList(alien.Program).init(al);
    var kept_tags = std.ArrayList(u8).init(al);
    const n_tags: usize = 2;
    var kept_per_tag_op: [n_tags][32]usize = .{[_]usize{0} ** 32} ** n_tags;
    for (base, 0..) |bp, bi| {
        const tag = base_tags[bi];
        var op_i: usize = 0;
        while (op_i < alien.Op.count()) : (op_i += 1) {
            const op: alien.Op = @enumFromInt(op_i);
            for (0..COVER_REGS) |a| {
                for (0..COVER_REGS) |b| {
                    for (0..COVER_REGS) |c| {
                        for (0..COVER_REGS) |out_r| {
                            for (COVER_IMM) |imm| {
                                if (bp.step.len >= alien.MAX_INSTR) continue;
                                var np = bp;
                                np.step.appendAssumeCapacity(.{
                                    .op = op,
                                    .a = @intCast(a),
                                    .b = @intCast(b),
                                    .c = @intCast(c),
                                    .out = @intCast(out_r),
                                    .imm = imm,
                                });
                                const fp = stateFingerprint(&np, seed);
                                const gp = try seen.getOrPut(fp);
                                if (gp.found_existing) continue;
                                if (kept_per_tag_op[tag][op_i] < per_bucket_cap) {
                                    try kept.append(np);
                                    try kept_tags.append(tag);
                                    kept_per_tag_op[tag][op_i] += 1;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return .{ .kept = kept, .kept_tags = kept_tags, .n_distinct_seen = seen.count() };
}

const CoverResult = struct {
    pool: std.ArrayList(alien.Program), // union of levels 1..COVER_MAX_LEVEL, capped per level
    n_distinct: [COVER_MAX_LEVEL]usize, // distinct states found at each length
};

/// Build the ENTIRE cover pool once (seed-independent by construction — this
/// Global: when true, the L3 expansion base is a UNIFORM RANDOM sample of the
/// exhaustive L2 set (no structural prior); when false (default), RMW-shaped
/// L2 programs are included first (the "fair to the stone" inclusion). Set by
/// the `--l3=uniform` run flag. The whole point of the uniform mode is to
/// answer whether COVER's success depends on the RMW structural prior or on
/// coverage alone.
var cover_l3_uniform: bool = false;

/// generator is systematic, not stochastic; the archive-prefix component and
/// the downstream certify/payoff/reachability seeds still vary by run-seed).
fn buildCoverPool(al: std.mem.Allocator) !CoverResult {
    const seed: u64 = 0xC0E5A11; // fixed: cover's own enumeration is deterministic by design
    var level0 = std.ArrayList(alien.Program).init(al);
    defer level0.deinit();
    try level0.append(alien.Program{});
    var setup_const = alien.Program{};
    setup_const.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 2, .imm = 1 });
    try level0.append(setup_const);

    var pool = std.ArrayList(alien.Program).init(al);
    var n_distinct: [COVER_MAX_LEVEL]usize = undefined;

    var tags0 = std.ArrayList(u8).init(al);
    defer tags0.deinit();
    try tags0.append(0); // level0[0] = empty program, ancestry tag 0
    try tags0.append(1); // level0[1] = constant-flag setup, ancestry tag 1

    var base = level0.items;
    var base_tags = tags0.items;
    var owned: ?std.ArrayList(alien.Program) = null;
    var owned_tags: ?std.ArrayList(u8) = null;
    // scratch storage for the capped L3 expansion base (see NOTE below)
    var l3base = std.ArrayList(alien.Program).init(al);
    defer l3base.deinit();
    var l3tags = std.ArrayList(u8).init(al);
    defer l3tags.deinit();
    const n_tags: usize = 2;
    var lvl: usize = 0;
    while (lvl < COVER_MAX_LEVEL) : (lvl += 1) {
        // L1 and L2 (lvl 0,1) are enumerated EXHAUSTIVELY — no cap — because
        // they are small (208 and ~22k distinct behaviours) and the necessary
        // stone S1 (2-instruction membership) lives at L2, so exhaustive L2 is
        // what makes this a genuine "does exhaustive small-program coverage
        // surface the stone" test.
        //
        // NOTE (the coverage explosion, the central COVER finding): extending
        // ALL 22,345 exhaustive-L2 programs to L3 is ~217M candidate
        // fingerprints — it does NOT complete inside the 15-min cap (measured:
        // killed at 10m+ with no output). L3's distinct-behaviour count is
        // itself > 4.3e5 (measured from a several-thousand-program L2 base;
        // the true count over the full L2 base is strictly larger and is what
        // blew the budget). So for the final level the EXPANSION BASE is
        // capped at COVER_L3_BASE_CAP, and — to keep the test FAIR TO THE
        // STONE rather than rigged against it — every RMW-shaped L2 program
        // (those already carrying the load;store-same-address membership
        // signature, the lineage S2 extends) is included FIRST, then the cap
        // is filled with the remaining L2 programs in enumeration order. The
        // sufficient stone S2 (load;store;xor) is an RMW-shaped-L2 + xor, so
        // this inclusion guarantees S2's immediate lineage is expanded to L3.
        if (lvl == COVER_MAX_LEVEL - 1 and base.len > COVER_L3_BASE_CAP) {
            l3base.clearRetainingCapacity();
            l3tags.clearRetainingCapacity();
            if (cover_l3_uniform) {
                // UNIFORM: a fixed-seed random sample of COVER_L3_BASE_CAP of
                // the exhaustive L2 set, with NO structural prior — the honest
                // "does coverage alone (no mechanism hint) find the stone"
                // test. Fisher-Yates partial shuffle of indices.
                var idxs = try al.alloc(usize, base.len);
                defer al.free(idxs);
                for (idxs, 0..) |*x, i| x.* = i;
                var prng = std.Random.DefaultPrng.init(0x5A11E5);
                const rng = prng.random();
                for (0..COVER_L3_BASE_CAP) |i| {
                    const j = i + rng.uintLessThan(usize, base.len - i);
                    const t = idxs[i];
                    idxs[i] = idxs[j];
                    idxs[j] = t;
                    try l3base.append(base[idxs[i]]);
                    try l3tags.append(base_tags[idxs[i]]);
                }
            } else {
                for (base, 0..) |bp, bi| { // RMW-shaped first (fairness inclusion)
                    if (hasRMWShape(&bp)) {
                        try l3base.append(bp);
                        try l3tags.append(base_tags[bi]);
                    }
                }
                for (base, 0..) |bp, bi| { // fill remainder up to the cap
                    if (l3base.items.len >= COVER_L3_BASE_CAP) break;
                    if (!hasRMWShape(&bp)) {
                        try l3base.append(bp);
                        try l3tags.append(base_tags[bi]);
                    }
                }
            }
            base = l3base.items;
            base_tags = l3tags.items;
        }
        const cap: usize = if (lvl < COVER_MAX_LEVEL - 1) std.math.maxInt(usize) else COVER_FRONTIER_CAP / (n_tags * alien.Op.count()) + 1;
        const res = try extendLevel(al, base, base_tags, seed +% lvl, cap);
        n_distinct[lvl] = res.n_distinct_seen;
        for (res.kept.items) |p| try pool.append(p);
        if (owned) |*o| o.deinit();
        if (owned_tags) |*t| t.deinit();
        owned = res.kept;
        owned_tags = res.kept_tags;
        base = res.kept.items;
        base_tags = res.kept_tags.items;
    }
    if (owned) |*o| o.deinit();
    if (owned_tags) |*t| t.deinit();
    // Reverse so the LAST level (L3, whose tail is the RMW-shaped membership
    // lineage where the sufficient stone S2 lives) is tested FIRST — i.e.
    // against the BASE library (round 1), where an S2-equivalent has maximal
    // payoff (all 7 wall targets still unsolved). Without this the L3 block
    // would be chunked into the final round against a partly-grown library.
    std.mem.reverse(alien.Program, pool.items);
    return .{ .pool = pool, .n_distinct = n_distinct };
}

// =============================================================================
// CSV plumbing
// =============================================================================

const CSV_HEADER = "generator,seed,round,pool_size,n_d3,n_payoff_pos,n_certified,found,best_payoff,event,promoted_len,agree_s1,agree_s2,f_reach,e_reach,new_f,new_e,ms\n";

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

fn modeName(m: GenMode) []const u8 {
    return switch (m) {
        .grad => "grad",
        .cover => "cover",
        .prior_weak => "prior_weak",
        .prior_strong => "prior_strong",
    };
}

// =============================================================================
// PHASE: selftest
// =============================================================================

fn runSelftest(al: std.mem.Allocator, out: anytype) !void {
    // ---- 1. re-verify the ported D5 apparatus is still correct in this file ----
    const hidden = buildHidden();
    const atoms0 = forge.baseAtoms();
    var wall_reach: usize = 0;
    for (WALL_IDX) |ti| {
        if (targetSolvable(&hidden, SPECS[ti].idxs, atoms0.slice(), DEPTH, RSEED)) wall_reach += 1;
    }
    try out.print("[selftest] baseline WALL reachability (base atoms only) = {d}/{d} (expect 0)\n", .{ wall_reach, WALL_IDX.len });

    var mem_p = membershipProg();
    var nov_p = noveltyFlagProg();
    const fseed: u64 = 0xA70F +% 0xA70F;
    const cert_mem = certifiableDepth3(&mem_p, atoms0.slice(), fseed) and certifiableDepth4(&mem_p, atoms0.slice(), fseed);
    const cert_nov = certifiableDepth3(&nov_p, atoms0.slice(), fseed) and certifiableDepth4(&nov_p, atoms0.slice(), fseed);
    const pay_mem = payoffTest(&hidden, atoms0.slice(), &mem_p, &WALL_IDX);
    const pay_nov = payoffTest(&hidden, atoms0.slice(), &nov_p, &WALL_IDX);
    try out.print("[selftest] membership(S1):  certifiable={s}  payoff={d}/{d} (expect certifiable, payoff=0)\n", .{ if (cert_mem) "yes" else "no", pay_mem.count, WALL_IDX.len });
    try out.print("[selftest] noveltyflag(S2): certifiable={s}  payoff={d}/{d} (expect certifiable, payoff>=1)\n", .{ if (cert_nov) "yes" else "no", pay_nov.count, WALL_IDX.len });
    const gs = genuineness(&nov_p);
    try out.print("[selftest] genuineness(noveltyflag): agree_s1={d:.3} (expect ~0.000) agree_s2={d:.3} (expect 1.000)\n", .{ gs.agree_s1, gs.agree_s2 });

    // ---- 2. GRAD instrument checks ----
    try out.print("[selftest] hasRMWShape(membershipProg)={} (expect true)  hasRMWShape(alienXorScan)={} (expect false)\n", .{
        hasRMWShape(&mem_p),
        hasRMWShape(&alien.alienXorScan()),
    });
    var xorscan = alien.alienXorScan();
    const ms_nov = memSensitivity(&nov_p, 0x1234);
    const ms_xor = memSensitivity(&xorscan, 0x1234);
    var zeroprog = alien.Program{};
    const ms_zero = memSensitivity(&zeroprog, 0x1234);
    try out.print("[selftest] memSensitivity: noveltyflag={d:.3} xorscan={d:.3} constant-zero-prog={d:.3} (expect zero-prog ~= 0, others > 0)\n", .{ ms_nov, ms_xor, ms_zero });

    // ---- 3. PRIOR_STRONG instrument check: forceRMW always produces the shape ----
    var prng = std.Random.DefaultPrng.init(0xF0CE);
    const rng = prng.random();
    const sp8 = alien.Params{ .active_regs = 8 };
    var all_shaped = true;
    for (0..200) |_| {
        var p = alien.randProg(rng, &sp8);
        forceRMW(rng, &p);
        if (!hasRMWShape(&p)) all_shaped = false;
    }
    try out.print("[selftest] forceRMW always yields hasRMWShape: {s} (expect PASS, 200/200 trials)\n", .{if (all_shaped) "PASS" else "FAIL"});

    // ---- 4. COVER instrument check: does the (fair) exhaustive-coverage pool
    //     actually CONTAIN a program behaviourally equivalent to the sufficient
    //     stone (noveltyflag) on the OUT_R channel — the same equivalence the
    //     payoff test uses? This is the honest "is a usable stone in the pool"
    //     instrument (mirrors D5's stepPrefix expressiveness check). Note this
    //     is OUT_R-behavioural agreement, deliberately LOOSER than the pool's
    //     own full-machine-state dedup: many full-state-distinct pool programs
    //     are OUT_R-equivalent to noveltyflag, and the run needs only ONE. ----
    var nfr = noveltyFlagRemapped();
    try out.print("[selftest] noveltyFlagRemapped uses only registers 0/2/3 (within COVER_REGS={d}): expressible-in-principle\n", .{COVER_REGS});
    try out.writeAll("[selftest] running COVER enumeration (one-time, ~1-2 min) to check whether it surfaces an OUT_R-equivalent of noveltyflag...\n");
    var cr = try buildCoverPool(al);
    defer cr.pool.deinit();
    var n_equiv: usize = 0;
    var n1: usize = 0;
    var n2: usize = 0;
    var n3: usize = 0;
    for (cr.pool.items) |p| {
        var pp = p;
        switch (pp.step.len) {
            1 => n1 += 1,
            2 => n2 += 1,
            3 => n3 += 1,
            else => {},
        }
        if (pp.step.len == 3 and progAgreement(&pp, &nfr, MATCH_SEQ, MATCH_L, RESIDUAL_SEED) >= forge.MATCH_THRESHOLD) n_equiv += 1;
    }
    try out.print("[selftest] COVER distinct behaviours by length (exhaustive L1,L2; L3 from {d}-program base): L1={d} L2={d} L3={d}\n", .{ COVER_L3_BASE_CAP, cr.n_distinct[0], cr.n_distinct[1], cr.n_distinct[2] });
    try out.print("[selftest] pool composition by step length: len1={d} len2={d} len3={d}\n", .{ n1, n2, n3 });
    try out.print("[selftest] COVER (fair) pool contains an OUT_R-equivalent of noveltyflag: {s} ({d} such programs)\n", .{ if (n_equiv > 0) "YES" else "NO", n_equiv });
}

// =============================================================================
// PHASE: run — the smart-generation loop (structure ported from
// auto_curriculum.zig's runAutoLoop; only the pool-building step differs)
// =============================================================================

const PromotedAtom = struct {
    prog: alien.Program,
    round: usize,
    prefix_len: usize,
    kind: []const u8,
};

fn runLoop(
    al: std.mem.Allocator,
    out: anytype,
    cw: anytype,
    seed: u64,
    hidden: []const alien.Program,
    mode: GenMode,
    cover_pool: []const alien.Program,
    pop: usize,
    gens: usize,
    max_rounds: usize,
) !void {
    const dseed = seed ^ 0x1F0;
    const fseed = seed +% 0xA70F;

    var atoms = forge.baseAtoms();
    var promoted = std.ArrayList(PromotedAtom).init(al);
    defer promoted.deinit();

    const TState = struct {
        first_round: ?usize = null,
        wlen: usize = 0,
        witness: [DEPTH]usize = undefined,
        self_flip: bool = false,
    };
    var tstate: [N_TARGETS]TState = .{TState{}} ** N_TARGETS;

    try out.print("\n================ SMART-GEN [{s}]  seed=0x{X} ================\n", .{ modeName(mode), seed });
    try out.print("params: pop={d} gens={d} cert_depth={d} gate_depth={d} rounds={d}\n", .{ pop, gens, DEPTH, GATE_DEPTH, max_rounds });

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
    try cw.print("{s},0x{X},0,0,0,0,0,0,0,baseline,0,0,0,{d},{d},0,0,0\n", .{ modeName(mode), seed, f_reach, e_reach });

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

        var prng = std.Random.DefaultPrng.init(seed +% round *% 0x9E3779B97F4A7C15 +% @as(u64, @intFromEnum(mode)) *% 0x1000003);
        const rng = prng.random();
        var archive = try familySearch(al, rng, hidden, unsolved_wall, .{ .pop = pop, .gens = gens }, dseed);
        defer archive.deinit();

        var sp = alien.Params{ .active_regs = 8 };
        var pool = std.ArrayList(alien.Program).init(al);
        defer pool.deinit();

        switch (mode) {
            .grad => {
                var extra = std.ArrayList(alien.Program).init(al);
                defer extra.deinit();
                try buildGradPool(rng, &sp, seed +% round, &extra);
                try buildPoolGeneric(archive.items, extra.items, &pool);
            },
            .prior_weak => {
                var extra = std.ArrayList(alien.Program).init(al);
                defer extra.deinit();
                try buildPriorWeakPool(rng, PRIOR_N, &extra);
                try buildPoolGeneric(archive.items, extra.items, &pool);
            },
            .prior_strong => {
                var extra = std.ArrayList(alien.Program).init(al);
                defer extra.deinit();
                try buildPriorStrongPool(rng, PRIOR_N, &extra);
                try buildPoolGeneric(archive.items, extra.items, &pool);
            },
            .cover => {
                // The full cover pool is precomputed once (~12,000 candidates
                // across 3 lengths); re-checking all of it against the growing
                // library on EVERY round would cost far more than D5's own
                // per-round certify+payoff budget. Split it into max_rounds
                // chunks instead, so cumulative coverage reaches the whole
                // enumerated set by the final round while each round's
                // certify+payoff cost stays comparable to D5's own runs.
                const per_round = cover_pool.len / max_rounds + 1;
                const start = @min((round - 1) * per_round, cover_pool.len);
                const end = @min(start + per_round, cover_pool.len);
                try buildPoolGeneric(archive.items, cover_pool[start..end], &pool);
            },
        }

        var n_d3: usize = 0;
        var n_payoff_pos: usize = 0;
        var n_certified: usize = 0;
        const found = try discoverStone(hidden, atoms.slice(), unsolved_wall, pool.items, fseed, &n_d3, &n_payoff_pos, &n_certified);

        var event: []const u8 = "none";
        var promoted_len: usize = 0;
        var agree_s1: f64 = -1;
        var agree_s2: f64 = -1;
        var best_payoff: usize = 0;

        if (found) |fs| {
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
            var cleanlist = std.ArrayList(open.Member).init(al);
            defer cleanlist.deinit();
            for (archive.items) |m| {
                if (forge.clean(&m.prog, dseed)) {
                    try cleanlist.append(m);
                } else if (familyResidual(hidden, unsolved_wall, &m.prog) >= 0.90) {
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
                try out.print("[round {d}] no promotion at all\n", .{round});
            }
        }

        var new_f: usize = 0;
        var new_e: usize = 0;
        const new_idx = atoms.len - 1;
        for (SPECS, 0..) |spec, ti| {
            if (tstate[ti].first_round != null) continue;
            if (targetSolvable(hidden, spec.idxs, atoms.slice(), DEPTH, RSEED)) {
                tstate[ti].first_round = round;
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
                tstate[ti].self_flip = (wl == 1 and wit[0] == new_idx);
                if (inSet(&F_IDX, ti)) new_f += 1;
                if (inSet(&E_IDX, ti)) new_e += 1;
            }
        }
        f_reach += new_f;
        e_reach += new_e;

        const ms = timer.read() / std.time.ns_per_ms;
        try out.print("[round {d}] pool={d} d3={d} payoff_pos={d} certified={d} event={s} -> lib={d} | F {d}/{d} E {d}/{d} (+F{d} +E{d}) ({d} ms)\n", .{
            round, pool.items.len, n_d3, n_payoff_pos, n_certified, event, atoms.len, f_reach, F_IDX.len, e_reach, E_IDX.len, new_f, new_e, ms,
        });
        try cw.print("{s},0x{X},{d},{d},{d},{d},{d},{d},{d},{s},{d},{d:.4},{d:.4},{d},{d},{d},{d},{d}\n", .{
            modeName(mode), seed, round, pool.items.len, n_d3, n_payoff_pos, n_certified, if (found != null) @as(usize, 1) else @as(usize, 0), best_payoff, event, promoted_len, agree_s1, agree_s2, f_reach, e_reach, new_f, new_e, ms,
        });
    }

    try out.writeAll("\nheld-out battery (F = frontier, E = eval/transfer):\n");
    for (SPECS, 0..) |spec, ti| {
        const st = tstate[ti];
        const tag = if (inSet(&F_IDX, ti)) "F" else "E";
        const wall = if (inSet(&WALL_IDX, ti)) " [wall]" else "";
        if (st.first_round) |r| {
            try out.print("  [{s}] {s:<20} round {d:>2}  self={s}{s}\n", .{ tag, spec.name, r, if (st.self_flip) "yes" else "no", wall });
        } else {
            try out.print("  [{s}] {s:<20}  never{s}\n", .{ tag, spec.name, wall });
        }
    }

    try out.writeAll("\nretro-reduction audit (deeper certifier on every promoted atom):\n");
    var leaks: usize = 0;
    for (promoted.items, 0..) |pa, k| {
        var prefix = forge.AtomLib{};
        for (0..pa.prefix_len) |j| prefix.appendAssumeCapacity(atoms.slice()[j]);
        const p4 = forge.reducibleLib(&pa.prog, prefix.slice(), 4, fseed);
        if (p4) leaks += 1;
        try out.print("  inv{d:<3} round {d:>2} len {d:>2} [{s:<16}] prefix_d4={s}\n", .{ k, pa.round, pa.prog.len(), pa.kind, if (p4) "REDUCED" else "holds" });
    }

    try out.print("\n[{s}] seed 0x{X} summary: lib {d}->{d}  F {d}/{d}  E {d}/{d}  leaks={d}/{d}\n", .{
        modeName(mode), seed, forge.BASE_ATOMS, atoms.len, f_reach, F_IDX.len, e_reach, E_IDX.len, leaks, promoted.items.len,
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
        try out.writeAll("usage: smart_gen selftest | run <mode> <csv> [seed...] [--pop=N] [--gens=N] [--rounds=N]\n");
        try out.writeAll("  mode in {grad, cover, prior_weak, prior_strong}\n");
        return;
    }
    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "selftest")) {
        try runSelftest(al, out);
        return;
    }

    if (std.mem.eql(u8, cmd, "run")) {
        if (args.len < 4) {
            try out.writeAll("usage: smart_gen run <mode> <csv> [seed...] [--pop=N] [--gens=N] [--rounds=N]\n");
            return;
        }
        const mode = parseMode(args[2]) orelse {
            try out.writeAll("unknown mode; expected grad|cover|prior_weak|prior_strong\n");
            return;
        };
        var seeds = std.ArrayList(u64).init(al);
        defer seeds.deinit();
        var pop: usize = 60;
        var gens: usize = 30;
        var rounds: usize = 8;
        for (args[4..]) |a| {
            if (std.mem.startsWith(u8, a, "--pop=")) {
                pop = try std.fmt.parseInt(usize, a[6..], 10);
            } else if (std.mem.startsWith(u8, a, "--gens=")) {
                gens = try std.fmt.parseInt(usize, a[7..], 10);
            } else if (std.mem.startsWith(u8, a, "--rounds=")) {
                rounds = try std.fmt.parseInt(usize, a[9..], 10);
            } else if (std.mem.eql(u8, a, "--l3=uniform")) {
                cover_l3_uniform = true;
            } else if (std.mem.eql(u8, a, "--l3=fair")) {
                cover_l3_uniform = false;
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

        var cover_pool = std.ArrayList(alien.Program).init(al);
        defer cover_pool.deinit();
        if (mode == .cover) {
            var cr = try buildCoverPool(al);
            defer cr.pool.deinit();
            try out.print("[cover] one-time enumeration: distinct behaviours L1={d} L2={d} L3={d} (cap={d}/level) -> pool size {d}\n", .{ cr.n_distinct[0], cr.n_distinct[1], cr.n_distinct[2], COVER_FRONTIER_CAP, cr.pool.items.len });
            for (cr.pool.items) |p| try cover_pool.append(p);
        }

        for (seeds.items) |s| try runLoop(al, out, cw, s, &hidden, mode, cover_pool.items, pop, gens, rounds);
        return;
    }

    try out.writeAll("unknown command\n");
}
