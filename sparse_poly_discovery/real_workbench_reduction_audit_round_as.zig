//! Round AS / AS6: local-only adversarial reduction audit.
//!
//! This audit does not rerun a network capture.  It checks source-level
//! invariants that must hold before AS3/AS4 can be called discovery.  A failed
//! invariant reduces a claim; it is not silently relabelled as a negative run.
const std = @import("std");

const Row = struct { subject: []const u8, attack: []const u8, evidence: []const u8, verdict: []const u8 };

fn contains(path: []const u8, needle: []const u8, a: std.mem.Allocator) !bool {
    const bytes = try std.fs.cwd().readFileAlloc(a, path, 1 << 20);
    defer a.free(bytes);
    return std.mem.indexOf(u8, bytes, needle) != null;
}

fn writeLedger(path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    const as3 = "sparse_poly_discovery/workbench_scheduler_round_as.zig";
    const as4 = "sparse_poly_discovery/real_artifact_discovery_round_as.zig";
    const as5 = "sparse_poly_discovery/web_observation_transfer_round_as.zig";

    // Fail closed: these exact mechanisms are the audit's evidence, not a
    // guessed interpretation of a previous report.
    const as4_answer_leak = try contains(as4, "const t = target(a, changed);", a) and
        try contains(as4, "p[t] = @intCast(200 + id % 41);", a) and
        try contains(as4, "if(a==q)p=0;else if(b==q)p=1;else if(c==q)p=2", a);
    const as3_generated_world = try contains(as3, "fn relation(world", a) and
        try contains(as3, "fn target(world", a) and
        try contains(as3, "The corpus is generated inside this evaluator", a);
    const as3_shared_program = try contains(as3, "fn action(p: Policy", a) and
        try contains(as3, "for(ps,0..)|p,i| vals[i]=run(p", a);
    const as3_unequal_wall = try contains(as3, "long and p==.learned_provenance", a);
    const as3_posthoc_curve = try contains(as3, "learned_checkpoint_48,2304", a) and
        try contains(as3, "learned_checkpoint_192,9648", a);
    const as5_honest_negative = try contains(as5, "VALID_NEGATIVE", a) and
        try contains(as5, "const fixed = passes(.{ .nonempty = true, .mostly_printable = true }, s2);", a);

    if (!as4_answer_leak or !as3_generated_world or !as3_shared_program or !as3_unequal_wall or !as3_posthoc_curve or !as5_honest_negative)
        return error.AuditEvidenceChanged;

    const rows = [_]Row{
        .{ .subject = "AS1", .attack = "denial_surface", .evidence = "request enum and allowed() deny fixtures exist; no independently sandboxed hostile candidate is exercised", .verdict = "SURVIVES_ONLY_AS_PROTOCOL_GATE_NOT_CONTAINMENT_PROOF" },
        .{ .subject = "AS2", .attack = "capture_replay", .evidence = "fixed GET allowlist and cached replay are reproducible; candidate request surface is not separately hostile-tested", .verdict = "SURVIVES_ONLY_AS_PROTOCOL_GATE_NOT_WEB_CAPABILITY" },
        .{ .subject = "AS3", .attack = "real_artifact_reduction", .evidence = "relation() and target() generate the corpus inside one evaluator; no local artifact bytes are parsed", .verdict = "REDUCED_INVALID_AS_REAL_ARTIFACT_POSITIVE" },
        .{ .subject = "AS3", .attack = "candidate_evaluator_coupling", .evidence = "action(policy), target(), controls, scoring, and verdict live in the same executable", .verdict = "REDUCED_INVALID_AS_ISOLATED_DISCOVERY" },
        .{ .subject = "AS3", .attack = "equal_budget_reduction", .evidence = "only learned_provenance receives long=true; controls run one pass", .verdict = "REDUCED_INVALID_AS_EQUAL_WALL_TIME_COMPARISON" },
        .{ .subject = "AS3", .attack = "posthoc_curve_reduction", .evidence = "reported checkpoint curve literals 2304,4992,9648 are written as constants rather than derived measurements", .verdict = "REDUCED_INVALID_AS_MEASURED_LEARNING_CURVE" },
        .{ .subject = "AS4", .attack = "direct_answer_leak", .evidence = "candidateInput computes t=target(), writes sentinel into p[t], and child returns index whose frame value equals q", .verdict = "REDUCED_INVALID_AS_STRUCTURAL_DISCOVERY" },
        .{ .subject = "AS4", .attack = "changed_encoding_reduction", .evidence = "the same target-index sentinel is regenerated after changed=true, so replication repeats the leak", .verdict = "REDUCED_INVALID_AS_INDEPENDENT_REPLICATION" },
        .{ .subject = "AS5", .attack = "fixed_rule_reduction", .evidence = "source marks fixed/broad/replay/shuffled/scrubbed ties VALID_NEGATIVE", .verdict = "HONEST_VALID_NEGATIVE_CONFIRMED" },
        .{ .subject = "AS6", .attack = "scope_limit", .evidence = "source-local audit and cached replays only; no semantic task, bug discovery, unrestricted web, or general intelligence test", .verdict = "NO_GENERAL_INTELLIGENCE_CLAIM" },
    };

    var file = if (std.fs.path.isAbsolute(path)) try std.fs.createFileAbsolute(path, .{ .truncate = true }) else try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    const w = file.writer();
    try w.writeAll("round,subject,attack,evidence,verdict\n");
    for (rows) |r| try w.print("round_as,\"{s}\",\"{s}\",\"{s}\",{s}\n", .{ r.subject, r.attack, r.evidence, r.verdict });
    try w.writeAll("round_as,summary,independent_reduction_audit,AS3_and_AS4_do_not_survive_their_discovery_claims;AS1_AS2_remain_narrow_protocol_gates;AS5_negative_is_honest,AS6_COMPLETE\n");
}

fn selftest() !void {
    try writeLedger("/tmp/as6-a.csv");
    try writeLedger("/tmp/as6-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/as6-a.csv", 1 << 20);
    defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/as6-b.csv", 1 << 20);
    defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.ReplayMismatch;
    if (std.mem.indexOf(u8, x, "REDUCED_INVALID_AS_STRUCTURAL_DISCOVERY") == null) return error.MissingLeakFinding;
    std.debug.print("round_as_as6 selftest PASS deterministic=true local_only=true as3_reduced=true as4_answer_leak=true as5_negative_honest=true verdict=REDUCTION_COMPLETE\n", .{});
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) return selftest();
    try writeLedger(args.next() orelse "results/real_workbench_reduction_audit_round_as.csv");
}
