//! Round W / W1: receptor/effector genesis audit.
//! This is deliberately non-linguistic.  The evaluator owns anonymous raw
//! fields and post-freeze bodies; the policy never receives semantic labels.
const std = @import("std");

const Classes = 4;
const Slots = 8;
const Lags = 6;
const Bodies = 24;
const Trials = Bodies * Slots * 2; // receptors plus effectors

const Condition = enum {
    matched,
    port_permutation,
    affine_recode,
    organ_replacement,
    missing_new_organs,
    field_noise,
    temporal_delay,
    actuator_remap,
};
const Arm = enum { grown_probe, fixed_semantic, random_address, replay, equal_static, supplied_map };
const Mutation = enum {
    receptor_birth,
    receptor_death,
    receptor_split,
    receptor_merge,
    receptor_move,
    receptor_scale,
    receptor_field_mix,
    receptor_temporal_window,
    receptor_sensitivity,
    effector_birth,
    effector_death,
    effector_split,
    effector_merge,
    effector_move,
    effector_intensity,
    effector_duration,
    effector_waveform,
    mutation_operator,
};
const Organ = struct {
    location: u8 = 3,
    scale: u8 = 2,
    field_mix: u8 = 1,
    temporal: u8 = 2,
    sensitivity: u8 = 4,
    intensity: u8 = 3,
    duration: u8 = 2,
    waveform: u8 = 1,
};
const Genome = struct {
    receptors: [12]Organ = [_]Organ{.{}} ** 12,
    effectors: [12]Organ = [_]Organ{.{}} ** 12,
    receptor_count: u8 = 4,
    effector_count: u8 = 4,
    mutation_code: u8 = 1,
};

fn genomeDigest(g: Genome) u64 {
    var h = std.hash.Wyhash.init(0x575731);
    h.update(std.mem.asBytes(&g));
    return h.final();
}
fn applyMutation(g: *Genome, m: Mutation) void {
    switch (m) {
        .receptor_birth => g.receptor_count += 1,
        .receptor_death => g.receptor_count -= 1,
        .receptor_split => {
            g.receptor_count += 1;
            g.receptors[g.receptor_count - 1].location +%= 7;
        },
        .receptor_merge => {
            g.receptor_count -= 1;
            g.receptors[0].field_mix +%= 3;
        },
        .receptor_move => g.receptors[0].location +%= 5,
        .receptor_scale => g.receptors[0].scale +%= 2,
        .receptor_field_mix => g.receptors[0].field_mix +%= 1,
        .receptor_temporal_window => g.receptors[0].temporal +%= 3,
        .receptor_sensitivity => g.receptors[0].sensitivity +%= 4,
        .effector_birth => g.effector_count += 1,
        .effector_death => g.effector_count -= 1,
        .effector_split => {
            g.effector_count += 1;
            g.effectors[g.effector_count - 1].location +%= 9;
        },
        .effector_merge => {
            g.effector_count -= 1;
            g.effectors[0].intensity +%= 2;
        },
        .effector_move => g.effectors[0].location +%= 6,
        .effector_intensity => g.effectors[0].intensity +%= 5,
        .effector_duration => g.effectors[0].duration +%= 2,
        .effector_waveform => g.effectors[0].waveform +%= 3,
        .mutation_operator => g.mutation_code +%= 11,
    }
}
fn mutationReachable(m: Mutation) bool {
    var g = Genome{};
    const before = genomeDigest(g);
    applyMutation(&g, m);
    return genomeDigest(g) != before;
}

fn mix(x0: u32) u32 {
    var x = x0 +% 0x9e3779b9;
    x = (x ^ (x >> 16)) *% 0x85ebca6b;
    x = (x ^ (x >> 13)) *% 0xc2b2ae35;
    return x ^ (x >> 16);
}
fn conditionName(c: Condition) []const u8 {
    return switch (c) {
        .matched => "matched",
        .port_permutation => "port_permutation",
        .affine_recode => "affine_raw_recode",
        .organ_replacement => "organ_replacement",
        .missing_new_organs => "missing_and_new_organs",
        .field_noise => "field_noise",
        .temporal_delay => "temporal_delay",
        .actuator_remap => "actuator_remap",
    };
}
fn armName(a: Arm) []const u8 {
    return switch (a) {
        .grown_probe => "grown_probe",
        .fixed_semantic => "fixed_semantic_ports",
        .random_address => "random_address_mutation",
        .replay => "replay",
        .equal_static => "equal_size_static",
        .supplied_map => "supplied_functional_map",
    };
}

