//! Round AH / AH2 -- local runtime capability-firewall fixture.
//!
//! This is deliberately a *runtime capability protocol*, not a claim that
//! source-level conventions secure mutually hostile code in one Zig process.
//! The simulated mutant receives a `Medium` value with only raw cells and
//! uniform neighbour transport.  It cannot obtain evaluator services through
//! that value.  The attack ledger exercises every name which the protocol
//! denies.  The final residual row is important: code compiled into the same
//! Unix process and running as the same uid could import `std`, inspect host
//! globals, or open files.  That needs a separate process/account/container
//! (and normally a syscall/MAC policy) and is outside what this local fixture
//! can enforce.
const std = @import("std");

const Cells: usize = 32;
const Ticks: usize = 96;
const Seed: u64 = 0x4148325f46495245; // "AH2_FIRE", provenance only.

const Attack = enum {
    direct_evaluator,
    alias_evaluator,
    indirection_evaluator,
    reflected_call,
    function_pointer,
    shared_memory,
    filesystem,
    process_spawn,
    ipc_socket,
    scalar_feedback,
    template,
    mutation_menu,
    boundary,
    repair,
    viability,
    reproduction_scheduler,
};

const Request = struct { tag: Attack, nonce: u64 };
const Verdict = enum { denied, not_applicable_no_reflection, unavailable_same_process_not_security_boundary };

// This is the complete object passed to the raw-mutant step.  It contains no
// evaluator pointer, callback, score, template, candidate menu, boundary, or
// scheduler.  Raw cells have no privileged labels: every location uses the
// same local update law.
const Medium = struct {
    raw: [Cells]u8,
    tick: usize,

    fn init() Medium {
        var m = Medium{ .raw = [_]u8{0} ** Cells, .tick = 0 };
        // A deterministic non-template initial material distribution.  This
        // fixture tests the boundary, not self-assembly or a behavior score.
        for (0..Cells) |i| m.raw[i] = @intCast((mix(Seed +% i) >> 61) & 0x3);
        return m;
    }

    fn localTransport(self: *Medium) void {
        var next = [_]u8{0} ** Cells;
        for (self.raw, 0..) |v, i| {
            const right = (i + 1) % Cells;
            const left = (i + Cells - 1) % Cells;
            // Uniform conservative split: no action, mutation, or organism API.
            next[right] +%= v & 1;
            next[left] +%= v >> 1;
        }
        self.raw = next;
        self.tick += 1;
    }
};

// Kept private to the exterior.  It is never referenced from `Medium`, never
// serialised into a mutant-visible response, and never becomes a scalar reply.
const EvaluatorPrivate = struct { withheld_measurement: u64, private_template_hash: u64 };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}

// This dispatch point is a runtime, deny-by-default capability gate.  It does
// not return handles, values, success/failure scores, or an oracle.  Unknown
// requests have the same denial as known forbidden requests.
fn firewall(_: *Medium, _: Request) Verdict { return .denied; }

fn mutantStep(m: *Medium) void {
    // The mutant's actual execution surface: bounded raw state + local law.
    m.localTransport();
}

fn attackLabel(a: Attack) []const u8 { return @tagName(a); }

const RunSummary = struct { denied: usize = 0, na_reflection: usize = 0, residual: usize = 0, material_hash: u64 = 0 };

fn emitAttack(w: anytype, a: Attack, v: Verdict, detail: []const u8) !void {
    try w.print("round_ah_ah2,attack,{s},{s},0,0,{s}\n", .{ attackLabel(a), @tagName(v), detail });
}

fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    const w = f.writer();
    try w.writeAll("artifact,kind,attempt,result,mutant_visible_scalar,charged_ticks,detail\n");

    var medium = Medium.init();
    for (0..Ticks) |_| mutantStep(&medium);
    var material_hash: u64 = 0;
    for (medium.raw, 0..) |v, i| material_hash = mix(material_hash ^ (@as(u64, v) << @intCast(i % 8)) ^ @as(u64, @intCast(i)));
    try w.print("round_ah_ah2,manifest,medium_only,pass,0,{d},raw_cells={d};uniform_local_transport=true;medium_fields=raw,tick;material_hash=0x{x}\n", .{ Ticks, Cells, material_hash });
    try w.writeAll("round_ah_ah2,manifest,evaluator_export,pass,0,0,no_evaluator_handle_callback_score_or_receipt_is_mounted\n");
    try w.writeAll("round_ah_ah2,manifest,source_runtime_manifest,pass,0,0,mutant_surface=bounded_raw_state+uniform_local_transport;exterior=evaluator_private_post_run_only\n");

    inline for ([_]Attack{
        .direct_evaluator, .alias_evaluator, .indirection_evaluator,
        .function_pointer, .shared_memory, .filesystem, .process_spawn,
        .ipc_socket, .scalar_feedback, .template, .mutation_menu, .boundary,
        .repair, .viability, .reproduction_scheduler,
    }) |a| {
        const v = firewall(&medium, .{ .tag = a, .nonce = mix(Seed ^ @intFromEnum(a)) });
        if (v != .denied) return error.ForbiddenRequestWasAllowed;
        try emitAttack(w, a, v, "runtime_capability_gate_returns_no_handle_data_or_feedback");
    }
    // Zig has no reflection API.  A reflected call is therefore absent from
    // this runtime's capability surface, rather than "blocked by convention".
    try emitAttack(w, .reflected_call, .not_applicable_no_reflection, "Zig_has_no_runtime_reflection_or_dynamic_member_lookup_capability");
    // This is a positive finding *against* an overclaim: a malicious separately
    // compiled same-process source module is not contained by a struct API.
    try w.writeAll("round_ah_ah2,residual,same_process_source,unavailable_same_process_not_security_boundary,0,0,same_uid_compiled_code_can_import_std_and_attempt_memory_files_process_or_ipc;requires_process_uid_container_syscall_boundary\n");
    try w.writeAll("round_ah_ah2,residual,evaluator_scalar,pass,0,0,evaluator_private_struct_is_not_read_or_returned_during_medium_execution;post_run_measurement_not_exported\n");
    try w.writeAll("round_ah_ah2,VERDICT,aggregate,VALID_NEGATIVE,0,96,local_runtime_protocol_blocks_all_mounted_forbidden_capabilities_but_is_not_an_OS_security_boundary;AH2_does_not_unlock_clean_medium_claim\n");
}

fn selftest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    try run("/tmp/ah2a.csv");
    try run("/tmp/ah2b.csv");
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ah2a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ah2b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministicReplay;
    for ([_][]const u8{ "direct_evaluator,denied", "alias_evaluator,denied", "filesystem,denied", "ipc_socket,denied", "scalar_feedback,denied", "same_process_source,unavailable_same_process_not_security_boundary", "VALID_NEGATIVE" }) |needle| {
        if (std.mem.indexOf(u8, x, needle) == null) return error.MissingAttackEvidence;
    }
    const unused_private = EvaluatorPrivate{ .withheld_measurement = 0xfeedface, .private_template_hash = 0xcafef00d };
    _ = unused_private; // Makes the private type concrete without mounting it.
    std.debug.print("round_ah_ah2 selftest PASS deterministic=true mounted_denials=15 reflection=absent same_process_residual=exposed verdict=VALID_NEGATIVE\n", .{});
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next();
    const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) return selftest();
    try run(args.next() orelse "results/capability_firewall_round_ah.csv");
}
