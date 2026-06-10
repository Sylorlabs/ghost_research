const std = @import("std");

pub const SparseMoE = struct {
    allocator: std.mem.Allocator,
    num_experts: usize,
    top_k: usize,
    hidden_dim: usize,

    pub fn init(allocator: std.mem.Allocator, num_experts: usize, top_k: usize, hidden_dim: usize) !*SparseMoE {
        const self = try allocator.create(SparseMoE);
        self.* = .{
            .allocator = allocator,
            .num_experts = num_experts,
            .top_k = top_k,
            .hidden_dim = hidden_dim,
        };
        return self;
    }

    pub fn deinit(self: *SparseMoE) void {
        self.allocator.destroy(self);
    }

    /// Calculates the routing probabilities and selects the Top-K experts.
    /// DeepSeek V4 uses a sparse MoE where only a few experts are activated per token.
    pub fn route(
        self: *SparseMoE,
        hidden_state: []const f32,
        gate_weights: []const f32, // [num_experts, hidden_dim]
        out_expert_indices: []usize,
        out_expert_weights: []f32,
    ) !void {
        std.debug.assert(out_expert_indices.len == self.top_k);
        std.debug.assert(out_expert_weights.len == self.top_k);

        const logits = try self.allocator.alloc(f32, self.num_experts);
        defer self.allocator.free(logits);

        // Calculate gate logits (hidden_state * gate_weights^T)
        for (0..self.num_experts) |e| {
            var dot: f32 = 0.0;
            const weight_row = gate_weights[e * self.hidden_dim .. (e + 1) * self.hidden_dim];
            for (0..self.hidden_dim) |i| {
                dot += hidden_state[i] * weight_row[i];
            }
            logits[e] = dot;
        }

        // Find Top-K via simple greedy scan (fine for small K like 4 or 8)
        const used = try self.allocator.alloc(bool, self.num_experts);
        defer self.allocator.free(used);
        @memset(used, false);

        var sum_exp: f32 = 0.0;

        for (0..self.top_k) |k| {
            var max_val: f32 = -std.math.inf(f32);
            var best_idx: usize = 0;

            for (0..self.num_experts) |e| {
                if (!used[e] and logits[e] > max_val) {
                    max_val = logits[e];
                    best_idx = e;
                }
            }

            used[best_idx] = true;
            out_expert_indices[k] = best_idx;
            
            // For DeepSeek, we apply sigmoid or softmax to the top K
            // Let's assume standard Softmax over Top-K
            const exp_val = @exp(logits[best_idx]);
            out_expert_weights[k] = exp_val;
            sum_exp += exp_val;
        }

        // Normalize weights
        for (0..self.top_k) |k| {
            out_expert_weights[k] /= sum_exp;
        }
    }
};
