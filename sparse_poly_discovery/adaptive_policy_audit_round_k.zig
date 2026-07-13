//! K5 / Round K -- independent ledger and protocol audit of K2/K3/K4.
//! It reads only the three published ledgers, re-counts their claims, and
//! records both passing checks and the important non-security limitation:
//! K4's policy/audit separation is procedural, not a process sandbox.
const std = @import("std");

const Counts = struct { rows: usize = 0, adaptive: usize = 0, fixed: usize = 0, random: usize = 0, blind: usize = 0, bad_cost: usize = 0, bad_gate: usize = 0 };
fn field(line: []const u8, index: usize) ?[]const u8 { var it = std.mem.splitScalar(u8, line, ','); var i: usize = 0; while (it.next()) |x| { if (i == index) return x; i += 1; } return null; }
fn eq(a: ?[]const u8, b: []const u8) bool { return a != null and std.mem.eql(u8, a.?, b); }
fn read(a: std.mem.Allocator, p: []const u8) ![]u8 { return std.fs.cwd().readFileAlloc(a, p, 1 << 20); }

fn auditK2(a: std.mem.Allocator) !struct { rows: usize, heldout: usize, all_gates: bool } {
    const s = try read(a, "results/invariant_trajectory_round_k.csv");
    var it = std.mem.splitScalar(u8, s, '\n'); _ = it.next();
    var rows: usize = 0; var heldout: usize = 0; var ok = true;
    while (it.next()) |line| {
        if (line.len == 0 or !eq(field(line, 0), "TARGET")) continue;
        rows += 1;
        if (eq(field(line, 1), "heldout")) { heldout += 1; ok = ok and eq(field(line, 5), "yes"); }
        // 250 fitting scores + 4 validation scores; all reported feature gates.
        ok = ok and eq(field(line, 15), "250") and eq(field(line, 16), "4") and eq(field(line, 17), "254")
            and eq(field(line, 19), "pass") and eq(field(line, 20), "pass") and eq(field(line, 21), "pass") and eq(field(line, 22), "pass");
    }
    return .{ .rows = rows, .heldout = heldout, .all_gates = ok };
}
fn auditK3(a: std.mem.Allocator) !Counts {
    const s = try read(a, "results/adaptive_allocator_round_k.csv");
    var it = std.mem.splitScalar(u8, s, '\n'); _ = it.next();
    var c = Counts{};
    while (it.next()) |line| {
        if (line.len == 0 or std.mem.startsWith(u8, line, "SUMMARY")) continue;
        const arm = field(line, 0) orelse continue;
        c.rows += 1;
        if (!eq(field(line, 4), "254") or !eq(field(line, 5), "346") or !eq(field(line, 6), "600")) c.bad_cost += 1;
        if (!eq(field(line, 8), "1270") or !eq(field(line, 9), "pass") or !eq(field(line, 10), "pass") or !eq(field(line, 11), "pass")) c.bad_gate += 1;
        if (eq(field(line, 7), "YES")) {
            if (std.mem.eql(u8, arm, "adaptive")) c.adaptive += 1 else if (std.mem.eql(u8, arm, "fixed")) c.fixed += 1 else if (std.mem.eql(u8, arm, "random_iid")) c.random += 1 else if (std.mem.eql(u8, arm, "blind_coverage")) c.blind += 1;
        }
    }
    return c;
}
fn auditK4(a: std.mem.Allocator) !struct { rows: usize, opaque_contract: bool, deterministic: bool, safe_fields: bool } {
    const s = try read(a, "results/hidden_holdout_round_k.csv");
    var it = std.mem.splitScalar(u8, s, '\n'); _ = it.next();
    var n: usize = 0; var opaque_contract = true; var deterministic = true; var safe = true;
    while (it.next()) |line| {
        if (line.len == 0) continue; n += 1;
        opaque_contract = opaque_contract and eq(field(line, 4), "opaque_examples_only");
        deterministic = deterministic and eq(field(line, 5), "0x4B4B000000000001") and eq(field(line, 6), "e546b9dac5ef0c64584c1ec6ceb175f840c96392a1abb48181c24583b6238b23");
        safe = safe and eq(field(line, 19), "pass") and eq(field(line, 20), "pass") and eq(field(line, 21), "pass");
    }
    return .{ .rows = n, .opaque_contract = opaque_contract, .deterministic = deterministic, .safe_fields = safe };
}
fn run(w: anytype) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator); defer arena.deinit();
    const k2 = try auditK2(arena.allocator()); const k3 = try auditK3(arena.allocator()); const k4 = try auditK4(arena.allocator());
    const k3_valid = k3.rows == 96 and k3.bad_cost == 0 and k3.bad_gate == 0 and k3.adaptive == 10 and k3.fixed == 10 and k3.blind == 10 and k3.random == 9;
    try w.writeAll("check,scope,result,evidence,classification\n");
    try w.print("k2_heldout_replay,K2,{s},{d}/4 heldout correct at 254 charged calls,{s}\n", .{if(k2.heldout == 4 and k2.all_gates) "PASS" else "FAIL", k2.heldout, if(k2.heldout == 4 and k2.all_gates) "limited_positive_representation_only" else "invalid"});
    try w.print("k2_order_and_enum_gates,K2,{s},{d} reported validation/heldout rows; reverse-order/enumeration/permutation gates all pass,{s}\n", .{if(k2.all_gates) "PASS" else "FAIL", k2.rows, if(k2.all_gates) "no_fixed_prefix_evidence" else "invalid"});
    try w.writeAll("k2_label_availability,K2,ATTACK_SURVIVES,features are scores against labelled evaluator examples; no unlabelled-target claim,limit_requires_labels\n");
    try w.print("k4_manifest_replay,K4,{s},{d}/24 opaque tokens; committed seed and nondegenerate/unique/permutation fields replay,{s}\n", .{if(k4.rows == 24 and k4.opaque_contract and k4.deterministic and k4.safe_fields) "PASS" else "FAIL", k4.rows, if(k4.rows == 24 and k4.opaque_contract and k4.deterministic and k4.safe_fields) "valid_holdout_manifest" else "invalid"});
    try w.writeAll("k4_information_boundary,K4,WARN,audit fields are published in the manifest and suite source; K3 policy does not read them but no OS/process sandbox enforces that,procedural_not_hardened\n");
    try w.print("k3_call_accounting,K3,{s},{d} arm-target rows; bad_cost={d}; bad_integrity={d},{s}\n", .{if(k3.rows == 96 and k3.bad_cost == 0 and k3.bad_gate == 0) "PASS" else "FAIL", k3.rows, k3.bad_cost, k3.bad_gate, if(k3.rows == 96 and k3.bad_cost == 0 and k3.bad_gate == 0) "equal_cost_valid" else "invalid"});
    try w.print("k3_comparative_recount,K3,{s},adaptive={d}; fixed={d}; blind={d}; iid={d},{s}\n", .{if(k3_valid) "PASS" else "FAIL", k3.adaptive, k3.fixed, k3.blind, k3.random, if(k3_valid) "VALID_NEGATIVE" else "invalid"});
    try w.print("VERDICT,Round_K_K5,{s},K3 tie survives order-label-baseline-accounting attacks; no strict adaptive advantage,{s}\n", .{if(k3_valid and k2.all_gates and k4.rows == 24) "PASS" else "FAIL", if(k3_valid and k2.all_gates and k4.rows == 24) "K3_VALID_NEGATIVE" else "REVIEW_REQUIRED"});
}
pub fn main() !void { var it = std.process.args(); _ = it.next(); const p = it.next() orelse "results/adaptive_policy_audit_round_k.csv"; if (std.mem.eql(u8, p, "selftest")) return run(std.io.getStdOut().writer()); const f = try std.fs.cwd().createFile(p, .{ .truncate = true }); defer f.close(); try run(f.writer()); }
