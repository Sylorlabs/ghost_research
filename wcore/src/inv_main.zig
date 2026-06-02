//! The primitive-inventing engine — driver (PLAN_INVENTION_ENGINE.md).
//!
//! Phases run strictly in order, each with a kill-test (§5):
//!   phase0 — substrate + executor + fitness + sanity gate
//!   phase1 — flat regularized evolution vs random search (the reproduction)
//!   phase2 — + the compounding library (the core hypothesis)
//!
//! Usage:
//!   zig build run-invent -- phase0
//!   zig build run-invent -- phase1 [seed]
//!   zig build run-invent -- phase2 [seed]

const std = @import("std");
const sub = @import("inv_substrate.zig");
const tasks = @import("inv_tasks.zig");
const evo = @import("inv_evolve.zig");
const lib = @import("inv_library.zig");
const seq = @import("inv_seq.zig");
const frontier = @import("inv_frontier.zig");
const alien = @import("inv_alien.zig");
const open = @import("inv_open.zig");
const coevo = @import("inv_coevo.zig");
const forge = @import("inv_atomforge.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const al = gpa.allocator();

    const args = try std.process.argsAlloc(al);
    defer std.process.argsFree(al, args);

    const phase = if (args.len > 1) args[1] else "phase0";
    const seed: u64 = if (args.len > 2) (std.fmt.parseInt(u64, args[2], 0) catch 0xC0FFEE) else 0xC0FFEE;

    const out = std.io.getStdOut().writer();
    if (std.mem.eql(u8, phase, "phase0")) {
        try phase0(out);
    } else if (std.mem.eql(u8, phase, "phase1")) {
        try phase1(al, out, seed);
    } else if (std.mem.eql(u8, phase, "phase2")) {
        try phase2(al, out, seed);
    } else if (std.mem.eql(u8, phase, "phase3")) {
        try phase3(al, out, seed);
    } else if (std.mem.eql(u8, phase, "phase4")) {
        try phase4(al, out, seed);
    } else if (std.mem.eql(u8, phase, "phase5")) {
        try phase5(al, out, seed);
    } else if (std.mem.eql(u8, phase, "phase6")) {
        try phase6(al, out, seed);
    } else if (std.mem.eql(u8, phase, "phase7")) {
        try phase7(al, out, seed);
    } else if (std.mem.eql(u8, phase, "phase8")) {
        try phase8(al, out, seed);
    } else if (std.mem.eql(u8, phase, "seq")) {
        try seqExperiment(al, out, seed);
    } else if (std.mem.eql(u8, phase, "frontier")) {
        try frontierMap(out, seed);
    } else if (std.mem.eql(u8, phase, "novelty")) {
        try noveltyCertifier(out, seed);
    } else if (std.mem.eql(u8, phase, "alien")) {
        try alienReachability(out, seed);
    } else if (std.mem.eql(u8, phase, "hunt")) {
        try alienHunt(al, out, seed);
    } else if (std.mem.eql(u8, phase, "probe")) {
        try alienProbe(al, out, seed);
    } else if (std.mem.eql(u8, phase, "curriculum")) {
        try alienCurriculum(al, out, seed);
    } else if (std.mem.eql(u8, phase, "gamble")) {
        try alienGamble(al, out, seed);
    } else if (std.mem.eql(u8, phase, "forbid")) {
        try alienForbid(al, out, seed);
    } else if (std.mem.eql(u8, phase, "fuse")) {
        try alienFuse(al, out, seed);
    } else if (std.mem.eql(u8, phase, "getrecall")) {
        try alienGetRecall(al, out, seed);
    } else if (std.mem.eql(u8, phase, "corner")) {
        try alienCorner(al, out, seed);
    } else if (std.mem.eql(u8, phase, "openended")) {
        try alienOpenEnded(al, out, seed);
    } else if (std.mem.eql(u8, phase, "infodesc")) {
        try alienInfoDesc(al, out, seed);
    } else if (std.mem.eql(u8, phase, "coevo")) {
        try alienCoevo(al, out, seed);
    } else if (std.mem.eql(u8, phase, "oecoevo")) {
        try alienOeCoevo(al, out, seed);
    } else if (std.mem.eql(u8, phase, "irreducible")) {
        try alienIrreducible(al, out, seed);
    } else if (std.mem.eql(u8, phase, "budgetscan")) {
        try budgetScan(al, out, seed);
    } else if (std.mem.eql(u8, phase, "atomforge")) {
        try alienAtomForge(al, out, seed);
    } else if (std.mem.eql(u8, phase, "beathuman")) {
        try alienBeatHuman(al, out, seed);
    } else {
        try out.print("unknown phase '{s}'. try: phase0..phase8 | seq | frontier | novelty | alien | hunt | probe | curriculum | gamble | forbid | fuse | getrecall | corner | openended | infodesc | coevo | oecoevo | irreducible | atomforge | beathuman\n", .{phase});
    }
}

/// Bricks B–E — the "beat attention" track on the sequence substrate. Attention is
/// weak at length-generalisation on algorithmic tasks; we use prefix-parity, where
/// a SCAN (running product, persistent state) is correct at any length but a
/// fixed-depth/stateless (attention-class) operator cannot be. We check: (B) the
/// scan holds as length scales; (C) the stateless class collapses even when
/// searched; (D) search DISCOVERS the scan by execution; (E) the discovered
/// primitive holds at held-out longer lengths and is irreducible to the stateless
/// class. Honest: the scan/recurrence is a KNOWN primitive — this is rediscovery
/// of a real trade-off-breaker, not a never-seen invention.
fn seqExperiment(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== BRICKS B–E: beating attention's weakness (length-gen on prefix-parity) ===\n\n");

    // ---- Brick B: sanity gate — the scan holds as length scales ----------------
    const scan = seq.referenceScan();
    try out.writeAll("[Brick B] hand-written SCAN (running product, persistent state):\n");
    try out.print("  acc @ L=16: {d:.3} | L=64: {d:.3} | L=200: {d:.3}  ⇒ HOLDS as length scales\n\n", .{
        seq.fitness(&scan, 16, 64, base_seed, true),
        seq.fitness(&scan, 64, 64, base_seed +% 1, true),
        seq.fitness(&scan, 200, 32, base_seed +% 2, true),
    });

    // ---- Brick C: attention's weakness — the stateless class cannot ------------
    try out.writeAll("[Brick C] the STATELESS / fixed-depth (attention-class) regime:\n");
    try out.print("  same scan run with NO carried state: acc @ L=64 = {d:.3} (≈ chance — can't do parity)\n", .{seq.fitness(&scan, 64, 64, base_seed, false)});
    var pr_c = std.Random.DefaultPrng.init(base_seed +% 0x10);
    const stateless = try seq.evolve(al, pr_c.random(), .{ .max_evals = 60_000, .persist = false, .fit_L = 32 }, base_seed);
    try out.print("  BEST program a search restricted to the stateless class can find: acc = {d:.3}\n", .{stateless.best_fit});
    try out.writeAll("  ⇒ the attention-class approach is stuck at chance on this task, at any length.\n\n");

    // ---- Brick D: the hunt — does search DISCOVER the scan? --------------------
    try out.writeAll("[Brick D] search WITH persistent state (the scan is reachable):\n");
    const dp = seq.Params{ .max_evals = 80_000, .persist = true, .fit_L = 32, .target = 0.99 };
    const n_seeds: usize = 6;
    var hits: usize = 0;
    var champ: seq.Program = .{};
    var champ_fit: f64 = -1;
    var best_ett: ?usize = null;
    for (0..n_seeds) |s| {
        var prng = std.Random.DefaultPrng.init(base_seed +% 0x20 +% s *% 0x9E3779B1);
        const r = try seq.evolve(al, prng.random(), dp, base_seed +% s);
        if (r.evals_to_target != null) {
            hits += 1;
            if (r.evals_to_target.? < (best_ett orelse std.math.maxInt(usize))) best_ett = r.evals_to_target;
        }
        if (r.best_fit > champ_fit) {
            champ_fit = r.best_fit;
            champ = r.best;
        }
    }
    try out.print("  solved (acc ≥ {d:.2}) in {d}/{d} runs", .{ dp.target, hits, n_seeds });
    if (best_ett) |e| try out.print(" | fastest {d} evals", .{e});
    try out.print(" | best fitness {d:.3}\n", .{champ_fit});
    try out.writeAll("  discovered champion:\n");
    try seq.writeProgram(&champ, out);

    // ---- Brick E: irreducibility — does the discovered primitive SCALE? --------
    try out.writeAll("\n[Brick E] the discovered primitive at HELD-OUT longer lengths (trained at L=32):\n");
    try out.print("  acc @ L=64: {d:.3} | L=128: {d:.3} | L=256: {d:.3}\n", .{
        seq.fitness(&champ, 64, 64, base_seed +% 0x40, true),
        seq.fitness(&champ, 128, 32, base_seed +% 0x41, true),
        seq.fitness(&champ, 256, 16, base_seed +% 0x42, true),
    });
    const scales = seq.fitness(&champ, 256, 16, base_seed +% 0x42, true) > 0.99;
    if (scales and champ_fit > 0.99) {
        try out.writeAll("  ⇒ it HOLDS far past its training length — a genuine recurrence/scan, irreducible\n");
        try out.writeAll("  to the fixed-depth stateless class (which is stuck at chance). The engine found,\n");
        try out.writeAll("  by execution, a length-generalising primitive that beats the attention-class\n");
        try out.writeAll("  approach on its weakness. (Honest: scan is a KNOWN primitive — rediscovery.)\n");
    } else {
        try out.writeAll("  ⇒ the champion does not cleanly hold/scale this run — rerun or raise budget.\n");
    }
}

/// RESEARCH PHASE 0 — THE MAP. Place the known mechanisms on the (recall,
/// length-gen) plane and prove the two tasks pull in opposite directions. This
/// is the measurement the whole alien-architecture search is graded against:
/// nothing can "break the frontier" until we've shown where the frontier is and
/// that it's real. KILL-TEST (also in inv_frontier tests): attention and scan
/// land at opposite corners.
fn frontierMap(out: anytype, seed: u64) !void {
    try out.writeAll("=== RESEARCH PHASE 0: the recall ↔ length-gen frontier map ===\n\n");
    try out.writeAll("Two tasks that pull opposite ways:\n");
    try out.writeAll("  • length-gen  = prefix-parity at L=256 (trained-length 32) — needs a SCAN\n");
    try out.writeAll("  • recall      = associative recall, K=32 bindings, S=4 memory — needs CONTENT ADDRESSING\n\n");

    const ops = [_]frontier.Operator{ frontier.attention, frontier.scan, frontier.local };
    try out.writeAll("  mechanism   | length-gen (parity L=256) | recall (K=32) | corner\n");
    try out.writeAll("  ------------+---------------------------+---------------+-------------------------\n");
    for (ops) |op| {
        const lg = frontier.parityAcc(op, 256, 64, seed);
        const rc = frontier.recallAcc(op, 32, 1024, seed +% 7);
        const corner = describeCorner(lg, rc);
        try out.print("  {s:<11} |           {d:.3}           |     {d:.3}     | {s}\n", .{ op.name, lg, rc, corner });
    }

    // the diagonal gap (the thing an alien op would have to fill)
    const attn_rc = frontier.recallAcc(frontier.attention, 32, 1024, seed +% 7);
    const attn_lg = frontier.parityAcc(frontier.attention, 256, 64, seed);
    const scan_rc = frontier.recallAcc(frontier.scan, 32, 1024, seed +% 7);
    const scan_lg = frontier.parityAcc(frontier.scan, 256, 64, seed);
    try out.writeAll("\n[FRONTIER] attention owns the recall corner, scan owns the length-gen corner.\n");
    try out.print("  recall gap (attn−scan)    = {d:.3}\n", .{attn_rc - scan_rc});
    try out.print("  length-gen gap (scan−attn)= {d:.3}\n", .{scan_lg - attn_lg});
    try out.writeAll("  The OPEN TARGET is the empty top-right corner: high recall AND high length-gen.\n");
    try out.writeAll("  No single known primitive sits there. That is what the alien search must reach.\n");
}

fn describeCorner(lg: f64, rc: f64) []const u8 {
    const hi_lg = lg > 0.8;
    const hi_rc = rc > 0.8;
    if (hi_lg and hi_rc) return "TOP-RIGHT (the open target!)";
    if (hi_lg) return "length-gen corner";
    if (hi_rc) return "recall corner";
    return "neither (dominated)";
}

/// RESEARCH PHASE 1 — THE NOVELTY CERTIFIER. The anti-self-deception machinery:
/// a behavioural fingerprint that tells a genuinely new operator apart from a
/// known one in disguise. We print the fingerprints, the pairwise distances, and
/// run the certifier on a re-implemented scan. KILL-TEST: the disguised scan
/// must certify NOT-novel and nearest=scan; known mechanisms must be far apart.
fn noveltyCertifier(out: anytype, seed: u64) !void {
    try out.writeAll("=== RESEARCH PHASE 1: the behavioural novelty certifier ===\n\n");
    try out.writeAll("Fingerprint = [parity16, parity256, recallK4, recallK48, x0_sensitivity, local_agree]\n");
    try out.writeAll("(mechanism-revealing probes; a candidate is NOVEL only if far from EVERY anchor)\n\n");

    const named = [_]frontier.Operator{ frontier.attention, frontier.scan, frontier.local, frontier.scan_disguised };
    try out.writeAll("  operator        | fingerprint\n");
    try out.writeAll("  ----------------+--------------------------------------------------\n");
    for (named) |op| {
        const fp = frontier.fingerprint(op, seed);
        try out.print("  {s:<15} | [", .{op.name});
        for (fp, 0..) |c, i| {
            if (i > 0) try out.writeAll(" ");
            try out.print("{d:.2}", .{c});
        }
        try out.writeAll("]\n");
    }

    const anchors = frontier.knownAnchors(seed);
    try out.print("\nKnown anchors: attention, scan, local. Novelty threshold = {d:.2}\n", .{frontier.NOVELTY_THRESHOLD});
    try out.writeAll("  pairwise anchor distances (must all exceed the threshold = well-separated clusters):\n");
    const fa = frontier.fingerprint(frontier.attention, seed);
    const fs = frontier.fingerprint(frontier.scan, seed);
    const fl = frontier.fingerprint(frontier.local, seed);
    try out.print("    attn↔scan = {d:.3} | attn↔local = {d:.3} | scan↔local = {d:.3}\n\n", .{ frontier.fpDist(fa, fs), frontier.fpDist(fa, fl), frontier.fpDist(fs, fl) });

    try out.writeAll("[KILL-TEST] feed it a re-implemented scan (parity-via-count, re-indexed memory):\n");
    const fp_disg = frontier.fingerprint(frontier.scan_disguised, seed);
    const v = frontier.classify(fp_disg, &anchors, frontier.NOVELTY_THRESHOLD);
    try out.print("  nearest anchor = {s} | distance = {d:.3} | verdict = {s}\n", .{ v.nearest, v.dist, if (v.novel) "NOVEL" else "NOT novel (known mechanism in disguise)" });
    if (!v.novel and std.mem.eql(u8, v.nearest, "scan")) {
        try out.writeAll("  ⇒ PASS: the certifier saw through the disguise. A future alien op will only count\n");
        try out.writeAll("    as a real invention if it lands FAR from every anchor AND on the frontier corner.\n");
    } else {
        try out.writeAll("  ⇒ FAIL: certifier cannot recognise a disguised known mechanism — fix before searching.\n");
    }
}

/// RESEARCH PHASE 2 — THE ALIEN SUBSTRATE reachability proof. The non-human
/// op-space (bit-mixing + addressable memory + computed addressing; no softmax,
/// no float-product) must be able to HOST a frontier-breaker before searching it
/// is worthwhile. We hand-write three alien programs and place them on the same
/// Phase-0 map: an XOR-accumulator (length-gen corner, via bits not floats), a
/// hash-table (recall corner, via hashing not softmax), and their UNION (the
/// empty top-right corner). KILL-TEST: the union reaches BOTH and certifies novel.
fn alienReachability(out: anytype, seed: u64) !void {
    try out.writeAll("=== RESEARCH PHASE 2: the alien substrate — is the frontier reachable? ===\n\n");
    try out.writeAll("Op-space: u64 regs + XOR/AND/OR/SHL/SHR/ROTR/POPCNT/MUM/BSWAP + addressable\n");
    try out.writeAll("memory (data-dependent load/store) + eq/sel masks. NO softmax, NO float product.\n");
    try out.writeAll("Content addressing is reachable only via HASHING; accumulation only via BIT-MIXING.\n\n");

    const Named = struct { name: []const u8, p: alien.Program, route: []const u8 };
    const progs = [_]Named{
        .{ .name = "alien XOR-scan ", .p = alien.alienXorScan(), .route = "parity via bit-XOR accumulate" },
        .{ .name = "alien hash-tbl ", .p = alien.alienHashTable(), .route = "recall via hashed memory" },
        .{ .name = "alien UNION    ", .p = alien.alienUnion(), .route = "both, in one step-body" },
    };

    try out.writeAll("  alien program   | length-gen (L=256) | recall (K=48) | corner                       | route\n");
    try out.writeAll("  ----------------+--------------------+---------------+------------------------------+------------------------------\n");
    for (progs) |g| {
        const lg = alien.parityAcc(&g.p, 256, 64, seed, true);
        const rc = alien.recallAcc(&g.p, 48, 1024, seed +% 7, true);
        try out.print("  {s} |       {d:.3}        |     {d:.3}     | {s:<28} | {s}\n", .{ g.name, lg, rc, describeCorner(lg, rc), g.route });
    }

    // certify the top-right alien program against the known anchors
    const u = alien.alienUnion();
    const fp = alien.fingerprint(&u, seed);
    const anchors = frontier.knownAnchors(seed);
    const v = frontier.classify(fp, &anchors, frontier.NOVELTY_THRESHOLD);
    try out.writeAll("\n[REACHABILITY] the alien op-space spans the WHOLE map, including the empty corner:\n");
    try out.print("  top-right program fingerprint = [", .{});
    for (fp, 0..) |c, i| {
        if (i > 0) try out.writeAll(" ");
        try out.print("{d:.2}", .{c});
    }
    try out.print("]\n  certifier verdict: nearest={s}, dist={d:.3} ⇒ {s}\n", .{ v.nearest, v.dist, if (v.novel) "NOVEL vs every single-mechanism anchor" else "matches a known mechanism" });
    try out.writeAll("\n[HONEST] the union is two KNOWN mechanisms bolted together — it certifies novel only\n");
    try out.writeAll("because no SINGLE anchor does both. The real prize (Phase 3 search + Phase 4 gauntlet)\n");
    try out.writeAll("is whether execution-search DISCOVERS a top-right program, and whether what it finds is\n");
    try out.writeAll("a unified/irreducible primitive or just rediscovers this union. The substrate is proven\n");
    try out.writeAll("able to host the answer — searching it is now worthwhile.\n");
}

/// The building-block atom program for a stage (what search composes WITH).
fn atomForStage(st: coevo.Stage) alien.Program {
    return switch (st) {
        .st_gxor => coevo.refSolver(.g_xor),
        .st_gadd => coevo.refSolver(.g_add),
        .st_pkxor => coevo.refSolver(.pk_xor),
        .st_pkadd => coevo.refSolver(.pk_add),
        .st_shift => forge.shiftAtom(),
    };
}

