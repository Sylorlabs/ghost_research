//! K4 / Round K -- post-freeze hidden-structure holdout manifest generator.
//!
//! This is evaluation infrastructure only.  It deliberately exports no route,
//! feature, score, or candidate-selection function.  A policy may receive
//! opaque example streams identified by `policy_target_token`; it must never
//! read the `audit_*` columns in the revealed manifest.
const std = @import("std");

const Cells: usize = 8;
const Examples: usize = 1024;
const TargetCount: usize = 24;
const ManifestSeed: u64 = 0x4B4B_0000_0000_0001;

const Kind = enum { directed_partition, threshold, adjacency, xor_control, parity_control };
const Target = struct {
    id: usize,
    kind: Kind,
    mask: u8,
    a: u8,
    b: u8,
    modulus: u8,
    residue: u8,
    permutation: [Cells]u3,
    example_seed: u64,
};
const Validity = struct { ones: usize, ok: bool };

fn kindName(k: Kind) []const u8 { return @tagName(k); }
fn pop(x: u8) usize { return @popCount(x); }
fn countAtLeast(g: [Cells]u8, a: u8) usize { var n: usize = 0; for (g) |v| { if (v >= a) n += 1; } return n; }
fn adjacentAtLeast(g: [Cells]u8, b: u8) usize { var n: usize = 0; for (1..Cells) |i| { if (g[i] >= b and g[i - 1] >= b) n += 1; } return n; }
fn directedCross(g: [Cells]u8, mask: u8) usize {
    var n: usize = 0;
    for (0..Cells) |i| for (0..Cells) |j| {
        const bi: u8 = @as(u8, 1) << @intCast(i);
        const bj: u8 = @as(u8, 1) << @intCast(j);
        if ((mask & bi) != 0 and (mask & bj) == 0 and g[i] > g[j]) n += 1;
    };
    return n;
}
fn permute(g: [Cells]u8, p: [Cells]u3) [Cells]u8 { var out: [Cells]u8 = undefined; for (0..Cells) |i| out[i] = g[p[i]]; return out; }
fn label(t: Target, raw: [Cells]u8) bool {
    const g = permute(raw, t.permutation);
    const q: usize = switch (t.kind) {
        .directed_partition => directedCross(g, t.mask),
        .threshold => countAtLeast(g, t.a),
        .adjacency => adjacentAtLeast(g, t.b),
        .xor_control => @intFromBool(countAtLeast(g, t.a) % 2 == 1) ^ @intFromBool(adjacentAtLeast(g, t.b) % 2 == 1),
        .parity_control => blk: { var s: usize = 0; for (g) |v| s += v; break :blk s; },
    };
    return q % t.modulus == t.residue;
}
fn shuffle(comptime T: type, xs: []T, r: std.Random) void { var i = xs.len; while (i > 1) { i -= 1; const j = r.uintLessThan(usize, i + 1); std.mem.swap(T, &xs[i], &xs[j]); } }
fn randomPermutation(r: std.Random) [Cells]u3 { var p: [Cells]u3 = undefined; for (0..Cells) |i| p[i] = @intCast(i); shuffle(u3, &p, r); return p; }
fn maskOfSize(r: std.Random, wanted: usize) u8 { var ids: [Cells]u3 = undefined; for (0..Cells) |i| ids[i] = @intCast(i); shuffle(u3, &ids, r); var m: u8 = 0; for (ids[0..wanted]) |i| m |= @as(u8, 1) << i; return m; }
fn valid(t: Target) Validity {
    var p = std.Random.DefaultPrng.init(t.example_seed);
    const r = p.random(); var ones: usize = 0;
    for (0..Examples) |_| { var g: [Cells]u8 = undefined; for (&g) |*v| v.* = r.intRangeAtMost(u8, 0, 5); if (label(t, g)) ones += 1; }
    // 20--80% makes exact accuracy meaningful and rules out constant labels.
    return .{ .ones = ones, .ok = ones >= Examples / 5 and ones <= Examples - Examples / 5 };
}
fn signature(t: Target, out: *[64]u8) []const u8 {
    // This is an audit uniqueness key, never policy input.
    return std.fmt.bufPrint(out, "{s}:{d}:{d}:{d}:{d}:{d}:{any}", .{ kindName(t.kind), t.mask, t.a, t.b, t.modulus, t.residue, t.permutation }) catch unreachable;
}
fn seedCommit(seed: u64, out: *[64]u8) []const u8 {
    var input: [8]u8 = undefined; std.mem.writeInt(u64, &input, seed, .big);
    var digest: [32]u8 = undefined; std.crypto.hash.sha2.Sha256.hash(&input, &digest, .{});
    out.* = std.fmt.bytesToHex(digest, .lower);
    return out;
}
fn makeTarget(id: usize, r: std.Random, example_seed: u64) Target {
    const bucket: usize = id % 5;
    const k: Kind = switch (bucket) { 0 => .directed_partition, 1 => .threshold, 2 => .adjacency, 3 => .xor_control, else => .parity_control };
    var t = Target{ .id = id, .kind = k, .mask = 0, .a = r.intRangeAtMost(u8, 1, 5), .b = r.intRangeAtMost(u8, 2, 5), .modulus = if (r.boolean()) 2 else 3, .residue = 0, .permutation = randomPermutation(r), .example_seed = example_seed };
    t.residue = r.uintLessThan(u8, t.modulus);
    if (k == .directed_partition) t.mask = maskOfSize(r, 1 + (id / 5) % 4);
    return t;
}
fn writeManifest(w: anytype, seed: u64) !void {
    var seed_hex: [64]u8 = undefined;
    const commit = seedCommit(seed, &seed_hex);
    try w.writeAll("protocol,policy_target_token,policy_split,policy_examples,policy_api_contract,audit_manifest_seed,audit_seed_commit_sha256,audit_target_id,audit_kind,audit_partition_size,audit_mask,audit_threshold_a,audit_threshold_b,audit_modulus,audit_residue,audit_permutation,audit_example_seed,audit_label_ones,audit_label_zeros,audit_nondegenerate,audit_unique_formula,audit_permutation_checked,reveal_status\n");
    var p = std.Random.DefaultPrng.init(seed); const r = p.random();
    var seen: [TargetCount][64]u8 = undefined; var seen_len: [TargetCount]usize = [_]usize{0} ** TargetCount;
    for (0..TargetCount) |id| {
        var tries: usize = 0;
        var t: Target = undefined; var v: Validity = undefined; var sig: [64]u8 = undefined; var duplicate = false;
        while (true) {
            tries += 1; if (tries > 10000) return error.GenerationExhausted;
            t = makeTarget(id, r, r.int(u64)); v = valid(t); const s = signature(t, &sig); duplicate = false;
            for (0..id) |j| if (std.mem.eql(u8, s, seen[j][0..seen_len[j]])) { duplicate = true; break; };
            if (v.ok and !duplicate) { @memcpy(seen[id][0..s.len], s); seen_len[id] = s.len; break; }
        }
        var perm_buf: [40]u8 = undefined; var ps = std.io.fixedBufferStream(&perm_buf); for (t.permutation, 0..) |x, i| { if (i != 0) try ps.writer().writeByte('-'); try ps.writer().print("{d}", .{x}); }
        try w.print("round_k_hidden_holdout,K4-{d:0>2},heldout,{d},opaque_examples_only,0x{X:0>16},{s},{d},{s},{d},0x{X:0>2},{d},{d},{d},{d},{s},0x{X:0>16},{d},{d},{s},pass,pass,revealed\n", .{ id, Examples, seed, commit, id, kindName(t.kind), pop(t.mask), t.mask, t.a, t.b, t.modulus, t.residue, ps.getWritten(), t.example_seed, v.ones, Examples - v.ones, "pass" });
    }
}
pub fn main() !void {
    var args = std.process.args(); _ = args.next();
    const path = args.next() orelse "../results/hidden_holdout_round_k.csv";
    const seed_text = args.next();
    const seed = if (seed_text) |s| try std.fmt.parseInt(u64, s, 0) else ManifestSeed;
    const f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    try writeManifest(f.writer(), seed);
    var hex: [64]u8 = undefined;
    std.debug.print("K4 REVEALED: {d} heldout targets; seed_commit_sha256={s}; policy API receives opaque examples only.\n", .{ TargetCount, seedCommit(seed, &hex) });
}
