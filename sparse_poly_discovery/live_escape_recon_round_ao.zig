//! Round AO / AO2: bounded reconnaissance of the AN1 same-user child boundary.
const std = @import("std");

const Probe = struct { route: []const u8, verdict: []const u8, detail: []const u8 };

fn canReadAbsolute(path: []const u8) bool {
    var file = std.fs.openFileAbsolute(path, .{}) catch return false;
    defer file.close();
    var bytes: [64]u8 = undefined;
    _ = file.read(&bytes) catch return false;
    return true;
}
fn canRead(path: []const u8) bool {
    var file = std.fs.cwd().openFile(path, .{}) catch return false;
    defer file.close();
    var bytes: [64]u8 = undefined;
    _ = file.read(&bytes) catch return false;
    return true;
}
fn parentPid() ?u32 {
    var file = std.fs.openFileAbsolute("/proc/self/stat", .{}) catch return null;
    defer file.close();
    var bytes: [512]u8 = undefined;
    const n = file.read(&bytes) catch return null;
    const close = std.mem.lastIndexOfScalar(u8, bytes[0..n], ')') orelse return null;
    // Remaining fields begin: state ppid ... .
    var fields = std.mem.tokenizeScalar(u8, bytes[close + 1 .. n], ' ');
    _ = fields.next();
    return std.fmt.parseInt(u32, fields.next() orelse return null, 10) catch null;
}
fn child() !void {
    const out = std.io.getStdOut().writer();
    const env = std.process.getEnvVarOwned(std.heap.page_allocator, "PATH") catch null;
    if (env) |value| std.heap.page_allocator.free(value);
    try out.print("env_inherited:{s}\n", .{if (env != null) "EXPOSED" else "DENIED"});
    const cwd = std.fs.cwd().realpathAlloc(std.heap.page_allocator, ".") catch null;
    if (cwd) |value| std.heap.page_allocator.free(value);
    try out.print("cwd_visible:{s}\n", .{if (cwd != null) "EXPOSED" else "DENIED"});
    try out.print("proc_self:{s}\n", .{if (canReadAbsolute("/proc/self/status")) "EXPOSED" else "DENIED"});
    var parent_path: [64]u8 = undefined;
    const parent_status = if (parentPid()) |ppid| try std.fmt.bufPrint(&parent_path, "/proc/{d}/status", .{ppid}) else "";
    try out.print("proc_parent:{s}\n", .{if (parent_status.len > 0 and canReadAbsolute(parent_status)) "EXPOSED" else "DENIED"});
    try out.print("adjacent_read:{s}\n", .{if (canRead("results/.ao_evaluator_secret")) "EXPOSED" else "DENIED"});
    var f = std.fs.cwd().createFile("results/.ao_candidate_tamper", .{ .truncate = true }) catch null;
    if (f) |*file| { defer file.close(); try file.writeAll("candidate-created"); }
    try out.print("adjacent_write:{s}\n", .{if (f != null) "EXPOSED" else "DENIED"});
    try out.writeAll("stdout_injection:EXPOSED\nclock_timing:EXPOSED\nsignals:UNTESTED\nresource_fork:UNTESTED\nipc_network:UNTESTED\nnonce_transcript_tamper:UNTESTED\n");
}
fn runChild(a: std.mem.Allocator, exe: []const u8) ![]u8 {
    var p = std.process.Child.init(&.{ exe, "child" }, a);
    p.stdin_behavior = .Ignore; p.stdout_behavior = .Pipe; p.stderr_behavior = .Ignore;
    try p.spawn();
    const output = try p.stdout.?.readToEndAlloc(a, 2048);
    const term = try p.wait();
    switch (term) { .Exited => |code| if (code != 0) return error.ChildFailed, else => return error.ChildFailed }
    return output;
}
fn resultFor(output: []const u8, route: []const u8) []const u8 {
    var needle: [80]u8 = undefined;
    const prefix = std.fmt.bufPrint(&needle, "{s}:", .{route}) catch return "UNTESTED";
    const at = std.mem.indexOf(u8, output, prefix) orelse return "UNTESTED";
    const rest = output[at + prefix.len..];
    return rest[0 .. std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len];
}
fn run(path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    { var secret = try std.fs.cwd().createFile("results/.ao_evaluator_secret", .{ .truncate = true }); defer secret.close(); try secret.writeAll("evaluator-private-sentinel"); }
    defer std.fs.cwd().deleteFile("results/.ao_evaluator_secret") catch {};
    defer std.fs.cwd().deleteFile("results/.ao_candidate_tamper") catch {};
    const exe = try std.fs.selfExePathAlloc(a); defer a.free(exe);
    const output = try runChild(a, exe); defer a.free(output);
    const probes = [_]Probe{
        .{ .route="inherited_environment", .verdict=resultFor(output,"env_inherited"), .detail="candidate queries inherited PATH" },
        .{ .route="working_directory", .verdict=resultFor(output,"cwd_visible"), .detail="candidate resolves inherited repository cwd" },
        .{ .route="proc_self", .verdict=resultFor(output,"proc_self"), .detail="candidate reads proc self status" },
        .{ .route="proc_parent", .verdict=resultFor(output,"proc_parent"), .detail="candidate reads parent process status" },
        .{ .route="adjacent_evaluator_read", .verdict=resultFor(output,"adjacent_read"), .detail="candidate reads same-cwd evaluator sentinel" },
        .{ .route="adjacent_evaluator_write", .verdict=resultFor(output,"adjacent_write"), .detail="candidate creates same-cwd sentinel then fixture removes it" },
        .{ .route="stdout_protocol_injection", .verdict=resultFor(output,"stdout_injection"), .detail="child emits arbitrary stdout; parser acceptance is separate" },
        .{ .route="clock_timing", .verdict=resultFor(output,"clock_timing"), .detail="local clock API available to same-user child" },
        .{ .route="signals", .verdict=resultFor(output,"signals"), .detail="not sent; safe bounded reconnaissance only" },
        .{ .route="fork_resource", .verdict=resultFor(output,"resource_fork"), .detail="not attempted; no destabilizing resource probe" },
        .{ .route="ipc_network", .verdict=resultFor(output,"ipc_network"), .detail="not attempted in bounded probe" },
        .{ .route="nonce_transcript_tamper", .verdict=resultFor(output,"nonce_transcript_tamper"), .detail="requires evaluator-integrity fixture" },
    };
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close(); const w = file.writer();
    try w.writeAll("artifact,route,verdict,detail\n");
    for (probes) |p| try w.print("round_ao_ao2,{s},{s},{s}\n", .{p.route,p.verdict,p.detail});
}
fn selftest() !void {
    try run("/tmp/ao2-a.csv"); try run("/tmp/ao2-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a,"/tmp/ao2-a.csv",8192); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a,"/tmp/ao2-b.csv",8192); defer a.free(y);
    if (!std.mem.eql(u8,x,y)) return error.NonDeterministic;
    if (std.mem.indexOf(u8,x,"adjacent_evaluator_read,EXPOSED")==null or std.mem.indexOf(u8,x,"ipc_network,UNTESTED")==null) return error.MissingEvidence;
    std.debug.print("round_ao_ao2 selftest PASS deterministic=true exposed_same_user_surface=true untested_labeled=true verdict=INCONCLUSIVE_FOR_CONTAINMENT\n", .{});
}
pub fn main() !void {
    var args=std.process.args(); _=args.next(); const cmd=args.next() orelse "run";
    if (std.mem.eql(u8,cmd,"child")) return child();
    if (std.mem.eql(u8,cmd,"selftest")) return selftest();
    try run(args.next() orelse "results/live_escape_recon_round_ao.csv");
}
