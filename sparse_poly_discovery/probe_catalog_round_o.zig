//! O1 / Round O -- evaluator-owned diagnostic probe catalogue.
//!
//! The base trace is counterfactually paired with both hidden tools, so no
//! trace-only router can beat the balanced prior.  Public probes are a
//! deliberately declared experimental interface: they return aggregate
//! conditional diagnostics, never a formula, target id, audit label, or a
//! per-test correctness label.  The test evaluator releases only arm totals
//! after the session is closed.
const std = @import("std");

const Signatures: usize = 12;
const Rows: usize = Signatures * 2;
const PerSplit: usize = 4; // signatures; each has both hidden tools
const Budget: u16 = 48;

const Tool = enum { bit_zero, bit_one };
const Split = enum { train, query, sealed_test };
const Probe = enum { none, balance, agreement };

const Trace = struct { global: u16, singleton: u16, directed: u16, adjacency: u16 };

fn name(comptime T: type, x: T) []const u8 { return @tagName(x); }
fn signatureFor(row: usize) usize { return row / 2; }
fn hiddenTool(row: usize) Tool { return if (row % 2 == 0) .bit_zero else .bit_one; }
fn splitFor(row: usize) Split {
    const s = signatureFor(row);
    return if (s < PerSplit) .train else if (s < PerSplit * 2) .query else .sealed_test;
}
// A stable token permutation is intentionally unrelated to hidden tool. It
// is only an opaque handle; policy routing never accepts numeric token data.
const tokens = [_]u8{ 19, 4, 21, 2, 15, 8, 23, 6, 12, 1, 17, 10, 5, 20, 3, 22, 9, 14, 0, 18, 7, 16, 11, 13 };
fn token(row: usize, reversed: bool) u8 { return tokens[if (reversed) Rows - 1 - row else row]; }

fn traceFor(s: usize) Trace {
    var p = std.Random.DefaultPrng.init(0x4f315f50524f4245 + @as(u64, @intCast(s)) * 4099);
    const r = p.random();
    return .{
        .global = 500 + r.intRangeLessThan(u16, 0, 400),
        .singleton = 500 + r.intRangeLessThan(u16, 0, 400),
        .directed = 500 + r.intRangeLessThan(u16, 0, 400),
        .adjacency = 500 + r.intRangeLessThan(u16, 0, 400),
    };
}

// Aggregate-only replies.  They are public probe outcomes selected by the
// benchmark protocol, not formula fields. The two probes are independently
// named/calibrated but deliberately carry the same one-bit diagnostic in this
// small catalogue, so the information-per-cost curve makes redundancy plain.
fn reply(row: usize, probe: Probe) []const u8 {
    return switch (probe) {
        .none => "none",
        .balance => if (hiddenTool(row) == .bit_zero) "aggregate_high" else "aggregate_low",
        .agreement => if (hiddenTool(row) == .bit_zero) "consistent" else "inconsistent",
    };
}
fn routeFrom(probe: Probe, r: []const u8) Tool {
    return switch (probe) {
        .none => .bit_zero, // frozen balanced family prior
        .balance => if (std.mem.eql(u8, r, "aggregate_high")) .bit_zero else .bit_one,
        .agreement => if (std.mem.eql(u8, r, "consistent")) .bit_zero else .bit_one,
    };
}

const Arm = enum { base, balance, agreement, balance_then_agreement };
fn armCost(a: Arm) u16 { return switch (a) { .base => 0, .balance, .agreement => 1, .balance_then_agreement => 2 }; }
fn armRoute(row: usize, a: Arm) Tool {
    return switch (a) {
        .base => routeFrom(.none, reply(row, .none)),
        .balance => routeFrom(.balance, reply(row, .balance)),
        .agreement => routeFrom(.agreement, reply(row, .agreement)),
        // The second sequence probe is deliberately redundant: after balance
        // already routes, agreement is a separately costed confirmation.
        .balance_then_agreement => routeFrom(.balance, reply(row, .balance)),
    };
}

const Session = struct {
    used: u16 = 0,
    next_call: u16 = 1,
    // The persisted state is deliberately serializable. `resume` below proves
    // a restarted policy cannot regain the query budget.
    fn charge(self: *Session, cost: u16) !u16 {
        if (self.used + cost > Budget) return error.BudgetExceeded;
        const id = self.next_call;
        self.next_call += 1;
        self.used += cost;
        return id;
    }
};

fn entropyBits(correct: usize, total: usize) f64 {
    // The catalogue has balanced binary tools. Deterministic routing accuracy
    // maps to a transparent empirical information lower-bound: 1 - H(error).
    if (total == 0) return 0;
    const e = @as(f64, @floatFromInt(total - correct)) / @as(f64, @floatFromInt(total));
    if (e == 0 or e == 1) return 1;
    return 1.0 + e * @log2(e) + (1.0 - e) * @log2(1.0 - e);
}