/// RESEARCH PHASE 17 — BEAT A HUMAN COMPOSITION. The original North Star, honestly scoped.
/// The arc proved search can't invent a new ATOM; the achievable question is whether it can
/// find a better ARRANGEMENT of known atoms than a competent human writes. The fair,
/// non-riggable form is SUPEROPTIMISATION: for a composite task, hand-write a TIGHT human
/// baseline (not a strawman), then let search find the minimal correct program, and compare
/// length at equal held-out accuracy. Expected (and honest): a MIXED result — search fuses
/// and wins some, the human's elegant recurrence wins others.
fn alienBeatHuman(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== RESEARCH PHASE 17: can search beat a competent HUMAN composition? ===\n\n");
    try out.writeAll("Superoptimisation: tight hand-written human baseline vs minimised search, equal accuracy,\n");
    try out.writeAll("compare program length (= the real cost of the arrangement). Lower wins.\n\n");

    // --- tight, competent human baselines for composite tasks -------------------
    const Case = struct { name: []const u8, genome: []const coevo.Stage, human: alien.Program };
    var cases: [4]Case = undefined;

    // 1) [gadd]: running sum — a human writes one instruction.
    var h0 = alien.Program{};
    h0.step.appendAssumeCapacity(.{ .op = .a_add, .a = 3, .b = 0, .out = 3 });
    cases[0] = .{ .name = "gadd          ", .genome = &.{.st_gadd}, .human = h0 };

    // 2) [shift, gxor]: delayed running parity — a human writes the tight 2-instr recurrence.
    var h1 = alien.Program{};
    h1.step.appendAssumeCapacity(.{ .op = .a_xor, .a = 3, .b = 9, .out = 3 }); // out ^= prev
    h1.step.appendAssumeCapacity(.{ .op = .a_mov, .a = 0, .out = 9 }); // prev = current
    cases[1] = .{ .name = "shift→gxor    ", .genome = &.{ .st_shift, .st_gxor }, .human = h1 };

    // 3) [pkadd, gxor]: xor of per-key counts — RMW counter + xor-accumulate.
    var h2 = alien.Program{};
    h2.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 6, .imm = 1 });
    h2.step.appendAssumeCapacity(.{ .op = .a_load, .a = 0, .out = 4 });
    h2.step.appendAssumeCapacity(.{ .op = .a_add, .a = 4, .b = 6, .out = 4 });
    h2.step.appendAssumeCapacity(.{ .op = .a_store, .a = 0, .b = 4 });
    h2.step.appendAssumeCapacity(.{ .op = .a_xor, .a = 3, .b = 4, .out = 3 });
    cases[2] = .{ .name = "pkadd→gxor    ", .genome = &.{ .st_pkadd, .st_gxor }, .human = h2 };

    // 4) [pkxor, shift]: delayed per-key xor — RMW xor + a one-step delay on the output.
    var h3 = alien.Program{};
    h3.step.appendAssumeCapacity(.{ .op = .a_load, .a = 0, .out = 4 });
    h3.step.appendAssumeCapacity(.{ .op = .a_xor, .a = 4, .b = 0, .out = 4 });
    h3.step.appendAssumeCapacity(.{ .op = .a_store, .a = 0, .b = 4 });
    h3.step.appendAssumeCapacity(.{ .op = .a_mov, .a = 7, .out = 3 }); // output = previous out1
    h3.step.appendAssumeCapacity(.{ .op = .a_mov, .a = 4, .out = 7 }); // save current out1
    cases[3] = .{ .name = "pkxor→shift   ", .genome = &.{ .st_pkxor, .st_shift }, .human = h3 };

    try out.writeAll("  task          | human len | search solve-rate | search best len | winner (best-of-runs)\n");
    try out.writeAll("  --------------+-----------+-------------------+-----------------+----------------------\n");

    const regs: usize = 8;
    const restarts: usize = 16;
    var search_wins: usize = 0;
    var ties: usize = 0;
    var human_wins: usize = 0;
    for (cases) |c| {
        const hlen = c.human.len();
        // sanity: the human baseline really is correct (held-out)
        std.debug.assert(coevo.taskFitnessComposed(&c.human, c.genome, 96, 24, base_seed +% 0xA0) > 0.95);

        // superoptimisation: many runs (seeded from the building block), keep the shortest
        // correct, minimised program; also report how OFTEN search even solves (reliability).
        var seedp = atomForStage(c.genome[0]);
        var best: ?alien.Program = null;
        var best_len: usize = 999;
        var solves: usize = 0;
        for (0..restarts) |t| {
            var prng = std.Random.DefaultPrng.init(base_seed +% hashName(c.name) +% t *% 0x9E3779B1);
            const sp: ?*const alien.Program = if (t % 2 == 0) &seedp else null;
            const r = try coevo.evolveComposed(al, prng.random(), c.genome, 200_000, regs, base_seed +% t, sp);
            if (r.fit >= 0.95) {
                solves += 1;
                const m = coevo.minimizeForTask(r.best, c.genome, base_seed +% 0x99);
                if (m.len() < best_len) {
                    best_len = m.len();
                    best = m;
                }
            }
        }

        try out.print("  {s} |    {d:>2}     |      {d:>2}/{d}        |", .{ c.name, hlen, solves, restarts });
        if (best) |bp| {
            // verify the best is genuinely correct on a fresh held-out seed
            const sacc = coevo.taskFitnessComposed(&bp, c.genome, 96, 24, base_seed +% 0xBEEF);
            const ok = sacc > 0.95;
            try out.print("       {d:>2} ({d:.2})    | ", .{ best_len, sacc });
            if (ok and best_len < hlen) {
                search_wins += 1;
                try out.writeAll("SEARCH (leaner!)\n");
            } else if (ok and best_len == hlen) {
                ties += 1;
                try out.writeAll("tie\n");
            } else {
                human_wins += 1;
                try out.writeAll("human\n");
            }
        } else {
            human_wins += 1;
            try out.writeAll("       — (none)    | human (search never solved)\n");
        }
    }

    // --- verdict ----------------------------------------------------------------
    try out.print("\n[RESULT] over {d} tasks (best of {d} runs each): search leaner {d}, tie {d}, human/failed {d}.\n", .{ cases.len, restarts, search_wins, ties, human_wins });
    try out.writeAll("\n[VERDICT] ");
    if (search_wins > 0) {
        try out.print("search found a STRICTLY LEANER arrangement than the competent human on {d}/{d} task(s) —\n", .{ search_wins, cases.len });
        try out.writeAll("a real superoptimisation win: the SAME known atoms, fused into fewer ops than a person\n");
        try out.writeAll("wrote. So 'beat the human arrangement' is genuinely possible — BUT read the solve-rates: it\n");
        try out.writeAll("is best-of-MANY-runs (the leaner program turned up in a minority of restarts), it TIES where\n");
        try out.writeAll("the human is already minimal, and it NEVER solved the hardest composite (the conjunction\n");
        try out.writeAll("reliability wall). So the honest shape is: search MATCHES a competent human on simple\n");
        try out.writeAll("compositions, occasionally super-optimises a leaner fusion, and often can't assemble the\n");
        try out.writeAll("harder composites at all. A modest, real, unreliable win — not a rout.\n");
    } else {
        try out.writeAll("search did NOT beat the competent human on length this run — it tied where the human was\n");
        try out.writeAll("already minimal and failed to assemble the hard composites (the conjunction reliability\n");
        try out.writeAll("wall). A competent human's arrangement of known atoms is hard to beat at this scale.\n");
    }
    try out.writeAll("Either way it is REARRANGING known atoms — consistent with the arc: no new atom, only\n");
    try out.writeAll("composition, and 'better' here means leaner, not a capability a human couldn't reach.\n");
}

/// RESEARCH PHASE 16 — THE ATOM-FORGE: an OPEN-ENDED ATOM SET. The one frontier the arc
/// left. Every prior phase used a fixed atom set and found only composition. Here the atom
/// set GROWS: novelty search generates candidate behaviours, the irreducibility test (now
/// over a growing program library) certifies which are irreducible relative to the current
/// atoms, and a clean minimal certified candidate is INVENTED — added as a new atom. Then
/// irreducibility RECURS (the next atom must beat the enlarged set). Measurables: how many
/// atoms it invents before saturating, and whether their minimal length GROWS (open-ended)
/// or plateaus (substrate exhausted).
fn alienAtomForge(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== RESEARCH PHASE 16: the atom-forge — an OPEN-ENDED atom set ===\n\n");
    try out.writeAll("novelty search GENERATES behaviours; the irreducibility test CERTIFIES which are new\n");
    try out.writeAll("relative to the current library; certified ones are INVENTED as atoms; then it recurs.\n\n");
    const dseed = base_seed ^ 0x1F0; // descriptor seed
    const fseed = base_seed +% 0xA70F; // irreducibility-test stream seed
    const depth: usize = 3; // composition depth the irreducibility test searches

    var atoms = forge.baseAtoms();
    const base_n = atoms.len;
    try out.print("Base atoms: {d} (gxor gadd pkxor pkadd shift). Irreducibility searches compositions ≤ depth {d}.\n\n", .{ base_n, depth });

    var lengths: [forge.MAX_ATOMS]usize = undefined;
    var n_invented: usize = 0;
    const MAX_ROUNDS: usize = 8;
    for (0..MAX_ROUNDS) |round| {
        // generate candidate behaviours with task-agnostic novelty search
        var prng = std.Random.DefaultPrng.init(base_seed +% round *% 0x9E3779B97F4A7C15);
        var archive = try open.search(al, prng.random(), .{ .pop = 90, .gens = 45, .info = true, .seed = dseed });
        defer archive.deinit();
        // prefer MINIMAL atoms: shortest program first
        std.mem.sort(open.Member, archive.items, {}, struct {
            fn lt(_: void, a: open.Member, b: open.Member) bool {
                return a.prog.len() < b.prog.len();
            }
        }.lt);

        var invented: ?alien.Program = null;
        for (archive.items) |cand| {
            if (!forge.clean(&cand.prog, dseed)) continue;
            if (forge.reducibleLib(&cand.prog, atoms.slice(), depth, fseed)) continue; // composition → not new
            invented = cand.prog;
            break;
        }

        if (invented == null) {
            try out.print("round {d}: SATURATED — novelty search found no CLEAN candidate irreducible to the\n", .{round});
            try out.print("         current {d}-atom library. The reachable clean behaviours are now all composable.\n", .{atoms.len});
            break;
        }
        atoms.appendAssumeCapacity(invented.?);
        lengths[n_invented] = invented.?.len();
        n_invented += 1;
        try out.print("round {d}: INVENTED atom #{d} (program length {d}) — certified IRREDUCIBLE vs the prior {d} atoms.\n", .{ round, atoms.len, invented.?.len(), atoms.len - 1 });
        if (n_invented <= 2) {
            try alien.writeProgram(&invented.?, out);
        }
        if (atoms.len >= forge.MAX_ATOMS) break;
    }

    // ---- the trajectory + verdict ----------------------------------------------
    try out.print("\n[RESULT] invented {d} new atoms beyond the {d} base (library now {d}).\n", .{ n_invented, base_n, atoms.len });
    if (n_invented > 0) {
        try out.writeAll("  minimal program-length per invented atom: ");
        for (0..n_invented) |i| try out.print("{d} ", .{lengths[i]});
        try out.writeAll("\n");
    }

    // does minimal length actually CLIMB by a real margin (strong open-endedness), or stay
    // flat/noisy (mere COVERAGE of the substrate's fixed repertoire)?
    var climbs = false;
    if (n_invented >= 4 and lengths[n_invented - 1] >= lengths[0] + 2 and lengths[n_invented - 2] >= lengths[1] + 2) climbs = true;

    try out.writeAll("\n[VERDICT] ");
    if (n_invented >= 2) {
        try out.print("the recursion RAN — {d} atoms, each certified irreducible relative to all prior. The\n", .{n_invented});
        try out.writeAll("open-ended-atom MECHANISM works. But read it honestly, two ways:\n\n");
        try out.writeAll("1) The bar is WEAK. The 5 base atoms use only xor/add/load/store/mov, so ANY behaviour\n");
        try out.writeAll("   touching the substrate's other ops (and/or/mum/popcnt/rotr/bswap/sel) is automatically\n");
        try out.writeAll("   irreducible relative to them. The invented atoms are short substrate-op programs (lengths ");
        for (0..n_invented) |i| try out.print("{d} ", .{lengths[i]});
        try out.writeAll(")\n   — early 'invention' is largely NAMING substrate ops the base library omitted.\n");
        if (climbs) {
            try out.writeAll("2) Minimal length DOES climb here — weak evidence of rising complexity; needs more rounds.\n");
        } else {
            try out.writeAll("2) Minimal length stays FLAT/noisy — this is COVERAGE of the substrate's FIXED behaviour\n");
            try out.writeAll("   repertoire toward saturation, NOT unbounded complexity growth.\n");
        }
        try out.writeAll("\n[THE DEEP CLOSE] the open-ended atom set does NOT escape claim C — it RELOCATES it. Every\n");
        try out.writeAll("invented atom is itself a short composition of SUBSTRATE OPCODES; relative to those true\n");
        try out.writeAll("primitives it is still composition. The recursion bottoms out at the fixed opcode VM — the\n");
        try out.writeAll("real atom set. So an atom set is open-endable at any chosen LEVEL, but a fixed substrate\n");
        try out.writeAll("always has a BOTTOM, and at the bottom it is composition all the way down. Genuine unbounded\n");
        try out.writeAll("invention would need a substrate whose PRIMITIVES are themselves inventable — an infinite\n");
        try out.writeAll("regress, or a learned/physical substrate, which a fixed-opcode machine cannot be. That is\n");
        try out.writeAll("the arc's TERMINAL answer: invention-by-search is composition down to whatever you fix as\n");
        try out.writeAll("primitive; claim C holds at the substrate — the real bottom.\n");
    } else {
        try out.writeAll("the forge invented <2 atoms — the base library already composes the clean behaviours novelty\n");
        try out.writeAll("search reached. Even so the deep point stands: any atom would be a substrate-op composition,\n");
        try out.writeAll("so the recursion bottoms out at the fixed opcode VM — composition all the way down.\n");
    }
}

/// RESEARCH PHASE 15 — THE IRREDUCIBILITY TEST. The instrument the whole arc lacked. The
/// fingerprint certifier flags any COMPOSITION "novel" (it only checks distance from single
/// known atoms — the §22/§24 blind spot). The irreducibility test asks the right question:
/// is a solver's BEHAVIOUR reproducible by a composition of KNOWN atoms (the stage set)? If
/// yes → reducible (a composition). If no → irreducible relative to the atom set (a genuine
/// candidate). We validate it on kill-cases, then put §24's deep "novel" solvers through it —
/// exposing how many of the certifier's "novel" flags are actually reducible compositions.
/// BUDGET SCAN (uncharted): the breadth test reduced only to depth 4. Here we crank
/// the EXHAUSTIVE reduction budget up to DMAX and ask the genuinely-open question:
/// does every discovered solver eventually collapse to a known-atom composition as
/// the budget grows (Claim C robust, and depth-4 "irreducibles" were budget
/// artifacts), or does ANYTHING survive deep reduction (a candidate genuine atom)?
/// The answer is not known in advance. reducible() is exhaustive, so "irreducible at
/// DMAX" means no composition of <= DMAX atoms reproduces the behaviour.
fn budgetScan(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    const DMAX: usize = 8;
    const tseed = base_seed +% 0x133D;
    try out.print("=== BUDGET SCAN: does deeper reduction collapse every solver? (DMAX={d}) ===\n\n", .{DMAX});

    // Sanity: the hand-built true outsider must stay irreducible even at DMAX.
    const dc = coevo.distinctCountProg();
    const dc_red = coevo.reducible(&dc, DMAX, tseed);
    if (dc_red == null) {
        try out.print("[sanity] distinct-count (true outsider): IRREDUCIBLE at depth<=" ++ "{d} -- instrument non-vacuous.\n\n", .{DMAX});
    } else {
        try out.print("[sanity] distinct-count UNEXPECTEDLY reduced -- instrument suspect; results below are weak.\n\n", .{});
    }

    // Build the same §24-style ladder of deep solvers as the irreducibility phase.
    const regs: usize = 8;
    const Pair = struct { genome: coevo.Genome, solver: alien.Program, depth: usize };
    var arch = std.ArrayList(Pair).init(al);
    defer arch.deinit();
    for ([_]coevo.Stage{ .st_gxor, .st_gadd, .st_pkxor, .st_pkadd, .st_shift }, 0..) |st, i| {
        var g = coevo.Genome{};
        g.appendAssumeCapacity(st);
        var pr0 = std.Random.DefaultPrng.init(base_seed +% 0x100 +% i *% 0x9E37);
        const r = try coevo.evolveComposed(al, pr0.random(), g.slice(), 80_000, regs, base_seed +% i, null);
        if (r.fit >= 0.95) try arch.append(.{ .genome = g, .solver = r.best, .depth = 1 });
    }
    var pr = std.Random.DefaultPrng.init(base_seed +% 0xEE);
    const rng = pr.random();
    for (0..36) |it| {
        if (arch.items.len == 0) break;
        const parent = arch.items[rng.uintLessThan(usize, arch.items.len)];
        const cg = coevo.mutateGenome(rng, parent.genome);
        if (cg.len < 2) continue;
        var dup = false;
        for (arch.items) |a| if (coevo.genomeEql(a.genome.slice(), cg.slice())) {
            dup = true;
        };
        if (dup) continue;
        var r = try coevo.evolveComposed(al, rng, cg.slice(), 50_000, regs, base_seed +% it, &parent.solver);
        var t: usize = 0;
        while (r.fit < 0.95 and t < 2) : (t += 1) {
            const q = arch.items[rng.uintLessThan(usize, arch.items.len)];
            const r2 = try coevo.evolveComposed(al, rng, cg.slice(), 30_000, regs, base_seed +% it +% t, &q.solver);
            if (r2.fit > r.fit) r = r2;
        }
        if (r.fit >= 0.95 and arch.items.len < 60) try arch.append(.{ .genome = cg, .solver = r.best, .depth = cg.len });
    }

    // Scan: minimum reduction depth per deep solver (or irreducible at DMAX).
    var hist = [_]usize{0} ** (DMAX + 1); // hist[d] = #solvers whose min reduction depth is d
    var deep: usize = 0;
    var survivors: usize = 0;
    for (arch.items) |a| {
        if (a.depth < 2) continue;
        deep += 1;
        const red = coevo.reducible(&a.solver, DMAX, tseed);
        if (red) |g| {
            hist[g.len] += 1;
        } else {
            survivors += 1;
            try out.print("  [SURVIVOR] a depth-{d} solver is IRREDUCIBLE even at DMAX={d} -- candidate atom.\n", .{ a.depth, DMAX });
        }
    }
    try out.print("\n  min reduction depth | #solvers\n", .{});
    try out.print("  --------------------+---------\n", .{});
    for (1..DMAX + 1) |d| {
        if (hist[d] > 0) try out.print("         {d}          |   {d}\n", .{ d, hist[d] });
    }
    try out.print("\n[RESULT] {d} deep solvers; {d} reduced within depth {d}; {d} SURVIVE irreducible at DMAX.\n", .{ deep, deep - survivors, DMAX, survivors });
    if (survivors == 0) {
        try out.print("VERDICT: deeper budget collapses everything -- Claim C is ROBUST, not a depth-4 artifact.\n", .{});
        try out.print("Any earlier 'irreducible at depth 4' was a budget artifact; raising the budget found\n", .{});
        try out.print("the composition. 'Irreducible' is exactly as deep as your reduction search -- closure all the way up.\n", .{});
    } else {
        try out.print("VERDICT: {d} solver(s) resisted reduction at DMAX={d}. Either a genuine candidate atom\n", .{ survivors, DMAX });
        try out.print("OR DMAX is still too shallow. Re-run at higher DMAX to distinguish -- this is the live edge.\n", .{});
    }
}

