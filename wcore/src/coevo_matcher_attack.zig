//! Round 2026-07-11 E6: red-team the COEVO-SIDE STATISTICAL MATCHER --
//! `inv_coevo.behaviorMatches` / `reducible()`: "a solver's behaviour equals a
//! composed stage-genome iff agreement >= 0.95 on 12 streams x 32 symbols, a
//! per-call seed". This is the instrument behind the Claim-C "85/86 breadth
//! corpus" headline (`claim_c_breadth.md`, `budget_scan.md`, INDEX.md): 16
//! seeds x §24-ladder deep solvers, fingerprint-certifier says "novel", this
//! matcher says "reducible" for 85/86 of them (the 86th resolves reducible at
//! depth 5 under `budgetscan`).
//!
//! Round 2026-07-10c red-teamed the SIBLING matcher (`inv_atomforge.reducibleLib`,
//! 8 streams x 28 symbols, chains of atom-Programs) and found it lies in the
//! FALSE-EQUAL direction: rare-pattern deviators and a "horizon bomb" (deviate
//! only past the sample window) fool it at 100% of seeds, and 8/189 = 4.2% of
//! the REAL production census verdicts were false-equals. That round explicitly
//! named this file's target -- the coevo-side 12x32 matcher -- as NOT-YET-
//! ATTACKED and "likely vulnerable to the same mechanics" (matcher_falsification.md
//! "What was NOT attacked").
//!
//! Prior coevo-side stress test (I54/I55, `swarm_i54_i55_behavior_matches.md`)
//! used only NATURALLY-OCCURRING near-misses (worst wrong-pair agreement 0.64,
//! "ample margin", 0 flips 32->256->4096 symbols) and NEVER constructed an
//! adversary or varied the matcher's own stream seed on production verdicts.
//! This round does both, mirroring `matcher_attack.zig`'s methodology exactly,
//! translated from "Program vs chain-of-Programs" to "Program vs Stage-genome".
//!
//! Attacks (see wcore/docs/research/coevo_matcher_falsification.md):
//!  A1 FALSE-EQUAL hunt      -- constructed rare-pattern deviators + a horizon
//!                              bomb (L=32 window) vs genome=[st_gxor]; a
//!                              random-Program background hunt against the
//!                              whole enumerated stage-genome space; and a
//!                              full audit of the REAL 85/86-corpus "reducible"
//!                              verdicts against their matched genome at high
//!                              resolution. Every false-equal carries a witness.
//!  A2 FALSE-DIFFERENT hunt  -- extensionally-equal syntactic variants of the
//!                              reference solvers, measured across many seeds.
//!  A3 SEED-FLIP             -- every "reducible" verdict in the reproduced
//!                              85/86 corpus, re-certified across many
//!                              alternative stream seeds; plus the
//!                              distinct-count kill-test across depths/seeds.
//!  A4 PROTOCOL ROC          -- empirical ROC over labeled pairs for a grid of
//!                              (streams, symbols, threshold) incl. exact
//!                              match; cost measured.
//!  A5 HEADLINE RE-RUN       -- the 85/86 corpus (and the depth-5 resolution
//!                              of the lone exception) under the corrected
//!                              protocol; does the headline still stand?
//!
//! New file; imports wcore sources READ-ONLY. Build:
//!   cd wcore && zig build-exe -O ReleaseFast src/coevo_matcher_attack.zig -femit-bin=bin/coevo_matcher_attack
//! Run:
//!   ./bin/coevo_matcher_attack run1 <state.bin> <csv-part-1>   (repro + A1 + A2)
//!   ./bin/coevo_matcher_attack run2 <state.bin> <csv-part-2>   (A3 + A4 + A5)
//! Threads: exactly 2 compute threads at any time. Each run wall-bounded <= 15 min.

const std = @import("std");
const alien = @import("inv_alien.zig");
const coevo = @import("inv_coevo.zig");
const open = @import("inv_open.zig");
const frontier = @import("inv_frontier.zig");

const V: usize = alien.CANON_BASE; // 4
const PROD_N: usize = 12;
const PROD_L: usize = 32;
const PROD_T: f64 = coevo.MATCH_THRESHOLD; // 0.95
const PROD_DEPTH: usize = 4; // depth used by claim_c_breadth / alienIrreducible / budgetScan's DMAX=4 loop gate
const NSTAGE: usize = @typeInfo(coevo.Stage).@"enum".fields.len; // 5
const MAX_DEEP_PER_SEED: usize = 64; // arch cap is 60 total; deep(depth>=2) subset fits

// the exact 16-seed corpus from scripts/claim_c_breadth.sh
const SEEDS = [_]u64{ 1, 2, 7, 42, 99, 1000, 0x1111, 0xBEEF, 0xC0FFEE, 0xD00D, 0xACE, 0x5EED, 0xFACE, 0x1234, 0xABCD, 0x9999 };

fn splitmix(x0: u64) u64 {
    var x = x0 +% 0x9E3779B97F4A7C15;
    x = (x ^ (x >> 30)) *% 0xBF58476D1CE4E5B9;
    x = (x ^ (x >> 27)) *% 0x94D049BB133111EB;
    return x ^ (x >> 31);
}
fn streamSeed(i: usize) u64 {
    return splitmix(0x51F7EED2 +% @as(u64, i));
}

// ============================================================================
// Core comparison machinery -- ports behaviorMatches/behaviorAgreement's exact
// symbol-generation loop, adding mismatch-witness capture and early exit.
// ============================================================================

const Witness = struct {
    stream_seed: u64 = 0,
    pos: usize = 0,
    exp: u8 = 0,
    got: u8 = 0,
    syms: [64]u8 = undefined,
    slen: usize = 0,
};

const Cmp = struct {
    agree: usize = 0,
    total: usize = 0,
    mm: usize = 0,
    wit: ?Witness = null,
    fn frac(c: *const Cmp) f64 {
        if (c.total == 0) return 0;
        return @as(f64, @floatFromInt(c.agree)) / @as(f64, @floatFromInt(c.total));
    }
};

/// Compare prog's stream behaviour against a composed Stage-genome's target on
/// n_seq random streams of length L -- identical stream generation to
/// `coevo.behaviorMatches`/`behaviorAgreement`. Stops after `stop_mm` mismatches.
fn compareGenome(prog: *const alien.Program, genome: []const coevo.Stage, n_seq: usize, L: usize, seed: u64, stop_mm: usize) Cmp {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var tgt: [256]u8 = undefined;
    var got: [256]u8 = undefined;
    const ll = @min(L, 256);
    var res = Cmp{};
    for (0..n_seq) |_| {
        for (0..ll) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        coevo.composedTarget(genome, syms[0..ll], tgt[0..ll]);
        alien.runStream(prog, syms[0..ll], got[0..ll]);
        for (0..ll) |i| {
            res.total += 1;
            if (got[i] == tgt[i]) {
                res.agree += 1;
            } else {
                res.mm += 1;
                if (res.wit == null) {
                    var wt = Witness{ .stream_seed = seed, .pos = i, .exp = tgt[i], .got = got[i] };
                    wt.slen = @min(ll, 64);
                    @memcpy(wt.syms[0..wt.slen], syms[0..wt.slen]);
                    res.wit = wt;
                }
                if (res.mm >= stop_mm) return res;
            }
        }
    }
    return res;
}

const CertOutG = struct {
    reducible: bool = false,
    genome: coevo.Genome = .{},
    best: f64 = 0,
    depth_reached: usize = 0,
    complete: bool = true,
    ms: u64 = 0,
};

/// Production-logic certifier, parameterized (max_depth, n, L, thr, seed). At
/// the production point (4, 12, 32, 0.95) this is logically identical to
/// `coevo.reducible(prog, 4, seed)` -- same enumeration order, same per-genome PRNG.
fn certFracGenome(prog: *const alien.Program, max_depth: usize, n_seq: usize, L: usize, thr: f64, seed: u64, cap_ns: u64) CertOutG {
    var res = CertOutG{};
    var timer = std.time.Timer.start() catch unreachable;
    var d: usize = 1;
    while (d <= max_depth) : (d += 1) {
        var total: usize = 1;
        for (0..d) |_| total *= NSTAGE;
        var idx: usize = 0;
        while (idx < total) : (idx += 1) {
            if (idx % 4096 == 0 and timer.read() > cap_ns) {
                res.complete = false;
                res.ms = timer.read() / std.time.ns_per_ms;
                return res;
            }
            var g = coevo.Genome{};
            var x = idx;
            for (0..d) |_| {
                g.appendAssumeCapacity(@enumFromInt(x % NSTAGE));
                x /= NSTAGE;
            }
            const c = compareGenome(prog, g.slice(), n_seq, L, seed, std.math.maxInt(usize));
            const f = c.frac();
            if (f > res.best) res.best = f;
            if (f >= thr) {
                res.reducible = true;
                res.genome = g;
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

/// Corrected certifier: EXACT match (zero mismatches) on (n_seq x L) under seed_a,
/// confirmed exact on an independent seed_b. Cheap 32-symbol gate makes
/// non-matching genomes cost only a few symbols each (early exit).
fn certExactGenome(prog: *const alien.Program, max_depth: usize, n_seq: usize, L: usize, seed_a: u64, seed_b: u64, cap_ns: u64) CertOutG {
    var res = CertOutG{};
    var timer = std.time.Timer.start() catch unreachable;
    var d: usize = 1;
    while (d <= max_depth) : (d += 1) {
        var total: usize = 1;
        for (0..d) |_| total *= NSTAGE;
        var idx: usize = 0;
        while (idx < total) : (idx += 1) {
            if (idx % 8192 == 0 and timer.read() > cap_ns) {
                res.complete = false;
                res.ms = timer.read() / std.time.ns_per_ms;
                return res;
            }
            var g = coevo.Genome{};
            var x = idx;
            for (0..d) |_| {
                g.appendAssumeCapacity(@enumFromInt(x % NSTAGE));
                x /= NSTAGE;
            }
            const q = compareGenome(prog, g.slice(), 1, 32, seed_a, 1);
            if (q.mm != 0) continue;
            const a = compareGenome(prog, g.slice(), n_seq, L, seed_a, 1);
            if (a.mm != 0) continue;
            const b = compareGenome(prog, g.slice(), n_seq, L, seed_b, 1);
            if (b.mm != 0) continue;
            res.reducible = true;
            res.genome = g;
            res.depth_reached = d;
            res.ms = timer.read() / std.time.ns_per_ms;
            return res;
        }
        res.depth_reached = d;
    }
    res.ms = timer.read() / std.time.ns_per_ms;
    return res;
}

// ============================================================================
// Constructed adversaries (attack A1a) -- same rare-pattern-deviator /
// horizon-bomb family as matcher_attack.zig, recalibrated to the coevo
// window L=32 (production atomforge used L=28). Compared against genome
// [st_gxor], which computes bit-identical output to these g_xor-based
// deviators when they don't trigger.
// ============================================================================

/// g_xor with a TRANSIENT +1 deviation exactly when the run of consecutive
/// symbol-3s reaches length k. True accumulator hidden in r4; r3 (OUT_R) gets
/// r4 + trigger. Deviation rate ~ (3/4) * 4^-k per position.
fn devRun(k: u64) alien.Program {
    var p = alien.Program{};
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 10, .imm = 3 });
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 11, .imm = 1 });
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 6, .imm = k });
    p.step.appendAssumeCapacity(.{ .op = .a_xor, .a = 4, .b = 0, .out = 4 }); // true acc
    p.step.appendAssumeCapacity(.{ .op = .a_eq, .a = 0, .b = 10, .out = 7 }); // sym==3?
    p.step.appendAssumeCapacity(.{ .op = .a_add, .a = 8, .b = 11, .out = 9 }); // count+1
    p.step.appendAssumeCapacity(.{ .op = .a_sel, .a = 9, .b = 1, .c = 7, .out = 8 }); // count = sym==3 ? count+1 : 0
    p.step.appendAssumeCapacity(.{ .op = .a_eq, .a = 8, .b = 6, .out = 7 }); // count==k?
    p.step.appendAssumeCapacity(.{ .op = .a_and, .a = 7, .b = 11, .out = 9 }); // 1 iff trigger
    p.step.appendAssumeCapacity(.{ .op = .a_add, .a = 4, .b = 9, .out = 3 }); // out = acc + trigger
    return p;
}

