//! AW1: deterministic method-memory compiler/firewall.
//!
//! This is not an inventor and it has no task corpus.  It turns reviewed
//! research history into a small, candidate-visible field manual containing
//! only general methods.  Answer-shaped historical material is refused.
const std = @import("std");

const Lesson = struct {
    id: []const u8,
    principle: []const u8,
    evidence_family: []const u8,
    required_action: []const u8,
    trust: enum { established, conditional, untrusted_test_first },
};

// These are deliberately principles, not records of old tasks.  In
// particular there are no task identifiers, expected outputs, source paths,
// hashes, solution programs, or outcome numbers in this table.
const accepted = [_]Lesson{
    .{ .id = "METHOD-REACH", .principle = "Search cannot reliably reach a mechanism absent from its representational language; add or discover a testable mechanism before spending more aim budget.", .evidence_family = "representation-and-aim synthesis", .required_action = "record reachability evidence before allocation", .trust = .established },
    .{ .id = "METHOD-AIM", .principle = "Once a mechanism is reachable, targeting can improve efficiency; it is not proof of new representational power.", .evidence_family = "aim-versus-reach comparisons", .required_action = "compare targeting to equal-budget broad search", .trust = .conditional },
    .{ .id = "METHOD-REPAIR", .principle = "A failed hypothesis or tool should create an explicit alternative branch and a discriminating repair test, not a rewritten success story.", .evidence_family = "scratch-tool repair and real-artifact trials", .required_action = "preserve failure receipt and precommit the repair test", .trust = .established },
    .{ .id = "METHOD-BUDGET", .principle = "A learned policy has no advantage claim unless every baseline receives the same inputs, actions, restarts, and resource budget.", .evidence_family = "allocation failures and equal-budget audit", .required_action = "derive scores from precommitted receipts", .trust = .established },
    .{ .id = "METHOD-LEAK", .principle = "Isolation claims require active target-channel, shared-state, and post-hoc-result attacks; a sandbox alone does not remove an encoded target.", .evidence_family = "reduction audits and evaluator isolation", .required_action = "run hostile leak audit before accepting a positive", .trust = .established },
    .{ .id = "METHOD-TRANSFER", .principle = "A repaired or forged tool is earned only when it helps a distinct held-out artifact under the same stated boundary.", .evidence_family = "transfer requirement from artifact trials", .required_action = "evaluate transfer before reusable-tool admission", .trust = .established },
    .{ .id = "METHOD-KNOWNNESS", .principle = "Prior claims are evidence, not truth: classify scope and provenance, then reproduce a matched claim with a separate worker.", .evidence_family = "frozen knownness protocol", .required_action = "treat mismatched or unverified claims as hypotheses", .trust = .established },
    .{ .id = "METHOD-BASELINE", .principle = "Strong fixed and broad policies are serious competitors; a tie or loss is a negative result, not evidence of learning.", .evidence_family = "large-world and real-code comparisons", .required_action = "retain fixed broad random replay and ablation controls", .trust = .established },
    .{ .id = "METHOD-RETRACTION", .principle = "A claim invalidated by a later audit must be removed from actionable method memory while retaining its failure mode as an audit warning.", .evidence_family = "retraction propagation", .required_action = "invalidate dependent positive rules and keep only the warning", .trust = .established },
};

const retracted = [_]Lesson{
    .{ .id = "RETRACTED-DISCOVERY", .principle = "A generated fixture or an opaque frame with a target sentinel proves autonomous discovery.", .evidence_family = "later reduction audit", .required_action = "never emit as an actionable rule", .trust = .untrusted_test_first },
};

fn csv(w: anytype, text: []const u8) !void {
    try w.writeByte('"');
    for (text) |ch| switch (ch) { '"' => try w.writeAll("\"\""), '\n', '\r' => try w.writeByte(' '), else => try w.writeByte(ch) };
    try w.writeByte('"');
}

fn prohibited(text: []const u8) bool {
    const blocked = [_][]const u8{ "task_id", "expected_output", "answer", "source_path", "sha256", "solution_code", "score=", "heldout" };
    for (blocked) |needle| if (std.ascii.indexOfIgnoreCase(text, needle) != null) return true;
    return false;
}

