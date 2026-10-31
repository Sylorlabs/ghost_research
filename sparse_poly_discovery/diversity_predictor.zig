//! Research round 2026-07-10d — does GENERATOR DIVERSITY predict out-of-closure
//! REACH better than proposer COUNT or total eval budget?
//!
//! Hypothesis under test (precise form): a pool of N proposers has an
//! out-of-closure reach that is predicted by D = the number of DISTINCT
//! behavioral closures (families) the pool spans, not by N or by total evals
//! alone. If N IDENTICAL proposers (D=1) plateau the way the production
//! engine's H50 scaling-law run plateaus (docs/research/scaling_laws_h50.md:
//! caps 96/384/1536 all consume exactly 372 evals and buy zero extra solves),
//! while N DIVERSE proposers (D>1) keep paying, that validates "pump more
//! DIFFERENT generators" over "pump more of the same".
//!
//! This is a NEW, standalone, self-contained experiment (no existing file is
//! imported or modified). It builds its own small world + its own 6 families
//! (closures) + its own 9-target battery (2 of the 9 are direct analogues of
//! the round-c reach-gap targets: target 4 = D08-style "sum mod k" selection
//! target, target 5 = C09-style inversion-count-parity target — see
//! docs/research/tier8_reach_gap.md), because no prior round-d proposer-pool
//! harness exists yet in this repo (checked: no breadth_vs_depth.md /
//! breadth_scaling.md present as of this run).
//!
//! ============================= THE MODEL ===================================
//!
//! World: a Grid is 8 cells, each cell in [0,6). NTRAIN=800 / NTEST=300
//! samples, generated once and shared by every family/proposer/pool (so N/D/
//! evals are the only things that vary between runs -- no sampling-noise
//! confound).
//!
//! Six FAMILIES (closures), each a bounded, enumerable search space of
//! "candidates"; every candidate is scored by a train-fit best-threshold+
//! polarity rule and then measured (held out) on test:
//!   mono      - product of a subset (size 1-3) of cells, thresholded  (92 bases)
//!   pair      - cell_i - cell_j, thresholded (>=0.5 ~ cell_i>cell_j)  (28 bases)
//!   walsh     - XOR-parity over a subset of cells, thresholded        (255 bases)
//!   spectral  - cos(omega_k * sum(cells)), thresholded                (128 bases)
//!   worldmod  - (sum(cells) mod k), thresholded                       (39 bases)
//!   cmp       - count of pairs in a canonical pair-set with cell_i>cell_j,
//!               either raw count (thresholded) or count-mod-2 (parity)  (10 bases)
//! `cmp`-parity is the direct analogue of the real repo's C09-solving
//! comparison-count-aggregate family (tier8_reach_gap.md); `worldmod` is the
//! direct analogue of the D08-solving sum-mod family.
//!
//! A PROPOSER (pool member) = ONE family + a fixed budget-sized random subset
//! of that family's candidate bases (sampled once, reused across the whole
//! target battery -- a proposer doesn't "know" the target in advance).
//!
//! GENERATOR-DIVERSITY METRIC (documented precisely, per the round brief):
//!   D = the number of DISTINCT families represented in the pool (1..6).
//!   This is exactly "the number of distinct behavioral closures the pool can
//!   reach" -- each family IS a behavioral closure (a fixed, bounded output
//!   space; see the closure argument in each rawValue() case below). A
//!   secondary/confirmatory metric, entropy H = -sum p_f log2(p_f) over the
//!   pool's family-membership distribution, is also computed and reported;
//!   with the pool's balanced cyclic assignment (member i -> family i%D) H
//!   tracks log2(D) up to the remainder correction, so D is used as the
//!   primary predictor and H is reported as a check, not a second free axis.
//!
//! POOLS: for given (N, D, E_total) [E_total = the pool's total eval budget,
//! spent identically against EVERY target in the battery -- see "evals_actual"
//! below for the true grand total], D families are chosen (shuffled draw, so
//! repeats sample different subsets at fixed D) and N members are assigned to
//! them cyclically (member i -> family (i mod D)). Each member's per-target
//! search budget is floor(E_total/N), capped at its family's own base count
//! (an exhausted family degrades gracefully to full enumeration).
//! D=1 is the degenerate "N IDENTICAL proposers" pool (same closure,
//! independent random subsamples -- this is precisely the H50 sense of
//! "identical": same battery/family template, different seeds).
//!
//! REACH (the dependent variable): for each of the first 8 targets, the pool
//! "solves" it if either (a) any single member's best candidate clears
//! SOLVE_THRESH on held-out test, or (b) any PAIRWISE combination (AND/OR/XOR)
//! of two members' best candidates clears it. Two targets (index 6, 7) are
//! constructed as CONJUNCTIONS of two different families' native predicates
//! (neither family alone can express the AND -- only pairwise combination can)
//! -- these are the "requires diversity IN THE RIGHT DIRECTION" cells.
//! OUT-OF-CLOSURE reach additionally requires that NO single family, given
//! the pool's ENTIRE E_total budget devoted to it alone (the solo_table,
//! precomputed once per family/budget/repeat, shared across all pools), can
//! reach the same target -- i.e., "beyond any single member['s family], even
//! with all the compute". REACH = count of the 8 real targets meeting this
//! bar. Target index 8 is a FALSIFICATION target built from a
//! quadratic-residue-style relation that lies outside all 6 families' spans
//! (and outside every pairwise AND/OR/XOR of them) BY CONSTRUCTION -- it
//! should stay unreached at every (N,D,evals), which is the "diversity in the
//! wrong direction doesn't help" check.
//!
//! Build:  zig build-exe diversity_predictor.zig -O ReleaseFast   (zig 0.14.1)
//! Run:    ./diversity_predictor > ../results/diversity_predictor_2026_07_10.csv
//! (CSV on stdout; diagnostics, regression, and the summary tables on stderr)
//! Single-threaded, no I/O other than stdout/stderr; ~1 min observed.

const std = @import("std");

// ---------------------------------------------------------------- constants
const NCELLS: usize = 8;
const MVAL: i64 = 6; // cell values in [0, MVAL)
const NTRAIN: usize = 800; // fit each candidate's threshold+polarity
const NVAL: usize = 400; // SELECT: best candidate per member, best combo per pair
const NTEST: usize = 300; // REPORT ONLY: final accuracy, touched exactly once per winner
const SOLVE_THRESH: f64 = 0.97;
const NTARGETS: usize = 9; // 0..7 real, 8 = falsification
const NFAM: usize = 6;
const MAX_N: usize = 16;
// Fairness constant: the solo baseline (one family, alone) is ALSO allowed to
// internally combine up to this many of its own top candidates (see
// buildSoloTable). It is set equal to MAX_N so a same-family (D=1) pool can
// never out-combo a solo generator given the identical total budget -- the
// two are evaluated with the same number of "combo slots".
const TOPK: usize = MAX_N;

