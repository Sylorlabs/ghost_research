//! T8-AG-21f — Remix alert on proposer paths (E11 + RQ7 tax runs).
//! Run: zig build tier8-remix-monitor-f --release=fast

const std = @import("std");
const mon = @import("remix_rate_monitor.zig");

pub fn main() !void {
    const out = std.io.getStdOut().writer();
    const logs = [_][]const u8{
        "/tmp/tier8-swarm/T8-AG-07.log",
        "/tmp/tier8-swarm/T8-AG-08.log",
    };

    try out.print("=== T8-AG-21f: Proposer-path remix monitor ===\n\n", .{});

    var rolling: mon.RollingMonitor = .{};
    var parsed_any = false;

    for (logs) |path| {
        const file = std.fs.cwd().openFile(path, .{}) catch continue;
        defer file.close();
        const raw = file.readToEndAlloc(std.heap.page_allocator, 64 * 1024) catch continue;
        defer std.heap.page_allocator.free(raw);

        var novel: usize = 0;
        var checked: usize = 0;
        var lines = std.mem.splitScalar(u8, raw, '\n');
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "tax checked=")) |pos| {
                const tail = line[pos + 12 ..];
                var it = std.mem.splitScalar(u8, tail, ' ');
                if (it.next()) |c| checked = std.fmt.parseInt(usize, c, 10) catch 0;
                if (it.next()) |nv| {
                    const eq = std.mem.indexOf(u8, nv, "novel=") orelse continue;
                    novel = std.fmt.parseInt(usize, nv[eq + 6 ..], 10) catch 0;
                }
            }
        }
        if (checked == 0) continue;
        parsed_any = true;
        const sample: mon.RunSample = .{ .novel = novel, .checked = checked };
        rolling.push(sample);
        try out.print("  {s}: checked={d} novel={d} rate={d:.1}%\n", .{ path, checked, novel, sample.rate() * 100.0 });
    }

    // Pad with battery B reference if fewer than 5 samples
    if (rolling.n < mon.WINDOW) {
        const sample: mon.RunSample = .{ .novel = 1, .checked = 18 };
        while (rolling.n < mon.WINDOW) rolling.push(sample);
        try out.print("  (padded with battery B reference 1/18)\n", .{});
    }

    const alert = rolling.alertFired();
    try out.print("\n  mean rate: {d:.1}%\n", .{rolling.meanRate() * 100.0});
    try out.print("  REMIX ALERT: {s}\n", .{if (alert) "FIRED" else "not fired"});
    const pass = parsed_any and alert;
    try out.print("  VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
}