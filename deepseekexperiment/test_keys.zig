const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    
    const norm_file = std.fs.cwd().openFile("distilled_core/norm_weights.bin", .{}) catch return;
    defer norm_file.close();
    const stat = try norm_file.stat();
    const norm_mem = try std.posix.mmap(null, stat.size, std.posix.PROT.READ, .{ .TYPE = .SHARED }, norm_file.handle, 0);
    
    var offset: usize = 0;
    while (offset < stat.size) {
        const name_len = std.mem.readInt(u32, norm_mem[offset..offset+4][0..4], .little);
        offset += 4;
        const name = norm_mem[offset..offset+name_len];
        offset += name_len;
        const data_len = std.mem.readInt(u32, norm_mem[offset..offset+4][0..4], .little);
        offset += 4;
        
        std.debug.print("Key: {s}\n", .{name});
        offset += data_len;
        if (offset > 1000) break; // print first few
    }
}