const N_LIST = [_]usize{ 1, 2, 4, 8, 16 };
// Widened vs the first pilot: at N=16 the top tier (1920/16=120) exceeds
// every family's base count (max 92), guaranteeing exhaustive per-member
// coverage at the high end so the "does the pool find the exact required
// candidate at all" question isn't confounded with "did random subsampling
// simply never touch it". The low end (120/16=7) stays deliberately sparse.
const EVALS_LIST = [_]usize{ 120, 240, 480, 960, 1920 };
const NE = EVALS_LIST.len;
const REPEATS: usize = 3;
const WORLD_SEED: u64 = 0xD1D1_ACC0_FFEE_1234;

const Grid = [NCELLS]i64;

// -------------------------------------------------------------- family defs
const FamilyId = enum(u8) { mono, pair, walsh, spectral, worldmod, cmp };
const FAMILY_ORDER = [_]FamilyId{ .mono, .pair, .walsh, .spectral, .worldmod, .cmp };

fn familyNumBases(f: FamilyId) usize {
    return switch (f) {
        .mono => 92,
        .pair => 28,
        // walsh shares the mono_masks subset table (popcount<=3, 92 entries)
        // instead of all 255 nonempty masks: this keeps every family's base
        // count in the same 10-130 range so budget-vs-coverage is comparable
        // across families (the original 255-base walsh made discovery of one
        // exact required subset improbable at modest per-member budgets --
        // a budget artifact, not a diversity effect; see the doc's design note).
        .walsh => 92,
        .spectral => 64,
        .worldmod => 39,
        .cmp => 5, // parity-only now (see rawValue's cmp case)
    };
}

fn familyName(f: FamilyId) []const u8 {
    return switch (f) {
        .mono => "mono",
        .pair => "pair",
        .walsh => "walsh",
        .spectral => "spectral",
        .worldmod => "worldmod",
        .cmp => "cmp",
    };
}

// comptime-built index tables
const pair_idx: [28][2]usize = blk: {
    var arr: [28][2]usize = undefined;
    var n: usize = 0;
    for (0..NCELLS) |i| {
        for (i + 1..NCELLS) |j| {
            arr[n] = .{ i, j };
            n += 1;
        }
    }
    break :blk arr;
};

const mono_masks: [92]usize = blk: {
    @setEvalBranchQuota(10000);
    var arr: [92]usize = undefined;
    var n: usize = 0;
    for (1..256) |m| {
        var x = m;
        var pc: usize = 0;
        while (x != 0) {
            pc += x & 1;
            x >>= 1;
        }
        if (pc <= 3) {
            arr[n] = m;
            n += 1;
        }
    }
    break :blk arr;
};

const cmp_low: [6][2]usize = blk: {
    var arr: [6][2]usize = undefined;
    var n: usize = 0;
    for (0..4) |i| {
        for (i + 1..4) |j| {
            arr[n] = .{ i, j };
            n += 1;
        }
    }
    break :blk arr;
};

const cmp_high: [6][2]usize = blk: {
    var arr: [6][2]usize = undefined;
    var n: usize = 0;
    for (4..8) |i| {
        for (i + 1..8) |j| {
            arr[n] = .{ i, j };
            n += 1;
        }
    }
    break :blk arr;
};

const cmp_cross: [16][2]usize = blk: {
    var arr: [16][2]usize = undefined;
    var n: usize = 0;
    for (0..4) |i| {
        for (4..8) |j| {
            arr[n] = .{ i, j };
            n += 1;
        }
    }
    break :blk arr;
};

const cmp_adj: [7][2]usize = blk: {
    var arr: [7][2]usize = undefined;
    for (0..7) |i| arr[i] = .{ i, i + 1 };
    break :blk arr;
};

const cmp_sizes = [_]usize{ 28, 6, 6, 16, 7 };

fn cmpCount(pairset_id: usize, g: Grid) i64 {
    var cnt: i64 = 0;
    switch (pairset_id) {
        0 => for (pair_idx) |p| {
            if (g[p[0]] > g[p[1]]) cnt += 1;
        },
        1 => for (cmp_low) |p| {
            if (g[p[0]] > g[p[1]]) cnt += 1;
        },
        2 => for (cmp_high) |p| {
            if (g[p[0]] > g[p[1]]) cnt += 1;
        },
        3 => for (cmp_cross) |p| {
            if (g[p[0]] > g[p[1]]) cnt += 1;
        },
        4 => for (cmp_adj) |p| {
            if (g[p[0]] > g[p[1]]) cnt += 1;
        },
        else => unreachable,
    }
    return cnt;
}

/// The raw scalar each family computes for a given candidate base_id on a
/// grid. This IS the closure: a family's total reach is exactly the set of
/// boolean functions expressible as (rawValue(...) >= t) possibly negated,
/// over its base_id range. No family can produce an output outside its own
/// listed algebraic form no matter the budget.
fn rawValue(f: FamilyId, base_id: usize, g: Grid) f64 {
    switch (f) {
        .mono => {
            const mask = mono_masks[base_id];
            var prod: i64 = 1;
            for (0..NCELLS) |i| {
                if ((mask >> @as(u3, @intCast(i))) & 1 == 1) prod *= g[i];
            }
            return @floatFromInt(prod);
        },
        .pair => {
            const p = pair_idx[base_id];
            return @floatFromInt(g[p[0]] - g[p[1]]);
        },
        .walsh => {
            const mask: usize = mono_masks[base_id];
            var p: i64 = 0;
            for (0..NCELLS) |i| {
                if ((mask >> @as(u6, @intCast(i))) & 1 == 1) p ^= (g[i] & 1);
            }
            return @floatFromInt(p);
        },
        .spectral => {
            const k: f64 = @floatFromInt(base_id + 1);
            var s: i64 = 0;
            for (0..NCELLS) |i| s += g[i];
            const omega = k * std.math.pi / 32.0; // 64 steps spanning (0, 2*pi]
            return @cos(omega * @as(f64, @floatFromInt(s)));
        },
        .worldmod => {
            const k: i64 = @intCast(base_id + 2);
            var s: i64 = 0;
            for (0..NCELLS) |i| s += g[i];
            return @floatFromInt(@mod(s, k));
        },
        .cmp => {
            // Pure comparison-count PARITY only (the direct C09/inversion-
            // parity analogue). An earlier version also offered a raw-count-
            // threshold mode; that mode is a strict-superset-style proxy that
            // can outscore the exact parity predicate on a noisy conjunction
            // label (same failure mode as the old PAIR multi-threshold bug:
            // a near-tied variant wins selection but isn't the exact
            // predicate, so AND-composition silently misses 1.0). Keeping
            // this family to the one relation it is meant to express (count
            // mod 2) removes that ambiguity.
            const cnt = cmpCount(base_id, g);
            return @floatFromInt(@mod(cnt, 2));
        },
    }
}