/// Deviates when the run length is 2 OR 3 -- a threshold-straddling rate.
fn devRun2or3() alien.Program {
    var p = alien.Program{};
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 10, .imm = 3 });
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 11, .imm = 1 });
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 6, .imm = 2 });
    p.step.appendAssumeCapacity(.{ .op = .a_xor, .a = 4, .b = 0, .out = 4 });
    p.step.appendAssumeCapacity(.{ .op = .a_eq, .a = 0, .b = 10, .out = 7 });
    p.step.appendAssumeCapacity(.{ .op = .a_add, .a = 8, .b = 11, .out = 9 });
    p.step.appendAssumeCapacity(.{ .op = .a_sel, .a = 9, .b = 1, .c = 7, .out = 8 });
    p.step.appendAssumeCapacity(.{ .op = .a_eq, .a = 8, .b = 6, .out = 7 }); // count==2
    p.step.appendAssumeCapacity(.{ .op = .a_eq, .a = 8, .b = 10, .out = 2 }); // count==3
    p.step.appendAssumeCapacity(.{ .op = .a_or, .a = 7, .b = 2, .out = 7 });
    p.step.appendAssumeCapacity(.{ .op = .a_and, .a = 7, .b = 11, .out = 9 });
    p.step.appendAssumeCapacity(.{ .op = .a_add, .a = 4, .b = 9, .out = 3 });
    return p;
}

/// The HORIZON BOMB: identical to g_xor for the first 32 positions of every
/// stream (the coevo production stream length), then deviates on EVERY
/// position from #33 onward (latched). The production protocol (streams of
/// length 32) can NEVER see the difference -- at any threshold, seed, or
/// stream count, since every stream it ever draws is exactly 32 symbols.
fn horizonBomb() alien.Program {
    var p = alien.Program{};
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 11, .imm = 1 });
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 6, .imm = 33 });
    p.step.appendAssumeCapacity(.{ .op = .a_xor, .a = 4, .b = 0, .out = 4 }); // true acc
    p.step.appendAssumeCapacity(.{ .op = .a_add, .a = 8, .b = 11, .out = 8 }); // pos count (1-based)
    p.step.appendAssumeCapacity(.{ .op = .a_eq, .a = 8, .b = 6, .out = 7 }); // pos==33?
    p.step.appendAssumeCapacity(.{ .op = .a_or, .a = 9, .b = 7, .out = 9 }); // latch
    p.step.appendAssumeCapacity(.{ .op = .a_and, .a = 9, .b = 11, .out = 2 }); // 1 after latch
    p.step.appendAssumeCapacity(.{ .op = .a_add, .a = 4, .b = 2, .out = 3 });
    return p;
}

// ============================================================================
// CSV (same schema as matcher_attack.zig's csv for cross-round comparability)
// ============================================================================

const CsvW = struct {
    file: std.fs.File,
    w: std.fs.File.Writer,
    fn init(path: []const u8, header: bool) !CsvW {
        const f = try std.fs.cwd().createFile(path, .{});
        var s = CsvW{ .file = f, .w = f.writer() };
        if (header)
            try s.w.writeAll("attack,item,detail,depth,n_streams,L,threshold,trials,m1,m2,m3,m4,witness,note\n");
        return s;
    }
    fn row(s: *CsvW, attack: []const u8, item: []const u8, detail: []const u8, depth: usize, n: usize, L: usize, thr: f64, trials: usize, m1: f64, m2: f64, m3: f64, m4: f64, witness: []const u8, note: []const u8) void {
        s.w.print("{s},{s},{s},{d},{d},{d},{d:.3},{d},{d:.6},{d:.6},{d:.6},{d:.6},\"{s}\",\"{s}\"\n", .{ attack, item, detail, depth, n, L, thr, trials, m1, m2, m3, m4, witness, note }) catch {};
    }
    fn close(s: *CsvW) void {
        s.file.sync() catch {};
        s.file.close();
    }
};

fn witnessStr(buf: []u8, w: Witness) []const u8 {
    var stream = std.io.fixedBufferStream(buf);
    const wr = stream.writer();
    wr.writeAll("syms=") catch {};
    const show = @min(w.slen, @min(w.pos + 1, 48));
    for (w.syms[0..show]) |s| wr.print("{d}", .{s}) catch {};
    if (w.pos + 1 > show) wr.writeAll("..") catch {};
    wr.print(";pos={d};exp={d};got={d};sseed=0x{X}", .{ w.pos, w.exp, w.got, w.stream_seed }) catch {};
    return stream.getWritten();
}

fn genomeStr(buf: []u8, g: []const coevo.Stage) []const u8 {
    var stream = std.io.fixedBufferStream(buf);
    const wr = stream.writer();
    wr.writeAll("[") catch {};
    for (g) |st| wr.print("{c}", .{coevo.stageChar(st)}) catch {};
    wr.writeAll("]") catch {};
    return stream.getWritten();
}

// ============================================================================
// Phase 0: reproduce the 85/86 breadth corpus (16 seeds, §24 deep-solver
// ladder, fingerprint-certifier "novel" flag, production reducible() verdict)
// -- byte-for-byte the same construction as inv_main.zig's shared
// `buildDeepArch` + `alienIrreducible` loop / scripts/claim_c_breadth.sh.
// ============================================================================

const DeepArchPair = struct { genome: coevo.Genome, solver: alien.Program, depth: usize };

/// Ported verbatim from wcore/src/inv_main.zig `buildDeepArch` (shared by
/// budget/audit/match-stress/irreducible phases there).
fn buildDeepArch(al: std.mem.Allocator, base_seed: u64) !std.ArrayList(DeepArchPair) {
    const regs: usize = 8;
    var arch = std.ArrayList(DeepArchPair).init(al);
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
    return arch;
}

const CensusCandG = struct {
    prog: alien.Program,
    depth: u8 = 0, // composition depth of the ORIGINAL evolved genome (a.depth)
    novel: bool = false,
    reducible: bool = false,
    genome: [8]u8 = [_]u8{0} ** 8, // matched genome (production reducible() result), if reducible
    genome_len: u8 = 0,
    self_check_ok: bool = true, // my certFracGenome port agreed with production coevo.reducible
};

const SeedReproG = struct {
    seed: u64 = 0,
    tseed: u64 = 0,
    n_cands: u16 = 0,
    cands: [MAX_DEEP_PER_SEED]CensusCandG = undefined,
    n_novel: u16 = 0,
    n_irreducible: u16 = 0,
    self_check_mismatch: u16 = 0,
    log: std.ArrayList(u8) = undefined,
};

fn runReproSeed(seed: u64, sr: *SeedReproG) void {
    sr.seed = seed;
    sr.tseed = seed +% 0x133D;
    sr.log = std.ArrayList(u8).init(std.heap.page_allocator);
    const lw = sr.log.writer();

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const al = arena_state.allocator();

    lw.print("== repro seed 0x{X} (tseed=0x{X}) ==\n", .{ seed, sr.tseed }) catch {};

    var arch = buildDeepArch(al, seed) catch {
        lw.print("  buildDeepArch FAILED\n", .{}) catch {};
        return;
    };
    defer arch.deinit();

    const knowns = [_]alien.Program{ alien.alienXorScan(), alien.alienHashTable(), alien.alienRMWCounter(), alien.alienUnion() };
    var anchors: [knowns.len]frontier.Fingerprint = undefined;
    for (knowns, 0..) |kp, i| anchors[i] = open.infoDescriptor(&kp, seed ^ 0x1F0);

    for (arch.items) |a| {
        if (a.depth < 2) continue;
        if (sr.n_cands >= MAX_DEEP_PER_SEED) break;
        const fp = open.infoDescriptor(&a.solver, seed ^ 0x1F0);
        var mind: f64 = 999;
        for (anchors) |an| mind = @min(mind, frontier.fpDist(fp, an));
        const novel = mind > frontier.NOVELTY_THRESHOLD;

        // production decision instrument:
        const prod_red = coevo.reducible(&a.solver, PROD_DEPTH, sr.tseed);
        // witness-capturing port (self-check):
        const mine = certFracGenome(&a.solver, PROD_DEPTH, PROD_N, PROD_L, PROD_T, sr.tseed, 30 * std.time.ns_per_s);

        var cand = CensusCandG{ .prog = a.solver, .depth = @intCast(a.depth), .novel = novel };
        cand.reducible = (prod_red != null);
        if (mine.reducible != cand.reducible) {
            cand.self_check_ok = false;
            sr.self_check_mismatch += 1;
        }
        if (prod_red) |g| {
            cand.genome_len = @intCast(g.len);
            for (0..g.len) |j| cand.genome[j] = @intFromEnum(g.slice()[j]);
        }

        if (novel) sr.n_novel += 1;
        if (!cand.reducible) sr.n_irreducible += 1;
        sr.cands[sr.n_cands] = cand;
        sr.n_cands += 1;
    }

    lw.print("  deep-solvers={d} novel={d} irreducible={d} self_check_mismatch={d}\n", .{ sr.n_cands, sr.n_novel, sr.n_irreducible, sr.self_check_mismatch }) catch {};
}

