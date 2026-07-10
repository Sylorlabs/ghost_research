//! addchain_gen_v2.zig — target generator for addition-chain campaign v2 (2026-07-10).
//!
//! Generates targets from /dev/urandom so they postdate the build and cannot be
//! hardcoded in any engine source. Two modes:
//!
//!   bits  <count> <lo_bits> <hi_bits> <label> <out.csv>
//!       count values with bit-length uniform in [lo_bits, hi_bits]
//!       (top bit forced set, so the bit-length is exact).
//!   range <count> <lo> <hi> <label> <out.csv>
//!       count values uniform in [lo, hi].
//!
//! Output CSV: one "n,label" per line (same format addchain_gen v1 emits and
//! dial_three/addchain_v2 consume).
//!
//! Build: zig build-exe addchain_gen_v2.zig -O ReleaseFast

const std = @import("std");

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len < 7) {
        std.debug.print(
            \\usage: addchain_gen_v2 bits  <count> <lo_bits> <hi_bits> <label> <out.csv>
            \\       addchain_gen_v2 range <count> <lo>      <hi>      <label> <out.csv>
            \\
        , .{});
        std.process.exit(2);
    }
    const mode = args[1];
    const count = try std.fmt.parseUnsigned(usize, args[2], 10);
    const lo = try std.fmt.parseUnsigned(u64, args[3], 10);
    const hi = try std.fmt.parseUnsigned(u64, args[4], 10);
    const label = args[5];
    const out_path = args[6];
    if (hi < lo) {
        std.debug.print("ERR: hi < lo\n", .{});
        std.process.exit(2);
    }

    var rand = try std.fs.cwd().openFile("/dev/urandom", .{});
    defer rand.close();
    const out = try std.fs.cwd().createFile(out_path, .{});
    defer out.close();
    const w = out.writer();

    var i: usize = 0;
    while (i < count) : (i += 1) {
        var buf: [16]u8 = undefined;
        _ = try rand.readAll(&buf);
        var v: u64 = 0;
        for (buf[0..8]) |b| v = (v << 8) | b;
        var extra: u64 = 0;
        for (buf[8..16]) |b| extra = (extra << 8) | b;

        var n: u64 = 0;
        if (std.mem.eql(u8, mode, "bits")) {
            if (lo < 2 or hi > 63) {
                std.debug.print("ERR: bits mode needs 2 <= lo <= hi <= 63\n", .{});
                std.process.exit(2);
            }
            const bits: u6 = @intCast(lo + (extra % (hi - lo + 1)));
            const mask = (@as(u64, 1) << bits) - 1;
            n = (v & mask) | (@as(u64, 1) << (bits - 1));
        } else if (std.mem.eql(u8, mode, "range")) {
            n = lo + (v % (hi - lo + 1));
        } else {
            std.debug.print("ERR: unknown mode '{s}'\n", .{mode});
            std.process.exit(2);
        }
        if (n < 2) n = 2;
        try w.print("{d},{s}\n", .{ n, label });
    }
    std.debug.print("wrote {d} {s} targets to {s}\n", .{ count, label, out_path });
}
