const std = @import("std");
const Tokenizer = @import("src/tokenizer.zig").Tokenizer;
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    const stdout = std.io.getStdOut().writer();
    var tok = try Tokenizer.init(alloc, "tokenizer.json");
    defer tok.deinit();
    var ids = std.ArrayList(u32).init(alloc);
    defer ids.deinit();
    try tok.encode("The capital of France is", &ids);
    try stdout.print("encoded {d} tokens: ", .{ids.items.len});
    for (ids.items) |id| try stdout.print("{d} ", .{id});
    try stdout.print("\ndecoded: ", .{});
    for (ids.items) |id| try stdout.print("{s}", .{tok.decode(id)});
    try stdout.print("\n", .{});
}
