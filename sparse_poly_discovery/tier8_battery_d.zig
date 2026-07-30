//! T8-battery-D — the "decisive band" battery for the Tier 8 ablation.
//!
//! Motivation (docs/research/tier8_ablation.md Diagnosis): the 2026-07-10
//! ablation found the decisive band (targets the ladder CAN certify an escape
//! for, but v3's greedy-remix tax blocks) contains essentially one member,
//! C08 "parity count". C08's mechanism: the ladder's Walsh route exhaustively
//! searches all 256 masks S over signPattern(g) (cells thresholded at >=3,
//! THRESH=3 hard-coded in unified_invention.zig) and finds S=0xFF, which is an
//! EXACT predictor of parity(count(cells>=3)) since XOR-of-all-bits(p) ==
//! popcount(p) mod 2. The v3 tax's mod-synth bank (equivalence_tax.zig
//! ProgBank, leaves {count2,count3,count4,inv,sum}, ops
//! add/mul/sin/mod(k=2..8), depth<=3) contains the node mod(count3,2), which
//! is the SAME function under a different name -> greedy remix fit reaches
//! COVER without the candidate -> blocked.
//!
//! This file generalizes that exact coincidence along the two axes the
//! diagnosis named:
//!   1. sum(g) % k  for k in the ladder's WORLD_POOL primes {2,3,5,7,11,13}.
//!      world_sum_mod(k) is an EXACT ladder feature (tryWorldPool). The tax's
//!      mod-synth bank has leaf `sum` and mod-node k range 2..8 -> k in
//!      {2,3,5,7} should be exactly remixable (mod(sum,k) node), k in
//!      {11,13} should NOT (outside the bank's k range) -- a built-in
//!      boundary probe.
//!   2. count(cells>=3) % k for k in {3,4,5,6} (k=2 is C08 itself, excluded).
//!      Ladder route: NOT Walsh (a single Walsh mask can only express GF(2)
//!      *linear* i.e. mod-2 functions of the bits of p, not mod-k for k>2),
//!      but the MENU's spectral_count feature cos(omega * count3): for any
//!      integer target period k, omega = 2*pi/k gives cos(omega*c) == 1 iff
//!      c%k==0 and <1 otherwise (over the small integer domain c in 0..8),
//!      so a single linear threshold on this one feature is an exact
//!      separator whenever discoverSpectral's 200-point frequency grid lands
//!      close enough to 2*pi/k. The tax's mod-synth bank has mod(count3,k)
//!      for the same k range 2..8 -> should remix.
//!   3. One "walsh-of-subset" composite (parity of a PROPER subset of the 8
//!      cells' sign bits, not all 8): ladder-reachable exactly (discoverWalsh
//!      is an exhaustive argmax over all 256 masks, so it finds the exact
//!      subset mask), but the tax's mod-synth bank only knows the FULL-grid
//!      aggregate counts, not any subset count, and (because p is uniform
//!      over GF(2)^8 under this generator) the tax's own top-32 correlated
//!      Walsh statics are ~orthogonal to any OTHER single Walsh mask -- so
//!      this is predicted to land OUTSIDE the decisive band (too easy),
//!      included specifically to characterize *why* subset choice matters
//!      (band membership is empirical, not assumed -- see culture note in
//!      the round prompt).
//!
//! Every target's ground-truth Y is a pure function of the 8-cell grid; no
//! oracle/dictionary tricks. `labelTarget` is the single source of truth.

const std = @import("std");

pub const DKind = enum { sum_mod, count3_mod, subset_parity };

pub const BatteryDTarget = struct {
    name: []const u8,
    kind: DKind,
    modulus: u8 = 0,
    subset_mask: u8 = 0,
    /// Predicted ladder route (documentation only, not enforced).
    predicted_route: []const u8 = "",
    /// Predicted tax fate (documentation only).
    predicted_fate: []const u8 = "",
};

fn gridSum(g: [8]u8) usize {
    var s: usize = 0;
    for (g) |v| s += v;
    return s;
}

