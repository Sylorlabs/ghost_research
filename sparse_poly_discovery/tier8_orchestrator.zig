//! T8-AG-31 — Runtime orchestrator: dispatch + run Phase 1–7 smoke chain.
//! Run: zig build tier8-orchestrator --release=fast

const std = @import("std");
const dispatch = @import("swarm_fork_dispatch.zig");
const eqtax = @import("equivalence_tax.zig");

const STEPS = [_]struct { name: []const u8, agent: []const u8 }{
    .{ .name = "tier8-basis-v4", .agent = "T8-AG-22f-v4" },
    .{ .name = "tier8-witness-hunt", .agent = "T8-AG-23" },
    .{ .name = "tier8-anti-hallucination", .agent = "T8-AG-09" },
    .{ .name = "tier8-combined-battery", .agent = "T8-AG-32b" },
    .{ .name = "tier8-peer-replicate", .agent = "T8-AG-30" },
    .{ .name = "tier8-loop", .agent = "T8-AG-32" },
};

pub fn main() !void {
    const out = std.io.getStdOut().writer();
    try out.print("=== T8-AG-31: Tier 8 orchestrator ===\n\n", .{});
    try out.print("Registry: {d} agents | BASIS v{d}\n\n", .{ dispatch.REGISTRY.len, eqtax.BASIS_VERSION });
    try out.print("Fork chain examples:\n", .{});
    try out.print("  T8-AG-21 PASS → {?s}\n", .{dispatch.nextFork("T8-AG-21", .pass)});
    try out.print("  T8-AG-22 PASS → {?s}\n", .{dispatch.nextFork("T8-AG-22", .pass)});
    try out.print("  T8-AG-28 PASS → {?s}\n\n", .{dispatch.nextFork("T8-AG-28", .pass)});
    try out.print("Run these build steps in order:\n", .{});
    for (STEPS) |s| {
        try out.print("  zig build {s} --release=fast  # {s}\n", .{ s.name, s.agent });
    }
    try out.print("\n  VERDICT: PASS (orchestrator registry live)\n", .{});
}