const std = @import("std");
const mixer = @import("domain_u64_mixer_mulfree.zig");

const Args = struct {
    program: ?[]const u8 = null,
    samples: u32 = 10_000,
    min_threshold: f64 = 0.45,
};

fn printUsage(w: anytype) !void {
    try w.writeAll(
        \\usage: mulfree_per_bit_avalanche --program=PATH [--samples=N] [--min=FLOAT]
        \\
        \\Computes the full 64x64 Strict Avalanche Criterion matrix:
        \\for each (input_bit i, output_bit j) pair, the fraction of samples
        \\where flipping input bit i changed output bit j. SAC ideal = 0.5.
        \\
        \\Prints sac_min, sac_max, sac_mean to stdout.
        \\Exits 0 if sac_min >= --min (default 0.45); exits 2 otherwise.
        \\
    );
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();

    var cfg = Args{};
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printUsage(std.io.getStdOut().writer());
            return;
        } else if (std.mem.startsWith(u8, arg, "--program=")) {
            cfg.program = arg["--program=".len..];
        } else if (std.mem.startsWith(u8, arg, "--samples=")) {
            cfg.samples = try std.fmt.parseInt(u32, arg["--samples=".len..], 10);
        } else if (std.mem.startsWith(u8, arg, "--min=")) {
            cfg.min_threshold = try std.fmt.parseFloat(f64, arg["--min=".len..]);
        } else {
            try std.io.getStdErr().writer().print("unknown arg: {s}\n", .{arg});
            try printUsage(std.io.getStdErr().writer());
            return error.InvalidArgument;
        }
    }

    const path = cfg.program orelse {
        try printUsage(std.io.getStdErr().writer());
        return error.MissingProgram;
    };

    const program = try mixer.programFromCsv(allocator, path);

    var counts: [64][64]u64 = [_][64]u64{[_]u64{0} ** 64} ** 64;

    var rng: u64 = 0xACE_F00D_BEEF_CAFE;
    var s: u32 = 0;
    while (s < cfg.samples) : (s += 1) {
        rng = rng *% 0x9E37_79B9_7F4A_7C15 +% 0xBF58_476D_1CE4_E5B9;
        const x = rng;
        const y = program.execute(x);

        var i: u6 = 0;
        while (true) {
            const y_flip = program.execute(x ^ (@as(u64, 1) << i));
            const diff = y ^ y_flip;

            var j: u6 = 0;
            while (true) {
                if (((diff >> j) & 1) == 1) counts[i][j] += 1;
                if (j == 63) break;
                j += 1;
            }

            if (i == 63) break;
            i += 1;
        }
    }

    const denom = @as(f64, @floatFromInt(cfg.samples));
    var min_v: f64 = 1.0;
    var max_v: f64 = 0.0;
    var sum_v: f64 = 0.0;
    var min_i: usize = 0;
    var min_j: usize = 0;
    for (counts, 0..) |row, ii| {
        for (row, 0..) |c, jj| {
            const v = @as(f64, @floatFromInt(c)) / denom;
            if (v < min_v) {
                min_v = v;
                min_i = ii;
                min_j = jj;
            }
            if (v > max_v) max_v = v;
            sum_v += v;
        }
    }
    const mean_v = sum_v / 4096.0;

    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        "sac_min={d:.6} sac_max={d:.6} sac_mean={d:.6} min_pair=(i={d},j={d}) samples={d} threshold={d:.6} program={s}\n",
        .{ min_v, max_v, mean_v, min_i, min_j, cfg.samples, cfg.min_threshold, path },
    );

    if (min_v < cfg.min_threshold) {
        std.process.exit(2);
    }
}
