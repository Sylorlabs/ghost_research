const std = @import("std");

pub const DOMAIN_NAME: []const u8 = "agi-subjectivity-model";

// A 'Subjective State' is just a persistent register that tracks 
// the AIG model's impact on the external environment.
pub const SubjectiveState = struct {
    self_hash: u64,
    world_model_fidelity: f64,
    intention_vector: [8]f64,

    pub fn reflect(self: *SubjectiveState, aig_nodes: usize, world_prediction_error: f64) void {
        self.world_model_fidelity = 1.0 / (1.0 + world_prediction_error);
        // The engine perceives its own complexity (nodes) relative to the world
        self.intention_vector[0] = @as(f64, @floatFromInt(aig_nodes)) / 1000.0;
    }
};
