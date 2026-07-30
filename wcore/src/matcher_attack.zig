//! Round 2026-07-10c red-team: attack the STATISTICAL MATCHER inside wcore's
//! irreducibility certifier (`inv_atomforge.reducibleLib` / `matchesChain`:
//! "two behaviours are equal iff they agree >= 0.95 on 8 streams x 28 symbols,
//! fixed seed"). The depth attack (claimc_depth_attack.md) showed depth is no
//! longer the thinnest axis -- the matcher is (kill-test passed by 0.008).
//! THIS file asks: can the matcher be made to LIE in either direction?
//!
//! Attacks (see wcore/docs/research/matcher_falsification.md):
//!  A1 FALSE-EQUAL hunt      -- pairs that pass the production protocol but are
//!                              provably different (constructed rare-pattern
//!                              deviators, a protocol-horizon bomb, random-mutant
//!                              search, and an audit of the real a1a6 census
//!                              reducible verdicts). Every false-equal carries an
//!                              exact disagreement witness (stream + position).
//!  A2 FALSE-DIFFERENT hunt  -- extensionally-equal pairs scoring < 0.95
//!                              (structural argument + measured 0/N), plus the
//!                              threshold-adjacent near-band where the verdict is
//!                              genuinely seed-noise.
//!  A3 SEED-FLIP margins     -- the 20 a1a6 promoted atoms + the distinct-count
//!                              kill-test re-certified across many stream seeds:
//!                              how often do PRODUCTION verdicts flip under a
//!                              different stream draw?
//!  A4 PROTOCOL ROC          -- empirical ROC over labeled pairs for a grid of
//!                              (threshold, streams, symbols), incl. exact-match
//!                              protocols with early exit; runtime cost measured.
//!  A5 VERDICT RE-RUN        -- the a1a6 promotions, the depth-attack flip
//!                              (inv8 chain [5,9,6,0]), the redundancy witnesses
//!                              and the kill-tests under the corrected protocol;
//!                              census-level promotion-identity migration.
//!
//! New file; imports wcore sources READ-ONLY (same convention as claimc_attack).
//! Build:  cd wcore && zig build-exe -O ReleaseFast src/matcher_attack.zig -femit-bin=bin/matcher_attack
//! Run:    ./bin/matcher_attack run1 <state.bin> <csv-part-1>   (repro + A1 + A2)
//!         ./bin/matcher_attack run2 <state.bin> <csv-part-2>   (A3 + A4 + A5)
//! Threads: exactly 2 compute threads at any time. Each run wall-bounded <= 15 min.

const std = @import("std");
const alien = @import("inv_alien.zig");
const coevo = @import("inv_coevo.zig");
const open = @import("inv_open.zig");
const forge = @import("inv_atomforge.zig");

const V: usize = alien.CANON_BASE; // 4
const PROD_N: usize = 8;
const PROD_L: usize = 28;
const PROD_T: f64 = forge.MATCH_THRESHOLD; // 0.95
const PROD_DEPTH: usize = forge.COMPOSE_DEPTH; // 3
const SEEDS = [_]u64{ 0xA70F, 0x5EED2 };
const POP: usize = 90;
const GENS: usize = 45;
const ROUNDS: usize = 10;
const CENSUS_CAP: usize = 80;
const MAX_CHAIN: usize = 10;

// expected a1a6 promoted lengths (reproduction self-check)
const EXPECT_LEN_A = [_]usize{ 2, 4, 2, 6, 4, 5, 5, 3, 5, 4 };
const EXPECT_LEN_B = [_]usize{ 5, 4, 3, 3, 4, 3, 5, 2, 6, 7 };

fn splitmix(x0: u64) u64 {
    var x = x0 +% 0x9E3779B97F4A7C15;
    x = (x ^ (x >> 30)) *% 0xBF58476D1CE4E5B9;
    x = (x ^ (x >> 27)) *% 0x94D049BB133111EB;
    return x ^ (x >> 31);
}
fn streamSeed(i: usize) u64 {
    return splitmix(0x51F7EED +% @as(u64, i));
}

// ============================================================================
// Core comparison machinery (ports the private matchesChain / chainAgreement
// logic from inv_atomforge.zig, with mismatch-witness capture and early exit)
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

/// Compare prog's stream behaviour against a chain of library atoms on n_seq
/// random streams of length L (identical stream generation to production
/// `matchesChain`). Stops after `stop_mm` mismatches (pass maxInt for full frac).
fn compareChain(prog: *const alien.Program, lib: []const alien.Program, idxs: []const usize, n_seq: usize, L: usize, seed: u64, stop_mm: usize) Cmp {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var tgt: [256]u8 = undefined;
    var got: [256]u8 = undefined;
    var res = Cmp{};
    for (0..n_seq) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        forge.applyChain(lib, idxs, syms[0..L], tgt[0..L]);
        alien.runStream(prog, syms[0..L], got[0..L]);
        for (0..L) |i| {
            res.total += 1;
            if (got[i] == tgt[i]) {
                res.agree += 1;
            } else {
                res.mm += 1;
                if (res.wit == null) {
                    var wt = Witness{ .stream_seed = seed, .pos = i, .exp = tgt[i], .got = got[i] };
                    wt.slen = @min(L, 64);
                    @memcpy(wt.syms[0..wt.slen], syms[0..wt.slen]);
                    res.wit = wt;
                }
                if (res.mm >= stop_mm) return res;
            }
        }
    }
    return res;
}

/// prog-vs-prog comparison through the same observation channel (OUT_R mod 4).
fn progVs(a: *const alien.Program, b: *const alien.Program, n_seq: usize, L: usize, seed: u64, stop_mm: usize) Cmp {
    const lib = [1]alien.Program{b.*};
    const idxs = [1]usize{0};
    return compareChain(a, &lib, &idxs, n_seq, L, seed, stop_mm);
}

const CertOut = struct {
    reducible: bool = false,
    chain: [MAX_CHAIN]usize = undefined,
    chain_len: usize = 0,
    best: f64 = 0, // max agreement frac over all enumerated chains (frac mode only)
    depth_reached: usize = 0, // deepest FULLY completed level (or witness depth)
    complete: bool = true,
    ms: u64 = 0,
};

/// Production-logic certifier, parameterized (n, L, threshold, seed). At the
/// production point (8, 28, 0.95, fseed) this is logically identical to
/// `forge.reducibleLib` (same enumeration order, same per-chain PRNG).
fn certFrac(prog: *const alien.Program, lib: []const alien.Program, max_depth: usize, n_seq: usize, L: usize, thr: f64, seed: u64, cap_ns: u64) CertOut {
    var res = CertOut{};
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
                res.complete = false;
                res.ms = timer.read() / std.time.ns_per_ms;
                return res;
            }
            var idxs: [MAX_CHAIN]usize = undefined;
            var x = idx;
            for (0..d) |j| {
                idxs[j] = x % n;
                x /= n;
            }
            const c = compareChain(prog, lib, idxs[0..d], n_seq, L, seed, std.math.maxInt(usize));
            const f = c.frac();
            if (f > res.best) res.best = f;
            if (f >= thr) {
                res.reducible = true;
                res.chain_len = d;
                @memcpy(res.chain[0..d], idxs[0..d]);
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
/// confirmed exact on an independent seed_b. Early exit on first mismatch makes
/// non-matching chains cost only a few symbols each.
fn certExact(prog: *const alien.Program, lib: []const alien.Program, max_depth: usize, n_seq: usize, L: usize, seed_a: u64, seed_b: u64, cap_ns: u64) CertOut {
    var res = CertOut{};
    var timer = std.time.Timer.start() catch unreachable;
    const n = lib.len;
    if (n == 0) return res;
    var d: usize = 1;
    while (d <= max_depth) : (d += 1) {
        var total: usize = 1;
        for (0..d) |_| total *= n;
        var idx: usize = 0;
        while (idx < total) : (idx += 1) {
            if (idx % 8192 == 0 and timer.read() > cap_ns) {
                res.complete = false;
                res.ms = timer.read() / std.time.ns_per_ms;
                return res;
            }
            var idxs: [MAX_CHAIN]usize = undefined;
            var x = idx;
            for (0..d) |j| {
                idxs[j] = x % n;
                x /= n;
            }
            // cheap gate: the 32-symbol PREFIX of seed_a's first stream (same PRNG
            // sequence, so an exact match can never be rejected here) -- makes
            // non-matching chains cost ~32 symbols instead of n_seq*L.
            const q = compareChain(prog, lib, idxs[0..d], 1, 32, seed_a, 1);
            if (q.mm != 0) continue;
            const a = compareChain(prog, lib, idxs[0..d], n_seq, L, seed_a, 1);
            if (a.mm != 0) continue;
            const b = compareChain(prog, lib, idxs[0..d], n_seq, L, seed_b, 1);
            if (b.mm != 0) continue;
            res.reducible = true;
            res.chain_len = d;
            @memcpy(res.chain[0..d], idxs[0..d]);
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
// Constructed adversaries (attack A1a)
// ============================================================================

/// g_xor with a TRANSIENT +1 deviation exactly when the run of consecutive
/// symbol-3s reaches length k. True accumulator hidden in r4; r3 (OUT_R) gets
/// r4 + trigger. Deviation rate ~ (3/4) * 4^-k per position.
/// r1 is 0 at step time (runStream writes REG_TYP=0 each position).
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

/// Same, deviating when the run length is 2 OR 3 (rate ~5.9% -- just BELOW the
/// 0.95 bar in true agreement; the k=2 version at ~4.7% sits just ABOVE it).
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

/// The HORIZON BOMB: identical to g_xor for the first 28 positions of every
/// stream, then deviates on EVERY position from #29 onward (latched). The
/// production protocol (streams of length 28) can NEVER see the difference --
/// at any threshold, any number of streams, any seed.
fn horizonBomb() alien.Program {
    var p = alien.Program{};
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 11, .imm = 1 });
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 6, .imm = 29 });
    p.step.appendAssumeCapacity(.{ .op = .a_xor, .a = 4, .b = 0, .out = 4 }); // true acc
    p.step.appendAssumeCapacity(.{ .op = .a_add, .a = 8, .b = 11, .out = 8 }); // pos count (1-based)
    p.step.appendAssumeCapacity(.{ .op = .a_eq, .a = 8, .b = 6, .out = 7 }); // pos==29?
    p.step.appendAssumeCapacity(.{ .op = .a_or, .a = 9, .b = 7, .out = 9 }); // latch
    p.step.appendAssumeCapacity(.{ .op = .a_and, .a = 9, .b = 11, .out = 2 }); // 1 after latch
    p.step.appendAssumeCapacity(.{ .op = .a_add, .a = 4, .b = 2, .out = 3 });
    return p;
}