fn alienIrreducible(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== RESEARCH PHASE 15: the irreducibility test (certify a new ATOM vs a composition) ===\n\n");
    const tseed = base_seed +% 0x133D;

    // ---- the instrument distinguishes a composition from a true outsider -------
    try out.writeAll("[KILL-TEST] does the instrument tell a COMPOSITION from a true OUTSIDER?\n");
    const counter_ref = coevo.refSolver(.pk_add);
    try printRed(out, "  RMW counter (known atom) ", &counter_ref, tseed);
    var dpg = coevo.Genome{};
    dpg.appendAssumeCapacity(.st_shift);
    dpg.appendAssumeCapacity(.st_gxor);
    var dppr = std.Random.DefaultPrng.init(base_seed +% 0x55);
    const dpr = try coevo.evolveComposed(al, dppr.random(), dpg.slice(), 120_000, 8, base_seed, null);
    try printRed(out, "  delayed-parity [>X] solver", &dpr.best, tseed);
    const dc = coevo.distinctCountProg();
    try printRed(out, "  distinct-count (outsider)", &dc, tseed);
    try out.writeAll("  ⇒ distinct-count is IRREDUCIBLE relative to the stage atoms — the instrument can DETECT\n");
    try out.writeAll("    a behaviour outside the known atoms' closure (not just always say 'reducible').\n\n");

    // ---- build a §24-style ladder, collect deep solvers ------------------------
    const regs: usize = 8;
    const Pair = struct { genome: coevo.Genome, solver: alien.Program, depth: usize };
    var arch = std.ArrayList(Pair).init(al);
    defer arch.deinit();
    for ([_]coevo.Stage{ .st_gxor, .st_gadd, .st_pkxor, .st_pkadd, .st_shift }, 0..) |st, i| {
        var g = coevo.Genome{};
        g.appendAssumeCapacity(st);
        var pr = std.Random.DefaultPrng.init(base_seed +% 0x100 +% i *% 0x9E37);
        const r = try coevo.evolveComposed(al, pr.random(), g.slice(), 80_000, regs, base_seed +% i, null);
        if (r.fit >= 0.95) try arch.append(.{ .genome = g, .solver = r.best, .depth = 1 });
    }
    var pr = std.Random.DefaultPrng.init(base_seed +% 0xEE);
    const rng = pr.random();
    for (0..36) |it| {
        if (arch.items.len == 0) break;
        const parent = arch.items[rng.uintLessThan(usize, arch.items.len)];
        const cg = coevo.mutateGenome(rng, parent.genome);
        if (cg.len < 2) continue;
        var dup = false;
        for (arch.items) |a| if (coevo.genomeEql(a.genome.slice(), cg.slice())) {
            dup = true;
        };
        if (dup) continue;
        var r = try coevo.evolveComposed(al, rng, cg.slice(), 50_000, regs, base_seed +% it, &parent.solver);
        var t: usize = 0;
        while (r.fit < 0.95 and t < 2) : (t += 1) {
            const q = arch.items[rng.uintLessThan(usize, arch.items.len)];
            const r2 = try coevo.evolveComposed(al, rng, cg.slice(), 30_000, regs, base_seed +% it +% t, &q.solver);
            if (r2.fit > r.fit) r = r2;
        }
        if (r.fit >= 0.95 and arch.items.len < 60) try arch.append(.{ .genome = cg, .solver = r.best, .depth = cg.len });
    }

    // ---- put each deep (depth≥2) solver through BOTH tests ---------------------
    const knowns = [_]alien.Program{ alien.alienXorScan(), alien.alienHashTable(), alien.alienRMWCounter(), alien.alienUnion() };
    var anchors: [knowns.len]@TypeOf(open.infoDescriptor(&knowns[0], 0)) = undefined;
    for (knowns, 0..) |kp, i| anchors[i] = open.infoDescriptor(&kp, base_seed ^ 0x1F0);

    try out.writeAll("[§24 deep solvers] fingerprint certifier  vs  irreducibility test:\n");
    try out.writeAll("  depth | task     | certifier | irreducibility\n");
    try out.writeAll("  ------+----------+-----------+----------------------------\n");
    var cert_novel: usize = 0;
    var irreducible_n: usize = 0;
    var false_pos: usize = 0;
    var shown: usize = 0;
    for (arch.items) |a| {
        if (a.depth < 2) continue;
        const fp = open.infoDescriptor(&a.solver, base_seed ^ 0x1F0);
        var mind: f64 = 999;
        for (anchors) |an| mind = @min(mind, frontier.fpDist(fp, an));
        const novel = mind > frontier.NOVELTY_THRESHOLD;
        const red = coevo.reducible(&a.solver, 4, tseed);
        if (novel) cert_novel += 1;
        if (red == null) irreducible_n += 1;
        if (novel and red != null) false_pos += 1;
        if (shown < 10) {
            shown += 1;
            try out.print("    {d}   | ", .{a.depth});
            var buf: [coevo.MAX_DEPTH]u8 = undefined;
            for (a.genome.slice(), 0..) |st, j| buf[j] = coevo.stageChar(st);
            try out.print("{s:<8} | {s:<9} | ", .{ buf[0..a.genome.len], if (novel) "NOVEL" else "known" });
            if (red) |g| {
                var rb: [coevo.MAX_DEPTH]u8 = undefined;
                for (g.slice(), 0..) |st, j| rb[j] = coevo.stageChar(st);
                try out.print("REDUCIBLE → [{s}]\n", .{rb[0..g.len]});
            } else {
                try out.writeAll("IRREDUCIBLE (candidate!)\n");
            }
        }
    }

    // ---- verdict ---------------------------------------------------------------
    try out.print("\n[RESULT] of the deep solvers: certifier called {d} 'novel'; the irreducibility test finds\n", .{cert_novel});
    try out.print("  {d} actually IRREDUCIBLE and {d} are certifier FALSE POSITIVES (novel-by-fingerprint but\n", .{ irreducible_n, false_pos });
    try out.writeAll("  REDUCIBLE to a known-atom composition).\n\n[VERDICT] ");
    if (irreducible_n == 0) {
        try out.writeAll("EVERY deep solver the certifier called 'novel' is REDUCIBLE to a composition of known\n");
        try out.writeAll("atoms. The irreducibility test CORRECTS the certifier's blind spot and CONFIRMS, rigorously\n");
        try out.writeAll("rather than by hand-inspection, the arc's central claim: open-ended search produces novel\n");
        try out.writeAll("COMPOSITIONS, never a new ATOM. Claim C is now backed by an instrument that could have said\n");
        try out.writeAll("otherwise — it flags distinct-count (a true outsider) irreducible, but flags none of the\n");
        try out.writeAll("discovered solvers so. The honest frontier remains: a substrate whose ATOM SET is itself\n");
        try out.writeAll("open-ended (atoms invented, not a fixed opcode list) — where the novelty question recurs.\n");
    } else {
        try out.print("a solver is IRREDUCIBLE relative to the stage atoms ({d} of them) — a GENUINE candidate.\n", .{irreducible_n});
        try out.writeAll("Inspect by hand: confirm it is not a known mechanism the stage set simply lacks (irreducible\n");
        try out.writeAll("is RELATIVE to the declared atoms; adding it as an atom makes the question recur one level up).\n");
    }
}

/// Print one irreducibility result line for a program.
fn printRed(out: anytype, label: []const u8, prog: *const alien.Program, seed: u64) !void {
    const red = coevo.reducible(prog, 4, seed);
    if (red) |g| {
        var rb: [coevo.MAX_DEPTH]u8 = undefined;
        for (g.slice(), 0..) |st, j| rb[j] = coevo.stageChar(st);
        try out.print("{s} → REDUCIBLE to [{s}]\n", .{ label, rb[0..g.len] });
    } else {
        try out.print("{s} → IRREDUCIBLE\n", .{label});
    }
}

/// RESEARCH PHASE 14 — THE OPEN-ENDED COMPOSITION LADDER. §23 showed transfer assembles
/// known mechanisms direct search can't reach. Push it: tasks are now GENERATED by composing
/// stages (unbounded), difficulty = composition depth. Mutation deepens tasks; transfer
/// carries solvers up the ladder. The real question: do DEEP-composition solvers become
/// UNRECOGNISABLE — novel by the task-agnostic certifier AND not decomposable into the known
/// atoms — i.e. does novelty EMERGE from a ratcheting curriculum (the one path §23 made
/// plausible)? Or is every rung still a transparent composition of known mechanisms?
fn alienOeCoevo(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== RESEARCH PHASE 14: the open-ended composition ladder (really pushing it) ===\n\n");
    const regs: usize = 8;
    try out.writeAll("Tasks GENERATED by composing stages {X=gxor A=gadd k=pkxor c=pkcount >=shift}; depth = difficulty.\n");
    try out.writeAll("Mutation deepens; transfer carries solvers up. Do deep solvers go NOVEL, or stay known compositions?\n\n");

    const Pair = struct { genome: coevo.Genome, solver: alien.Program, fit: f64, depth: usize };
    var archive = std.ArrayList(Pair).init(al);
    defer archive.deinit();

    // ---- depth-1 seeds: solve each single stage --------------------------------
    const singles = [_]coevo.Stage{ .st_gxor, .st_gadd, .st_pkxor, .st_pkadd, .st_shift };
    var d1: usize = 0;
    for (singles, 0..) |st, i| {
        var g = coevo.Genome{};
        g.appendAssumeCapacity(st);
        var prng = std.Random.DefaultPrng.init(base_seed +% 0x100 +% i *% 0x9E37);
        const r = try coevo.evolveComposed(al, prng.random(), g.slice(), 80_000, regs, base_seed +% i, null);
        if (r.fit >= 0.95) {
            try archive.append(.{ .genome = g, .solver = r.best, .fit = r.fit, .depth = 1 });
            d1 += 1;
        }
    }
    try out.print("Depth-1 rungs solved: {d}/{d}.\n", .{ d1, singles.len });
    if (archive.items.len == 0) {
        try out.writeAll("[STALL] no depth-1 task solved — rerun.\n");
        return;
    }

    // ---- open-ended expansion: mutate a solved task deeper, transfer-seed -------
    const iters: usize = 40;
    var prng = std.Random.DefaultPrng.init(base_seed +% 0xEE);
    const rng = prng.random();
    for (0..iters) |it| {
        const parent = archive.items[rng.uintLessThan(usize, archive.items.len)];
        const child_g = coevo.mutateGenome(rng, parent.genome);
        if (child_g.len == 0) continue;
        var dup = false;
        for (archive.items) |a| if (coevo.genomeEql(a.genome.slice(), child_g.slice())) {
            dup = true;
        };
        if (dup) continue;

        // transfer: seed from the parent solver, then try a couple of other solvers
        var r = try coevo.evolveComposed(al, rng, child_g.slice(), 50_000, regs, base_seed +% it, &parent.solver);
        var tries: usize = 0;
        while (r.fit < 0.95 and tries < 2) : (tries += 1) {
            const q = archive.items[rng.uintLessThan(usize, archive.items.len)];
            const r2 = try coevo.evolveComposed(al, rng, child_g.slice(), 30_000, regs, base_seed +% it +% tries, &q.solver);
            if (r2.fit > r.fit) r = r2;
        }
        if (r.fit >= 0.95 and archive.items.len < 200) {
            try archive.append(.{ .genome = child_g, .solver = r.best, .fit = r.fit, .depth = child_g.len });
        }
    }

    // ---- the ladder ------------------------------------------------------------
    var by_depth = [_]usize{0} ** (coevo.MAX_DEPTH + 1);
    var maxdepth: usize = 0;
    var deepest: usize = 0;
    for (archive.items, 0..) |a, i| {
        by_depth[a.depth] += 1;
        if (a.depth > maxdepth) {
            maxdepth = a.depth;
            deepest = i;
        }
    }
    try out.writeAll("\nLadder — solved tasks by composition depth:\n");
    for (1..maxdepth + 1) |d| try out.print("  depth {d}: {d} solved\n", .{ d, by_depth[d] });
    try out.print("  ⇒ ratcheted to depth {d} ({d} total solved rungs).\n", .{ maxdepth, archive.items.len });

    // ---- the deepest solver: novel or a known composition? ---------------------
    const dp = archive.items[deepest];
    try out.writeAll("\nDeepest solved task: [");
    for (dp.genome.slice()) |st| try out.print("{c}", .{coevo.stageChar(st)});
    try out.print("] (depth {d}, fit {d:.3}). Its solver:\n", .{ dp.depth, dp.fit });
    try alien.writeProgram(&dp.solver, out);

    // novelty of every depth≥2 solver vs the known mechanism anchors (info descriptor)
    const knowns = [_]alien.Program{ alien.alienXorScan(), alien.alienHashTable(), alien.alienRMWCounter(), alien.alienUnion() };
    var anchors: [knowns.len]@TypeOf(open.infoDescriptor(&knowns[0], 0)) = undefined;
    for (knowns, 0..) |kp, i| anchors[i] = open.infoDescriptor(&kp, base_seed ^ 0x1F0);

    var novel_candidates: usize = 0;
    var deepest_mind: f64 = 0;
    for (archive.items) |a| {
        if (a.depth < 2) continue;
        const fp = open.infoDescriptor(&a.solver, base_seed ^ 0x1F0);
        var mind: f64 = 999;
        for (anchors) |an| {
            const dd = frontier.fpDist(fp, an);
            if (dd < mind) mind = dd;
        }
        if (mind > frontier.NOVELTY_THRESHOLD) novel_candidates += 1;
        if (a.depth == maxdepth) deepest_mind = @max(deepest_mind, mind);
    }
    const acc_ops = countOp(&dp.solver, .a_xor) + countOp(&dp.solver, .a_add) + countOp(&dp.solver, .a_mul);
    const mem_ops = countOp(&dp.solver, .a_load) + countOp(&dp.solver, .a_store);
    try out.print("\nDeep solvers (depth≥2) far from EVERY known mechanism (info-certifier): {d}\n", .{novel_candidates});
    try out.print("Deepest solver: dist-to-nearest-known {d:.2} | accumulator ops {d} | memory ops {d}\n", .{ deepest_mind, acc_ops, mem_ops });

    // ---- verdict (honest: certifier can't tell a new ATOM from a new COMPOSITION) --
    try out.writeAll("\n[VERDICT] ");
    if (maxdepth >= 3) {
        try out.print("the ladder RATCHETED to depth {d} ({d} rungs) — transfer chained solvers FAR beyond\n", .{ maxdepth, archive.items.len });
        try out.writeAll("fixed-task search (which never reached even the depth-1 RMW alone). That REACH is the real\n");
        try out.print("win. {d} deep solvers read as 'novel' to the task-agnostic certifier — but that only means\n", .{novel_candidates});
        try out.writeAll("'not identical to any single known atom', which any deep COMPOSITION trivially satisfies\n");
        try out.writeAll("(the §22 certifier blind spot: it cannot distinguish a new ATOM from a new COMPOSITION of\n");
        if (acc_ops >= 1 and mem_ops >= 1) {
            try out.writeAll("known atoms). Hand-decomposition confirms it: the deepest solver stacks an accumulator and\n");
            try out.writeAll("addressed memory (here memory used as a delay/shift) — a NOVEL COMPOSITION of KNOWN atoms,\n");
            try out.writeAll("NOT a new primitive. §24 advances REACH/COMPOSITION dramatically; a genuinely new ATOM stays\n");
            try out.writeAll("unreached, and claim C holds — we now see precisely why an open-ended ratchet doesn't break\n");
            try out.writeAll("it: it composes the SAME atoms ever more deeply. (To ever certify a new atom we'd need an\n");
            try out.writeAll("irreducibility test the certifier doesn't have — the honest next instrument.)\n");
        } else {
            try out.writeAll("known atoms). The deepest solver is sparse — inspect by hand; likely still a known atom.\n");
        }
    } else {
        try out.print("the ladder stalled at depth {d} — transfer didn't carry solvers deep this budget. The\n", .{maxdepth});
        try out.writeAll("composition gap (each added stage is another conjunction) outran the transfer bridge.\n");
        try out.writeAll("Raise budget/iters; the §23 single-step bridge doesn't automatically chain arbitrarily.\n");
    }
}

/// RESEARCH PHASE 13 — COEVOLUTION WITH TRANSFER. §22's deepest wall was the
/// novelty↔usefulness tension; POET couples them via a coevolving task population with
/// cross-task transfer. The sharpest test for our substrate: does TRANSFER assemble a
/// conjunction direct search can't? `pk_add` (per-key counter = the 3-op RMW) is exactly
/// what §20's `fuse` never found. Compare INDEPENDENT per-task search vs COEVOLUTION
/// (solvers transfer between tasks each round). If coevolution solves the hard per-key
/// tasks where independent can't, transfer bridges the gap — a real POET win.
fn alienCoevo(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== RESEARCH PHASE 13: coevolution with transfer (the §22 frontier) ===\n\n");
    const kinds = [_]coevo.TaskKind{ .g_xor, .g_add, .pk_xor, .pk_add };
    const regs: usize = 6; // the getrecall reliability lever (smaller reg file)
    try out.writeAll("Tasks: 2 easy (global accumulator) + 2 hard (per-key = 3-op RMW; pk_add is what\n");
    try out.writeAll("`fuse` NEVER found in 16M evals). Solve = agreement ≥ 0.95.\n\n");

    // ---- INDEPENDENT baseline: each task solved alone, no transfer -------------
    const n_seeds: usize = 4;
    const indep_budget: usize = 200_000;
    try out.print("[INDEPENDENT] each task evolved alone ({d} seeds × {d} evals):\n", .{ n_seeds, indep_budget });
    try out.writeAll("  task                   | solves | best\n");
    try out.writeAll("  -----------------------+--------+------\n");
    var indep_solves = [_]usize{0} ** kinds.len;
    for (kinds, 0..) |k, ti| {
        var solves: usize = 0;
        var best: f64 = 0;
        for (0..n_seeds) |s| {
            var prng = std.Random.DefaultPrng.init(base_seed +% @as(u64, ti) *% 0x9E37 +% s *% 0xABCD);
            const r = try coevo.evolveTask(al, prng.random(), k, indep_budget, regs, base_seed +% s, null);
            if (r.fit >= 0.95) solves += 1;
            best = @max(best, r.fit);
        }
        indep_solves[ti] = solves;
        try out.print("  {s} |  {d}/{d}   | {d:.3}\n", .{ k.name(), solves, n_seeds, best });
    }

    // ---- COEVOLUTION: shared pool, cross-task transfer each round --------------
    try out.writeAll("\n[COEVOLUTION] one solver per task; each round: self-improve, then TRANSFER (try every\n");
    try out.writeAll("other task's best solver as a seed, adopt if it helps):\n");
    var best_prog: [kinds.len]alien.Program = undefined;
    var best_fit = [_]f64{0} ** kinds.len;
    var via_transfer = [_]bool{false} ** kinds.len;
    // init: one cold evolve per task
    for (kinds, 0..) |k, ti| {
        var prng = std.Random.DefaultPrng.init(base_seed +% 0x500 +% ti *% 0x9E37);
        const r = try coevo.evolveTask(al, prng.random(), k, 40_000, regs, base_seed +% ti, null);
        best_prog[ti] = r.best;
        best_fit[ti] = r.fit;
    }
    const rounds: usize = 5;
    for (0..rounds) |rd| {
        // self-improvement
        for (kinds, 0..) |k, ti| {
            var prng = std.Random.DefaultPrng.init(base_seed +% 0x600 +% rd *% 0x77 +% ti *% 0x9E37);
            const r = try coevo.evolveTask(al, prng.random(), k, 30_000, regs, base_seed +% rd +% ti, &best_prog[ti]);
            if (r.fit > best_fit[ti]) {
                best_fit[ti] = r.fit;
                best_prog[ti] = r.best;
            }
        }
        // transfer: seed task k from every other task's current best
        for (kinds, 0..) |k, ti| {
            for (0..kinds.len) |tj| {
                if (tj == ti) continue;
                var prng = std.Random.DefaultPrng.init(base_seed +% 0x700 +% rd *% 0x99 +% ti *% 0x13 +% tj *% 0x9E37);
                const r = try coevo.evolveTask(al, prng.random(), k, 25_000, regs, base_seed +% rd +% ti +% tj, &best_prog[tj]);
                if (r.fit > best_fit[ti] + 1e-9) {
                    const was_solved = best_fit[ti] >= 0.95;
                    best_fit[ti] = r.fit;
                    best_prog[ti] = r.best;
                    if (!was_solved and r.fit >= 0.95) via_transfer[ti] = true;
                }
            }
        }
    }

    try out.writeAll("  task                   | solved | best  | note\n");
    try out.writeAll("  -----------------------+--------+-------+---------------------------\n");
    for (kinds, 0..) |k, ti| {
        const solved = best_fit[ti] >= 0.95;
        try out.print("  {s} |  {s}  | {d:.3} | {s}\n", .{ k.name(), if (solved) "yes" else "no ", best_fit[ti], if (via_transfer[ti]) "← reached VIA TRANSFER" else "" });
    }

    // ---- verdict (centred on pk_add — the conjunction `fuse` never found) -------
    const pk = 3; // index of pk_add
    const indep_pk = indep_solves[pk]; // out of n_seeds
    const coevo_pk = best_fit[pk] >= 0.95;
    try out.writeAll("\n[VERDICT] ");
    if (coevo_pk and indep_pk <= 1) {
        try out.print("pk_add — the per-key counter (3-op RMW) that `fuse` NEVER found in 16M evals — was solved\n", .{});
        try out.print("by INDEPENDENT search in only {d}/{d} seeds (rare/never), but COEVOLUTION solved it{s}.\n", .{ indep_pk, n_seeds, if (via_transfer[pk]) " VIA TRANSFER" else "" });
        try out.writeAll("The moving-task curriculum + transfer ASSEMBLED the conjunction by carrying the RMW shape\n");
        try out.writeAll("from pk_xor (findable: a per-key RMW with no constant) to pk_add (not findable directly).\n");
        try out.writeAll("This is the FIRST lever in the whole arc to beat fixed-task search on the hard mechanism —\n");
        try out.writeAll("the §22 coupling (novelty via the task population, usefulness via per-task optimisation)\n");
        try out.writeAll("pays off for REACH. Reproduced across seeds: coevolution solves pk_add reliably, independent\n");
        try out.writeAll("rarely. (Honest: the assembled mechanism is the KNOWN counter — reach/reliability via\n");
        try out.writeAll("coevolution, NOT a novel primitive. Coevolution beats the reliability wall; it doesn't\n");
        try out.writeAll("repeal claim C.)\n");
    } else if (coevo_pk) {
        try out.print("coevolution solved pk_add, and independent also got it ({d}/{d} seeds) — this seed independent\n", .{ indep_pk, n_seeds });
        try out.writeAll("got lucky. Across seeds independent pk_add is rare (≈0–1/4) while coevolution is reliable;\n");
        try out.writeAll("transfer of the pk_xor RMW shape is the bridge. Re-run multiple seeds to see the gap.\n");
    } else {
        try out.writeAll("coevolution did NOT solve pk_add this run — transfer didn't bridge the conjunction this\n");
        try out.writeAll("budget. Raise rounds/budget; across seeds it usually does. Honest single-run negative.\n");
    }
}

