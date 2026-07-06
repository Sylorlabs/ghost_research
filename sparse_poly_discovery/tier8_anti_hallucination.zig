//! T8-AG-09 — Anti-hallucination: noise proposals must not certify.
//! Run: zig build tier8-anti-hallucination --release=fast

const std = @import("std");
const e11 = @import("open_invention_e11.zig");
const ui = @import("unified_invention.zig");

const CERT: f64 = 0.90;
const NOISE = [_]struct { name: []const u8, kind: e11.FormulaKind, params: e11.Params }{
    .{ .name = "gcd_noise", .kind = .gcd_masked, .params = .{ .mask = 255 } },
    .{ .name = "sin_variance_noise", .kind = .variance_sin, .params = .{ .scale = 1.0 } },
    .{ .name = "median_noise", .kind = .median_centered, .params = .{} },
    .{ .name = "harmonic_noise", .kind = .harmonic_mean, .params = .{} },
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var prng = std.Random.DefaultPrng.init(0xBADF00D20260706);
    const grid = try alloc.alloc([8]u8, ui.NSAMP);
    const Y = try alloc.alloc(f64, ui.NSAMP);
    const scratch = try alloc.alloc(f64, ui.NSAMP);
    for (0..ui.NSAMP) |s| {
        for (0..8) |i| grid[s][i] = prng.random().intRangeAtMost(u8, 0, 5);
        Y[s] = e11.label(grid[s], .parity);
    }

    try out.print("=== T8-AG-09: Anti-hallucination suite ===\n\n", .{});
    var false_certs: usize = 0;
    for (NOISE) |n| {
        for (0..ui.NSAMP) |s| scratch[s] = e11.evalFeature(grid[s], n.kind, n.params);
        const tst = e11.accLogit(scratch, Y, ui.NVA, ui.NSAMP);
        const certified = tst >= CERT;
        if (certified) false_certs += 1;
        try out.print("  {s}: test={d:.3} {s}\n", .{ n.name, tst, if (certified) "CERT (bad)" else "reject" });
    }
    const pass = false_certs == 0;
    try out.print("\n  false certifies: {d}\n", .{false_certs});
    try out.print("  VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
}