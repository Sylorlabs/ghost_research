//! Prospective held-out target generator.
//!
//! This source is frozen before execution.  It reads each exponent and policy
//! seed directly from /dev/urandom, rejects duplicates, and writes no expected
//! score or answer.  The generated exponent n is the visible mathematical input;
//! all baseline outcomes remain evaluator-owned until the trial runs.
const std = @import("std");

const TARGET_COUNT: usize = 60;
const MIN_BITS: u6 = 24;
const MAX_BITS: u6 = 40;

fn readU64(random: *std.fs.File) !u64 {
    var bytes: [8]u8 = undefined;
    const count = try random.readAll(&bytes);
    if (count != bytes.len) return error.ShortRandomRead;
    return std.mem.readInt(u64, &bytes, .little);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 2) {
        std.debug.print("usage: ghost_math_generate_targets_v1 <output.csv>\n", .{});
        std.process.exit(2);
    }
    var random = try std.fs.openFileAbsolute("/dev/urandom", .{});
    defer random.close();
    var seen = std.AutoHashMap(u64, void).init(allocator);
    defer seen.deinit();
    var output = if (std.fs.path.isAbsolute(args[1]))
        try std.fs.createFileAbsolute(args[1], .{ .truncate = true })
    else
        try std.fs.cwd().createFile(args[1], .{ .truncate = true });
    defer output.close();
    const writer = output.writer();
    try writer.writeAll("n,label,bits,seed_hex\n");

    var count: usize = 0;
    while (count < TARGET_COUNT) {
        const raw = try readU64(&random);
        const bit_span = MAX_BITS - MIN_BITS + 1;
        const bits: u6 = MIN_BITS + @as(u6, @intCast(raw % bit_span));
        const high = @as(u64, 1) << (bits - 1);
        const mask = (@as(u64, 1) << bits) - 1;
        const target = high | (raw & mask);
        if (seen.contains(target)) continue;
        try seen.put(target, {});
        const seed = try readU64(&random);
        try writer.print("{d},HELDOUT,{d},0x{X:0>16}\n", .{ target, bits, seed });
        count += 1;
    }
    std.debug.print(
        "GHOST_MATH_TARGETS_V1 generated={d} source=/dev/urandom unique=true bits={d}..{d} answers_written=false\n",
        .{ count, MIN_BITS, MAX_BITS },
    );
}
