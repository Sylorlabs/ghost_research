//! AIMED-FORGE DIAGNOSIS PROBE (round 2026-07-10b, companion to inv_aimed.zig).
//!
//! The aimed forge produced ZERO F-solves in all arms. This probe measures WHY,
//! by characterising the residual signal itself (best depth-1 behavioural
//! agreement between a candidate program and an F target — the exact quantity
//! the aimed forge's fitness blended in):
//!
//!   1. LANDSCAPE: distribution of residual over 5000 random clean programs,
//!      per F singleton target (distinct / hashtbl / union). If the ceiling of
//!      random sampling is far below the 0.95 match bar, aiming has to CLIMB.
//!   2. CLIMB: greedy hill-climbing on residual alone (no novelty, 30k mutations,
//!      8 restarts from the best random starts) per target. If even undiluted
//!      residual pressure plateaus below 0.95, the signal is a deceptive
//!      gradient / conjunction wall — and the blended aimed forge never had a
//!      chance, independent of the blend weight.
//!   3. PROXIMITY MAP: residual of each known reference mechanism (base atoms,
//!      rmw, xorscan) vs each F singleton — how close the nearest known
//!      stepping-stone sits.
//!
//! Build:  zig build-exe -O ReleaseFast src/inv_aimed_probe.zig -femit-bin=bin/inv_aimed_probe
//! Run:    ./bin/inv_aimed_probe
//! Single-threaded, deterministic, ~1-2 min.

const std = @import("std");
const alien = @import("inv_alien.zig");
const coevo = @import("inv_coevo.zig");
const forge = @import("inv_atomforge.zig");

const V: usize = alien.CANON_BASE;
const MATCH_SEQ: usize = 8;
const MATCH_L: usize = 28;
const RESIDUAL_SEED: u64 = 0x2E51DA1; // same seed the aimed forge used
const BATTERY_SEED: u64 = 0xBA77E71;

/// Depth-1 residual: fractional per-symbol agreement between `cand` alone and a
/// hidden single-atom target — identical computation to inv_aimed.residualScore.
fn residual(cand: *const alien.Program, tgt: *const alien.Program) f64 {
    var prng = std.Random.DefaultPrng.init(RESIDUAL_SEED);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var out_a: [256]u8 = undefined;
    var out_b: [256]u8 = undefined;
    var agree: usize = 0;
    var total: usize = 0;
    for (0..MATCH_SEQ) |_| {
        for (0..MATCH_L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        alien.runStream(tgt, syms[0..MATCH_L], out_a[0..MATCH_L]);
        alien.runStream(cand, syms[0..MATCH_L], out_b[0..MATCH_L]);
        for (0..MATCH_L) |i| {
            total += 1;
            if (out_a[i] == out_b[i]) agree += 1;
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total));
}

pub fn main() !void {
    const out = std.io.getStdOut().writer();

    const targets = [_]struct { name: []const u8, prog: alien.Program }{
        .{ .name = "distinct", .prog = coevo.distinctCountProg() },
        .{ .name = "hashtbl", .prog = alien.alienHashTable() },
        .{ .name = "union", .prog = alien.alienUnion() },
    };

    var sp = alien.Params{ .active_regs = 8 };

    // ---- 1. landscape: 5000 random clean programs per target ----------------
    try out.writeAll("== 1. residual landscape over 5000 random clean programs ==\n");
    try out.writeAll("   (chance agreement at V=4 is 0.25; the certifier match bar is 0.95)\n");
    var best_starts: [targets.len][8]alien.Program = undefined; // top-8 per target for climb restarts
    var best_start_scores: [targets.len][8]f64 = .{[_]f64{0} ** 8} ** targets.len;
    {
        var prng = std.Random.DefaultPrng.init(0xD1A6);
        const rng = prng.random();
        var scores: [targets.len]std.BoundedArray(f64, 5000) = .{std.BoundedArray(f64, 5000){}} ** targets.len;
        var n_clean: usize = 0;
        while (n_clean < 5000) {
            const p = alien.randProg(rng, &sp);
            if (!forge.clean(&p, BATTERY_SEED)) continue;
            n_clean += 1;
            for (targets, 0..) |t, ti| {
                const r = residual(&p, &t.prog);
                scores[ti].appendAssumeCapacity(r);
                // keep top-8 as climb restart seeds
                var mi: usize = 0;
                for (best_start_scores[ti], 0..) |s, j| {
                    if (s < best_start_scores[ti][mi]) mi = j;
                }
                if (r > best_start_scores[ti][mi]) {
                    best_start_scores[ti][mi] = r;
                    best_starts[ti][mi] = p;
                }
            }
        }
        for (targets, 0..) |t, ti| {
            const s = scores[ti].slice();
            std.mem.sort(f64, s, {}, std.sort.asc(f64));
            try out.print("  {s:<9} p50={d:.3} p90={d:.3} p99={d:.3} max={d:.3}\n", .{
                t.name, s[s.len / 2], s[(s.len * 90) / 100], s[(s.len * 99) / 100], s[s.len - 1],
            });
        }
    }

    // ---- 2. climb: pure-residual greedy hill-climb, 8 restarts x 30k moves ---
    try out.writeAll("\n== 2. pure-residual hill-climb (8 restarts x 30k mutations, no novelty) ==\n");
    for (targets, 0..) |t, ti| {
        var best_overall: f64 = 0;
        var prng = std.Random.DefaultPrng.init(0xC11B ^ ti);
        const rng = prng.random();
        for (0..8) |r| {
            var cur = best_starts[ti][r];
            var cur_s = residual(&cur, &t.prog);
            for (0..30_000) |_| {
                var cand = cur;
                alien.mutate(rng, &cand, &sp);
                const s = residual(&cand, &t.prog);
                if (s >= cur_s) { // accept ties: neutral drift
                    cur = cand;
                    cur_s = s;
                }
            }
            if (cur_s > best_overall) best_overall = cur_s;
        }
        try out.print("  {s:<9} best-after-climb={d:.3}  ({s} the 0.95 match bar)\n", .{
            t.name, best_overall, if (best_overall >= 0.95) "REACHES" else "BELOW",
        });
    }

    // ---- 3. proximity map: known mechanisms vs the F singletons --------------
    try out.writeAll("\n== 3. proximity of known reference mechanisms to the F singletons ==\n");
    const refs = [_]struct { name: []const u8, prog: alien.Program }{
        .{ .name = "g_xor", .prog = coevo.refSolver(.g_xor) },
        .{ .name = "g_add", .prog = coevo.refSolver(.g_add) },
        .{ .name = "pk_xor", .prog = coevo.refSolver(.pk_xor) },
        .{ .name = "pk_add", .prog = coevo.refSolver(.pk_add) },
        .{ .name = "shift", .prog = forge.shiftAtom() },
        .{ .name = "rmw", .prog = alien.alienRMWCounter() },
        .{ .name = "xorscan", .prog = alien.alienXorScan() },
    };
    try out.writeAll("            ");
    for (targets) |t| try out.print("{s:>10}", .{t.name});
    try out.writeAll("\n");
    for (refs) |rf| {
        try out.print("  {s:<10}", .{rf.name});
        for (targets) |t| try out.print("{d:>10.3}", .{residual(&rf.prog, &t.prog)});
        try out.writeAll("\n");
    }
}
