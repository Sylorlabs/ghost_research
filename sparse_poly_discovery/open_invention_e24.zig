//! EXPERIMENT E24 — k≥3 aliens with order-stats.
//!
//! Question: Can k3_order_escape solve E6's 16 aliens without Walsh?
//! Protocol: k3_order_escape full substrate (mono + modK + order-stats) on E6's certified
//! alien target distribution (k=3 and k=4, pinned seed). No Boolean Fourier / Walsh menu.
//!
//! Pass bar: ≥4/16 certified promotions (escape ≥0.90 held-out + irreducible R²<0.40).
//!
//! Reuses: open_invention_e6.zig (alien certification + target draw), k3_order_escape.zig (forge).
//!
//! Run: zig build open-invention-e24 --release=fast

const std = @import("std");
const e6 = @import("open_invention_e6.zig");
const k3 = @import("k3_order_escape.zig");

const PASS_PROMOS: usize = 4;
const NTOTAL: usize = e6.NT_ALIEN * e6.K_VALUES.len;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    try out.print("=== Experiment E24: k3_order_escape on E6 alien distribution (no Walsh) ===\n\n", .{});
    try out.print("E6 alien seed = 0x{X:0>16} (pinned)\n", .{e6.RNG_SEED});
    try out.print("substrate: k3_order_escape FULL pool (mono + modK + order-stats)\n", .{});
    try out.print("targets: E6 certified aliens ({d} per k, k=3,4)\n", .{e6.NT_ALIEN});
    try out.print("pass bar: ≥{d}/{d} certified promotions\n", .{ PASS_PROMOS, NTOTAL });
    try out.print("train/val/test {d}/{d}/{d}\n\n", .{ e6.NTR, e6.NVA - e6.NTR, e6.NSAMP - e6.NVA });

    var total_solved: usize = 0;
    var total_promos: usize = 0;
    var total_nonmono: usize = 0;

    for (e6.K_VALUES) |k_val| {
        var prng = std.Random.DefaultPrng.init(e6.RNG_SEED +% @as(u64, k_val));
        const rand = prng.random();

        const grid = try alloc.alloc([e6.NCELL]u8, e6.NSAMP);
        for (0..e6.NSAMP) |s| for (0..e6.NCELL) |i| {
            grid[s][i] = rand.intRangeAtMost(u8, 0, k_val - 1);
        };

        const X = try alloc.alloc([]f64, e6.NSAMP);
        const Xrec = try alloc.alloc([]f64, e6.NSAMP);
        for (0..e6.NSAMP) |s| {
            X[s] = try alloc.alloc(f64, k3.MAXATOMS);
            Xrec[s] = try alloc.alloc(f64, k3.MAXATOMS);
        }
        const phiTgt = try alloc.alloc(f64, e6.NSAMP);
        var w: [k3.MAXATOMS + 1]f64 = undefined;

        try out.print("════════ k={d} E6 alien targets (structural cert, base<{d:.2}) ════════\n", .{ k_val, e6.BASE_OUTSIDE_THRESH });
        const gen = try e6.generateAlienTargets(alloc, grid, rand, k_val, X, &w, out);
        try out.print("\n", .{});

        const Y = try alloc.alloc([]f64, gen.targets.len);
        for (0..gen.targets.len) |t| {
            Y[t] = try alloc.alloc(f64, e6.NSAMP);
            for (0..e6.NSAMP) |s| Y[t][s] = gen.targets[t].eval(grid[s], k_val);
        }

        const result = try k3.runAlienForge(.full, k_val, grid, Y, gen.labels, X, Xrec, phiTgt, &w, out);

        total_solved += result.nsolved;
        total_promos += result.promotions.len;

        try out.print("certified promotions (k={d}):\n", .{k_val});
        if (result.promotions.len == 0) {
            try out.print("  (none)\n", .{});
        } else {
            for (result.promotions) |p| {
                var lbl: [64]u8 = undefined;
                const name = p.atom.label(k_val, &lbl);
                const nonmono = p.atom.kind != .monomial;
                if (nonmono) total_nonmono += 1;
                try out.print("  A{d} ← {s}  (R²={d:.2}, escape={d:.2}{s})\n", .{
                    p.target_idx + 1,
                    name,
                    p.r2,
                    p.escape,
                    if (nonmono) " [non-mono]" else "",
                });
            }
        }
        try out.print("\n", .{});

        std.heap.page_allocator.free(result.promotions);
    }

    const pass = total_promos >= PASS_PROMOS;

    try out.print("════════════════════ VERDICT (E24) ════════════════════\n", .{});
    try out.print("aggregate solve rate: {d}/{d} ({d:.1}%)\n", .{
        total_solved,
        NTOTAL,
        @as(f64, @floatFromInt(total_solved * 100)) / @as(f64, @floatFromInt(NTOTAL)),
    });
    try out.print("certified promotions: {d}/{d}\n", .{ total_promos, NTOTAL });
    try out.print("non-monomial promotions: {d}\n", .{total_nonmono});
    try out.print("pass bar (≥{d} promotions): {s}\n\n", .{ PASS_PROMOS, if (pass) "PASS" else "FAIL" });

    if (pass) {
        try out.print("ORDER-STAT SUBSTRATE ESCAPES some E6 aliens without Walsh.\n", .{});
        try out.print("k3_order_escape rank/mod pool crosses family boundaries on random aliens.\n", .{});
    } else if (total_promos > 0) {
        try out.print("PARTIAL: some promotions but below pass bar — order-stats help marginally.\n", .{});
        try out.print("Most E6 aliens remain outside mono+modK+order closure (mul/affine/parity/count).\n", .{});
    } else {
        try out.print("FAIL: k3_order_escape full substrate solves 0 E6 aliens with certified promotion.\n", .{});
        try out.print("Order-stats break the T6 median wall on designed targets but not E6's random aliens.\n", .{});
        try out.print("Same closure law as E6 — richer substrate without Walsh still saturates on cross-family preds.\n", .{});
    }

    try out.print("\nHONEST SCOPE: E6 alien families unchanged; only forge substrate swapped to k3_order_escape.\n", .{});
    try out.print("No Walsh/spectral menu. Promotions require escape≥0.90 test + R²<0.40 irreducibility.\n", .{});
    try out.print("\nSee: open_invention_e6.zig, k3_order_escape.zig, open_invention_e6.md, open_invention_e24.md\n", .{});
}