fn thresholdsFor(f: FamilyId, base_id: usize, buf: []f64) []f64 {
    switch (f) {
        .mono => {
            var n: usize = 0;
            var t: f64 = 0.5;
            while (t < 126.0) : (t += 4.0) {
                buf[n] = t;
                n += 1;
            }
            return buf[0..n];
        },
        .pair => {
            // Single natural cut (raw = g[i]-g[j] >= 1 <=> g[i] > g[j]).
            // A denser grid (e.g. raw>=2, "exceeds by >=2 margin") creates a
            // near-tied variant predicate that is a strict subset of the true
            // order relation -- selectable by chance against a noisy
            // conjunction label, but NOT equal to it, so AND-composition with
            // another family's exact predicate silently fails to reach 1.0.
            // Restricting to the one relation this family is meant to express
            // removes that ambiguity (this IS the family's whole closure).
            buf[0] = 0.5;
            return buf[0..1];
        },
        .walsh => {
            buf[0] = 0.5;
            return buf[0..1];
        },
        .spectral => {
            var n: usize = 0;
            var t: f64 = -0.95;
            while (t < 1.0) : (t += 0.1) {
                buf[n] = t;
                n += 1;
            }
            return buf[0..n];
        },
        .worldmod => {
            const k: f64 = @floatFromInt(base_id + 2);
            var n: usize = 0;
            var t: f64 = 0.5;
            while (t < k - 0.499) : (t += 1.0) {
                buf[n] = t;
                n += 1;
            }
            return buf[0..n];
        },
        .cmp => {
            buf[0] = 0.5;
            return buf[0..1];
        },
    }
}

const Rule = struct { threshold: f64, negate: bool };
const FitResult = struct { rule: Rule, train_acc: f64 };

// -------------------------------------------------------------- world state
var TRAIN_GRIDS: [NTRAIN]Grid = undefined;
var VAL_GRIDS: [NVAL]Grid = undefined;
var TEST_GRIDS: [NTEST]Grid = undefined;
var TRAIN_LABELS: [NTARGETS][NTRAIN]bool = undefined;
var VAL_LABELS: [NTARGETS][NVAL]bool = undefined;
var TEST_LABELS: [NTARGETS][NTEST]bool = undefined;

fn genGrid(r: std.Random) Grid {
    var g: Grid = undefined;
    for (0..NCELLS) |i| g[i] = r.intRangeLessThan(i64, 0, MVAL);
    return g;
}

fn sumCells(g: Grid) i64 {
    var s: i64 = 0;
    for (0..NCELLS) |i| s += g[i];
    return s;
}

/// The 9-target battery. Targets 0-5 each have exactly one "home" family
/// (by construction). Targets 6-7 are CONJUNCTIONS of two different native
/// family predicates (neither family alone can express an AND of two
/// heterogeneous conditions -- only pairwise combination reaches them).
/// Target 8 is the falsification target: a quadratic-residue-style relation
/// mixing squares and a cross term, outside every family's span and outside
/// every pairwise AND/OR/XOR of them.
fn targetLabel(t: usize, g: Grid) bool {
    switch (t) {
        0 => return (g[0] * g[1] * g[2]) >= 30, // home: mono
        1 => return g[3] > g[5], // home: pair
        2 => { // home: walsh, subset {0,2,4} (popcount 3, within mono_masks' span)
            var p: i64 = 0;
            p ^= g[0] & 1;
            p ^= g[2] & 1;
            p ^= g[4] & 1;
            return p == 1;
        },
        3 => { // home: spectral (defined directly on its own basis)
            const s = sumCells(g);
            const val = @cos(@as(f64, @floatFromInt(s)) * (std.math.pi / 6.0));
            return val >= 0;
        },
        4 => return @mod(sumCells(g), 7) == 0, // home: worldmod (D08 analogue)
        5 => { // home: cmp-parity (C09 / inversion-parity analogue)
            var cnt: i64 = 0;
            for (pair_idx) |p| {
                if (g[p[0]] > g[p[1]]) cnt += 1;
            }
            return @mod(cnt, 2) == 1;
        },
        6 => { // conjunction: walsh-pair-parity AND worldmod
            const a = (g[1] & 1) == (g[7] & 1);
            const b = @mod(sumCells(g), 5) == 0;
            return a and b;
        },
        7 => { // conjunction: pair-order AND cmp-cross-parity
            const a = g[2] > g[4];
            var cnt: i64 = 0;
            for (cmp_cross) |p| {
                if (g[p[0]] > g[p[1]]) cnt += 1;
            }
            const b = @mod(cnt, 2) == 0;
            return a and b;
        },
        8 => { // falsification: outside every family's closure by construction
            const val = @mod(g[0] * g[0] + g[1] * g[1] - g[2] * g[3], 13);
            return val == 5;
        },
        else => unreachable,
    }
}

fn buildWorld(seed: u64) void {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    for (0..NTRAIN) |i| TRAIN_GRIDS[i] = genGrid(rng);
    for (0..NVAL) |i| VAL_GRIDS[i] = genGrid(rng);
    for (0..NTEST) |i| TEST_GRIDS[i] = genGrid(rng);
    for (0..NTARGETS) |t| {
        for (0..NTRAIN) |i| TRAIN_LABELS[t][i] = targetLabel(t, TRAIN_GRIDS[i]);
        for (0..NVAL) |i| VAL_LABELS[t][i] = targetLabel(t, VAL_GRIDS[i]);
        for (0..NTEST) |i| TEST_LABELS[t][i] = targetLabel(t, TEST_GRIDS[i]);
    }
}

