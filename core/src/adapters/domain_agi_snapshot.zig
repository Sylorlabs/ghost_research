const std = @import("std");

pub const Snapshot = struct {
    aig_nodes_count: usize,
    vitality_score: f64,
    hash: u64,
};

pub const SnapshotManager = struct {
    allocator: std.mem.Allocator,
    history: std.ArrayList(Snapshot),

    pub fn init(allocator: std.mem.Allocator) SnapshotManager {
        return .{
            .allocator = allocator,
            .history = std.ArrayList(Snapshot).init(allocator),
        };
    }

    pub fn deinit(self: *SnapshotManager) void {
        self.history.deinit();
    }

    pub fn takeSnapshot(self: *SnapshotManager, nodes: usize, vitality: f64, hash: u64) !void {
        try self.history.append(.{ .aig_nodes_count = nodes, .vitality_score = vitality, .hash = hash });
    }

    pub fn getLatest(self: *SnapshotManager) ?Snapshot {
        if (self.history.items.len == 0) return null;
        return self.history.items[self.history.items.len - 1];
    }
};
