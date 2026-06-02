const std = @import("std");
const ghost_daemon = @import("ghost_daemon.zig");

// Live demo: runs the synchronous Agent (mb_safety controller) in real time and
// serves telemetry to dashboard.html over a websocket. The REPL used to reject
// every command ("Command not recognized in Active Inference Mode."); it now
// actually inspects the running agent. For the reproducible benchmark that
// answers "does it work?", use `zig build eval` instead.

fn printHelp() void {
    std.debug.print(
        \\Commands:
        \\  status   - current grid mass of the live battery cell
        \\  help     - this message
        \\  quit     - stop the daemon and exit
        \\
    , .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
    const rand = prng.random();

    std.debug.print("=========================================\n", .{});
    std.debug.print("  GHOST ACTIVE INFERENCE ENGINE - INITIALIZING \n", .{});
    std.debug.print("=========================================\n", .{});

    var daemon = try ghost_daemon.DaemonState.init(allocator, rand);
    defer daemon.deinit();

    std.debug.print("[INFO] Starting agent loop (mb_safety controller). Type 'help'.\n", .{});
    try daemon.start();

    const stdin = std.io.getStdIn().reader();
    var buffer: [1024]u8 = undefined;

    while (true) {
        std.debug.print("\nGHOST> ", .{});
        const line = stdin.readUntilDelimiterOrEof(&buffer, '\n') catch |err| {
            std.debug.print("Error reading input: {}\n", .{err});
            continue;
        } orelse break;

        const input = std.mem.trim(u8, line, " \r\t");
        if (input.len == 0) continue;
        if (std.mem.eql(u8, input, "exit") or std.mem.eql(u8, input, "quit")) break;
        if (std.mem.eql(u8, input, "help")) {
            printHelp();
        } else if (std.mem.eql(u8, input, "status")) {
            std.debug.print("live grid mass = {d}\n", .{daemon.snapshotMass()});
        } else {
            std.debug.print("Unknown command '{s}'. Type 'help'.\n", .{input});
        }
    }
}