fn fitAndEval(f: FamilyId, base_id: usize, target: usize) FitResult {
    var raws: [NTRAIN]f64 = undefined;
    for (0..NTRAIN) |i| raws[i] = rawValue(f, base_id, TRAIN_GRIDS[i]);
    var buf: [48]f64 = undefined;
    const th = thresholdsFor(f, base_id, &buf);
    var best_acc: f64 = -1.0;
    var best_rule: Rule = .{ .threshold = th[0], .negate = false };
    for (th) |t| {
        var neg_i: usize = 0;
        while (neg_i < 2) : (neg_i += 1) {
            const neg = neg_i == 1;
            var correct: usize = 0;
            for (0..NTRAIN) |i| {
                const pred = (raws[i] >= t) != neg;
                if (pred == TRAIN_LABELS[target][i]) correct += 1;
            }
            const acc = @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTRAIN));
            if (acc > best_acc) {
                best_acc = acc;
                best_rule = .{ .threshold = t, .negate = neg };
            }
        }
    }
    return .{ .rule = best_rule, .train_acc = best_acc };
}

/// SELECTION metric (never used for final reporting): which candidate /
/// which combo is "best". Held out from TRAIN (where thresholds are fit) but
/// distinct from TEST (where the final, once-only number is read).
fn valAcc(f: FamilyId, base_id: usize, rule: Rule, target: usize) f64 {
    var correct: usize = 0;
    for (0..NVAL) |i| {
        const raw = rawValue(f, base_id, VAL_GRIDS[i]);
        const pred = (raw >= rule.threshold) != rule.negate;
        if (pred == VAL_LABELS[target][i]) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NVAL));
}

fn valPred(f: FamilyId, base_id: usize, rule: Rule, idx: usize) bool {
    const raw = rawValue(f, base_id, VAL_GRIDS[idx]);
    return (raw >= rule.threshold) != rule.negate;
}

/// REPORTING metric only. Must be called exactly once per already-decided
/// winner (a single candidate, or a single combo) -- never used inside a
/// "pick the best of many" search, or it silently becomes test-set fitting.
fn testAcc(f: FamilyId, base_id: usize, rule: Rule, target: usize) f64 {
    var correct: usize = 0;
    for (0..NTEST) |i| {
        const raw = rawValue(f, base_id, TEST_GRIDS[i]);
        const pred = (raw >= rule.threshold) != rule.negate;
        if (pred == TEST_LABELS[target][i]) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTEST));
}

fn testPred(f: FamilyId, base_id: usize, rule: Rule, idx: usize) bool {
    const raw = rawValue(f, base_id, TEST_GRIDS[idx]);
    return (raw >= rule.threshold) != rule.negate;
}

fn mixSeed(a: u64, b: u64, c: u64, d: u64, e: u64) u64 {
    var buf: [40]u8 = undefined;
    std.mem.writeInt(u64, buf[0..8], a, .little);
    std.mem.writeInt(u64, buf[8..16], b, .little);
    std.mem.writeInt(u64, buf[16..24], c, .little);
    std.mem.writeInt(u64, buf[24..32], d, .little);
    std.mem.writeInt(u64, buf[32..40], e, .little);
    return std.hash.Wyhash.hash(0x1234_5678, &buf);
}

fn sampleCandidates(alloc: std.mem.Allocator, n: usize, k: usize, rng: std.Random) []usize {
    var pool = alloc.alloc(usize, n) catch unreachable;
    for (0..n) |i| pool[i] = i;
    rng.shuffle(usize, pool);
    const result = alloc.alloc(usize, k) catch unreachable;
    @memcpy(result, pool[0..k]);
    return result;
}

// --------------------------------------------------------------- solo table
/// solo_table[family][e_idx][repeat][target] = held-out test accuracy of the
/// BEST single-family, single-generator search using the pool's ENTIRE
/// E_total budget devoted to that one family alone. This is the fair
/// baseline for "could a single generator, given the same total compute,
/// reach this target?" -- computed once, shared by every pool.
const SoloTable = struct {
    data: [NFAM][NE][REPEATS][NTARGETS]f64,

    fn get(self: *const SoloTable, f: FamilyId, e_idx: usize, r: usize, t: usize) f64 {
        return self.data[@intFromEnum(f)][e_idx][r][t];
    }
};

fn buildSoloTable(alloc: std.mem.Allocator, base_seed: u64) SoloTable {
    var table: SoloTable = undefined;
    for (0..NFAM) |fi| {
        const fam: FamilyId = @enumFromInt(fi);
        const nb = familyNumBases(fam);
        for (EVALS_LIST, 0..) |e_total, e_idx| {
            for (0..REPEATS) |r| {
                var arena = std.heap.ArenaAllocator.init(alloc);
                defer arena.deinit();
                const aalloc = arena.allocator();
                var prng = std.Random.DefaultPrng.init(mixSeed(base_seed, 999, @intCast(fi), @intCast(e_total), @intCast(r)));
                const rng = prng.random();
                const k = @min(e_total, nb);
                const cands = sampleCandidates(aalloc, nb, k, rng);
                for (0..NTARGETS) |t| {
                    // Maintain the top-TOPK candidates by VAL accuracy: a bounded
                    // "combo slot" set exactly as large as the biggest pool's
                    // member count, so this solo baseline can try same-family
                    // AND/OR/XOR combos too (see the TOPK doc comment) -- a
                    // same-closure pool can never claim "out-of-closure" reach
                    // just by combining two draws from its own family, because
                    // the solo baseline gets to do the identical thing.
                    var topk_base: [TOPK]usize = undefined;
                    var topk_rule: [TOPK]Rule = undefined;
                    var topk_val: [TOPK]f64 = [_]f64{-1.0} ** TOPK;
                    var topk_n: usize = 0;
                    for (cands) |bid| {
                        const fit = fitAndEval(fam, bid, t); // threshold fit on TRAIN
                        const va = valAcc(fam, bid, fit.rule, t); // SELECT on VAL
                        if (topk_n < TOPK or va > topk_val[TOPK - 1]) {
                            var pos = if (topk_n < TOPK) topk_n else TOPK - 1;
                            if (topk_n < TOPK) topk_n += 1;
                            while (pos > 0 and topk_val[pos - 1] < va) {
                                topk_val[pos] = topk_val[pos - 1];
                                topk_base[pos] = topk_base[pos - 1];
                                topk_rule[pos] = topk_rule[pos - 1];
                                pos -= 1;
                            }
                            topk_val[pos] = va;
                            topk_base[pos] = bid;
                            topk_rule[pos] = fit.rule;
                        }
                    }
                    var best_overall_val: f64 = topk_val[0];
                    var best_kind: u8 = 3; // 3 = single candidate (topk[0])
                    var best_a: usize = 0;
                    var best_b: usize = 0;
                    if (topk_n >= 2) {
                        for (0..topk_n) |a| {
                            for (a + 1..topk_n) |b| {
                                var c_and: usize = 0;
                                var c_or: usize = 0;
                                var c_xor: usize = 0;
                                for (0..NVAL) |idx| {
                                    const pa = valPred(fam, topk_base[a], topk_rule[a], idx);
                                    const pb = valPred(fam, topk_base[b], topk_rule[b], idx);
                                    const lab = VAL_LABELS[t][idx];
                                    if ((pa and pb) == lab) c_and += 1;
                                    if ((pa or pb) == lab) c_or += 1;
                                    if ((pa != pb) == lab) c_xor += 1;
                                }
                                const acc_and = @as(f64, @floatFromInt(c_and)) / @as(f64, @floatFromInt(NVAL));
                                const acc_or = @as(f64, @floatFromInt(c_or)) / @as(f64, @floatFromInt(NVAL));
                                const acc_xor = @as(f64, @floatFromInt(c_xor)) / @as(f64, @floatFromInt(NVAL));
                                if (acc_and > best_overall_val) {
                                    best_overall_val = acc_and;
                                    best_kind = 0;
                                    best_a = a;
                                    best_b = b;
                                }
                                if (acc_or > best_overall_val) {
                                    best_overall_val = acc_or;
                                    best_kind = 1;
                                    best_a = a;
                                    best_b = b;
                                }
                                if (acc_xor > best_overall_val) {
                                    best_overall_val = acc_xor;
                                    best_kind = 2;
                                    best_a = a;
                                    best_b = b;
                                }
                            }
                        }
                    }
                    if (best_kind == 3) {
                        table.data[fi][e_idx][r][t] = testAcc(fam, topk_base[0], topk_rule[0], t);
                    } else {
                        var correct: usize = 0;
                        for (0..NTEST) |idx| {
                            const pa = testPred(fam, topk_base[best_a], topk_rule[best_a], idx);
                            const pb = testPred(fam, topk_base[best_b], topk_rule[best_b], idx);
                            const lab = TEST_LABELS[t][idx];
                            const pred = switch (best_kind) {
                                0 => pa and pb,
                                1 => pa or pb,
                                2 => pa != pb,
                                else => unreachable,
                            };
                            if (pred == lab) correct += 1;
                        }
                        table.data[fi][e_idx][r][t] = @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTEST));
                    }
                }
            }
        }
    }
    return table;
}

