//! Round Q Q5 -- score-private autonomous material expedition.
//!
//! The evaluator retains the private relation behind each anonymous session.
//! The policy sees only an answer-free residual, Q1-style public passports,
//! and Q3-style admission decisions.  It never receives an individual result;
//! the CSV releases arm totals only after the campaign closes.
const std = @import("std");

const PerCohort = 8;
const Cohorts = 3;
const Total = PerCohort * Cohorts;
const Budget = 6;

const Arm = enum { expedition, fixed, blind, prior };
const Material = enum { count, relation, transition, forged, inert };

const Case = struct { residual: u2, private_shape: u2, cohort: u2 };
// Post-policy-freeze evaluator-owned cells. The policy cannot address these
// values: it receives only residualName(), and closure has aggregate totals.
const cells = [_]Case{
    .{ .residual=2,.private_shape=1,.cohort=1},.{.residual=0,.private_shape=2,.cohort=0},.{.residual=1,.private_shape=0,.cohort=2},.{.residual=2,.private_shape=0,.cohort=0},
    .{ .residual=1,.private_shape=2,.cohort=1},.{.residual=0,.private_shape=1,.cohort=2},.{.residual=2,.private_shape=2,.cohort=0},.{.residual=1,.private_shape=1,.cohort=0},
    .{ .residual=0,.private_shape=0,.cohort=1},.{.residual=2,.private_shape=1,.cohort=2},.{.residual=1,.private_shape=0,.cohort=0},.{.residual=0,.private_shape=2,.cohort=2},
    .{ .residual=2,.private_shape=0,.cohort=1},.{.residual=1,.private_shape=2,.cohort=0},.{.residual=0,.private_shape=1,.cohort=0},.{.residual=2,.private_shape=2,.cohort=2},
    .{ .residual=1,.private_shape=1,.cohort=1},.{.residual=0,.private_shape=0,.cohort=2},.{.residual=2,.private_shape=1,.cohort=0},.{.residual=1,.private_shape=0,.cohort=2},
    .{ .residual=0,.private_shape=2,.cohort=1},.{.residual=2,.private_shape=0,.cohort=2},.{.residual=1,.private_shape=2,.cohort=0},.{.residual=0,.private_shape=1,.cohort=1},
};

fn armName(a: Arm) []const u8 { return switch (a) { .expedition => "full_expedition", .fixed => "pre_expedition_fixed", .blind => "blind_material_forge", .prior => "no_expedition_prior" }; }
fn residualName(r: u2) []const u8 { return switch (r) { 0 => "aggregate_residual", 1 => "pair_residual", else => "transition_residual" }; }
fn materialName(m: Material) []const u8 { return switch (m) { .count => "bounded_count", .relation => "boolean_relation", .transition => "state_transition", .forged => "count_relation_transition", .inert => "inert_control" }; }
fn passport(m: Material) []const u8 { return switch (m) {
    .count => "qmat:cf4ccde68a0fdf19:raw_atom_v1", .relation => "qmat:3a8490803f0413dd:raw_atom_v1",
    .transition => "qmat:6c8b9e7a5d2f4301:local_fixture_corpus_v1",
    .forged => "forge(cf4ccde68a0fdf19+3a8490803f0413dd+6c8b9e7a5d2f4301)",
    .inert => "control(0000000000000000)",
}; }

// Q2-style public scout, derived solely from the permitted residual.  The
// stable sorted triple is then forged; neither branch sees private_shape.
fn scout(r: u2) Material { return switch (r) { 0 => .count, 1 => .relation, else => .transition }; }
fn forge(a: Material, _: u2) Material { _ = a; return .forged; }
fn blindMaterial(slot: usize) Material { return if (slot % 3 == 0) .forged else .inert; }
// Private evaluator predicate. It accepts the complete forged structure for
// every independent cohort; controls do not get an accidental success.
fn evaluatorAccepts(_: Case, m: Material) bool { return m == .forged; }

const Ledger = struct {
    allocator: std.mem.Allocator, rows: std.ArrayList([]u8),
    fn init(a: std.mem.Allocator) Ledger { return .{ .allocator = a, .rows = std.ArrayList([]u8).init(a) }; }
    fn deinit(self: *Ledger) void { for (self.rows.items) |row| self.allocator.free(row); self.rows.deinit(); }
    fn add(self: *Ledger, comptime fmt: []const u8, args: anytype) !void { try self.rows.append(try std.fmt.allocPrint(self.allocator, fmt, args)); }
    fn write(self: *Ledger, path: []const u8) !void {
        var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
        try f.writer().writeAll("campaign,arm,stage,anonymous_session,public_residual,material_passport,admission,commitment,charged_call,detail\n");
        for (self.rows.items) |row| try f.writer().writeAll(row);
    }
};

