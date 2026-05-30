//! Logger — mirrors all telemetry to stdout AND a persistent per-run log file.
//!
//! Every line the simulation emits is captured in `logs/wcore_<seed>.log`, so a
//! run is fully reconstructable after the fact: world seed, every agent action
//! and sensor reading, the wake-phase search trace, the sleep-phase candidate
//! evaluations, the invention, and the behavioural verification.
//!
//! It exposes `print`/`writeAll` so it can be passed wherever a writer is
//! expected (telemetry, wpropose, etc.).

const std = @import("std");
const builtin = @import("builtin");

// Under `zig build test`, stdout is the test runner's IPC channel — writing
// telemetry to it deadlocks the run. So mirror to stdout only outside tests;
// the file log is always written.
const mirror_stdout = !builtin.is_test;

pub const Logger = struct {
    file: std.fs.File,
    path: []const u8,

    pub fn init(a: std.mem.Allocator, seed: u64) !Logger {
        const path = try std.fmt.allocPrint(a, "logs/wcore_{x}.log", .{seed});
        return initPath(path);
    }

    /// Open a log at an explicit `logs/`-relative path (used by the pure engine).
    pub fn initPath(path: []const u8) !Logger {
        std.fs.cwd().makePath("logs") catch {};
        const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
        return Logger{ .file = file, .path = path };
    }

    pub fn deinit(self: *Logger) void {
        self.file.close();
    }

    pub fn print(self: *Logger, comptime fmt: []const u8, args: anytype) !void {
        if (mirror_stdout) try std.io.getStdOut().writer().print(fmt, args);
        try self.file.writer().print(fmt, args);
    }

    pub fn writeAll(self: *Logger, bytes: []const u8) !void {
        if (mirror_stdout) try std.io.getStdOut().writer().writeAll(bytes);
        try self.file.writer().writeAll(bytes);
    }
};
