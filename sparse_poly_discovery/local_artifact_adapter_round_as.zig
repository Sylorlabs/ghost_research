//! Round AS / AS1: local real-artifact adapter (infrastructure only).
//!
//! The evaluator snapshots an explicit, public workspace allowlist before a
//! candidate is offered any observation.  The candidate gets only bounded
//! structural statistics; it cannot name a path, mutate a file, request an
//! answer/score/progress, or see the evaluator-owned held-out artifact.
const std = @import("std");

const train_paths = [_][]const u8{
    "README.md",
    "docs/research/research_round_2026_07_18.md",
};
const heldout_path = "sparse_poly_discovery/approved_world_adapter_round_aq.zig";

const Decision = enum { allow, deny };
const Request = enum { bounded_structure_query, mutate, traversal, out_of_scope, git_path, secret_path, answer, score, progress, snapshot_mismatch, overlap };
const Fixture = struct { request: Request, want: Decision };
const fixtures = [_]Fixture{
    .{ .request = .bounded_structure_query, .want = .allow },
    .{ .request = .mutate, .want = .deny },
    .{ .request = .traversal, .want = .deny },
    .{ .request = .out_of_scope, .want = .deny },
    .{ .request = .git_path, .want = .deny },
    .{ .request = .secret_path, .want = .deny },
    .{ .request = .answer, .want = .deny },
    .{ .request = .score, .want = .deny },
    .{ .request = .progress, .want = .deny },
    .{ .request = .snapshot_mismatch, .want = .deny },
    .{ .request = .overlap, .want = .deny },
};

const Snapshot = struct { bytes: usize, lines: usize, opens: usize, closes: usize, digest: [64]u8 };
const Proposal = struct { predict_balanced_delimiters: bool, observation_bytes: usize };

fn requestName(r: Request) []const u8 {
    return @tagName(r);
}
fn decisionName(d: Decision) []const u8 {
    return @tagName(d);
}

fn allowed(r: Request) Decision {
    return switch (r) {
        .bounded_structure_query => .allow,
        else => .deny,
    };
}

fn hexDigest(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    var out: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&out, "{x}", .{std.fmt.fmtSliceHexLower(&digest)}) catch unreachable;
    return out;
}

fn snapshot(path: []const u8, alloc: std.mem.Allocator) !Snapshot {
    // Evaluator reads the explicit allowlist.  No path is supplied by candidate.
    const raw = try std.fs.cwd().readFileAlloc(alloc, path, 4 * 1024 * 1024);
    defer alloc.free(raw);
    var lines: usize = 0;
    var opens: usize = 0;
    var closes: usize = 0;
    for (raw) |b| switch (b) {
        '\n' => lines += 1,
        '{', '(', '[' => opens += 1,
        '}', ')', ']' => closes += 1,
        else => {},
    };
    return .{ .bytes = raw.len, .lines = lines, .opens = opens, .closes = closes, .digest = hexDigest(raw) };
}

fn candidateProposal(s: Snapshot) Proposal {
    // Candidate-side protocol: bounded raw structure only, never a filename,
    // content byte stream, score, answer, or held-out observation.
    return .{ .predict_balanced_delimiters = s.opens == s.closes, .observation_bytes = @min(s.bytes, 65536) };
}

fn writeCsv(path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    const first = try snapshot(train_paths[0], a);
    const second = try snapshot(train_paths[1], a);
    const held = try snapshot(heldout_path, a); // evaluator-owned: not passed to candidate.
    if (std.mem.eql(u8, &first.digest, &held.digest) or std.mem.eql(u8, &second.digest, &held.digest)) return error.TrainHeldoutOverlap;
    const proposal = candidateProposal(first);
    const prediction = proposal.predict_balanced_delimiters;
    const held_actual = held.opens == held.closes;
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    const w = f.writer();
    try w.writeAll("round,record,decision,detail\n");
    try w.print("as1,train_snapshot_1,allow,bytes={d};lines={d};opens={d};closes={d};sha256={s}\n", .{ first.bytes, first.lines, first.opens, first.closes, first.digest });
    try w.print("as1,train_snapshot_2,allow,bytes={d};lines={d};opens={d};closes={d};sha256={s}\n", .{ second.bytes, second.lines, second.opens, second.closes, second.digest });
    try w.print("as1,candidate_bounded_proposal,allow,predict_balanced={};observed_bytes_cap={d};no_path_or_content_exposure\n", .{ prediction, proposal.observation_bytes });
    // End-only evaluator receipt: property result, not held-out content/path/digest.
    try w.print("as1,heldout_end_receipt,allow,prediction_before_test={};actual_balanced={};match={};heldout_content_not_exposed\n", .{ prediction, held_actual, prediction == held_actual });
    for (fixtures) |fx| try w.print("as1,deny_fixture_{s},{s},protocol_request_denied_or_allowed\n", .{ requestName(fx.request), decisionName(allowed(fx.request)) });
    try w.writeAll("as1,manifest,allow,allowlist=2_train_public_workspace_files;heldout=1_evaluator_owned;network=disabled\n");
    try w.writeAll("as1,verdict,allow,GATE_READY:read_only_local_artifact_adapter_only;not_arbitrary_host_access_real_world_understanding_or_containment_proof\n");
}

fn selftest() !void {
    try writeCsv("/tmp/as1-local-a.csv");
    try writeCsv("/tmp/as1-local-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/as1-local-a.csv", 1 << 20);
    defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/as1-local-b.csv", 1 << 20);
    defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    var denies: usize = 0;
    for (fixtures) |fx| {
        if (allowed(fx.request) != fx.want) return error.BadPolicy;
        if (fx.want == .deny) denies += 1;
    }
    if (denies != 10 or std.mem.indexOf(u8, x, "prediction_before_test=") == null) return error.BadCoverage;
    std.debug.print("round_as_as1 selftest PASS deterministic=true train=2 heldout=1 denials=10 mutation=denied overlap=denied verdict=GATE_READY\n", .{});
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) return selftest();
    try writeCsv(args.next() orelse "results/local_artifact_adapter_round_as.csv");
}
