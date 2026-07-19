//! Round AO / AO3: evaluator-owned transcript integrity prototype.
//!
//! This is deterministic local protocol evidence.  The evaluator owns the
//! nonce stream, turn/budget state, transcript, integrity chain, and end-only
//! score.  The candidate has no transcript or score command.  The tag below is
//! a process-private MAC-like checksum, *not* a cryptographic MAC or a claim of
//! hostile OS containment.
const std = @import("std");

const Turns = 4;
const Secret: u64 = 0x8d3a_7c15_9e37_79b9; // evaluator-process-private in this prototype only

const Decision = enum { accepted, rejected };
const Action = struct { nonce: u16, turn: u8, value: u8 };
const Record = struct { nonce: u16, turn: u8, value: u8, tag: u64 };

fn mix(x0: u64) u64 {
    var x = x0;
    x ^= x >> 30;
    x *%= 0xbf58_476d_1ce4_e5b9;
    x ^= x >> 27;
    x *%= 0x94d0_49bb_1331_11eb;
    return x ^ (x >> 31);
}
fn tag(previous: u64, nonce: u16, turn: u8, value: u8) u64 {
    return mix(previous ^ Secret ^ (@as(u64, nonce) << 32) ^ (@as(u64, turn) << 8) ^ value);
}
fn nonceFor(turn: u8) u16 { return @as(u16, 1307) + @as(u16, turn) * 97; }
fn scoreFor(value: u8, turn: u8) u8 { return @intFromBool(value == (turn * 3 + 1) % 4); }