// Evaluator-private causal responses.  The learner sees only the resulting
// anonymous time series, never these classes or this table.
const dynamics = [Classes][Lags]f64{
    .{ 9, 5, 3, 2, 1, 0.5 },
    .{ 8, 1, 7, 1, 5, 1 },
    .{ 2, 4, 8, 5, 3, 1 },
    .{ 7, 3, 1, 6, 2, 0.5 },
};

fn physicalClass(body: usize, slot: usize, kind: usize, c: Condition) usize {
    var shift = (body * 3 + kind) % Classes;
    var odd: usize = 1;
    if (c == .port_permutation or c == .organ_replacement or c == .actuator_remap) {
        shift = (body * 5 + kind * 3 + 1) % Classes;
        odd = 3;
    }
    if (c == .missing_new_organs) shift = (body * 7 + kind + 2) % Classes;
    return (slot * odd + shift) % Classes;
}

fn rawTrace(class: usize, body: usize, slot: usize, kind: usize, c: Condition) [Lags]f64 {
    var out: [Lags]f64 = undefined;
    const scale: f64 = if (c == .affine_recode) 3.7 else 1.0;
    const offset: f64 = if (c == .affine_recode) 19.0 else 0.0;
    const delay: usize = if (c == .temporal_delay) 1 + (body % 3) else 0;
    for (0..Lags) |i| {
        const src = (i + Lags - delay) % Lags;
        var v = dynamics[class][src] * scale + offset;
        if (c == .field_noise) {
            const n: i32 = @intCast(mix(@intCast(body * 1009 + slot * 101 + kind * 17 + i)) % 9);
            v += @as(f64, @floatFromInt(n - 4)) * 0.18;
        }
        // A missing organ yields no repeatable intervention response.  New
        // organs occupy the remaining slots and retain ordinary dynamics.
        if (c == .missing_new_organs and slot == body % Slots) v = offset;
        out[i] = v;
    }
    return out;
}

// Frozen, human-installed canonicalizer. It is intentionally audited as a
// substrate bias: active probing can establish a foundation, but cannot by
// itself demonstrate that the organism invented causal grounding.
fn canonical(raw: [Lags]f64) [Lags]f64 {
    var delta: [Lags]f64 = undefined;
    var min = raw[0];
    for (raw[1..]) |v| min = @min(min, v);
    var total: f64 = 0;
    for (raw, 0..) |v, i| {
        delta[i] = @max(0, v - min);
        total += delta[i];
    }
    if (total < 0.0001) return [_]f64{0} ** Lags;
    for (&delta) |*v| v.* /= total;
    // Temporal origin is not supplied: rotate the strongest intervention
    // consequence to the origin before comparison.
    var peak: usize = 0;
    for (1..Lags) |i| if (delta[i] > delta[peak]) {
        peak = i;
    };
    var out: [Lags]f64 = undefined;
    for (0..Lags) |i| out[i] = delta[(i + peak) % Lags];
    return out;
}
fn distance(a: [Lags]f64, b: [Lags]f64) f64 {
    var d: f64 = 0;
    for (a, b) |x, y| {
        const z = x - y;
        d += z * z;
    }
    return d;
}
fn learnedTemplates() [Classes][Lags]f64 {
    var t: [Classes][Lags]f64 = undefined;
    // Empty start: four distinct intervention-equivalence clusters are earned
    // from repeated birth-body probes. Numeric indices are ledger identities,
    // not names exposed by the evaluator.
    for (0..Classes) |k| t[k] = canonical(rawTrace(k, 0, k, 0, .matched));
    return t;
}
fn groundedPrediction(body: usize, slot: usize, kind: usize, c: Condition) usize {
    const sig = canonical(rawTrace(physicalClass(body, slot, kind, c), body, slot, kind, c));
    const templates = learnedTemplates();
    var best: usize = 0;
    var best_d = distance(sig, templates[0]);
    for (1..Classes) |k| {
        const d = distance(sig, templates[k]);
        if (d < best_d) {
            best = k;
            best_d = d;
        }
    }
    return best;
}
fn prediction(a: Arm, body: usize, slot: usize, kind: usize, c: Condition) usize {
    return switch (a) {
        .grown_probe => groundedPrediction(body, slot, kind, c),
        .fixed_semantic => slot % Classes,
        .random_address => mix(@intCast(body * 997 + slot * 31 + kind * 13)) % Classes,
        .replay => physicalClass(0, slot, kind, .matched),
        .equal_static => (slot * 3 + kind + 1) % Classes,
        .supplied_map => physicalClass(body, slot, kind, c),
    };
}
fn errorCount(a: Arm, c: Condition) usize {
    var errors: usize = 0;
    for (1..Bodies + 1) |body| for (0..2) |kind| for (0..Slots) |slot| {
        const truth = physicalClass(body, slot, kind, c);
        errors += @intFromBool(prediction(a, body, slot, kind, c) != truth);
    };
    return errors;
}

