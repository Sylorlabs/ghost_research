const std = @import("std");

pub const Sampler = struct {
    allocator: std.mem.Allocator,
    rng: std.Random.Xoshiro256,

    const TokenProb = struct {
        id: u32,
        prob: f32,
    };

    pub fn init(allocator: std.mem.Allocator, seed: u64) !*Sampler {
        const self = try allocator.create(Sampler);
        self.* = .{
            .allocator = allocator,
            .rng = std.Random.Xoshiro256.init(seed),
        };
        return self;
    }

    pub fn deinit(self: *Sampler) void {
        self.allocator.destroy(self);
    }

    fn sortDesc(context: void, a: TokenProb, b: TokenProb) bool {
        _ = context;
        return a.prob > b.prob;
    }

    /// True Top-K, Top-P, and Temperature Sampling
    pub fn sample(self: *Sampler, logits: []f32, temp: f32, top_k: usize, top_p: f32) !u32 {
        const vocab_size = logits.len;
        
        // 1. Apply Temperature
        if (temp != 1.0) {
            for (0..vocab_size) |i| logits[i] /= temp;
        }

        // 2. Softmax
        var max_logit: f32 = -std.math.inf(f32);
        for (logits) |l| {
            if (l > max_logit) max_logit = l;
        }

        var sum_exp: f32 = 0.0;
        for (0..vocab_size) |i| {
            logits[i] = @exp(logits[i] - max_logit);
            sum_exp += logits[i];
        }

        var probs = try self.allocator.alloc(TokenProb, vocab_size);
        defer self.allocator.free(probs);

        for (0..vocab_size) |i| {
            probs[i] = .{ .id = @as(u32, @intCast(i)), .prob = logits[i] / sum_exp };
        }

        // 3. Sort by probability (Descending)
        std.mem.sort(TokenProb, probs, {}, sortDesc);

        // 4. Top-K Truncation
        var active_len = vocab_size;
        if (top_k > 0 and top_k < active_len) {
            active_len = top_k;
        }

        // 5. Top-P (Nucleus) Truncation
        var cumulative_prob: f32 = 0.0;
        var p_idx: usize = 0;
        while (p_idx < active_len) : (p_idx += 1) {
            cumulative_prob += probs[p_idx].prob;
            if (cumulative_prob >= top_p) {
                p_idx += 1;
                break;
            }
        }
        active_len = p_idx;

        // 6. Re-normalize probabilities over the truncated set
        var trunc_sum: f32 = 0.0;
        for (0..active_len) |i| trunc_sum += probs[i].prob;
        
        // 7. Random Sample
        const rand_val = self.rng.random().float(f32) * trunc_sum;
        var cdf: f32 = 0.0;
        for (0..active_len) |i| {
            cdf += probs[i].prob;
            if (rand_val <= cdf) {
                return probs[i].id;
            }
        }

        return probs[0].id; // Fallback
    }
};
