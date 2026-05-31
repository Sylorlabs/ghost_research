//! Open-ended (novelty) search over the alien substrate (RESEARCH §21).
//!
//! The §20 diagnosis: fixed-task + performance fitness collapses search onto the
//! minimal-complexity KNOWN mechanism — known mechanisms are convergent attractors.
//! The treatment indicated by that diagnosis (Lehman & Stanley novelty search): stop
//! rewarding "solve task X" and reward BEHAVIOURAL NOVELTY — a program scores by how
//! far its behaviour is from everything seen so far. The certifier's fingerprint (the
//! §20 audit tool) BECOMES the selection pressure: search is driven to fill the
//! behaviour space, not to optimise a task.
//!
//! The honest question this answers: does novelty search
//!   (a) REDISCOVER the known mechanisms as the sparse functional points (no task
//!       objective, yet the scan/hash-table/etc. emerge) — convergence from a new angle;
//!   (b) find VIABLE points OUTSIDE every known anchor — candidate novelty; or
//!   (c) drown in degenerate "different but useless" novelty — the open-endedness
//!       failure mode.
//!
//! Minimal-criterion: a program must be input-SENSITIVE (behave measurably unlike a
//! no-op) to enter the archive, so pure noise can't farm cheap novelty.

const std = @import("std");
const alien = @import("inv_alien.zig");
const fr = @import("inv_frontier.zig");

pub const Member = struct { prog: alien.Program, fp: fr.Fingerprint, novelty: f64 = 0 };

pub const Params = struct {
    pop: usize = 100,
    gens: usize = 60,
    k: usize = 12, // kNN for the novelty metric
    add_threshold: f64 = 0.12, // min novelty (and min archive-distance) to be admitted
    archive_cap: usize = 512,
    immigrant_rate: f64 = 0.20,
    tournament: usize = 3,
    active_regs: usize = 8, // substrate width for the proposer
    viable_eps: f64 = 0.15, // min distance from the no-op fingerprint to count as "alive"
    seed: u64 = 0xE1A5E, // descriptor seed (fixed so behaviour is comparable across the run)
    info: bool = false, // use the task-AGNOSTIC info-theoretic descriptor instead of the task one
};

/// The behaviour descriptor used for novelty: the §21 known-task fingerprint, or the
/// task-AGNOSTIC information-theoretic descriptor (which can SEE capabilities the task
/// descriptor is blind to). Both live in the same 6-dim space so they're swappable.
pub fn desc(prog: *const alien.Program, p: Params) fr.Fingerprint {
    return if (p.info) infoDescriptor(prog, p.seed) else alien.descriptorLite(prog, p.seed);
}

// ---- the task-agnostic information-theoretic descriptor --------------------

const CANON_L: usize = 48;

fn entropy(s: []const u8) f64 {
    var cnt = [_]usize{0} ** alien.CANON_BASE;
    for (s) |v| cnt[v] += 1;
    const n: f64 = @floatFromInt(s.len);
    var h: f64 = 0;
    for (cnt) |c| {
        if (c == 0) continue;
        const pr = @as(f64, @floatFromInt(c)) / n;
        h -= pr * std.math.log2(pr);
    }
    return h / std.math.log2(@as(f64, @floatFromInt(alien.CANON_BASE))); // normalise 0..1
}
fn distinctFrac(s: []const u8) f64 {
    var seen = [_]bool{false} ** alien.CANON_BASE;
    for (s) |v| seen[v] = true;
    var d: usize = 0;
    for (seen) |b| if (b) {
        d += 1;
    };
    return @as(f64, @floatFromInt(d)) / @as(f64, @floatFromInt(alien.CANON_BASE));
}
fn changeFrac(a: []const u8, b: []const u8, lo: usize, hi: usize) f64 {
    var ch: usize = 0;
    var n: usize = 0;
    for (lo..hi) |i| {
        n += 1;
        if (a[i] != b[i]) ch += 1;
    }
    return if (n > 0) @as(f64, @floatFromInt(ch)) / @as(f64, @floatFromInt(n)) else 0;
}
/// Order-1 determinism: fraction of steps where the output equals the most-frequent
/// successor of the previous output (structure vs. memorylessness).
fn predictability(s: []const u8) f64 {
    var trans = [_][alien.CANON_BASE]usize{[_]usize{0} ** alien.CANON_BASE} ** alien.CANON_BASE;
    for (1..s.len) |i| trans[s[i - 1]][s[i]] += 1;
    var hit: usize = 0;
    var tot: usize = 0;
    for (1..s.len) |i| {
        const row = trans[s[i - 1]];
        var best: usize = 0;
        for (row, 0..) |c, j| if (c > row[best]) {
            best = j;
        };
        tot += 1;
        if (s[i] == best) hit += 1;
    }
    return if (tot > 0) @as(f64, @floatFromInt(hit)) / @as(f64, @floatFromInt(tot)) else 0;
}

