//! Runtime fork dispatcher — PASS/FAIL → next agent ID (Tier 8 orchestrator).
//! Run: zig build tier8-dispatch --release=fast

const std = @import("std");

pub const Verdict = enum { pass, fail, partial };

pub const AgentSpec = struct {
    id: []const u8,
    phase: u8,
    fork_on_pass: ?[]const u8,
    fork_on_fail: ?[]const u8,
};

pub const REGISTRY = [_]AgentSpec{
    .{ .id = "T8-AG-00a", .phase = 0, .fork_on_pass = "T8-AG-00d", .fork_on_fail = null },
    .{ .id = "T8-AG-00b", .phase = 0, .fork_on_pass = null, .fork_on_fail = null },
    .{ .id = "T8-AG-00c", .phase = 0, .fork_on_pass = null, .fork_on_fail = null },
    .{ .id = "T8-AG-01", .phase = 1, .fork_on_pass = "T8-AG-02", .fork_on_fail = "T8-AG-01b" },
    .{ .id = "T8-AG-02", .phase = 1, .fork_on_pass = "T8-AG-02f", .fork_on_fail = null },
    .{ .id = "T8-AG-06", .phase = 2, .fork_on_pass = "T8-AG-07", .fork_on_fail = "T8-AG-06b" },
    .{ .id = "T8-AG-11", .phase = 3, .fork_on_pass = "T8-AG-11f", .fork_on_fail = null },
    .{ .id = "T8-AG-31", .phase = 7, .fork_on_pass = null, .fork_on_fail = null },
};

pub fn nextFork(agent_id: []const u8, v: Verdict) ?[]const u8 {
    for (REGISTRY) |spec| {
        if (!std.mem.eql(u8, spec.id, agent_id)) continue;
        return switch (v) {
            .pass => spec.fork_on_pass,
            .fail => spec.fork_on_fail,
            .partial => spec.fork_on_fail,
        };
    }
    return null;
}

pub fn main() !void {
    const out = std.io.getStdOut().writer();
    try out.print("=== Tier 8 fork dispatch registry ({d} agents) ===\n\n", .{REGISTRY.len});
    for (REGISTRY) |spec| {
        try out.print("{s} phase={d} pass→{?s} fail→{?s}\n", .{
            spec.id,
            spec.phase,
            spec.fork_on_pass,
            spec.fork_on_fail,
        });
    }
    try out.print("\nExample: T8-AG-01 PASS → {?s}\n", .{nextFork("T8-AG-01", .pass)});
    try out.print("Example: T8-AG-01 FAIL → {?s}\n", .{nextFork("T8-AG-01", .fail)});
}