// ============================================================================
// CSV
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

fn chainStr(buf: []u8, chain: []const usize) []const u8 {
    var stream = std.io.fixedBufferStream(buf);
    const wr = stream.writer();
    wr.writeAll("[") catch {};
    for (chain, 0..) |c, i| {
        if (i > 0) wr.writeAll(",") catch {};
        wr.print("{d}", .{c}) catch {};
    }
    wr.writeAll("]") catch {};
    return stream.getWritten();
}

// ============================================================================
// Phase 0: reproduce the a1a6 promotion loop, capturing the census
// ============================================================================

const CensusCand = struct {
    prog: alien.Program,
    reducible: bool,
    chain: [PROD_DEPTH]u8 = [_]u8{0} ** PROD_DEPTH,
    chain_len: u8 = 0,
};

const RoundData = struct {
    lib_before: u8 = 0,
    n_census: u16 = 0,
    promoted_idx: i16 = -1, // census index of the promoted (first irreducible) candidate
    cands: [CENSUS_CAP]CensusCand = undefined,
};

const PromotedAtom = struct { prog: alien.Program, round: usize, prefix_len: usize };

const SeedRepro = struct {
    seed: u64 = 0,
    n_promoted: usize = 0,
    promoted: [ROUNDS]PromotedAtom = undefined,
    final: forge.AtomLib = .{},
    n_rounds: usize = 0,
    rounds: [ROUNDS]RoundData = undefined,
    self_check_mismatch: usize = 0, // certFrac vs forge.reducibleLib disagreements
    self_check_n: usize = 0,
    lengths_ok: bool = false,
    log: std.ArrayList(u8) = undefined,
};