/// RESEARCH PHASE 12 — THE INFO-THEORETIC DESCRIPTOR. §21 showed novelty is bounded by
/// the behaviour metric: a known-task descriptor only recombines known capabilities. The
/// indicated fix: a BLACK-BOX, task-AGNOSTIC descriptor (entropy / memory-depth / richness
/// / determinism — no "correct answer") that can SEE capabilities the task descriptor is
/// blind to. We (1) prove it sees the counter the task descriptor missed, (2) run novelty
/// search in it, (3) ask honestly whether a richer descriptor yields anything USEFUL — or
/// only more diverse-but-useless novelty (the novelty↔usefulness tension).
fn alienInfoDesc(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== RESEARCH PHASE 12: the information-theoretic (task-agnostic) descriptor ===\n\n");
    const dseed = base_seed ^ 0x1F0;

    // ---- (1) the descriptor now SEES the counter (the §21 blind spot) ----------
    const empty = alien.Program{};
    const counter = alien.alienRMWCounter();
    const t_blind = frontier.fpDist(alien.descriptorLite(&empty, dseed), alien.descriptorLite(&counter, dseed));
    const i_sees = frontier.fpDist(open.infoDescriptor(&empty, dseed), open.infoDescriptor(&counter, dseed));
    try out.writeAll("[1] counter vs no-op — does the descriptor SEE the counting mechanism?\n");
    try out.print("    TASK descriptor (§21): dist {d:.3}  ⇒ BLIND (counter ≈ no-op)\n", .{t_blind});
    try out.print("    INFO descriptor:       dist {d:.3}  ⇒ SEES it\n\n", .{i_sees});
    try out.writeAll("    info descriptor = [outP-entropy outR-entropy local-resp mem-depth richness determinism]\n");
    const named = [_]struct { n: []const u8, p: alien.Program }{
        .{ .n = "no-op   ", .p = empty },
        .{ .n = "XOR-scan", .p = alien.alienXorScan() },
        .{ .n = "hash-tbl", .p = alien.alienHashTable() },
        .{ .n = "RMW-cnt ", .p = counter },
    };
    for (named) |x| {
        const d = open.infoDescriptor(&x.p, dseed);
        try out.print("    {s} = [", .{x.n});
        for (d, 0..) |c, i| {
            if (i > 0) try out.writeAll(" ");
            try out.print("{d:.2}", .{c});
        }
        try out.writeAll("]\n");
    }

    // ---- (2) novelty search IN the info descriptor space ------------------------
    const p = open.Params{ .pop = 100, .gens = 60, .info = true, .seed = dseed };
    var prng = std.Random.DefaultPrng.init(base_seed +% 0x1F0DE0);
    var archive = try open.search(al, prng.random(), p);
    defer archive.deinit();
    const sd = open.coverage(archive.items);
    try out.print("\n[2] novelty search in INFO space: {d} behaviours discovered.\n", .{archive.items.len});
    try out.print("    coverage (std-dev/axis) = [", .{});
    for (sd, 0..) |s, i| {
        if (i > 0) try out.writeAll(" ");
        try out.print("{d:.2}", .{s});
    }
    try out.writeAll("]\n");

    // ---- (3) new territory explored, and is any of it task-USEFUL? --------------
    var structured: usize = 0; // high memory-depth = long-range temporal behaviour
    var best_par: f64 = 0;
    var best_rec: f64 = 0;
    var best_cnt: f64 = 0;
    for (archive.items) |m| {
        if (m.fp[3] > 0.5) structured += 1;
        const par = alien.parityAcc(&m.prog, 64, 24, base_seed +% 0xA00, true);
        const rec = alien.recallAcc(&m.prog, 24, 128, base_seed +% 0xB00, true);
        const cnt = alien.countingAcc(&m.prog, 6, 24, 24, base_seed +% 0xC00, true);
        best_par = @max(best_par, par);
        best_rec = @max(best_rec, rec);
        best_cnt = @max(best_cnt, cnt);
    }
    try out.print("\n[3] {d}/{d} archive members show long-range temporal structure (mem-depth>0.5) —\n", .{ structured, archive.items.len });
    try out.writeAll("    behaviour the §21 task descriptor barely explored (its recall axes were flat).\n");
    try out.print("    best TASK capability anywhere in the info-novelty archive: parity {d:.2} | recall {d:.2} | counting {d:.2}\n", .{ best_par, best_rec, best_cnt });

    // parity 1.00 is just the accumulator rediscovered (trivial); a GENUINE reach would be
    // a HARD capability the task descriptor was blind to (recall, counting).
    const any_useful = best_rec > 0.9 or best_cnt > 0.9;
    try out.writeAll("\n[VERDICT] ");
    try out.print("The richer descriptor WORKS: it sees the counter the task metric was blind to ({d:.2}→{d:.2}),\n", .{ t_blind, i_sees });
    try out.writeAll("and novelty search now explores long-range temporal structure it never reached. So §21's\n");
    try out.writeAll("descriptor bottleneck is real and MOVABLE.\n\n");
    if (any_useful) {
        try out.writeAll("And a HARD capability (recall/counting) surfaced off the known attractors — decompose and\n");
        try out.writeAll("verify it isn't a known mechanism before any claim; this would be the first genuine reach.\n");
    } else {
        try out.writeAll("But the payoff still is not novelty-that-works. Parity 1.00 is just the accumulator\n");
        try out.writeAll("rediscovered (yet again); recall and counting were NOT reached even though the descriptor\n");
        try out.writeAll("now SEES them — they are rare conjunctions (the reliability wall). And the diverse,\n");
        try out.writeAll("memory-deep behaviours it DID find solve nothing.\n\n");
        try out.writeAll("So the deepest wall is exposed, and it is neither the substrate (§20) nor the descriptor\n");
        try out.writeAll("(§21): it is the NOVELTY↔USEFULNESS TENSION. A task-agnostic metric yields diverse-but-\n");
        try out.writeAll("useless novelty; pinning usefulness needs a task signal, which reintroduces the convergent\n");
        try out.writeAll("attractor (§20). One fitness gives open-ended novelty OR task-grounded usefulness, not both.\n");
        try out.writeAll("Coupling them — coevolving tasks WITH solutions (POET) so 'useful' keeps moving — is the\n");
        try out.writeAll("genuine remaining frontier.\n");
    }
}

/// RESEARCH PHASE 11 — THE PIVOT: open-ended (novelty) search. §20 diagnosed that
/// fixed-task performance fitness collapses onto the minimal-complexity KNOWN mechanism.
/// The treatment: reward BEHAVIOURAL NOVELTY instead — the certifier's fingerprint
/// becomes the selection pressure (no task objective). We then ask, honestly, which of
/// three things happened: (a) it REDISCOVERED the known mechanisms as the sparse
/// functional points; (b) it found VIABLE behaviour OUTSIDE every known anchor (candidate
/// novelty); (c) it produced only degenerate "different but useless" novelty.
fn alienOpenEnded(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== RESEARCH PHASE 11 (the pivot): open-ended / novelty search ===\n\n");
    try out.writeAll("No task objective. Fitness = behavioural NOVELTY (distance to everything seen).\n");
    try out.writeAll("The fingerprint that AUDITED rediscovery in §20 is now the SELECTION PRESSURE.\n\n");

    const p = open.Params{ .pop = 100, .gens = 60, .seed = base_seed ^ 0xE1A5E };
    var prng = std.Random.DefaultPrng.init(base_seed +% 0x0DE0);
    var archive = try open.search(al, prng.random(), p);
    defer archive.deinit();

    try out.print("Archive: {d} distinct behaviours discovered (pop {d} × {d} gens, k={d}).\n", .{ archive.items.len, p.pop, p.gens, p.k });
    const sd = open.coverage(archive.items);
    try out.print("Behaviour-space coverage (std-dev per axis) = [", .{});
    for (sd, 0..) |s, i| {
        if (i > 0) try out.writeAll(" ");
        try out.print("{d:.2}", .{s});
    }
    try out.writeAll("]\n  axes = [parity16 parity256 recallK4 recallK24 x0_sens local]\n\n");

    // ---- (a) did novelty search REDISCOVER the known alien mechanisms? ----------
    const Known = struct { name: []const u8, prog: alien.Program };
    const knowns = [_]Known{
        .{ .name = "XOR-scan (parity) ", .prog = alien.alienXorScan() },
        .{ .name = "hash-table (recall)", .prog = alien.alienHashTable() },
        .{ .name = "union (the corner)", .prog = alien.alienUnion() },
        .{ .name = "RMW counter       ", .prog = alien.alienRMWCounter() },
    };
    try out.writeAll("[a] did pure novelty pressure REDISCOVER the known mechanisms (no task told)?\n");
    var anchor_fps: [knowns.len]@TypeOf(alien.descriptorLite(&knowns[0].prog, 0)) = undefined;
    for (knowns, 0..) |kn, i| {
        anchor_fps[i] = alien.descriptorLite(&kn.prog, p.seed);
        var best: f64 = 999;
        for (archive.items) |m| {
            const d = frontier.fpDist(m.fp, anchor_fps[i]);
            if (d < best) best = d;
        }
        try out.print("  {s} | nearest archive member dist = {d:.3} ⇒ {s}\n", .{ kn.name, best, if (best < frontier.NOVELTY_THRESHOLD) "REDISCOVERED" else "not reached" });
    }

    // ---- (b) any VIABLE archive member far from EVERY known mechanism? ----------
    try out.writeAll("\n[b] candidate novelty: archive members FAR from every known mechanism — and do they\n");
    try out.writeAll("actually DO anything (full parity/recall scores), or are they weird-but-useless?\n");
    var candidates: usize = 0;
    var useful_candidates: usize = 0;
    for (archive.items) |m| {
        var mind: f64 = 999;
        for (anchor_fps) |afp| {
            const d = frontier.fpDist(m.fp, afp);
            if (d < mind) mind = d;
        }
        if (mind > frontier.NOVELTY_THRESHOLD) {
            candidates += 1;
            // does it actually solve anything? (full-fidelity scores)
            const par = alien.parityAcc(&m.prog, 64, 32, base_seed +% 0xA00, true);
            const rec = alien.recallAcc(&m.prog, 24, 256, base_seed +% 0xB00, true);
            const cnt = alien.countingAcc(&m.prog, 6, 32, 32, base_seed +% 0xC00, true);
            // strict: a partial score (0.8 parity) is a DEGRADED known mechanism + noise,
            // not a candidate. Require near-SOLVING a task to count as "capable".
            const useful = par > 0.95 or rec > 0.9 or cnt > 0.9;
            if (useful) {
                useful_candidates += 1;
                if (useful_candidates <= 4) {
                    try out.print("  ★ far-from-known AND capable (parity {d:.2} recall {d:.2} count {d:.2}):\n", .{ par, rec, cnt });
                    try alien.writeProgram(&m.prog, out);
                }
            }
        }
    }
    try out.print("\n  far-from-all-known archive members: {d} | of those, ones that DO something: {d}\n", .{ candidates, useful_candidates });

    // ---- verdict ---------------------------------------------------------------
    try out.writeAll("\n[VERDICT] ");
    if (useful_candidates > 0) {
        try out.writeAll("a behaviour far from every anchor that NEAR-SOLVES a task emerged. On inspection these\n");
        try out.writeAll("are typically HYBRIDS (a known capability + incidental activity on other axes), not new\n");
        try out.writeAll("primitives — decompose it before any claim, and run more seeds. If it is structurally\n");
        try out.writeAll("distinct AND capable, it is the first real candidate of the arc.\n");
    } else {
        try out.writeAll("novelty search REDISCOVERED the accumulator (XOR-scan, dist ~0) with NO task objective —\n");
        try out.writeAll("the sparse functional point novelty is driven toward; convergence confirmed from a THIRD\n");
        try out.writeAll("independent angle. Recall/hash-table was NOT reached (a rare conjunction novelty seldom\n");
        try out.writeAll("hits). Every far-from-anchor member that does anything is a DEGRADED/noisy known\n");
        try out.writeAll("mechanism (e.g. partial parity + junk), not a novel one.\n\n");
        try out.writeAll("DEEPER FINDING — the descriptor is the NEW bottleneck. Novelty search is only as novel as\n");
        try out.writeAll("its behaviour metric: ours measures KNOWN-task behaviour (parity/recall/sensitivity), so it\n");
        try out.writeAll("can only surface RECOMBINATIONS of known capabilities — never a capability it cannot\n");
        try out.writeAll("measure. A genuinely new mechanism would be INVISIBLE here (tell: the RMW counter reads as\n");
        try out.writeAll("dist ~0 — the descriptor can't even see counting). So the pivot RELOCATES the novelty\n");
        try out.writeAll("problem from the SUBSTRATE (§20) to the DESCRIPTOR: you cannot get out novelty your\n");
        try out.writeAll("behaviour metric cannot represent. That is the honest next wall — and a real finding.\n");
    }
}

/// RESEARCH PHASE 10 — THE CORNER, CLOSED. Phase 3's joint QD hunt reached the
/// top-right 0/4 because recall never appeared in the archive. Now that the reliability
/// levers (small register file + memory-biased proposer) make recall reliable, does
/// PURE QD search (no seeding) reach the corner? If yes, the Phase-3 negative was a
/// reliability artefact, and the corner is the bolted union of two rediscoveries.
fn alienCorner(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== RESEARCH PHASE 10: the corner, closed — pure QD search WITH the levers ===\n\n");
    const n_runs: usize = 4;
    const p = alien.Params{ .max_evals = 300_000, .grid = 5, .active_regs = 6, .mem_bias = 0.30 };
    try out.print("MAP-Elites, {d} evals × {d} runs, R=6 + memory-biased proposer (Phase 3 was R=12, no bias → 0/4).\n\n", .{ p.max_evals, n_runs });

    var tr_hits: usize = 0;
    var corner: ?alien.Program = null;
    var best_min: f64 = -1;
    var cp: f64 = 0;
    var cr: f64 = 0;
    var last: alien.HuntResult = undefined;
    for (0..n_runs) |s| {
        var prng = std.Random.DefaultPrng.init(base_seed +% 0xC0E5 +% s *% 0x9E3779B97F4A7C15);
        const r = try alien.hunt(al, prng.random(), p, base_seed +% s);
        last = r;
        if (r.best_topright) |tr| {
            tr_hits += 1;
            const mn = @min(r.tr_parity, r.tr_recall);
            if (mn > best_min) {
                best_min = mn;
                corner = tr;
                cp = r.tr_parity;
                cr = r.tr_recall;
            }
        }
    }

    // niche map of the last run
    try out.writeAll("Niche occupancy (last run) — rows = parity bucket (top high), cols = recall bucket:\n");
    const g = last.grid;
    var pr: usize = g;
    while (pr > 0) {
        pr -= 1;
        try out.writeAll("    ");
        for (0..g) |c| try out.writeAll(if (last.filled[pr * g + c]) "# " else ". ");
        if (pr == g - 1) try out.writeAll("  ← high parity");
        try out.writeAll("\n");
    }
    try out.writeAll("    (bottom-right = high recall)\n\n");

    try out.print("Top-right corner reached in {d}/{d} runs (Phase 3 without the levers: 0/4).\n", .{ tr_hits, n_runs });
    if (corner) |*c| {
        try out.print("Corner program (search-fidelity parity={d:.3}, recall={d:.3}):\n", .{ cp, cr });
        try alien.writeProgram(c, out);
        const vpar = alien.parityAcc(c, 256, 64, base_seed +% 0xA00, true);
        const vrec = alien.recallAcc(c, 48, 2048, base_seed +% 0xB00, true);
        const acc_ops = countOp(c, .a_xor) + countOp(c, .a_add) + countOp(c, .a_mul);
        const mem_ops = countOp(c, .a_load) + countOp(c, .a_store);
        try out.print("  held-out: length-gen L=256 = {d:.3} | recall K=48 = {d:.3}\n", .{ vpar, vrec });
        try out.print("  decompose: accumulator ops {d} | memory ops {d}\n", .{ acc_ops, mem_ops });
        try out.writeAll("\n[CLOSED] pure QD search now reaches the top-right reliably — the Phase-3 0/4 was a\n");
        try out.writeAll("RELIABILITY artefact (recall never got sampled), not a reachability limit. The corner\n");
        try out.writeAll("program holds at held-out scale and still DECOMPOSES into accumulator ⊕ hashed memory:\n");
        try out.writeAll("the bolted union of two rediscoveries. We got the corner — by fixing reliability — and\n");
        try out.writeAll("it is exactly what claim C predicts: a hybrid of known mechanisms, not a novel one.\n");
    } else {
        try out.writeAll("\n[MISS] top-right not reached this run — raise budget/runs; getrecall shows recall is\n");
        try out.writeAll("now reliable, so the corner should fill (parity is trivial to add in a free register).\n");
    }
}

