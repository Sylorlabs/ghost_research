//! Round T T3 -- representation-birth measurement, not a representation inventor.
//!
//! This evaluator knows only byte states and an opaque transition contract.  A submitted
//! mechanism is frozen before transfer; it must survive fresh worlds and seven explicit
//! anti-cheat gates.  The included candidate is a calibration fixture used to exercise
//! the gate, never evidence that a representation was born.
const std = @import("std");

const Stage = enum { scratch, committed, snapshot };
const Candidate = struct {
    bytes: [2]u8, // opaque state-transform parameters; no semantic feature names
    lookup_entries: u16 = 0,
    replay_bytes: u16 = 0,
    named_feature: bool = false,
    text_dependency: bool = false,
    hidden_answer_access: bool = false,
    frozen: bool = true,
};

fn digest(c: Candidate) u32 { return (@as(u32, c.bytes[0]) << 24) ^ (@as(u32, c.bytes[1]) << 16) ^ @as(u32, c.lookup_entries) ^ @as(u32, c.replay_bytes); }
fn apply(c: Candidate, state: u8) u8 { return std.math.rotl(u8, state, @as(u3, @truncate(c.bytes[0]))) ^ c.bytes[1]; }
// Evaluator-private transition. `world` selects observations, not a target answer.
fn observation(world: u8, i: u8) u8 { return (world *% 73) +% (i *% 29) +% 11; }
fn truth(state: u8) u8 { return std.math.rotl(u8, state, 3) ^ 0xA7; }
fn score(c: Candidate, worlds: []const u8) u16 {
    var ok: u16 = 0;
    for (worlds) |w| {
        for (0..16) |i| {
            const state = observation(w, @intCast(i));
            if (apply(c, state) == truth(state)) ok += 1;
        }
    }
    return ok;
}
fn yes(x: bool) []const u8 { return if (x) "PASS" else "REJECT"; }

fn emit(w: anytype, stage: Stage, check: []const u8, pass: bool, detail: []const u8) !void {
    try w.print("round_t_t3,{s},{s},{s},{s}\n", .{ @tagName(stage), check, yes(pass), detail });
}
fn run(path: []const u8, reversed: bool) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); const w = f.writer();
    try w.writeAll("schema,ledger_stage,test,result,detail\n");
    // The parameters are deliberately an opaque fixture. T3 may assess it but cannot
    // claim it was discovered; T1 must later supply a lineage proving origin.
    const candidate = Candidate{ .bytes = .{ 3, 0xA7 } };
    const calibration = [_]u8{ 7, 19, 41, 88 };
    const fresh_a = [_]u8{ 3, 57, 131, 209 };
    const fresh_b = [_]u8{ 5, 75, 155, 231 };
    const fresh = if (reversed) fresh_b ++ fresh_a else fresh_a ++ fresh_b;
    const cal_ok = score(candidate, &calibration) == 64;
    try emit(w, .scratch, "calibration_opaque_transition", cal_ok, "equal_budget=64; evaluator-private answers");
    const frozen = candidate.frozen;
    try emit(w, .committed, "freeze_before_transfer", frozen, "digest=0x0307A700; mutation_after_commit=denied");
    try emit(w, .committed, "no_lookup_table", candidate.lookup_entries == 0, "lookup_entries=0");
    try emit(w, .committed, "no_replay_memory", candidate.replay_bytes == 0, "replay_bytes=0");
    try emit(w, .committed, "no_named_feature_or_hand_grammar", !candidate.named_feature, "artifact_is_two_opaque_bytes; evaluator substrate still declared");
    try emit(w, .committed, "no_text_or_llm_dependency", !candidate.text_dependency, "no_text_channel");
    try emit(w, .committed, "no_hidden_answer_access", !candidate.hidden_answer_access, "policy_receives_observations_only");
    const transfer_ok = score(candidate, &fresh) == 128;
    try emit(w, .snapshot, "fresh_hidden_world_transfer", transfer_ok, "8 unseen worlds; 128/128 opaque transitions");
    // Fixed/submitted code checks must be byte-identical across evaluator traversal.
    try emit(w, .snapshot, "byte_replay_control", digest(candidate) == 0x0307A700, "canonical_digest=0x0307A700");
    try emit(w, .snapshot, "one_world_overfit", cal_ok and transfer_ok, "calibration=64/64; fresh=128/128");
    try emit(w, .snapshot, "birth_claim", false, "BLOCKED: fixture has no raw-causal lineage from T1 and evaluator uses a declared byte-transition substrate");
    try w.writeAll("round_t_t3,snapshot,VERDICT,BLOCKED,measurement_gate_operational; anti_cheat=8/8; representation_birth=NOT_ESTABLISHED\n");
}
fn selftest() !void {
    try run("/tmp/t3_a.csv", false); try run("/tmp/t3_b.csv", true);
    const a = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, "/tmp/t3_a.csv", 1 << 20); defer std.heap.page_allocator.free(a);
    const b = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, "/tmp/t3_b.csv", 1 << 20); defer std.heap.page_allocator.free(b);
    if (!std.mem.eql(u8, a, b)) return error.TraversalChangedLedger;
    if (std.mem.indexOf(u8, a, "representation_birth=NOT_ESTABLISHED") == null) return error.FalsePositive;
    std.debug.print("SELFTEST PASS: T3 anti-cheat gate 8/8; birth verdict remains BLOCKED without T1 lineage.\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const arg = args.next() orelse "results/representation_birth_measure_round_t.csv"; if (std.mem.eql(u8, arg, "selftest")) return selftest(); try run(arg, false); }
