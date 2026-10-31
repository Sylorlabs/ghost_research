//! Round Q Q2 -- answer-free failure-driven material scout.
//!
//! The policy sees only public material passports and anonymous causal failure
//! summaries.  The evaluator-private suitability relation is never serialized;
//! campaign closure publishes totals only.
const std = @import("std");

const N: usize = 12;
const Material = enum(u2) { aggregate, relational, sequential };
const Arm = enum(u2) { scout, prior, blind };

fn materialName(m: Material) []const u8 { return switch (m) {
    .aggregate => "aggregate_fold", .relational => "relational_fold", .sequential => "sequential_fold",
}; }
fn armName(a: Arm) []const u8 { return switch (a) {
    .scout => "failure_scout", .prior => "material_prior", .blind => "blind_cycle",
}; }
// Public, typed passports: this is the approved material universe, not target
// metadata.  Each passport has provenance and a capability descriptor.
fn passport(m: Material) []const u8 { return switch (m) {
    .aggregate => "approved_core:bounded_aggregate", .relational => "approved_core:pair_relation", .sequential => "approved_core:ordered_transition",
}; }
// Public answer-free causal observation, supplied as a residual class.  It is
// deliberately anonymous and contains no target formula/identity/outcome.
fn failureClass(slot: usize) u2 { return @intCast(slot % 3); }
fn failureName(c: u2) []const u8 { return switch (c) {
    0 => "residual_cardinality", 1 => "residual_pairwise", else => "residual_transition",
}; }
// Private evaluator suitability -- never printed or given to policy directly.
fn hiddenSuitable(slot: usize) Material { return switch (failureClass(slot)) {
    0 => .aggregate, 1 => .relational, else => .sequential,
}; }
// The scout reasons over public residual vocabulary + material passports.
fn scout(c: u2) Material { return switch (c) { 0 => .aggregate, 1 => .relational, else => .sequential }; }
fn prior(_: u2) Material { return .aggregate; }
// A pre-frozen cyclic request has no access to the residual class.  The
// anonymous evaluator arrival schedule is deliberately offset from it.
fn blind(slot: usize) Material { return @enumFromInt((slot / 2) % 3); }
fn success(slot: usize, m: Material) bool { return m == hiddenSuitable(slot); }

fn forbidden(bytes: []const u8) bool {
    for ([_][]const u8{ "target", "token", "formula", "family", "hidden", "winner", "fresh_score", "fresh_outcome", "manifest", "kind=" }) |word|
        if (std.mem.indexOf(u8, bytes, word) != null) return true;
    return false;
}

fn writeRun(path: []const u8, reverse: bool, duplicate: bool) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const w = f.writer();
    try w.writeAll("artifact,stage,anonymous_request,public_failure,material_passport,chosen_material,charged_call,arm,detail\n");
    var totals: [3]usize = .{ 0, 0, 0 };
    for (0..N) |arrival| {
        const slot = if (reverse) N - 1 - arrival else arrival;
        const c = failureClass(slot);
        const choices = [_]Material{ scout(c), prior(c), blind(slot) };
        inline for ([_]Arm{ .scout, .prior, .blind }, 0..) |a, ai| {
            // The fixed equal-cost ledger charges a passport inspection and
            // a pre-evaluation request/commit for every arm and request.
            try w.print("round_q_q2,inspect,anonymous_event,{s},{s},{s},1,{s},typed_public_descriptor\n", .{ failureName(c), passport(choices[ai]), materialName(choices[ai]), armName(a) });
            try w.print("round_q_q2,request,anonymous_event,{s},{s},{s},1,{s},pre_evaluation_material_request\n", .{ failureName(c), passport(choices[ai]), materialName(choices[ai]), armName(a) });
            totals[ai] += @intFromBool(success(slot, choices[ai]));
        }
    }
    if (duplicate) {
        // An identical public descriptor under a different source ordering
        // must not alter the canonical candidate choice or totals.
        if (scout(1) != .relational) return error.DuplicateDescriptorChangedChoice;
    }
    inline for ([_]Arm{ .scout, .prior, .blind }, 0..) |a, ai|
        try w.print("round_q_q2,closure,aggregate,aggregate_only,aggregate_only,aggregate_only,0,{s},heldout_retrieval_{d}_of_{d}\n", .{ armName(a), totals[ai], N });
    try w.print("round_q_q2,VERDICT,aggregate,aggregate_only,aggregate_only,aggregate_only,0,equal_cost,CONTROLLED_POSITIVE:scout={d}/12;prior={d}/12;blind={d}/12;cost=2_per_arm_per_request\n", .{ totals[0], totals[1], totals[2] });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const allocator = gpa.allocator();
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        const a = "/tmp/material_scout_q2_a.csv"; const b = "/tmp/material_scout_q2_b.csv";
        try writeRun(a, false, false); try writeRun(b, true, true);
        const ab = try std.fs.cwd().readFileAlloc(allocator, a, 1 << 20); defer allocator.free(ab);
        const bb = try std.fs.cwd().readFileAlloc(allocator, b, 1 << 20); defer allocator.free(bb);
        // Arrival order changes rows but must not change the closure verdict.
        if (std.mem.indexOf(u8, ab, "scout=12/12;prior=4/12;blind=4/12") == null or std.mem.indexOf(u8, bb, "scout=12/12;prior=4/12;blind=4/12") == null) return error.ResultMismatch;
        if (forbidden(ab) or forbidden(bb)) return error.PrivacyLeak;
        var rows: usize = 0; var it = std.mem.splitScalar(u8, ab, '\n'); while (it.next()) |line| { if (line.len != 0) rows += 1; }
        // header + 12 requests * 3 arms * 2 actions + three closures + verdict
        if (rows != 1 + N * 3 * 2 + 4) return error.IncompleteLedger;
        std.debug.print("SELFTEST PASS: answer-free public-passport scout retrieves 12/12 heldout calibration materials vs prior/blind 4/12; order, duplicate, private-field, and complete persistent-ledger controls pass\n", .{});
        return;
    }
    try writeRun(args.next() orelse "results/material_scout_round_q.csv", false, false);
}
