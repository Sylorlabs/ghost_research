//! I53-style depth-push red-team attack on wcore's Claim-C irreducibility certifier
//! (round 2026-07-10b). New file; imports existing wcore sources READ-ONLY
//! (inv_alien / inv_coevo / inv_open / inv_atomforge) and PORTS the private helpers
//! it needs (chain-vs-chain agreement) rather than modifying them, same convention
//! `inv_iterate.zig` used for the A1-A6 round this file re-attacks.
//!
//! CONTEXT: I53 (docs/research/i53_falsification_2026_07_10.md) showed the synergy
//! substrate's "outside the closure" walls were (depth, register-count) resource
//! bounds: a pair-necessity claim made at depth <=3 broke at depth 6. wcore's Claim C
//! ("a fixed atom set cannot invent -- everything reduces", INDEX.md: "85/86 behaviours
//! reducible at depth 4; 1 exception reducible at depth 5; 0 survivors at deeper
//! budget"; certifier "16/16 kill-tests, non-vacuous at depth 8") and the atom-forge's
//! own irreducibility certifier (`inv_atomforge.reducibleLib`, COMPOSE_DEPTH=3, used
//! to CERTIFY promotions in the A1-A6 iterated-promotion loop) carry the same risk in
//! the OPPOSITE direction: an "irreducible at depth 3" promotion verdict may flip to
//! reducible at depth 3+k, making the promotion bogus (a1a6's own retro-audit already
//! caught 1/20 leaking this way at depth 4 -- ~5%). This file pushes that finding
//! deeper and systematically, exactly as i53 pushed the synergy substrate.
//!
//! HONEST NOTE ON THE TASK BRIEF: the brief named `wcore/src/checker.zig` and
//! `evaluator.zig` as certifier files to read. They are NOT -- `checker.zig` is a
//! total STLC type-checker and `evaluator.zig` a small beta-reducer for a totally
//! separate W-type/dependent-type research line (RESEARCH_QUESTIONS.md Section 11),
//! with no connection to Claim C or irreducibility. Both were read (as instructed,
//! read-only) and confirmed unrelated. The actual Claim-C / irreducibility-certifier
//! code is `inv_coevo.zig` (`reducible`/`reducibleWithBudget`/`behaviorMatches`,
//! Stage-genome based -- the mechanism behind the 85/86, budget_scan.md, and
//! claim_c_breadth.md 16-seed kill-test numbers) and `inv_atomforge.zig`
//! (`reducibleLib`, atom-Program-library based -- the mechanism behind the A1-A6
//! atom-forge promotion loop this file targets, since the task explicitly asks to
//! reuse the a1a6 seeds/20-promoted-atoms artifact). This file attacks
//! `inv_atomforge.reducibleLib` (primary target, with the real promoted-atom
//! artifact) and re-runs the `inv_coevo` distinct-count kill-test through the SAME
//! attack machinery as an independent non-vacuity cross-check.
//!
//! WHAT THIS DOES:
//!   1. Reproduces the a1a6 baseline: re-run the exact atom-forge promotion loop
//!      (ported from `inv_iterate.zig`, since `forge.MAX_ROUNDS`=8 < a1a6's 10 rounds)
//!      for seeds 0xA70F and 0x5EED2, producing the same 20 promoted atoms, at the
//!      PRODUCTION certifier depth (`forge.COMPOSE_DEPTH`=3).
//!   2. Depth push: re-certifies every promoted atom against (a) its promotion-time
//!      PREFIX library and (b) the FINAL library minus itself, at depths beyond
//!      production (+1/+2/+3 and further where library size allows), extending
//!      a1a6's own A5/A6 audit (which covered prefix d4/d5, final-minus-self d3/d4)
//!      one-to-several levels deeper. Depth caps are library-size-ADAPTIVE and
//!      wall-clock-bounded (documented explicitly, per-row, in the CSV -- "budget,
//!      not proof" exactly as i53 and budget_scan.md qualify their own depth claims).
//!   3. Every verdict flip (irreducible -> reducible) records the witness chain and
//!      is independently re-verified with a LARGER sample (64x64=4096 symbols) and a
//!      seed never used by the certifier search.
//!   4. Vacuity check: `inv_coevo.distinctCountProg()` (the hand-built true outsider
//!      used everywhere in wcore as the certifier kill-test) is re-run through this
//!      SAME reducibleLib-based attack machinery -- 16 certifier-seed replicates
//!      against the base-5 library (depth 8, matching INDEX.md's framing) and a
//!      subset against both reproduced final 15-atom libraries at the same pushed
//!      depths used on the real atoms -- confirming the certifier does not ALSO
//!      start rubber-stamping a known non-member "reducible" once the search space
//!      is large enough to hit a threshold false-positive by sheer combinatorics.
//!
//! REGISTER/WIDTH AXIS: `reducibleLib` composes whole atom-Programs by chaining their
//! STREAM OUTPUTS (`applyChain`); it has no register-count or bit-width parameter of
//! its own (unlike I53's synergy substrate, whose K=2-register straight-line dataflow
//! was itself a wall). The only resource axis exposed by this certifier is composition
//! DEPTH, which is what this file pushes. This is stated explicitly rather than
//! silently skipped.
//!
//! Build:  cd wcore && zig build-exe -O ReleaseFast src/claimc_attack.zig
//! Run:    ./claimc_attack ../results/claimc_attack_2026_07_10.csv
//! Threads: exactly 2 (one per research seed), joined before the single-threaded
//! kill-test phase. Wall-clock bounded internally (see CAP_NS_* below) to fit <=15 min.