// ============================================================================
// State (de)serialization -- so run2 doesn't rebuild the (expensive) corpus.
// ============================================================================

fn writeProg(w: anytype, p: *const alien.Program) !void {
    try w.writeByte(@intCast(p.setup.len));
    for (p.setup.slice()) |ins| try writeInstr(w, ins);
    try w.writeByte(@intCast(p.step.len));
    for (p.step.slice()) |ins| try writeInstr(w, ins);
}
fn writeInstr(w: anytype, ins: alien.Instr) !void {
    try w.writeByte(@intFromEnum(ins.op));
    try w.writeByte(ins.a);
    try w.writeByte(ins.b);
    try w.writeByte(ins.c);
    try w.writeByte(ins.out);
    try w.writeInt(u64, ins.imm, .little);
}
fn readProg(r: anytype) !alien.Program {
    var p = alien.Program{};
    const ns = try r.readByte();
    for (0..ns) |_| p.setup.appendAssumeCapacity(try readInstr(r));
    const nt = try r.readByte();
    for (0..nt) |_| p.step.appendAssumeCapacity(try readInstr(r));
    return p;
}
fn readInstr(r: anytype) !alien.Instr {
    var ins = alien.Instr{};
    ins.op = @enumFromInt(try r.readByte());
    ins.a = try r.readByte();
    ins.b = try r.readByte();
    ins.c = try r.readByte();
    ins.out = try r.readByte();
    ins.imm = try r.readInt(u64, .little);
    return ins;
}

fn saveState(path: []const u8, results: []const *SeedReproG) !void {
    const f = try std.fs.cwd().createFile(path, .{});
    defer f.close();
    var bw = std.io.bufferedWriter(f.writer());
    const w = bw.writer();
    try w.writeInt(u32, 0x434D4131, .little); // "CMA1"
    try w.writeByte(@intCast(results.len));
    for (results) |sr| {
        try w.writeInt(u64, sr.seed, .little);
        try w.writeInt(u64, sr.tseed, .little);
        try w.writeInt(u16, sr.n_cands, .little);
        for (0..sr.n_cands) |i| {
            const c = &sr.cands[i];
            try writeProg(w, &c.prog);
            try w.writeByte(c.depth);
            try w.writeByte(if (c.novel) 1 else 0);
            try w.writeByte(if (c.reducible) 1 else 0);
            try w.writeByte(c.genome_len);
            for (0..8) |j| try w.writeByte(c.genome[j]);
            try w.writeByte(if (c.self_check_ok) 1 else 0);
        }
        try w.writeInt(u16, sr.n_novel, .little);
        try w.writeInt(u16, sr.n_irreducible, .little);
        try w.writeInt(u16, sr.self_check_mismatch, .little);
    }
    try bw.flush();
}

fn loadState(al: std.mem.Allocator, path: []const u8) ![]*SeedReproG {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    var br = std.io.bufferedReader(f.reader());
    const r = br.reader();
    const magic = try r.readInt(u32, .little);
    if (magic != 0x434D4131) return error.BadState;
    const nres = try r.readByte();
    const out = try al.alloc(*SeedReproG, nres);
    for (0..nres) |i| {
        const sr = try al.create(SeedReproG);
        sr.* = .{};
        sr.seed = try r.readInt(u64, .little);
        sr.tseed = try r.readInt(u64, .little);
        sr.n_cands = try r.readInt(u16, .little);
        for (0..sr.n_cands) |ci| {
            var c = CensusCandG{ .prog = try readProg(r) };
            c.depth = try r.readByte();
            c.novel = (try r.readByte()) != 0;
            c.reducible = (try r.readByte()) != 0;
            c.genome_len = try r.readByte();
            for (0..8) |j| c.genome[j] = try r.readByte();
            c.self_check_ok = (try r.readByte()) != 0;
            sr.cands[ci] = c;
        }
        sr.n_novel = try r.readInt(u16, .little);
        sr.n_irreducible = try r.readInt(u16, .little);
        sr.self_check_mismatch = try r.readInt(u16, .little);
        out[i] = sr;
    }
    return out;
}

fn candGenome(c: *const CensusCandG) coevo.Genome {
    var g = coevo.Genome{};
    for (0..c.genome_len) |j| g.appendAssumeCapacity(@enumFromInt(c.genome[j]));
    return g;
}

// ============================================================================
// RUN 1: repro + A1 (false-equal) + A2 (false-different)
// ============================================================================

fn reproWorker(seeds: []const u64, results: []*SeedReproG, start: usize, stride: usize) void {
    var i = start;
    while (i < seeds.len) : (i += stride) {
        runReproSeed(seeds[i], results[i]);
    }
}

// ---- A1b: random-Program false-equal hunt against the enumerated stage-genome space ----

const FePair = struct {
    prod_frac: f64,
    true_frac: f64,
    genome: [8]u8 = [_]u8{0} ** 8,
    genome_len: u8 = 0,
    wit: Witness,
};

const HuntStats = struct {
    trials: usize = 0,
    alive: usize = 0,
    prod_pass: usize = 0,
    gray: usize = 0,
    false_equal: usize = 0,
    fes: [16]FePair = undefined,
    n_fes: usize = 0,
};

fn isAlive(p: *const alien.Program) bool {
    var syms: [64]u8 = undefined;
    var out: [64]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(0xA11FE);
    const rng = prng.random();
    for (&syms) |*s| s.* = @intCast(rng.uintLessThan(usize, V));
    alien.runStream(p, &syms, &out);
    for (out[1..]) |o| if (o != out[0]) return true;
    return false;
}

fn huntWorker(rng_seed: u64, trials: usize, tseed: u64, stats: *HuntStats) void {
    var prng = std.Random.DefaultPrng.init(rng_seed);
    const rng = prng.random();
    const sp = alien.Params{ .active_regs = 8, .mem_bias = 0.25 };
    for (0..trials) |_| {
        stats.trials += 1;
        const prog = alien.randProg(rng, &sp);
        if (!isAlive(&prog)) continue;
        stats.alive += 1;
        // production-budget certifier against the WHOLE enumerated genome space
        const prod = certFracGenome(&prog, PROD_DEPTH, PROD_N, PROD_L, PROD_T, tseed, 5 * std.time.ns_per_s);
        if (!prod.reducible) continue;
        stats.prod_pass += 1;
        // re-verify at high resolution against the SAME matched genome
        const full = compareGenome(&prog, prod.genome.slice(), 1024, 96, 0xD00D2, std.math.maxInt(usize));
        if (full.frac() < PROD_T) {
            stats.false_equal += 1;
            if (stats.n_fes < stats.fes.len) {
                var fe = FePair{ .prod_frac = prod.best, .true_frac = full.frac(), .genome_len = @intCast(prod.genome.len), .wit = full.wit.? };
                for (0..prod.genome.len) |j| fe.genome[j] = @intFromEnum(prod.genome.slice()[j]);
                stats.fes[stats.n_fes] = fe;
                stats.n_fes += 1;
            }
        } else {
            stats.gray += 1;
        }
    }
}

// ---- A1c: census audit of the REAL 85/86-corpus reducible verdicts ----

const CensusAudit = struct {
    seed_idx: usize,
    ci: usize,
    true_frac: f64 = -1,
    mm: usize = 0,
    wit: ?Witness = null,
};

fn censusAuditWorker(jobs: []CensusAudit, results: []const *SeedReproG, start: usize, stride: usize) void {
    var i = start;
    while (i < jobs.len) : (i += stride) {
        const j = &jobs[i];
        const sr = results[j.seed_idx];
        const cand = &sr.cands[j.ci];
        const g = candGenome(cand);
        const c = compareGenome(&cand.prog, g.slice(), 1024, 96, 0xD00D3, std.math.maxInt(usize));
        j.true_frac = c.frac();
        j.mm = c.mm;
        j.wit = c.wit;
    }
}

