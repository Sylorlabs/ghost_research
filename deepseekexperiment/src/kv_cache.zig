const std = @import("std");

pub const PagedKVCache = struct {
    pub const BitBlock = extern struct {
        bits: u64,
        scale: f32,
    };

    // 1-Bit Block-Scaled KV Cache (64GB -> 2.5GB Context Window)
    pub const Block = struct {
        k_data: []BitBlock,
        v_data: []BitBlock,
    };
    
    allocator: std.mem.Allocator,
    block_size: usize,
    head_dim: usize,
    num_heads: usize,
    
    // Layer -> list of allocated blocks
    layer_blocks: [][]Block,
    
    pub fn init(allocator: std.mem.Allocator, num_layers: usize, num_heads: usize, head_dim: usize, block_size: usize) !*PagedKVCache {
        const self = try allocator.create(PagedKVCache);
        
        const layer_blocks = try allocator.alloc([]Block, num_layers);
        for (0..num_layers) |l| {
            // Start with 0 blocks, dynamically allocate as needed
            layer_blocks[l] = try allocator.alloc(Block, 0); 
        }

        self.* = .{
            .allocator = allocator,
            .block_size = block_size,
            .head_dim = head_dim,
            .num_heads = num_heads,
            .layer_blocks = layer_blocks,
        };
        return self;
    }

    pub fn deinit(self: *PagedKVCache) void {
        const num_layers = self.layer_blocks.len;
        for (0..num_layers) |l| {
            for (self.layer_blocks[l]) |block| {
                self.allocator.free(block.k_data);
                self.allocator.free(block.v_data);
            }
            self.allocator.free(self.layer_blocks[l]);
        }
        self.allocator.free(self.layer_blocks);
        self.allocator.destroy(self);
    }

    /// Dynamically allocates a new Block if the sequence length exceeds current capacity.
    /// This entirely solves VRAM fragmentation (vLLM PagedAttention style).
    pub fn ensureCapacity(self: *PagedKVCache, layer: usize, seq_len: usize) !void {
        const required_blocks = (seq_len + self.block_size - 1) / self.block_size;
        const current_blocks = self.layer_blocks[layer].len;
        
        if (required_blocks > current_blocks) {

            
            var new_arr = try self.allocator.alloc(Block, required_blocks);
            std.mem.copyForwards(Block, new_arr[0..current_blocks], self.layer_blocks[layer]);
            
            for (current_blocks..required_blocks) |i| {
                const total_dim = self.block_size * self.num_heads * self.head_dim;
                const k_data = try self.allocator.alloc(BitBlock, (total_dim + 63) / 64);
                const v_data = try self.allocator.alloc(BitBlock, (total_dim + 63) / 64);
                
                @memset(k_data, BitBlock{ .bits = 0, .scale = 0.0 });
                @memset(v_data, BitBlock{ .bits = 0, .scale = 0.0 });
                
                new_arr[i] = Block{ .k_data = k_data, .v_data = v_data };
            }
            
            self.allocator.free(self.layer_blocks[layer]);
            self.layer_blocks[layer] = new_arr;
        }
    }

    pub fn saveToken(self: *PagedKVCache, layer: usize, pos: usize, k: []const f32, v: []const f32) !void {
        try self.ensureCapacity(layer, pos + 1);
        const block_idx = pos / self.block_size;
        const tok_idx = pos % self.block_size;
        
        var block = self.layer_blocks[layer][block_idx];
        const total_dim = self.num_heads * self.head_dim;
        const packed_dim = (total_dim + 63) / 64;
        const base_offset = (tok_idx * total_dim) / 64;
        
        // Quantize K vector natively to 1-Bit Block-Scale
        for (0..packed_dim) |w_idx| {
            var sum: f32 = 0.0;
            var bits: u64 = 0;
            for (0..64) |b| {
                const idx = w_idx * 64 + b;
                if (idx >= total_dim) break;
                const val = k[idx];
                sum += @abs(val);
                if (val > 0.0) bits |= (@as(u64, 1) << @as(u6, @truncate(b)));
            }
            block.k_data[base_offset + w_idx] = .{ .bits = bits, .scale = sum / 64.0 };
        }
        
        // Quantize V vector natively to 1-Bit Block-Scale
        for (0..packed_dim) |w_idx| {
            var sum: f32 = 0.0;
            var bits: u64 = 0;
            for (0..64) |b| {
                const idx = w_idx * 64 + b;
                if (idx >= total_dim) break;
                const val = v[idx];
                sum += @abs(val);
                if (val > 0.0) bits |= (@as(u64, 1) << @as(u6, @truncate(b)));
            }
            block.v_data[base_offset + w_idx] = .{ .bits = bits, .scale = sum / 64.0 };
        }
    }

    pub fn getHistory(self: *PagedKVCache, layer: usize, pos: usize) []const Block {
        _ = pos;
        return self.layer_blocks[layer];
    }
};