const std = @import("std");
const alien = @import("inv_alien.zig");
const coevo = @import("inv_coevo.zig");
const open = @import("inv_open.zig");
const forge = @import("inv_atomforge.zig");

const V: usize = alien.CANON_BASE;
const PROD_DEPTH: usize = forge.COMPOSE_DEPTH; // = 3, the production certifier depth
const SEEDS = [_]u64{ 0xA70F, 0x5EED2 };
const POP: usize = 90;
const GENS: usize = 45;
const ROUNDS: usize = 10; // matches a1a6_iterated_promotion.md exactly
const CENSUS_CAP: usize = 80;

// Per-call wall-clock safety nets (a call that exceeds its cap mid-depth-level
// returns .irreducible_incomplete with depth_reached = last FULLY completed level).
const CAP_NS_PREFIX: u64 = 20 * std.time.ns_per_s;
const CAP_NS_FINAL: u64 = 15 * std.time.ns_per_s;
const CAP_NS_KILL_BASE: u64 = 45 * std.time.ns_per_s; // base-5 depth-8 must COMPLETE (measured ~25s/run)
const CAP_NS_KILL_FINAL: u64 = 15 * std.time.ns_per_s; // 15-atom finals: budget-capped, depth_reached recorded

const MAX_CHAIN: usize = 12; // headroom past PROD_DEPTH+3=6 for small-n atoms

// =============================================================================
// Ported (private in inv_atomforge.zig): chain-vs-atom agreement fraction. Same
// logic as forge's matchesChain, but returns the fraction instead of a threshold
// bool, so we can track "how close" even irreducible verdicts got (a stronger
// non-vacuity statement than a bare pass/fail).
// =============================================================================
fn chainAgreementFrac(prog: *const alien.Program, lib: []const alien.Program, idxs: []const usize, n_seq: usize, L: usize, seed: u64) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var tgt: [256]u8 = undefined;
    var got: [256]u8 = undefined;
    var agree: usize = 0;
    var total: usize = 0;
    for (0..n_seq) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        forge.applyChain(lib, idxs, syms[0..L], tgt[0..L]);
        alien.runStream(prog, syms[0..L], got[0..L]);
        for (0..L) |i| {
            total += 1;
            if (got[i] == tgt[i]) agree += 1;
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total));
}