fn doRun1(al: std.mem.Allocator, state_path: []const u8, csv_path: []const u8) !void {
    const out = std.io.getStdOut().writer();
    var csv = try CsvW.init(csv_path, true);
    defer csv.close();
    var wbuf: [160]u8 = undefined;
    var cbuf: [64]u8 = undefined;
    var nbuf: [256]u8 = undefined;

    var total_timer = try std.time.Timer.start();

    // ---------------- Phase 0: reproduce the 85/86 corpus (2 threads) ----------------
    try out.writeAll("=== COEVO MATCHER ATTACK run1: repro 85/86 corpus + false-equal + false-different ===\n");
    var results_arr: [SEEDS.len]*SeedReproG = undefined;
    for (0..SEEDS.len) |i| {
        results_arr[i] = try al.create(SeedReproG);
        results_arr[i].* = .{};
    }
    {
        const t1 = try std.Thread.spawn(.{}, reproWorker, .{ &SEEDS, &results_arr, 0, 2 });
        const t2 = try std.Thread.spawn(.{}, reproWorker, .{ &SEEDS, &results_arr, 1, 2 });
        t1.join();
        t2.join();
    }
    var tot_deep: usize = 0;
    var tot_novel: usize = 0;
    var tot_irr: usize = 0;
    var tot_mismatch: usize = 0;
    for (results_arr) |sr| {
        try out.writeAll(sr.log.items);
        sr.log.deinit();
        tot_deep += sr.n_cands;
        tot_novel += sr.n_novel;
        tot_irr += sr.n_irreducible;
        tot_mismatch += sr.self_check_mismatch;
        const item = std.fmt.bufPrint(&wbuf, "0x{X}", .{sr.seed}) catch "";
        const note = std.fmt.bufPrint(&nbuf, "deep={d};novel={d};irreducible={d};self_check_mismatch={d}", .{ sr.n_cands, sr.n_novel, sr.n_irreducible, sr.self_check_mismatch }) catch "";
        csv.row("repro", item, "seed_corpus", PROD_DEPTH, PROD_N, PROD_L, PROD_T, sr.n_cands, @floatFromInt(sr.n_novel), @floatFromInt(sr.n_irreducible), @floatFromInt(sr.self_check_mismatch), 0, "", note);
    }
    try out.print("\n[TOTALS] deep_solvers={d} novel={d} irreducible={d} (expect ~86 novel, ~1 irreducible per claim_c_breadth.md) self_check_mismatch={d}/{d}\n", .{ tot_deep, tot_novel, tot_irr, tot_mismatch, tot_deep });
    {
        const note = std.fmt.bufPrint(&nbuf, "seeds={d};expect_novel~86;expect_irreducible~1", .{SEEDS.len}) catch "";
        csv.row("repro", "TOTALS", "16seed_corpus", PROD_DEPTH, PROD_N, PROD_L, PROD_T, tot_deep, @floatFromInt(tot_novel), @floatFromInt(tot_irr), @floatFromInt(tot_mismatch), 0, "", note);
    }
    try saveState(state_path, &results_arr);
    try out.print("[state saved to {s}; elapsed {d} ms]\n", .{ state_path, total_timer.read() / std.time.ns_per_ms });

    // ---------------- A1a: constructed adversaries vs genome=[st_gxor] ----------------
    try out.writeAll("\n=== A1a CONSTRUCTED FALSE-EQUAL ADVERSARIES (vs genome=[st_gxor], production protocol 12x32@0.95) ===\n");
    const gxor_genome = [_]coevo.Stage{.st_gxor};
    const tseed_ref = SEEDS[8] +% 0x133D; // 0xC0FFEE's tseed, a representative production seed

    const DevSpec = struct { name: []const u8, prog: alien.Program };
    var devs: [9]DevSpec = .{
        .{ .name = "dev_k2", .prog = devRun(2) },
        .{ .name = "dev_k2or3", .prog = devRun2or3() },
        .{ .name = "dev_k3", .prog = devRun(3) },
        .{ .name = "dev_k4", .prog = devRun(4) },
        .{ .name = "dev_k5", .prog = devRun(5) },
        .{ .name = "dev_k6", .prog = devRun(6) },
        .{ .name = "dev_k7", .prog = devRun(7) },
        .{ .name = "dev_k8", .prog = devRun(8) },
        .{ .name = "horizon_bomb", .prog = horizonBomb() },
    };

    try out.writeAll("  name          prod(tseed_ref)  pass500  TA(96)    TA(256)   reducible@d4(coevo.reducible)  witness\n");
    for (&devs) |*ds| {
        const p = &ds.prog;
        const prod_pass = compareGenome(p, &gxor_genome, PROD_N, PROD_L, tseed_ref, std.math.maxInt(usize)).frac() >= PROD_T;
        var npass: usize = 0;
        const NSW = 500;
        for (0..NSW) |i| {
            if (compareGenome(p, &gxor_genome, PROD_N, PROD_L, streamSeed(i), std.math.maxInt(usize)).frac() >= PROD_T) npass += 1;
        }
        const ta96 = compareGenome(p, &gxor_genome, 1024, 96, 0xFA15E, std.math.maxInt(usize));
        const ta256 = compareGenome(p, &gxor_genome, 256, 256, 0xFA15F, std.math.maxInt(usize));
        const red = coevo.reducible(p, PROD_DEPTH, tseed_ref);

        // constructed witness stream: enough symbol-3s (or zeros past the horizon)
        var wsyms: [64]u8 = [_]u8{0} ** 64;
        if (!std.mem.eql(u8, ds.name, "horizon_bomb")) {
            for (0..10) |i| wsyms[i] = 3;
        }
        var tgt: [64]u8 = undefined;
        var got: [64]u8 = undefined;
        coevo.composedTarget(&gxor_genome, &wsyms, &tgt);
        alien.runStream(p, &wsyms, &got);
        var cw = Witness{ .stream_seed = 0, .pos = 0, .exp = 0, .got = 0, .slen = 64 };
        @memcpy(cw.syms[0..64], wsyms[0..64]);
        var found = false;
        for (0..64) |i| {
            if (tgt[i] != got[i]) {
                cw.pos = i;
                cw.exp = tgt[i];
                cw.got = got[i];
                found = true;
                break;
            }
        }
        const ws = if (found) witnessStr(&wbuf, cw) else "NO-CONSTRUCTED-WITNESS";
        const pass_rate = @as(f64, @floatFromInt(npass)) / @as(f64, NSW);
        const red_str: []const u8 = if (red != null) "REDUCIBLE" else "irreducible";
        const note = std.fmt.bufPrint(&nbuf, "coevo.reducible_d4={s}", .{red_str}) catch "";
        csv.row("A1_constructed", ds.name, "vs_st_gxor", 1, PROD_N, PROD_L, PROD_T, NSW, if (prod_pass) 1 else 0, pass_rate, ta96.frac(), ta256.frac(), ws, note);
        try out.print("  {s:<13} {s:<5}            {d:.3}    {d:.6}  {d:.6}  {s:<11}                  {s}\n", .{ ds.name, if (prod_pass) "PASS" else "fail", pass_rate, ta96.frac(), ta256.frac(), red_str, ws });
    }

    // ---------------- A1b: random-Program hunt (2 threads) ----------------
    try out.writeAll("\n=== A1b RANDOM-PROGRAM FALSE-EQUAL HUNT (vs whole enumerated stage-genome space, depth<=4) ===\n");
    const TRIALS: usize = 20_000;
    var hs1 = HuntStats{};
    var hs2 = HuntStats{};
    {
        const t1 = try std.Thread.spawn(.{}, huntWorker, .{ 0x7A57A11, TRIALS / 2, tseed_ref, &hs1 });
        const t2 = try std.Thread.spawn(.{}, huntWorker, .{ 0x7A57B22, TRIALS / 2, tseed_ref, &hs2 });
        t1.join();
        t2.join();
    }
    const h_trials = hs1.trials + hs2.trials;
    const h_alive = hs1.alive + hs2.alive;
    const h_pass = hs1.prod_pass + hs2.prod_pass;
    const h_gray = hs1.gray + hs2.gray;
    const h_fe = hs1.false_equal + hs2.false_equal;
    try out.print("  trials={d} alive={d} prod_pass(reducible@d4)={d} gray={d} FALSE-EQUAL={d}\n", .{ h_trials, h_alive, h_pass, h_gray, h_fe });
    {
        const note = std.fmt.bufPrint(&nbuf, "alive={d}", .{h_alive}) catch "";
        csv.row("A1_random", "aggregate", "random_progs_vs_genome_space", PROD_DEPTH, PROD_N, PROD_L, PROD_T, h_trials, @floatFromInt(h_pass), @floatFromInt(h_fe), @floatFromInt(h_gray), 0, "", note);
    }
    for ([_]*HuntStats{ &hs1, &hs2 }) |hs| {
        for (hs.fes[0..hs.n_fes], 0..) |fe, i| {
            const item = std.fmt.bufPrint(&cbuf, "fe_pair_{d}", .{i}) catch "";
            const ws = witnessStr(&wbuf, fe.wit);
            var gbuf: [16]u8 = undefined;
            var gs = coevo.Genome{};
            for (0..fe.genome_len) |j| gs.appendAssumeCapacity(@enumFromInt(fe.genome[j]));
            const gstr = genomeStr(&gbuf, gs.slice());
            const note = std.fmt.bufPrint(&nbuf, "matched_genome={s}", .{gstr}) catch "";
            csv.row("A1_random", item, "false_equal", 0, PROD_N, PROD_L, PROD_T, 1, fe.prod_frac, fe.true_frac, 0, 0, ws, note);
            try out.print("  FE: prod_best={d:.4} true={d:.4} genome={s} {s}\n", .{ fe.prod_frac, fe.true_frac, gstr, ws });
        }
    }

    // ---------------- A1c: audit of the REAL 85/86-corpus reducible verdicts ----------------
    try out.writeAll("\n=== A1c CENSUS AUDIT: true agreement of every REAL production 'reducible' verdict ===\n");
    var jobs = std.ArrayList(CensusAudit).init(al);
    defer jobs.deinit();
    for (results_arr, 0..) |sr, si| {
        for (0..sr.n_cands) |ci| {
            if (sr.cands[ci].reducible) try jobs.append(.{ .seed_idx = si, .ci = ci });
        }
    }
    {
        const res_slice: []const *SeedReproG = &results_arr;
        const t1 = try std.Thread.spawn(.{}, censusAuditWorker, .{ jobs.items, res_slice, 0, 2 });
        const t2 = try std.Thread.spawn(.{}, censusAuditWorker, .{ jobs.items, res_slice, 1, 2 });
        t1.join();
        t2.join();
    }
    var n_exact: usize = 0;
    var n_gray: usize = 0;
    var n_fe: usize = 0;
    var fracs = std.ArrayList(f64).init(al);
    defer fracs.deinit();
    for (jobs.items) |j| {
        try fracs.append(j.true_frac);
        if (j.mm == 0) {
            n_exact += 1;
        } else if (j.true_frac >= PROD_T) {
            n_gray += 1;
        } else {
            n_fe += 1;
            const sr = results_arr[j.seed_idx];
            const cand = &sr.cands[j.ci];
            const g = candGenome(cand);
            var gbuf: [16]u8 = undefined;
            const gstr = genomeStr(&gbuf, g.slice());
            const item = std.fmt.bufPrint(&nbuf, "0x{X}_cand{d}", .{ sr.seed, j.ci }) catch "";
            var wb2: [160]u8 = undefined;
            const ws = if (j.wit) |w| witnessStr(&wb2, w) else "";
            csv.row("A1_census_fe", item, gstr, PROD_DEPTH, PROD_N, PROD_L, PROD_T, 1, j.true_frac, @floatFromInt(j.mm), 0, 0, ws, "production coevo.reducible said REDUCIBLE; true agreement < 0.95");
        }
    }
    std.mem.sort(f64, fracs.items, {}, std.sort.asc(f64));
    const med = if (fracs.items.len > 0) fracs.items[fracs.items.len / 2] else 0;
    const minf = if (fracs.items.len > 0) fracs.items[0] else 0;
    try out.print("  reducible verdicts audited={d} (of {d} total 'reducible' in corpus): exact={d} gray[0.95,1)={d} FALSE-EQUAL(<0.95)={d} (min={d:.4} med={d:.4})\n", .{ jobs.items.len, tot_deep - tot_irr, n_exact, n_gray, n_fe, minf, med });
    {
        const note = std.fmt.bufPrint(&nbuf, "min_true={d:.6};median_true={d:.6};of_86_headline_reducible={d}", .{ minf, med, jobs.items.len }) catch "";
        csv.row("A1_census", "aggregate", "all_production_reducible_verdicts", PROD_DEPTH, PROD_N, PROD_L, PROD_T, jobs.items.len, @floatFromInt(n_exact), @floatFromInt(n_gray), @floatFromInt(n_fe), med, "", note);
    }

    // ---------------- A2: false-different hunt ----------------
    try out.writeAll("\n=== A2 FALSE-DIFFERENT: extensionally-equal syntactic variants of the reference solvers ===\n");
    {
        const TaskSpec = struct { task: coevo.TaskKind, stage: coevo.Stage };
        const tasks = [_]TaskSpec{
            .{ .task = .g_xor, .stage = .st_gxor },
            .{ .task = .g_add, .stage = .st_gadd },
            .{ .task = .pk_xor, .stage = .st_pkxor },
            .{ .task = .pk_add, .stage = .st_pkadd },
        };
        var n_pairs: usize = 0;
        var n_ver_fail: usize = 0;
        var n_below: usize = 0;
        var min_frac: f64 = 1.0;
        for (tasks) |ts| {
            const base = coevo.refSolver(ts.task);
            const genome = [_]coevo.Stage{ts.stage};
            for (0..3) |variant| {
                var v = base;
                switch (variant) {
                    0 => {
                        if (v.step.len >= alien.MAX_INSTR) continue;
                        v.step.appendAssumeCapacity(.{ .op = .nop });
                    },
                    1 => {
                        if (v.step.len >= alien.MAX_INSTR) continue;
                        v.step.appendAssumeCapacity(.{ .op = .a_mov, .a = 5, .out = 5 });
                    },
                    else => {
                        if (v.setup.len >= alien.MAX_INSTR) continue;
                        v.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 5, .imm = 42 });
                    },
                }
                // verify extensional equality on a large sample (construction guarantees it)
                const ver = compareGenome(&v, &genome, 256, 128, 0xEC0A2, 1);
                if (ver.mm != 0) {
                    n_ver_fail += 1;
                    continue;
                }
                n_pairs += 1;
                for (0..100) |i| {
                    const f = compareGenome(&v, &genome, PROD_N, PROD_L, streamSeed(1000 + i), std.math.maxInt(usize)).frac();
                    if (f < min_frac) min_frac = f;
                    if (f < PROD_T) n_below += 1;
                }
            }
        }
        try out.print("  known-equal pairs={d} x 100 seeds: verdicts below 0.95 = {d} (min frac {d:.6}); variant-verify failures={d}\n", .{ n_pairs, n_below, min_frac, n_ver_fail });
        const note = std.fmt.bufPrint(&nbuf, "variant_construction_failures={d};min_frac_over_all={d:.6}", .{ n_ver_fail, min_frac }) catch "";
        csv.row("A2_equal", "aggregate", "syntactic_variants_100seeds", 0, PROD_N, PROD_L, PROD_T, n_pairs * 100, @floatFromInt(n_below), min_frac, 0, 0, "", note);
    }

    // near-band: threshold-adjacent pairs (both sides of 0.95)
    try out.writeAll("\n=== A2 NEAR-BAND: verdict noise for pairs whose TRUE agreement straddles 0.95 ===\n");
    {
        const NearSpec = struct { name: []const u8, prog: alien.Program };
        var nears: [2]NearSpec = .{
            .{ .name = "dev_k2_trueabove", .prog = devRun(2) },
            .{ .name = "dev_k2or3_truebelow", .prog = devRun2or3() },
        };
        for (&nears) |*ns| {
            const ta = compareGenome(&ns.prog, &gxor_genome, 1024, 96, 0xFA15E, std.math.maxInt(usize)).frac();
            var npass: usize = 0;
            const NSW = 2000;
            for (0..NSW) |i| {
                if (compareGenome(&ns.prog, &gxor_genome, PROD_N, PROD_L, streamSeed(3000 + i), std.math.maxInt(usize)).frac() >= PROD_T) npass += 1;
            }
            const pr = @as(f64, @floatFromInt(npass)) / @as(f64, NSW);
            try out.print("  {s:<22} true={d:.4} pass_rate={d:.4} (verdict flips seed-to-seed)\n", .{ ns.name, ta, pr });
            csv.row("A2_nearband", ns.name, "vs_st_gxor", 1, PROD_N, PROD_L, PROD_T, NSW, ta, pr, 1.0 - pr, 0, "", "true agreement straddles the threshold; verdict is stream-seed noise");
        }
    }

    try out.print("\n[run1 total elapsed {d} ms]\n", .{total_timer.read() / std.time.ns_per_ms});
}

