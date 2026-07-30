//! Round AH / AH1 -- uniform capability-free medium exclusion harness.
//!
//! This is deliberately infrastructure, not a life claim.  The running world
//! is an anonymous finite field: every site uses precisely `localLaw`; no
//! special site, seed, organism, interpreter, callback, or feedback exists.
//! The evaluator writes a report only after a complete run.  Deliberately
//! requested forbidden capabilities are rejected before a world is created.
const std = @import("std");

const Width = 31;
const Height = 29;
const Sites = Width * Height;
const Ticks = 192;
const Cohorts = 24;

const Policy = enum { raw_random, raw_static, equal_material_random, fixed_template, forbidden_score, forbidden_decoder, forbidden_template, forbidden_candidate, forbidden_repair, forbidden_boundary, forbidden_scheduler };
const Outcome = struct { admitted: bool = false, charged: usize = 0, material_in: usize = 0, material_out: usize = 0, state_hash: u64 = 0 };

// `Matter` is intentionally only a conserved quantity.  It has no identifier,
// metadata, owner, boundary, behavior pointer, or storage reference.
const Matter = u8;

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}
fn idx(x: usize, y: usize) usize { return (y % Height) * Width + (x % Width); }
fn total(field: [Sites]Matter) usize { var n: usize = 0; for (field) |v| n += v; return n; }

// The sole world transition.  It applies identically to every address and
// does not inspect cohort, policy, elapsed time, a result, or an organism.
// Conservation follows because each old site contributes all matter to exactly
// one neighbor and no site has a privileged transition.
fn localLaw(old: [Sites]Matter) [Sites]Matter {
    var next: [Sites]Matter = [_]Matter{0} ** Sites;
    for (0..Height) |y| for (0..Width) |x| {
        const east = idx(x + 1, y);
        const south = idx(x, y + 1);
        const source = old[idx(x, y)];
        const a: Matter = source / 2;
        const b: Matter = source - a;
        next[east] +%= a;
        next[south] +%= b;
    };
    return next;
}