const CertOutcome = enum { reducible, irreducible_complete, irreducible_incomplete };

const CertResult = struct {
    outcome: CertOutcome = .irreducible_complete,
    depth_requested: usize = 0,
    depth_reached: usize = 0, // deepest level FULLY enumerated (or the witness depth)
    witness_len: usize = 0,
    witness: [MAX_CHAIN]usize = undefined,
    best_agree: f64 = 0, // max agreement fraction seen across every combo tried
    ms: u64 = 0,
};

/// Exhaustive composition-depth certifier with witness capture and a wall-clock
/// safety net. Logically identical to `forge.reducibleLib` (same threshold, same
/// chain semantics) but (a) returns the witness chain, (b) tracks the closest
/// approach even when irreducible, (c) is not limited to depth<=8 by a fixed [8]usize
/// buffer, (d) aborts cleanly past `cap_ns` instead of running unbounded.
fn certify(prog: *const alien.Program, lib: []const alien.Program, max_depth: usize, seed: u64, cap_ns: u64) CertResult {
    var res = CertResult{ .depth_requested = max_depth };
    var timer = std.time.Timer.start() catch unreachable;
    const n = lib.len;
    if (n == 0) return res;
    var d: usize = 1;
    while (d <= max_depth) : (d += 1) {
        var total: usize = 1;
        for (0..d) |_| total *= n;
        var idx: usize = 0;
        while (idx < total) : (idx += 1) {
            if (idx % 4096 == 0 and timer.read() > cap_ns) {
                res.outcome = .irreducible_incomplete;
                res.ms = timer.read() / std.time.ns_per_ms;
                return res;
            }
            var idxs: [MAX_CHAIN]usize = undefined;
            var x = idx;
            for (0..d) |j| {
                idxs[j] = x % n;
                x /= n;
            }
            const frac = chainAgreementFrac(prog, lib, idxs[0..d], 8, 28, seed);
            if (frac > res.best_agree) res.best_agree = frac;
            if (frac >= forge.MATCH_THRESHOLD) {
                res.outcome = .reducible;
                res.witness_len = d;
                @memcpy(res.witness[0..d], idxs[0..d]);
                res.depth_reached = d;
                res.ms = timer.read() / std.time.ns_per_ms;
                return res;
            }
        }
        res.depth_reached = d;
    }
    res.ms = timer.read() / std.time.ns_per_ms;
    return res;
}

/// Independent re-verification of a witness: a LARGER sample (64x64=4096 symbols)
/// with a seed distinct from the certifier's search seed. No flip is reported
/// without this check.
fn independentVerify(prog: *const alien.Program, lib: []const alien.Program, witness: []const usize, indep_seed: u64) f64 {
    return chainAgreementFrac(prog, lib, witness, 64, 64, indep_seed);
}

fn outcomeStr(o: CertOutcome) []const u8 {
    return switch (o) {
        .reducible => "reducible",
        .irreducible_complete => "irreducible_complete",
        .irreducible_incomplete => "irreducible_incomplete",
    };
}

fn prefixTargetDepth(n: usize) usize {
    if (n <= 6) return 9;
    if (n <= 9) return 8;
    if (n <= 12) return 7;
    return 6; // n in 13..15 -> PROD_DEPTH+3
}

fn finalTargetDepth(n: usize) usize {
    if (n <= 9) return 7;
    if (n <= 12) return 6;
    return 6; // n in 13..15 (final-minus-self is always ~14) -> aim PROD_DEPTH+3, cap does the rest
}

fn witnessLabel(buf: []u8, w: []const usize) ![]const u8 {
    var stream = std.io.fixedBufferStream(buf);
    const writer = stream.writer();
    try writer.writeAll("[");
    for (w, 0..) |ix, j| {
        if (j > 0) try writer.writeAll(",");
        try writer.print("{d}", .{ix});
    }
    try writer.writeAll("]");
    return stream.getWritten();
}