fn countGE3(g: [8]u8) usize {
    var c: usize = 0;
    for (g) |v| {
        if (v >= 3) c += 1;
    }
    return c;
}

pub fn labelTarget(g: [8]u8, t: BatteryDTarget) f64 {
    return switch (t.kind) {
        .sum_mod => if (gridSum(g) % t.modulus == 0) 1.0 else 0.0,
        .count3_mod => if (countGE3(g) % t.modulus == 0) 1.0 else 0.0,
        .subset_parity => blk: {
            var p: usize = 0;
            for (0..8) |i| {
                if ((t.subset_mask & (@as(u8, 1) << @intCast(i))) != 0 and g[i] >= 3) p += 1;
            }
            break :blk @floatFromInt(p & 1);
        },
    };
}

/// Base rate (fraction of samples with Y=1) -- reported for honesty; skewed
/// base rates near 0 or 1 let a majority-class predictor "solve" a target
/// without any real escape, which would show up as both arms solving from
/// cov0 already >=COVER (a TOO-EASY verdict, not a bug).
pub fn baseRate(grid: []const [8]u8, t: BatteryDTarget) f64 {
    var pos: usize = 0;
    for (grid) |g| {
        if (labelTarget(g, t) > 0.5) pos += 1;
    }
    return @as(f64, @floatFromInt(pos)) / @as(f64, @floatFromInt(grid.len));
}

/// D01-D06: sum(g) % k for the ladder's own WORLD_POOL primes.
/// D07-D10: count(cells>=3) % k, k=3..6 (k=2 is C08 itself).
/// D11    : subset-Walsh parity boundary probe.
pub const BATTERY_D = [_]BatteryDTarget{
    .{ .name = "D01 sum%2", .kind = .sum_mod, .modulus = 2, .predicted_route = "world_sum_mod(2)", .predicted_fate = "remix via mod(sum,2)" },
    .{ .name = "D02 sum%3", .kind = .sum_mod, .modulus = 3, .predicted_route = "world_sum_mod(3)", .predicted_fate = "remix via mod(sum,3)" },
    .{ .name = "D03 sum%5", .kind = .sum_mod, .modulus = 5, .predicted_route = "world_sum_mod(5)", .predicted_fate = "remix via mod(sum,5)" },
    .{ .name = "D04 sum%7", .kind = .sum_mod, .modulus = 7, .predicted_route = "world_sum_mod(7)", .predicted_fate = "remix via mod(sum,7)" },
    .{ .name = "D05 sum%11", .kind = .sum_mod, .modulus = 11, .predicted_route = "world_sum_mod(11)", .predicted_fate = "NOT remixable (k>8, boundary probe)" },
    .{ .name = "D06 sum%13", .kind = .sum_mod, .modulus = 13, .predicted_route = "world_sum_mod(13)", .predicted_fate = "NOT remixable (k>8, boundary probe)" },
    .{ .name = "D07 count3%3", .kind = .count3_mod, .modulus = 3, .predicted_route = "spectral_count (menu)", .predicted_fate = "remix via mod(count3,3)" },
    .{ .name = "D08 count3%4", .kind = .count3_mod, .modulus = 4, .predicted_route = "spectral_count (menu)", .predicted_fate = "remix via mod(count3,4)" },
    .{ .name = "D09 count3%5", .kind = .count3_mod, .modulus = 5, .predicted_route = "spectral_count (menu)", .predicted_fate = "remix via mod(count3,5)" },
    .{ .name = "D10 count3%6", .kind = .count3_mod, .modulus = 6, .predicted_route = "spectral_count (menu)", .predicted_fate = "remix via mod(count3,6)" },
    .{ .name = "D11 subset-parity{0-3}", .kind = .subset_parity, .subset_mask = 0x0F, .predicted_route = "walsh (exact S=0x0F)", .predicted_fate = "predicted NOT remixable (no subset-count leaf); boundary probe" },
};
