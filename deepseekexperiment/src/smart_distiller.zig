const std = @import("std");
const posix = std.posix;

pub const BitBlock = extern struct {
    bits: u64,
    scale: f32,
};

pub fn processShard(allocator: std.mem.Allocator, in_path: []const u8, out_path: []const u8, index_path: []const u8) !void {
    const in_file = try std.fs.cwd().openFile(in_path, .{});
    defer in_file.close();
    
    const stat = try in_file.stat();
    if (stat.size < 8) return;
    
    const mmap_in = try posix.mmap(null, stat.size, posix.PROT.READ, .{ .TYPE = .SHARED }, in_file.handle, 0);
    defer posix.munmap(mmap_in);

    const header_len_bytes = mmap_in[0..8];
    const header_len = std.mem.readInt(u64, header_len_bytes, .little);
    const data_start = 8 + header_len;
    
    if (data_start >= stat.size) return;
    
    const header_str = mmap_in[8 .. 8 + header_len];
    
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, header_str, .{});
    defer parsed.deinit();
    
    const map = parsed.value.object;
    
    const out_file = try std.fs.cwd().createFile(out_path, .{});
    defer out_file.close();
    var bw = std.io.bufferedWriter(out_file.writer());
    const writer = bw.writer();

    const idx_file = try std.fs.cwd().createFile(index_path, .{});
    defer idx_file.close();
    var idx_bw = std.io.bufferedWriter(idx_file.writer());
    const idx_writer = idx_bw.writer();
    
    var current_out_offset: u64 = 0;

    var it = map.iterator();
    while (it.next()) |entry| {
        const tensor_name = entry.key_ptr.*;
        if (std.mem.eql(u8, tensor_name, "__metadata__")) continue;
        
        // We only care about weight matrices
        if (!std.mem.endsWith(u8, tensor_name, ".weight")) continue;
        
        const shape = entry.value_ptr.*.object.get("shape").?.array;
        const is_1d = shape.items.len < 2;
        
        const offsets = entry.value_ptr.*.object.get("data_offsets").?.array;
        const start = @as(usize, @intCast(offsets.items[0].integer));
        const end = @as(usize, @intCast(offsets.items[1].integer));
        
        const tensor_data = mmap_in[data_start + start .. data_start + end];
        
        const aligned_data: []align(2) const u8 = @alignCast(tensor_data);
        const bf16_data = std.mem.bytesAsSlice(u16, aligned_data);
        const float_data = try allocator.alloc(f32, bf16_data.len);
        defer allocator.free(float_data);
        for (bf16_data, 0..) |bf16_val, i| {
            float_data[i] = @bitCast(@as(u32, bf16_val) << 16);
        }
        
        const vector_size = 64;
        const num_vectors = float_data.len / vector_size;

        const is_gate = std.mem.indexOf(u8, tensor_name, ".ffn.gate.weight") != null and std.mem.indexOf(u8, tensor_name, ".experts") == null;
        const is_head = std.mem.indexOf(u8, tensor_name, "head.weight") != null;
        const is_embed = std.mem.indexOf(u8, tensor_name, "embed.weight") != null;
        
        // 1. Keep Router Gates, Embeddings, LM Head, and 1D Norms in FP32
        if (is_gate or is_head or is_embed or is_1d) {
            const bytes_len = float_data.len * 4;
            try idx_writer.print("{{\"name\": \"{s}\", \"offset\": {d}, \"length\": {d}, \"type\": \"fp32\"}}\n", .{
                tensor_name, current_out_offset, bytes_len
            });
            const bytes_to_write = std.mem.sliceAsBytes(float_data);
            try writer.writeAll(bytes_to_write);
            current_out_offset += bytes_to_write.len;
        } else {
            // 2. Binarize to 1-Bit Block Scale (12 bytes per 64 weights)
            const bytes_len = num_vectors * 12;
            try idx_writer.print("{{\"name\": \"{s}\", \"offset\": {d}, \"length\": {d}, \"type\": \"1bit\"}}\n", .{
                tensor_name, current_out_offset, bytes_len
            });
            
            const zero_vec: @Vector(vector_size, f32) = @splat(0.0);
            for (0..num_vectors) |v_idx| {
                const vec_offset = v_idx * vector_size;
                const float_vec: @Vector(vector_size, f32) = @as(*const [vector_size]f32, @ptrCast(@alignCast(float_data.ptr + vec_offset))).*;
                
                const abs_vec: @Vector(vector_size, f32) = @abs(float_vec);
                const sum = @reduce(.Add, abs_vec);
                const block_scale = sum / @as(f32, @floatFromInt(vector_size));
                
                const bool_vec: @Vector(vector_size, bool) = float_vec > zero_vec;
                const packed_bits: u64 = @bitCast(bool_vec);

                try writer.writeInt(u64, packed_bits, .little);
                try writer.writeInt(u32, @bitCast(block_scale), .little);
                current_out_offset += 12;
            }
        }
    }

    try bw.flush();
    try idx_bw.flush();
}

fn processShardSafe(allocator: std.mem.Allocator, in_path: []const u8, out_path: []const u8, idx_path: []const u8) void {
    processShard(allocator, in_path, out_path, idx_path) catch |err| {
        std.debug.print("Failed to process {s}: {}\n", .{in_path, err});
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== SMART DISTILLER (NATIVE ZIG) ===\n", .{});
    
    std.fs.cwd().makeDir("distilled_core") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    var timer = try std.time.Timer.start();
    var pool: std.Thread.Pool = undefined;
    try pool.init(std.Thread.Pool.Options{ .allocator = alloc });
    
    for (1..65) |i| {
        const in_path = try std.fmt.allocPrint(alloc, "/mnt/corpus/DeepSeek-V4-Pro/model-{d:0>5}-of-00064.safetensors", .{i});
        const out_path = try std.fmt.allocPrint(alloc, "distilled_core/shard-{d:0>5}.bin", .{i});
        const idx_path = try std.fmt.allocPrint(alloc, "distilled_core/shard-{d:0>5}.json", .{i});
        try pool.spawn(processShardSafe, .{ alloc, in_path, out_path, idx_path });
    }

    pool.deinit();

    const elapsed = @as(f64, @floatFromInt(timer.read())) / 1_000_000_000.0;
    try stdout.print("Operation Time: {d:.4}s\n", .{elapsed});
}
