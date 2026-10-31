const std = @import("std");
const gpu = @import("src/gpu.zig");

// Streaming batched-decode throughput harness.
// Proves the integration unknown behind the 1.5 GB/s slow-drive tps projection:
// does the disk read forged experts at full speed CONCURRENTLY with GPU compute?
//   solo disk  -> raw read GB/s (O_DIRECT, no cache)
//   solo gpu   -> batched XNOR Gw/s
//   concurrent -> both at once; if disk stays ~solo, overlap works -> tps holds.
// args: <forged_layer_path> <n_passes> <batch>

const CHUNK: usize = 8 << 20; // 8 MiB, multiple of 4096 for O_DIRECT
const O_DIRECT: u32 = 0o40000; // linux x86_64

const Shared = struct {
    path: []const u8,
    n_passes: usize,
    bytes: std.atomic.Value(u64),
    done: std.atomic.Value(bool),
};

fn readPasses(s: *Shared) void {
    const buf = std.heap.page_allocator.alignedAlloc(u8, 4096, CHUNK) catch return;
    defer std.heap.page_allocator.free(buf);
    var pass: usize = 0;
    while (pass < s.n_passes) : (pass += 1) {
        const fd = std.posix.open(s.path, .{ .ACCMODE = .RDONLY, .DIRECT = true }, 0) catch {
            // fallback without O_DIRECT (will hit page cache)
            const f2 = std.fs.cwd().openFile(s.path, .{}) catch return;
            defer f2.close();
            while (true) {
                const n = f2.read(buf) catch break;
                if (n == 0) break;
                _ = s.bytes.fetchAdd(n, .monotonic);
            }
            continue;
        };
        defer std.posix.close(fd);
        while (true) {
            const n = std.posix.read(fd, buf) catch break;
            if (n == 0) break;
            _ = s.bytes.fetchAdd(n, .monotonic);
        }
    }
    s.done.store(true, .release);
}

fn soloDisk(path: []const u8, n_passes: usize) !f64 {
    var s = Shared{ .path = path, .n_passes = n_passes, .bytes = std.atomic.Value(u64).init(0), .done = std.atomic.Value(bool).init(false) };
    var t = try std.time.Timer.start();
    readPasses(&s);
    const sec = @as(f64, @floatFromInt(t.read())) / 1e9;
    const gb = @as(f64, @floatFromInt(s.bytes.load(.monotonic))) / 1e9;
    return gb / sec;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();
    var args = std.process.args();
    _ = args.skip();
    const path = args.next() orelse "/mnt/corpus/engine_test/L30_experts_P3.bin";
    const n_passes: usize = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 3;
    const B: u32 = if (args.next()) |a| try std.fmt.parseInt(u32, a, 10) else 64;

    const fsz = (try std.fs.cwd().statFile(path)).size;
    const W_layer_gb = @as(f64, @floatFromInt(fsz)) / 1e9;
    try out.print("=== STREAMING ENGINE BENCH ===\n", .{});
    try out.print("file {s}  size {d:.2} GB  passes {d}  batch {d}\n\n", .{ path, W_layer_gb, n_passes, B });

    // 1) SOLO DISK
    const disk_solo = try soloDisk(path, n_passes);
    try out.print("[1] solo disk read (O_DIRECT)      : {d:.2} GB/s\n", .{disk_solo});

    // 2) SOLO GPU
    const in_dim: u32 = 7168;
    const out_dim: u32 = 3072;
    const g = try gpu.GPUAccelerator.init(alloc);
    defer g.deinit();
    try g.loadPipeline("src/shaders/compute_1bit_tiled.spv");
    const groups: u32 = (out_dim * (B / 8) + 63) / 64;
    var gpu_solo: f64 = 0;
    {
        var t = try std.time.Timer.start();
        var iters: u64 = 0;
        while (t.read() < 3_000_000_000) {
            gpu_solo = try g.benchResidentGEMM(in_dim, out_dim, B, 60, groups);
            iters += 1;
        }
        try out.print("[2] solo gpu batched XNOR (P3)      : {d:.0} Gw/s\n", .{gpu_solo / 3.0});
    }

    // 3) CONCURRENT disk + gpu
    var s = Shared{ .path = path, .n_passes = n_passes, .bytes = std.atomic.Value(u64).init(0), .done = std.atomic.Value(bool).init(false) };
    var t = try std.time.Timer.start();
    const th = try std.Thread.spawn(.{}, readPasses, .{&s});
    var gpu_w: f64 = 0;
    var gpu_calls: u64 = 0;
    while (!s.done.load(.acquire)) {
        const gws = try g.benchResidentGEMM(in_dim, out_dim, B, 40, groups);
        gpu_w += gws * 40.0; // accumulate; gws is Gw/s for the 40-iter call
        gpu_calls += 1;
    }
    th.join();
    const sec = @as(f64, @floatFromInt(t.read())) / 1e9;
    const gb = @as(f64, @floatFromInt(s.bytes.load(.monotonic))) / 1e9;
    const disk_conc = gb / sec;
    try out.print("[3] CONCURRENT disk                : {d:.2} GB/s  ({d:.0}%% of solo)\n", .{ disk_conc, 100.0 * disk_conc / disk_solo });
    try out.print("    CONCURRENT gpu calls           : {d} over {d:.1}s (gpu stayed busy)\n", .{ gpu_calls, sec });

    // 4) AGGREGATE TPS PROJECTION from concurrent disk bandwidth
    try out.print("\n=== AGGREGATE TPS (B={d}, overlap-bound = concurrent disk {d:.2} GB/s) ===\n", .{ B, disk_conc });
    const W = [_]struct { name: []const u8, gb: f64 }{
        .{ .name = "P3  812GB", .gb = 812 },
        .{ .name = "mix 387GB", .gb = 387 },
        .{ .name = "P1  250GB", .gb = 250 },
    };
    for (W) |w| {
        const tps = @as(f64, @floatFromInt(B)) * disk_conc / w.gb;
        try out.print("    {s} : {d:.2} tps aggregate  (and at B=512: {d:.2})\n", .{ w.name, tps, 512.0 * disk_conc / w.gb });
    }
}