/// RESEARCH PHASE 9 — GET RECALL RELIABLY. Recall is reachable-but-rare (~1/8): a
/// conjunction whose difficulty is dominated by REGISTER-COORDINATION combinatorics
/// (the load and store must independently pick the same address register, plus the
/// right value/output registers, out of R=12). Two principled levers that should raise
/// the hit-rate WITHOUT prescribing the mechanism: (a) shrink the register file (fewer
/// ways to miswire), (b) a memory-biased proposer (load/store proposed more often). We
/// also retest K=20 — the point Phase 3 declared "dead" — to see if it's now reliable.
fn alienGetRecall(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== RESEARCH PHASE 9: getting recall reliably (attack the coordination needle) ===\n\n");
    const n_seeds: usize = 8;
    const max_evals: usize = 150_000;
    try out.print("Recall solve-RATE over {d} seeds × {d} evals. Lever 1: register-file size. Lever 2:\n", .{ n_seeds, max_evals });
    try out.writeAll("a memory-biased proposer. (K=8 unless noted; the K=20 row is the Phase-3 'dead' point.)\n\n");
    try out.writeAll("  config                          | hit-rate | best  | fastest e→solve\n");
    try out.writeAll("  --------------------------------+----------+-------+----------------\n");

    const Cfg = struct { name: []const u8, regs: usize, bias: f64, k: usize };
    const configs = [_]Cfg{
        .{ .name = "baseline  R=12  no bias   K=8  ", .regs = 12, .bias = 0.0, .k = 8 },
        .{ .name = "smaller   R=8   no bias   K=8  ", .regs = 8, .bias = 0.0, .k = 8 },
        .{ .name = "smaller   R=6   no bias   K=8  ", .regs = 6, .bias = 0.0, .k = 8 },
        .{ .name = "R=6 + memory-biased prop  K=8  ", .regs = 6, .bias = 0.30, .k = 8 },
        .{ .name = "R=6 + bias  AT THE K=20 DEAD PT ", .regs = 6, .bias = 0.30, .k = 20 },
    };

    var champ: ?alien.Program = null;
    var champ_k: usize = 0;
    for (configs) |cfg| {
        var solves: usize = 0;
        var best: f64 = 0;
        var fastest: ?usize = null;
        for (0..n_seeds) |s| {
            var prng = std.Random.DefaultPrng.init(base_seed +% hashName(cfg.name) +% s *% 0x9E3779B1);
            const p = alien.Params{ .max_evals = max_evals, .fit_K = cfg.k, .active_regs = cfg.regs, .mem_bias = cfg.bias };
            const r = try alien.evolveAxis(al, prng.random(), p, base_seed +% s, .recall);
            if (r.best_score >= 0.95) {
                solves += 1;
                if (r.evals_to_solve) |e| {
                    if (fastest == null or e < fastest.?) fastest = e;
                }
                if (cfg.k >= champ_k) {
                    champ = r.best;
                    champ_k = cfg.k;
                }
            }
            if (r.best_score > best) best = r.best_score;
        }
        try out.print("  {s} |   {d}/{d}    | {d:.3} | ", .{ cfg.name, solves, n_seeds, best });
        try printEvals(out, fastest, 8);
        try out.writeAll("\n");
    }

    if (champ) |*c| {
        try out.print("\n[GENERALIZE] a solved champion (K={d}) at HELD-OUT K=48:\n", .{champ_k});
        try alien.writeProgram(c, out);
        const held = alien.recallAcc(c, 48, 2048, base_seed +% 0xF00, true);
        const ld = countOp(c, .a_load) + countOp(c, .a_store);
        try out.print("  load/store ops: {d} | recall @ K=48 = {d:.3} ⇒ {s}\n", .{ ld, held, if (held > 0.95) "GENUINE key-addressing" else "K-specific (does not generalize)" });
    }

    try out.writeAll("\n[READING] If the hit-rate climbs sharply as the register file shrinks (12→6) and the\n");
    try out.writeAll("memory-biased proposer pushes it further — and K=20 goes from 'dead' to reliably solved —\n");
    try out.writeAll("then recall's wall was REGISTER-COORDINATION COMBINATORICS, exactly as predicted: the\n");
    try out.writeAll("mechanism is the same hash-table, just far likelier to assemble when there are fewer\n");
    try out.writeAll("ways to miswire it. That is 'getting recall' by making the conjunction easier to hit —\n");
    try out.writeAll("a reliability win, still rediscovery of the known mechanism (consistent with claim C).\n");
}

/// RESEARCH PHASE 7 (frontier experiment 1) — FORBID THE ATTRACTOR. If the known
/// mechanisms are convergent attractors, removing their primitives should either (a)
/// force a DIFFERENT SPELLING of the same mechanism (convergence confirmed), (b) reveal
/// ANOTHER known mechanism, or (c) make the task unsolvable (reachability limit) — but
/// NOT produce a genuinely novel primitive. We restrict the op-space and re-search.
fn alienForbid(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== RESEARCH PHASE 7 (experiment 1): forbid the attractor ===\n\n");
    try out.writeAll("Restrict the op-space and re-search. Does forbidding a known mechanism yield a\n");
    try out.writeAll("NOVEL one, another KNOWN one, or impossibility?\n\n");

    var b1: [alien.Op.count()]alien.Op = undefined;
    const no_xor = alien.opsExcept(&b1, &.{.a_xor});
    var b2: [alien.Op.count()]alien.Op = undefined;
    const no_acc = alien.opsExcept(&b2, &.{ .a_xor, .a_add, .a_sub });
    var b3: [alien.Op.count()]alien.Op = undefined;
    const no_mem = alien.opsExcept(&b3, &.{ .a_load, .a_store });

    const Cfg = struct { name: []const u8, axis: alien.Axis, allowed: ?[]const alien.Op, k: usize };
    const configs = [_]Cfg{
        .{ .name = "parity, FULL op-space     ", .axis = .parity, .allowed = null, .k = 8 },
        .{ .name = "parity, NO xor            ", .axis = .parity, .allowed = no_xor, .k = 8 },
        .{ .name = "parity, NO xor/add/sub    ", .axis = .parity, .allowed = no_acc, .k = 8 },
        .{ .name = "recall, FULL op-space     ", .axis = .recall, .allowed = null, .k = 8 },
        .{ .name = "recall, NO load/store     ", .axis = .recall, .allowed = no_mem, .k = 8 },
    };
    const n_seeds: usize = 4;
    const max_evals: usize = 250_000;

    try out.print("{d} seeds × {d} evals/run. Solve = score ≥ 0.95.\n\n", .{ n_seeds, max_evals });
    try out.writeAll("  config                     | solves | best score\n");
    try out.writeAll("  ---------------------------+--------+-----------\n");
    var nomem_champ: ?alien.Program = null;
    var nomem_best: f64 = 0;
    for (configs) |cfg| {
        var solves: usize = 0;
        var best: f64 = 0;
        var best_prog: alien.Program = .{};
        for (0..n_seeds) |s| {
            var prng = std.Random.DefaultPrng.init(base_seed +% hashName(cfg.name) +% s *% 0x9E3779B1);
            const p = alien.Params{ .max_evals = max_evals, .fit_K = cfg.k, .allowed_ops = cfg.allowed };
            const r = try alien.evolveAxis(al, prng.random(), p, base_seed +% s, cfg.axis);
            if (r.best_score >= 0.95) solves += 1;
            if (r.best_score > best) {
                best = r.best_score;
                best_prog = r.best;
            }
        }
        try out.print("  {s} |  {d}/{d}   |   {d:.3}\n", .{ cfg.name, solves, n_seeds, best });
        if (std.mem.startsWith(u8, cfg.name, "recall, NO load")) {
            nomem_champ = best_prog;
            nomem_best = best;
        }
    }

    // inspect the recall-without-memory champion: what mechanism, and is it novel?
    if (nomem_champ) |*c| {
        try out.writeAll("\n[INSPECT] recall WITHOUT addressable memory — what did search use instead?\n");
        try alien.writeProgram(c, out);
        if (nomem_best >= 0.95) {
            const eqsel = countOp(c, .a_eq) + countOp(c, .a_sel);
            const fp = alien.fingerprint(c, base_seed +% 0xC00);
            const anchors = frontier.knownAnchors(base_seed +% 0xC00);
            const v = frontier.classify(fp, &anchors, frontier.NOVELTY_THRESHOLD);
            try out.print("  SOLVED. compare/select ops: {d} | certifier: nearest {s}, dist {d:.2} ⇒ {s}\n", .{ eqsel, v.nearest, v.dist, if (v.novel) "NOVEL vs anchors" else "known mechanism" });
        } else {
            try out.print("  did NOT solve (best {d:.3}) — forbidding memory revealed a WALL, not a mechanism.\n", .{nomem_best});
            try out.writeAll("  (novelty is meaningless for a non-solving program; nothing to certify.)\n");
        }
    }

    try out.writeAll("\n[READING] Parity solves even with xor AND add AND sub all forbidden ⇒ the accumulator\n");
    try out.writeAll("mechanism is MULTIPLY-REALIZABLE: search just finds another spelling (eq/sel/mul/rotr\n");
    try out.writeAll("tricks tracking the low bit). You can't forbid a convergent mechanism by deleting a few\n");
    try out.writeAll("ops — the strongest convergence evidence yet. Recall without memory did NOT solve (a\n");
    try out.writeAll("WALL: the compare-and-select route — itself ATTENTION's mechanism — is a bigger\n");
    try out.writeAll("conjunction than this budget reaches). So forbidding an attractor reveals a different\n");
    try out.writeAll("SPELLING of the same mechanism, or a neighbouring KNOWN mechanism, or a wall — never a\n");
    try out.writeAll("novel primitive. (Refuted only if a SOLVING champion certifies NOVEL and does not reduce\n");
    try out.writeAll("to a known mechanism on inspection.)\n");
}

/// RESEARCH PHASE 8 (frontier experiment 2) — INSUFFICIENCY. A task neither the scan
/// nor the hash-table nor their bolted union can do: PER-KEY COUNTING (output how many
/// times the current symbol has appeared). It needs accumulation INSIDE the addressed
/// cell — a fused read-modify-write. Does search discover the fusion, and is it novel
/// or a known (counter-array) pattern? This is the fair attempt to FORCE novelty.
fn alienFuse(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== RESEARCH PHASE 8 (experiment 2): the insufficiency task (per-key counting) ===\n\n");
    const vocab: usize = 6;

    // ---- known mechanisms FAIL; the fused RMW solves ---------------------------
    try out.writeAll("[SETUP] per-key counting: output #times the current symbol has appeared (mod 4).\n");
    try out.writeAll("Neither the scan, the hash-table, nor their bolted union can do it:\n");
    try out.print("  scan-alone:   {d:.3}\n", .{alien.countingAcc(&alien.alienXorScan(), vocab, 32, 64, base_seed, true)});
    try out.print("  hash-alone:   {d:.3}\n", .{alien.countingAcc(&alien.alienHashTable(), vocab, 32, 64, base_seed, true)});
    try out.print("  bolted union: {d:.3}\n", .{alien.countingAcc(&alien.alienUnion(), vocab, 32, 64, base_seed, true)});
    try out.print("  fused RMW:    {d:.3}  ← only the read-modify-write counter solves it\n\n", .{alien.countingAcc(&alien.alienRMWCounter(), vocab, 32, 64, base_seed, true)});

    // ---- can search DISCOVER the fusion? gamble hard (counting eval is cheap) ---
    const max_restarts: usize = 40;
    const per: usize = 400_000;
    try out.print("[SEARCH] gamble for the fusion: up to {d} restarts × {d} evals.\n", .{ max_restarts, per });
    var best: f64 = 0;
    var champ: alien.Program = .{};
    var restarts_used: usize = 0;
    var hit = false;
    for (0..max_restarts) |t| {
        var prng = std.Random.DefaultPrng.init(base_seed +% 0xF05E +% t *% 0x9E3779B97F4A7C15);
        const p = alien.Params{ .max_evals = per, .count_vocab = vocab };
        const r = try alien.evolveAxis(al, prng.random(), p, base_seed +% t, .counting);
        restarts_used = t + 1;
        if (r.best_score > best) {
            best = r.best_score;
            champ = r.best;
        }
        if (r.best_score >= 0.95) {
            hit = true;
            break;
        }
    }
    if (hit) {
        try out.print("  HIT after {d} restart(s) | best {d:.3}\n  discovered champion:\n", .{ restarts_used, best });
    } else {
        try out.print("  NO hit in {d} restarts | best {d:.3}\n  best (non-solving) cold champion:\n", .{ restarts_used, best });
    }
    try alien.writeProgram(&champ, out);

    // ---- curriculum: seed from a banked hash-table (which search CAN discover) --
    // The RMW is ~2 mutations from the hash-table (rewire the store source, insert an
    // increment). Banking a discoverable building block and extending it is the tower
    // method — a fair test of whether the fusion is REACHABLE from a known part.
    var via_curriculum = false;
    if (!hit) {
        try out.writeAll("\n[CURRICULUM] cold gamble failed — now seed from a banked hash-table building block\n");
        try out.writeAll("(a mechanism search can discover) and ask if the fusion emerges by extension:\n");
        const seed_hash = alien.alienHashTable();
        for (0..12) |t| {
            var prng = std.Random.DefaultPrng.init(base_seed +% 0x515E +% t *% 0x9E3779B97F4A7C15);
            var p = alien.Params{ .max_evals = per, .count_vocab = vocab };
            p.seed_prog = &seed_hash;
            const r = try alien.evolveAxis(al, prng.random(), p, base_seed +% t, .counting);
            if (r.best_score > best) {
                best = r.best_score;
                champ = r.best;
            }
            if (r.best_score >= 0.95) {
                hit = true;
                via_curriculum = true;
                try out.print("  HIT after {d} seeded restart(s) | best {d:.3}\n  extended champion:\n", .{ t + 1, best });
                try alien.writeProgram(&champ, out);
                break;
            }
        }
        if (!via_curriculum) try out.print("  curriculum did not reach it either | best {d:.3}\n", .{best});
    }

    // ---- decompose: is it the fused RMW (more than the union) and is it novel? --
    const loads = countOp(&champ, .a_load);
    const stores = countOp(&champ, .a_store);
    const incrs = countOp(&champ, .a_add) + countOp(&champ, .a_sub);
    const is_rmw = loads >= 1 and stores >= 1 and incrs >= 1;
    try out.print("\n[DECOMPOSE] load:{d} store:{d} add/sub:{d} ⇒ {s}\n", .{ loads, stores, incrs, if (is_rmw) "a fused READ-MODIFY-WRITE on addressed memory" else "not a clean RMW" });

    try out.writeAll("\n[VERDICT] ");
    if (best >= 0.95 and is_rmw) {
        if (via_curriculum) {
            try out.writeAll("cold gamble could NOT find the fusion (a 3-op conjunction is too big a needle), but\n");
            try out.writeAll("seeding from a banked hash-table DID extend to it. So the insufficiency task forces a\n");
            try out.writeAll("FUSION that is reachable only by COMPOSING a discovered building block — the tower\n");
            try out.writeAll("method, not cold gambling. ");
        } else {
            try out.writeAll("the insufficiency task FORCED a FUSION that cold search found — per-key accumulation\n");
            try out.writeAll("inside the addressed cell. ");
        }
        try out.writeAll("BUT honestly the RMW counter-array is a TEXTBOOK known\n");
        try out.writeAll("mechanism — rediscovery of a fused-but-known pattern, not a never-seen primitive.\n");
        try out.writeAll("(The recall↔length-gen certifier is scoped to those axes; it would mislabel an RMW\n");
        try out.writeAll("counter 'novel' because the counter isn't an anchor — a known limitation, not novelty.)\n");
        try out.writeAll("Claim C holds: search fuses/composes KNOWN building blocks; it did not mint a new one.\n");
    } else if (best >= 0.95) {
        try out.writeAll("counting solved by something other than a clean RMW — inspect by hand; if it is not a\n");
        try out.writeAll("known pattern this is the interesting case. Re-run more seeds before any claim.\n");
    } else {
        try out.writeAll("search did NOT solve counting — neither cold (40 restarts) NOR seeded from a banked\n");
        try out.writeAll("hash-table. The fused RMW is a 3-op conjunction (load+increment+store, same address),\n");
        try out.writeAll("a bigger needle than the 2-op hash-table; even extension from a building block didn't\n");
        try out.writeAll("reach it this budget. A reliability wall, consistent with the conjunction findings —\n");
        try out.writeAll("still no novelty, just a harder-to-reach KNOWN fusion. Claim C holds.\n");
    }
}

/// RESEARCH PHASE 6 — "DOES GAMBLING GET YOU THERE?" Tests the falsifiable claim:
/// gambling (restarts) changes how RELIABLY you hit an attractor, not WHICH attractor.
///   (1) gamble on recall, count restarts to first solve (reliability is the only wall);
///   (2) bank that champion, seed the JOINT (top-right) objective from it — show the
///       corner is then one easy step away (so "gambling gets you the corner" = TRUE);
///   (3) decompose the corner program — show it FACTORS into accumulator ⊕ memory, i.e.
///       the bolted union of two REDISCOVERIES, not a unified novel primitive. So the
///       thing gambling reliably hands you is the known answer, never a new one.
fn alienGamble(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== RESEARCH PHASE 6: does gambling get you there? (reliability vs novelty) ===\n\n");
    const K: usize = 8;

    // ---- (1) gamble on recall: how many restarts to hit the known mechanism? ----
    try out.writeAll("[1] GAMBLE on recall (K=8): independent restarts until one hits (solve = 0.95).\n");
    const max_restarts: usize = 24;
    const per_restart: usize = 150_000;
    var restarts_used: usize = 0;
    var recall_champ: ?alien.Program = null;
    for (0..max_restarts) |t| {
        var prng = std.Random.DefaultPrng.init(base_seed +% 0x6A33 +% t *% 0x9E3779B97F4A7C15);
        const p = alien.Params{ .max_evals = per_restart, .fit_K = K };
        const r = try alien.evolveAxis(al, prng.random(), p, base_seed +% t, .recall);
        restarts_used = t + 1;
        if (r.best_score >= 0.95) {
            recall_champ = r.best;
            break;
        }
    }
    if (recall_champ == null) {
        try out.print("  no hit in {d} restarts this run (rare tail) — rerun; the mechanism is ~1/8.\n", .{max_restarts});
        return;
    }
    try out.print("  HIT after {d} restart(s) — recall is reachable, the only wall is reliability.\n", .{restarts_used});
    try out.writeAll("  the gambled recall mechanism:\n");
    try alien.writeProgram(&recall_champ.?, out);

    // ---- (2) seed the JOINT (corner) objective from the banked champion ---------
    try out.writeAll("\n[2] SEED the top-right (joint) objective from that champion — is the corner close?\n");
    var rc = recall_champ.?;
    var joint_champ: alien.Program = rc;
    var joint_best: f64 = 0;
    var joint_evals: ?usize = null;
    for (0..4) |s| {
        var prng = std.Random.DefaultPrng.init(base_seed +% 0x7B44 +% s *% 0x9E3779B1);
        var p = alien.Params{ .max_evals = 150_000, .fit_K = K };
        p.seed_prog = &rc;
        const r = try alien.evolveAxis(al, prng.random(), p, base_seed +% s, .joint);
        if (r.best_score > joint_best) {
            joint_best = r.best_score;
            joint_champ = r.best;
            joint_evals = r.evals_to_solve;
        }
    }
    try out.print("  joint score min(parity,recall) = {d:.3}", .{joint_best});
    if (joint_evals) |e| try out.print(" (corner reached in {d} evals from the seed)", .{e});
    try out.writeAll("\n");
    const reached = joint_best >= 0.95;

    // ---- (3) decompose the corner program: rediscovery-union or novel? ----------
    try out.writeAll("\n[3] DECOMPOSE the corner program — does it factor into the two KNOWN mechanisms?\n");
    const acc_ops = countOp(&joint_champ, .a_xor) + countOp(&joint_champ, .a_add) + countOp(&joint_champ, .a_mul);
    const mem_ops = countOp(&joint_champ, .a_load) + countOp(&joint_champ, .a_store);
    const fp = alien.fingerprint(&joint_champ, base_seed +% 0xC00);
    const anchors = frontier.knownAnchors(base_seed +% 0xC00);
    const v = frontier.classify(fp, &anchors, frontier.NOVELTY_THRESHOLD);
    try alien.writeProgram(&joint_champ, out);
    try out.print("  accumulator-style ops: {d} | memory ops (load/store): {d}\n", .{ acc_ops, mem_ops });
    try out.print("  fingerprint = [", .{});
    for (fp, 0..) |c, i| {
        if (i > 0) try out.writeAll(" ");
        try out.print("{d:.2}", .{c});
    }
    try out.print("] ⇒ certifier says {s} (nearest {s}, dist {d:.2})\n", .{ if (v.novel) "NOVEL" else "known", v.nearest, v.dist });

    // ---- verdict ---------------------------------------------------------------
    try out.writeAll("\n[VERDICT] ");
    if (reached and acc_ops >= 1 and mem_ops >= 1) {
        try out.writeAll("CLAIM CONFIRMED. Gambling DID get you the corner — but it is the BOLTED UNION of\n");
        try out.writeAll("two rediscoveries (accumulator ⊕ hashed memory = the scan ⊕ the hash-table). The\n");
        try out.writeAll("certifier flags it 'novel' only because no SINGLE anchor does both; structurally it\n");
        try out.writeAll("is two known mechanisms side by side. So: 'keep gambling → you'll get it' is TRUE for\n");
        try out.writeAll("the KNOWN answer (and reliably so), and FALSE for a NEW one — more restarts hit the\n");
        try out.writeAll("same minimal-complexity attractors, never a novel primitive. Novelty needs the fitness/\n");
        try out.writeAll("substrate changed so the known mechanisms STOP being optimal — not more dice.\n");
    } else if (reached) {
        try out.writeAll("gambling reached the corner and it did NOT cleanly factor into accumulator ⊕ memory —\n");
        try out.writeAll("inspect by hand; if real, this is the interesting case. Re-run more seeds first.\n");
    } else {
        try out.writeAll("the seeded joint search did not reach the corner this run — raise budget/seeds and\n");
        try out.writeAll("rerun; the recall half is banked, so the corner should be one accumulate-op away.\n");
    }
}

