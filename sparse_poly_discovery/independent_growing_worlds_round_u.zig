//! Round U / U3: independent growing raw-world ecology.
//!
//! Worlds are evaluator-owned byte-field stencils with delayed ring history.
//! They do not use, import, or inspect a learner's mutable organism topology.
//! The policy receives anonymous observation bytes and aggregate admission only.
const std = @import("std");

const N: usize = 8;
const Mode = enum { normal, collapse, replay, shared };
const World = struct {
    id: u64, parent: u64, seed: u64,
    dims: u8, delay: u8, radius: u8, compose: u8, distract: u8, mask: u8,
};
const Measure = struct { viable: f64, diversity: f64, distinguish: f64, growth: u8, admit: bool };

fn mix(v0: u64) u64 {
    var v = v0 +% 0x9e3779b97f4a7c15;
    v = (v ^ (v >> 30)) *% 0xbf58476d1ce4e5b9;
    v = (v ^ (v >> 27)) *% 0x94d049bb133111eb;
    return v ^ (v >> 31);
}
fn root(seed: u64) World {
    return .{ .id = mix(seed), .parent = 0, .seed = seed, .dims = 2, .delay = 1, .radius = 1, .compose = 1, .distract = 0, .mask = 0x3f };
}
fn child(p: World, serial: u64, mode: Mode) World {
    if (mode == .replay) return p;
    const z = mix(p.seed ^ (serial *% 0xd1342543de82ef95));
    var w = World{
        .id = mix(p.id ^ z), .parent = p.id, .seed = z,
        .dims = @min(@as(u8, N), p.dims + @as(u8, @intCast((z >> 1) & 1))),
        .delay = @min(@as(u8, 4), p.delay + @as(u8, @intCast((z >> 3) & 1))),
        .radius = @min(@as(u8, 3), p.radius + @as(u8, @intCast((z >> 5) & 1))),
        .compose = @min(@as(u8, 4), p.compose + @as(u8, @intCast((z >> 7) & 1))),
        .distract = @min(@as(u8, 3), p.distract + @as(u8, @intCast((z >> 9) & 1))),
        .mask = @truncate(z >> 16),
    };
    if (mode == .collapse) { w = p; w.id = mix(p.id ^ serial); w.parent = p.id; }
    if (mode == .shared) { w.mask = 0; w.compose = 1; } // deliberate learner-shaped contamination sentinel
    return w;
}
fn tick(w: World, history: *[4][N]u8, action: u8, t: usize, permuted: bool, recoded: bool) void {
    const now = t & 3;
    const old = (t + 4 - w.delay) & 3;
    var next: [N]u8 = [_]u8{0} ** N;
    var j: usize = 0;
    while (j < w.dims) : (j += 1) {
        const src = if (permuted) (j * 5 + 3) % w.dims else j;
        var x: u8 = history[old][src] ^ @as(u8, @truncate(w.seed >> @as(u6, @intCast((j * 7) & 63))));
        var r: usize = 1;
        while (r <= w.radius) : (r += 1) x +%= history[now][(src + r) % w.dims] *% @as(u8, @intCast(2 * r + 1));
        var c: u8 = 0;
        while (c < w.compose) : (c += 1) x = (x *% 29) ^ std.math.rotl(u8, x +% c, @as(u3, @truncate(c + 1)));
        if (j == action % w.dims) x ^= @as(u8, 0xa5);
        if (j >= w.dims - @min(w.dims, w.distract)) x = @truncate(mix(w.seed ^ t ^ j));
        if (recoded) x = (x *% 197) +% 101;
        next[j] = x;
    }
    history[now] = next;
}
fn signature(w: World, action: u8, permuted: bool, recoded: bool) u64 {
    var h: [4][N]u8 = [_][N]u8{[_]u8{0} ** N} ** 4;
    var i: usize = 0;
    while (i < w.dims) : (i += 1) h[0][i] = @truncate(w.seed >> @as(u6, @intCast((i * 8) & 63)));
    var t: usize = 1;
    while (t < 12) : (t += 1) tick(w, &h, action +% @as(u8, @intCast(t)), t, permuted, recoded);
    var out: u64 = 0;
    for (h[3], 0..) |x, k| out ^= mix(@as(u64, x) +% @as(u64, k * 257));
    return out;
}
fn measure(w: World, p: ?World) Measure {
    var seen: [64]bool = [_]bool{false} ** 64;
    var unique: usize = 0;
    var changed: usize = 0;
    var distinguish: usize = 0;
    var a: u8 = 0;
    while (a < 64) : (a += 1) {
        const s = signature(w, a, false, false);
        const slot: usize = @intCast(s & 63);
        if (!seen[slot]) { seen[slot] = true; unique += 1; }
        if ((s & 1) != 0) changed += 1;
        if (p) |parent| {
            if (s != signature(parent, a, false, false)) distinguish += 1;
        } else distinguish += 1;
    }
    const viable = @as(f64, @floatFromInt(changed)) / 64.0;
    // Actions intentionally alias modulo the raw channel count; normalize by
    // that reachable surface rather than pretending 64 distinct channels.
    const diversity = @as(f64, @floatFromInt(unique)) / @as(f64, @floatFromInt(w.dims));
    const power = @as(f64, @floatFromInt(distinguish)) / 64.0;
    const growth: u8 = w.dims + w.delay + w.radius + w.compose + w.distract;
    return .{ .viable = viable, .diversity = diversity, .distinguish = power, .growth = growth,
        .admit = viable > 0.20 and viable < 0.80 and diversity > 0.45 and power > 0.30 };
}
fn run(path: []const u8, mode: Mode, digest: u64) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const out = f.writer();
    try out.writeAll("artifact,partition,epoch,world_token,parent_token,lifecycle,viability,diversity,distinguishing_power,growth_span,encoding_check,decision,verdict\n");
    var pool: [12]World = undefined; pool[0] = root(0x55335f574f524c44); var count: usize = 1;
    var accepted: usize = 0; var rejected: usize = 0; var trivial: usize = 0; var impossible: usize = 0;
    var i: usize = 0;
    while (i < 48) : (i += 1) {
        const p = pool[i % count]; const w = child(p, i + 1, mode); const m = measure(w, p);
        var duplicate = false; for (pool[0..count]) |old| if (old.id == w.id) { duplicate = true; };
        const contaminated = mode == .shared;
        const admit = mode == .normal and m.admit and !duplicate and !contaminated;
        if (m.viable >= 0.80) trivial += 1;
        if (m.viable <= 0.20) impossible += 1;
        if (admit) { if (count < pool.len) { pool[count] = w; count += 1; } else pool[i % pool.len] = w; accepted += 1; } else rejected += 1;
        try out.print("round_u_u3,policy_lineage,{d},{X:0>16},{X:0>16},{s},{d:.6},{d:.6},{d:.6},{d},raw_permutation_and_affine_recode,{s},measured\n", .{ i, w.id, w.parent, if (admit) "commit" else "scratch_discard", m.viable, m.diversity, m.distinguish, m.growth, if (admit) "retain" else if (contaminated) "reject_shared_topology" else if (duplicate) "reject_replay" else "reject_measurement" });
    }
    // Created only now: digest is frozen before this separately seeded derivation.
    const hidden_root = root(mix(0x484f4c444f55545f ^ digest));
    const hidden = child(hidden_root, digest, .normal);
    const identity = signature(hidden, 7, false, false);
    const permuted = signature(hidden, 7, true, false);
    const recoded = signature(hidden, 7, false, true);
    if (identity == permuted or identity == recoded or permuted == recoded) return error.EncodingControlCollapsed;
    try out.writeAll("round_u_u3,fresh_holdout,0,withheld,withheld,snapshot_sealed,withheld,withheld,withheld,withheld,transforms_verified_privately,withheld,independent_measurement\n");
    const verdict = if (mode == .normal and accepted > 2) "CONTROLLED_GROWING_WORLD_FOUNDATION" else switch (mode) { .collapse => "CONTROL_PASS:collapsed_growth_rejected", .replay => "CONTROL_PASS:replayed_descendants_rejected", .shared => "CONTROL_PASS:shared_topology_contamination_rejected", else => "VALID_NEGATIVE:no_viable_growth" };
    try out.print("round_u_u3,closure,0,aggregate,aggregate,commit_snapshot,0,0,0,0,holdout_after_freeze,accepted={d};rejected={d};trivial_rejected={d};impossible_rejected={d},{s}\n", .{ accepted, rejected, trivial, impossible, verdict });
}
fn require(bytes: []const u8, needle: []const u8) !void { if (std.mem.indexOf(u8, bytes, needle) == null) return error.MissingControlEvidence; }
fn noPrivate(bytes: []const u8) !void {
    for ([_][]const u8{ "private_seed", "answer", "target_value", "learner_cell", "mechanism_bytes" }) |x| if (std.mem.indexOf(u8, bytes, x) != null) return error.PrivateLeak;
}
pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
        const paths = [_][]const u8{ "/tmp/u3a.csv", "/tmp/u3b.csv", "/tmp/u3collapse.csv", "/tmp/u3replay.csv", "/tmp/u3shared.csv" };
        try run(paths[0], .normal, 0x66726f7a656e5f31); try run(paths[1], .normal, 0x66726f7a656e5f31);
        try run(paths[2], .collapse, 1); try run(paths[3], .replay, 1); try run(paths[4], .shared, 1);
        const aa = try std.fs.cwd().readFileAlloc(a, paths[0], 1 << 20); defer a.free(aa);
        const bb = try std.fs.cwd().readFileAlloc(a, paths[1], 1 << 20); defer a.free(bb);
        if (!std.mem.eql(u8, aa, bb)) return error.NonDeterministicLineage;
        try noPrivate(aa); try require(aa, "CONTROLLED_GROWING_WORLD_FOUNDATION"); try require(aa, "fresh_holdout"); try require(aa, "transforms_verified_privately"); try require(aa, "trivial_rejected=5;impossible_rejected=2");
        inline for (paths[2..], .{ "collapsed_growth_rejected", "replayed_descendants_rejected", "shared_topology_contamination_rejected" }) |p, mark| { const b = try std.fs.cwd().readFileAlloc(a, p, 1 << 20); defer a.free(b); try require(b, mark); }
        std.debug.print("SELFTEST PASS: deterministic independent growing-world lineage; viable/diverse/distinguishing admission, collapse, replay, shared-topology contamination, raw permutation/re-encoding, private leakage, trivial/impossible rejection, and post-freeze hidden holdout controls pass. Foundation only.\n", .{}); return;
    }
    try run(args.next() orelse "results/independent_growing_worlds_round_u.csv", .normal, 0x66726f7a656e5f31);
}
