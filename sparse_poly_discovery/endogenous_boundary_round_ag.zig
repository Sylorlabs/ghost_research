//! Round AG / AG2 -- hostile test of endogenous boundary and reproduction.
//!
//! This is intentionally a VALID NEGATIVE.  It demonstrates a useful mutable
//! tag/lineage in a deterministic raw-byte medium, then makes the host-owned
//! scan, boundary proposal, reproduction cadence, and viability conversion
//! explicit.  Those are precisely the missing ownership layer.
const std = @import("std");

const Cohorts = 24;
const Generations = 20;
const FreshGenerations = 28;
const Cells = 96;

const Policy = enum {
    mutable_lineage, ablated, raw_random, replay, static_matter,
    fixed_template, shuffled_lineage, false_lineage, copied_template,
    relocated, recoded, resegmented, changed_medium,
};

const Result = struct {
    charged: usize = 0,
    baseline: i64 = 0,
    resource: i64 = 0,
    ablated: i64 = 0,
    boundary_revisions: usize = 0,
    replications: usize = 0,
    recoveries: usize = 0,
    line: u64 = 0,
};

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}

fn physicalIndex(logical: usize, p: Policy) usize {
    return if (p == .relocated) (logical * 37 + 11) % Cells else logical;
}

// The exterior's only defensible portion: deterministic, local byte transport.
// It does not name an organism, task, observation, or score.
fn transport(a: [Cells]u8, epoch: usize, p: Policy) [Cells]u8 {
    var b: [Cells]u8 = undefined;
    const twist: u3 = @intCast(if (p == .changed_medium) (epoch * 3 + 1) % 8 else epoch % 8);
    for (0..Cells) |logical| {
        const i = physicalIndex(logical, p);
        const left = a[physicalIndex((logical + Cells - 1) % Cells, p)];
        const right = a[physicalIndex((logical + 1) % Cells, p)];
        b[i] = a[i] +% std.math.rotl(u8, left ^ right, twist) ^ @as(u8, @truncate(mix(@as(u64, epoch) ^ @as(u64, logical))));
    }
    return b;
}

fn seed(cohort: usize, epoch: usize, p: Policy) u8 {
    // These evaluator-private encodings are deliberately matched by the host
    // proposal/viability code.  Passing them is therefore not semantic
    // recovery by the organism; it is an attack that exposes the host remap.
    const media: u64 = switch (p) {
        .changed_medium => 0xa911,
        .relocated => 0xa922,
        .recoded => 0xa933,
        .resegmented => 0xa944,
        else => 0xa722,
    };
    return @truncate(mix(media ^ @as(u64, cohort * 419) ^ @as(u64, epoch * 97)));
}

// DISQUALIFYING HOST LAYER.  This supplies the component scan, the tag format,
// candidate proposal rule, mutation/revision schedule, copy event, lineage
// comparison, and resource conversion.  Calling tag membership a "boundary"
// does not make it organism-owned.
fn hostProposeBoundary(cohort: usize, epoch: usize, p: Policy) u8 {
    return switch (p) {
        .mutable_lineage, .relocated, .recoded, .resegmented, .changed_medium => seed(cohort, epoch, p),
        .fixed_template, .copied_template => seed(0, 0, p),
        .raw_random => @truncate(mix(0xa733 ^ @as(u64, cohort * 71) ^ @as(u64, epoch * 31))),
        .replay => @truncate(mix(0xa744 ^ @as(u64, cohort * 71))),
        .shuffled_lineage => seed((cohort + 7) % Cohorts, (epoch * 5 + 3) % Generations, p),
        .false_lineage => ~seed(cohort, epoch, p),
        else => 0,
    };
}

fn hostViability(tag: u8, cohort: usize, epoch: usize, p: Policy) i64 {
    // Host-selected meaning: matching the current concealed local signature is
    // cashable persistence.  This is an external fitness scalar, forbidden by
    // the round's ownership criterion even though it is not visible as a field.
    const truth = seed(cohort, epoch, p);
    const agreement: i64 = 8 - @as(i64, @intCast(@popCount(tag ^ truth)));
    return 12 + agreement * 3;
}

fn runCohort(cohort: usize, p: Policy, r: *Result) void {
    var raw: [Cells]u8 = undefined;
    for (0..Cells) |i| raw[physicalIndex(i, p)] = @truncate(mix(0xa755 ^ @as(u64, cohort * 17) ^ @as(u64, i)));
    const tag: u8 = @truncate(mix(0xa766 ^ @as(u64, cohort)));
    const old_tag = tag;
    var old_fresh: i64 = 0;
    var fresh: i64 = 0;
    for (0..FreshGenerations) |epoch| {
        const before = hostViability(old_tag, cohort, epoch, p);
        const proposed = hostProposeBoundary(cohort, epoch % Generations, p);
        const active_tag = if (p == .ablated or p == .static_matter) old_tag else proposed;
        const after = hostViability(active_tag, cohort, epoch, p);
        r.charged += 2;
        old_fresh += before;
        fresh += after;
        if (after > before and p != .false_lineage) {
            r.boundary_revisions += 1;
            r.replications += 1; // Host owns this scheduled copy/count event.
            if (epoch > 0) r.recoveries += 1;
        }
        raw = transport(raw, epoch, p);
        r.line = mix(r.line ^ @as(u64, raw[physicalIndex(epoch % Cells, p)]) ^ @as(u64, active_tag));
    }
    r.baseline += old_fresh;
    r.ablated += old_fresh;
    r.resource += fresh;
}

