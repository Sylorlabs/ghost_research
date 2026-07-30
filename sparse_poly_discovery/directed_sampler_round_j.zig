//! J1 / Round J -- directed grammar enumeration and sampler integrity repair.
//!
//! This program deliberately has no targets, labels, candidate scores, or
//! routing.  It establishes the substrate needed for later fair search
//! experiments: the directed grammar is enumerated once, exactly, and every
//! prefix sampler is target-agnostic and without replacement.
const std = @import("std");

const MASKS: usize = 254;
const FLAVORS: usize = 5; // (mod 2,res 0/1), (mod 3,res 0/1/2)
const MAX: usize = MASKS * FLAVORS;
const budgets = [_]usize{ 25, 100, 300, 635, 1270 };
const seeds = [_]u64{ 0xA100000000000001, 0xA100000000000002, 0xA100000000000003 };

const Candidate = struct { mask: u8, modulus: u8, residue: u8 };

fn flavorAt(f: usize) struct { modulus: u8, residue: u8 } {
    return if (f < 2) .{ .modulus = 2, .residue = @intCast(f) }
    else .{ .modulus = 3, .residue = @intCast(f - 2) };
}
fn candidateAt(k: usize) Candidate {
    const x = flavorAt(k % FLAVORS);
    return .{ .mask = @intCast(k / FLAVORS + 1), .modulus = x.modulus, .residue = x.residue };
}
/// Canonical key: 1..254 mask, then one of exactly five legal residue flavors.
fn key(c: Candidate) usize {
    const flavor: usize = if (c.modulus == 2) c.residue else 2 + c.residue;
    return (@as(usize, c.mask) - 1) * FLAVORS + flavor;
}
fn bitCount(x: u8) usize { return @popCount(x); }
fn shuffle(comptime T: type, xs: []T, random: std.Random) void {
    var i = xs.len;
    while (i > 1) { i -= 1; const j = random.uintLessThan(usize, i + 1); std.mem.swap(T, &xs[i], &xs[j]); }
}
fn identity(out: *[MAX]Candidate) void { for (0..MAX) |i| out[i] = candidateAt(i); }

fn uniform(out: *[MAX]Candidate, seed: u64) void {
    identity(out);
    var prng = std.Random.DefaultPrng.init(seed);
    shuffle(Candidate, out, prng.random());
}
/// Interleaves five independently shuffled mask strata.  For every complete
/// five-candidate block it has exactly one of each legal modulus/residue
/// flavor; every candidate remains present exactly once.
fn stratified(out: *[MAX]Candidate, seed: u64) void {
    var prng = std.Random.DefaultPrng.init(seed);
    var masks: [FLAVORS][MASKS]u8 = undefined;
    for (0..FLAVORS) |f| {
        for (0..MASKS) |i| masks[f][i] = @intCast(i + 1);
        shuffle(u8, &masks[f], prng.random());
    }
    for (0..MASKS) |round| for (0..FLAVORS) |f| {
        const x = flavorAt(f);
        out[round * FLAVORS + f] = .{ .mask = masks[f][round], .modulus = x.modulus, .residue = x.residue };
    };
}
/// Fixed affine enumeration is a permutation control, not an aiming arm.
fn affine(out: *[MAX]Candidate) void { for (0..MAX) |i| out[i] = candidateAt((809 * i + 113) % MAX); }