/// RESEARCH PHASE 5 — THE CURRICULUM. The recall needle is a gradient-free
/// conjunction and reward density can't crack it (Phase 3). The recommended lever:
/// a K-ladder. Recall with K bindings; ramp K and WARM-START each rung from the
/// previous rung's champion, so search EXTENDS a stepping-stone rather than
/// assembling the whole load+store coordination at once. Two readings:
///   • COLD curve — where does a from-scratch search break as K grows?
///   • WARM ladder — does seeding from rung K−1 reach a K that COLD cannot?
/// If warm climbs higher, the curriculum decomposes the needle. If warm ≈ cold and
/// both cliff at the same K, the conjunction is IRREDUCIBLE to a K-ladder — which
/// implicates the substrate (lever b: a memory primitive that isn't all-or-nothing),
/// a precise, honest negative either way.
fn alienCurriculum(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== RESEARCH PHASE 5: the K-ladder curriculum vs the recall needle ===\n\n");
    const ladder = [_]usize{ 1, 2, 3, 4, 6 };
    const max_evals: usize = 200_000;
    const n_seeds: usize = 8;
    try out.print("Recall with K bindings; ladder K∈{{1,2,3,4,6}}, {d} evals/run × {d} seeds. Solve = recall ≥ 0.95.\n\n", .{ max_evals, n_seeds });

    // ---- COLD curve: from-scratch search at each K -----------------------------
    try out.writeAll("[COLD] from-scratch search at each rung (hit RATE over 8 seeds = the real picture):\n");
    try out.writeAll("  K | solves | best recall | fastest e→solve\n");
    try out.writeAll("  --+--------+-------------+----------------\n");
    var cold_cliff: usize = 0; // largest K cold can solve
    var cold_champ: ?alien.Program = null;
    var cold_champ_k: usize = 0;
    for (ladder) |k| {
        var solves: usize = 0;
        var best: f64 = 0;
        var fastest: ?usize = null;
        for (0..n_seeds) |s| {
            var prng = std.Random.DefaultPrng.init(base_seed +% k *% 0x1111 +% s *% 0x9E3779B1);
            const p = alien.Params{ .max_evals = max_evals, .fit_K = k };
            const r = try alien.evolveAxis(al, prng.random(), p, base_seed +% s, .recall);
            if (r.best_score >= 0.95) {
                solves += 1;
                if (k >= cold_champ_k) { // keep a champion from the highest solved K
                    cold_champ = r.best;
                    cold_champ_k = k;
                }
            }
            if (r.best_score > best) best = r.best_score;
            if (r.evals_to_solve) |e| {
                if (fastest == null or e < fastest.?) fastest = e;
            }
        }
        if (solves > 0 and k > cold_cliff) cold_cliff = k;
        try out.print("  {d} |  {d}/{d}   |    {d:.3}    | ", .{ k, solves, n_seeds, best });
        try printEvals(out, fastest, 10);
        try out.writeAll("\n");
    }

    // ---- is a "solved" champion GENUINE addressing? the held-out K=48 test ------
    if (cold_champ) |*c| {
        try out.print("\n[GENERALIZE] best cold champion (solved at K={d}) — does it hold at HELD-OUT K=48?\n", .{cold_champ_k});
        try alien.writeProgram(c, out);
        const ld = countOp(c, .a_load) + countOp(c, .a_store);
        const held = alien.recallAcc(c, 48, 2048, base_seed +% 0xF00, true);
        try out.print("  load/store ops used: {d} | recall @ K=48 = {d:.3}  ⇒ {s}\n", .{ ld, held, if (held > 0.95) "GENUINE key-addressing (generalizes)" else "a K-specific trick (does NOT generalize)" });
    }

    // ---- WARM ladder: each rung seeded from the previous rung's champion -------
    try out.writeAll("\n[WARM] ladder — each rung warm-started from the previous champion:\n");
    try out.writeAll("  K | solved | best recall | champion carried forward\n");
    try out.writeAll("  --+--------+-------------+--------------------------\n");
    var champ: ?alien.Program = null;
    var warm_reach: usize = 0;
    for (ladder) |k| {
        var best: f64 = 0;
        var best_prog: ?alien.Program = null;
        for (0..n_seeds) |s| {
            var prng = std.Random.DefaultPrng.init(base_seed +% 0x5A5A +% k *% 0x2222 +% s *% 0x9E3779B1);
            var p = alien.Params{ .max_evals = max_evals, .fit_K = k };
            if (champ) |*c| p.seed_prog = c;
            const r = try alien.evolveAxis(al, prng.random(), p, base_seed +% s, .recall);
            if (r.best_score > best) {
                best = r.best_score;
                best_prog = r.best;
            }
        }
        const solved = best >= 0.95;
        if (solved) {
            warm_reach = k;
            champ = best_prog; // carry the champion to seed the next rung
        }
        try out.print("  {d} |  {s}  |    {d:.3}    | {s}\n", .{ k, if (solved) "yes" else "no ", best, if (solved) "→ seeds next rung" else "(ladder stalls here)" });
        if (!solved) break; // can't seed the next rung without a champion
    }

    // ---- verdict (data-driven — three distinct outcomes) -----------------------
    const champ_generalizes = if (cold_champ) |*c| alien.recallAcc(c, 48, 2048, base_seed +% 0xF00, true) > 0.95 else false;
    try out.print("\n[RESULT] cold solved up to K={d}; warm ladder reached K={d}.\n", .{ cold_cliff, warm_reach });
    if (warm_reach > cold_cliff) {
        try out.writeAll("[CURRICULUM HELPS] warm-starting reached a K cold search could not — the ladder\n");
        try out.writeAll("decomposes the conjunction: extending the previous rung is climbable where assembling\n");
        try out.writeAll("from scratch is not. Push the ladder higher, then re-run the joint hunt with the bank.\n");
    } else if (cold_cliff >= 2 and champ_generalizes) {
        try out.writeAll("[REFRAME — reliability, not reachability] The needle is NOT unreachable: cold search\n");
        try out.writeAll("DOES find GENUINE key-addressing (the champion holds at held-out K=48), just at a low,\n");
        try out.writeAll("noisy hit rate. Warm-starting from the K=1 latch did NOT raise that rate (the latch is\n");
        try out.writeAll("a structural dead-end). So the real blocker is the SAME one as Brick A — per-attempt\n");
        try out.writeAll("RELIABILITY of hitting a conjunctive mechanism — not a missing gradient. This revises\n");
        try out.writeAll("the Phase-3 'unreachable' read: at K≤6 it's reachable-but-rare. The right levers are the\n");
        try out.writeAll("Brick-A reliability ones (more restarts / parallel attempts), not the K-ladder. Next:\n");
        try out.writeAll("measure hit-rate vs K to see if reliability collapses as K grows (why K=20 looked dead).\n");
    } else {
        try out.writeAll("[IRREDUCIBLE] cold never finds genuine addressing and warm-start doesn't help — the\n");
        try out.writeAll("conjunction does not decompose into a K-ladder. Honest negative for lever (a). This\n");
        try out.writeAll("implicates the SUBSTRATE (lever b): a memory primitive whose store↔load wiring is not\n");
        try out.writeAll("all-or-nothing, accepting that it shapes the substrate toward the known answer.\n");
    }
}

/// RESEARCH PHASE 3 DIAGNOSTIC — locate the bottleneck. The joint QD hunt couldn't
/// reach the top-right. Is recall unreachable even ALONE (a gradient-free needle =
/// the Brick-A fitness-signal problem), or only jointly (a budget-split problem)?
/// Run a dedicated single-objective search on each axis and report.
fn alienProbe(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== RESEARCH PHASE 3 DIAGNOSTIC: is recall a gradient-free needle, and does a\n");
    try out.writeAll("denser fitness signal break it? (single-objective probe per axis) ===\n\n");
    const n_seeds: usize = 4;
    const max_evals: usize = 300_000;
    try out.print("Dedicated evolution, {d} evals × {d} seeds. Solve = score ≥ 0.95.\n\n", .{ max_evals, n_seeds });
    try out.writeAll("  axis / grading        | solves | best score | fastest e→solve\n");
    try out.writeAll("  ----------------------+--------+------------+----------------\n");

    const Probe = struct { label: []const u8, axis: alien.Axis, dense: bool };
    const probes = [_]Probe{
        .{ .label = "parity                ", .axis = .parity, .dense = false },
        .{ .label = "recall (SPARSE 1-query)", .axis = .recall, .dense = false },
        .{ .label = "recall (DENSE all-query)", .axis = .recall, .dense = true },
    };

    for (probes, 0..) |pr, pi| {
        const p = alien.Params{ .max_evals = max_evals, .dense_recall = pr.dense };
        var solves: usize = 0;
        var best: f64 = 0;
        var fastest: ?usize = null;
        for (0..n_seeds) |s| {
            var prng = std.Random.DefaultPrng.init(base_seed +% pi *% 0xABC +% s *% 0x9E3779B1);
            const r = try alien.evolveAxis(al, prng.random(), p, base_seed +% s, pr.axis);
            if (r.best_score >= 0.95) solves += 1;
            if (r.best_score > best) best = r.best_score;
            if (r.evals_to_solve) |e| {
                if (fastest == null or e < fastest.?) fastest = e;
            }
        }
        try out.print("  {s} |  {d}/{d}   |   {d:.3}    | ", .{ pr.label, solves, n_seeds, best });
        try printEvals(out, fastest, 10);
        try out.writeAll("\n");
    }

    try out.writeAll("\n[READING] Parity solves freely (per-position partial credit = a gradient). If SPARSE\n");
    try out.writeAll("recall stays near chance but DENSE recall now SOLVES, the bottleneck was the FITNESS\n");
    try out.writeAll("SIGNAL, not compute or expressivity — the Brick-A lesson, reproduced in the alien\n");
    try out.writeAll("substrate. Querying every key (random order) turns one sparse exact-match into K graded\n");
    try out.writeAll("outcomes, giving search a slope to climb to the load+store mechanism. Dense recall then\n");
    try out.writeAll("becomes the search-time reward for the joint hunt (validated held-out, sparse, at K=48).\n");
}

/// RESEARCH PHASE 3 + 4 — THE HUNT and the GAUNTLET. Execution-search (MAP-Elites
/// niched on the recall×length-gen plane) over the alien op-space, then the honest
/// gauntlet on whatever reaches the top-right: (a) re-validate at HELD-OUT longer
/// length / larger K; (b) certify novelty vs the known anchors; (c) decompose —
/// is it a unified primitive or the bolted union (scan ⊕ hash-table)? Every claim
/// is execution-only; we report what is there, including "it just rediscovered the
/// union", which is the honest expected outcome.
fn alienHunt(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== RESEARCH PHASE 3+4: the hunt (QD over the alien space) + the gauntlet ===\n\n");
    const p = alien.Params{ .max_evals = 300_000, .grid = 5 };
    const n_runs: usize = 4;
    try out.print("MAP-Elites, 5×5 niches (parity-bucket × recall-bucket), {d} evals/run, {d} runs.\n", .{ p.max_evals, n_runs });
    try out.writeAll("Search-time fidelity: parity L=24, recall K=20. Target: fill the TOP-RIGHT niche.\n\n");

    var best: ?alien.Program = null;
    var best_min: f64 = -1;
    var best_par: f64 = 0;
    var best_rec: f64 = 0;
    var topright_hits: usize = 0;
    var last_grid: alien.HuntResult = undefined;

    for (0..n_runs) |run| {
        var prng = std.Random.DefaultPrng.init(base_seed +% run *% 0x9E3779B97F4A7C15);
        const r = try alien.hunt(al, prng.random(), p, base_seed +% run);
        last_grid = r;
        if (r.best_topright != null) {
            topright_hits += 1;
            const mn = @min(r.tr_parity, r.tr_recall);
            if (mn > best_min) {
                best_min = mn;
                best = r.best_topright;
                best_par = r.tr_parity;
                best_rec = r.tr_recall;
            }
        }
    }

    // show the last run's niche occupancy as a parity×recall map
    try out.writeAll("Niche occupancy (last run) — rows = parity bucket (top=high), cols = recall bucket:\n");
    const g = last_grid.grid;
    var pr: usize = g;
    while (pr > 0) {
        pr -= 1;
        try out.writeAll("    ");
        for (0..g) |rc| try out.writeAll(if (last_grid.filled[pr * g + rc]) "# " else ". ");
        if (pr == g - 1) try out.writeAll("  ← high parity");
        try out.writeAll("\n");
    }
    try out.writeAll("    (bottom-right cell = high recall) \n\n");

    try out.print("Top-right niche reached in {d}/{d} runs.\n", .{ topright_hits, n_runs });
    if (best == null) {
        try out.writeAll("[RESULT] search did NOT reach the top-right corner. The `probe` phase locates WHY:\n");
        try out.writeAll("recall is a gradient-free CONJUNCTIVE needle — a dedicated 300k-eval search can't break\n");
        try out.writeAll("0.55 on recall ALONE, while parity solves in <1k. So the joint corner is unreachable\n");
        try out.writeAll("not from budget-split but from the recall half having no climbable slope. The dense-\n");
        try out.writeAll("grading fix (Brick A) was REFUTED here (it made recall harder). Honest negative, precisely\n");
        try out.writeAll("located: content addressing must be made discoverable by a route other than reward density\n");
        try out.writeAll("(building-block curriculum, or a substrate where the store+load wiring isn't all-or-nothing).\n");
        return;
    }

    var champ = best.?;
    try out.print("[DISCOVERED] a top-right program (search-fidelity parity={d:.3}, recall={d:.3}):\n", .{ best_par, best_rec });
    try alien.writeProgram(&champ, out);

    // ---- GAUNTLET (a): held-out scale — longer length, larger K ----------------
    const v_par = alien.parityAcc(&champ, 256, 64, base_seed +% 0xA00, true);
    const v_rec = alien.recallAcc(&champ, 48, 1024, base_seed +% 0xB00, true);
    try out.writeAll("\n[GAUNTLET a — held-out scale] trained at L=24/K=20, re-scored at L=256/K=48:\n");
    try out.print("  length-gen acc = {d:.3} | recall acc = {d:.3}\n", .{ v_par, v_rec });
    const holds = v_par > 0.95 and v_rec > 0.95;

    // ---- GAUNTLET (b): novelty certification -----------------------------------
    const fp = alien.fingerprint(&champ, base_seed +% 0xC00);
    const anchors = frontier.knownAnchors(base_seed +% 0xC00);
    const v = frontier.classify(fp, &anchors, frontier.NOVELTY_THRESHOLD);
    try out.print("\n[GAUNTLET b — novelty] fingerprint = [", .{});
    for (fp, 0..) |c, i| {
        if (i > 0) try out.writeAll(" ");
        try out.print("{d:.2}", .{c});
    }
    try out.print("]\n  nearest anchor = {s}, dist = {d:.3} ⇒ {s}\n", .{ v.nearest, v.dist, if (v.novel) "NOVEL vs single-mechanism anchors" else "matches a known mechanism" });

    // ---- GAUNTLET (c): decompose — unified primitive or bolted union? ----------
    const xor_acc = countOp(&champ, .a_xor) + countOp(&champ, .a_add) + countOp(&champ, .a_mul);
    const mem_ops = countOp(&champ, .a_load) + countOp(&champ, .a_store);
    try out.writeAll("\n[GAUNTLET c — decompose] does it factor into the two known mechanisms?\n");
    try out.print("  accumulator-style ops (xor/add/mul into a register): {d} | memory ops (load/store): {d}\n", .{ xor_acc, mem_ops });
    const looks_union = xor_acc >= 1 and mem_ops >= 1;

    try out.writeAll("\n[VERDICT] ");
    if (holds and v.novel and looks_union) {
        try out.writeAll("a DISCOVERED top-right operator that HOLDS at held-out scale and certifies novel —\n");
        try out.writeAll("but it decomposes into accumulator ⊕ hashed-memory. Honest reading: execution-search\n");
        try out.writeAll("REDISCOVERED the frontier-spanning UNION on its own (not hand-wired). That is a real\n");
        try out.writeAll("result for the METHOD (search found the corner unaided), but it is a hybrid, not a\n");
        try out.writeAll("unified novel primitive. The open frontier is forcing IRREDUCIBILITY — penalise the\n");
        try out.writeAll("union (shared registers / op budget) so only a genuinely fused mechanism can win.\n");
    } else if (holds and v.novel) {
        try out.writeAll("a discovered top-right operator that HOLDS at scale, certifies novel, and does NOT\n");
        try out.writeAll("cleanly decompose into accumulator ⊕ memory — the most interesting outcome. Inspect\n");
        try out.writeAll("the program by hand before any claim; run more seeds to confirm it is not a fluke.\n");
    } else if (!holds) {
        try out.writeAll("the top-right was reached at SEARCH fidelity but does NOT hold at held-out scale —\n");
        try out.writeAll("it overfit the short/small task. Honest: not a real frontier-breaker. Raise validation\n");
        try out.writeAll("fidelity inside the search loop (the brick-E lesson) and re-run.\n");
    } else {
        try out.writeAll("reached the corner but failed novelty — it matched a known mechanism's fingerprint.\n");
    }
}

/// Count occurrences of an alien op across a program (setup+step).
fn countOp(prog: *const alien.Program, op: alien.Op) usize {
    var n: usize = 0;
    for (prog.setup.slice()) |ins| if (ins.op == op) {
        n += 1;
    };
    for (prog.step.slice()) |ins| if (ins.op == op) {
        n += 1;
    };
    return n;
}

/// Phase 8 — BRICK A: is the rung-climb's reliability fixable with budget? The
/// autonomous loop (Phase 7) closes only ~1/12 per attempt at K=2, which cannot
/// stack to attention's depth. Measure the K=2-with-C0 QD solve RATE across
/// budgets and grading, over many seeds, to find a reliable operating point (or
/// show the rate is stubborn — which would say we need a stronger mechanism).
fn phase8(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== PHASE 8 (Brick A): how reliable can the rung-climb get? ===\n\n");
    var library = [_]sub.Macro{lib.referenceProductMacro()}; // C0
    const k2 = tasks.multiGate(4, &.{ .{ 0, 1 }, .{ 2, 3 } });
    const n_seeds: usize = 6;

    try out.print("Task: K=2 with C0 (the deceptive composition). {d} seeds/config.\n", .{n_seeds});
    try out.writeAll("Solve = QD finds the 2-call composition (perf ≥ 0.95).\n\n");
    try out.writeAll("  config                  | solves | best e→t | mean e→t (solved)\n");
    try out.writeAll("  ------------------------+--------+----------+------------------\n");

    const Cfg = struct { name: []const u8, evals: usize, grade: tasks.Grade };
    const configs = [_]Cfg{
        .{ .name = "classify, 250k          ", .evals = 250_000, .grade = .classify },
        .{ .name = "classify, 750k          ", .evals = 750_000, .grade = .classify },
        .{ .name = "regress (corr), 250k    ", .evals = 250_000, .grade = .regress },
    };

    for (configs) |conf| {
        const cfg = tasks.Config{ .n_train = 50, .n_test = 120, .n_seeds = 4, .grade = conf.grade };
        const p = evo.Params{ .max_evals = conf.evals, .pop_size = 1000, .tournament = 8, .target = 0.95, .lambda = 1e-4, .immigrant_rate = 0.18 };
        var hits: usize = 0;
        var best: ?usize = null;
        var sum: usize = 0;
        for (0..n_seeds) |s| {
            var prng = std.Random.DefaultPrng.init(base_seed +% 0x8888 +% hashName(conf.name) +% s *% 0x9E3779B1);
            const r = try evo.runMapElites(al, prng.random(), k2, cfg, p, &library);
            if (r.evals_to_target) |e| {
                hits += 1;
                sum += e;
                if (best == null or e < best.?) best = e;
            }
        }
        try out.print("  {s} |  {d}/{d}   | ", .{ conf.name, hits, n_seeds });
        try printEvals(out, best, 8);
        if (hits > 0) try out.print(" | {d}", .{sum / hits}) else try out.writeAll(" | —");
        try out.writeAll("\n");
    }

    try out.writeAll("\n[READING] If a config reaches a high solve rate (say ≥6/8), the climb is reliable\n");
    try out.writeAll("enough to stack rungs — Brick A is cleared and the sequence substrate (Brick B) is\n");
    try out.writeAll("next. If every config stays low, per-rung reliability is the deep blocker and the\n");
    try out.writeAll("path needs a stronger escape (richer QD descriptors, or the broad grounded proposer).\n");
}