// ============================================================================
// RUN 2: A3 seed-flip + A4 ROC + A5 corrected-protocol headline re-run
// ============================================================================

const SweepJob = struct {
    prog: *const alien.Program,
    genome: []const coevo.Stage,
    seed: u64,
    result_frac: f64 = 0,
    result_pass: bool = false,
};

fn sweepWorker(jobs: []SweepJob, start: usize, stride: usize) void {
    var i = start;
    while (i < jobs.len) : (i += stride) {
        const j = &jobs[i];
        const c = compareGenome(j.prog, j.genome, PROD_N, PROD_L, j.seed, std.math.maxInt(usize));
        j.result_frac = c.frac();
        j.result_pass = j.result_frac >= PROD_T;
    }
}

const N_SEEDFLIP: usize = 100;

fn doA3(al: std.mem.Allocator, out: anytype, csv: *CsvW, results: []*SeedReproG) !void {
    try out.writeAll("\n=== A3 SEED-FLIP: production 'reducible' verdicts under alternative stream draws ===\n");

    var jobs = std.ArrayList(SweepJob).init(al);
    defer jobs.deinit();
    // group bookkeeping: one group per corpus candidate that was 'reducible'
    const GroupMeta = struct {
        seed_idx: usize,
        ci: usize,
        n_jobs: usize = 0,
        flips: usize = 0,
        best_min: f64 = 1,
        best_max: f64 = 0,
    };
    var groups = std.ArrayList(GroupMeta).init(al);
    defer groups.deinit();
    var group_of_job = std.ArrayList(usize).init(al);
    defer group_of_job.deinit();

    for (results, 0..) |sr, si| {
        for (0..sr.n_cands) |ci| {
            if (!sr.cands[ci].reducible) continue;
            const gi = groups.items.len;
            try groups.append(.{ .seed_idx = si, .ci = ci });
            for (0..N_SEEDFLIP) |i| {
                const s = if (i == 0) sr.tseed else streamSeed(7000 + i);
                try jobs.append(.{ .prog = &sr.cands[ci].prog, .genome = candGenomeStable(&sr.cands[ci]), .seed = s });
                try group_of_job.append(gi);
            }
        }
    }
    try out.print("  [{d} sweep jobs across {d} REDUCIBLE-verdict groups, 2 threads]\n", .{ jobs.items.len, groups.items.len });
    {
        const t1 = try std.Thread.spawn(.{}, sweepWorker, .{ jobs.items, 0, 2 });
        const t2 = try std.Thread.spawn(.{}, sweepWorker, .{ jobs.items, 1, 2 });
        t1.join();
        t2.join();
    }
    for (jobs.items, 0..) |j, idx| {
        const g = &groups.items[group_of_job.items[idx]];
        g.n_jobs += 1;
        if (!j.result_pass) g.flips += 1; // flip = no longer reducible under this seed
        g.best_min = @min(g.best_min, j.result_frac);
        g.best_max = @max(g.best_max, j.result_frac);
    }
    var total_flips: usize = 0;
    var groups_with_flip: usize = 0;
    for (groups.items) |g| {
        total_flips += g.flips;
        if (g.flips > 0) groups_with_flip += 1;
        const sr = results[g.seed_idx];
        const item = std.fmt.bufPrint(std.heap.page_allocator.alloc(u8, 64) catch unreachable, "0x{X}_cand{d}", .{ sr.seed, g.ci }) catch "item";
        csv.row("A3_seedflip", item, "reducible_verdict", PROD_DEPTH, PROD_N, PROD_L, PROD_T, g.n_jobs, @floatFromInt(g.flips), g.best_min, g.best_max, 0, "", "flip = verdict becomes NOT-reducible under an alternative stream seed");
    }
    try out.print("  TOTAL: {d} reducible-verdict groups x {d} seeds each; verdicts that flip to NOT-reducible at >=1 seed: {d} groups ({d} total seed-level flips / {d})\n", .{ groups.items.len, N_SEEDFLIP, groups_with_flip, total_flips, groups.items.len * N_SEEDFLIP });
    {
        const note = std.fmt.bufPrint(std.heap.page_allocator.alloc(u8, 128) catch unreachable, "groups={d};seeds_per_group={d};groups_with_any_flip={d};total_seed_flips={d}", .{ groups.items.len, N_SEEDFLIP, groups_with_flip, total_flips }) catch "note";
        csv.row("A3_seedflip", "TOTAL", "aggregate", PROD_DEPTH, PROD_N, PROD_L, PROD_T, groups.items.len * N_SEEDFLIP, @floatFromInt(groups_with_flip), @floatFromInt(total_flips), 0, 0, "", note);
    }

    // kill-test: distinct-count seed-flip sweep across depths (mirrors budget_scan sanity)
    try out.writeAll("\n  distinct-count kill-test seed-flip sweep (vs the 5 stage atoms, depth 1..8):\n");
    const dc = coevo.distinctCountProg();
    for (1..9) |d| {
        var flips: usize = 0;
        var bmax: f64 = 0;
        const NS: usize = if (d <= 5) 32 else 8;
        for (0..NS) |i| {
            const s = if (i == 0) 0x133D else streamSeed(9000 + d * 100 + i);
            const r = certFracGenome(&dc, d, PROD_N, PROD_L, PROD_T, s, 20 * std.time.ns_per_s);
            if (r.reducible) flips += 1;
            bmax = @max(bmax, r.best);
        }
        try out.print("    depth {d}: {d}/{d} seeds say REDUCIBLE (expect 0); best-approach max={d:.4}\n", .{ d, flips, NS, bmax });
        csv.row("A3_killtest", "distinct_count", "vs_5_stage_atoms", d, PROD_N, PROD_L, PROD_T, NS, @floatFromInt(flips), bmax, 0, 0, "", "flips=0 expected at every depth (non-vacuity)");
    }
}