fn assertPermutation(xs: []const Candidate) !void {
    if (xs.len != MAX) return error.WrongCount;
    var seen = [_]bool{false} ** MAX;
    for (xs) |c| {
        if (c.mask == 0 or c.modulus < 2 or c.modulus > 3 or c.residue >= c.modulus) return error.IllegalCandidate;
        const k = key(c);
        if (k >= MAX or seen[k]) return error.DuplicateCandidate;
        seen[k] = true;
    }
    for (seen) |v| if (!v) return error.MissingCandidate;
}
/// Any permutation of the eight mask bits maps the canonical grammar to the
/// canonical grammar.  This is set invariance, not a claim about an order.
fn assertMaskPermutationInvariant() !void {
    const p = [_]u3{ 3, 6, 1, 7, 0, 5, 2, 4 };
    var seen = [_]bool{false} ** MAX;
    for (0..MAX) |i| {
        var c = candidateAt(i); var mapped: u8 = 0;
        for (0..8) |b| {
            if ((c.mask & (@as(u8, 1) << @intCast(b))) != 0) mapped |= @as(u8, 1) << p[b];
        }
        c.mask = mapped;
        const k = key(c); if (seen[k]) return error.MaskPermutationDuplicate; seen[k] = true;
    }
    for (seen) |v| if (!v) return error.MaskPermutationMissing;
}
/// Reordering the five legal residue flavors is also a set permutation.
fn assertFlavorPermutationInvariant() !void {
    const p = [_]usize{ 4, 2, 0, 3, 1 };
    var seen = [_]bool{false} ** MAX;
    for (0..MASKS) |m| for (p) |f| { const x = flavorAt(f); const k = key(.{ .mask = @intCast(m + 1), .modulus = x.modulus, .residue = x.residue }); if (seen[k]) return error.FlavorPermutationDuplicate; seen[k] = true; };
    for (seen) |v| if (!v) return error.FlavorPermutationMissing;
}
const Ledger = struct { unique: usize = 0, masks: usize = 0, mod2: usize = 0, mod3: usize = 0, r20: usize = 0, r21: usize = 0, r30: usize = 0, r31: usize = 0, r32: usize = 0, mean_hamming: f64 = 0 };
fn ledger(xs: []const Candidate) !Ledger {
    var l = Ledger{}; var keys = [_]bool{false} ** MAX; var masks = [_]bool{false} ** 256;
    var pairs: usize = 0; var hsum: usize = 0;
    for (xs, 0..) |c, i| {
        const k = key(c); if (keys[k]) return error.PrefixDuplicate; keys[k] = true; l.unique += 1; masks[c.mask] = true;
        if (c.modulus == 2) { l.mod2 += 1; if (c.residue == 0) l.r20 += 1 else l.r21 += 1; } else { l.mod3 += 1; if (c.residue == 0) l.r30 += 1 else if (c.residue == 1) l.r31 += 1 else l.r32 += 1; }
        for (xs[0..i]) |d| { hsum += bitCount(c.mask ^ d.mask); pairs += 1; }
    }
    for (masks[1..]) |v| {
        if (v) l.masks += 1;
    }
    if (pairs > 0) l.mean_hamming = @as(f64, @floatFromInt(hsum)) / @as(f64, @floatFromInt(pairs));
    return l;
}
fn writeRows(w: anytype, name: []const u8, seed: u64, xs: []const Candidate) !void {
    try assertPermutation(xs);
    for (budgets) |b| { const l = try ledger(xs[0..b]); try w.print("{s},0x{X:0>16},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d:.6},pass\n", .{ name, seed, b, l.unique, l.masks, l.mod2, l.mod3, l.r20, l.r21, l.r30, l.r31, l.r32, l.mean_hamming }); }
}
pub fn main() !void {
    try assertMaskPermutationInvariant(); try assertFlavorPermutationInvariant();
    var base: [MAX]Candidate = undefined; identity(&base); try assertPermutation(&base);
    const f = try std.fs.cwd().createFile("../results/directed_sampler_round_j.csv", .{ .truncate = true }); defer f.close(); var w = f.writer();
    try w.writeAll("sampler,seed,prefix,candidate_calls,unique_candidate_keys,unique_masks,mod2,mod3,res2_0,res2_1,res3_0,res3_1,res3_2,mean_pairwise_mask_hamming,integrity\n");
    for (seeds) |seed| {
        var u: [MAX]Candidate = undefined; uniform(&u, seed); try writeRows(w, "uniform_without_replacement", seed, &u);
        var s: [MAX]Candidate = undefined; stratified(&s, seed); try writeRows(w, "stratified_without_replacement", seed, &s);
        var fxd: [MAX]Candidate = undefined; affine(&fxd); try writeRows(w, "fixed_affine_permutation_control", seed, &fxd);
    }
    std.debug.print("J1 PASS: {d} unique candidates = {d} masks * ({d} mod2 residues + {d} mod3 residues); all samplers duplicate-free.\n", .{ MAX, MASKS, 2, 3 });
}
