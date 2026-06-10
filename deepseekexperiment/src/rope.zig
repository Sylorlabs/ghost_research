const std = @import("std");

pub const RoPE = struct {
    allocator: std.mem.Allocator,
    head_dim: usize,
    max_seq_len: usize,
    theta_base: f32,
    
    // Precomputed frequency cache
    cos_cache: []f32,
    sin_cache: []f32,

    pub fn init(allocator: std.mem.Allocator, head_dim: usize, max_seq_len: usize, theta_base: f32) !*RoPE {
        const self = try allocator.create(RoPE);
        
        const cache_size = max_seq_len * (head_dim / 2);
        const cos_cache = try allocator.alloc(f32, cache_size);
        const sin_cache = try allocator.alloc(f32, cache_size);

        // Precompute frequencies for blazing fast lookup
        for (0..max_seq_len) |pos| {
            for (0..(head_dim / 2)) |i| {
                const freq = 1.0 / std.math.pow(f32, theta_base, @as(f32, @floatFromInt(i * 2)) / @as(f32, @floatFromInt(head_dim)));
                const val = @as(f32, @floatFromInt(pos)) * freq;
                
                const cache_idx = pos * (head_dim / 2) + i;
                cos_cache[cache_idx] = @cos(val);
                sin_cache[cache_idx] = @sin(val);
            }
        }

        self.* = .{
            .allocator = allocator,
            .head_dim = head_dim,
            .max_seq_len = max_seq_len,
            .theta_base = theta_base,
            .cos_cache = cos_cache,
            .sin_cache = sin_cache,
        };
        return self;
    }

    pub fn deinit(self: *RoPE) void {
        self.allocator.free(self.cos_cache);
        self.allocator.free(self.sin_cache);
        self.allocator.destroy(self);
    }

    /// Applies Rotary Positional Embeddings to a Query or Key vector
    pub fn apply(self: *RoPE, vector: []f32, pos: usize) void {
        std.debug.assert(vector.len == self.head_dim);
        
        const cache_offset = pos * (self.head_dim / 2);
        
        var i: usize = 0;
        while (i < self.head_dim) : (i += 2) {
            const v0 = vector[i];
            const v1 = vector[i + 1];
            
            const cos_val = self.cos_cache[cache_offset + (i / 2)];
            const sin_val = self.sin_cache[cache_offset + (i / 2)];
            
            // Complex number rotation
            vector[i]     = v0 * cos_val - v1 * sin_val;
            vector[i + 1] = v0 * sin_val + v1 * cos_val;
        }
    }
};