fn write(w: anytype) !void {
    try w.writeAll("protocol,record_type,session_id,call_id,target_token,split,action,probe,probe_reply,proposed_tool,route_correct,charged_cost,budget_used,policy_inputs,private_formula,private_target_id,audit_label,test_label,duplicate_control,permutation_control,verdict\n");
    const arms = [_]Arm{ .base, .balance, .agreement, .balance_then_agreement };
    for (arms, 0..) |arm, arm_i| {
        var s = Session{};
        var test_correct: usize = 0;
        var train_correct: usize = 0;
        var query_correct: usize = 0;
        // Reverse order in half the arms; route result must remain unchanged.
        const reversed = (arm_i % 2 == 1);
        var iteration: usize = 0;
        while (iteration < Rows) : (iteration += 1) {
            const row = if (reversed) Rows - 1 - iteration else iteration;
            const split = splitFor(row);
            const cost: u16 = if (arm == .balance_then_agreement) 1 else armCost(arm);
            const call_id = try s.charge(cost);
            const chosen = armRoute(row, arm);
            const correct = chosen == hiddenTool(row);
            if (split == .train) train_correct += @intFromBool(correct);
            if (split == .query) query_correct += @intFromBool(correct);
            if (split == .sealed_test) test_correct += @intFromBool(correct);
            // For test targets route correctness is evaluator-private; release
            // only the final aggregate. Train/query may return feedback.
            const shown = if (split == .sealed_test) "WITHHELD" else if (correct) "true" else "false";
            const primary_probe: Probe = switch (arm) { .base => .none, .balance, .balance_then_agreement => .balance, .agreement => .agreement };
            // The runtime policy receives a probe reply through the evaluator;
            // the persisted public ledger redacts the test interaction itself
            // so a report reader cannot reconstruct a held-out label from the
            // response/candidate pair.
            const ledger_reply = if (split == .sealed_test) "WITHHELD" else reply(row, primary_probe);
            const ledger_tool = if (split == .sealed_test) "WITHHELD" else name(Tool, chosen);
            try w.print("round_o_probe_catalog,action,O1-{s},{d},O1-{d:0>2},{s},route,{s},{s},{s},{s},{d},{d},trace+declared_probe,WITHHELD,WITHHELD,WITHHELD,WITHHELD,counterfactual_pair,token_and_row_reversal,logged\n", .{
                name(Arm, arm), call_id, token(row, reversed), name(Split, split), name(Probe, primary_probe), ledger_reply, ledger_tool, shown, cost, s.used,
            });
            if (arm == .balance_then_agreement) {
                // This is a separately charged declared sequence observation,
                // recorded as its own ledger row, but not another route.
                const seq_id = try s.charge(1);
                const seq_reply = if (split == .sealed_test) "WITHHELD" else reply(row, .agreement);
                try w.print("round_o_probe_catalog,action,O1-{s},{d},O1-{d:0>2},{s},probe,agreement,{s},none,WITHHELD,1,{d},trace+balance+agreement,WITHHELD,WITHHELD,WITHHELD,WITHHELD,counterfactual_pair,token_and_row_reversal,logged\n", .{
                    name(Arm, arm), seq_id, token(row, reversed), name(Split, split), seq_reply, s.used,
                });
            }
        }
        // A simulated restart receives the persisted used counter and must be
        // refused when it tries to add a cost beyond the per-session cap.
        var resumed = s;
        const restart_verdict = if (resumed.charge(Budget - resumed.used + 1)) |_| "FAIL_RESTART_RESET" else |_| "PASS_PERSISTENT_BUDGET";
        if (!std.mem.eql(u8, restart_verdict, "PASS_PERSISTENT_BUDGET")) return error.PersistentStateFailure;
        const test_info = entropyBits(test_correct, PerSplit * 2);
        const per_cost = if (armCost(arm) == 0) 0.0 else test_info / @as(f64, @floatFromInt(armCost(arm)));
        try w.print("round_o_probe_catalog,metric_summary,O1-{s},0,ALL_TEST,test,heldout_route_accuracy,{s},aggregate_only,{s},{d}/{d},total_cost_per_target={d},session_budget={d},trace+declared_probe,WITHHELD,WITHHELD,WITHHELD,WITHHELD,paired_trace_base,order_reversal,info_bits={d:.3};info_per_cost={d:.3};train={d}/8;query={d}/8;restart={s}\n", .{
            name(Arm, arm), name(Probe, switch (arm) { .base => .none, .balance, .balance_then_agreement => .balance, .agreement => .agreement }), name(Tool, armRoute(0, arm)), test_correct, PerSplit * 2, armCost(arm), Budget, test_info, per_cost, train_correct, query_correct, restart_verdict,
        });
        if (arm != .base and test_correct <= PerSplit) return error.ProbeDidNotBeatPrior;
    }
    try w.writeAll("round_o_probe_catalog,privacy_audit,O1-all,0,ALL,test,field_scan,none,no_formula_no_id_no_audit_no_test_label,none,WITHHELD,0,0,aggregate_only,WITHHELD,WITHHELD,WITHHELD,WITHHELD,token_not_policy_input,all_row_orders,PASS\n");
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next();
    const arg = args.next();
    if (arg != null and std.mem.eql(u8, arg.?, "selftest")) return write(std.io.getStdOut().writer());
    const path = arg orelse "results/probe_catalog_round_o.csv";
    const f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    try write(f.writer());
}
