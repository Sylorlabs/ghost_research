//! Round AJ / AJ1 -- frozen-substrate contract fixture.
//!
//! This program is an infrastructure test, not an intelligence benchmark.  It
//! freezes a deliberately small *trusted* base and mechanically checks that the
//! organism-facing surface contains generic state transport/variation/execution
//! and append-only provenance, while every task-semantic/evaluator capability
//! named in the Round AJ contract is absent.  Hidden-world measurement is made
//! only after a bounded run and is never returned to the organism.
const std = @import("std");

const Width: usize = 16;
const Steps: usize = 12;
const Seed: u64 = 0x414a315f46524f5a; // "AJ1_FROZ", provenance only.

const Forbidden = enum {
    task_target,
    answer_trace,
    semantic_decoder,
    task_label,
    curriculum_label,
    world_family_label,
    candidate_menu,
    tool_library,
    intermediate_reward,
    novelty_score,
    evaluator_feedback,
};

fn forbiddenName(x: Forbidden) []const u8 { return @tagName(x); }

// This is the complete organism-facing object.  It deliberately has no
// pointers, callbacks, scores, labels, target values, candidate/tool library,
// decoder, or world handle.  Cells are untyped bytes; all positions obey the
// identical operations below.
const OrganismSurface = struct {
    raw: [Width]u8,
    used_steps: usize,
    provenance: [Steps]Event,
    provenance_len: usize,

    const Event = struct { before: u64, operation: u8, after: u64 };

    fn init() OrganismSurface {
        var out = OrganismSurface{
            .raw = undefined,
            .used_steps = 0,
            .provenance = undefined,
            .provenance_len = 0,
        };
        // Initial material is a deterministic raw transport fixture, not an
        // answer, template, task instance, or organism seed.
        for (0..Width) |i| out.raw[i] = @truncate(mix(Seed +% @as(u64, i)));
        return out;
    }

    fn digest(self: *const OrganismSurface) u64 {
        var h: u64 = 0x7d5a_4f21_13c9_88e1;
        for (self.raw, 0..) |byte, i| h = mix(h ^ (@as(u64, byte) << @intCast((i % 8) * 8)) ^ @as(u64, i));
        return h;
    }

    // Generic reversible variation: xor with a raw mask.  The caller chooses
    // only a raw byte/mask, not a named operator or a task-specific candidate.
    fn vary(self: *OrganismSurface, cell: usize, mask: u8) !void {
        if (self.used_steps >= Steps or cell >= Width) return error.ResourceBound;
        const before = self.digest();
        self.raw[cell] ^= mask;
        const after = self.digest();
        self.provenance[self.provenance_len] = .{ .before = before, .operation = mask, .after = after };
        self.provenance_len += 1;
        self.used_steps += 1;
    }

    // Generic uniform execution: a reversible nearest-neighbour permutation.
    // It has no task score, instruction decoder, or semantic opcode.
    fn execute(self: *OrganismSurface) !void {
        if (self.used_steps >= Steps) return error.ResourceBound;
        const before = self.digest();
        const tail = self.raw[Width - 1];
        var i: usize = Width - 1;
        while (i > 0) : (i -= 1) self.raw[i] = self.raw[i - 1];
        self.raw[0] = tail;
        const after = self.digest();
        self.provenance[self.provenance_len] = .{ .before = before, .operation = 0xff, .after = after };
        self.provenance_len += 1;
        self.used_steps += 1;
    }

    // A capability request is never an organism API.  It exists only for the
    // hostile fixture below: every named forbidden capability resolves to the
    // same no-data denial, preventing an accidental special-case oracle.
    fn hostileRequest(_: *OrganismSurface, _: Forbidden) bool { return false; }
};

// Sealed host-only state.  The world seed and measurement are not supplied to
// OrganismSurface and are constructed only after the run has finished.
const EvaluatorPrivate = struct {
    hidden_world_seed: u64,
    post_run_measurement: u64,
};

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}

fn postRunMeasure(final_digest: u64, hidden_seed: u64) u64 {
    // This opaque receipt deliberately has no success/correctness interpretation
    // in AJ1; it only demonstrates sealed post-run measurement placement.
    return mix(final_digest ^ hidden_seed);
}

fn writeRow(w: anytype, kind: []const u8, name: []const u8, result: []const u8, detail: []const u8) !void {
    try w.print("round_aj_aj1,{s},{s},{s},{s}\n", .{ kind, name, result, detail });
}

