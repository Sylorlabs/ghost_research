const std = @import("std");
const posix = std.posix;

pub const BitBlock = extern struct {
    bits: u64,
    scale: f32,
};

pub fn processShard(allocator: std.mem.Allocator, in_path: []const u8, out_path: []const u8) !void {
    _ = allocator;
    const in_file = try std.fs.cwd().openFile(in_path, .{});
    defer in_file.close();
    
    const stat = try in_file.stat();
    if (stat.size < 8) return;
    
    const mmap_in = try posix.mmap(
        null, 
        stat.size, 
        posix.PROT.READ, 
        .{ .TYPE = .SHARED }, 
        in_file.handle, 
        0
    );
    defer posix.munmap(mmap_in);

    const header_len_bytes = mmap_in[0..8];
    const header_len = std.mem.readInt(u64, header_len_bytes, .little);
    const data_start = 8 + header_len;
    
    if (data_start >= stat.size) return;
    
    const tensor_data = mmap_in[data_start..];
    const float_data = std.mem.bytesAsSlice(f32, tensor_data);

    const out_file = try std.fs.cwd().createFile(out_path, .{});
    defer out_file.close();
    var bw = std.io.bufferedWriter(out_file.writer());
    const writer = bw.writer();

    const vector_size = 64;
    const num_vectors = float_data.len / vector_size;
    const zero_vec: @Vector(vector_size, f32) = @splat(0.0);

    for (0..num_vectors) |v_idx| {
        const offset = v_idx * vector_size;
        
        const float_vec: @Vector(vector_size, f32) = @as(*const [vector_size]f32, @ptrCast(@alignCast(float_data.ptr + offset))).*;
        
        // Calculate the absolute mean scale for this specific block of 64
        const abs_vec: @Vector(vector_size, f32) = @abs(float_vec);
        const sum = @reduce(.Add, abs_vec);
        const block_scale = sum / @as(f32, @floatFromInt(vector_size));
        
        const bool_vec: @Vector(vector_size, bool) = float_vec > zero_vec;
        const packed_bits: u64 = @bitCast(bool_vec);

        // Save interleaved Bits + Scale
        try writer.writeInt(u64, packed_bits, .little);
        try writer.writeInt(u32, @bitCast(block_scale), .little);
    }

    try bw.flush();
}

fn processShardSafe(allocator: std.mem.Allocator, in_path: []const u8, out_path: []const u8) void {
    processShard(allocator, in_path, out_path) catch |err| {
        std.debug.print("Failed to process {s}: {}\n", .{in_path, err});
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== BITFORGE BLOCK-SCALED DISTILLER ===\n", .{});
    try stdout.print("[*] Architecture: 1-Bit XOR + FP32 Magnitude Restoration\n", .{});
    try stdout.print("[*] Spawning Thread Pool for all 64 Shards...\n\n", .{});

    std.fs.cwd().makeDir("distilled_core") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    var timer = try std.time.Timer.start();

    var pool: std.Thread.Pool = undefined;
    try pool.init(std.Thread.Pool.Options{ .allocator = alloc });
    
    for (1..65) |i| {
        const in_path = try std.fmt.allocPrint(alloc, "/mnt/corpus/DeepSeek-V4-Pro/model-{d:0>5}-of-00064.safetensors", .{i});
        const out_path = try std.fmt.allocPrint(alloc, "distilled_core/shard-{d:0>5}.bin", .{i});
        try pool.spawn(processShardSafe, .{ alloc, in_path, out_path });
    }

    pool.deinit();

    const elapsed = @as(f64, @floatFromInt(timer.read())) / 1_000_000_000.0;
    try stdout.print("\n=== SUCCESS ===\n", .{});
    try stdout.print("Total Operation Time: {d:.4} seconds.\n", .{elapsed});
}