fn candGenomeStable(c: *const CensusCandG) []const coevo.Stage {
    // small helper: allocate genome slice once per candidate (leaked into arena via
    // caller's page_allocator is acceptable for a short-lived attack binary)
    const buf = std.heap.page_allocator.alloc(coevo.Stage, c.genome_len) catch unreachable;
    for (0..c.genome_len) |j| buf[j] = @enumFromInt(c.genome[j]);
    return buf;
}

// ---- A4 ROC machinery ----

const N_CELLS: usize = 10;
const CELLS = [N_CELLS][2]usize{
    .{ 12, 32 }, .{ 24, 32 }, .{ 48, 32 }, .{ 12, 64 },
    .{ 24, 64 }, .{ 48, 64 }, .{ 12, 128 }, .{ 24, 128 },
    .{ 48, 128 }, .{ 64, 256 },
};
const N_THR: usize = 4; // 0.95, 0.97, 0.99, exact(1.0)
const THRS = [_]f64{ 0.95, 0.97, 0.99, 1.0 };
const N_CLASS: usize = 3; // 0=DIFF 1=GRAY 2=EQ(exact incl. EQSYN)

const LabeledPair = struct {
    prog: alien.Program,
    genome: [8]u8,
    genome_len: u8,
    class: usize,
    true_frac: f64,
};

const RocCounts = struct {
    pass: [N_CELLS][N_THR][N_CLASS]usize = std.mem.zeroes([N_CELLS][N_THR][N_CLASS]usize),
    total: [N_CLASS]usize = std.mem.zeroes([N_CLASS]usize),
};

const ROC_EVAL_SEEDS: usize = 5;

fn rocWorker(pairs: []const LabeledPair, counts: *RocCounts, start: usize, stride: usize) void {
    var i = start;
    while (i < pairs.len) : (i += stride) {
        const p = &pairs[i];
        var g = coevo.Genome{};
        for (0..p.genome_len) |j| g.appendAssumeCapacity(@enumFromInt(p.genome[j]));
        counts.total[p.class] += ROC_EVAL_SEEDS;
        for (CELLS, 0..) |cell, ci| {
            for (0..ROC_EVAL_SEEDS) |si| {
                const c = compareGenome(&p.prog, g.slice(), cell[0], cell[1], splitmix(0xE7A1 +% @as(u64, si)), std.math.maxInt(usize));
                const f = c.frac();
                for (THRS, 0..) |t, ti| {
                    const pass = if (ti == N_THR - 1) (c.mm == 0) else (f >= t);
                    if (pass) counts.pass[ci][ti][p.class] += 1;
                }
            }
        }
    }
}

fn doA4(al: std.mem.Allocator, out: anytype, csv: *CsvW) !void {
    try out.writeAll("\n=== A4 PROTOCOL ROC (labeled pairs x protocol grid) ===\n");
    var ibuf: [64]u8 = undefined;
    var pairs = std.ArrayList(LabeledPair).init(al);
    defer pairs.deinit();
    {
        var prng = std.Random.DefaultPrng.init(0x0C0FFEE);
        const rng = prng.random();
        const sp = alien.Params{ .active_regs = 8, .mem_bias = 0.25 };
        // natural pairs: random Program vs its production-budget best-matching genome
        // (or, if none matches, vs genome=[st_gxor] as a fixed reference) -- labeled by
        // 98k-symbol true agreement against THAT genome.
        var made: usize = 0;
        var attempts: usize = 0;
        while (made < 1200 and attempts < 40_000) : (attempts += 1) {
            const prog = alien.randProg(rng, &sp);
            if (!isAlive(&prog)) continue;
            const prod = certFracGenome(&prog, 3, PROD_N, PROD_L, PROD_T, 0x133D, 2 * std.time.ns_per_s);
            var g: coevo.Genome = undefined;
            if (prod.reducible) {
                g = prod.genome;
            } else {
                g = coevo.Genome{};
                g.appendAssumeCapacity(.st_gxor);
            }
            const full = compareGenome(&prog, g.slice(), 1024, 96, 0xD00D7, std.math.maxInt(usize));
            const f = full.frac();
            const class: usize = if (full.mm == 0) 2 else if (f >= PROD_T) 1 else 0;
            var lp = LabeledPair{ .prog = prog, .genome = [_]u8{0} ** 8, .genome_len = @intCast(g.len), .class = class, .true_frac = f };
            for (0..g.len) |j| lp.genome[j] = @intFromEnum(g.slice()[j]);
            try pairs.append(lp);
            made += 1;
        }
        // syntactic-equal pairs (provably extensionally equal) -- reference solvers + dead code
        const TaskSpec = struct { task: coevo.TaskKind, stage: coevo.Stage };
        const tasks = [_]TaskSpec{
            .{ .task = .g_xor, .stage = .st_gxor },
            .{ .task = .g_add, .stage = .st_gadd },
            .{ .task = .pk_xor, .stage = .st_pkxor },
            .{ .task = .pk_add, .stage = .st_pkadd },
        };
        for (tasks) |ts| {
            const base = coevo.refSolver(ts.task);
            var v = base;
            if (v.step.len < alien.MAX_INSTR) v.step.appendAssumeCapacity(.{ .op = .nop });
            var lp = LabeledPair{ .prog = v, .genome = [_]u8{0} ** 8, .genome_len = 1, .class = 2, .true_frac = 1.0 };
            lp.genome[0] = @intFromEnum(ts.stage);
            try pairs.append(lp);
        }
    }
    var counts1 = RocCounts{};
    var counts2 = RocCounts{};
    {
        const t1 = try std.Thread.spawn(.{}, rocWorker, .{ pairs.items, &counts1, 0, 2 });
        const t2 = try std.Thread.spawn(.{}, rocWorker, .{ pairs.items, &counts2, 1, 2 });
        t1.join();
        t2.join();
    }
    var counts = RocCounts{};
    for (0..N_CELLS) |ci| for (0..N_THR) |ti| for (0..N_CLASS) |cl| {
        counts.pass[ci][ti][cl] = counts1.pass[ci][ti][cl] + counts2.pass[ci][ti][cl];
    };
    for (0..N_CLASS) |cl| counts.total[cl] = counts1.total[cl] + counts2.total[cl];
    try out.print("  labeled pairs: DIFF={d} GRAY={d} EQ={d} (x{d} eval seeds)\n", .{ counts.total[0] / ROC_EVAL_SEEDS, counts.total[1] / ROC_EVAL_SEEDS, counts.total[2] / ROC_EVAL_SEEDS, ROC_EVAL_SEEDS });
    try out.writeAll("  cell        thr    FE(DIFF-pass) GRAY-pass  det(EQ)\n");
    for (CELLS, 0..) |cell, ci| {
        for (THRS, 0..) |t, ti| {
            const fe = @as(f64, @floatFromInt(counts.pass[ci][ti][0])) / @as(f64, @floatFromInt(@max(1, counts.total[0])));
            const gp = @as(f64, @floatFromInt(counts.pass[ci][ti][1])) / @as(f64, @floatFromInt(@max(1, counts.total[1])));
            const de = @as(f64, @floatFromInt(counts.pass[ci][ti][2])) / @as(f64, @floatFromInt(@max(1, counts.total[2])));
            const item = std.fmt.bufPrint(&ibuf, "n{d}_L{d}", .{ cell[0], cell[1] }) catch "";
            csv.row("A4_roc", item, "labeled_pairs", 0, cell[0], cell[1], t, counts.total[0] + counts.total[2], fe, gp, de, 0, "", "m1=FE_rate(DIFF pass) m2=GRAY pass m3=det EQ");
            if (ti == 0 or ti == N_THR - 1) {
                try out.print("  n{d:<3}L{d:<4} {d:.2}   {d:.6}      {d:.4}    {d:.4}\n", .{ cell[0], cell[1], t, fe, gp, de });
            }
        }
    }

    // deviator ladder against the grid (representative cells)
    try out.writeAll("\n  deviator ladder pass rates (constructed rare-pattern adversaries vs [st_gxor]):\n");
    {
        var devs2: [9]struct { name: []const u8, prog: alien.Program } = .{
            .{ .name = "dev_k2", .prog = devRun(2) },
            .{ .name = "dev_k2or3", .prog = devRun2or3() },
            .{ .name = "dev_k3", .prog = devRun(3) },
            .{ .name = "dev_k4", .prog = devRun(4) },
            .{ .name = "dev_k5", .prog = devRun(5) },
            .{ .name = "dev_k6", .prog = devRun(6) },
            .{ .name = "dev_k7", .prog = devRun(7) },
            .{ .name = "dev_k8", .prog = devRun(8) },
            .{ .name = "horizon_bomb", .prog = horizonBomb() },
        };
        const gxor_genome = [_]coevo.Stage{.st_gxor};
        const ladder_cells = [_][2]usize{ .{ 12, 32 }, .{ 24, 64 }, .{ 48, 128 }, .{ 64, 256 } };
        for (&devs2) |*ds| {
            for (ladder_cells) |cell| {
                var pass95: usize = 0;
                var pass_exact: usize = 0;
                const NS: usize = if (cell[1] == 256) 2000 else 300;
                for (0..NS) |i| {
                    const c = compareGenome(&ds.prog, &gxor_genome, cell[0], cell[1], streamSeed(20000 + i), std.math.maxInt(usize));
                    if (c.frac() >= PROD_T) pass95 += 1;
                    if (c.mm == 0) pass_exact += 1;
                }
                const p95 = @as(f64, @floatFromInt(pass95)) / @as(f64, @floatFromInt(NS));
                const pex = @as(f64, @floatFromInt(pass_exact)) / @as(f64, @floatFromInt(NS));
                const item = std.fmt.bufPrint(&ibuf, "{s}_n{d}_L{d}", .{ ds.name, cell[0], cell[1] }) catch "";
                csv.row("A4_ladder", item, "vs_st_gxor", 1, cell[0], cell[1], PROD_T, NS, p95, pex, 0, 0, "", "m1=pass@0.95 m2=pass@exact");
                if (cell[1] >= 128) {
                    try out.print("    {s:<14} n{d}xL{d}: pass@0.95={d:.4} pass@exact={d:.4}\n", .{ ds.name, cell[0], cell[1], p95, pex });
                }
            }
        }
    }

    // cost measurement: production loose census vs corrected-exact census on real corpus items
    try out.writeAll("\n  protocol cost (single-candidate census, production vs corrected-exact):\n");
    {
        const dc = coevo.distinctCountProg();
        var t0 = try std.time.Timer.start();
        const r_prod = certFracGenome(&dc, PROD_DEPTH, PROD_N, PROD_L, PROD_T, 0x133D, 60 * std.time.ns_per_s);
        const ms_prod = t0.read() / std.time.ns_per_ms;
        t0.reset();
        const r_corr = certExactGenome(&dc, PROD_DEPTH, 64, 256, 0xE1A5E01, 0xE1A5E02, 60 * std.time.ns_per_s);
        const ms_corr = t0.read() / std.time.ns_per_ms;
        try out.print("    production (12x32,0.95) d<=4: {d} ms (reducible={})   corrected exact(64x256,2-seed) d<=4: {d} ms (reducible={})\n", .{ ms_prod, r_prod.reducible, ms_corr, r_corr.reducible });
        csv.row("A4_cost", "distinct_count_d4", "prod_vs_correctedexact", PROD_DEPTH, 64, 256, 1.0, 1, @floatFromInt(ms_prod), @floatFromInt(ms_corr), if (r_prod.reducible) 1 else 0, if (r_corr.reducible) 1 else 0, "", "m1=prod ms m2=corrected ms");
    }
}

