//! T8-AG-26 — RealityAnchor trait smoke (file + peer replay).
//! Run: zig build tier8-reality-anchor --release=fast

const std = @import("std");
const ie = @import("invention_engine.zig");
const eqtax = @import("equivalence_tax.zig");
const ui = @import("unified_invention.zig");
const ra = @import("reality_anchor.zig");

const PEER_SEED: u64 = 0xA7C0DE20260629;

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    eqtax.strict_enabled = true;
    eqtax.basis_level = 3;

    const prep = try ie.prepareBlindBatterySeed(alloc, ie.GRID_SEED, SilentOut{});
    var lib: [32]ui.Feature = undefined;
    var nlib: usize = 0;
    ie.seedUiFromRq1(prep.trained_lib, &lib, &nlib);

    const survivor: ui.Feature = .{ .world_sum_mod = 7 };
    const Y = try alloc.alloc(f64, ui.NSAMP);
    for (0..ui.NSAMP) |s| {
        var sum: usize = 0;
        for (0..8) |i| sum += prep.ctx.grid[s][i];
        Y[s] = if (sum % 7 == 0) 1.0 else 0.0;
    }

    std.fs.cwd().makePath("/tmp/tier8-swarm") catch {};
    const tag = @intFromEnum(std.meta.activeTag(survivor));
    const ef = try std.fs.cwd().createFile("/tmp/tier8-swarm/reality_expect.txt", .{});
    defer ef.close();
    try ef.writer().print("tag={d}\nparam=7\nacc=0.90\n", .{tag});

    try out.print("=== T8-AG-26: Reality anchor trait ===\n\n", .{});

    const file_anchor: ra.RealityAnchor = .{ .file = .{ .path = "/tmp/tier8-swarm/reality_expect.txt" } };
    const peer_anchor: ra.RealityAnchor = .{ .peer_replay = .{ .peer_seed = PEER_SEED } };

    const r_file = try file_anchor.check(alloc, lib[0..nlib], survivor, Y, 1.0);
    const r_peer = try peer_anchor.check(alloc, lib[0..nlib], survivor, Y, 1.0);

    try out.print("  file anchor: {} ({s})\n", .{ r_file.ok, r_file.detail });
    try out.print("  peer replay: {} ({s})\n", .{ r_peer.ok, r_peer.detail });

    const pass = r_file.ok or r_peer.ok;
    try out.print("  VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
}