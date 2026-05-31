const std = @import("std");
const domain = @import("domain_u64_bijective");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: {s} <csv_path> <bytes>\n", .{args[0]});
        return;
    }

    const csv_path = args[1];
    const bytes_str = args[2];
    const bytes: u64 = try std.fmt.parseInt(u64, bytes_str, 10);

    const file = try std.fs.cwd().openFile(csv_path, .{});
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(contents);

    var prog = domain.Program{
        .instructions = undefined,
        .used = 0,
    };

    var lines = std.mem.tokenizeAny(u8, contents, "\n\r");
    _ = lines.next(); // Skip header
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, ",");
        _ = fields.next() orelse continue; // idx
        const op_name = fields.next() orelse continue;
        const imm_hex = fields.next() orelse continue;
        
        const imm = try std.fmt.parseInt(u64, imm_hex, 16);
        const op = std.meta.stringToEnum(domain.Op, op_name) orelse return error.UnknownOp;
        
        prog.instructions[prog.used] = .{ .op = op, .imm = imm };
        prog.used += 1;
    }

    const out = std.io.getStdOut().writer();
    
    // Generate sequence starting from an arbitrary seed
    var state: u64 = 0xCAFEBABE12345678;
    var written: u64 = 0;
    const buf_len = 8192;
    var buf: [buf_len]u64 = undefined;

    while (written < bytes) {
        var i: usize = 0;
        while (i < buf_len) : (i += 1) {
            state +%= 1; // Counter to avoid getting stuck if period is low, though bijective from state means we just use counter as input!
            // Wait, standard practice for testing a bijection is to feed it a counter.
            buf[i] = prog.execute(state);
        }
        const to_write = @min(bytes - written, buf_len * 8);
        const slice = std.mem.sliceAsBytes(buf[0..]);
        try out.writeAll(slice[0..to_write]);
        written += to_write;
    }
}