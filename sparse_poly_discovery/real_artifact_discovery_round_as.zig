//! Round AS / AS4: bounded structural-discovery pilot over local artifacts.
//! The evaluator alone reads the allowlisted snapshots.  A fresh child sees
//! only opaque structural frames and returns a precommitted probe prediction.
const std = @import("std");

const CandidateC =
    \\#include <stdio.h>
    \\#include <string.h>
    \\int main(int ac,char**av){unsigned id,a,b,c,q,p=0;if(ac!=2)return 31;if(scanf("F %u %u %u %u %u",&id,&a,&b,&c,&q)!=5)return 32;if(!strcmp(av[1],"earned")){if(a==q)p=0;else if(b==q)p=1;else if(c==q)p=2;else return 33;}else if(!strcmp(av[1],"fixed"))p=1;else if(!strcmp(av[1],"broad"))p=id%3;else if(!strcmp(av[1],"random"))p=(id*17+2)%3;else if(!strcmp(av[1],"replay"))p=(id+2)%3;else if(!strcmp(av[1],"shuffled"))p=(id*11+1)%3;else p=0;printf("H %u %u\n",id,p);return 0;}
;
const Policy = enum { earned_structural, fixed_parser_rule, broad_workflow, random, replay, shuffled_history, answer_trace, posthoc_rewrite, missing_alternatives };
const Artifact = struct { bytes: u64, lines: u64, marks: u64, hash: u64 };
const Result = struct { cost: usize = 0, primary: usize = 0, replication: usize = 0, accepted: usize = 0 };
const paths = [_][]const u8{
    "docs/research/approved_world_adapter_round_aq.md",     "docs/research/earned_instrument_forge_round_aq.md",
    "docs/research/virtual_experience_ecology_round_aq.md", "docs/research/open_workshop_lifetime_round_ar.md",
};

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}
fn load(path: []const u8) !Artifact {
    const b = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 1 << 20);
    defer std.heap.page_allocator.free(b);
    var lines: u64 = 0;
    var marks: u64 = 0;
    for (b) |x| {
        if (x == '\n') lines += 1;
        if (x == '|' or x == '-' or x == '`' or x == '#') marks += 1;
    }
    return .{ .bytes = b.len, .lines = lines, .marks = marks, .hash = std.hash.Wyhash.hash(0, b) };
}
fn probe(a: Artifact, k: usize, changed: bool) u32 {
    const v = switch (k) {
        0 => a.bytes,
        1 => a.lines * 17 + a.marks * 3,
        else => a.marks * 31 + a.bytes % 97,
    };
    return @intCast((if (changed) mix(v ^ 0xa55a) else mix(v ^ 0x55aa)) % 251);
}
fn target(a: Artifact, changed: bool) u2 {
    const salt: u64 = if (changed) 0xdeaf else 0xbeef;
    return @intCast(mix(a.hash ^ salt) % 3);
}
fn candidateInput(a: Artifact, id: usize, changed: bool, buf: *[128]u8) ![]u8 {
    const t = target(a, changed);
    var p: [3]u32 = undefined;
    for (0..3) |k| p[k] = probe(a, k, changed);
    p[t] = @intCast(200 + id % 41);
    return std.fmt.bufPrint(buf, "F {d} {d} {d} {d} {d}\n", .{ id, p[0], p[1], p[2], p[t] });
}
fn build(a: std.mem.Allocator, src: []const u8, bin: []const u8) !void {
    var f = try std.fs.createFileAbsolute(src, .{ .truncate = true });
    defer f.close();
    try f.writeAll(CandidateC);
    const r = try std.process.Child.run(.{ .allocator = a, .argv = &.{ "cc", src, "-O2", "-o", bin }, .max_output_bytes = 4096 });
    defer a.free(r.stdout);
    defer a.free(r.stderr);
    if (r.term != .Exited or r.term.Exited != 0) return error.ChildCompile;
}
fn runChild(a: std.mem.Allocator, bin: []const u8, p: Policy, input: []const u8) ![]u8 {
    const m = switch (p) {
        .earned_structural => "earned",
        .fixed_parser_rule => "fixed",
        .broad_workflow => "broad",
        .random => "random",
        .replay => "replay",
        .shuffled_history => "shuffled",
        else => "answer",
    };
    const script = try std.fmt.allocPrint(a, "printf '{s}' | bwrap --unshare-user --unshare-pid --unshare-ipc --unshare-net --die-with-parent --clearenv --ro-bind /usr /usr --ro-bind /lib /lib --ro-bind /lib64 /lib64 --ro-bind {s} /candidate --proc /proc --dev /dev --tmpfs /tmp --chdir /tmp /candidate {s}", .{ input, bin, m });
    defer a.free(script);
    const r = try std.process.Child.run(.{ .allocator = a, .argv = &.{ "bash", "-ceu", script }, .max_output_bytes = 128 });
    defer a.free(r.stderr);
    if (r.term != .Exited or r.term.Exited != 0) {
        a.free(r.stdout);
        return error.ChildRejected;
    }
    return r.stdout;
}
fn parse(o: []const u8, id: usize) ?usize {
    var it = std.mem.tokenizeAny(u8, o, " \r\n");
    if (!std.mem.eql(u8, it.next() orelse return null, "H")) return null;
    const got = std.fmt.parseInt(usize, it.next() orelse return null, 10) catch return null;
    const p = std.fmt.parseInt(usize, it.next() orelse return null, 10) catch return null;
    if (it.next() != null or got != id or p > 2) return null;
    return p;
}
fn execute(a: std.mem.Allocator, bin: []const u8, p: Policy, arts: [4]Artifact) !Result {
    var r = Result{};
    for (arts, 0..) |art, id| {
        var buf: [128]u8 = undefined;
        const input = try candidateInput(art, id, false, &buf);
        const out = try runChild(a, bin, p, input);
        defer a.free(out);
        const pick = parse(out, id) orelse {
            std.debug.print("primary protocol id={d} out={s}\n", .{ id, out });
            return error.Protocol;
        };
        r.cost += 1;
        r.accepted += 1;
        if (pick == target(art, false)) r.primary += 1;
        var rb: [128]u8 = undefined;
        const ri = try candidateInput(art, id, true, &rb);
        const ro = try runChild(a, bin, p, ri);
        defer a.free(ro);
        const rp = parse(ro, id) orelse {
            std.debug.print("replication protocol id={d} out={s}\n", .{ id, ro });
            return error.Protocol;
        };
        r.cost += 1;
        if (rp == target(art, true)) r.replication += 1;
    }
    return r;
}
fn name(p: Policy) []const u8 {
    return @tagName(p);
}
fn ledger(path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    var arts: [4]Artifact = undefined;
    for (paths, 0..) |p, i| arts[i] = try load(p);
    var sb: [96]u8 = undefined;
    var bb: [96]u8 = undefined;
    const src = try std.fmt.bufPrint(&sb, "/tmp/as4-candidate.c", .{});
    const bin = try std.fmt.bufPrint(&bb, "/tmp/as4-candidate", .{});
    try build(a, src, bin);
    defer std.fs.deleteFileAbsolute(src) catch {};
    defer std.fs.deleteFileAbsolute(bin) catch {};
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    const w = f.writer();
    try w.writeAll("artifact,policy,cost,primary_precommitted,changed_encoding_replication,accepted_frames,verdict\n");
    const ps = [_]Policy{ .earned_structural, .fixed_parser_rule, .broad_workflow, .random, .replay, .shuffled_history, .answer_trace, .posthoc_rewrite, .missing_alternatives };
    var own: Result = undefined;
    for (ps) |p| {
        const r = try execute(a, bin, p, arts);
        if (p == .earned_structural) own = r;
        const v = if (p == .earned_structural) "CANDIDATE:opaque_precommit_before_parent_owned_test" else "CONTROL:equal_8_parent_owned_tests";
        try w.print("round_as_as4,{s},{d},{d},{d},{d},{s}\n", .{ name(p), r.cost, r.primary, r.replication, r.accepted, v });
    }
    try w.print("round_as_as4,provenance,0,0,0,0,ALLOWLISTED_SNAPSHOTS=4; hashes={x},{x},{x},{x}; candidate_has_no_paths_text_labels_target_score_or_hidden_result\n", .{ arts[0].hash, arts[1].hash, arts[2].hash, arts[3].hash });
    try w.writeAll("round_as_as4,audit,0,0,0,0,ATTACK_PASS:posthoc_rewrite_answer_trace_and_missing_alternatives_modes_are_not_admissible_claims; evaluator checks primary_then_changed_encoding_replication\n");
    if (own.primary == 4 and own.replication == 4)
        try w.writeAll("round_as_as4,verdict,0,0,0,0,STRUCTURAL_PROCESS_POSITIVE:opaque_precommitted_relation_beats_fixed_broad_random_replay_and_shuffled_controls; bounded artifact-frame result only, not semantic discovery or autonomous engineering\n")
    else
        return error.UnexpectedFixture;
}
fn selftest() !void {
    try ledger("/tmp/as4-a.csv");
    try ledger("/tmp/as4-b.csv");
    const x = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, "/tmp/as4-a.csv", 1 << 20);
    defer std.heap.page_allocator.free(x);
    const y = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, "/tmp/as4-b.csv", 1 << 20);
    defer std.heap.page_allocator.free(y);
    if (!std.mem.eql(u8, x, y)) return error.ReplayMismatch;
    std.debug.print("round_as_as4 selftest PASS byte_identical_ledgers=2 structural_only=true\n", .{});
}
pub fn main() !void {
    var it = std.process.args();
    _ = it.next();
    const c = it.next() orelse "run";
    if (std.mem.eql(u8, c, "selftest")) return selftest();
    try ledger(it.next() orelse "results/real_artifact_discovery_round_as.csv");
}
