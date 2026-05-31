const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const out = std.io.getStdOut().writer();
    try out.print("=== Tier 4 Dynamic Compilation Benchmark ===\n", .{});

    const code =
        \\export fn evaluate(x: u64) u64 {
        \\    return x ^ (x >> 3);
        \\}
    ;

    var timer = try std.time.Timer.start();

    // 1. Write file
    try std.fs.cwd().writeFile(.{ .sub_path = "tmp_eval.zig", .data = code });

    // 2. Compile
    const compile_start = timer.read();
    const argv = &[_][]const u8{ "zig", "build-lib", "tmp_eval.zig", "-dynamic", "-O", "ReleaseFast" };
    const run_res = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
    allocator.free(run_res.stdout);
    allocator.free(run_res.stderr);
    const compile_end = timer.read();

    // 3. Load DynLib
    const load_start = timer.read();
    var lib = try std.DynLib.open("./libtmp_eval.so");
    defer lib.close();

    const evaluate_fn = lib.lookup(*const fn(u64) callconv(.C) u64, "evaluate") orelse return error.SymbolNotFound;
    const load_end = timer.read();

    // 4. Execute
    const exec_start = timer.read();
    const res = evaluate_fn(0x12345678);
    const exec_end = timer.read();

    try out.print("Result: 0x{X}\n", .{res});
    try out.print("Compile time: {d} ms\n", .{(compile_end - compile_start) / 1_000_000});
    try out.print("Load time:    {d} us\n", .{(load_end - load_start) / 1000});
    try out.print("Execute time: {d} ns\n", .{exec_end - exec_start});

    // Projections
    const total_time_ms = (compile_end - compile_start) / 1_000_000;
    try out.print("\n=== The Buzzkill Math ===\n", .{});
    try out.print("To run a tiny 20,000 iteration hill-climb search...\n", .{});
    try out.print("Time required: {d} SECONDS ({d} MINUTES)\n", .{ (total_time_ms * 20000) / 1000, (total_time_ms * 20000) / 60000 });
    try out.print("\nA normal BitForge search does 20,000 iterations in < 0.1 seconds.\n", .{});
}