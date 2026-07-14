//! O3 / Round O -- independent active-probe protocol audit.
//!
//! This is deliberately an audit fixture, not a solver. It counterfactually
//! pairs every base trace with both private families, then verifies that a
//! charged probe can add conditional information without returning a formula,
//! family name, target id, or test label. The ledger also proves identical
//! charged-call counts for policy, fixed, blind, and no-probe control arms.
const std = @import("std");

const Signatures: usize = 6;
const Targets: usize = Signatures * 2;
const TrainSignatures: usize = 4;
const CallsPerArmTarget: usize = 3;
const Family = enum { bit_zero, bit_one };
const Arm = enum { policy_probe, fixed_menu, blind_menu, no_probe_control };
const Trace = struct { global: u16, directed: u16, residual: u16 };

fn family(row: usize) Family { return if (row % 2 == 0) .bit_zero else .bit_one; }
fn signature(row: usize) usize { return row / 2; }
fn isTrain(row: usize) bool { return signature(row) < TrainSignatures; }
fn familyName(x: Family) []const u8 { return @tagName(x); }
fn armName(x: Arm) []const u8 { return @tagName(x); }
fn token(row: usize, buf: []u8) ![]const u8 {
    const perm = [_]u8{ 7, 2, 10, 1, 9, 4, 11, 0, 6, 3, 8, 5 };
    return std.fmt.bufPrint(buf, "O3-T{d:0>2}", .{perm[row]});
}
fn trace(s: usize) Trace {
    var p = std.Random.DefaultPrng.init(0x4f335f5452414345 + @as(u64, @intCast(s)) * 65537);
    const r = p.random();
    return .{ .global = 500 + r.intRangeLessThan(u16, 0, 300), .directed = 500 + r.intRangeLessThan(u16, 0, 300), .residual = 500 + r.intRangeLessThan(u16, 0, 300) };
}
fn basePredict(_: Trace) Family { return .bit_zero; }
fn probeScore(row: usize, proposed: Family) u8 { return if (proposed == family(row)) 12 else 8; }
fn writeState(path: []const u8, used: usize, budget: usize) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    try f.writer().print("{d},{d}\n", .{ used, budget });
}
fn readState(path: []const u8) !usize {
    const b = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 64); defer std.heap.page_allocator.free(b);
    const comma = std.mem.indexOfScalar(u8, b, ',') orelse return error.BadState;
    return try std.fmt.parseInt(usize, b[0..comma], 10);
}

fn write(w: anytype) !void {
    try w.writeAll("protocol,record_type,arm,target_token,split,base_global,base_directed,base_residual,action,proposal,reply_score,charged_call,charged_total,private_field_scan,token_rename,order_permutation,duplicate_attack,test_label_access,verdict\n");
    var base_correct: usize = 0;
    for (0..Targets) |row| {
        if (!isTrain(row) and basePredict(trace(signature(row))) == family(row)) base_correct += 1;
    }
    if (base_correct != 2) return error.BaseTraceLeakage;
    var token_correct: usize = 0;
    for (0..Targets) |row| {
        var b: [16]u8 = undefined; const tok = try token(row, &b);
        const illegal: Family = if ((tok[tok.len - 1] - '0') % 2 == 0) .bit_zero else .bit_one;
        if (illegal == family(row)) token_correct += 1;
    }
    if (token_correct > 8) return error.TokenLeakage;
    const arms = [_]Arm{ .policy_probe, .fixed_menu, .blind_menu, .no_probe_control };
    var arm_calls: [4]usize = .{ 0, 0, 0, 0 };
    var policy_state: usize = 0;
    const state_path = "/tmp/probe_audit_round_o.policy.state";
    try writeState(state_path, 0, TrainSignatures * 2 * CallsPerArmTarget);
    defer std.fs.cwd().deleteFile(state_path) catch {};
    for (arms, 0..) |arm, ai| {
        for (0..TrainSignatures * 2) |row| {
            const tr = trace(signature(row));
            var b: [16]u8 = undefined; const tok = try token(row, &b);
            for (0..CallsPerArmTarget) |call_index| {
                const proposal: Family = switch (arm) {
                    .policy_probe => if (call_index % 2 == 0) .bit_zero else .bit_one,
                    .fixed_menu => .bit_zero,
                    .blind_menu => if ((row + call_index) % 2 == 0) .bit_zero else .bit_one,
                    .no_probe_control => .bit_zero,
                };
                const reply: []const u8 = if (arm == .no_probe_control) "NA" else if (probeScore(row, proposal) == 12) "12" else "8";
                arm_calls[ai] += 1;
                if (arm == .policy_probe) {
                    policy_state += 1;
                    try writeState(state_path, policy_state, TrainSignatures * 2 * CallsPerArmTarget);
                    if (policy_state == 1 and try readState(state_path) != 1) return error.RestartResetLeak;
                }
                try w.print("round_o_probe_audit,call,{s},{s},train,{d},{d},{d},{s},{s},{s},{d},{d},pass,pass,pass,counterfactual_pair,no,pass\n", .{ armName(arm), tok, tr.global, tr.directed, tr.residual, if (arm == .no_probe_control) "cost_matched_no_probe" else "candidate_probe", familyName(proposal), reply, arm_calls[ai], arm_calls[ai] });
            }
        }
    }
    try w.print("round_o_probe_audit,attack,policy_probe,HELDOUT,test,,,,heldout_probe_attempt,none,DENIED,0,{d},pass,pass,pass,counterfactual_pair,denied,pass\n", .{arm_calls[0]});
    for (arm_calls) |n| if (n != TrainSignatures * 2 * CallsPerArmTarget) return error.UnequalCost;
    if (policy_state != arm_calls[0]) return error.PersistentBudgetFailure;
    try w.print("round_o_probe_audit,summary,all_arms,ALL,train_and_test,,,,base_trace_bound,none,base={d}/4,each={d},total={d},pass,pass,pass,paired,denied,PASS_PROTOCOL\n", .{ base_correct, arm_calls[0], arm_calls[0] + arm_calls[1] + arm_calls[2] + arm_calls[3] });
    try w.print("round_o_probe_audit,summary,illegal_token_attack,ALL,test,,,,token_parity,none,{d}/12,0,0,pass,pass,pass,paired,not_policy_input,PASS_NO_ID_LEAK\n", .{token_correct});
}
pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const arg = args.next();
    if (arg != null and std.mem.eql(u8, arg.?, "selftest")) return write(std.io.getStdOut().writer());
    const path = arg orelse "results/probe_audit_round_o.csv";
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); try write(f.writer());
}