/// Black-box, TASK-AGNOSTIC behaviour descriptor. No reference to any "correct"
/// answer — only generic properties of the program's input→output map:
///   [0] output entropy on channel OUT_P     [1] output entropy on channel OUT_R
///   [2] local responsiveness (perturb a mid input → immediate OUT_R change)
///   [3] memory depth (perturb the FIRST input → OUT_R change far downstream)
///   [4] output richness (distinct OUT_R values)  [5] OUT_R order-1 determinism
/// This SEES mechanisms the task descriptor cannot (e.g. counting shows up as high
/// memory-depth + rich, structured output).
pub fn infoDescriptor(prog: *const alien.Program, seed: u64) fr.Fingerprint {
    var syms: [CANON_L]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    for (&syms) |*s| s.* = @intCast(rng.uintLessThan(usize, alien.CANON_BASE));
    var o2: [CANON_L]u8 = undefined;
    var o3: [CANON_L]u8 = undefined;
    alien.runCanonical(prog, &syms, &o2, &o3);

    var mid = syms; // perturb a middle input
    mid[CANON_L / 2] = @intCast((@as(usize, mid[CANON_L / 2]) + 1) % alien.CANON_BASE);
    var m2: [CANON_L]u8 = undefined;
    var m3: [CANON_L]u8 = undefined;
    alien.runCanonical(prog, &mid, &m2, &m3);

    var first = syms; // perturb the very first input
    first[0] = @intCast((@as(usize, first[0]) + 1) % alien.CANON_BASE);
    var f2: [CANON_L]u8 = undefined;
    var f3: [CANON_L]u8 = undefined;
    alien.runCanonical(prog, &first, &f2, &f3);

    var d: fr.Fingerprint = undefined;
    d[0] = entropy(&o2);
    d[1] = entropy(&o3);
    d[2] = changeFrac(&o3, &m3, CANON_L / 2, CANON_L / 2 + 4); // local responsiveness
    d[3] = changeFrac(&o3, &f3, CANON_L / 2, CANON_L); // memory depth (far downstream)
    d[4] = distinctFrac(&o3);
    d[5] = predictability(&o3);
    return d;
}

const MAXREF = 1024;