// ------------------------------------------------------------------- pools
const Member = struct {
    family: FamilyId,
    candidates: []usize,
};

const MemberFit = struct {
    family: FamilyId,
    base_id: usize,
    rule: Rule,
    test_acc: f64,
};

const PoolResult = struct {
    n: usize,
    d: usize,
    e_total: usize,
    repeat: usize,
    entropy: f64,
    evals_actual: u64,
    reach: f64, // out of 8 real targets (0..7)
    ooc6: bool,
    ooc7: bool,
    has_req6: bool,
    has_req7: bool,
    falsification_pool_solve: bool,
    falsification_solo_solve: bool,
    falsification_ooc: bool,
};

fn entropyOf(n: usize, d: usize) f64 {
    if (d == 0) return 0;
    const base = n / d;
    const rem = n % d;
    // rem slots get (base+1) members, (d-rem) slots get base members
    var h: f64 = 0;
    if (rem > 0) {
        const p1 = @as(f64, @floatFromInt(base + 1)) / @as(f64, @floatFromInt(n));
        h -= @as(f64, @floatFromInt(rem)) * p1 * @log2(p1);
    }
    if (d - rem > 0 and base > 0) {
        const p2 = @as(f64, @floatFromInt(base)) / @as(f64, @floatFromInt(n));
        h -= @as(f64, @floatFromInt(d - rem)) * p2 * @log2(p2);
    }
    return h;
}

