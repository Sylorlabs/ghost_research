const std = @import("std");
const posix = std.posix;

pub const PagedManager = struct {
    pub const BitBlock = extern struct {
        bits: u64,
        scale: f32,
    };

    pub const TensorLocation = struct {
        shard_idx: usize,
        offset: usize,
        length: usize,
        is_fp32: bool,
    };

    allocator: std.mem.Allocator,
    num_shards: usize,
    mapped_files: [][]align(4096) const u8,
    file_handles: []std.fs.File,
    tensor_registry: std.StringHashMap(TensorLocation),

    pub fn init(allocator: std.mem.Allocator, shard_dir: []const u8, num_shards: usize, experts_per_shard: usize, hidden_dim: usize) !*PagedManager {
        _ = experts_per_shard;
        _ = hidden_dim;
        const self = try allocator.create(PagedManager);
        
        const mapped_files = try allocator.alloc([]align(4096) const u8, num_shards);
        const file_handles = try allocator.alloc(std.fs.File, num_shards);
        var tensor_registry = std.StringHashMap(TensorLocation).init(allocator);

        for (0..num_shards) |i| {
            var bin_path_buf: [256]u8 = undefined;
            const bin_path = try std.fmt.bufPrint(&bin_path_buf, "{s}/shard-{d:0>5}.bin", .{shard_dir, i + 1});
            
            const file = std.fs.cwd().openFile(bin_path, .{}) catch |err| {
                if (err == error.FileNotFound) {
                    mapped_files[i] = &[_]u8{};
                    continue;
                }
                return err;
            };
            file_handles[i] = file;
            
            const stat = try file.stat();
            const mmap_data = try posix.mmap(null, stat.size, posix.PROT.READ, .{ .TYPE = .SHARED }, file.handle, 0);
            mapped_files[i] = mmap_data;

            // Read the JSON index corresponding to this shard
            var json_path_buf: [256]u8 = undefined;
            const json_path = try std.fmt.bufPrint(&json_path_buf, "{s}/shard-{d:0>5}.json", .{shard_dir, i + 1});
            
            const json_file = std.fs.cwd().openFile(json_path, .{}) catch continue;
            defer json_file.close();
            
            const json_data = try json_file.readToEndAlloc(allocator, 1024 * 1024 * 100);
            defer allocator.free(json_data);
            
            var line_it = std.mem.splitScalar(u8, json_data, '\n');
            while (line_it.next()) |line| {
                if (line.len < 2) continue;
                
                var parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
                defer parsed.deinit();
                
                const obj = parsed.value.object;
                const name = obj.get("name").?.string;
                const offset = @as(usize, @intCast(obj.get("offset").?.integer));
                const length = @as(usize, @intCast(obj.get("length").?.integer));
                const t_type = obj.get("type").?.string;
                
                try tensor_registry.put(try allocator.dupe(u8, name), .{
                    .shard_idx = i,
                    .offset = offset,
                    .length = length,
                    .is_fp32 = std.mem.eql(u8, t_type, "fp32"),
                });
            }
        }

        self.* = .{
            .allocator = allocator,
            .num_shards = num_shards,
            .mapped_files = mapped_files,
            .file_handles = file_handles,
            .tensor_registry = tensor_registry,
        };
        return self;
    }

    pub fn deinit(self: *PagedManager) void {
        for (0..self.num_shards) |i| {
            if (self.mapped_files[i].len > 0) {
                posix.munmap(self.mapped_files[i]);
                self.file_handles[i].close();
            }
        }
        self.allocator.free(self.mapped_files);
        self.allocator.free(self.file_handles);
        
        var it = self.tensor_registry.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.tensor_registry.deinit();
        self.allocator.destroy(self);
    }

    pub fn getSlice1Bit(self: *PagedManager, name: []const u8) []const BitBlock {
        if (self.tensor_registry.get(name)) |loc| {
            if (loc.is_fp32) return &[_]BitBlock{};
            const shard = self.mapped_files[loc.shard_idx];
            if (loc.offset + loc.length > shard.len) return &[_]BitBlock{};
            const byte_slice = shard[loc.offset .. loc.offset + loc.length];
            const aligned_data: []align(8) const u8 = @alignCast(byte_slice);
            return std.mem.bytesAsSlice(BitBlock, aligned_data);
        }
        return &[_]BitBlock{};
    }

    pub fn getSliceFp32(self: *PagedManager, name: []const u8) []const f32 {
        if (self.tensor_registry.get(name)) |loc| {
            if (!loc.is_fp32) return &[_]f32{};
            const shard = self.mapped_files[loc.shard_idx];
            if (loc.offset + loc.length > shard.len) return &[_]f32{};
            const byte_slice = shard[loc.offset .. loc.offset + loc.length];
            const aligned_data: []align(4) const u8 = @alignCast(byte_slice);
            return std.mem.bytesAsSlice(f32, aligned_data);
        }
        return &[_]f32{};
    }

    pub fn getExpertSlice(self: *PagedManager, layer_id: usize, expert_id: usize, proj_type: enum { gate, up, down }) []const BitBlock {
        var name_buf: [128]u8 = undefined;
        const name = switch (proj_type) {
            .gate => std.fmt.bufPrint(&name_buf, "layers.{d}.ffn.experts.{d}.w1.weight", .{layer_id, expert_id}) catch return &[_]BitBlock{},
            .down => std.fmt.bufPrint(&name_buf, "layers.{d}.ffn.experts.{d}.w2.weight", .{layer_id, expert_id}) catch return &[_]BitBlock{},
            .up => std.fmt.bufPrint(&name_buf, "layers.{d}.ffn.experts.{d}.w3.weight", .{layer_id, expert_id}) catch return &[_]BitBlock{},
        };
        return self.getSlice1Bit(name);
    }
    
    pub fn getLayerSlice(self: *PagedManager, layer_id: usize, proj_type: enum { q, k, v, o, lm_head }) []const BitBlock {
        var name_buf: [128]u8 = undefined;
        const name = switch (proj_type) {
            .q => std.fmt.bufPrint(&name_buf, "layers.{d}.attn.wq_b.weight", .{layer_id}) catch return &[_]BitBlock{},
            .k => std.fmt.bufPrint(&name_buf, "layers.{d}.attn.wkv.weight", .{layer_id}) catch return &[_]BitBlock{},
            .v => std.fmt.bufPrint(&name_buf, "layers.{d}.attn.wo_a.weight", .{layer_id}) catch return &[_]BitBlock{},
            .o => std.fmt.bufPrint(&name_buf, "layers.{d}.attn.wo_b.weight", .{layer_id}) catch return &[_]BitBlock{},
            .lm_head => "head.weight",
        };
        return self.getSlice1Bit(name);
    }

    pub fn getRouterSlice(self: *PagedManager, layer_id: usize) []const f32 {
        var name_buf: [128]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "layers.{d}.ffn.gate.weight", .{layer_id}) catch return &[_]f32{};
        return self.getSliceFp32(name);
    }
};
