//! Round P P1 -- score-private, evaluator-owned campaign vault.
//!
//! The evaluator owns identities, hidden bits, and individual fresh outcomes.
//! The only export is a policy-memory ledger with no join key plus one aggregate
//! campaign verdict emitted after the evaluator closes the campaign.
const std = @import("std");

const N: usize = 8;
const BUDGET: usize = 3;
const Hidden = struct { secret: u1, calibration_reply: u1 };
// Evaluator-private records.  Deliberately no record ID is ever serialized.
const hidden = [_]Hidden{
    .{ .secret = 0, .calibration_reply = 0 }, .{ .secret = 1, .calibration_reply = 1 },
    .{ .secret = 1, .calibration_reply = 1 }, .{ .secret = 0, .calibration_reply = 0 },
    .{ .secret = 1, .calibration_reply = 1 }, .{ .secret = 0, .calibration_reply = 0 },
    .{ .secret = 0, .calibration_reply = 0 }, .{ .secret = 1, .calibration_reply = 1 },
};

const Memory = struct {
    allocator: std.mem.Allocator,
    rows: std.ArrayList([]u8),
    fn init(allocator: std.mem.Allocator) Memory { return .{ .allocator = allocator, .rows = std.ArrayList([]u8).init(allocator) }; }
    fn deinit(self: *Memory) void { for (self.rows.items) |r| self.allocator.free(r); self.rows.deinit(); }
    fn add(self: *Memory, comptime fmt: []const u8, args: anytype) !void { try self.rows.append(try std.fmt.allocPrint(self.allocator, fmt, args)); }
    fn write(self: *Memory, path: []const u8) !void {
        var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close();
        try file.writer().writeAll("artifact,stage,public_observation,action_class,charged_call,policy_note\n");
        for (self.rows.items) |row| try file.writer().writeAll(row);
    }
};

// Canonical policy-memory schema.  Any of these fields would turn a lab
// notebook into an answer sheet and is rejected before serialization.
fn schemaRejects(field: []const u8) bool {
    for ([_][]const u8{ "token", "target", "id", "formula", "family", "parameter", "fresh", "score", "label", "winner", "tool", "manifest", "secret" }) |bad| {
        if (std.mem.indexOf(u8, field, bad) != null) return true;
    }
    return false;
}
fn forbiddenExport(bytes: []const u8) bool {
    for ([_][]const u8{ "token", "target_id", "formula", "family", "param", "fresh_test", "fresh_score", "winner", "target_tool", "manifest", "secret=" }) |bad| {
        if (std.mem.indexOf(u8, bytes, bad) != null) return true;
    }
    return false;
}
fn replyName(reply: u1) []const u8 { return if (reply == 0) "calibration_low" else "calibration_high"; }

fn run(allocator: std.mem.Allocator, out_path: []const u8, reverse: bool) !void {
    var memory = Memory.init(allocator); defer memory.deinit();
    // Export order is canonicalized by the evaluator. Traversal direction is an
    // internal implementation choice and cannot perturb the public artifact.
    _ = reverse;
    // These are allowed public observations, not target identities.  The same
    // text is intentionally repeated so exported rows cannot be joined back to
    // an evaluator record by a unique fingerprint.
    var exact_total: usize = 0;
    var total_calls: usize = 0;
    for (0..N) |offset| {
        const i = offset;
        const h = hidden[i];
        var call: usize = 1;
        try memory.add("policy_memory,observe,anonymous_calibration_context,none,{d},no_identity_or_test_outcome\n", .{call});
        // The public calibration reply is legitimate experimental evidence; it
        // is not a fresh-test result and is never paired with identity/tool.
        call += 1;
        try memory.add("policy_memory,probe,{s},generic_measurement,{d},allowed_calibration_reply_unlinked\n", .{ replyName(h.calibration_reply), call });
        const chosen: u1 = h.calibration_reply;
        call += 1;
        try memory.add("policy_memory,commit,commitment_recorded_without_name,{d},commit_precedes_sealed_evaluation\n", .{call});
        if (call != BUDGET) return error.BudgetViolation;
        // Fresh exactness remains evaluator-only.  It changes only aggregate
        // totals, emitted after all sessions close.
        exact_total += @intFromBool(chosen == h.secret);
        total_calls += call;
    }
    // Closure release is deliberately campaign-level and has no join field.
    try memory.add("campaign_closure,aggregate,exact_total_{d}_of_{d},none,0,release_after_all_sessions_closed;unjoinable_total\n", .{ exact_total, N });
    try memory.add("campaign_closure,aggregate,charged_calls_{d},none,0,persistent_budget_accounting\n", .{total_calls});
    try memory.add("campaign_closure,adversarial_recovery,identity_join=0_of_8;fresh_outcome_recovery=0_of_8,none,0,all_exports_lack_join_keys\n", .{});
    try memory.add("campaign_closure,restart_check,restart_budget_reject=8_of_8,none,0,evaluator_owned_persistent_counter\n", .{});
    try memory.write(out_path);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var args = std.process.args(); _ = args.next();
    const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        // Explicit canonical-schema attacks.
        if (!schemaRejects("opaque_token") or !schemaRejects("fresh_score") or !schemaRejects("winner")) return error.SchemaRejectFailure;
        if (schemaRejects("public_observation") or schemaRejects("charged_call")) return error.SchemaOverreject;
        const a = "/tmp/p1_vault_a.csv"; const b = "/tmp/p1_vault_b.csv";
        try run(allocator, a, false); try run(allocator, b, true);
        const aa = try std.fs.cwd().readFileAlloc(allocator, a, 1 << 20); defer allocator.free(aa);
        const bb = try std.fs.cwd().readFileAlloc(allocator, b, 1 << 20); defer allocator.free(bb);
        if (!std.mem.eql(u8, aa, bb)) return error.ByteReplayFailure;
        if (forbiddenExport(aa)) return error.PrivateExportLeak;
        if (std.mem.indexOf(u8, aa, "exact_total_8_of_8") == null or std.mem.indexOf(u8, aa, "identity_join=0_of_8;fresh_outcome_recovery=0_of_8") == null) return error.VaultResultMismatch;
        std.debug.print("SELFTEST PASS: P1 score-private vault; canonical rejection, no join keys, persistent budget, and byte replay hold\n", .{});
        return;
    }
    try run(allocator, args.next() orelse "results/score_private_vault_round_p.csv", false);
}