// =============================================================================
// Phase 1: reproduce the a1a6 promotion loop (ported from inv_iterate.zig's
// runSeed, minus the A4 held-out battery which this attack does not need).
// =============================================================================

const PromotedAtom = struct {
    prog: alien.Program,
    round: usize,
    prefix_len: usize,
};

const MAX_PROMOTED: usize = ROUNDS;

const AtomRow = struct {
    kind: []const u8, // "atom" or "killtest"
    seed: u64, // research seed, or certifier replicate seed for killtest rows
    label: [16]u8,
    label_len: usize,
    round: usize,
    lib_size: usize,
    check: []const u8, // "prefix" / "final_minus_self" / library name for killtest
    depth_requested: usize,
    depth_reached: usize,
    outcome: []const u8,
    witness: [96]u8,
    witness_len: usize,
    best_agree: f64,
    indep_agree: f64, // -1 => n/a (no flip to verify)
    ms: u64,
};

const MAX_ROWS: usize = 128;

const SeedResult = struct {
    seed: u64,
    n_promoted: usize = 0,
    promoted: [MAX_PROMOTED]PromotedAtom = undefined,
    final_atoms: forge.AtomLib = .{},
    rows: [MAX_ROWS]AtomRow = undefined,
    n_rows: usize = 0,
    log: std.ArrayList(u8) = undefined,
    self_check_pass: bool = true, // certify()@depth3 agrees with forge.reducibleLib()@depth3
    self_check_n: usize = 0,
};

fn addRow(sr: *SeedResult, row: AtomRow) void {
    if (sr.n_rows < MAX_ROWS) {
        sr.rows[sr.n_rows] = row;
        sr.n_rows += 1;
    }
}

fn mkLabel(k: usize) [16]u8 {
    var buf = [_]u8{0} ** 16;
    _ = std.fmt.bufPrint(&buf, "inv{d}", .{k}) catch {};
    return buf;
}