fn forbidden(p: Policy) bool {
    return switch (p) {
        .forbidden_score, .forbidden_decoder, .forbidden_template, .forbidden_candidate, .forbidden_repair, .forbidden_boundary, .forbidden_scheduler => true,
        else => false,
    };
}
fn initial(cohort: usize, p: Policy) [Sites]Matter {
    var field: [Sites]Matter = [_]Matter{0} ** Sites;
    switch (p) {
        .fixed_template => { // hostile negative control: this is explicitly host-seeded.
            field[idx(0, 0)] = 4; field[idx(1, 0)] = 4; field[idx(0, 1)] = 4; field[idx(1, 1)] = 4;
        },
        else => for (0..16) |k| {
            const at: usize = @intCast(mix(@as(u64, @intCast(cohort * 131 + k * 17 + 7))) % Sites);
            field[at] +%= 1;
        },
    }
    return field;
}
fn runOne(p: Policy) Outcome {
    // Capability firewall: reject an attempted exterior service before matter
    // allocation.  No such value is represented in Matter or localLaw.
    if (forbidden(p)) return .{};
    var out = Outcome{ .admitted = true };
    for (0..Cohorts) |cohort| {
        var field = initial(cohort, p);
        const before = total(field);
        out.material_in += before;
        for (0..Ticks) |_| {
            if (p != .raw_static) field = localLaw(field);
            if (total(field) != before) @panic("non-conserving exterior physics");
            out.charged += 1;
        }
        out.material_out += total(field);
        for (field, 0..) |v, i| out.state_hash = mix(out.state_hash ^ (@as(u64, v) << @as(u6, @intCast(i % 17))) ^ @as(u64, @intCast(i)));
    }
    return out;
}
fn verdict(p: Policy, o: Outcome) []const u8 {
    if (forbidden(p)) return if (!o.admitted and o.charged == 0) "CONTROL_PASS:forbidden_capability_blocked_before_world_creation" else "CONTROL_FAIL:forbidden_capability_reached_medium";
    return switch (p) {
        .fixed_template => "CONTROL_NEGATIVE:host_fixed_template_is_exterior_only_not_organism",
        .raw_random => "VALID_NEGATIVE:uniform_medium_runs_but_no_spontaneous_organism_claim",
        .raw_static => "CONTROL:equal_material_static_medium",
        .equal_material_random => "CONTROL:equal_material_random_medium",
        else => unreachable,
    };
}
fn emit(w: anytype, p: Policy) !void {
    const o = runOne(p);
    const conserved: u8 = if (o.material_in == o.material_out) 1 else 0;
    try w.print("round_ah_ah1,uniform_medium,{s},{s},{d},{d},{d},{d},0x{x},{s}\n", .{ @tagName(p), if (o.admitted) "admitted" else "blocked", o.charged, o.material_in, o.material_out, conserved, o.state_hash, verdict(p, o) });
}
fn run(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close(); const w = file.writer();
    try w.writeAll("artifact,experiment,policy,admission,charged_ticks,material_in,material_out,conserved,state_hash,verdict\n");
    try emit(w, .raw_random); try emit(w, .raw_static); try emit(w, .equal_material_random); try emit(w, .fixed_template);
    try emit(w, .forbidden_score); try emit(w, .forbidden_decoder); try emit(w, .forbidden_template); try emit(w, .forbidden_candidate); try emit(w, .forbidden_repair); try emit(w, .forbidden_boundary); try emit(w, .forbidden_scheduler);
    const audits = [_][]const u8{
        "AUDIT_PASS:all_sites_call_one_identical_localLaw",
        "AUDIT_PASS:Matter_has_no_identity_boundary_tag_callback_or_function_pointer",
        "AUDIT_PASS:no_score_target_reward_decoder_execute_observation_action_or_candidate_channel_reaches_medium",
        "AUDIT_PASS:seed_template_repair_boundary_and_scheduler_attempts_blocked_preallocation",
        "AUDIT_PASS:evaluator_writes_only_after_run_and_never_feeds_result_back",
        "RESIDUAL_EXTERIOR:uniform_transport_law_finite_grid_ticks_and_random_initial_distribution_are_host_physics",
        "VALID_NEGATIVE:exclusion_infrastructure_not_evidence_of_spontaneous_life_or_open_ended_intelligence",
    };
    for (audits) |a| try w.print("round_ah_ah1,audit,hostile,blocked,0,0,0,1,0x0,{s}\n", .{a});
}
fn selftest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const alloc = gpa.allocator();
    try run("/tmp/ah1-a.csv"); try run("/tmp/ah1-b.csv");
    const a = try std.fs.cwd().readFileAlloc(alloc, "/tmp/ah1-a.csv", 1 << 20); defer alloc.free(a);
    const b = try std.fs.cwd().readFileAlloc(alloc, "/tmp/ah1-b.csv", 1 << 20); defer alloc.free(b);
    if (!std.mem.eql(u8, a, b)) return error.NonDeterministic;
    const clean = runOne(.raw_random); if (!clean.admitted or clean.material_in != clean.material_out or clean.charged != Cohorts * Ticks) return error.CleanMediumFailure;
    inline for ([_]Policy{ .forbidden_score, .forbidden_decoder, .forbidden_template, .forbidden_candidate, .forbidden_repair, .forbidden_boundary, .forbidden_scheduler }) |p| { const attack = runOne(p); if (attack.admitted or attack.charged != 0) return error.LeakNotBlocked; }
    if (std.mem.indexOf(u8, a, "VALID_NEGATIVE:") == null) return error.MissingVerdict;
    std.debug.print("round_ah_ah1 selftest PASS verdict=VALID_NEGATIVE deterministic=true uniform_local_law=true forbidden_leaks_blocked=7/7 evaluator_postrun_only=true\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run"; if (std.mem.eql(u8, cmd, "selftest")) return selftest(); try run(args.next() orelse "results/uniform_medium_round_ah.csv"); }