/// A1c re-derived with a NOVEL vs non-novel breakdown -- precisely answers "how
/// many of the 85/86 (fingerprint-novel, reducible) headline verdicts are
/// false-equals, vs how many false-equals are in the non-novel-but-deep
/// remainder that doesn't touch the 85/86 number at all". Reuses the exact
/// same big-sample seed (0xD00D3) as run1's A1c so the two audits agree.
fn doA1cByNovelty(out: anytype, csv: *CsvW, results: []*SeedReproG) !void {
    try out.writeAll("\n=== A1c-recap: census false-equals broken down by fingerprint-novelty (the 85/86 bucket) ===\n");
    var novel_red: usize = 0;
    var novel_fe: usize = 0;
    var novel_min: f64 = 1.0;
    var nonnovel_red: usize = 0;
    var nonnovel_fe: usize = 0;
    for (results) |sr| {
        for (0..sr.n_cands) |ci| {
            const cand = &sr.cands[ci];
            if (!cand.reducible) continue;
            const g = candGenome(cand);
            const c = compareGenome(&cand.prog, g.slice(), 1024, 96, 0xD00D3, std.math.maxInt(usize));
            const f = c.frac();
            if (cand.novel) {
                novel_red += 1;
                if (f < PROD_T) {
                    novel_fe += 1;
                    novel_min = @min(novel_min, f);
                    try out.print("  [85/86-BUCKET FALSE-EQUAL] 0x{X}_cand{d}: true_agree={d:.4}\n", .{ sr.seed, ci, f });
                }
            } else {
                nonnovel_red += 1;
                if (f < PROD_T) nonnovel_fe += 1;
            }
        }
    }
    try out.print("  85/86 bucket (fingerprint-novel & production-reducible): {d} reducible, {d} FALSE-EQUAL (worst true={d:.4})\n", .{ novel_red, novel_fe, if (novel_fe > 0) novel_min else 0 });
    try out.print("  non-novel deep-solver remainder (reducible, outside the 85/86 count): {d} reducible, {d} FALSE-EQUAL\n", .{ nonnovel_red, nonnovel_fe });
    const note = std.fmt.bufPrint(std.heap.page_allocator.alloc(u8, 256) catch unreachable, "novel_reducible={d};novel_false_equal={d};nonnovel_reducible={d};nonnovel_false_equal={d};headline_was={d}/86", .{ novel_red, novel_fe, nonnovel_red, nonnovel_fe, novel_red }) catch "note";
    csv.row("A1c_novelty", "breakdown", "85_86_bucket_vs_remainder", PROD_DEPTH, PROD_N, PROD_L, PROD_T, novel_red + nonnovel_red, @floatFromInt(novel_fe), @floatFromInt(nonnovel_fe), @floatFromInt(novel_red), @floatFromInt(nonnovel_red), "", note);
}

fn doA5(al: std.mem.Allocator, out: anytype, csv: *CsvW, results: []*SeedReproG) !void {
    _ = al;
    try out.writeAll("\n=== A5 HEADLINE RE-RUN: the 85/86 corpus under the corrected protocol (exact, 64x256, 2 seeds) ===\n");
    const CS_A: u64 = 0xE1A5E01;
    const CS_B: u64 = 0xE1A5E02;
    var ibuf: [64]u8 = undefined;

    var total_reducible_prod: usize = 0;
    var total_reducible_corrected: usize = 0;
    var migrations: usize = 0; // prod REDUCIBLE -> corrected NOT reducible (at same depth 4)
    var promoted_to_depth5: usize = 0; // prod irreducible@d4 -> corrected reducible@d5 (mirrors budget_scan resolution)
    var still_irreducible: usize = 0;

    for (results) |sr| {
        for (0..sr.n_cands) |ci| {
            const cand = &sr.cands[ci];
            const item = std.fmt.bufPrint(&ibuf, "0x{X}_cand{d}", .{ sr.seed, ci }) catch "";
            if (cand.reducible) {
                total_reducible_prod += 1;
                const g = candGenome(cand);
                const r4 = certExactGenome(&cand.prog, PROD_DEPTH, 64, 256, CS_A, CS_B, 15 * std.time.ns_per_s);
                if (r4.reducible) total_reducible_corrected += 1 else migrations += 1;
                var gb: [16]u8 = undefined;
                const gstr = genomeStr(&gb, g.slice());
                csv.row("A5_verdict", item, gstr, PROD_DEPTH, 64, 256, 1.0, 1, if (r4.reducible) 1 else 0, 1, 0, 0, "", "prod=REDUCIBLE; m1=corrected-exact still reducible@d4");
            } else {
                // production said irreducible at depth 4 -- push to depth 5 under corrected
                // exact protocol (mirrors budget_scan's DMAX push that resolved the lone
                // historical exception).
                const r5 = certExactGenome(&cand.prog, PROD_DEPTH + 1, 64, 256, CS_A, CS_B, 45 * std.time.ns_per_s);
                if (r5.reducible) {
                    promoted_to_depth5 += 1;
                    var gb: [16]u8 = undefined;
                    const gstr = genomeStr(&gb, r5.genome.slice());
                    try out.print("  {s}: prod IRREDUCIBLE@d4 -> corrected REDUCIBLE@d5 via {s} (mirrors the historical 0xD00D resolution)\n", .{ item, gstr });
                    csv.row("A5_verdict", item, gstr, 5, 64, 256, 1.0, 1, 0, 1, 0, 0, "", "prod=irreducible@d4; m2=corrected-exact reducible@d5");
                } else {
                    still_irreducible += 1;
                    try out.print("  {s}: prod IRREDUCIBLE@d4 -> corrected STILL IRREDUCIBLE@d5 (complete={})\n", .{ item, r5.complete });
                    csv.row("A5_verdict", item, "none", 5, 64, 256, 1.0, 1, 0, 0, 0, 0, "", "prod=irreducible@d4; corrected-exact also irreducible@d5");
                }
            }
        }
    }

    const corrected_headline_num = total_reducible_corrected + promoted_to_depth5;
    const corrected_headline_den = total_reducible_prod + promoted_to_depth5 + still_irreducible;
    try out.print("\n  PRODUCTION headline: {d}/{d} reducible (depth<=4)\n", .{ total_reducible_prod, total_reducible_prod + promoted_to_depth5 + still_irreducible });
    try out.print("  CORRECTED headline (exact 64x256 2-seed, same depths as production used +1 for the historical exception): {d}/{d} reducible; {d} false-equal migrations (prod REDUCIBLE -> corrected NOT); {d} true-irreducible survivors\n", .{ corrected_headline_num, corrected_headline_den, migrations, still_irreducible });
    {
        const note = std.fmt.bufPrint(std.heap.page_allocator.alloc(u8, 256) catch unreachable, "prod_reducible={d};corrected_reducible={d};migrations_reducible_to_irreducible={d};depth5_resolutions={d};still_irreducible={d};total={d}", .{ total_reducible_prod, corrected_headline_num, migrations, promoted_to_depth5, still_irreducible, corrected_headline_den }) catch "note";
        csv.row("A5_summary", "headline", "corrected_vs_production", PROD_DEPTH, 64, 256, 1.0, corrected_headline_den, @floatFromInt(total_reducible_prod), @floatFromInt(corrected_headline_num), @floatFromInt(migrations), @floatFromInt(still_irreducible), "", note);
    }

    // impact-on-claim-C aggregate row, combining A1c (census false-equal) semantics
    // with this A5 corrected re-certification: precisely, how many of the ORIGINAL
    // 85/86-style "reducible" bucket are confirmed false (migrations), vs how many
    // "irreducible" flags dissolve under more budget (promoted_to_depth5, the SAFE
    // direction that only strengthens Claim C).
    {
        const note = std.fmt.bufPrint(std.heap.page_allocator.alloc(u8, 256) catch unreachable, "false_equal_migrations(concern_direction)={d}/{d};false_different_resolutions(strengthens_claim_c)={d}/{d}", .{ migrations, total_reducible_prod, promoted_to_depth5, promoted_to_depth5 + still_irreducible }) catch "note";
        csv.row("A5_impact", "claim_c", "precise_impact", PROD_DEPTH, 64, 256, 1.0, 0, @floatFromInt(migrations), @floatFromInt(total_reducible_prod), @floatFromInt(promoted_to_depth5), @floatFromInt(still_irreducible), "", note);
    }
}

