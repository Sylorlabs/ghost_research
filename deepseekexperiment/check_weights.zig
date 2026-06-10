const std = @import("std");
const mmap_mgr = @import("src/mmap_manager.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    var mgr = try mmap_mgr.PagedManager.init(alloc, "distilled_core", 64, 256, 7168);
    defer mgr.deinit();

    const head = mgr.getSliceFp32("head.weight");
    std.debug.print("head.weight len: {d}\n", .{head.len});
    
    const embed = mgr.getSliceFp32("embed.weight");
    std.debug.print("embed.weight len: {d}\n", .{embed.len});
}