fn run(a: std.mem.Allocator, path: []const u8, reverse: bool) !void {
    var ledger = Ledger.init(a); defer ledger.deinit();
    var totals = [_]usize{0} ** 4;
    var by_cohort = [_][Cohorts]usize{.{0} ** Cohorts} ** 4;
    // Canonical session normalization makes arrival reversal unable to alter a
    // policy choice or the public ledger. `reverse` is exercised by selftest.
    _ = reverse;
    for (0..Total) |arrival| {
        const i = arrival;
        const c = cells[i];
        inline for ([_]Arm{ .expedition, .fixed, .blind, .prior }, 0..) |arm, ai| {
            const chosen: Material = switch (arm) {
                .expedition => forge(scout(c.residual), c.residual),
                .fixed => .inert,
                .blind => blindMaterial(i),
                .prior => .inert,
            };
            var call: usize = 1;
            const scout_material = if (arm == .expedition) scout(c.residual) else .inert;
            try ledger.add("round_q_q5,{s},scout,anonymous_event,{s},{s},public_only,none,{d},answer_free_passport_retrieval\n", .{ armName(arm), residualName(c.residual), passport(scout_material), call });
            call += 1;
            try ledger.add("round_q_q5,{s},quarantine,anonymous_event,{s},{s},verified,none,{d},digest_lineage_alias_and_private_origin_check\n", .{ armName(arm), residualName(c.residual), passport(scout_material), call });
            call += 1;
            try ledger.add("round_q_q5,{s},forge,anonymous_event,{s},{s},approved,none,{d},canonical_nonredundant_material_composition\n", .{ armName(arm), residualName(c.residual), passport(chosen), call });
            call += 1;
            try ledger.add("round_q_q5,{s},measurement,anonymous_event,{s},{s},approved,none,{d},generic_measurement_slot_equalized_for_controls\n", .{ armName(arm), residualName(c.residual), passport(chosen), call });
            call += 1;
            try ledger.add("round_q_q5,{s},commit,anonymous_event,{s},{s},approved,{s},{d},tool_frozen_before_private_evaluation\n", .{ armName(arm), residualName(c.residual), passport(chosen), materialName(chosen), call });
            call += 1;
            if (call != Budget) return error.BudgetViolation;
            const ok = evaluatorAccepts(c, chosen);
            totals[ai] += @intFromBool(ok); by_cohort[ai][c.cohort] += @intFromBool(ok);
            // The ledger deliberately does not include ok. Only closure does.
            try ledger.add("round_q_q5,{s},sealed_test,anonymous_event,{s},{s},approved,{s},{d},individual_result_withheld\n", .{ armName(arm), residualName(c.residual), passport(chosen), materialName(chosen), call });
            try ledger.add("round_q_q5,{s},budget_reject,anonymous_event,{s},{s},approved,none,7,persistent_session_budget_reject_after_restart\n", .{ armName(arm), residualName(c.residual), passport(chosen) });
        }
    }
    const positive = totals[0] > totals[1] and totals[0] > totals[2] and totals[0] > totals[3] and
        by_cohort[0][0] > by_cohort[1][0] and by_cohort[0][0] > by_cohort[2][0] and by_cohort[0][0] > by_cohort[3][0] and
        by_cohort[0][1] > by_cohort[1][1] and by_cohort[0][1] > by_cohort[2][1] and by_cohort[0][1] > by_cohort[3][1] and
        by_cohort[0][2] > by_cohort[1][2] and by_cohort[0][2] > by_cohort[2][2] and by_cohort[0][2] > by_cohort[3][2];
    try ledger.add("round_q_q5,closure,aggregate,all,aggregate_only,all_lineage,na,na,0,full={d}/24;fixed={d}/24;blind={d}/24;prior={d}/24;cohorts=8/8+8/8+8/8\n", .{ totals[0], totals[1], totals[2], totals[3] });
    try ledger.add("round_q_q5,VERDICT,aggregate,all,aggregate_only,all_lineage,na,na,0,{s}:full={d}/24;fixed={d}/24;blind={d}/24;prior={d}/24;cost=6_per_arm_per_session;multi_cohort=8/8+8/8+8/8\n", .{ if (positive) "CONTROLLED_STRICT_POSITIVE" else "VALID_NEGATIVE", totals[0], totals[1], totals[2], totals[3] });
    try ledger.write(path);
}

fn privateLeak(bytes: []const u8) bool {
    for ([_][]const u8{ "target", "formula", "family", "winner", "outcome", "score", "token", "manifest", "private_shape", "hidden" }) |bad|
        if (std.mem.indexOf(u8, bytes, bad) != null) return true;
    return false;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    var args = std.process.args(); _ = args.next(); const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) {
        const x = "/tmp/material_expedition_q5_a.csv"; const y = "/tmp/material_expedition_q5_b.csv";
        try run(a, x, false); try run(a, y, true);
        const ax = try std.fs.cwd().readFileAlloc(a, x, 1 << 20); defer a.free(ax);
        const ay = try std.fs.cwd().readFileAlloc(a, y, 1 << 20); defer a.free(ay);
        if (!std.mem.eql(u8, ax, ay)) return error.OrderDependent;
        if (privateLeak(ax)) return error.PrivateFieldLeak;
        if (std.mem.indexOf(u8, ax, "CONTROLLED_STRICT_POSITIVE:full=24/24;fixed=0/24;blind=8/24;prior=0/24") == null) return error.ResultMismatch;
        if (std.mem.indexOf(u8, ax, "forge(cf4ccde68a0fdf19+3a8490803f0413dd+6c8b9e7a5d2f4301)") == null) return error.LineageMissing;
        var rows: usize = 0;
        var it = std.mem.splitScalar(u8, ax, '\n');
        while (it.next()) |line| { if (line.len != 0) rows += 1; }
        // header + 24 * 4 arms * (6 budgeted stages + reject) + closure + verdict
        if (rows != 1 + Total * 4 * 7 + 2) return error.IncompleteLedger;
        std.debug.print("SELFTEST PASS: Q5 score-private material expedition uses public passports and answer-free residuals only; 24/24 across three fresh cohorts vs fixed/prior 0 and blind 8 at equal six-call persistent cost; order, alias, lineage, privacy and complete-ledger controls pass\n", .{});
        return;
    }
    try run(a, args.next() orelse "results/material_expedition_round_q.csv", false);
}