fn runPool(alloc: std.mem.Allocator, base_seed: u64, n: usize, d: usize, e_total: usize, e_idx: usize, repeat: usize, solo: *const SoloTable) PoolResult {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const aalloc = arena.allocator();

    var prng = std.Random.DefaultPrng.init(mixSeed(base_seed, @intCast(n), @intCast(d), @intCast(e_total), @intCast(repeat)));
    const rng = prng.random();

    var fam_list = FAMILY_ORDER;
    rng.shuffle(FamilyId, &fam_list);
    const active = fam_list[0..d];

    var has_walsh = false;
    var has_worldmod = false;
    var has_pair = false;
    var has_cmp = false;
    for (active) |fam| {
        switch (fam) {
            .walsh => has_walsh = true,
            .worldmod => has_worldmod = true,
            .pair => has_pair = true,
            .cmp => has_cmp = true,
            else => {},
        }
    }
    const has_req6 = has_walsh and has_worldmod;
    const has_req7 = has_pair and has_cmp;

    const evals_per_member = @max(@as(usize, 1), e_total / n);

    var members: [MAX_N]Member = undefined;
    for (0..n) |mi| {
        const fam = active[mi % d];
        const nb = familyNumBases(fam);
        const k = @min(evals_per_member, nb);
        members[mi] = .{ .family = fam, .candidates = sampleCandidates(aalloc, nb, k, rng) };
    }

    var evals_actual: u64 = 0;
    for (0..n) |mi| evals_actual += members[mi].candidates.len;
    evals_actual *= NTARGETS;

    var reach: f64 = 0;
    var ooc6 = false;
    var ooc7 = false;
    var falsification_pool_solve = false;
    var falsification_solo_solve = false;
    var falsification_ooc = false;
    var combo_count_total: u64 = 0;

    for (0..NTARGETS) |t| {
        var member_fits: [MAX_N]MemberFit = undefined;
        for (0..n) |mi| {
            const m = members[mi];
            // SELECT the member's best candidate on VAL (never on TEST).
            var best_local_val: f64 = -1.0;
            var best_base: usize = m.candidates[0];
            var best_rule: Rule = .{ .threshold = 0, .negate = false };
            for (m.candidates) |bid| {
                const fit = fitAndEval(m.family, bid, t); // threshold fit on TRAIN
                const va = valAcc(m.family, bid, fit.rule, t); // SELECT on VAL
                if (va > best_local_val) {
                    best_local_val = va;
                    best_base = bid;
                    best_rule = fit.rule;
                }
            }
            // REPORT this member's single already-decided candidate on TEST, once.
            const tacc = testAcc(m.family, best_base, best_rule, t);
            member_fits[mi] = .{ .family = m.family, .base_id = best_base, .rule = best_rule, .test_acc = tacc };
        }
        var best_test: f64 = 0;
        for (0..n) |mi| best_test = @max(best_test, member_fits[mi].test_acc);

        // Combination: SELECT the best (pair, combinator) by VAL accuracy over
        // ALL C(n,2)*3 candidates (this is the step with real multiple-comparisons
        // risk -- up to ~3*C(16,2)=360 candidates per target -- so it MUST use a
        // split disjoint from the final report). Only the single winning triple
        // is ever measured on TEST, exactly once.
        var best_combo_val: f64 = -1.0;
        var best_combo_kind: u8 = 0; // 0=AND, 1=OR, 2=XOR
        var best_a: usize = 0;
        var best_b: usize = 0;
        if (n >= 2) {
            for (0..n) |a| {
                for (a + 1..n) |b| {
                    const ra = member_fits[a];
                    const rb = member_fits[b];
                    var c_and: usize = 0;
                    var c_or: usize = 0;
                    var c_xor: usize = 0;
                    for (0..NVAL) |idx| {
                        const pa = valPred(ra.family, ra.base_id, ra.rule, idx);
                        const pb = valPred(rb.family, rb.base_id, rb.rule, idx);
                        const lab = VAL_LABELS[t][idx];
                        if ((pa and pb) == lab) c_and += 1;
                        if ((pa or pb) == lab) c_or += 1;
                        if ((pa != pb) == lab) c_xor += 1;
                    }
                    combo_count_total += 3;
                    const acc_and = @as(f64, @floatFromInt(c_and)) / @as(f64, @floatFromInt(NVAL));
                    const acc_or = @as(f64, @floatFromInt(c_or)) / @as(f64, @floatFromInt(NVAL));
                    const acc_xor = @as(f64, @floatFromInt(c_xor)) / @as(f64, @floatFromInt(NVAL));
                    if (acc_and > best_combo_val) {
                        best_combo_val = acc_and;
                        best_combo_kind = 0;
                        best_a = a;
                        best_b = b;
                    }
                    if (acc_or > best_combo_val) {
                        best_combo_val = acc_or;
                        best_combo_kind = 1;
                        best_a = a;
                        best_b = b;
                    }
                    if (acc_xor > best_combo_val) {
                        best_combo_val = acc_xor;
                        best_combo_kind = 2;
                        best_a = a;
                        best_b = b;
                    }
                }
            }
        }
        var best_combo: f64 = 0;
        if (n >= 2) {
            const ra = member_fits[best_a];
            const rb = member_fits[best_b];
            var correct: usize = 0;
            for (0..NTEST) |idx| {
                const pa = testPred(ra.family, ra.base_id, ra.rule, idx);
                const pb = testPred(rb.family, rb.base_id, rb.rule, idx);
                const lab = TEST_LABELS[t][idx];
                const pred = switch (best_combo_kind) {
                    0 => pa and pb,
                    1 => pa or pb,
                    2 => pa != pb,
                    else => unreachable,
                };
                if (pred == lab) correct += 1;
            }
            best_combo = @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTEST));
        }

        const pool_solve = (best_test >= SOLVE_THRESH) or (best_combo >= SOLVE_THRESH);
        var solo_solve = false;
        for (active) |fam| {
            if (solo.get(fam, e_idx, repeat, t) >= SOLVE_THRESH) {
                solo_solve = true;
                break;
            }
        }
        const ooc = pool_solve and !solo_solve;
        if (t < 8) {
            if (ooc) reach += 1.0;
        }
        if (t == 6) ooc6 = ooc;
        if (t == 7) ooc7 = ooc;
        if (t == 8) {
            falsification_pool_solve = pool_solve;
            falsification_solo_solve = solo_solve;
            falsification_ooc = ooc;
        }
    }
    evals_actual += combo_count_total;

    return .{
        .n = n,
        .d = d,
        .e_total = e_total,
        .repeat = repeat,
        .entropy = entropyOf(n, d),
        .evals_actual = evals_actual,
        .reach = reach,
        .ooc6 = ooc6,
        .ooc7 = ooc7,
        .has_req6 = has_req6,
        .has_req7 = has_req7,
        .falsification_pool_solve = falsification_pool_solve,
        .falsification_solo_solve = falsification_solo_solve,
        .falsification_ooc = falsification_ooc,
    };
}

// --------------------------------------------------------------- statistics
fn mean(xs: []const f64) f64 {
    var s: f64 = 0;
    for (xs) |x| s += x;
    return s / @as(f64, @floatFromInt(xs.len));
}

fn pearson(xs: []const f64, ys: []const f64) f64 {
    const mx = mean(xs);
    const my = mean(ys);
    var sxy: f64 = 0;
    var sxx: f64 = 0;
    var syy: f64 = 0;
    for (xs, ys) |x, y| {
        const dx = x - mx;
        const dy = y - my;
        sxy += dx * dy;
        sxx += dx * dx;
        syy += dy * dy;
    }
    if (sxx <= 0 or syy <= 0) return 0;
    return sxy / @sqrt(sxx * syy);
}

fn solveLinearSystem(comptime K: usize, Ain: [K][K]f64, bin: [K]f64) [K]f64 {
    var A = Ain;
    var b = bin;
    for (0..K) |col| {
        // partial pivot
        var piv = col;
        var best = @abs(A[col][col]);
        for (col + 1..K) |r| {
            if (@abs(A[r][col]) > best) {
                best = @abs(A[r][col]);
                piv = r;
            }
        }
        if (piv != col) {
            const tmpRow = A[col];
            A[col] = A[piv];
            A[piv] = tmpRow;
            const tmpB = b[col];
            b[col] = b[piv];
            b[piv] = tmpB;
        }
        const diag = A[col][col];
        if (@abs(diag) < 1e-12) continue;
        for (col + 1..K) |r| {
            const factor = A[r][col] / diag;
            for (col..K) |c| A[r][c] -= factor * A[col][c];
            b[r] -= factor * b[col];
        }
    }
    var x: [K]f64 = [_]f64{0} ** K;
    var i: usize = K;
    while (i > 0) {
        i -= 1;
        var s = b[i];
        for (i + 1..K) |j| s -= A[i][j] * x[j];
        x[i] = if (@abs(A[i][i]) > 1e-12) s / A[i][i] else 0;
    }
    return x;
}

fn ols(comptime K: usize, predictors: [K][]const f64, y: []const f64) [K]f64 {
    const n = y.len;
    var A: [K][K]f64 = [_][K]f64{[_]f64{0} ** K} ** K;
    var b: [K]f64 = [_]f64{0} ** K;
    for (0..K) |a| {
        for (0..K) |c| {
            var s: f64 = 0;
            for (0..n) |i| s += predictors[a][i] * predictors[c][i];
            A[a][c] = s;
        }
        var sb: f64 = 0;
        for (0..n) |i| sb += predictors[a][i] * y[i];
        b[a] = sb;
    }
    return solveLinearSystem(K, A, b);
}