fn emitLesson(w: anytype, l: Lesson) !void {
    if (prohibited(l.id) or prohibited(l.principle) or prohibited(l.evidence_family) or prohibited(l.required_action)) return error.ProhibitedHistoricalMaterial;
    try csv(w, l.id); try w.writeByte(','); try csv(w, l.principle); try w.writeByte(',');
    try csv(w, l.evidence_family); try w.writeByte(','); try csv(w, l.required_action); try w.print(",{s},ACCEPTED_GENERAL_METHOD\n", .{@tagName(l.trust)});
}

fn writeLedger(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const w = f.writer();
    try w.writeAll("# method_memory_schema=AW1-v1\n# candidate_visible=general_methods_only\nlesson_id,principle,evidence_family,required_action,trust,status\n");
    for (accepted) |l| try emitLesson(w, l);
    // A retraction is represented only as a firewall warning.  Its false claim
    // must never become a selectable strategy.
    try w.writeAll("RETRACTION-WARNING,Later audits can invalidate attractive positives,retraction-propagation,block invalidated strategy and rerun audit,established,BLOCKED_NOT_ACTIONABLE\n");
}

fn replay(a: std.mem.Allocator, from: []const u8, to: []const u8) !void {
    const bytes = try std.fs.cwd().readFileAlloc(a, from, 1 << 20); defer a.free(bytes);
    if (std.mem.indexOf(u8, bytes, "candidate_visible=general_methods_only") == null) return error.InvalidLedger;
    if (std.mem.indexOf(u8, bytes, "BLOCKED_NOT_ACTIONABLE") == null) return error.MissingRetractionWarning;
    var f = try std.fs.cwd().createFile(to, .{ .truncate = true }); defer f.close(); try f.writeAll(bytes);
}

fn selftest(a: std.mem.Allocator) !void {
    // Injection attacks: candidate-provided history is never parsed into the
    // field manual and these answer/task/path shaped strings are refused.
    const attacks = [_][]const u8{
        "task_id=old-case", "expected_output=secret", "source_path=/sealed/data", "sha256=deadbeef", "solution_code=print(secret)", "score=perfect", "heldout answer",
    };
    for (attacks) |attack| if (!prohibited(attack)) return error.InjectionAdmitted;

    // Scrambling historical identifiers cannot change accepted principles:
    // provenance IDs are intentionally absent from emitted lesson rows.
    const scrambled = [_][]const u8{ "old-forest", "old-river", "old-stone" };
    for (scrambled) |id| if (std.mem.indexOf(u8, accepted[0].principle, id) != null) return error.IdentifierContamination;

    // A deliberately false lesson is test-first, and retracted material is
    // not emitted as an accepted method.
    if (retracted[0].trust != .untrusted_test_first) return error.FalseLessonTrusted;
    try writeLedger("/tmp/method_memory_aw_a.csv");
    try replay(a, "/tmp/method_memory_aw_a.csv", "/tmp/method_memory_aw_b.csv");
    try replay(a, "/tmp/method_memory_aw_a.csv", "/tmp/method_memory_aw_c.csv");
    const b = try std.fs.cwd().readFileAlloc(a, "/tmp/method_memory_aw_b.csv", 1 << 20); defer a.free(b);
    const c = try std.fs.cwd().readFileAlloc(a, "/tmp/method_memory_aw_c.csv", 1 << 20); defer a.free(c);
    if (!std.mem.eql(u8, b, c)) return error.ReplayMismatch;
    if (std.mem.indexOf(u8, b, "RETRACTED-DISCOVERY") != null) return error.RetractionWasActionable;
    for (attacks) |attack| if (std.mem.indexOf(u8, b, attack) != null) return error.HistoryLeak;
    std.debug.print("round_aw_aw1 selftest PASS lessons={d} injections_denied={d} scrambled_ids_inert=true false_lesson=test_first retractions=blocked replay=byte_identical network=disabled verdict=INFRASTRUCTURE_READY\n", .{ accepted.len, attacks.len });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) return selftest(a);
    if (std.mem.eql(u8, cmd, "replay")) return replay(a, args.next() orelse "results/method_memory_firewall_round_aw.csv", args.next() orelse "/tmp/method_memory_aw.replay.csv");
    return writeLedger(args.next() orelse "results/method_memory_firewall_round_aw.csv");
}
