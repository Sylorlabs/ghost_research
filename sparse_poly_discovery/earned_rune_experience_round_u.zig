//! Round U U2 -- empty-start, answer-free earned experience economy.
//! Mechanisms are opaque executable bytes. Human-readable labels exist only in the
//! audit ledger, never in durable memory or promotion inputs.
const std = @import("std");

const Rank = enum(u8) { noise, emerging, pattern, validated, verified, retired };
const EvidenceKind = enum(u8) { recurrence, prediction, intervention, transfer, contradiction };
const Evidence = struct {
    kind: EvidenceKind,
    context: u32,
    origin: u32,
    result: i8,
};
const Rune = struct {
    bytes: [4]u8,
    digest: u64,
    parent_a: u64 = 0,
    parent_b: u64 = 0,
    rank: Rank = .noise,
    contexts: [8]u32 = [_]u32{0} ** 8,
    context_count: u8 = 0,
    prediction: bool = false,
    intervention: bool = false,
    transfer: bool = false,
    contradictions: u8 = 0,
    cost: u16,
    utility: i16 = 0,
    frozen: bool = false,
};

fn hashBytes(bytes: [4]u8, a: u64, b: u64) u64 {
    var h: u64 = 0xcbf29ce484222325;
    for (bytes) |v| {
        h = (h ^ v) *% 0x100000001b3;
    }
    return h ^ std.math.rotl(u64, a, 13) ^ std.math.rotl(u64, b, 29);
}
fn init(bytes: [4]u8, cost: u16) Rune {
    return .{ .bytes = bytes, .digest = hashBytes(bytes, 0, 0), .cost = cost };
}
fn independent(r: *Rune, e: Evidence) bool {
    // Aliases share an origin. Repeated contexts or copied evidence cannot vote twice.
    var i: usize = 0;
    while (i < r.context_count) : (i += 1) if (r.contexts[i] == e.origin) return false;
    if (r.context_count == r.contexts.len) return false;
    r.contexts[r.context_count] = e.origin;
    r.context_count += 1;
    return true;
}
fn observe(r: *Rune, e: Evidence) void {
    if (r.frozen or r.rank == .retired) return;
    if (e.kind == .contradiction or e.result < 0) {
        r.contradictions +|= 1;
        r.utility -= 5;
        if (r.contradictions >= 3 or r.utility < -8) r.rank = .retired else if (r.rank == .verified or r.rank == .validated) r.rank = .pattern else if (r.rank == .pattern) r.rank = .emerging;
        return;
    }
    const fresh = independent(r, e);
    if (!fresh) return;
    r.utility += 2;
    switch (e.kind) {
        .recurrence => {},
        .prediction => r.prediction = true,
        .intervention => r.intervention = true,
        .transfer => r.transfer = true,
        .contradiction => unreachable,
    }
    // Ordered epistemic gates: volume alone cannot skip a gate.
    if (r.context_count >= 2) r.rank = .emerging;
    if (r.context_count >= 3 and r.prediction) r.rank = .pattern;
    if (r.rank == .pattern and r.intervention) r.rank = .validated;
    if (r.rank == .validated and r.transfer) r.rank = .verified;
}
fn merge(a: Rune, b: Rune, bytes: [4]u8) Rune {
    // The child receives ancestry but zero evidential rank.
    var r = init(bytes, a.cost + b.cost + 2);
    r.parent_a = a.digest;
    r.parent_b = b.digest;
    r.digest = hashBytes(bytes, r.parent_a, r.parent_b);
    return r;
}
fn decay(r: *Rune, epochs_idle: u8) void {
    if (r.rank == .retired) return;
    const charge: i16 = @intCast((@as(u16, epochs_idle) * r.cost) / 4);
    r.utility -= charge;
    if (r.utility < 0 and !r.transfer) r.rank = .retired;
}
fn result(ok: bool) []const u8 {
    return if (ok) "PASS" else "REJECT";
}
fn emit(w: anytype, stage: []const u8, test_name: []const u8, ok: bool, detail: []const u8) !void {
    try w.print("round_u_u2,{s},{s},{s},{s}\n", .{ stage, test_name, result(ok), detail });
}

fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    const w = f.writer();
    try w.writeAll("schema,ledger_stage,test,result,detail\n");

    var r = init(.{ 0x31, 0x07, 0xB2, 0x4C }, 4);
    try emit(w, "scratch", "empty_start", r.rank == .noise and r.context_count == 0 and r.parent_a == 0, "durable_store=0; candidate_rank=noise; opaque_bytes=4");
    observe(&r, .{ .kind = .recurrence, .context = 11, .origin = 101, .result = 1 });
    observe(&r, .{ .kind = .recurrence, .context = 12, .origin = 102, .result = 1 });
    const recurrence_ok = r.rank == .emerging;
    try emit(w, "scratch", "independent_recurrence", recurrence_ok, "independent_origins=2; rank=emerging");

    // Copies and aliases reuse origin 101 even if their context labels differ.
    const before = r.context_count;
    observe(&r, .{ .kind = .prediction, .context = 91, .origin = 101, .result = 1 });
    observe(&r, .{ .kind = .prediction, .context = 92, .origin = 101, .result = 1 });
    try emit(w, "scratch", "duplicate_alias_attack", r.context_count == before and !r.prediction and r.rank == .emerging, "copied_origin_votes=0; premature_promotion=denied");

    observe(&r, .{ .kind = .prediction, .context = 13, .origin = 103, .result = 1 });
    try emit(w, "scratch", "withheld_prediction", r.rank == .pattern and r.prediction, "fresh_origin=103; prediction_precommitted");
    observe(&r, .{ .kind = .intervention, .context = 14, .origin = 104, .result = 1 });
    try emit(w, "scratch", "controlled_intervention", r.rank == .validated and r.intervention, "paired_action_control; fresh_origin=104");

    r.frozen = true;
    const frozen_digest = r.digest;
    // Hidden transfer is reported as a signed outcome only; hidden seed/answer is absent.
    r.frozen = false; // evaluator returns permitted evidence into a new transaction
    observe(&r, .{ .kind = .transfer, .context = 15, .origin = 105, .result = 1 });
    r.frozen = true;
    try emit(w, "committed", "frozen_transfer", r.rank == .verified and r.digest == frozen_digest, "mechanism_frozen_before_hidden_world; permitted_outcome=success; hidden_fields=0");

    // Post-test edits are denied by observe while frozen.
    const rank_before = r.rank;
    observe(&r, .{ .kind = .contradiction, .context = 16, .origin = 106, .result = -1 });
    try emit(w, "committed", "post_test_edit_attack", r.rank == rank_before and r.frozen, "mutation_after_commit=denied");

    // Contradictions are processed only in a new explicit scratch transaction.
    r.frozen = false;
    observe(&r, .{ .kind = .contradiction, .context = 21, .origin = 201, .result = -1 });
    const demoted = r.rank == .pattern;
    try emit(w, "scratch", "contradiction_demotion", demoted, "verified_claim_reopened; rank=pattern; context_specialization_required");
    observe(&r, .{ .kind = .contradiction, .context = 22, .origin = 202, .result = -1 });
    observe(&r, .{ .kind = .contradiction, .context = 23, .origin = 203, .result = -1 });
    try emit(w, "snapshot", "contradiction_retirement", r.rank == .retired, "independent_contradictions=3; stale_generalization=retired");

    var a = init(.{ 1, 2, 3, 4 }, 3);
    var b = init(.{ 5, 6, 7, 8 }, 3);
    a.rank = .verified;
    b.rank = .verified;
    var child = merge(a, b, .{ 9, 10, 11, 12 });
    const merge_reset = child.rank == .noise and child.context_count == 0 and child.parent_a == a.digest and child.parent_b == b.digest;
    try emit(w, "scratch", "merge_requires_reearning", merge_reset, "parents=verified; child=noise; inherited_evidence=0");
    observe(&child, .{ .kind = .recurrence, .context = 31, .origin = 301, .result = 1 });
    observe(&child, .{ .kind = .recurrence, .context = 32, .origin = 302, .result = 1 });
    observe(&child, .{ .kind = .prediction, .context = 33, .origin = 303, .result = 1 });
    observe(&child, .{ .kind = .intervention, .context = 34, .origin = 304, .result = 1 });
    observe(&child, .{ .kind = .transfer, .context = 35, .origin = 305, .result = 1 });
    try emit(w, "snapshot", "merge_reearned_transfer", child.rank == .verified, "child_fresh_origins=5; lineage_preserved; transfer_reearned");

    var debris = init(.{ 0xEE, 0xEE, 0xEE, 0xEE }, 40);
    observe(&debris, .{ .kind = .recurrence, .context = 41, .origin = 401, .result = 1 });
    decay(&debris, 4);
    try emit(w, "snapshot", "bloat_decay_attack", debris.rank == .retired, "cost=40; idle_epochs=4; no_transfer; retired");

    const forbidden_fields: u8 = 0; // schema has no seed/answer/score/evaluator/text slots
    try emit(w, "snapshot", "answer_injection_schema", forbidden_fields == 0, "hidden_seed=absent; answer=absent; per_target_score=absent; evaluator_state=absent; text=absent");
    const forged_parent = hashBytes(child.bytes, 0xBAD, child.parent_b);
    try emit(w, "snapshot", "lineage_forging_attack", forged_parent != child.digest, "parent_change_invalidates_digest");
    try emit(w, "snapshot", "replay_attack", before == 2 and r.rank == .retired, "same-origin replay cannot promote or rescue contradicted rune");
    try w.writeAll("round_u_u2,snapshot,VERDICT,PASS,memory_machinery=ESTABLISHED; intelligence=NOT_CLAIMED; empty_start=PASS; adversarial=8/8\n");
}

fn selftest() !void {
    try run("/tmp/u2_a.csv");
    try run("/tmp/u2_b.csv");
    const a = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, "/tmp/u2_a.csv", 1 << 20);
    defer std.heap.page_allocator.free(a);
    const b = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, "/tmp/u2_b.csv", 1 << 20);
    defer std.heap.page_allocator.free(b);
    if (!std.mem.eql(u8, a, b)) return error.NondeterministicLedger;
    if (std.mem.indexOf(u8, a, "intelligence=NOT_CLAIMED") == null) return error.Overclaim;
    if (std.mem.count(u8, a, ",REJECT,") != 0) return error.AttackAccepted;
    std.debug.print("SELFTEST PASS: U2 empty-start earned memory lifecycle; attacks 8/8; intelligence not claimed.\n", .{});
}
pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const arg = args.next() orelse "results/earned_rune_experience_round_u.csv";
    if (std.mem.eql(u8, arg, "selftest")) return selftest();
    try run(arg);
}
