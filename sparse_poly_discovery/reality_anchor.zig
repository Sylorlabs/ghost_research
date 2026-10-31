//! Reality anchor trait — T8-AG-26 core. Out-of-symbol contact beyond grid held-out.
const std = @import("std");
const ui = @import("unified_invention.zig");
const eqtax = @import("equivalence_tax.zig");

pub const AnchorResult = struct {
    ok: bool,
    source: []const u8,
    detail: []const u8,
};

pub const FileExpect = struct {
    feature_tag: u8,
    feature_param: u64,
    min_test_acc: f64,
};

pub const FileAnchor = struct {
    path: []const u8,

    pub fn evaluate(self: FileAnchor, cand: ui.Feature, test_acc: f64) !AnchorResult {
        const file = std.fs.cwd().openFile(self.path, .{}) catch {
            return .{ .ok = false, .source = "file", .detail = "missing expect file" };
        };
        defer file.close();
        var buf: [512]u8 = undefined;
        const n = try file.read(&buf);
        const raw = buf[0..n];
        // Minimal parse: tag=N param=N acc=N
        var tag: u8 = 255;
        var param: u64 = 0;
        var acc: f64 = 0;
        var it = std.mem.splitScalar(u8, raw, '\n');
        while (it.next()) |line| {
            if (std.mem.startsWith(u8, line, "tag=")) tag = @intCast(std.fmt.parseInt(usize, line[4..], 10) catch 255);
            if (std.mem.startsWith(u8, line, "param=")) param = std.fmt.parseInt(u64, line[6..], 10) catch 0;
            if (std.mem.startsWith(u8, line, "acc=")) acc = std.fmt.parseFloat(f64, line[4..]) catch 0;
        }
        const ct = @intFromEnum(std.meta.activeTag(cand));
        const cp = switch (cand) {
            .world_sum_mod => |p| @as(u64, p),
            .world_sign_mod => |p| @as(u64, p),
            .walsh => |s| s,
            .monomial => |m| m,
            else => 0,
        };
        const ok = ct == tag and cp == param and test_acc >= acc;
        return .{
            .ok = ok,
            .source = "file",
            .detail = if (ok) "file oracle match" else "file oracle mismatch",
        };
    }
};

pub const PeerReplayAnchor = struct {
    peer_seed: u64,

    pub fn evaluate(
        self: PeerReplayAnchor,
        alloc: std.mem.Allocator,
        lib: []const ui.Feature,
        cand: ui.Feature,
        Y: []const f64,
    ) !AnchorResult {
        const ie = @import("invention_engine.zig");
        const SilentOut = struct {
            pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
        };
        const prep = try ie.prepareBlindBatterySeed(alloc, self.peer_seed, SilentOut{});
        const saved_strict = eqtax.strict_enabled;
        const saved_level = eqtax.basis_level;
        eqtax.strict_enabled = true;
        eqtax.basis_level = 3;
        defer {
            eqtax.strict_enabled = saved_strict;
            eqtax.basis_level = saved_level;
        }
        const w = eqtax.witnessRemix(prep.ctx.grid, lib, cand, Y);
        const ok = w.verdict == .novel;
        return .{
            .ok = ok,
            .source = "peer_replay",
            .detail = if (ok) "peer seed tax-survivor" else "peer seed remix",
        };
    }
};

pub const RealityAnchor = union(enum) {
    file: FileAnchor,
    peer_replay: PeerReplayAnchor,

    pub fn check(
        self: RealityAnchor,
        alloc: std.mem.Allocator,
        lib: []const ui.Feature,
        cand: ui.Feature,
        Y: []const f64,
        test_acc: f64,
    ) !AnchorResult {
        return switch (self) {
            .file => |a| a.evaluate(cand, test_acc),
            .peer_replay => |a| a.evaluate(alloc, lib, cand, Y),
        };
    }
};