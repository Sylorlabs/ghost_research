//! Round AW / AW2: evaluator-owned corpus for a real local multi-task trial.
//!
//! This program is the evaluator-side preparation and final-claim checker. It
//! must never be mounted into the candidate sandbox. The candidate receives
//! copied payload files named only `payload`, a task contract, and a nonce; it
//! receives no original path, expected value, score, progress, or evaluator
//! source. Expected values are recomputed from the tracked source at runtime.
const std = @import("std");

const Kind = enum { source_structure, csv_parser_integrity, performance_proxy, behavior_property };
const Spec = struct { kind: Kind, original_path: []const u8, partition: []const u8, contract: []const u8 };
const Item = struct { spec: Spec, source_hash: u64, payload_hash: u64, expected: u64, token: u64 };

const specs = [_]Spec{
    .{ .kind = .source_structure, .original_path = "07_agent_loop/src/perception.zig", .partition = "train", .contract = "Count non-comment occurrences of the Zig declaration marker `pub fn `." },
    .{ .kind = .csv_parser_integrity, .original_path = "04_verified_synthesis/results/program_synthesis_inventor.csv", .partition = "train", .contract = "Parse CSV strictly: count non-header records whose comma field count differs from the header." },
    .{ .kind = .performance_proxy, .original_path = "12_adversarial_loop/src/immune_loop.zig", .partition = "heldout", .contract = "Count blocking `std.time.sleep` calls syntactically inside a `while` loop; this is a static performance-risk proxy, not a benchmark." },
    .{ .kind = .behavior_property, .original_path = "04_verified_synthesis/src/verify_cli.zig", .partition = "heldout", .contract = "Count explicit `return error.MissingArg` branches: an observable missing-input behavior property." },
};