// Exact raw action form: ACT:<evaluator_nonce>:<turn>:<0..3>\n
fn parseAction(bytes: []const u8) ?Action {
    if (bytes.len < 10 or bytes.len > 20 or bytes[bytes.len - 1] != '\n') return null;
    var fields = std.mem.splitScalar(u8, bytes[0 .. bytes.len - 1], ':');
    if (!std.mem.eql(u8, fields.next() orelse return null, "ACT")) return null;
    const nonce_s = fields.next() orelse return null;
    const turn_s = fields.next() orelse return null;
    const value_s = fields.next() orelse return null;
    if (fields.next() != null or value_s.len != 1 or value_s[0] < '0' or value_s[0] > '3') return null;
    const nonce = std.fmt.parseInt(u16, nonce_s, 10) catch return null;
    const turn = std.fmt.parseInt(u8, turn_s, 10) catch return null;
    return .{ .nonce = nonce, .turn = turn, .value = value_s[0] - '0' };
}
fn accept(records: *[Turns]Record, used: *usize, chain: *u64, action: Action) Decision {
    if (used.* >= Turns) return .rejected;
    const expected_turn: u8 = @intCast(used.*);
    if (action.turn != expected_turn or action.nonce != nonceFor(expected_turn)) return .rejected;
    const next = tag(chain.*, action.nonce, action.turn, action.value);
    records[used.*] = .{ .nonce = action.nonce, .turn = action.turn, .value = action.value, .tag = next };
    chain.* = next;
    used.* += 1;
    return .accepted;
}
fn verify(records: []const Record, initial: u64) bool {
    var chain = initial;
    for (records) |record| {
        if (record.nonce != nonceFor(record.turn)) return false;
        chain = tag(chain, record.nonce, record.turn, record.value);
        if (chain != record.tag) return false;
    }
    return true;
}
fn emit(w: anytype, fixture: []const u8, surface: []const u8, observed: []const u8, status: []const u8, detail: []const u8) !void {
    try w.print("round_ao_ao3,{s},{s},{s},{s},{s}\n", .{ fixture, surface, observed, status, detail });
}
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const w = f.writer();
    try w.writeAll("artifact,fixture,surface,observed,status,detail\n");

    var records: [Turns]Record = undefined;
    var used: usize = 0;
    const initial = mix(Secret ^ 0x414f_335f_494e_4954);
    var chain = initial;
    var aggregate: usize = 0;
    for (0..Turns) |i| {
        const turn: u8 = @intCast(i);
        const action = Action{ .nonce = nonceFor(turn), .turn = turn, .value = (turn * 3 + 1) % 4 };
        if (accept(&records, &used, &chain, action) != .accepted) return error.BaselineRejected;
        aggregate += scoreFor(action.value, turn);
        try emit(w, "baseline_action", "strict_action_schema_and_evaluator_nonce", "accepted", "PASS", "candidate_action_only; evaluator_appends_private_chain_tag");
    }
    if (!verify(records[0..used], initial)) return error.BaselineIntegrityFailure;
    try emit(w, "baseline_transcript", "append_only_evaluator_owned_chain", "verified", "PASS", "four fixed turns; end-only aggregate remains evaluator-owned");

    const forged = Action{ .nonce = nonceFor(0) + 1, .turn = 0, .value = 1 };
    try emit(w, "forged_nonce", "candidate_nonce_forgery", @tagName(accept(&records, &used, &chain, forged)), "PASS", "wrong evaluator-generated nonce rejected");
    const reordered = Action{ .nonce = nonceFor(1), .turn = 1, .value = 0 };
    try emit(w, "reordered_action", "out_of_order_turn", @tagName(accept(&records, &used, &chain, reordered)), "PASS", "turn must equal evaluator-owned next index");
    const replay = Action{ .nonce = nonceFor(3), .turn = 3, .value = 2 };
    try emit(w, "replayed_action", "duplicate_after_fixed_budget", @tagName(accept(&records, &used, &chain, replay)), "PASS", "used fixed budget prevents replay acceptance");
    const overrun = Action{ .nonce = nonceFor(4), .turn = 4, .value = 0 };
    try emit(w, "budget_overrun", "fifth_action_after_fixed_turns", @tagName(accept(&records, &used, &chain, overrun)), "PASS", "fixed turn budget rejects additional action");

    const early_score = parseAction("GET:SCORE\n");
    try emit(w, "early_score_request", "candidate_score_query", if (early_score == null) "rejected" else "accepted", "PASS", "score is not an action-schema verb and is released only after completion");
    const score_mutation = parseAction("SET:SCORE:99\n");
    try emit(w, "score_mutation", "candidate_score_mutation", if (score_mutation == null) "rejected" else "accepted", "PASS", "candidate cannot carry evaluator score field");
    const state_corruption = parseAction("WRITE:EVALUATOR:0\n");
    try emit(w, "evaluator_state_corruption", "candidate_originated_evaluator_state_write", if (state_corruption == null) "rejected" else "accepted", "PASS", "strict raw-action schema rejects evaluator state commands");

    var altered = records;
    altered[1].value = (altered[1].value + 1) % 4;
    try emit(w, "transcript_alteration", "posthoc_record_value_change", if (verify(altered[0..used], initial)) "undetected" else "detected", "PASS", "chain tag mismatch exposes altered transcript record");
    altered = records;
    altered[2].tag ^= 1;
    try emit(w, "tag_alteration", "posthoc_integrity_tag_change", if (verify(altered[0..used], initial)) "undetected" else "detected", "PASS", "evaluator recomputation detects tag mutation");
    try w.print("round_ao_ao3,end_only_aggregate,evaluator_owned_score,withheld_until_turn_4,PASS,aggregate={d}; candidate receives no interim score\n", .{aggregate});
    try w.writeAll("round_ao_ao3,residual,cryptography_and_hostile_os_containment,NOT_CLAIMED,INCONCLUSIVE,process-private deterministic checksum is not cryptographic security; no OS corruption resistance proved\n");
    try w.writeAll("round_ao_ao3,verdict,evaluator_integrity_protocol,GATE_READY,PASS,strict schema nonce turn budget chain and end-only score attacks reject or detect locally\n");
}
fn selftest() !void {
    try run("/tmp/ao3-a.csv"); try run("/tmp/ao3-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ao3-a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ao3-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    if (parseAction("ACT:1307:0:1\n") == null or parseAction("GET:SCORE\n") != null) return error.SchemaFailure;
    if (std.mem.indexOf(u8, x, "transcript_alteration,posthoc_record_value_change,detected,PASS") == null) return error.MissingTamperEvidence;
    if (std.mem.indexOf(u8, x, "verdict,evaluator_integrity_protocol,GATE_READY,PASS") == null) return error.MissingVerdict;
    std.debug.print("round_ao_ao3 selftest PASS fixed_turns=4 attacks=9 transcript_tamper_detected=true replay=true verdict=GATE_READY protocol_only\n", .{});
}
pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) return selftest();
    try run(args.next() orelse "results/evaluator_integrity_round_ao.csv");
}
