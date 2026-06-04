const std = @import("std");
const prover = @import("native_prover");
const memory = @import("domain_concept_memory");

pub const DOMAIN_NAME: []const u8 = "agi-creative-divergence";

pub const DivergenceObjective = struct {
    mem: *memory.ConceptMemory,

    pub fn init(mem: *memory.ConceptMemory) DivergenceObjective {
        return .{ .mem = mem };
    }

    /// Rewards structural novelty. 
    /// The more 'distant' the AIG graph is from the library, the higher the reward.
    pub fn calculateFitness(self: *DivergenceObjective, aig: prover.Aig, root: prover.NodeId) f64 {
        var min_distance: f64 = 1000.0;
        
        // Find the distance to the *closest* concept (the most familiar concept)
        for (self.mem.library.items) |c| {
            const dist = self.structuralDistance(aig, root, c.root_node);
            if (dist < min_distance) min_distance = dist;
        }

        // We want to maximize the distance to the familiar
        return min_distance;
    }

    fn structuralDistance(self: *DivergenceObjective, aig: prover.Aig, n1: prover.NodeId, n2: prover.NodeId) f64 {
        _ = self;
        // Simple structural distance: 
        // 0.0 = identical, 1.0 = completely disjoint.
        const v1 = aig.getSimValue(n1);
        const v2 = aig.getSimValue(n2);
        return @as(f64, @floatFromInt(@popCount(v1 ^ v2))) / 64.0;
    }
};
