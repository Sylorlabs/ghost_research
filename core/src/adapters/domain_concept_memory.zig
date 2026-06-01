const std = @import("std");
const prover = @import("native_prover");

pub const Concept = struct {
    name: []const u8,
    root_node: prover.NodeId,
    complexity: usize,
};

pub const ConceptMemory = struct {
    allocator: std.mem.Allocator,
    library: std.ArrayList(Concept),

    pub fn init(allocator: std.mem.Allocator) ConceptMemory {
        return .{
            .allocator = allocator,
            .library = std.ArrayList(Concept).init(allocator),
        };
    }

    pub fn deinit(self: *ConceptMemory) void {
        for (self.library.items) |c| self.allocator.free(c.name);
        self.library.deinit();
    }

    /// Tries to name a discovered AIG structure using functional equivalence (SIM values).
    pub fn nameStructure(self: *ConceptMemory, aig: prover.Aig, root: prover.NodeId) !?[]const u8 {
        const root_sim = aig.getSimValue(root);
        for (self.library.items) |c| {
            const c_sim = aig.getSimValue(c.root_node);
            if (root_sim == c_sim) {
                return c.name;
            }
        }
        return null;
    }

    pub fn register(self: *ConceptMemory, name: []const u8, root: prover.NodeId, complexity: usize) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        try self.library.append(.{ .name = name_copy, .root_node = root, .complexity = complexity });
    }
};