/// kNN novelty: mean distance to the k nearest fingerprints among `others`.
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
    for (0..kk) |i| { // partial selection of the kk smallest
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

/// Novelty search with an archive. Returns the archive (the diverse behaviour set).
pub fn search(al: std.mem.Allocator, rng: std.Random, p: Params) !std.ArrayList(Member) {
    var sp = alien.Params{ .active_regs = p.active_regs };
    const empty = alien.Program{};
    const dead = desc(&empty, p); // the no-op behaviour

    var archive = std.ArrayList(Member).init(al);
    var arch_fps = std.ArrayList(fr.Fingerprint).init(al);
    defer arch_fps.deinit();

    const pop = try al.alloc(Member, p.pop);
    defer al.free(pop);
    for (pop) |*m| {
        m.prog = alien.randProg(rng, &sp);
        m.fp = desc(&m.prog, p);
    }

    var combined = std.ArrayList(fr.Fingerprint).init(al);
    defer combined.deinit();

    for (0..p.gens) |_| {
        // reference set = archive ∪ population
        combined.clearRetainingCapacity();
        for (arch_fps.items) |f| try combined.append(f);
        for (pop) |m| try combined.append(m.fp);

        // score novelty + admit the genuinely-novel, viable members
        for (pop) |*m| {
            m.novelty = knnNovelty(m.fp, combined.items, p.k);
            const alive = fr.fpDist(m.fp, dead) > p.viable_eps;
            const new_enough = arch_fps.items.len == 0 or minDistTo(m.fp, arch_fps.items) > p.add_threshold;
            if (alive and new_enough and m.novelty > p.add_threshold and archive.items.len < p.archive_cap) {
                try archive.append(m.*);
                try arch_fps.append(m.fp);
            }
        }

        // produce the next population: novelty-tournament + immigrants
        const next = try al.alloc(Member, p.pop);
        for (next) |*c| {
            if (rng.float(f64) < p.immigrant_rate) {
                c.prog = alien.randProg(rng, &sp);
            } else {
                var best = rng.uintLessThan(usize, p.pop);
                for (1..p.tournament) |_| {
                    const cand = rng.uintLessThan(usize, p.pop);
                    if (pop[cand].novelty > pop[best].novelty) best = cand;
                }
                c.prog = pop[best].prog;
                alien.mutate(rng, &c.prog, &sp);
            }
            c.fp = desc(&c.prog, p);
        }
        @memcpy(pop, next);
        al.free(next);
    }
    return archive;
}

/// Spread of the archive in each behaviour dimension (std-dev), a coverage proxy.
pub fn coverage(archive: []const Member) fr.Fingerprint {
    var mean: fr.Fingerprint = [_]f64{0} ** fr.FP_N;
    for (archive) |m| for (0..fr.FP_N) |i| {
        mean[i] += m.fp[i];
    };
    const n: f64 = @floatFromInt(@max(1, archive.len));
    for (0..fr.FP_N) |i| mean[i] /= n;
    var sd: fr.Fingerprint = [_]f64{0} ** fr.FP_N;
    for (archive) |m| for (0..fr.FP_N) |i| {
        const d = m.fp[i] - mean[i];
        sd[i] += d * d;
    };
    for (0..fr.FP_N) |i| sd[i] = std.math.sqrt(sd[i] / n);
    return sd;
}

test "KILL-TEST: the info descriptor SEES the counter where the task descriptor is blind" {
    const seed: u64 = 0x1F0;
    const empty = alien.Program{};
    const counter = alien.alienRMWCounter();
    const scan = alien.alienXorScan();

    // task descriptor: the counter reads ~identical to the no-op (the §21 blind spot)
    const t_noop = alien.descriptorLite(&empty, seed);
    const t_counter = alien.descriptorLite(&counter, seed);
    try std.testing.expect(fr.fpDist(t_noop, t_counter) < 0.20); // blind: counter ≈ no-op

    // info descriptor: the counter is now FAR from the no-op AND from the scan
    const i_noop = infoDescriptor(&empty, seed);
    const i_counter = infoDescriptor(&counter, seed);
    const i_scan = infoDescriptor(&scan, seed);
    try std.testing.expect(fr.fpDist(i_noop, i_counter) > 0.40); // visible: counter ≠ no-op
    try std.testing.expect(fr.fpDist(i_scan, i_counter) > 0.30); // and ≠ the scan
}

test "novelty search runs and produces a non-trivial, spread archive (smoke + kill-test)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var prng = std.Random.DefaultPrng.init(0x09E45EED);
    const arch = try search(arena.allocator(), prng.random(), .{ .pop = 60, .gens = 20 });
    try std.testing.expect(arch.items.len >= 2); // it fills an archive with distinct behaviours
    const sd = coverage(arch.items);
    // at least one behaviour dimension must show real spread (not all clones) — the
    // actual kill-test: novelty search produces DIVERSITY, not a single converged point
    var max_sd: f64 = 0;
    for (sd) |s| max_sd = @max(max_sd, s);
    try std.testing.expect(max_sd > 0.03);
}