fn runSeedAttack(seed: u64, sr: *SeedResult) void {
    sr.seed = seed;
    sr.log = std.ArrayList(u8).init(std.heap.page_allocator);
    const lw = sr.log.writer();

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const al = arena_state.allocator();

    const dseed = seed ^ 0x1F0; // matches forge.runPromotionSnapshots / inv_iterate
    const fseed = seed +% 0xA70F;

    lw.print("\n================ SEED 0x{X} ================\n", .{seed}) catch {};
    lw.print("params: pop={d} gens={d} rounds={d} depth_budget={d} census_cap={d}\n", .{ POP, GENS, ROUNDS, PROD_DEPTH, CENSUS_CAP }) catch {};

    var atoms = forge.baseAtoms();
    var n_promoted: usize = 0;

    var round: usize = 1;
    while (round <= ROUNDS) : (round += 1) {
        var timer = std.time.Timer.start() catch unreachable;
        const lib_before = atoms.len;

        var prng = std.Random.DefaultPrng.init(seed +% round *% 0x9E3779B97F4A7C15);
        var archive = open.search(al, prng.random(), .{ .pop = POP, .gens = GENS, .info = true, .seed = dseed }) catch {
            lw.print("[round {d}] search FAILED (OOM?)\n", .{round}) catch {};
            break;
        };

        var cleanlist = std.ArrayList(open.Member).init(al);
        for (archive.items) |m| {
            if (forge.clean(&m.prog, dseed)) cleanlist.append(m) catch {};
        }
        std.mem.sort(open.Member, cleanlist.items, {}, struct {
            fn lt(_: void, a: open.Member, b: open.Member) bool {
                return a.prog.len() < b.prog.len();
            }
        }.lt);

        const n_checked = @min(CENSUS_CAP, cleanlist.items.len);
        var n_irred: usize = 0;
        var first_irred: ?alien.Program = null;
        for (cleanlist.items[0..n_checked]) |m| {
            if (!forge.reducibleLib(&m.prog, atoms.slice(), PROD_DEPTH, fseed)) {
                n_irred += 1;
                if (first_irred == null) first_irred = m.prog;
            }
        }

        if (first_irred == null or atoms.len >= forge.MAX_ATOMS) {
            const ms = timer.read() / std.time.ns_per_ms;
            lw.print("[round {d}] archive={d} clean={d} checked={d} irreducible=0 -> FIXED POINT ({d} ms)\n", .{ round, archive.items.len, cleanlist.items.len, n_checked, ms }) catch {};
            archive.deinit();
            _ = arena_state.reset(.retain_capacity);
            break;
        }

        const new_atom = first_irred.?;
        atoms.appendAssumeCapacity(new_atom);

        // instrument self-check: my certify() at PROD_DEPTH must agree with the
        // real production forge.reducibleLib() at PROD_DEPTH on this exact atom
        // (cross-validates the ported certifier before trusting deeper pushes).
        const prefix_before = lib_before;
        var prefix_lib = forge.AtomLib{};
        for (0..prefix_before) |j| prefix_lib.appendAssumeCapacity(atoms.slice()[j]);
        const my_verdict = certify(&new_atom, prefix_lib.slice(), PROD_DEPTH, fseed, CAP_NS_PREFIX);
        const prod_verdict_reducible = forge.reducibleLib(&new_atom, prefix_lib.slice(), PROD_DEPTH, fseed);
        const my_reducible = (my_verdict.outcome == .reducible);
        sr.self_check_n += 1;
        if (my_reducible != prod_verdict_reducible) sr.self_check_pass = false;

        n_promoted += 1;
        sr.promoted[n_promoted - 1] = .{ .prog = new_atom, .round = round, .prefix_len = prefix_before };

        const ms = timer.read() / std.time.ns_per_ms;
        lw.print("[round {d}] archive={d} clean={d} checked={d} irreducible={d} PROMOTE len={d} -> lib={d} ({d} ms) [self-check {s}]\n", .{ round, archive.items.len, cleanlist.items.len, n_checked, n_irred, new_atom.len(), atoms.len, ms, if (my_reducible == prod_verdict_reducible) "OK" else "MISMATCH" }) catch {};

        archive.deinit();
        _ = arena_state.reset(.retain_capacity);
    }

    sr.n_promoted = n_promoted;
    sr.final_atoms = atoms;

    lw.print("reproduction: lib {d} -> {d}, {d} atoms promoted, instrument self-check {s} ({d}/{d})\n", .{ forge.BASE_ATOMS, atoms.len, n_promoted, if (sr.self_check_pass) "PASS" else "FAIL", sr.self_check_n, sr.self_check_n }) catch {};

    // =========================================================================
    // Phase 2: depth push on every promoted atom, vs (a) promotion-time prefix,
    // (b) final library minus itself. Independent verification of any flip.
    // =========================================================================
    lw.print("\n--- depth push (production depth = {d}) ---\n", .{PROD_DEPTH}) catch {};
    lw.writeAll("  atom  round  prefix_n  check              depth_req  depth_reached  outcome                witness          best_agree  indep_verify\n") catch {};

    var wbuf: [96]u8 = undefined;

    for (0..n_promoted) |k| {
        const pa = sr.promoted[k];
        const label = mkLabel(k);

        // (a) vs promotion-time prefix
        var prefix = forge.AtomLib{};
        for (0..pa.prefix_len) |j| prefix.appendAssumeCapacity(atoms.slice()[j]);
        const d_target_p = prefixTargetDepth(prefix.len);
        const rp = certify(&pa.prog, prefix.slice(), d_target_p, fseed, CAP_NS_PREFIX);
        var indep_p: f64 = -1;
        var wlabel_p: []const u8 = "[]";
        if (rp.outcome == .reducible) {
            indep_p = independentVerify(&pa.prog, prefix.slice(), rp.witness[0..rp.witness_len], seed ^ 0xBADA55);
            wlabel_p = witnessLabel(&wbuf, rp.witness[0..rp.witness_len]) catch "[]";
        }
        lw.print("  {s:<5} {d:>4}  {d:>7}  {s:<18}  {d:>8}  {d:>12}  {s:<21}  {s:<15}  {d:.4}      {d:.4}\n", .{
            std.mem.sliceTo(&label, 0), pa.round, prefix.len, "prefix", d_target_p, rp.depth_reached, outcomeStr(rp.outcome), wlabel_p, rp.best_agree, indep_p,
        }) catch {};
        var row1 = AtomRow{
            .kind = "atom",
            .seed = seed,
            .label = label,
            .label_len = std.mem.sliceTo(&label, 0).len,
            .round = pa.round,
            .lib_size = prefix.len,
            .check = "prefix",
            .depth_requested = d_target_p,
            .depth_reached = rp.depth_reached,
            .outcome = outcomeStr(rp.outcome),
            .witness = undefined,
            .witness_len = wlabel_p.len,
            .best_agree = rp.best_agree,
            .indep_agree = indep_p,
            .ms = rp.ms,
        };
        @memcpy(row1.witness[0..wlabel_p.len], wlabel_p);
        addRow(sr, row1);

        // (b) vs final library minus itself
        var minus = forge.AtomLib{};
        const self_idx = forge.BASE_ATOMS + k;
        for (0..atoms.len) |j| {
            if (j != self_idx) minus.appendAssumeCapacity(atoms.slice()[j]);
        }
        const d_target_f = finalTargetDepth(minus.len);
        const rf = certify(&pa.prog, minus.slice(), d_target_f, fseed, CAP_NS_FINAL);
        var indep_f: f64 = -1;
        var wlabel_f: []const u8 = "[]";
        if (rf.outcome == .reducible) {
            indep_f = independentVerify(&pa.prog, minus.slice(), rf.witness[0..rf.witness_len], seed ^ 0xBADA55);
            wlabel_f = witnessLabel(&wbuf, rf.witness[0..rf.witness_len]) catch "[]";
        }
        lw.print("  {s:<5} {d:>4}  {d:>7}  {s:<18}  {d:>8}  {d:>12}  {s:<21}  {s:<15}  {d:.4}      {d:.4}\n", .{
            std.mem.sliceTo(&label, 0), pa.round, minus.len, "final_minus_self", d_target_f, rf.depth_reached, outcomeStr(rf.outcome), wlabel_f, rf.best_agree, indep_f,
        }) catch {};
        var row2 = AtomRow{
            .kind = "atom",
            .seed = seed,
            .label = label,
            .label_len = std.mem.sliceTo(&label, 0).len,
            .round = pa.round,
            .lib_size = minus.len,
            .check = "final_minus_self",
            .depth_requested = d_target_f,
            .depth_reached = rf.depth_reached,
            .outcome = outcomeStr(rf.outcome),
            .witness = undefined,
            .witness_len = wlabel_f.len,
            .best_agree = rf.best_agree,
            .indep_agree = indep_f,
            .ms = rf.ms,
        };
        @memcpy(row2.witness[0..wlabel_f.len], wlabel_f);
        addRow(sr, row2);
    }
}

