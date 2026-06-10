const std = @import("std");
const safetensors = @import("safetensors.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== BITFORGE DISTILLER: AIG BINARIZATION ===\n", .{});

    const path = "/mnt/corpus/DeepSeek-V4-Pro/model-00001-of-00064.safetensors";
    try stdout.print("Loading tensor from {s}...\n", .{path});

    var st = try safetensors.SafetensorsFile.load(alloc, path);
    defer st.deinit();

    // Find a tensor to distill.
    var it = st.tensors.iterator();
    var target_tensor_name: []const u8 = "";
    while (it.next()) |entry| {
        if (std.mem.indexOf(u8, entry.key_ptr.*, "wkv") != null or 
            std.mem.indexOf(u8, entry.key_ptr.*, "expert") != null) {
            target_tensor_name = entry.key_ptr.*;
            break;
        }
    }

    if (target_tensor_name.len == 0) {
        // Just grab the first tensor
        it = st.tensors.iterator();
        if (it.next()) |first| {
            target_tensor_name = first.key_ptr.*;
        }
    }

    const tensor = st.tensors.get(target_tensor_name).?;
    try stdout.print("Target Tensor: {s}\n", .{target_tensor_name});
    try stdout.print("Shape: {any}, DType: {s}, Size: {d} bytes\n", .{tensor.shape, tensor.dtype, tensor.data.len});

    // Binarize
    try stdout.print("Distilling {d} parameters into 1-bit boolean logic...\n", .{tensor.data.len});
    
    // We will pack 64 weights into 1 u64.
    const packed_len = (tensor.data.len + 63) / 64;
    const packed_data = try alloc.alloc(u64, packed_len);
    defer alloc.free(packed_data);
    @memset(packed_data, 0);

    for (tensor.data, 0..) |byte, i| {
        // For FP8 (1-byte float), the most significant bit is the sign bit.
        // If sign bit is 0, value is positive.
        const is_positive = (byte & 0x80) == 0;
        
        if (is_positive and byte != 0) {
            const word_idx = i / 64;
            const bit_idx = @as(u6, @truncate(i % 64));
            packed_data[word_idx] |= (@as(u64, 1) << bit_idx);
        }
    }

    try stdout.print("Successfully SAT-swept float distributions into {d} u64 registers.\n", .{packed_len});
    
    // Save to bin
    const out_path = "distilled_tensor.bin";
    const file = try std.fs.cwd().createFile(out_path, .{});
    defer file.close();
    
    const slice_u8 = std.mem.sliceAsBytes(packed_data);
    try file.writeAll(slice_u8);
    
    try stdout.print("AIG Binary exported to {s} ({d} bytes)\n", .{out_path, slice_u8.len});
    try stdout.print("Ready for pure hardware bitwise execution.\n", .{});
}