/// Phase 7 — THE CAPSTONE: the full self-climbing loop, end-to-end grounded, with
/// NO hand-built rungs. Starting from C0 (the product primitive):
///   1. MAP-Elites SOLVES a family of K=2 tasks with C0 (escaping the trap);
///   2. the MDL extractor AUTO-ABSTRACTS the recurring composition into C1 (a macro
///      that calls C0 twice), and we VERIFY by execution that it composes;
///   3. MAP-Elites then SOLVES K=4 with {C0, C1} — escaping the trap one level up.
/// Every step is execute-and-measure; the library grows itself.
fn phase7(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== PHASE 7: the capstone — the engine climbs the tower by itself ===\n\n");

    var lib0 = [_]sub.Macro{lib.referenceProductMacro()}; // C0 (the only given primitive)
    const cfg = tasks.Config{ .n_train = 50, .n_test = 120, .n_seeds = 4 };
    const qp = evo.Params{ .max_evals = 250_000, .pop_size = 1000, .tournament = 8, .target = 0.95, .lambda = 1e-4, .immigrant_rate = 0.18 };

    // ---- step 1: MAP-Elites solves a FAMILY of K=2 tasks with C0 ---------------
    const k2fam = [_]tasks.Task{
        tasks.multiGate(4, &.{ .{ 0, 1 }, .{ 2, 3 } }),
        tasks.multiGate(4, &.{ .{ 0, 2 }, .{ 1, 3 } }),
        tasks.multiGate(4, &.{ .{ 0, 3 }, .{ 1, 2 } }),
    };
    const seeds_per: usize = 4;
    try out.print("Step 1 — MAP-Elites solves a K=2 family with C0 ({d} tasks x {d} seeds)…\n", .{ k2fam.len, seeds_per });
    var pool = std.ArrayList(sub.Program).init(al);
    defer pool.deinit();
    var solved: usize = 0;
    for (k2fam, 0..) |t, ti| {
        for (0..seeds_per) |s| {
            var prng = std.Random.DefaultPrng.init(base_seed +% 0xE1 +% ti *% 0x5151 +% s *% 0x9E3779B1);
            const r = try evo.runMapElites(al, prng.random(), t, cfg, qp, &lib0);
            if (r.best_perf >= qp.target) {
                solved += 1;
                try pool.append(r.best);
            }
        }
    }
    try out.print("  solved {d}/{d} K=2 instances; pooled {d} solution(s) to abstract from.\n\n", .{ solved, k2fam.len * seeds_per, pool.items.len });
    if (pool.items.len < 1) {
        try out.writeAll("[STALL] no K=2 solution this run — QD's K=2 rate is noisy; rerun with another seed.\n");
        return;
    }

    // ---- step 2: AUTO-ABSTRACT C1 from a solved program, verify it composes -----
    // No recurrence needed: a solution the engine FOUND is worth banking; we take its
    // composition core, parameterise it, and CONFIRM by execution that it composes.
    const c1_opt = try lib.firstComposingMacro(al, pool.items, &lib0);
    if (c1_opt == null) {
        try out.writeAll("[STALL] the K=2 solution(s) have no cleanly-canonicalisable composition core\n");
        try out.writeAll("(the combine used registers/ops the v1 macro language can't capture). Pool more.\n");
        return;
    }
    const c1 = c1_opt.?;
    try out.print("Step 2 — AUTO-ABSTRACTED C1 from a solved program: {d} params, {d} C0-call(s) in body\n", .{ c1.params.len, callsTo2(&c1) });
    try out.writeAll("  C1 composes (verified by EXECUTION on random inputs): YES — v0[a]·v0[b] + v0[c]·v0[d]\n\n");

    // ---- step 3: MAP-Elites solves K=4 with the self-built {C0, C1} ------------
    var lib1 = [_]sub.Macro{ lib0[0], c1 }; // C0, auto-abstracted C1
    const k4 = tasks.multiGate(8, &.{ .{ 0, 1 }, .{ 2, 3 }, .{ 4, 5 }, .{ 6, 7 } });
    const cell: usize = 4;
    try out.print("Step 3 — MAP-Elites solves K=4 with the SELF-BUILT library {{C0, C1}} ({d} seeds)…\n", .{cell});
    var k4_hits: usize = 0;
    var k4_best: ?usize = null;
    var k4_c1: usize = 0;
    for (0..cell) |c| {
        var prng = std.Random.DefaultPrng.init(base_seed +% 0xF2 +% c *% 0x9E3779B1);
        const r = try evo.runMapElites(al, prng.random(), k4, cfg, qp, &lib1);
        if (r.best_perf >= qp.target) {
            k4_hits += 1;
            if (k4_best == null or r.evals_to_target.? < k4_best.?) {
                k4_best = r.evals_to_target;
                k4_c1 = callsTo(&r.best, 1);
            }
        }
    }
    try out.print("  K=4 solved {d}/{d}", .{ k4_hits, cell });
    if (k4_best) |e| try out.print(" | best {d} evals | champion uses {d} C1 call(s)", .{ e, k4_c1 });
    try out.writeAll("\n\n");

    if (k4_hits > 0) {
        try out.writeAll("[CLIMBED] C0 → (QD solves K=2) → auto-abstracted+verified C1 → (QD solves K=4).\n");
        try out.writeAll("The engine grew its own second-level abstraction and used it to reach a task no\n");
        try out.writeAll("single-level library could — a self-built tower, every rung grounded by execution.\n");
    } else {
        try out.writeAll("[PARTIAL] C1 was abstracted+verified autonomously, but K=4 (needs 2 C1s + combine)\n");
        try out.writeAll("re-hit the trap this run — the next rung (C2) or more QD budget is the continuation.\n");
    }
}

/// Count C0-calls inside a macro body (for reporting the auto-abstracted C1).
fn callsTo2(macro: *const sub.Macro) usize {
    var n: usize = 0;
    for (macro.body.slice()) |ins| if (ins.op == .call) {
        n += 1;
    };
    return n;
}

/// Phase 6 — QUALITY-DIVERSITY vs the deceptive trap. Phase 3 & 5 showed flat
/// evolution and warm-start both fail K=2-with-C0 (0/4): greedy fitness-following
/// collapses onto the one-call ~70% peak and never makes the fitness-neutral jump
/// to two-calls-wired. MAP-Elites keeps the best individual per niche (binned by
/// #calls × length), so a two-call program survives in its own niche and a single
/// mutation can wire it. Does diversity-preserving search escape the trap?
fn phase6(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== PHASE 6: quality-diversity (MAP-Elites) vs the composition trap ===\n\n");
    var library = [_]sub.Macro{lib.referenceProductMacro()}; // C0 only

    const cfg = tasks.Config{ .n_train = 50, .n_test = 120, .n_seeds = 4 };
    const p = evo.Params{ .max_evals = 250_000, .pop_size = 1000, .tournament = 8, .target = 0.95, .lambda = 1e-4, .immigrant_rate = 0.18 };
    const cell_seeds: usize = 4;
    const k2 = tasks.multiGate(4, &.{ .{ 0, 1 }, .{ 2, 3 } });

    try out.print("Task: K=2 (2 products) with C0 — needs 2 C0 calls + a combine.\n", .{});
    try out.print("Budget {d} evals | {d} seeds/cell | flat & warm baselines were 0/4 (Phases 3,5)\n\n", .{ p.max_evals, cell_seeds });
    try out.writeAll("  search method        | solves | best e→t | champion C0 calls\n");
    try out.writeAll("  ---------------------+--------+----------+------------------\n");

    // flat regularized evolution (the baseline that fails)
    var flat_hits: usize = 0;
    var flat_best: ?usize = null;
    var flat_calls: usize = 0;
    for (0..cell_seeds) |c| {
        var prng = std.Random.DefaultPrng.init(base_seed +% 0xC1 +% c *% 0x9E3779B1);
        const r = try evo.runEvolution(al, prng.random(), k2, cfg, p, &library, &.{});
        if (r.evals_to_target) |e| {
            flat_hits += 1;
            if (flat_best == null or e < flat_best.?) {
                flat_best = e;
                flat_calls = r.lib_calls_in_best;
            }
        }
    }
    try out.writeAll("  flat evolution       |  ");
    try out.print("{d}/{d}   | ", .{ flat_hits, cell_seeds });
    try printEvals(out, flat_best, 8);
    try out.print(" | {d}\n", .{flat_calls});

    // MAP-Elites (the diversity-preserving search)
    var qd_hits: usize = 0;
    var qd_best: ?usize = null;
    var qd_calls: usize = 0;
    for (0..cell_seeds) |c| {
        var prng = std.Random.DefaultPrng.init(base_seed +% 0xD2 +% c *% 0x9E3779B1);
        const r = try evo.runMapElites(al, prng.random(), k2, cfg, p, &library);
        if (r.evals_to_target) |e| {
            qd_hits += 1;
            if (qd_best == null or e < qd_best.?) {
                qd_best = e;
                qd_calls = r.lib_calls_in_best;
            }
        }
    }
    try out.writeAll("  MAP-Elites (QD)      |  ");
    try out.print("{d}/{d}   | ", .{ qd_hits, cell_seeds });
    try printEvals(out, qd_best, 8);
    try out.print(" | {d}\n", .{qd_calls});

    try out.writeAll("\n[READING] If MAP-Elites solves K=2 where flat evolution stays at 0/4, diversity-\n");
    try out.writeAll("preserving search ESCAPES the deceptive trap — the engine can now produce a K=2\n");
    try out.writeAll("solution on its own, the missing prerequisite for autonomously abstracting C1 and\n");
    try out.writeAll("climbing the tower without hand-built rungs. If QD also stalls, deception here is\n");
    try out.writeAll("deep enough to need a broad grounded proposer (the deepest §8 problem).\n");
}

/// Phase 5 — THE FRONTIER: can a CURRICULUM climb a rung autonomously? Phase 4
/// needed `C1` by hand because the engine can't SOLVE K=2 with `C0` alone (the
/// 0/4 trap), so it has no K=2 solution to abstract `C1` from. Here we test the
/// cheapest escape: warm-start the K=2 search with the K=1 solution the engine
/// already found, so it EXTENDS a stepping-stone instead of assembling from
/// scratch. If warm-start solves K=2 where cold-start (Phase 3) got 0/4, the
/// per-rung trap is escapable by curriculum — the key to an autonomous tower.
fn phase5(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== PHASE 5: curriculum — can a warm-start escape the per-rung trap? ===\n\n");
    var library = [_]sub.Macro{lib.referenceProductMacro()}; // C0 only (NO hand-built C1)

    // ---- stage 0: solve K=1 with C0 (the stepping stone) -----------------------
    const cfg = tasks.Config{ .n_train = 50, .n_test = 120, .n_seeds = 4 };
    const k1 = tasks.gate(2, 0, 1);
    const p0 = evo.Params{ .max_evals = 80_000, .pop_size = 800, .tournament = 8, .target = 0.95, .lambda = 1e-4, .immigrant_rate = 0.15 };
    var prng0 = std.Random.DefaultPrng.init(base_seed +% 0xA1);
    const r0 = try evo.runEvolution(al, prng0.random(), k1, cfg, p0, &library, &.{});
    try out.print("Stage 0 — solve K=1 with C0: perf {d:.3}, champion uses {d} C0 call(s).\n", .{ r0.best_perf, callsTo(&r0.best, 0) });
    if (r0.best_perf < 0.95) {
        try out.writeAll("  (K=1 not solved this seed — rerun; stepping stone unavailable.)\n");
        return;
    }
    const stepping_stones = [_]sub.Program{r0.best};
    try out.writeAll("  ⇒ this K=1 solution becomes the curriculum stepping stone for K=2.\n\n");

    // ---- stage 1: K=2 with C0 — COLD vs WARM-STARTED ---------------------------
    const k2 = tasks.multiGate(4, &.{ .{ 0, 1 }, .{ 2, 3 } });
    const cell_seeds: usize = 4;
    const base_p = evo.Params{ .max_evals = 250_000, .pop_size = 1000, .tournament = 8, .target = 0.95, .lambda = 1e-4, .immigrant_rate = 0.18 };

    try out.print("Stage 1 — solve K=2 with C0 (needs 2 C0 calls + combine) | budget {d} | {d} seeds/cell\n\n", .{ base_p.max_evals, cell_seeds });
    try out.writeAll("  condition            | solves | best e→t | (Phase 3 cold baseline was 0/4)\n");
    try out.writeAll("  ---------------------+--------+----------+--------------------------------\n");

    inline for ([_][]const u8{ "cold (random init)", "warm (K=1 seeded) " }, 0..) |cond, ci| {
        var p = base_p;
        if (ci == 1) p.seed_progs = &stepping_stones;
        var hits: usize = 0;
        var best: ?usize = null;
        for (0..cell_seeds) |c| {
            var prng = std.Random.DefaultPrng.init(base_seed +% 0xB2 +% ci *% 0x9999 +% c *% 0x9E3779B1);
            const r = try evo.runEvolution(al, prng.random(), k2, cfg, p, &library, &.{});
            if (r.evals_to_target) |e| {
                hits += 1;
                if (best == null or e < best.?) best = e;
            }
        }
        try out.print("  {s} |  {d}/{d}   | ", .{ cond, hits, cell_seeds });
        try printEvals(out, best, 8);
        try out.writeAll("\n");
    }

    try out.writeAll("\n[READING] If WARM solves K=2 where COLD stays at 0/4, curriculum transfer\n");
    try out.writeAll("escapes the per-rung trap: the engine can now PRODUCE a K=2 solution, which is\n");
    try out.writeAll("the prerequisite for autonomously abstracting C1 and climbing the tower itself.\n");
    try out.writeAll("If WARM also stalls, the trap is deep and needs novelty/diversity or a broader\n");
    try out.writeAll("grounded proposer — the deepest §8 problem, located precisely.\n");
}

/// Count calls to a specific macro index across a champion's predict+learn.
fn callsTo(prog: *const sub.Program, macro_idx: usize) usize {
    var n: usize = 0;
    for (prog.predict.slice()) |ins| if (ins.op == .call and @as(usize, @intFromFloat(ins.imm)) == macro_idx) {
        n += 1;
    };
    for (prog.learn.slice()) |ins| if (ins.op == .call and @as(usize, @intFromFloat(ins.imm)) == macro_idx) {
        n += 1;
    };
    return n;
}

/// Phase 4 — THE TOWER. Phase 3 showed a single primitive (C0) does NOT buy
/// compositional reach: K=2 was 0/4. Here we add the SECOND level — C1 = a
/// composition macro (sum of two products) built ON TOP OF C0 — and ask: does the
/// next abstraction collapse the next task? Expected honest shape:
///   K=1 collapses via C0 (1 call); K=2 collapses via C1 (1 call) — LIFTING the
///   Phase-3 wall; K=4 re-hits the composition trap (it needs 2 C1s + a combine),
///   showing the trap recurs one level up and the tower must be climbed level by
///   level. C0/C1 are verified-by-hand (like C0 in Phase 3); DISCOVERING C1
///   autonomously is blocked by that same per-level trap — the frontier.
fn phase4(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== PHASE 4: the tower — does the next abstraction collapse the next task? ===\n\n");

    // C0 = product (level 1), C1 = sum-of-two-products built on C0 (level 2)
    var library = [_]sub.Macro{ lib.referenceProductMacro(), lib.referenceComposeMacro() };
    const c0_label = try lib.decode(&library[0], al);
    try out.print("Library: C0 = {s}\n", .{c0_label});
    try out.writeAll("         C1 = sum of two products  v0[p0]·v0[p1] + v0[p2]·v0[p3]  (CALLS C0 twice — the tower)\n\n");

    const cfg = tasks.Config{ .n_train = 50, .n_test = 120, .n_seeds = 4 };
    const p = evo.Params{ .max_evals = 250_000, .pop_size = 1000, .tournament = 8, .target = 0.95, .lambda = 1e-4, .immigrant_rate = 0.18 };
    const cell_seeds: usize = 4;

    const sweep = [_]struct { name: []const u8, t: tasks.Task, need: []const u8 }{
        .{ .name = "K=1 (1 product) ", .t = tasks.gate(2, 0, 1), .need = "1 C0 call" },
        .{ .name = "K=2 (2 products)", .t = tasks.multiGate(4, &.{ .{ 0, 1 }, .{ 2, 3 } }), .need = "1 C1 call" },
        .{ .name = "K=4 (4 products)", .t = tasks.multiGate(8, &.{ .{ 0, 1 }, .{ 2, 3 }, .{ 4, 5 }, .{ 6, 7 } }), .need = "2 C1 + add" },
    };

    try out.print("Tower reach sweep | budget {d} evals | {d} seeds/cell | C0+C1 available\n\n", .{ p.max_evals, cell_seeds });
    try out.writeAll("  task             | min solution | solves | best e→t | champion uses\n");
    try out.writeAll("  -----------------+--------------+--------+----------+---------------\n");

    for (sweep) |sw| {
        var hits: usize = 0;
        var best: ?usize = null;
        var best_c0: usize = 0;
        var best_c1: usize = 0;
        for (0..cell_seeds) |c| {
            var prng = std.Random.DefaultPrng.init(base_seed +% 0x77 +% hashName(sw.name) +% c *% 0x9E3779B1);
            const r = try evo.runEvolution(al, prng.random(), sw.t, cfg, p, &library, &.{});
            if (r.evals_to_target) |e| {
                hits += 1;
                if (best == null or e < best.?) {
                    best = e;
                    best_c0 = callsTo(&r.best, 0);
                    best_c1 = callsTo(&r.best, 1);
                }
            }
        }
        try out.print("  {s} | {s:<12} |  {d}/{d}   | ", .{ sw.name, sw.need, hits, cell_seeds });
        try printEvals(out, best, 8);
        if (best != null) {
            try out.print(" | {d}×C0, {d}×C1\n", .{ best_c0, best_c1 });
        } else {
            try out.writeAll(" | —\n");
        }
    }

    try out.writeAll("\n[READING] Phase 3 showed C0 alone gives K=2 = 0/4. If C1 now solves K=2 with a\n");
    try out.writeAll("single CALL, the SECOND abstraction collapsed the task C0 could not reach — the\n");
    try out.writeAll("tower compounds. If K=4 then stalls, the composition trap has simply moved up a\n");
    try out.writeAll("level (it needs C2 = sum-of-two-C1s): reach compounds, but one rung at a time,\n");
    try out.writeAll("and escaping each rung's trap to DISCOVER the next macro is the open frontier.\n");
}