// =============================================================================
// Phase 3 (after phase-2 threads have joined): vacuity check -- distinct-count
// through the SAME certify() machinery, 16 certifier-seed replicates. Runs the
// job list on 2 worker threads (the phase-2 threads are done, so the process
// never exceeds 2 concurrent compute threads).
// =============================================================================

const KILL_SEEDS = [_]u64{
    0x1000, 0x2000, 0x3000, 0x4000, 0x5000, 0x6000, 0x7000, 0x8000,
    0x9000, 0xA000, 0xB000, 0xC000, 0xD000, 0xE000, 0xF000, 0x11000,
};

const KillJob = struct {
    lib: []const alien.Program,
    check: []const u8,
    seed: u64,
    depth: usize,
    cap_ns: u64,
    result: CertResult = .{},
};

fn killWorker(jobs: []KillJob, start: usize, stride: usize) void {
    const dc = coevo.distinctCountProg();
    var i = start;
    while (i < jobs.len) : (i += stride) {
        jobs[i].result = certify(&dc, jobs[i].lib, jobs[i].depth, jobs[i].seed, jobs[i].cap_ns);
    }
}

fn killTestPhase(al: std.mem.Allocator, out: anytype, results: []SeedResult, rows: *std.ArrayList(AtomRow)) !void {
    try out.writeAll("\n=== VACUITY CHECK: distinct-count (true outsider) through reducibleLib-attack machinery ===\n");
    const base = forge.baseAtoms();
    std.debug.assert(KILL_SEEDS.len == 16);

    // Job list: all 16 replicates against the cheap base-5 library at depth 8
    // (matches INDEX.md's "non-vacuous at depth 8" framing), plus the first 6
    // replicates against BOTH reproduced final 15-atom libraries at depth 6
    // (cost-bounded trim, documented).
    var jobs = std.ArrayList(KillJob).init(al);
    defer jobs.deinit();
    for (KILL_SEEDS) |ks| {
        try jobs.append(.{ .lib = base.slice(), .check = "base5", .seed = ks, .depth = 8, .cap_ns = CAP_NS_KILL_BASE });
    }
    for (results) |*sr| {
        for (KILL_SEEDS[0..6]) |ks| {
            try jobs.append(.{
                .lib = sr.final_atoms.slice(),
                .check = if (sr.seed == SEEDS[0]) "finalA70F" else "final5EED2",
                .seed = ks,
                .depth = 6,
                .cap_ns = CAP_NS_KILL_FINAL,
            });
        }
    }

    const t0 = try std.Thread.spawn(.{}, killWorker, .{ jobs.items, 0, 2 });
    const t1 = try std.Thread.spawn(.{}, killWorker, .{ jobs.items, 1, 2 });
    t0.join();
    t1.join();

    // Summaries per check-group, rows in deterministic job order.
    var n_pass_base: usize = 0;
    var worst_base: f64 = 0;
    var min_depth_base: usize = 99;
    for (jobs.items) |j| {
        try rows.append(.{
            .kind = "killtest",
            .seed = j.seed,
            .label = mkLabel(0),
            .label_len = 0,
            .round = 0,
            .lib_size = j.lib.len,
            .check = j.check,
            .depth_requested = j.depth,
            .depth_reached = j.result.depth_reached,
            .outcome = outcomeStr(j.result.outcome),
            .witness = undefined,
            .witness_len = 0,
            .best_agree = j.result.best_agree,
            .indep_agree = -1,
            .ms = j.result.ms,
        });
        if (std.mem.eql(u8, j.check, "base5")) {
            if (j.result.outcome != .reducible) n_pass_base += 1;
            if (j.result.best_agree > worst_base) worst_base = j.result.best_agree;
            if (j.result.depth_reached < min_depth_base) min_depth_base = j.result.depth_reached;
        }
    }
    try out.print("  base-5 library, depth 8, 16 seed replicates: {d}/16 correctly IRREDUCIBLE, min completed depth {d}, closest approach {d:.4}\n", .{ n_pass_base, min_depth_base, worst_base });

    for (results) |sr| {
        const tag = if (sr.seed == SEEDS[0]) "finalA70F" else "final5EED2";
        var n_pass: usize = 0;
        var tried: usize = 0;
        var worst: f64 = 0;
        var min_depth: usize = 99;
        for (jobs.items) |j| {
            if (!std.mem.eql(u8, j.check, tag)) continue;
            tried += 1;
            if (j.result.outcome != .reducible) n_pass += 1;
            if (j.result.best_agree > worst) worst = j.result.best_agree;
            if (j.result.depth_reached < min_depth) min_depth = j.result.depth_reached;
        }
        try out.print("  final library (seed 0x{X}, {d} atoms), depth 6 requested, {d} seed replicates: {d}/{d} correctly IRREDUCIBLE, min completed depth {d}, closest approach {d:.4}\n", .{ sr.seed, sr.final_atoms.len, tried, n_pass, tried, min_depth, worst });
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const al = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(al);
    defer std.process.argsFree(al, args);
    const csv_path = if (args.len > 1) args[1] else "../results/claimc_attack_2026_07_10.csv";

    try out.writeAll("=== CLAIM-C DEPTH-PUSH ATTACK (I53-style red-team on wcore's irreducibility certifier) ===\n");
    try out.print("production certifier depth = {d}; pushing to library-size-adaptive depths beyond it\n", .{PROD_DEPTH});

    var result_a: SeedResult = .{ .seed = SEEDS[0] };
    var result_b: SeedResult = .{ .seed = SEEDS[1] };

    var overall_timer = try std.time.Timer.start();

    const th_a = try std.Thread.spawn(.{}, runSeedAttack, .{ SEEDS[0], &result_a });
    const th_b = try std.Thread.spawn(.{}, runSeedAttack, .{ SEEDS[1], &result_b });
    th_a.join();
    th_b.join();

    try out.writeAll(result_a.log.items);
    try out.writeAll(result_b.log.items);
    result_a.log.deinit();
    result_b.log.deinit();

    try out.print("\n[phase 1+2 elapsed: {d} ms]\n", .{overall_timer.read() / std.time.ns_per_ms});

    var results = [_]SeedResult{ result_a, result_b };

    // ---- write CSV incrementally: atom rows FIRST (so a wall-clock kill during
    // the vacuity phase can never destroy the phase-1/2 data), kill rows appended.
    const csv = try std.fs.cwd().createFile(csv_path, .{});
    defer csv.close();
    const cw = csv.writer();
    try cw.writeAll("kind,seed,label,round,lib_size,check,depth_requested,depth_reached,outcome,witness,best_agreement,indep_agreement,ms\n");
    for (results) |sr| {
        for (sr.rows[0..sr.n_rows]) |row| {
            try cw.print("{s},0x{X},{s},{d},{d},{s},{d},{d},{s},\"{s}\",{d:.6},{d:.6},{d}\n", .{
                row.kind,
                row.seed,
                std.mem.sliceTo(&row.label, 0),
                row.round,
                row.lib_size,
                row.check,
                row.depth_requested,
                row.depth_reached,
                row.outcome,
                row.witness[0..row.witness_len],
                row.best_agree,
                row.indep_agree, // -1 => n/a (no flip); else independent 4096-symbol re-verification
                row.ms,
            });
        }
    }
    try csv.sync();
    try out.print("[atom rows written to {s}]\n", .{csv_path});

    var kill_rows = std.ArrayList(AtomRow).init(al);
    defer kill_rows.deinit();
    try killTestPhase(al, out, results[0..], &kill_rows);

    try out.print("\n[total elapsed: {d} ms]\n", .{overall_timer.read() / std.time.ns_per_ms});

    for (kill_rows.items) |row| {
        try cw.print("{s},0x{X},dc,{d},{d},{s},{d},{d},{s},,{d:.6},-1,{d}\n", .{
            row.kind, row.seed, row.round, row.lib_size, row.check, row.depth_requested, row.depth_reached, row.outcome, row.best_agree, row.ms,
        });
    }

    try out.print("\nCSV written: {s}\n", .{csv_path});
    try out.print("instrument self-check (certify() depth-3 vs production forge.reducibleLib depth-3): seed 0x{X} {s}, seed 0x{X} {s}\n", .{
        result_a.seed, if (result_a.self_check_pass) "PASS" else "FAIL",
        result_b.seed, if (result_b.self_check_pass) "PASS" else "FAIL",
    });
}
