//! T8-AG-16 — Cross-audit primary vs independent coverage/certify.
//!
//! PASS: 0 verdict flips on 4096 stress trials (lib size 1..32).
//!
//! Run: zig build tier8-cert-cross-audit --release=fast

const std = @import("std");
const ui = @import("unified_invention.zig");
const audit = @import("coverage_audit.zig");
const ie = @import("invention_engine.zig");
const rq1 = @import("open_invention_rq1.zig");

const STRESS_TRIALS: usize = 4096;
const MAX_LIB: usize = 32;

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    const prep = try ie.prepareBlindBattery(alloc, SilentOut{});

    var prng = std.Random.DefaultPrng.init(0xC16A20260706);
    const rand = prng.random();

    var cov_flips: usize = 0;
    var cert_flips: usize = 0;

    const X = prep.ctx.X;
    const grid = prep.ctx.grid;
    var w: [33]f64 = undefined;
    var scratch: [ui.NSAMP]f64 = undefined;

    try out.print("=== T8-AG-16: Cert cross-audit ({d} stress trials) ===\n\n", .{STRESS_TRIALS});

    for (0..STRESS_TRIALS) |_| {
        const tgt = prep.ctx.battery[rand.intRangeAtMost(usize, 0, prep.ctx.battery.len - 1)];
        const Yb = try alloc.alloc(f64, rq1.NSAMP);
        for (0..rq1.NSAMP) |s| Yb[s] = rq1.labelBattery(grid[s], tgt);

        const nlib = rand.intRangeAtMost(usize, 1, 8);
        var lib: [MAX_LIB]ui.Feature = undefined;
        for (0..nlib) |i| {
            lib[i] = .{ .monomial = @intCast(rand.intRangeAtMost(u16, 1, 255)) };
        }
        const cand: ui.Feature = .{ .monomial = @intCast(rand.intRangeAtMost(u16, 1, 255)) };

        const cov_pri = ui.measureCoverage(X, grid, lib[0..nlib], Yb, &w);
        const cov_aud = audit.measureCoverageAudit(X, grid, lib[0..nlib], Yb, &w);
        if (!audit.coverageAgrees(cov_pri, cov_aud)) cov_flips += 1;

        const cert_pri = ui.certifyPublic(X, grid, lib[0..nlib], cand, Yb, &scratch, &w);
        const cert_aud = audit.certifyAudit(X, grid, lib[0..nlib], cand, Yb, &scratch, &w);
        if (!audit.certifyAgrees(cert_pri, cert_aud)) cert_flips += 1;

        alloc.free(Yb);
    }

    try out.print("  trials: {d}\n", .{STRESS_TRIALS});
    try out.print("  coverage flips: {d}\n", .{cov_flips});
    try out.print("  certify flips: {d}\n", .{cert_flips});
    const pass = cov_flips == 0 and cert_flips == 0;
    try out.print("  VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
}