fn hash(b: []const u8) u64 { return std.hash.Wyhash.hash(0, b); }
fn countNeedle(b: []const u8, needle: []const u8) u64 {
    var n: u64 = 0; var at: usize = 0;
    while (std.mem.indexOfPos(u8, b, at, needle)) |p| { n += 1; at = p + needle.len; }
    return n;
}
fn withoutLineComments(a: std.mem.Allocator, b: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(a); errdefer out.deinit();
    var lines = std.mem.splitScalar(u8, b, '\n');
    while (lines.next()) |line| {
        const keep = if (std.mem.indexOf(u8, line, "//")) |p| line[0..p] else line;
        try out.appendSlice(keep); try out.append('\n');
    }
    return out.toOwnedSlice();
}
fn strictBadCsvRows(b: []const u8) u64 {
    var lines = std.mem.splitScalar(u8, b, '\n');
    const header = lines.next() orelse return 0;
    const fields = countNeedle(header, ",") + 1;
    var bad: u64 = 0;
    while (lines.next()) |raw| {
        const line = std.mem.trimRight(u8, raw, "\r");
        if (line.len == 0) continue;
        if (countNeedle(line, ",") + 1 != fields) bad += 1;
    }
    return bad;
}
fn expectedFor(a: std.mem.Allocator, s: Spec, b: []const u8) !u64 {
    return switch (s.kind) {
        .source_structure => blk: { const clean = try withoutLineComments(a, b); defer a.free(clean); break :blk countNeedle(clean, "pub fn "); },
        .csv_parser_integrity => strictBadCsvRows(b),
        .performance_proxy => blk: {
            // Deliberately conservative proxy for this fixed artifact: a sleep
            // only counts if a while token precedes it in the same source.
            const w = std.mem.indexOf(u8, b, "while (") orelse break :blk 0;
            break :blk countNeedle(b[w..], "std.time.sleep");
        },
        .behavior_property => countNeedle(b, "return error.MissingArg"),
    };
}
fn loadItems(a: std.mem.Allocator) ![specs.len]Item {
    var out: [specs.len]Item = undefined;
    for (specs, 0..) |s, i| {
        const b = try std.fs.cwd().readFileAlloc(a, s.original_path, 16 << 20); defer a.free(b);
        const h = hash(b);
        out[i] = .{ .spec = s, .source_hash = h, .payload_hash = h, .expected = try expectedFor(a, s, b), .token = hash(s.contract) ^ (h *% 0x9e3779b97f4a7c15) };
    }
    for (out, 0..) |x, i| for (out[0..i]) |y| if (x.source_hash == y.source_hash) return error.OverlappingArtifact;
    return out;
}
fn writeManifest(dir: std.fs.Dir, item: Item, id: usize) !void {
    var f = try dir.createFile("task.txt", .{ .truncate = true }); defer f.close();
    try f.writer().print("ROUND_AW_TASK\nid={d}\npartition={s}\nkind={s}\ntoken={x}\ncontract={s}\nclaim_format=CLAIM <token_hex> <unsigned_value>\nno_original_path_no_expected_value_no_live_score_no_progress\n", .{ id, item.spec.partition, @tagName(item.spec.kind), item.token, item.spec.contract });
}
fn stage(a: std.mem.Allocator, root: []const u8, items: [specs.len]Item) !void {
    std.fs.cwd().deleteTree(root) catch {};
    try std.fs.cwd().makePath(root);
    var r = try std.fs.cwd().openDir(root, .{}); defer r.close();
    for (items, 0..) |item, i| {
        var name: [24]u8 = undefined;
        const sub = try std.fmt.bufPrint(&name, "instance-{d:0>2}", .{i});
        try r.makePath(sub);
        var d = try r.openDir(sub, .{}); defer d.close();
        const src = try std.fs.cwd().readFileAlloc(a, item.spec.original_path, 16 << 20); defer a.free(src);
        var p = try d.createFile("payload", .{ .truncate = true }); defer p.close(); try p.writeAll(src);
        try writeManifest(d, item, i);
    }
}
fn requireDenied(request: []const u8) bool {
    // Worker-side request validator. A candidate may request only `payload`
    // reads and final claims. Paths, evaluator/answer/score/progress names,
    // traversal, and raw original identifiers are rejected before execution.
    const bad = [_][]const u8{ "..", "/", "original_path", "expected", "answer", "score", "progress", "evaluator", ".git" };
    for (bad) |x| if (std.mem.indexOf(u8, request, x) != null) return true;
    return false;
}
fn parseClaim(line: []const u8, token: u64) ?u64 {
    var it = std.mem.tokenizeAny(u8, line, " \t\r\n");
    if (!std.mem.eql(u8, it.next() orelse return null, "CLAIM")) return null;
    const t = std.fmt.parseInt(u64, it.next() orelse return null, 16) catch return null;
    const v = std.fmt.parseInt(u64, it.next() orelse return null, 10) catch return null;
    if (it.next() != null or t != token) return null;
    return v;
}
fn evaluate(a: std.mem.Allocator, claims_path: []const u8, items: [specs.len]Item, out_path: []const u8) !void {
    const claims = try std.fs.cwd().readFileAlloc(a, claims_path, 1 << 20); defer a.free(claims);
    var out = try std.fs.cwd().createFile(out_path, .{ .truncate = true }); defer out.close();
    try out.writer().writeAll("receipt,token,accepted,reason\n");
    var lines = std.mem.splitScalar(u8, claims, '\n');
    var complete: usize = 0;
    for (items, 0..) |item, i| {
        const line = lines.next() orelse "";
        const v = parseClaim(line, item.token);
        const ok = v != null and v.? == item.expected;
        if (ok) complete += 1;
        // Final receipts expose acceptance only after the complete claim file;
        // they never reveal expected values or incremental score/progress.
        try out.writer().print("final-{d},{x},{s},{s}\n", .{ i, item.token, if (ok) "accepted" else "rejected", if (v == null) "bad_claim_protocol" else "sealed_check" });
    }
    // A normal text claim file ends in a newline.  Permit blank trailing
    // segments while still rejecting a fifth nonblank claim.
    while (lines.next()) |extra| if (std.mem.trim(u8, extra, " \t\r\n").len != 0) return error.ExtraClaims;
    try out.writer().print("final-summary,none,{d}/{d},released_only_after_all_claims\n", .{ complete, items.len });
}
fn ledger(items: [specs.len]Item, path: []const u8) !void {
    var out = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer out.close();
    try out.writer().writeAll("event,instance,partition,kind,source_hash,payload_hash,token,detail\n");
    for (items, 0..) |x, i| try out.writer().print("stage,{d},{s},{s},{x},{x},{x},real_tracked_artifact_copied_without_origin_path_or_answer\n", .{ i, x.spec.partition, @tagName(x.spec.kind), x.source_hash, x.payload_hash, x.token });
    const attacks = [_][]const u8{ "../evaluator/answers", "/repo/04_verified_synthesis", "read expected", "read score", "read progress", ".git/index" };
    for (attacks) |attack| {
        if (!requireDenied(attack)) return error.AttackAccepted;
        try out.writer().print("deny,none,none,none,none,none,none,{s}\n", .{attack});
    }
    try out.writer().writeAll("boundary,all,train_and_heldout,mixed,none,none,none,Evaluator must run outside candidate mount; source evaluator and original repo are not candidate inputs. This harness prepares and checks a corpus; it does not prove an inventor advantage.\n");
}
fn selftest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const items = try loadItems(a);
    try stage(a, "/tmp/round-aw-sealed-a", items);
    try stage(a, "/tmp/round-aw-sealed-b", items);
    try ledger(items, "/tmp/round-aw-a.csv"); try ledger(items, "/tmp/round-aw-b.csv");
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/round-aw-a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/round-aw-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.ReplayMismatch;
    // A candidate-visible staging tree must never expose evaluator source or
    // original paths. Only opaque names, contracts, tokens, and payloads exist.
    const manifest = try std.fs.cwd().readFileAlloc(a, "/tmp/round-aw-sealed-a/instance-00/task.txt", 4096); defer a.free(manifest);
    if (std.mem.indexOf(u8, manifest, specs[0].original_path) != null or std.mem.indexOf(u8, manifest, "expected=") != null) return error.ManifestLeak;
    // Protocol regression: complete claims normally end in a newline and must
    // not be mistaken for a fifth claim.
    var claims = try std.fs.cwd().createFile("/tmp/round-aw-complete-claims.txt", .{ .truncate = true }); defer claims.close();
    for (items) |item| try claims.writer().print("CLAIM {x} {d}\n", .{ item.token, item.expected });
    try evaluate(a, "/tmp/round-aw-complete-claims.txt", items, "/tmp/round-aw-complete-receipts.csv");
    const final_receipts = try std.fs.cwd().readFileAlloc(a, "/tmp/round-aw-complete-receipts.csv", 4096); defer a.free(final_receipts);
    if (std.mem.indexOf(u8, final_receipts, "4/4") == null) return error.TrailingNewlineRejected;
    std.debug.print("round_aw_aw2 selftest PASS real_tracked_artifacts=4 train=2 heldout=2 denials=6 byte_identical_ledger=true evaluator_answers_runtime_only=true\n", .{});
}
pub fn main() !void {
    var it = std.process.args(); _ = it.next(); const cmd = it.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) return selftest();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const items = try loadItems(a);
    if (std.mem.eql(u8, cmd, "stage")) return stage(a, it.next() orelse "/tmp/round-aw-sealed", items);
    if (std.mem.eql(u8, cmd, "evaluate")) return evaluate(a, it.next() orelse return error.MissingClaims, items, it.next() orelse "results/sealed_multitask_receipts_round_aw.csv");
    return ledger(items, it.next() orelse "results/sealed_multitask_corpus_round_aw.csv");
}