fn runRepro(seed: u64, sr: *SeedRepro) void {
    sr.seed = seed;
    sr.log = std.ArrayList(u8).init(std.heap.page_allocator);
    const lw = sr.log.writer();

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const al = arena_state.allocator();

    const dseed = seed ^ 0x1F0;
    const fseed = seed +% 0xA70F;

    lw.print("\n== repro seed 0x{X} (pop={d} gens={d} rounds={d} depth={d} census<={d}) ==\n", .{ seed, POP, GENS, ROUNDS, PROD_DEPTH, CENSUS_CAP }) catch {};

    var atoms = forge.baseAtoms();
    var n_promoted: usize = 0;

    var round: usize = 1;
    while (round <= ROUNDS) : (round += 1) {
        var timer = std.time.Timer.start() catch unreachable;
        var prng = std.Random.DefaultPrng.init(seed +% round *% 0x9E3779B97F4A7C15);
        var archive = open.search(al, prng.random(), .{ .pop = POP, .gens = GENS, .info = true, .seed = dseed }) catch {
            lw.print("[round {d}] search FAILED\n", .{round}) catch {};
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
        const rd = &sr.rounds[sr.n_rounds];
        rd.lib_before = @intCast(atoms.len);
        rd.n_census = @intCast(n_checked);
        rd.promoted_idx = -1;

        var first_irred: ?alien.Program = null;
        var n_irred: usize = 0;
        for (cleanlist.items[0..n_checked], 0..) |m, ci| {
            // production decision instrument:
            const prod_red = forge.reducibleLib(&m.prog, atoms.slice(), PROD_DEPTH, fseed);
            // witness-capturing port (must agree -- instrument self-check):
            const mine = certFrac(&m.prog, atoms.slice(), PROD_DEPTH, PROD_N, PROD_L, PROD_T, fseed, 60 * std.time.ns_per_s);
            sr.self_check_n += 1;
            if (mine.reducible != prod_red) sr.self_check_mismatch += 1;

            var cand = CensusCand{ .prog = m.prog, .reducible = prod_red };
            if (mine.reducible) {
                cand.chain_len = @intCast(mine.chain_len);
                for (0..mine.chain_len) |j| cand.chain[j] = @intCast(mine.chain[j]);
            }
            rd.cands[ci] = cand;

            if (!prod_red) {
                n_irred += 1;
                if (first_irred == null) {
                    first_irred = m.prog;
                    rd.promoted_idx = @intCast(ci);
                }
            }
        }
        sr.n_rounds += 1;

        if (first_irred == null or atoms.len >= forge.MAX_ATOMS) {
            lw.print("[round {d}] archive={d} clean={d} checked={d} irreducible=0 -> FIXED POINT\n", .{ round, archive.items.len, cleanlist.items.len, n_checked }) catch {};
            archive.deinit();
            _ = arena_state.reset(.retain_capacity);
            break;
        }

        const new_atom = first_irred.?;
        sr.promoted[n_promoted] = .{ .prog = new_atom, .round = round, .prefix_len = atoms.len };
        atoms.appendAssumeCapacity(new_atom);
        n_promoted += 1;

        const ms = timer.read() / std.time.ns_per_ms;
        lw.print("[round {d}] archive={d} clean={d} checked={d} irreducible={d} PROMOTE len={d} -> lib={d} ({d} ms)\n", .{ round, archive.items.len, cleanlist.items.len, n_checked, n_irred, new_atom.len(), atoms.len, ms }) catch {};

        archive.deinit();
        _ = arena_state.reset(.retain_capacity);
    }

    sr.n_promoted = n_promoted;
    sr.final = atoms;

    const expect: []const usize = if (seed == SEEDS[0]) &EXPECT_LEN_A else &EXPECT_LEN_B;
    sr.lengths_ok = (n_promoted == expect.len);
    if (sr.lengths_ok) {
        for (0..n_promoted) |k| {
            if (sr.promoted[k].prog.len() != expect[k]) sr.lengths_ok = false;
        }
    }
    lw.print("repro seed 0x{X}: {d} promoted, lengths-match-a1a6={}, census-instrument mismatches {d}/{d}\n", .{ seed, n_promoted, sr.lengths_ok, sr.self_check_mismatch, sr.self_check_n }) catch {};
}

// ============================================================================
// State (de)serialization -- so run2 doesn't repeat the repro
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

fn saveState(path: []const u8, results: []const *SeedRepro) !void {
    const f = try std.fs.cwd().createFile(path, .{});
    defer f.close();
    var bw = std.io.bufferedWriter(f.writer());
    const w = bw.writer();
    try w.writeInt(u32, 0x4D415431, .little); // "MAT1"
    try w.writeByte(@intCast(results.len));
    for (results) |sr| {
        try w.writeInt(u64, sr.seed, .little);
        try w.writeByte(@intCast(sr.n_promoted));
        for (0..sr.n_promoted) |k| {
            try w.writeByte(@intCast(sr.promoted[k].round));
            try w.writeByte(@intCast(sr.promoted[k].prefix_len));
            try writeProg(w, &sr.promoted[k].prog);
        }
        try w.writeByte(@intCast(sr.final.len));
        for (sr.final.slice()) |*p| try writeProg(w, p);
        try w.writeByte(@intCast(sr.n_rounds));
        for (0..sr.n_rounds) |r_i| {
            const rd = &sr.rounds[r_i];
            try w.writeByte(rd.lib_before);
            try w.writeInt(u16, rd.n_census, .little);
            try w.writeInt(i16, rd.promoted_idx, .little);
            for (0..rd.n_census) |ci| {
                const c = &rd.cands[ci];
                try writeProg(w, &c.prog);
                try w.writeByte(if (c.reducible) 1 else 0);
                try w.writeByte(c.chain_len);
                for (0..PROD_DEPTH) |j| try w.writeByte(c.chain[j]);
            }
        }
    }
    try bw.flush();
}

fn loadState(al: std.mem.Allocator, path: []const u8) ![]*SeedRepro {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    var br = std.io.bufferedReader(f.reader());
    const r = br.reader();
    const magic = try r.readInt(u32, .little);
    if (magic != 0x4D415431) return error.BadState;
    const nres = try r.readByte();
    const out = try al.alloc(*SeedRepro, nres);
    for (0..nres) |i| {
        const sr = try al.create(SeedRepro);
        sr.* = .{};
        sr.seed = try r.readInt(u64, .little);
        sr.n_promoted = try r.readByte();
        for (0..sr.n_promoted) |k| {
            const round = try r.readByte();
            const plen = try r.readByte();
            const prog = try readProg(r);
            sr.promoted[k] = .{ .prog = prog, .round = round, .prefix_len = plen };
        }
        const nfin = try r.readByte();
        sr.final = .{};
        for (0..nfin) |_| sr.final.appendAssumeCapacity(try readProg(r));
        sr.n_rounds = try r.readByte();
        for (0..sr.n_rounds) |r_i| {
            const rd = &sr.rounds[r_i];
            rd.lib_before = try r.readByte();
            rd.n_census = try r.readInt(u16, .little);
            rd.promoted_idx = try r.readInt(i16, .little);
            for (0..rd.n_census) |ci| {
                var c = CensusCand{ .prog = try readProg(r), .reducible = false };
                c.reducible = (try r.readByte()) != 0;
                c.chain_len = try r.readByte();
                for (0..PROD_DEPTH) |j| c.chain[j] = try r.readByte();
                rd.cands[ci] = c;
            }
        }
        out[i] = sr;
    }
    return out;
}

// ============================================================================
// RUN 1: repro + A1 (false-equal) + A2 (false-different)
// ============================================================================

// ---- A1b: random-mutant false-equal hunt (threaded) ----

const FePair = struct {
    prod_frac: f64,
    true_frac: f64,
    wit: Witness,
};

const HuntStats = struct {
    trials: usize = 0,
    alive: usize = 0,
    identical: usize = 0,
    prod_pass: usize = 0,
    exactish: usize = 0, // 0 mismatches in the 4096-symbol stage-1 probe
    gray: usize = 0, // true agreement in [0.95, 1)
    false_equal: usize = 0, // prod pass but true agreement < 0.95
    fes: [16]FePair = undefined,
    n_fes: usize = 0,
};

fn progIdentical(a: *const alien.Program, b: *const alien.Program) bool {
    if (a.setup.len != b.setup.len or a.step.len != b.step.len) return false;
    for (a.setup.slice(), b.setup.slice()) |x, y| {
        if (!std.meta.eql(x, y)) return false;
    }
    for (a.step.slice(), b.step.slice()) |x, y| {
        if (!std.meta.eql(x, y)) return false;
    }
    return true;
}

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

fn huntWorker(rng_seed: u64, trials: usize, fseed: u64, stats: *HuntStats) void {
    var prng = std.Random.DefaultPrng.init(rng_seed);
    const rng = prng.random();
    const sp = alien.Params{ .active_regs = 8, .mem_bias = 0.25 };
    for (0..trials) |_| {
        stats.trials += 1;
        const base = alien.randProg(rng, &sp);
        if (!isAlive(&base)) continue;
        stats.alive += 1;
        var mut = base;
        const nmut = 1 + rng.uintLessThan(usize, 3);
        for (0..nmut) |_| alien.mutate(rng, &mut, &sp);
        if (progIdentical(&base, &mut)) {
            stats.identical += 1;
            continue;
        }
        const prod = progVs(&mut, &base, PROD_N, PROD_L, fseed, std.math.maxInt(usize));
        if (prod.frac() < PROD_T) continue;
        stats.prod_pass += 1;
        const s1 = progVs(&mut, &base, 64, 64, 0xD00D1, std.math.maxInt(usize));
        if (s1.mm == 0) {
            stats.exactish += 1;
            continue;
        }
        const full = progVs(&mut, &base, 1024, 96, 0xD00D2, std.math.maxInt(usize));
        if (full.frac() < PROD_T) {
            stats.false_equal += 1;
            if (stats.n_fes < stats.fes.len) {
                stats.fes[stats.n_fes] = .{ .prod_frac = prod.frac(), .true_frac = full.frac(), .wit = full.wit.? };
                stats.n_fes += 1;
            }
        } else {
            stats.gray += 1;
        }
    }
}

// ---- A1c: census audit job (threaded) ----

const CensusAudit = struct {
    seed_idx: usize,
    round: usize,
    ci: usize,
    true_frac: f64 = -1,
    mm: usize = 0,
    wit: ?Witness = null,
};

fn censusAuditWorker(jobs: []CensusAudit, results: []const *SeedRepro, start: usize, stride: usize) void {
    var i = start;
    while (i < jobs.len) : (i += stride) {
        const j = &jobs[i];
        const sr = results[j.seed_idx];
        const rd = &sr.rounds[j.round];
        const cand = &rd.cands[j.ci];
        var idxs: [PROD_DEPTH]usize = undefined;
        for (0..cand.chain_len) |k| idxs[k] = cand.chain[k];
        const lib = sr.final.slice()[0..rd.lib_before];
        const c = compareChain(&cand.prog, lib, idxs[0..cand.chain_len], 1024, 96, 0xD00D3, std.math.maxInt(usize));
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

    // ---------------- Phase 0: reproduction (2 threads) ----------------
    try out.writeAll("=== MATCHER ATTACK run1: repro + false-equal + false-different ===\n");
    const sr_a = try al.create(SeedRepro);
    const sr_b = try al.create(SeedRepro);
    sr_a.* = .{};
    sr_b.* = .{};
    {
        const ta = try std.Thread.spawn(.{}, runRepro, .{ SEEDS[0], sr_a });
        const tb = try std.Thread.spawn(.{}, runRepro, .{ SEEDS[1], sr_b });
        ta.join();
        tb.join();
    }
    try out.writeAll(sr_a.log.items);
    try out.writeAll(sr_b.log.items);
    sr_a.log.deinit();
    sr_b.log.deinit();
    const results = [_]*SeedRepro{ sr_a, sr_b };
    for (results) |sr| {
        const note = std.fmt.bufPrint(&nbuf, "lengths_match_a1a6={};census_selfcheck_mismatch={d}/{d}", .{ sr.lengths_ok, sr.self_check_mismatch, sr.self_check_n }) catch "";
        const item = std.fmt.bufPrint(&wbuf, "0x{X}", .{sr.seed}) catch "";
        csv.row("repro", item, "promotion_loop", PROD_DEPTH, PROD_N, PROD_L, PROD_T, sr.n_rounds, @floatFromInt(sr.n_promoted), if (sr.lengths_ok) 1 else 0, @floatFromInt(sr.self_check_mismatch), @floatFromInt(sr.self_check_n), "", note);
    }
    try saveState(state_path, &results);
    try out.print("[state saved to {s}; elapsed {d} ms]\n", .{ state_path, total_timer.read() / std.time.ns_per_ms });

    // ---------------- A1a: constructed adversaries ----------------
    try out.writeAll("\n=== A1a CONSTRUCTED FALSE-EQUAL ADVERSARIES (vs g_xor, production protocol) ===\n");
    const base5 = forge.baseAtoms();
    const gxor_idxs = [1]usize{0};
    const fseed_a = SEEDS[0] +% 0xA70F;
    const fseed_b = SEEDS[1] +% 0xA70F;
    const dseed_a = SEEDS[0] ^ 0x1F0;

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

    try out.writeAll("  name          prodA prodB  pass500  TA(96)    TA(256)   clean  reducibleLib@d3  witness\n");
    for (&devs) |*ds| {
        const p = &ds.prog;
        const prod_a_pass = compareChain(p, base5.slice(), &gxor_idxs, PROD_N, PROD_L, fseed_a, std.math.maxInt(usize)).frac() >= PROD_T;
        const prod_b_pass = compareChain(p, base5.slice(), &gxor_idxs, PROD_N, PROD_L, fseed_b, std.math.maxInt(usize)).frac() >= PROD_T;
        var npass: usize = 0;
        const NSW = 500;
        for (0..NSW) |i| {
            if (compareChain(p, base5.slice(), &gxor_idxs, PROD_N, PROD_L, streamSeed(i), std.math.maxInt(usize)).frac() >= PROD_T) npass += 1;
        }
        const ta96 = compareChain(p, base5.slice(), &gxor_idxs, 1024, 96, 0xFA15E, std.math.maxInt(usize));
        const ta256 = compareChain(p, base5.slice(), &gxor_idxs, 256, 256, 0xFA15F, std.math.maxInt(usize));
        const is_clean = forge.clean(p, dseed_a);
        const red = forge.reducibleLib(p, base5.slice(), PROD_DEPTH, fseed_a);

        // constructed witness stream: enough symbol-3s (or zeros past the horizon)
        var wsyms: [64]u8 = [_]u8{0} ** 64;
        if (!std.mem.eql(u8, ds.name, "horizon_bomb")) {
            for (0..10) |i| wsyms[i] = 3;
        }
        var tgt: [64]u8 = undefined;
        var got: [64]u8 = undefined;
        forge.applyChain(base5.slice(), &gxor_idxs, &wsyms, &tgt);
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
        const note = std.fmt.bufPrint(&nbuf, "clean={};reducibleLib_d3={};prodB_pass={}", .{ is_clean, red, prod_b_pass }) catch "";
        csv.row("A1_constructed", ds.name, "vs_gxor_chain0", 1, PROD_N, PROD_L, PROD_T, NSW, if (prod_a_pass) 1 else 0, pass_rate, ta96.frac(), ta256.frac(), ws, note);
        try out.print("  {s:<13} {s:<5} {s:<5} {d:.3}    {d:.6}  {d:.6}  {}   {}   {s}\n", .{ ds.name, if (prod_a_pass) "PASS" else "fail", if (prod_b_pass) "PASS" else "fail", pass_rate, ta96.frac(), ta256.frac(), is_clean, red, ws });
    }

    // ---------------- A1b: random-mutant hunt (2 threads) ----------------
    try out.writeAll("\n=== A1b RANDOM-MUTANT FALSE-EQUAL HUNT ===\n");
    const TRIALS: usize = 120_000;
    var hs1 = HuntStats{};
    var hs2 = HuntStats{};
    {
        const t1 = try std.Thread.spawn(.{}, huntWorker, .{ 0x7A57A11, TRIALS / 2, fseed_a, &hs1 });
        const t2 = try std.Thread.spawn(.{}, huntWorker, .{ 0x7A57B22, TRIALS / 2, fseed_a, &hs2 });
        t1.join();
        t2.join();
    }
    const h_trials = hs1.trials + hs2.trials;
    const h_alive = hs1.alive + hs2.alive;
    const h_pass = hs1.prod_pass + hs2.prod_pass;
    const h_exact = hs1.exactish + hs2.exactish;
    const h_gray = hs1.gray + hs2.gray;
    const h_fe = hs1.false_equal + hs2.false_equal;
    try out.print("  trials={d} alive={d} identical={d} prod_pass={d} exactish={d} gray={d} FALSE-EQUAL={d}\n", .{ h_trials, h_alive, hs1.identical + hs2.identical, h_pass, h_exact, h_gray, h_fe });
    {
        const note = std.fmt.bufPrint(&nbuf, "alive={d};identical={d};exactish(0mm@4096)={d}", .{ h_alive, hs1.identical + hs2.identical, h_exact }) catch "";
        csv.row("A1_random", "aggregate", "mutant_pairs", 0, PROD_N, PROD_L, PROD_T, h_trials, @floatFromInt(h_pass), @floatFromInt(h_fe), @floatFromInt(h_gray), @floatFromInt(h_exact), "", note);
    }
    for ([_]*HuntStats{ &hs1, &hs2 }) |hs| {
        for (hs.fes[0..hs.n_fes], 0..) |fe, i| {
            const item = std.fmt.bufPrint(&cbuf, "fe_pair_{d}", .{i}) catch "";
            const ws = witnessStr(&wbuf, fe.wit);
            csv.row("A1_random", item, "false_equal", 0, PROD_N, PROD_L, PROD_T, 1, fe.prod_frac, fe.true_frac, 0, 0, ws, "prod>=0.95 but true<0.95; witness independently generated");
            try out.print("  FE: prod={d:.4} true={d:.4} {s}\n", .{ fe.prod_frac, fe.true_frac, ws });
        }
    }

    // ---------------- A1c: audit of the real a1a6 census reducible verdicts ----------------
    try out.writeAll("\n=== A1c CENSUS AUDIT: true agreement of every production 'reducible' verdict ===\n");
    var jobs = std.ArrayList(CensusAudit).init(al);
    defer jobs.deinit();
    for (results, 0..) |sr, si| {
        for (0..sr.n_rounds) |r_i| {
            const rd = &sr.rounds[r_i];
            for (0..rd.n_census) |ci| {
                if (rd.cands[ci].reducible and rd.cands[ci].chain_len > 0) {
                    try jobs.append(.{ .seed_idx = si, .round = r_i, .ci = ci });
                }
            }
        }
    }
    {
        const res_slice: []const *SeedRepro = &results;
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
    var n_fe_rows: usize = 0;
    for (jobs.items) |j| {
        try fracs.append(j.true_frac);
        if (j.mm == 0) {
            n_exact += 1;
        } else if (j.true_frac >= PROD_T) {
            n_gray += 1;
        } else {
            n_fe += 1;
            if (n_fe_rows < 40) {
                n_fe_rows += 1;
                const sr = results[j.seed_idx];
                const rd = &sr.rounds[j.round];
                var idxs: [PROD_DEPTH]usize = undefined;
                for (0..rd.cands[j.ci].chain_len) |k| idxs[k] = rd.cands[j.ci].chain[k];
                const cs = chainStr(&cbuf, idxs[0..rd.cands[j.ci].chain_len]);
                const item = std.fmt.bufPrint(&nbuf, "0x{X}_r{d}_c{d}", .{ sr.seed, j.round + 1, j.ci }) catch "";
                var wb2: [160]u8 = undefined;
                const ws = if (j.wit) |w| witnessStr(&wb2, w) else "";
                csv.row("A1_census_fe", item, cs, PROD_DEPTH, PROD_N, PROD_L, PROD_T, 1, j.true_frac, @floatFromInt(j.mm), @floatFromInt(rd.lib_before), 0, ws, "production census said reducible; true agreement < 0.95");
            }
        }
    }
    std.mem.sort(f64, fracs.items, {}, std.sort.asc(f64));
    const med = if (fracs.items.len > 0) fracs.items[fracs.items.len / 2] else 0;
    const minf = if (fracs.items.len > 0) fracs.items[0] else 0;
    try out.print("  reducible verdicts audited={d}: exact={d} gray[0.95,1)={d} FALSE-EQUAL(<0.95)={d} (min={d:.4} med={d:.4})\n", .{ jobs.items.len, n_exact, n_gray, n_fe, minf, med });
    {
        const note = std.fmt.bufPrint(&nbuf, "min_true={d:.6};median_true={d:.6}", .{ minf, med }) catch "";
        csv.row("A1_census", "aggregate", "all_production_reducible_verdicts", PROD_DEPTH, PROD_N, PROD_L, PROD_T, jobs.items.len, @floatFromInt(n_exact), @floatFromInt(n_gray), @floatFromInt(n_fe), med, "", note);
    }

    // ---------------- A2: false-different hunt ----------------
    try out.writeAll("\n=== A2 FALSE-DIFFERENT: extensionally-equal pairs under the production protocol ===\n");
    {
        var prng = std.Random.DefaultPrng.init(0xEC0A1);
        const rng = prng.random();
        const sp = alien.Params{ .active_regs = 8, .mem_bias = 0.25 };
        var n_pairs: usize = 0;
        var n_ver_fail: usize = 0;
        var n_below: usize = 0;
        var min_frac: f64 = 1.0;
        var attempts: usize = 0;
        while (n_pairs < 900 and attempts < 20000) : (attempts += 1) {
            const base = alien.randProg(rng, &sp);
            if (!isAlive(&base)) continue;
            // find a register never referenced by the program and not 0,1,3,5
            var used = [_]bool{false} ** alien.R;
            used[0] = true;
            used[1] = true;
            used[3] = true;
            used[5] = true;
            for (base.setup.slice()) |ins| {
                used[ins.a % alien.R] = true;
                used[ins.b % alien.R] = true;
                used[ins.c % alien.R] = true;
                used[ins.out % alien.R] = true;
            }
            for (base.step.slice()) |ins| {
                used[ins.a % alien.R] = true;
                used[ins.b % alien.R] = true;
                used[ins.c % alien.R] = true;
                used[ins.out % alien.R] = true;
            }
            var free_reg: ?u8 = null;
            for (0..alien.R) |ri| {
                if (!used[ri]) {
                    free_reg = @intCast(ri);
                    break;
                }
            }
            for (0..3) |variant| {
                var v = base;
                switch (variant) {
                    0 => { // append a nop
                        if (v.step.len >= alien.MAX_INSTR) continue;
                        v.step.appendAssumeCapacity(.{ .op = .nop });
                    },
                    1 => { // dead self-move on an unused register
                        if (free_reg == null or v.step.len >= alien.MAX_INSTR) continue;
                        v.step.appendAssumeCapacity(.{ .op = .a_mov, .a = free_reg.?, .out = free_reg.? });
                    },
                    else => { // dead constant into an unused register (setup)
                        if (free_reg == null or v.setup.len >= alien.MAX_INSTR) continue;
                        v.setup.appendAssumeCapacity(.{ .op = .a_set, .out = free_reg.?, .imm = 42 });
                    },
                }
                // verify extensional equality on a large sample (construction guarantees it)
                const ver = progVs(&v, &base, 256, 128, 0xEC0A2, 1);
                if (ver.mm != 0) {
                    n_ver_fail += 1;
                    continue;
                }
                n_pairs += 1;
                // production protocol across 100 stream seeds
                for (0..100) |i| {
                    const f = progVs(&v, &base, PROD_N, PROD_L, streamSeed(1000 + i), std.math.maxInt(usize)).frac();
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
            const ta = compareChain(&ns.prog, base5.slice(), &gxor_idxs, 1024, 96, 0xFA15E, std.math.maxInt(usize)).frac();
            var npass: usize = 0;
            const NSW = 2000;
            for (0..NSW) |i| {
                if (compareChain(&ns.prog, base5.slice(), &gxor_idxs, PROD_N, PROD_L, streamSeed(3000 + i), std.math.maxInt(usize)).frac() >= PROD_T) npass += 1;
            }
            const pr = @as(f64, @floatFromInt(npass)) / @as(f64, NSW);
            try out.print("  {s:<22} true={d:.4} pass_rate={d:.4} (verdict flips seed-to-seed)\n", .{ ns.name, ta, pr });
            csv.row("A2_nearband", ns.name, "vs_gxor_chain0", 1, PROD_N, PROD_L, PROD_T, NSW, ta, pr, 1.0 - pr, 0, "", "true agreement straddles the threshold; verdict is stream-seed noise");
        }
    }

    try out.print("\n[run1 total elapsed {d} ms]\n", .{total_timer.read() / std.time.ns_per_ms});
}

// ============================================================================
// RUN 2: A3 seed-flip sweeps + A4 ROC + A5 corrected-protocol verdicts
// ============================================================================

const SweepJob = struct {
    prog: *const alien.Program,
    lib: []const alien.Program,
    depth: usize,
    n_seq: usize,
    L: usize,
    thr: f64,
    seed: u64,
    cap_ns: u64,
    group: usize,
    result: CertOut = .{},
};

fn sweepWorker(jobs: []SweepJob, start: usize, stride: usize) void {
    var i = start;
    while (i < jobs.len) : (i += stride) {
        const j = &jobs[i];
        j.result = certFrac(j.prog, j.lib, j.depth, j.n_seq, j.L, j.thr, j.seed, j.cap_ns);
    }
}

// ---- A4 ROC machinery ----

const N_CELLS: usize = 11;
const CELLS = [N_CELLS][2]usize{
    .{ 8, 28 }, .{ 16, 28 }, .{ 32, 28 }, .{ 64, 28 },
    .{ 8, 64 }, .{ 16, 64 }, .{ 32, 64 }, .{ 64, 64 },
    .{ 16, 128 }, .{ 32, 128 }, .{ 64, 128 },
};
const N_THR: usize = 4; // 0.95, 0.97, 0.99, exact(1.0)
const THRS = [_]f64{ 0.95, 0.97, 0.99, 1.0 };
const N_CLASS: usize = 4; // 0=DIFF 1=GRAY 2=EQ0 3=EQSYN

const LabeledPair = struct {
    a: alien.Program,
    b: alien.Program,
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
        counts.total[p.class] += ROC_EVAL_SEEDS;
        for (CELLS, 0..) |cell, ci| {
            for (0..ROC_EVAL_SEEDS) |si| {
                const c = progVs(&p.a, &p.b, cell[0], cell[1], splitmix(0xE7A1 +% @as(u64, si)), std.math.maxInt(usize));
                const f = c.frac();
                for (THRS, 0..) |t, ti| {
                    const pass = if (ti == N_THR - 1) (c.mm == 0) else (f >= t);
                    if (pass) counts.pass[ci][ti][p.class] += 1;
                }
            }
        }
    }
}

fn doRun2(al: std.mem.Allocator, state_path: []const u8, csv_path: []const u8, skip_a3: bool, skip_a4: bool) !void {
    const out = std.io.getStdOut().writer();
    var csv = try CsvW.init(csv_path, false);
    defer csv.close();
    var nbuf: [256]u8 = undefined;
    var cbuf: [64]u8 = undefined;
    var ibuf: [64]u8 = undefined;

    var total_timer = try std.time.Timer.start();

    const results = try loadState(al, state_path);
    try out.print("=== MATCHER ATTACK run2: loaded state ({d} seeds) ===\n", .{results.len});
    for (results) |sr| {
        try out.print("  seed 0x{X}: {d} promoted, final lib {d}, {d} census rounds\n", .{ sr.seed, sr.n_promoted, sr.final.len, sr.n_rounds });
    }

    const base5 = forge.baseAtoms();
    const dc = coevo.distinctCountProg();

    // ---------------- A3: seed-flip sweeps ----------------
    try out.writeAll("\n=== A3 SEED-FLIP: production verdicts under alternative stream draws ===\n");

    const GroupMeta = struct {
        name: [40]u8 = [_]u8{0} ** 40,
        depth: usize,
        expected_irreducible: bool = true,
        n_jobs: usize = 0,
        flips: usize = 0,
        incomplete: usize = 0,
        bests: [128]f64 = undefined,
        n_bests: usize = 0,
        flip_seed: u64 = 0,
        flip_chain: [MAX_CHAIN]usize = undefined,
        flip_chain_len: usize = 0,
    };
    var groups = std.ArrayList(GroupMeta).init(al);
    defer groups.deinit();
    var jobs = std.ArrayList(SweepJob).init(al);
    defer jobs.deinit();

    // prefix libraries for the 20 atoms (heap-stable)
    var prefix_libs = std.ArrayList([]alien.Program).init(al);
    defer prefix_libs.deinit();

    const N_D3: usize = 100;
    const N_D4: usize = 16;

    for (results) |sr| {
        for (0..sr.n_promoted) |k| {
            const pa = &sr.promoted[k];
            const plib = try al.alloc(alien.Program, pa.prefix_len);
            for (0..pa.prefix_len) |j| plib[j] = sr.final.slice()[j];
            try prefix_libs.append(plib);

            // group: depth 3, 100 seeds (seed 0 = the production fseed)
            var g3 = GroupMeta{ .depth = PROD_DEPTH };
            _ = std.fmt.bufPrint(&g3.name, "0x{X}_inv{d}_d3", .{ sr.seed, k }) catch {};
            const g3i = groups.items.len;
            try groups.append(g3);
            for (0..N_D3) |i| {
                const s = if (i == 0) sr.seed +% 0xA70F else streamSeed(7000 + i);
                try jobs.append(.{ .prog = &sr.promoted[k].prog, .lib = plib, .depth = PROD_DEPTH, .n_seq = PROD_N, .L = PROD_L, .thr = PROD_T, .seed = s, .cap_ns = 15 * std.time.ns_per_s, .group = g3i });
            }
            // group: depth 4, 16 seeds
            var g4 = GroupMeta{ .depth = PROD_DEPTH + 1 };
            _ = std.fmt.bufPrint(&g4.name, "0x{X}_inv{d}_d4", .{ sr.seed, k }) catch {};
            const g4i = groups.items.len;
            try groups.append(g4);
            for (0..N_D4) |i| {
                const s = if (i == 0) sr.seed +% 0xA70F else streamSeed(8000 + i);
                try jobs.append(.{ .prog = &sr.promoted[k].prog, .lib = plib, .depth = PROD_DEPTH + 1, .n_seq = PROD_N, .L = PROD_L, .thr = PROD_T, .seed = s, .cap_ns = 30 * std.time.ns_per_s, .group = g4i });
            }
        }
    }

    // kill-test groups (distinct-count must stay IRREDUCIBLE)
    const KillSpec = struct { name: []const u8, lib: []const alien.Program, depth: usize, n_seeds: usize, cap_s: u64 };
    var kill_specs = std.ArrayList(KillSpec).init(al);
    defer kill_specs.deinit();
    try kill_specs.append(.{ .name = "dc_base5_d3", .lib = base5.slice(), .depth = 3, .n_seeds = 100, .cap_s = 10 });
    try kill_specs.append(.{ .name = "dc_base5_d4", .lib = base5.slice(), .depth = 4, .n_seeds = 100, .cap_s = 10 });
    try kill_specs.append(.{ .name = "dc_base5_d5", .lib = base5.slice(), .depth = 5, .n_seeds = 100, .cap_s = 15 });
    try kill_specs.append(.{ .name = "dc_base5_d6", .lib = base5.slice(), .depth = 6, .n_seeds = 64, .cap_s = 25 });
    try kill_specs.append(.{ .name = "dc_base5_d7", .lib = base5.slice(), .depth = 7, .n_seeds = 32, .cap_s = 50 });
    try kill_specs.append(.{ .name = "dc_base5_d8", .lib = base5.slice(), .depth = 8, .n_seeds = 16, .cap_s = 90 });
    for (results) |sr| {
        const nm = try std.fmt.allocPrint(al, "dc_final{X}_d3", .{sr.seed});
        try kill_specs.append(.{ .name = nm, .lib = sr.final.slice(), .depth = 3, .n_seeds = 100, .cap_s = 15 });
        const nm4 = try std.fmt.allocPrint(al, "dc_final{X}_d4", .{sr.seed});
        try kill_specs.append(.{ .name = nm4, .lib = sr.final.slice(), .depth = 4, .n_seeds = 16, .cap_s = 30 });
    }
    for (kill_specs.items) |ks| {
        var g = GroupMeta{ .depth = ks.depth };
        _ = std.fmt.bufPrint(&g.name, "{s}", .{ks.name}) catch {};
        const gi = groups.items.len;
        try groups.append(g);
        for (0..ks.n_seeds) |i| {
            const s = if (i == 0) SEEDS[0] +% 0xA70F else if (i == 1) SEEDS[1] +% 0xA70F else streamSeed(9000 + i);
            try jobs.append(.{ .prog = &dc, .lib = ks.lib, .depth = ks.depth, .n_seq = PROD_N, .L = PROD_L, .thr = PROD_T, .seed = s, .cap_ns = ks.cap_s * std.time.ns_per_s, .group = gi });
        }
    }

    if (skip_a3) {
        try out.writeAll("  [A3 sweep SKIPPED (run3 mode -- rows already in csv part from the timed-out run)]\n");
        jobs.clearRetainingCapacity();
    } else {
        try out.print("  [{d} sweep jobs across {d} groups on 2 threads...]\n", .{ jobs.items.len, groups.items.len });
        const t1 = try std.Thread.spawn(.{}, sweepWorker, .{ jobs.items, 0, 2 });
        const t2 = try std.Thread.spawn(.{}, sweepWorker, .{ jobs.items, 1, 2 });
        t1.join();
        t2.join();
    }

    // aggregate
    for (jobs.items) |j| {
        const g = &groups.items[j.group];
        g.n_jobs += 1;
        if (!j.result.complete) g.incomplete += 1;
        if (j.result.reducible) {
            if (g.flips == 0) {
                g.flip_seed = j.seed;
                g.flip_chain_len = j.result.chain_len;
                @memcpy(g.flip_chain[0..j.result.chain_len], j.result.chain[0..j.result.chain_len]);
            }
            g.flips += 1;
        }
        if (g.n_bests < g.bests.len) {
            g.bests[g.n_bests] = j.result.best;
            g.n_bests += 1;
        }
    }

    try out.writeAll("  group                      seeds flips incomplete best_min best_med best_max\n");
    var total_atom_flips_d3: usize = 0;
    var total_atom_flips_d4: usize = 0;
    for (groups.items) |*g| {
        const bs = g.bests[0..g.n_bests];
        std.mem.sort(f64, bs, {}, std.sort.asc(f64));
        const bmin = if (bs.len > 0) bs[0] else 0;
        const bmed = if (bs.len > 0) bs[bs.len / 2] else 0;
        const bmax = if (bs.len > 0) bs[bs.len - 1] else 0;
        const gname = std.mem.sliceTo(&g.name, 0);
        try out.print("  {s:<26} {d:>5} {d:>5} {d:>10} {d:.4}   {d:.4}   {d:.4}\n", .{ gname, g.n_jobs, g.flips, g.incomplete, bmin, bmed, bmax });
        const is_atom = std.mem.indexOf(u8, gname, "_inv") != null;
        if (is_atom and g.depth == 3) total_atom_flips_d3 += g.flips;
        if (is_atom and g.depth == 4) total_atom_flips_d4 += g.flips;
        var flip_note: []const u8 = "";
        var wb: [96]u8 = undefined;
        if (g.flips > 0) {
            // verify the first flip chain's true agreement (is the flip a real
            // reduction production missed, or the alternative seed's false-equal?)
            var fj: ?*const SweepJob = null;
            for (jobs.items) |*j| {
                if (j.group < groups.items.len and &groups.items[j.group] == g and j.result.reducible) {
                    fj = j;
                    break;
                }
            }
            if (fj) |j| {
                const ta = compareChain(j.prog, j.lib, j.result.chain[0..j.result.chain_len], 1024, 96, 0xD00D6, std.math.maxInt(usize)).frac();
                const cls = if (ta >= PROD_T) "PRODUCTION-MISSED-REAL-REDUCTION" else "FLIP-SEED-FALSE-EQUAL";
                flip_note = std.fmt.bufPrint(&nbuf, "first_flip_seed=0x{X};chain={s};chain_true_agree={d:.4};class={s}", .{ g.flip_seed, chainStr(&wb, g.flip_chain[0..g.flip_chain_len]), ta, cls }) catch "";
                try out.print("      FLIP {s}\n", .{flip_note});
            }
        }
        csv.row("A3_seedflip", gname, if (is_atom) "prefix" else "killtest", g.depth, PROD_N, PROD_L, PROD_T, g.n_jobs, @floatFromInt(g.flips), bmin, bmed, bmax, "", flip_note);
    }
    try out.print("  TOTAL atom-verdict flips: d3={d}/(20x{d}) d4={d}/(20x{d})\n", .{ total_atom_flips_d3, N_D3, total_atom_flips_d4, N_D4 });

    // known witness chains across seeds (depth-attack flip + redundancy witnesses)
    try out.writeAll("\n  known witness chains across 100 seeds (agreement min/med/max):\n");
    {
        const WitSpec = struct { name: []const u8, seed_idx: usize, atom: usize, use_prefix: bool, chain: []const usize };
        const wspecs = [_]WitSpec{
            .{ .name = "inv8_prefix_d4_[5,9,6,0]", .seed_idx = 1, .atom = 8, .use_prefix = true, .chain = &.{ 5, 9, 6, 0 } },
            .{ .name = "inv0_minus_self_[5,9,10]", .seed_idx = 1, .atom = 0, .use_prefix = false, .chain = &.{ 5, 9, 10 } },
            .{ .name = "inv5_minus_self_[10,5,11]", .seed_idx = 1, .atom = 5, .use_prefix = false, .chain = &.{ 10, 5, 11 } },
        };
        for (wspecs) |ws| {
            const sr = results[ws.seed_idx];
            const pa = &sr.promoted[ws.atom];
            var lib = std.ArrayList(alien.Program).init(al);
            defer lib.deinit();
            if (ws.use_prefix) {
                for (0..pa.prefix_len) |j| try lib.append(sr.final.slice()[j]);
            } else {
                const self_idx = forge.BASE_ATOMS + ws.atom;
                for (0..sr.final.len) |j| {
                    if (j != self_idx) try lib.append(sr.final.slice()[j]);
                }
            }
            var mn: f64 = 1;
            var mx: f64 = 0;
            var npass: usize = 0;
            for (0..100) |i| {
                const f = compareChain(&pa.prog, lib.items, ws.chain, PROD_N, PROD_L, streamSeed(11000 + i), std.math.maxInt(usize)).frac();
                if (f < mn) mn = f;
                if (f > mx) mx = f;
                if (f >= PROD_T) npass += 1;
            }
            const ex = compareChain(&pa.prog, lib.items, ws.chain, 64, 256, 0xEEE1, 1);
            try out.print("    {s:<28} pass {d}/100  min={d:.4} max={d:.4} exact@16384={}\n", .{ ws.name, npass, mn, mx, ex.mm == 0 });
            csv.row("A3_witness", ws.name, "known_flip_witness", ws.chain.len, PROD_N, PROD_L, PROD_T, 100, @floatFromInt(npass), mn, mx, if (ex.mm == 0) 1 else 0, "", "pass count across 100 seeds; m4=exact on 64x256");
        }
    }

    try out.print("\n[A3 done at {d} ms]\n", .{total_timer.read() / std.time.ns_per_ms});

    // ---------------- A4: ROC over labeled pairs ----------------
    if (!skip_a4) {
    try out.writeAll("\n=== A4 PROTOCOL ROC (labeled pairs x protocol grid) ===\n");
    var pairs = std.ArrayList(LabeledPair).init(al);
    defer pairs.deinit();
    {
        var prng = std.Random.DefaultPrng.init(0x0C0FFEE);
        const rng = prng.random();
        const sp = alien.Params{ .active_regs = 8, .mem_bias = 0.25 };
        // natural mutant pairs, labeled by 98k-symbol true agreement
        var made: usize = 0;
        while (made < 2200) {
            const base = alien.randProg(rng, &sp);
            if (!isAlive(&base)) continue;
            var mut = base;
            const nm = 1 + rng.uintLessThan(usize, 3);
            for (0..nm) |_| alien.mutate(rng, &mut, &sp);
            if (progIdentical(&base, &mut)) continue;
            const full = progVs(&mut, &base, 1024, 96, 0xD00D7, std.math.maxInt(usize));
            const f = full.frac();
            const class: usize = if (full.mm == 0) 2 else if (f >= PROD_T) 1 else 0;
            try pairs.append(.{ .a = mut, .b = base, .class = class, .true_frac = f });
            made += 1;
        }
        // syntactic-equal pairs (provably extensionally equal)
        var eq_made: usize = 0;
        while (eq_made < 300) {
            const base = alien.randProg(rng, &sp);
            if (!isAlive(&base) or base.step.len >= alien.MAX_INSTR) continue;
            var v = base;
            v.step.appendAssumeCapacity(.{ .op = .nop });
            try pairs.append(.{ .a = v, .b = base, .class = 3, .true_frac = 1.0 });
            eq_made += 1;
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
    try out.print("  labeled pairs: DIFF={d} GRAY={d} EQ0={d} EQSYN={d} (x{d} eval seeds)\n", .{ counts.total[0] / ROC_EVAL_SEEDS, counts.total[1] / ROC_EVAL_SEEDS, counts.total[2] / ROC_EVAL_SEEDS, counts.total[3] / ROC_EVAL_SEEDS, ROC_EVAL_SEEDS });
    try out.writeAll("  cell        thr    FE(DIFF-pass) GRAY-pass  det(EQ0)  det(EQSYN)\n");
    for (CELLS, 0..) |cell, ci| {
        for (THRS, 0..) |t, ti| {
            const fe = @as(f64, @floatFromInt(counts.pass[ci][ti][0])) / @as(f64, @floatFromInt(@max(1, counts.total[0])));
            const gp = @as(f64, @floatFromInt(counts.pass[ci][ti][1])) / @as(f64, @floatFromInt(@max(1, counts.total[1])));
            const d0 = @as(f64, @floatFromInt(counts.pass[ci][ti][2])) / @as(f64, @floatFromInt(@max(1, counts.total[2])));
            const ds = @as(f64, @floatFromInt(counts.pass[ci][ti][3])) / @as(f64, @floatFromInt(@max(1, counts.total[3])));
            const item = std.fmt.bufPrint(&ibuf, "n{d}_L{d}", .{ cell[0], cell[1] }) catch "";
            csv.row("A4_roc", item, "labeled_pairs", 0, cell[0], cell[1], t, counts.total[0] + counts.total[2] + counts.total[3], fe, gp, d0, ds, "", "m1=FE_rate(DIFF pass) m2=GRAY pass m3=det EQ0 m4=det EQSYN");
            if (ti == 0 or ti == N_THR - 1) {
                try out.print("  n{d:<3}L{d:<4} {d:.2}   {d:.6}      {d:.4}    {d:.4}    {d:.4}\n", .{ cell[0], cell[1], t, fe, gp, d0, ds });
            }
        }
    }

    // deviator ladder against the grid (300 seeds/cell) + recommended cell (2000)
    try out.writeAll("\n  deviator ladder pass rates (constructed rare-pattern adversaries):\n");
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
        const gxor_idxs2 = [1]usize{0};
        // representative cells: production, mid, large, exact-recommended
        const ladder_cells = [_][2]usize{ .{ 8, 28 }, .{ 32, 64 }, .{ 64, 128 }, .{ 64, 256 } };
        for (&devs2) |*ds| {
            for (ladder_cells) |cell| {
                var pass95: usize = 0;
                var pass_exact: usize = 0;
                const NS: usize = if (cell[1] == 256) 2000 else 300;
                for (0..NS) |i| {
                    const c = compareChain(&ds.prog, base5.slice(), &gxor_idxs2, cell[0], cell[1], streamSeed(20000 + i), std.math.maxInt(usize));
                    if (c.frac() >= PROD_T) pass95 += 1;
                    if (c.mm == 0) pass_exact += 1;
                }
                const p95 = @as(f64, @floatFromInt(pass95)) / @as(f64, @floatFromInt(NS));
                const pex = @as(f64, @floatFromInt(pass_exact)) / @as(f64, @floatFromInt(NS));
                const item = std.fmt.bufPrint(&ibuf, "{s}_n{d}_L{d}", .{ ds.name, cell[0], cell[1] }) catch "";
                csv.row("A4_ladder", item, "vs_gxor_chain0", 1, cell[0], cell[1], PROD_T, NS, p95, pex, 0, 0, "", "m1=pass@0.95 m2=pass@exact");
                if (cell[1] >= 128) {
                    try out.print("    {s:<14} n{d}xL{d}: pass@0.95={d:.4} pass@exact={d:.4}\n", .{ ds.name, cell[0], cell[1], p95, pex });
                }
            }
        }
    }

    // cost measurement: production census vs corrected-exact census on one real atom
    try out.writeAll("\n  protocol cost (census of one promoted atom vs 14-atom library):\n");
    {
        const sr = results[1];
        const pa = &sr.promoted[8]; // inv8, the depth-attack atom
        var lib = std.ArrayList(alien.Program).init(al);
        defer lib.deinit();
        for (0..pa.prefix_len) |j| try lib.append(sr.final.slice()[j]);
        var t0 = try std.time.Timer.start();
        const r_prod = certFrac(&pa.prog, lib.items, 4, PROD_N, PROD_L, PROD_T, sr.seed +% 0xA70F, 120 * std.time.ns_per_s);
        const ms_prod = t0.read() / std.time.ns_per_ms;
        t0.reset();
        const r_corr = certExact(&pa.prog, lib.items, 4, 64, 256, 0xE1A5E01, 0xE1A5E02, 120 * std.time.ns_per_s);
        const ms_corr = t0.read() / std.time.ns_per_ms;
        try out.print("    production (8x28,0.95) d<=4: {d} ms (reducible={})   corrected exact(64x256,2-seed) d<=4: {d} ms (reducible={})\n", .{ ms_prod, r_prod.reducible, ms_corr, r_corr.reducible });
        csv.row("A4_cost", "census_inv8_prefix13_d4", "prod_vs_correctedexact", 4, 64, 256, 1.0, 1, @floatFromInt(ms_prod), @floatFromInt(ms_corr), if (r_prod.reducible) 1 else 0, if (r_corr.reducible) 1 else 0, "", "m1=prod ms m2=corrected ms");
    }

    try out.print("\n[A4 done at {d} ms]\n", .{total_timer.read() / std.time.ns_per_ms});
    } // end skip_a4

    // ---------------- A5: verdict re-run under the corrected protocol ----------------
    try out.writeAll("\n=== A5 HEADLINE VERDICTS UNDER THE CORRECTED PROTOCOL (exact, 64x256, 2 seeds) ===\n");
    const CS_A: u64 = 0xE1A5E01;
    const CS_B: u64 = 0xE1A5E02;

    // 20 promoted atoms, corrected census at d3/d4/d5 vs prefix
    try out.writeAll("  atom            d3_verdict        d4_verdict        d5_verdict (corrected)\n");
    var lib_off: usize = 0;
    for (results) |sr| {
        for (0..sr.n_promoted) |k| {
            const pa = &sr.promoted[k];
            const plib = prefix_libs.items[lib_off];
            lib_off += 1;
            var verdicts: [3][]const u8 = undefined;
            var reds: [3]bool = undefined;
            var chain_s: []const u8 = "";
            for (0..3) |di| {
                const d = PROD_DEPTH + di;
                const r = certExact(&pa.prog, plib, d, 64, 256, CS_A, CS_B, 45 * std.time.ns_per_s);
                reds[di] = r.reducible;
                verdicts[di] = if (r.reducible) "REDUCIBLE" else if (r.complete) "irreducible" else "irred(cap)";
                if (r.reducible and chain_s.len == 0) chain_s = chainStr(&cbuf, r.chain[0..r.chain_len]);
            }
            const item = std.fmt.bufPrint(&ibuf, "0x{X}_inv{d}", .{ sr.seed, k }) catch "";
            try out.print("  {s:<15} {s:<17} {s:<17} {s}  {s}\n", .{ item, verdicts[0], verdicts[1], verdicts[2], chain_s });
            csv.row("A5_verdict", item, "corrected_prefix_census", PROD_DEPTH, 64, 256, 1.0, 2, if (reds[0]) 1 else 0, if (reds[1]) 1 else 0, if (reds[2]) 1 else 0, 0, chain_s, "m1..m3 = reducible at d3/d4/d5 under exact 2-seed protocol");
        }
    }

    // kill-tests under corrected protocol
    try out.writeAll("\n  kill-tests (distinct-count) under corrected protocol:\n");
    {
        var pass8: usize = 0;
        for (0..16) |i| {
            const r = certExact(&dc, base5.slice(), 8, 64, 256, streamSeed(30000 + i), streamSeed(31000 + i), 90 * std.time.ns_per_s);
            if (!r.reducible and r.complete) pass8 += 1;
        }
        try out.print("    dc vs base5, exact d<=8, 16 seed replicates: {d}/16 irreducible (complete)\n", .{pass8});
        csv.row("A5_kill", "dc_base5_d8_exact", "corrected", 8, 64, 256, 1.0, 16, @floatFromInt(pass8), 0, 0, 0, "", "16/16 expected");
        for (results) |sr| {
            var passf: usize = 0;
            var completef: usize = 0;
            for (0..6) |i| {
                const r = certExact(&dc, sr.final.slice(), 5, 64, 256, streamSeed(32000 + i), streamSeed(33000 + i), 60 * std.time.ns_per_s);
                if (!r.reducible) passf += 1;
                if (r.complete) completef += 1;
            }
            const item = std.fmt.bufPrint(&ibuf, "dc_final{X}_d5_exact", .{sr.seed}) catch "";
            try out.print("    dc vs final 0x{X}, exact d<=5, 6 replicates: {d}/6 irreducible ({d} complete)\n", .{ sr.seed, passf, completef });
            csv.row("A5_kill", item, "corrected", 5, 64, 256, 1.0, 6, @floatFromInt(passf), @floatFromInt(completef), 0, 0, "", "m2=complete count");
        }
    }

    // census migration: would promotion IDENTITY have changed under the corrected matcher?
    try out.writeAll("\n  census migration (corrected exact census, first-irreducible index vs production):\n");
    {
        var total_migrations: usize = 0;
        var total_red: usize = 0;
        var rounds_with_different_promotion: usize = 0;
        var rounds_checked: usize = 0;
        for (results) |sr| {
            for (0..sr.n_rounds) |r_i| {
                const rd = &sr.rounds[r_i];
                if (rd.n_census == 0) continue;
                rounds_checked += 1;
                const lib = sr.final.slice()[0..rd.lib_before];
                var first_corr: i16 = -1;
                var migr: usize = 0;
                for (0..rd.n_census) |ci| {
                    const cand = &rd.cands[ci];
                    const r = certExact(&cand.prog, lib, PROD_DEPTH, 64, 256, CS_A, CS_B, 20 * std.time.ns_per_s);
                    if (cand.reducible) total_red += 1;
                    if (cand.reducible and !r.reducible) migr += 1;
                    if (!r.reducible and first_corr < 0) first_corr = @intCast(ci);
                }
                total_migrations += migr;
                const same = (first_corr == rd.promoted_idx);
                if (!same) rounds_with_different_promotion += 1;
                const item = std.fmt.bufPrint(&ibuf, "0x{X}_round{d}", .{ sr.seed, r_i + 1 }) catch {
                    continue;
                };
                csv.row("A5_census_migration", item, "corrected_first_irreducible", PROD_DEPTH, 64, 256, 1.0, rd.n_census, @floatFromInt(rd.promoted_idx), @floatFromInt(first_corr), @floatFromInt(migr), if (same) 1 else 0, "", "m1=prod promoted census idx; m2=corrected first-irreducible idx; m3=reducible->irreducible migrations; m4=same promotion");
            }
        }
        try out.print("    reducible verdicts re-checked: {d}; migrations reducible->irreducible: {d}\n", .{ total_red, total_migrations });
        try out.print("    rounds where the PROMOTED candidate would differ: {d}/{d}\n", .{ rounds_with_different_promotion, rounds_checked });
        const note = std.fmt.bufPrint(&nbuf, "reducible_rechecked={d};migrations={d};promotion_identity_changes={d}/{d}", .{ total_red, total_migrations, rounds_with_different_promotion, rounds_checked }) catch "";
        csv.row("A5_census_migration", "aggregate", "corrected_vs_production", PROD_DEPTH, 64, 256, 1.0, total_red, @floatFromInt(total_migrations), @floatFromInt(rounds_with_different_promotion), @floatFromInt(rounds_checked), 0, "", note);
    }

    // constructed adversaries under corrected protocol (the fix must catch them)
    try out.writeAll("\n  constructed adversaries under corrected protocol:\n");
    {
        var devs3: [9]struct { name: []const u8, prog: alien.Program } = .{
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
        for (&devs3) |*ds| {
            const r = certExact(&ds.prog, base5.slice(), PROD_DEPTH, 64, 256, CS_A, CS_B, 30 * std.time.ns_per_s);
            // also 2000-seed pass rate under corrected protocol (single chain [0])
            var npass: usize = 0;
            const gx = [1]usize{0};
            for (0..2000) |i| {
                const a = compareChain(&ds.prog, base5.slice(), &gx, 64, 256, streamSeed(40000 + i), 1);
                if (a.mm != 0) continue;
                const b = compareChain(&ds.prog, base5.slice(), &gx, 64, 256, streamSeed(41000 + i), 1);
                if (b.mm == 0) npass += 1;
            }
            const pr = @as(f64, @floatFromInt(npass)) / 2000.0;
            try out.print("    {s:<14} corrected census d3: {s}; corrected chain[0] pass rate {d:.4}\n", .{ ds.name, if (r.reducible) "REDUCIBLE(=still fooled)" else "irreducible(=caught)", pr });
            csv.row("A5_adversary", ds.name, "corrected", PROD_DEPTH, 64, 256, 1.0, 2000, if (r.reducible) 1 else 0, pr, 0, 0, "", "m1=corrected census still fooled; m2=2000-seed corrected pass rate");
        }
    }

    // witness chains under corrected protocol
    {
        const sr = results[1];
        // inv8 depth-4 flip
        const pa8 = &sr.promoted[8];
        var lib8 = std.ArrayList(alien.Program).init(al);
        defer lib8.deinit();
        for (0..pa8.prefix_len) |j| try lib8.append(sr.final.slice()[j]);
        const w8 = [_]usize{ 5, 9, 6, 0 };
        const a8 = compareChain(&pa8.prog, lib8.items, &w8, 64, 256, CS_A, 1);
        const b8 = compareChain(&pa8.prog, lib8.items, &w8, 64, 256, CS_B, 1);
        const stands = (a8.mm == 0 and b8.mm == 0);
        try out.print("\n  depth-attack flip witness inv8 [5,9,6,0] under corrected protocol: {s}\n", .{if (stands) "STANDS (exact on 2x16384 symbols)" else "DOES NOT STAND"});
        csv.row("A5_witness", "inv8_prefix_d4", "corrected_exact_2seed", 4, 64, 256, 1.0, 2, if (stands) 1 else 0, 0, 0, 0, "[5,9,6,0]", "depth-attack flip re-check");
    }

    try out.print("\n[run2 total elapsed {d} ms]\n", .{total_timer.read() / std.time.ns_per_ms});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const al = gpa.allocator();

    const args = try std.process.argsAlloc(al);
    defer std.process.argsFree(al, args);
    if (args.len < 4) {
        std.debug.print("usage: matcher_attack run1|run2 <state.bin> <out.csv>\n", .{});
        return error.BadArgs;
    }
    if (std.mem.eql(u8, args[1], "run1")) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        try doRun1(arena.allocator(), args[2], args[3]);
    } else {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const s3 = std.mem.eql(u8, args[1], "run3") or std.mem.eql(u8, args[1], "run4");
        const s4 = std.mem.eql(u8, args[1], "run4");
        try doRun2(arena.allocator(), args[2], args[3], s3, s4);
    }
}
