const std = @import("std");

pub const DOMAIN_NAME: []const u8 = "agi-curiosity-engine";

/// The Curiosity Engine rewards 'Novelty' and 'Prediction Error'.
/// If the engine finds a structure it cannot predict, it gets a reward.
pub const CuriosityObjective = struct {
    known_concepts: std.AutoHashMap(u64, bool), // Simplified: Hash of structures
    
    pub fn init(allocator: std.mem.Allocator) CuriosityObjective {
        return .{ .known_concepts = std.AutoHashMap(u64, bool).init(allocator) };
    }

    pub fn deinit(self: *CuriosityObjective) void {
        self.known_concepts.deinit();
    }

    /// Reward based on Information Gain
    pub fn calculateReward(self: *CuriosityObjective, structure_hash: u64) f64 {
        if (self.known_concepts.contains(structure_hash)) {
            return 0.0; // Boring
        } else {
            self.known_concepts.put(structure_hash, true) catch unreachable;
            return 1.0; // Surprising
        }
    }
};