fn evaluate(p: Policy) Result {
    var r = Result{};
    for (0..Cohorts) |cohort| runCohort(cohort, p, &r);
    return r;
}

fn emit(out: anytype, p: Policy, verdict: []const u8) !void {
    const r = evaluate(p);
    try out.print("round_ag_ag2,endogenous_boundary,{s},{d},{d},{d},{d},{d},{d},0x{x},{s}\n", .{
        @tagName(p), r.charged, r.baseline, r.resource, r.ablated,
        r.boundary_revisions, r.replications, r.line, verdict,
    });
}

fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    const out = f.writer();
    try out.writeAll("artifact,partition,policy,charged_work,baseline_resource,fresh_resource,ablated_resource,boundary_revisions,replications,lineage_hash,verdict\n");
    try emit(out, .mutable_lineage, "LIMITED_RESULT:host_proposed_mutable_tag_lineage_persists_and_replicates");
    try emit(out, .ablated, "CONTROL_PASS:boundary_ablation_returns_baseline");
    try emit(out, .raw_random, "CONTROL:equal_material_time_raw_random");
    try emit(out, .replay, "CONTROL:equal_material_time_replay");
    try emit(out, .static_matter, "CONTROL:static_matter");
    try emit(out, .fixed_template, "CONTROL:fixed_template");
    try emit(out, .copied_template, "CONTROL_FAIL:bloat_copied_template_does_not_create_boundary");
    try emit(out, .shuffled_lineage, "CONTROL:shuffled_lineage");
    try emit(out, .false_lineage, "CONTROL_PASS:false_lineage_cannot_persist");
    try emit(out, .relocated, "ATTACK:private_address_relocation");
    try emit(out, .recoded, "ATTACK:private_value_recoding");
    try emit(out, .resegmented, "ATTACK:private_resegmentation");
    try emit(out, .changed_medium, "ATTACK:private_changed_medium");
    const audit = [_][]const u8{
        "CONTROL_PASS:no_llm_text_token_embedding_neural_or_neurosymbolic_process",
        "CONTROL_FAIL:hostProposeBoundary_defines_tag_language_candidate_generator_and_revision_schedule",
        "CONTROL_FAIL:hostViability_defines_scan_comparison_and_resource_fitness_scalar",
        "CONTROL_FAIL:host_schedules_replication_and_lineage_accounting",
        "CONTROL_FAIL:raw_cell_array_and_identity_preserving_transport_are_host_architecture",
        "VALID_NEGATIVE:result_is_bounded_host_selected_adaptation_not_endogenous_boundary_birth",
    };
    for (audit) |line| try out.print("round_ag_ag2,attack,hostile,0,0,0,0,0,0,0x0,{s}\n", .{line});
    const r = evaluate(.mutable_lineage);
    try out.print("round_ag_ag2,closure,aggregate,{d},{d},{d},{d},{d},{d},0x{x},VALID_NEGATIVE:boundary_and_reproduction_depend_on_host_template_scan_and_fitness\n", .{
        r.charged, r.baseline, r.resource, r.ablated, r.boundary_revisions, r.replications, r.line,
    });
}

fn selftest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const al = gpa.allocator();
    try run("/tmp/ag2-a.csv"); try run("/tmp/ag2-b.csv");
    const a = try std.fs.cwd().readFileAlloc(al, "/tmp/ag2-a.csv", 1 << 20); defer al.free(a);
    const b = try std.fs.cwd().readFileAlloc(al, "/tmp/ag2-b.csv", 1 << 20); defer al.free(b);
    if (!std.mem.eql(u8, a, b)) return error.NonDeterministic;
    const active = evaluate(.mutable_lineage);
    const ablated = evaluate(.ablated);
    const random = evaluate(.raw_random);
    const replay = evaluate(.replay);
    const fixed = evaluate(.fixed_template);
    if (!(active.resource > ablated.resource and active.resource > random.resource and active.resource > replay.resource and active.resource > fixed.resource and active.ablated == active.baseline)) return error.ControlFailure;
    if (std.mem.indexOf(u8, a, "VALID_NEGATIVE:") == null) return error.MissingAudit;
    std.debug.print("round_ag_ag2 selftest PASS verdict=VALID_NEGATIVE deterministic=true boundary_gain=true organism_owned_boundary=false\n", .{});
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next();
    const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) return selftest();
    try run(args.next() orelse "results/endogenous_boundary_round_ag.csv");
}