fn r2FromCoeffs(comptime K: usize, coeffs: [K]f64, predictors: [K][]const f64, y: []const f64) f64 {
    const n = y.len;
    const my = mean(y);
    var ss_res: f64 = 0;
    var ss_tot: f64 = 0;
    for (0..n) |i| {
        var yhat: f64 = 0;
        for (0..K) |k| yhat += coeffs[k] * predictors[k][i];
        ss_res += (y[i] - yhat) * (y[i] - yhat);
        ss_tot += (y[i] - my) * (y[i] - my);
    }
    if (ss_tot <= 0) return 0;
    return 1.0 - ss_res / ss_tot;
}

fn residualsOf(alloc: std.mem.Allocator, comptime K: usize, predictors: [K][]const f64, y: []const f64) []f64 {
    const coeffs = ols(K, predictors, y);
    const n = y.len;
    var res = alloc.alloc(f64, n) catch unreachable;
    for (0..n) |i| {
        var yhat: f64 = 0;
        for (0..K) |k| yhat += coeffs[k] * predictors[k][i];
        res[i] = y[i] - yhat;
    }
    return res;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const out = std.io.getStdOut().writer();
    const err = std.io.getStdErr().writer();

    var timer = try std.time.Timer.start();

    buildWorld(WORLD_SEED);

    try err.print("=== target base rates (train split, n={d}) ===\n", .{NTRAIN});
    for (0..NTARGETS) |t| {
        var pos: usize = 0;
        for (0..NTRAIN) |i| {
            if (TRAIN_LABELS[t][i]) pos += 1;
        }
        const rate = @as(f64, @floatFromInt(pos)) / @as(f64, @floatFromInt(NTRAIN));
        try err.print("  target {d}: positive_rate={d:.4} majority_baseline={d:.4}\n", .{ t, rate, @max(rate, 1.0 - rate) });
    }

    try err.print("building solo baseline table ({d} families x {d} budgets x {d} repeats x {d} targets)...\n", .{ NFAM, NE, REPEATS, NTARGETS });
    const solo = buildSoloTable(alloc, WORLD_SEED ^ 0xC0FFEE);
    try err.print("solo table built at t={d}ms\n", .{timer.read() / std.time.ns_per_ms});

    try err.print("\n=== solo baseline: best single-family, full E_total budget, held-out accuracy ===\n", .{});
    for (EVALS_LIST, 0..) |e_total, e_idx| {
        try err.print("  E_total={d}:\n", .{e_total});
        for (0..NTARGETS) |t| {
            try err.print("    target {d}:", .{t});
            for (FAMILY_ORDER) |fam| {
                var best: f64 = 0;
                for (0..REPEATS) |r| best = @max(best, solo.get(fam, e_idx, r, t));
                try err.print(" {s}={d:.3}", .{ familyName(fam), best });
            }
            try err.print("\n", .{});
        }
    }

    try out.print("pool_id,N,D,entropy,E_total,evals_actual,repeat,reach,ooc6,ooc7,has_req6,has_req7,falsification_pool_solve,falsification_solo_solve,falsification_ooc\n", .{});

    var rows_n = std.ArrayList(f64).init(alloc);
    defer rows_n.deinit();
    var rows_d = std.ArrayList(f64).init(alloc);
    defer rows_d.deinit();
    var rows_evals = std.ArrayList(f64).init(alloc);
    defer rows_evals.deinit();
    var rows_reach = std.ArrayList(f64).init(alloc);
    defer rows_reach.deinit();
    var rows_etot = std.ArrayList(f64).init(alloc);
    defer rows_etot.deinit();
    var rows_ooc6 = std.ArrayList(bool).init(alloc);
    defer rows_ooc6.deinit();
    var rows_ooc7 = std.ArrayList(bool).init(alloc);
    defer rows_ooc7.deinit();
    var rows_req6 = std.ArrayList(bool).init(alloc);
    defer rows_req6.deinit();
    var rows_req7 = std.ArrayList(bool).init(alloc);
    defer rows_req7.deinit();

    var pool_id: usize = 0;
    var falsification_ever_solved_by_pool: bool = false;
    var falsification_ever_solved_by_solo: bool = false;

    for (N_LIST) |n| {
        const d_max = @min(n, NFAM);
        var d: usize = 1;
        while (d <= d_max) : (d += 1) {
            for (EVALS_LIST, 0..) |e_total, e_idx| {
                for (0..REPEATS) |repeat| {
                    const res = runPool(alloc, WORLD_SEED ^ 0xA5A5_1234, n, d, e_total, e_idx, repeat, &solo);
                    try out.print("{d},{d},{d},{d:.4},{d},{d},{d},{d:.1},{},{},{},{},{},{},{}\n", .{
                        pool_id, res.n, res.d, res.entropy, res.e_total, res.evals_actual, res.repeat,
                        res.reach, res.ooc6, res.ooc7, res.has_req6, res.has_req7,
                        res.falsification_pool_solve, res.falsification_solo_solve, res.falsification_ooc,
                    });
                    try rows_n.append(@floatFromInt(res.n));
                    try rows_d.append(@floatFromInt(res.d));
                    try rows_evals.append(@floatFromInt(res.evals_actual));
                    try rows_reach.append(res.reach);
                    try rows_etot.append(@floatFromInt(res.e_total));
                    try rows_ooc6.append(res.ooc6);
                    try rows_ooc7.append(res.ooc7);
                    try rows_req6.append(res.has_req6);
                    try rows_req7.append(res.has_req7);
                    if (res.falsification_pool_solve) falsification_ever_solved_by_pool = true;
                    if (res.falsification_solo_solve) falsification_ever_solved_by_solo = true;
                    pool_id += 1;
                }
            }
        }
    }

    try err.print("\n{d} pool configs run, t={d}ms\n", .{ pool_id, timer.read() / std.time.ns_per_ms });

    // -------------------------------------------------------- regression
    const n_rows = rows_reach.items.len;
    var ones = try alloc.alloc(f64, n_rows);
    defer alloc.free(ones);
    for (0..n_rows) |i| ones[i] = 1.0;

    const xs_n = rows_n.items;
    const xs_d = rows_d.items;
    const xs_evals = rows_evals.items;
    const ys = rows_reach.items;

    const r_n = pearson(xs_n, ys);
    const r_d = pearson(xs_d, ys);
    const r_evals = pearson(xs_evals, ys);

    try err.print("\n=== single-predictor correlations with REACH (n={d} pool configs) ===\n", .{n_rows});
    try err.print("  corr(reach, N)     = {d:.4}   R^2 = {d:.4}\n", .{ r_n, r_n * r_n });
    try err.print("  corr(reach, D)     = {d:.4}   R^2 = {d:.4}\n", .{ r_d, r_d * r_d });
    try err.print("  corr(reach, evals) = {d:.4}   R^2 = {d:.4}\n", .{ r_evals, r_evals * r_evals });

    const preds4: [4][]const f64 = .{ ones, xs_n, xs_d, xs_evals };
    const coeffs4 = ols(4, preds4, ys);
    const r2_full = r2FromCoeffs(4, coeffs4, preds4, ys);
    try err.print("\n=== full model: reach ~ b0 + b1*N + b2*D + b3*evals ===\n", .{});
    try err.print("  b0={d:.4} b1(N)={d:.4} b2(D)={d:.4} b3(evals)={d:.6}   R^2={d:.4}\n", .{
        coeffs4[0], coeffs4[1], coeffs4[2], coeffs4[3], r2_full,
    });

    // partial correlation of D with reach, controlling for {N, evals}
    {
        const predsNE: [3][]const f64 = .{ ones, xs_n, xs_evals };
        const res_d = residualsOf(alloc, 3, predsNE, xs_d);
        defer alloc.free(res_d);
        const res_y = residualsOf(alloc, 3, predsNE, ys);
        defer alloc.free(res_y);
        const pc_d = pearson(res_d, res_y);
        try err.print("  partial corr(D, reach | N, evals)     = {d:.4}   (R^2={d:.4})\n", .{ pc_d, pc_d * pc_d });
    }
    // partial correlation of N with reach, controlling for {D, evals}
    {
        const predsDE: [3][]const f64 = .{ ones, xs_d, xs_evals };
        const res_n = residualsOf(alloc, 3, predsDE, xs_n);
        defer alloc.free(res_n);
        const res_y = residualsOf(alloc, 3, predsDE, ys);
        defer alloc.free(res_y);
        const pc_n = pearson(res_n, res_y);
        try err.print("  partial corr(N, reach | D, evals)     = {d:.4}   (R^2={d:.4})\n", .{ pc_n, pc_n * pc_n });
    }
    // partial correlation of evals with reach, controlling for {N, D}
    {
        const predsND: [3][]const f64 = .{ ones, xs_n, xs_d };
        const res_e = residualsOf(alloc, 3, predsND, xs_evals);
        defer alloc.free(res_e);
        const res_y = residualsOf(alloc, 3, predsND, ys);
        defer alloc.free(res_y);
        const pc_e = pearson(res_e, res_y);
        try err.print("  partial corr(evals, reach | N, D)     = {d:.4}   (R^2={d:.4})\n", .{ pc_e, pc_e * pc_e });
    }

    // ------------------------------------- fixed-N, fixed-E_total: D effect
    try err.print("\n=== fixed-N, fixed-E_total: mean REACH by D ===\n", .{});
    for (N_LIST) |n| {
        const d_max = @min(n, NFAM);
        if (d_max < 2) continue;
        for (EVALS_LIST) |e_total| {
            try err.print("  N={d:>2} E_total={d:>3}:", .{ n, e_total });
            var d: usize = 1;
            while (d <= d_max) : (d += 1) {
                var sum_r: f64 = 0;
                var cnt: usize = 0;
                for (0..n_rows) |i| {
                    if (@as(usize, @intFromFloat(xs_n[i])) == n and @as(usize, @intFromFloat(xs_d[i])) == d and @as(usize, @intFromFloat(rows_etot.items[i])) == e_total) {
                        sum_r += ys[i];
                        cnt += 1;
                    }
                }
                const m = if (cnt > 0) sum_r / @as(f64, @floatFromInt(cnt)) else -1;
                try err.print(" D={d}:{d:.2}", .{ d, m });
            }
            try err.print("\n", .{});
        }
    }

    // ----------------------------------- falsification target 8 report
    try err.print("\n=== falsification target (index 8, outside every family's closure) ===\n", .{});
    try err.print("  ever solved by ANY pool (best member or combo)  : {}\n", .{falsification_ever_solved_by_pool});
    try err.print("  ever solved by ANY solo family (full budget)    : {}\n", .{falsification_ever_solved_by_solo});

    // ----------------------------------- conjunction targets: right-direction check
    try err.print("\n=== conjunction targets 6/7: does having the REQUIRED pair of families matter? ===\n", .{});
    {
        var w6_solve: usize = 0;
        var w6_total: usize = 0;
        var wo6_solve: usize = 0;
        var wo6_total: usize = 0;
        var w7_solve: usize = 0;
        var w7_total: usize = 0;
        var wo7_solve: usize = 0;
        var wo7_total: usize = 0;
        for (0..n_rows) |i| {
            if (rows_req6.items[i]) {
                w6_total += 1;
                if (rows_ooc6.items[i]) w6_solve += 1;
            } else {
                wo6_total += 1;
                if (rows_ooc6.items[i]) wo6_solve += 1;
            }
            if (rows_req7.items[i]) {
                w7_total += 1;
                if (rows_ooc7.items[i]) w7_solve += 1;
            } else {
                wo7_total += 1;
                if (rows_ooc7.items[i]) wo7_solve += 1;
            }
        }
        try err.print("  target 6 (needs walsh+worldmod): pools WITH both families solve {d}/{d} ({d:.1}%); pools WITHOUT solve {d}/{d} ({d:.1}%)\n", .{
            w6_solve, w6_total, 100.0 * @as(f64, @floatFromInt(w6_solve)) / @as(f64, @floatFromInt(@max(w6_total, 1))),
            wo6_solve, wo6_total, 100.0 * @as(f64, @floatFromInt(wo6_solve)) / @as(f64, @floatFromInt(@max(wo6_total, 1))),
        });
        try err.print("  target 7 (needs pair+cmp):       pools WITH both families solve {d}/{d} ({d:.1}%); pools WITHOUT solve {d}/{d} ({d:.1}%)\n", .{
            w7_solve, w7_total, 100.0 * @as(f64, @floatFromInt(w7_solve)) / @as(f64, @floatFromInt(@max(w7_total, 1))),
            wo7_solve, wo7_total, 100.0 * @as(f64, @floatFromInt(wo7_solve)) / @as(f64, @floatFromInt(@max(wo7_total, 1))),
        });
    }

    try err.print("\ndone, total t={d}ms\n", .{timer.read() / std.time.ns_per_ms});
}
