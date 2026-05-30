//! Telemetry — plain-text logging and the milestone markers (Section 6).
//!
//! Kept dependency-light (takes a writer and primitive values) so it can be
//! called from anywhere without import cycles.

const std = @import("std");

pub fn init(w: anytype, base_types: usize, combinators: usize, total_nodes: usize) !void {
    try w.print("[INIT] Library size: {d} base types, {d} combinators. Total nodes: {d}.\n", .{ base_types, combinators, total_nodes });
}

pub fn wakeBatch(w: anytype, k: usize) !void {
    try w.print("[WAKE] Batch of {d} programs collected (fully unrolled — no recursion exists yet).\n", .{k});
}

pub fn sleepHeader(w: anytype) !void {
    try w.writeAll("[SLEEP] Evaluating W-type proposals...\n");
}

fn writeArities(w: anytype, arities: []const u8) !void {
    try w.writeAll("[");
    for (arities, 0..) |ar, i| {
        if (i != 0) try w.writeAll(",");
        // arity 1 == one recursive subtree (Unit position); 0 == leaf (Bottom)
        try w.writeAll(if (ar == 1) "Unit" else "Bottom");
    }
    try w.writeAll("]");
}

pub fn candidate(w: anytype, shape_name: []const u8, arities: []const u8, capable: bool, delta: i64) !void {
    try w.print("  Candidate Shape={s}, Pos=", .{shape_name});
    try writeArities(w, arities);
    if (!capable) {
        try w.writeAll(" -> Rejected (cannot host iteration: needs one leaf + one unary constructor)\n");
    } else if (delta > 0) {
        try w.print(" -> hosts pattern, saves {d} nodes\n", .{delta});
    } else {
        try w.print(" -> hosts pattern, but no net saving ({d} nodes)\n", .{delta});
    }
}

pub fn accepted(w: anytype, name: []const u8) !void {
    try w.print("[ACCEPT] Best proposal: {s}\n", .{name});
}

pub fn milestone(w: anytype, name: []const u8, saved: usize) !void {
    try w.print("[MILESTONE] New type invented: {s} - node count saved: {d}\n", .{ name, saved });
}

pub fn naturals(w: anytype) !void {
    try w.writeAll(">> ENGINE INVENTED THE NATURAL NUMBERS <<\n");
}

pub fn binaryTrees(w: anytype) !void {
    try w.writeAll(">> ENGINE INVENTED BINARY TREES (a DIFFERENT W-type, same blind rule) <<\n");
}

pub fn noProposal(w: anytype) !void {
    try w.writeAll("[SLEEP] No W-type proposal reduced the node count. Library unchanged.\n");
}

pub fn compression(w: anytype, old_total: usize, new_total: usize) !void {
    const before: f64 = 1.0;
    const after: f64 = if (new_total == 0) 0.0 else @as(f64, @floatFromInt(old_total)) / @as(f64, @floatFromInt(new_total));
    try w.print("[TELEMETRY] Compression ratio improved from {d:.2} to {d:.2}.\n", .{ before, after });
}

pub fn librarySummary(w: anytype, types_count: usize, combinators: usize, total_nodes: usize) !void {
    try w.print("[FINAL] Library: {d} types, {d} combinators, {d} total nodes.\n", .{ types_count, combinators, total_nodes });
}