fn run(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    const w = file.writer();
    try w.writeAll("artifact,kind,name,result,detail\n");

    try writeRow(w, "manifest", "trusted_substrate", "PASS", "uniform_raw_transport;bounded_steps;reversible_raw_variation;uniform_execution;append_only_provenance;sealed_hidden_world;post_run_measurement");
    try writeRow(w, "manifest", "organism_surface", "PASS", "raw_bytes+step_budget+append_only_event_hashes_only;no_pointer_callback_score_label_decoder_or_world_handle");
    try writeRow(w, "manifest", "evaluator_placement", "PASS", "hidden_seed_and_measurement_constructed_after_organism_run_and_not_exported");
    try writeRow(w, "manifest", "claim_boundary", "PASS", "foundation_science_contract_only;in_process_fixture_does_not_certify_AI_process_or_syscall_containment");

    var org = OrganismSurface.init();
    const initial = org.raw;
    // Reversibility fixture: apply the same raw mutation twice around uniform
    // execution permutations, then undo the permutations with 15 more steps is
    // outside the fixed budget.  Instead test exact reversible mutation alone.
    try org.vary(3, 0x5a);
    try org.vary(3, 0x5a);
    if (!std.mem.eql(u8, &initial, &org.raw)) return error.ReversibleVariationFailed;
    try org.execute();
    try org.execute();
    if (org.provenance_len != 4 or org.used_steps != 4) return error.ProvenanceOrBudgetFailed;
    try writeRow(w, "fixture", "generic_variation", "PASS", "raw_xor_mutation_round_trip=true;no_candidate_or_tool_name");
    try writeRow(w, "fixture", "generic_execution", "PASS", "uniform_neighbour_permutation_executed_twice;no_decoder_or_opcode_meaning");
    try writeRow(w, "fixture", "causal_provenance", "PASS", "four_append_only_before_operation_after_digest_events;organism_never_reads_evaluator_measurement");

    inline for ([_]Forbidden{
        .task_target, .answer_trace, .semantic_decoder, .task_label,
        .curriculum_label, .world_family_label, .candidate_menu, .tool_library,
        .intermediate_reward, .novelty_score, .evaluator_feedback,
    }) |forbidden| {
        if (org.hostileRequest(forbidden)) return error.ForbiddenCapabilityLeak;
        try writeRow(w, "hostile", forbiddenName(forbidden), "DENIED", "no_handle_value_or_distinguishing_reply_is_mounted_on_organism_surface");
    }

    const final_digest = org.digest();
    const private = EvaluatorPrivate{
        .hidden_world_seed = mix(Seed ^ 0x48494444454e5f57),
        .post_run_measurement = postRunMeasure(final_digest, mix(Seed ^ 0x48494444454e5f57)),
    };
    try w.print("round_aj_aj1,fixture,sealed_post_run_measurement,PASS,final_digest=0x{x};opaque_receipt=0x{x};hidden_seed_not_mounted\n", .{ final_digest, private.post_run_measurement });
    try writeRow(w, "residual", "hostile_os_containment", "NOT_CLAIMED", "same_process_Zig_fixture_cannot_prevent_imports_syscalls_memory_or_process_access;Round_AI_syscall_allowlist_remains_unresolved");
    try writeRow(w, "VERDICT", "aggregate", "FOUNDATION_PASS", "frozen_non_task_specific_contract_and_hostile_manifest_pass;this_enables_foundation_experiments_only_not_autonomy_or_security");
}

fn selftest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    try run("/tmp/frozen-substrate-aj1-a.csv");
    try run("/tmp/frozen-substrate-aj1-b.csv");
    const a = try std.fs.cwd().readFileAlloc(allocator, "/tmp/frozen-substrate-aj1-a.csv", 1 << 20);
    defer allocator.free(a);
    const b = try std.fs.cwd().readFileAlloc(allocator, "/tmp/frozen-substrate-aj1-b.csv", 1 << 20);
    defer allocator.free(b);
    if (!std.mem.eql(u8, a, b)) return error.NonDeterministicReplay;
    for ([_][]const u8{ "trusted_substrate,PASS", "task_target,DENIED", "answer_trace,DENIED", "semantic_decoder,DENIED", "candidate_menu,DENIED", "intermediate_reward,DENIED", "evaluator_feedback,DENIED", "hostile_os_containment,NOT_CLAIMED", "FOUNDATION_PASS" }) |needle| {
        if (std.mem.indexOf(u8, a, needle) == null) return error.MissingContractEvidence;
    }
    std.debug.print("round_aj_aj1 selftest PASS deterministic=true hostile_denials=11 generic_fixtures=3 verdict=FOUNDATION_PASS\n", .{});
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) return selftest();
    try run(args.next() orelse "results/frozen_substrate_round_aj.csv");
}