fn doRun2(al: std.mem.Allocator, state_path: []const u8, csv_path: []const u8, skip_a3: bool, skip_a4: bool) !void {
    const out = std.io.getStdOut().writer();
    var csv = try CsvW.init(csv_path, false);
    defer csv.close();
    var total_timer = try std.time.Timer.start();

    const results = try loadState(al, state_path);
    try out.print("=== COEVO MATCHER ATTACK run2: loaded state ({d} seeds) ===\n", .{results.len});
    var tot_cands: usize = 0;
    var tot_red: usize = 0;
    for (results) |sr| {
        tot_cands += sr.n_cands;
        for (0..sr.n_cands) |ci| if (sr.cands[ci].reducible) {
            tot_red += 1;
        };
    }
    try out.print("  total deep solvers={d}, reducible={d}, irreducible={d}\n", .{ tot_cands, tot_red, tot_cands - tot_red });

    if (!skip_a3) {
        try doA3(al, out, &csv, results);
    } else {
        try out.writeAll("\n[A3 SKIPPED (run3 mode)]\n");
    }
    try out.print("\n[A3 done at {d} ms]\n", .{total_timer.read() / std.time.ns_per_ms});

    if (!skip_a4) {
        try doA4(al, out, &csv);
    } else {
        try out.writeAll("\n[A4 SKIPPED (run4 mode)]\n");
    }
    try out.print("\n[A4 done at {d} ms]\n", .{total_timer.read() / std.time.ns_per_ms});

    try doA1cByNovelty(out, &csv, results);
    try doA5(al, out, &csv, results);

    try out.print("\n[run2 total elapsed {d} ms]\n", .{total_timer.read() / std.time.ns_per_ms});
}

/// FOLLOWUP: does the one census false-equal (0x63_cand6, matched to [>>] at
/// true agreement 0.664 -- production REDUCIBLE but corrected-exact NOT at
/// depth<=4) resolve at deeper budget, exactly the way the historical 0xD00D
/// exception resolved at depth 5 under the loose protocol (budget_scan.md)?
/// If it does, it is "just" a second depth artifact -- consistent with Claim C.
/// If it does NOT resolve by depth 8, it is a genuine candidate the false-equal
/// was hiding -- the serious direction for Claim C's 85/86 headline.
fn doFollowup(al: std.mem.Allocator, state_path: []const u8, csv_path: []const u8) !void {
    const out = std.io.getStdOut().writer();
    var csv = try CsvW.init(csv_path, false);
    defer csv.close();
    const results = try loadState(al, state_path);
    try out.print("=== FOLLOWUP: deep-budget resolution of every census false-equal ({d} seeds loaded) ===\n", .{results.len});

    var any = false;
    for (results) |sr| {
        for (0..sr.n_cands) |ci| {
            const cand = &sr.cands[ci];
            if (!cand.reducible) continue;
            const g = candGenome(cand);
            const big = compareGenome(&cand.prog, g.slice(), 1024, 96, 0xD00D3, std.math.maxInt(usize));
            if (big.frac() >= PROD_T) continue; // not a false-equal
            any = true;
            try out.print("\n  0x{X}_cand{d} (depth={d}, novel={}) -- census false-equal, true_agree(vs matched genome)={d:.4}\n", .{ sr.seed, ci, cand.depth, cand.novel, big.frac() });

            // (a) LOOSE protocol (coevo.reducible, production 12x32@0.95), pushed to depth 8
            const loose8 = coevo.reducible(&cand.prog, 8, sr.tseed);
            var gb: [16]u8 = undefined;
            if (loose8) |lg| {
                try out.print("    loose coevo.reducible(depth<=8, tseed=0x{X}): REDUCIBLE via {s}\n", .{ sr.tseed, genomeStr(&gb, lg.slice()) });
            } else {
                try out.print("    loose coevo.reducible(depth<=8, tseed=0x{X}): IRREDUCIBLE (full depth-8 enumeration)\n", .{sr.tseed});
            }
            // (b) also sweep loose protocol across several alternative seeds at depth 8
            var loose_flip_seed: ?u64 = null;
            for (0..8) |i| {
                const s = if (i == 0) sr.tseed else streamSeed(50000 + i);
                if (coevo.reducible(&cand.prog, 8, s) != null) {
                    loose_flip_seed = s;
                    break;
                }
            }

            // (c) CORRECTED exact protocol (64x256, 2 seeds), pushed depth 5..8
            var resolved_depth: ?usize = null;
            var resolved_genome_s: [16]u8 = undefined;
            var resolved_genome_len: usize = 0;
            for (5..9) |d| {
                const r = certExactGenome(&cand.prog, d, 64, 256, 0xE1A5E01, 0xE1A5E02, 90 * std.time.ns_per_s);
                if (r.reducible) {
                    resolved_depth = d;
                    const s = genomeStr(&resolved_genome_s, r.genome.slice());
                    resolved_genome_len = s.len;
                    try out.print("    corrected-exact(64x256,2seed) depth<={d}: REDUCIBLE via {s}\n", .{ d, s });
                    break;
                } else {
                    try out.print("    corrected-exact(64x256,2seed) depth<={d}: irreducible (complete={})\n", .{ d, r.complete });
                }
            }

            const item = std.fmt.bufPrint(std.heap.page_allocator.alloc(u8, 32) catch unreachable, "0x{X}_cand{d}", .{ sr.seed, ci }) catch "item";
            const verdict: []const u8 = if (resolved_depth) |_| "RESOLVED_DEEPER(budget_artifact_like_0xD00D)" else if (loose8 != null) "RESOLVED_UNDER_LOOSE_ONLY(matcher_dependent)" else "SURVIVES_TO_DEPTH8(genuine_candidate)";
            const note = std.fmt.bufPrint(std.heap.page_allocator.alloc(u8, 256) catch unreachable, "resolved_depth={?d};loose_reducible_d8={};loose_flip_alt_seed=0x{X};verdict={s}", .{ resolved_depth, loose8 != null, loose_flip_seed orelse 0, verdict }) catch "note";
            const resolved_genome_str: []const u8 = if (resolved_depth != null) resolved_genome_s[0..resolved_genome_len] else "none";
            csv.row("A6_followup", item, resolved_genome_str, if (resolved_depth) |d| d else 8, 64, 256, 1.0, 1, if (resolved_depth != null) 1 else 0, if (loose8 != null) 1 else 0, @floatFromInt(resolved_depth orelse 0), 0, "", note);
        }
    }
    if (!any) try out.writeAll("  (no census false-equals found in loaded state -- nothing to follow up)\n");
}

/// LADDER2: the deviator ladder's pass rate under the FULLY corrected protocol
/// (exact match, 64x256 symbols, confirmed on a SECOND independent seed) -- the
/// single-seed A4 ladder undersells the residual blind spot (round-c found the
/// second seed squares it: dev_k6 0.065->0.0025, dev_k7 0.4825->0.2330).
fn doLadder2(csv_path: []const u8) !void {
    const out = std.io.getStdOut().writer();
    var csv = try CsvW.init(csv_path, false);
    defer csv.close();
    const gxor_genome = [_]coevo.Stage{.st_gxor};
    var devs: [9]struct { name: []const u8, prog: alien.Program } = .{
        .{ .name = "dev_k2", .prog = devRun(2) },
        .{ .name = "dev_k2or3", .prog = devRun2or3() },
        .{ .name = "dev_k3", .prog = devRun(3) },
        .{ .name = "dev_k4", .prog = devRun(4) },
        .{ .name = "dev_k5", .prog = devRun(5) },
        .{ .name = "dev_k6", .prog = devRun(6) },
        .{ .name = "dev_k7", .prog = devRun(7) },
        .{ .name = "dev_k8", .prog = devRun(8) },
        .{ .name = "horizon_bomb", .prog = horizonBomb() },
    };
    try out.writeAll("=== LADDER2: 64x256 exact-match pass rate, 1-seed vs 2-independent-seed ===\n");
    try out.writeAll("  name          pass@exact(1seed,2000) pass@exact(2seed,2000)\n");
    const NS: usize = 2000;
    for (&devs) |*ds| {
        var pass1: usize = 0;
        var pass2: usize = 0;
        for (0..NS) |i| {
            const a = compareGenome(&ds.prog, &gxor_genome, 64, 256, streamSeed(40000 + i), 1);
            if (a.mm != 0) continue;
            pass1 += 1;
            const b = compareGenome(&ds.prog, &gxor_genome, 64, 256, streamSeed(41000 + i), 1);
            if (b.mm == 0) pass2 += 1;
        }
        const p1 = @as(f64, @floatFromInt(pass1)) / @as(f64, NS);
        const p2 = @as(f64, @floatFromInt(pass2)) / @as(f64, NS);
        try out.print("  {s:<14} {d:.4}                  {d:.4}\n", .{ ds.name, p1, p2 });
        csv.row("A4_ladder2", ds.name, "vs_st_gxor_64x256", 1, 64, 256, 1.0, NS, p1, p2, 0, 0, "", "m1=pass@exact_1seed m2=pass@exact_2seed(AND)");
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const al = gpa.allocator();

    const args = try std.process.argsAlloc(al);
    defer std.process.argsFree(al, args);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "ladder2")) {
        if (args.len < 3) {
            std.debug.print("usage: coevo_matcher_attack ladder2 <out.csv>\n", .{});
            return error.BadArgs;
        }
        try doLadder2(args[2]);
        return;
    }
    if (args.len < 4) {
        std.debug.print("usage: coevo_matcher_attack run1|run2|run3|run4|followup <state.bin> <out.csv>\n", .{});
        return error.BadArgs;
    }
    if (std.mem.eql(u8, args[1], "run1")) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        try doRun1(arena.allocator(), args[2], args[3]);
    } else if (std.mem.eql(u8, args[1], "followup")) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        try doFollowup(arena.allocator(), args[2], args[3]);
    } else {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const s3 = std.mem.eql(u8, args[1], "run3") or std.mem.eql(u8, args[1], "run4");
        const s4 = std.mem.eql(u8, args[1], "run4");
        try doRun2(arena.allocator(), args[2], args[3], s3, s4);
    }
}