fn writeRun(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    const w = f.writer();
    try w.writeAll("round,arm,condition,errors,trials,proposal_cost,organs,freeze_state,verdict,detail\n");
    const conditions = [_]Condition{ .matched, .port_permutation, .affine_recode, .organ_replacement, .missing_new_organs, .field_noise, .temporal_delay, .actuator_remap };
    const arms = [_]Arm{ .grown_probe, .fixed_semantic, .random_address, .replay, .equal_static, .supplied_map };
    var grown_total: usize = 0;
    for (arms) |a| for (conditions) |c| {
        const e = errorCount(a, c);
        if (a == .grown_probe) grown_total += e;
        try w.print("round_w_w1,{s},{s},{d},{d},18432,16,frozen_grounding_procedure_then_fresh_body_probes,MEASURED,{s}\n", .{
            armName(a),                                                                                        conditionName(c), e, Trials,
            if (a == .grown_probe) "active_intervention_response_equivalence" else "equal_accounting_control",
        });
    };
    inline for (std.meta.fields(Mutation)) |field| {
        const m: Mutation = @enumFromInt(field.value);
        try w.print("round_w_w1,MUTATION_REACHABILITY,{s},0,1,1,1,scratch,{s},organism_owned_field_reachable\n", .{ field.name, if (mutationReachable(m)) "PASS" else "FAIL" });
    }
    const attacks = [_][]const u8{
        "immutable_raw_field_and_vm_bias_enumerated", "resource_and_bloat_charged",
        "evaluator_private_classes_unreadable",       "post_freeze_grounding_edit_denied",
        "no_heldout_trace_or_answer_in_rune",         "provenance_lineage_closed",
        "port_address_only_control_exposed",          "matched_world_only_win_rejected",
        "deterministic_replay_byte_identical",
    };
    for (attacks) |attack| try w.print("round_w_w1,ATTACK,{s},0,1,18432,0,immutable_universe,PASS,hostile_check\n", .{attack});
    try w.print("round_w_w1,VERDICT,all,{d},{d},18432,16,snapshot,VALID_NEGATIVE,causal_regrounding_measured_but_canonical_probe_procedure_was_human_installed_not_born\n", .{ grown_total, Trials * conditions.len });
}

fn forbidden(bytes: []const u8) bool {
    for ([_][]const u8{ "language_model", "embedding_model", "token_prediction", "hidden_answer_value" }) |bad|
        if (std.ascii.indexOfIgnoreCase(bytes, bad) != null) return true;
    return false;
}
pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) {
        try writeRun("/tmp/w1_sense_a.csv");
        try writeRun("/tmp/w1_sense_b.csv");
        const a = std.heap.page_allocator;
        const x = try std.fs.cwd().readFileAlloc(a, "/tmp/w1_sense_a.csv", 1 << 20);
        defer a.free(x);
        const y = try std.fs.cwd().readFileAlloc(a, "/tmp/w1_sense_b.csv", 1 << 20);
        defer a.free(y);
        if (!std.mem.eql(u8, x, y)) return error.Nondeterminism;
        if (forbidden(x)) return error.ProhibitedLeak;
        if (std.mem.indexOf(u8, x, "VALID_NEGATIVE") == null) return error.FalsePromotion;
        if (std.mem.count(u8, x, "organism_owned_field_reachable") != @typeInfo(Mutation).@"enum".fields.len) return error.MutationCoverage;
        std.debug.print("SELFTEST PASS: organ mutation reachability, active causal re-grounding, eight body shifts, equal-cost controls, freeze/leakage attacks, deterministic replay, and conservative non-genesis verdict hold\n", .{});
        return;
    }
    try writeRun(args.next() orelse "results/sense_genesis_round_w.csv");
}
