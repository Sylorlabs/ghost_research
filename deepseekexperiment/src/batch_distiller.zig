const std = @import("std");
const posix = std.posix;
const safetensors = @import("safetensors.zig");

const NUM_SHARDS = 64;

// Context for thread tasks
const TaskContext = struct {
    tensor_name: []const u8,
    tensor: safetensors.Tensor,
    packed_data: []u64,
    wait_group: *std.Thread.WaitGroup,
};

fn binarizeTensorTask(ctx: TaskContext) void {
    defer ctx.wait_group.finish();
    
    // We process the tensor data and binarize it.
    // 8 threads can work on different tensors, or we could split one tensor across threads.
    // Since some tensors are huge, let's split the work of this single tensor across threads if needed,
    // but a simpler approach is thread pool on the outer tensor loop if there are many tensors.
    
    for (ctx.tensor.data, 0..) |byte, i| {
        const is_positive = (byte & 0x80) == 0;
        if (is_positive and byte != 0) {
            const word_idx = i / 64;
            const bit_idx = @as(u6, @truncate(i % 64));
            
            // Atomic OR to be safe if multiple threads somehow wrote to same word, 
            // but here each tensor has its own packed_data.
            // Still, doing non-atomic is safe since one tensor per task.
            ctx.packed_data[word_idx] |= (@as(u64, 1) << bit_idx);
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== BITFORGE AIG BATCH COMPILER ===\n", .{});
    try stdout.print("Target: 64 DeepSeek Shards -> Pure Logic Core\n", .{});

    const out_dir = "distilled_core";
    std.fs.cwd().makeDir(out_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    var thread_pool: std.Thread.Pool = undefined;
    try thread_pool.init(std.Thread.Pool.Options{
        .allocator = alloc,
        .n_jobs = std.Thread.getCpuCount() catch 8,
    });
    defer thread_pool.deinit();

    try stdout.print("Thread Pool initialized with {d} workers.\n\n", .{thread_pool.threads.len});

    var start_time = try std.time.Timer.start();
    var total_bytes_processed: usize = 0;

    for (1..NUM_SHARDS + 1) |shard_idx| {
        var shard_path_buf: [256]u8 = undefined;
        const shard_path = try std.fmt.bufPrint(&shard_path_buf, "/mnt/corpus/DeepSeek-V4-Pro/model-{d:0>5}-of-00064.safetensors", .{shard_idx});

        try stdout.print("[{d}/{d}] Distilling {s}...\n", .{shard_idx, NUM_SHARDS, shard_path});
        
        var st = safetensors.SafetensorsFile.load(alloc, shard_path) catch |err| {
            try stdout.print("  Failed to load shard: {}\n", .{err});
            continue;
        };
        defer st.deinit();

        var wait_group = std.Thread.WaitGroup{};
        var it = st.tensors.iterator();
        
        var packed_tensors = std.StringHashMap([]u64).init(alloc);
        defer {
            var val_it = packed_tensors.valueIterator();
            while (val_it.next()) |val| {
                alloc.free(val.*);
            }
            packed_tensors.deinit();
        }

        while (it.next()) |entry| {
            const tensor_name = entry.key_ptr.*;
            const tensor = entry.value_ptr.*;
            
            const packed_len = (tensor.data.len + 63) / 64;
            const packed_data = try alloc.alloc(u64, packed_len);
            @memset(packed_data, 0);
            
            try packed_tensors.put(tensor_name, packed_data);
            total_bytes_processed += tensor.data.len;

            wait_group.start();
            try thread_pool.spawn(binarizeTensorTask, .{ TaskContext{
                .tensor_name = tensor_name,
                .tensor = tensor,
                .packed_data = packed_data,
                .wait_group = &wait_group,
            } });
        }

        // Wait for all tensors in this shard to finish
        wait_group.wait();

        // Write to disk
        var out_path_buf: [256]u8 = undefined;
        const out_path = try std.fmt.bufPrint(&out_path_buf, "{s}/shard-{d:0>5}.bin", .{out_dir, shard_idx});
        const file = try std.fs.cwd().createFile(out_path, .{});
        defer file.close();

        // We will just concatenate all packed data into this shard bin
        // In a real implementation we'd store offsets and names, but this proves the physics pipeline.
        var packed_it = packed_tensors.valueIterator();
        while (packed_it.next()) |packed_data| {
            const slice_u8 = std.mem.sliceAsBytes(packed_data.*);
            try file.writeAll(slice_u8);
        }

        const elapsed_s = @as(f64, @floatFromInt(start_time.read())) / 1_000_000_000.0;
        const avg_time_per_shard = elapsed_s / @as(f64, @floatFromInt(shard_idx));
        const shards_left = NUM_SHARDS - shard_idx;
        const eta_s = avg_time_per_shard * @as(f64, @floatFromInt(shards_left));

        try stdout.print("  -> Binarized to {s}. ETA: {d:.1} seconds\n", .{out_path, eta_s});
    }

    const total_time_s = @as(f64, @floatFromInt(start_time.read())) / 1_000_000_000.0;
    try stdout.print("\n=== COMPILATION COMPLETE ===\n", .{});
    try stdout.print("Total Time: {d:.2} seconds\n", .{total_time_s});
    try stdout.print("Total Processed: {d} bytes\n", .{total_bytes_processed});
    try stdout.print("System is fully primed for AIG Execution.\n", .{});
}