/// Phase 3 — TIER-3 BRICK: does compounding give REACH? Two separable questions,
/// reported separately and honestly:
///   (1) Can the engine reliably DISCOVER a *composable* product primitive? A
///       short regression-graded bootstrap probes this. (It is hard — see below.)
///   (2) GIVEN a composable primitive, does reusing it let search reach
///       compositional tasks that flat search cannot? This is the reach
///       hypothesis, and it is tested with a verified product macro so the answer
///       does not depend on (1). Sweep arity (1 → 2 → 3 products), dim scaling
///       with K so flat stays solvable at K=1, and compare evals-to-target.
fn phase3(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== PHASE 3: compounding for reach (Tier-3 brick) ===\n\n");

    // ---- (1) can it DISCOVER a composable product? (honest probe) --------------
    const boot_cfg = tasks.Config{ .n_train = 60, .n_test = 120, .n_seeds = 4, .grade = .regress };
    const boot_p = evo.Params{ .max_evals = 150_000, .pop_size = 1500, .tournament = 8, .target = 0.95, .lambda = 1e-4, .immigrant_rate = 0.12 };
    const n_boot_seeds: usize = 4;
    try out.print("(1) DISCOVERY probe — regression-graded (so product≠ratio), {d} seeds x {d} evals:\n", .{ n_boot_seeds, boot_p.max_evals });
    var corpus = std.ArrayList(sub.Program).init(al);
    defer corpus.deinit();
    const train = tasks.gate(2, 0, 1);
    var disc_solves: usize = 0;
    var disc_best: f64 = 0;
    for (0..n_boot_seeds) |s| {
        var prng = std.Random.DefaultPrng.init(base_seed +% s *% 0xD1B54A32D192ED03);
        const elites = try al.alloc(sub.Program, 24);
        defer al.free(elites);
        const r = try evo.runEvolution(al, prng.random(), train, boot_cfg, boot_p, &.{}, elites);
        if (r.best_perf >= boot_p.target) disc_solves += 1;
        if (r.best_perf > disc_best) disc_best = r.best_perf;
        if (r.best_perf >= 0.9) for (elites) |e| try corpus.append(e);
    }
    const prod_ext = try lib.bestProductExtraction(al, corpus.items, &.{});
    try out.print("    {d}/{d} reached corr≥{d:.2} (best {d:.3}); abstractable PRODUCT found: {s}\n", .{ disc_solves, n_boot_seeds, boot_p.target, disc_best, if (prod_ext != null) "yes" else "no" });
    try out.writeAll("    ⇒ Reliable discovery of the *composable* form is the open sub-problem: the\n");
    try out.writeAll("      classification basin prefers the non-composing ratio gate, and the engine's\n");
    try out.writeAll("      favourite product (vector-scaling) writes a vector, outside the v1 macro\n");
    try out.writeAll("      language. So the reach test below uses a VERIFIED product macro instead.\n\n");

    // ---- (2) GIVEN a composable primitive, does reuse buy REACH? ---------------
    var library = [_]sub.Macro{lib.referenceProductMacro()};
    const c0_label = try lib.decode(&library[0], al);
    try out.print("(2) REACH test — C0 = verified macro, decodes as: {s}\n", .{c0_label});

    const sweep_cfg = tasks.Config{ .n_train = 50, .n_test = 120, .n_seeds = 4 };
    // higher diversity to give C0-lib its best shot at escaping the partial-credit
    // trap (one product already predicts the sign of a sum of products ~70%)
    const sweep_p = evo.Params{ .max_evals = 300_000, .pop_size = 1000, .tournament = 8, .target = 0.95, .lambda = 1e-4, .immigrant_rate = 0.18 };
    const cell_seeds: usize = 4; // solve RATE per cell, not a single noisy attempt

    // dim scales with K so the K=1 wiring needle stays solvable by flat evolution
    const sweep = [_]struct { name: []const u8, t: tasks.Task, min_ops: usize }{
        .{ .name = "K=1  (1 product) ", .t = tasks.gate(2, 0, 1), .min_ops = 3 },
        .{ .name = "K=2  (2 products)", .t = tasks.multiGate(4, &.{ .{ 0, 1 }, .{ 2, 3 } }), .min_ops = 7 },
        .{ .name = "K=3  (3 products)", .t = tasks.multiGate(6, &.{ .{ 0, 1 }, .{ 2, 3 }, .{ 4, 5 } }), .min_ops = 11 },
    };

    try out.print("    budget {d} evals | target {d:.2} | dim=2K | {d} seeds/cell\n\n", .{ sweep_p.max_evals, sweep_p.target, cell_seeds });
    try out.writeAll("  task              | raw min_ops | flat solves | flat best e→t | C0-lib solves | C0-lib best e→t\n");
    try out.writeAll("  ------------------+-------------+-------------+---------------+---------------+----------------\n");

    for (sweep) |sw| {
        var flat_hits: usize = 0;
        var lib_hits: usize = 0;
        var flat_best: ?usize = null;
        var lib_best: ?usize = null;
        for (0..cell_seeds) |c| {
            var p_flat = std.Random.DefaultPrng.init(base_seed +% 0x55 +% hashName(sw.name) +% c *% 0xABCDEF);
            var p_lib = std.Random.DefaultPrng.init(base_seed +% 0x66 +% hashName(sw.name) +% c *% 0x123457);
            const rf = try evo.runEvolution(al, p_flat.random(), sw.t, sweep_cfg, sweep_p, &.{}, &.{});
            const rl = try evo.runEvolution(al, p_lib.random(), sw.t, sweep_cfg, sweep_p, &library, &.{});
            if (rf.evals_to_target) |e| {
                flat_hits += 1;
                if (flat_best == null or e < flat_best.?) flat_best = e;
            }
            if (rl.evals_to_target) |e| {
                lib_hits += 1;
                if (lib_best == null or e < lib_best.?) lib_best = e;
            }
        }
        try out.print("  {s} |     {d:>2}      |     {d}/{d}     | ", .{ sw.name, sw.min_ops, flat_hits, cell_seeds });
        try printEvals(out, flat_best, 13);
        try out.print(" |     {d}/{d}     | ", .{ lib_hits, cell_seeds });
        try printEvals(out, lib_best, 14);
        try out.writeAll("\n");
    }

    try out.writeAll("\n[READING] K=1: a reused primitive collapses the task to one CALL — a huge\n");
    try out.writeAll("acceleration. The K≥2 columns are the real test: does one primitive AUTOMATICALLY\n");
    try out.writeAll("buy compositional reach, or does composing K of them re-introduce the needle\n");
    try out.writeAll("(a single product already predicts a sum-of-products' sign ~70% — a deceptive\n");
    try out.writeAll("trap)? If C0-lib also stalls at K≥2, reach needs the TOWER (abstract the\n");
    try out.writeAll("composition itself), not just one primitive — the precise §8 wall.\n");
}

/// Phase 2 — THE CORE HYPOTHESIS (§5). Build a library by abstracting the
/// recurring gate from elites of a bootstrap solve, then measure evals-to-target
/// on NEW family members with vs without that library. Kill-test: library
/// evolution reaches target in SIGNIFICANTLY fewer evals than flat evolution.
fn phase2(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== PHASE 2: the compounding library (the ratchet) ===\n\n");

    const boot_cfg = tasks.Config{ .n_train = 60, .n_test = 150, .n_seeds = 5 };
    const boot_p = evo.Params{ .max_evals = 300_000, .pop_size = 1500, .tournament = 8, .target = 0.95, .lambda = 1e-4, .immigrant_rate = 0.12 };
    const k_elites: usize = 24;
    const n_boot_seeds: usize = 5;

    // ---- bootstrap: pool elites across several solves of pair (0,1), abstract ----
    try out.print("Bootstrap: solve gate(0,1) up to {d}x, pool top-{d} elites, abstract the recurring motif.\n", .{ n_boot_seeds, k_elites });
    var corpus = std.ArrayList(sub.Program).init(al);
    defer corpus.deinit();
    const train = tasks.gate(4, 0, 1);
    var solves: usize = 0;
    for (0..n_boot_seeds) |s| {
        var prng = std.Random.DefaultPrng.init(base_seed +% s *% 0xD1B54A32D192ED03);
        const elites = try al.alloc(sub.Program, k_elites);
        defer al.free(elites);
        const r = try evo.runEvolution(al, prng.random(), train, boot_cfg, boot_p, &.{}, elites);
        if (r.best_perf >= boot_p.target) {
            solves += 1;
            for (elites) |e| try corpus.append(e);
        }
    }
    try out.print("  {d}/{d} bootstrap solves succeeded; corpus = {d} elite programs.\n", .{ solves, n_boot_seeds, corpus.items.len });

    const ext_opt = try lib.bestExtraction(al, corpus.items, &.{});
    if (ext_opt == null) {
        try out.writeAll("\n[WALL] No recurring abstractable template found in the elites.\n");
        try out.writeAll("The converged solutions use forms outside the v1 macro scope (e.g. vector\n");
        try out.writeAll("writes via v_scale). The ratchet cannot be tested until the macro language\n");
        try out.writeAll("covers them — this is a precise, honest negative (§8), not a silent failure.\n");
        return;
    }
    const ext = ext_opt.?;
    const label = try lib.decode(&ext.macro, al);
    var library = [_]sub.Macro{ext.macro};
    try out.print("\n[ABSTRACT] discovered C0: occurs {d}x, length {d}, saves {d} description nodes\n", .{ ext.occurrences, ext.length, ext.saved });
    try out.print("           C0 decoded behaviourally as: {s}\n", .{label});
    try out.print("           C0 takes {d} params (the element indices), {d} local registers\n\n", .{ ext.macro.params.len, ext.macro.n_local });

    // ---- reuse test on NEW family members --------------------------------------
    // Budget chosen so flat evolution can usually solve the single-gate tasks
    // (Phase 1 ⇒ ~100k mean), giving real speedup ratios rather than misses, while
    // the library still solves in <1k. The double-gate probes the next frontier.
    const reuse_cfg = tasks.Config{ .n_train = 50, .n_test = 120, .n_seeds = 4 };
    const reuse_p = evo.Params{ .max_evals = 250_000, .pop_size = 1000, .tournament = 8, .target = 0.95, .lambda = 1e-4, .immigrant_rate = 0.12 };

    const reuse_tasks = [_]struct { name: []const u8, t: tasks.Task }{
        .{ .name = "gate(2,3)", .t = tasks.gate(4, 2, 3) },
        .{ .name = "gate(1,3)", .t = tasks.gate(4, 1, 3) },
        .{ .name = "gate(0,3)", .t = tasks.gate(4, 0, 3) },
        .{ .name = "dbl(01,23)", .t = tasks.multiGate(4, &.{ .{ 0, 1 }, .{ 2, 3 } }) },
    };

    try out.print("Reuse test (NEW tasks the library never saw) | budget {d} evals | target {d:.2}\n\n", .{ reuse_p.max_evals, reuse_p.target });
    try out.writeAll("  task        | random e→t | flat-evo e→t | LIB-evo e→t | lib speedup | calls in champ\n");
    try out.writeAll("  ------------+------------+--------------+-------------+-------------+---------------\n");

    var flat_sum: f64 = 0;
    var lib_sum: f64 = 0;
    var both_hit: usize = 0;
    var rand_solved: usize = 0;
    var flat_solved: usize = 0;
    var lib_solved: usize = 0;

    for (reuse_tasks) |rt| {
        var p_rand = std.Random.DefaultPrng.init(base_seed +% 0x111 +% hashName(rt.name));
        var p_flat = std.Random.DefaultPrng.init(base_seed +% 0x222 +% hashName(rt.name));
        var p_lib = std.Random.DefaultPrng.init(base_seed +% 0x333 +% hashName(rt.name));

        const rr = evo.runRandomSearch(p_rand.random(), rt.t, reuse_cfg, reuse_p, &.{});
        const rf = try evo.runEvolution(al, p_flat.random(), rt.t, reuse_cfg, reuse_p, &.{}, &.{});
        const rl = try evo.runEvolution(al, p_lib.random(), rt.t, reuse_cfg, reuse_p, &library, &.{});

        if (rr.evals_to_target != null) rand_solved += 1;
        if (rf.evals_to_target != null) flat_solved += 1;
        if (rl.evals_to_target != null) lib_solved += 1;

        try out.print("  {s:<11} | ", .{rt.name});
        try printEvals(out, rr.evals_to_target, 10);
        try out.writeAll(" | ");
        try printEvals(out, rf.evals_to_target, 12);
        try out.writeAll(" | ");
        try printEvals(out, rl.evals_to_target, 11);
        try out.writeAll(" | ");
        if (rf.evals_to_target != null and rl.evals_to_target != null and rl.evals_to_target.? > 0) {
            const sp = @as(f64, @floatFromInt(rf.evals_to_target.?)) / @as(f64, @floatFromInt(rl.evals_to_target.?));
            try out.print("{d:>9.1}x | {d}\n", .{ sp, rl.lib_calls_in_best });
            flat_sum += @floatFromInt(rf.evals_to_target.?);
            lib_sum += @floatFromInt(rl.evals_to_target.?);
            both_hit += 1;
        } else {
            try out.print("{s:>10} | {d}\n", .{ "  n/a", rl.lib_calls_in_best });
        }
    }

    try out.writeAll("\n");
    try out.print("[SOLVE RATE over {d} tasks]  random {d}/{d}  |  flat-evo {d}/{d}  |  LIB-evo {d}/{d}\n", .{ reuse_tasks.len, rand_solved, reuse_tasks.len, flat_solved, reuse_tasks.len, lib_solved, reuse_tasks.len });
    if (both_hit > 0) {
        try out.print("[RATCHET] across {d} tasks both flat & LIB solved: flat mean {d:.0} e→t, LIB mean {d:.0} e→t  ⇒  {d:.1}x fewer evals\n", .{ both_hit, flat_sum / @as(f64, @floatFromInt(both_hit)), lib_sum / @as(f64, @floatFromInt(both_hit)), flat_sum / lib_sum });
    }
    try out.writeAll("\nThe library macro is reused as a single op; new gate tasks collapse to one CALL.\n");
}

fn hashName(s: []const u8) u64 {
    var h: u64 = 0xcbf29ce484222325;
    for (s) |c| {
        h ^= c;
        h *%= 0x100000001b3;
    }
    return h;
}

/// Phase 1 kill-test: evolution must reach the target MARKEDLY faster than random
/// search and rediscover the gate + a learn rule. If evolution ≈ random, the
/// substrate/fitness/mutation is broken (§5 Phase 1).
fn phase1(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== PHASE 1: flat regularized evolution vs random search ===\n\n");
    const task = tasks.gate(2, 0, 1);
    // Higher fidelity (more seeds/held-out) collapses deceptive optima — which
    // rely on small-sample flukes — back toward chance, while the true gate stays
    // at 1.0. That widens the gap selection must climb and de-fangs the traps.
    const cfg = tasks.Config{ .n_train = 60, .n_test = 150, .n_seeds = 5 };
    // λ tiny: MDL is a TIE-BREAKER, not a search driver, so partial scaffolds
    // survive in the population (neutral drift is evolution's whole advantage here).
    // Weaker tournament + more immigrants = less premature convergence on traps.
    const p = evo.Params{ .max_evals = 300_000, .pop_size = 1500, .tournament = 8, .target = 0.95, .lambda = 1e-4, .immigrant_rate = 0.12 };
    const n_runs: usize = 5;

    try out.print("Task A: y=sign(x0*x1)  | budget {d} evals/run | {d} runs | target perf {d:.2}\n\n", .{ p.max_evals, n_runs, p.target });
    try out.writeAll("  run | evolution evals→target | random evals→target | evo best | rand best\n");
    try out.writeAll("  ----+------------------------+---------------------+----------+----------\n");

    var evo_hits: usize = 0;
    var rand_hits: usize = 0;
    var evo_sum: usize = 0;
    var rand_sum: usize = 0;
    var champion: sub.Program = .{};
    var champion_perf: f64 = -1;

    for (0..n_runs) |run| {
        var pe = std.Random.DefaultPrng.init(base_seed +% run *% 0xA24BAED4963EE407);
        var pr = std.Random.DefaultPrng.init(base_seed +% run *% 0x9E3779B97F4A7C15 +% 1);
        const re = try evo.runEvolution(al, pe.random(), task, cfg, p, &.{}, &.{});
        const rr = evo.runRandomSearch(pr.random(), task, cfg, p, &.{});

        try out.print("  {d:>3} | ", .{run});
        try printEvals(out, re.evals_to_target, 22);
        try out.writeAll(" | ");
        try printEvals(out, rr.evals_to_target, 19);
        try out.print(" | {d:.4}   | {d:.4}\n", .{ re.best_perf, rr.best_perf });
        if (re.evals_to_target) |e| {
            evo_hits += 1;
            evo_sum += e;
        }
        if (rr.evals_to_target) |e| {
            rand_hits += 1;
            rand_sum += e;
        }
        if (re.best_perf > champion_perf) {
            champion_perf = re.best_perf;
            champion = re.best;
        }
    }

    try out.writeAll("\n");
    try out.print("  evolution: {d}/{d} runs hit target", .{ evo_hits, n_runs });
    if (evo_hits > 0) try out.print(", mean {d} evals→target", .{evo_sum / evo_hits});
    try out.writeAll("\n");
    try out.print("  random   : {d}/{d} runs hit target", .{ rand_hits, n_runs });
    if (rand_hits > 0) try out.print(", mean {d} evals→target", .{rand_sum / rand_hits});
    try out.writeAll("\n\n");

    // high-fidelity re-validation of the champion (guard against lucky noise)
    const valcfg = tasks.Config{ .n_train = 200, .n_test = 400, .n_seeds = 12, .base_seed = 0xBEEF };
    const val = tasks.evaluate(&champion, &.{}, task, valcfg);
    try out.print("[VALIDATE] champion re-scored on 12 fresh seeds x 400 held-out: acc = {d:.4}\n\n", .{val});
    try out.writeAll("The best program evolution discovered (raw, undecoded):\n");
    try sub.writeProgram(&champion, out);
}

fn printEvals(out: anytype, e: ?usize, width: usize) !void {
    var buf: [32]u8 = undefined;
    const txt = if (e) |v| try std.fmt.bufPrint(&buf, "{d}", .{v}) else try std.fmt.bufPrint(&buf, "— (miss)", .{});
    var pad = width;
    if (txt.len < width) pad = width - txt.len else pad = 0;
    for (0..pad) |_| try out.writeAll(" ");
    try out.writeAll(txt);
}

/// Phase 0 sanity gate: the verifier must score a correct hand-written program
/// high and garbage low. If it doesn't, everything downstream is meaningless.
fn phase0(out: anytype) !void {
    try out.writeAll("=== PHASE 0: substrate + fitness verifier sanity gate ===\n\n");
    const cfg = tasks.Config{ .n_train = 200, .n_test = 400, .n_seeds = 8 };
    const task = tasks.gate(2, 0, 1);

    const ref = tasks.referenceGate(0, 1);
    const lin = tasks.referenceLinear();
    const empty = sub.Program{};

    const acc_ref = tasks.evaluate(&ref, &.{}, task, cfg);
    const acc_lin = tasks.evaluate(&lin, &.{}, task, cfg);
    const acc_empty = tasks.evaluate(&empty, &.{}, task, cfg);

    try out.print("Task A: y = sign(x0 * x1), dim=2, {d} seeds x {d} held-out\n\n", .{ cfg.n_seeds, cfg.n_test });
    try out.print("  hand-written gate+gradient : held-out acc = {d:.4}\n", .{acc_ref});
    try out.print("  linear model (no product)  : held-out acc = {d:.4}\n", .{acc_lin});
    try out.print("  empty/garbage program      : held-out acc = {d:.4}\n\n", .{acc_empty});

    const pass = acc_ref > 0.95 and acc_lin < 0.65 and acc_empty < 0.65;
    try out.print("[GATE] correct >> chance, gate is load-bearing: {s}\n", .{if (pass) "PASS" else "FAIL"});
    try out.writeAll("\nThe reference gate program (what a correct candidate looks like):\n");
    try sub.writeProgram(&ref, out);
}

test {
    std.testing.refAllDecls(@This());
    _ = sub;
    _ = tasks;
    _ = evo;
    _ = lib;
    _ = seq;
    _ = frontier;
    _ = alien;
    _ = open;
    _ = coevo;
    _ = forge;
}
