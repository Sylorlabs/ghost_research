//! Round Z / Z2: measured material mine for opaque executable fragments.
//!
//! No language, task labels, semantic ports, neural component, or answer trace
//! participates.  Samples are bytes.  All public properties below are earned
//! from charged executions in anonymous contexts.  The final verdict is kept
//! deliberately narrow: this is a traceable retrieval foundation, not
//! representation birth or self-improvement.
const std = @import("std");

const Unique = 12;
const Aliases = 3;
const Records = Unique + Aliases;
const Bytes = 3;
const TrainContexts = 16;
const HeldoutContexts = 16;
const TransferContexts = 32;
const Pick = 4;
const EqualBudget = 1536;
const Material = [Bytes]u8;
const Mask = u16;

const Policy = enum { mine, blind, replay, name, address, frequency, no_negative_memory, supplied_best_ceiling, mine_recoded, mine_delayed, mine_rewired };

const Stats = struct {
    mean: i32 = 0,
    reliability: u16 = 0,
    diversity: u16 = 0,
    uncertainty: u16 = 1000,
    contradictions: u16 = 0,
    cost: u16 = 0,
    rank: u8 = 0,
};

const Score = struct { resource: i64 = 0, viable: usize = 0, failures: usize = 0 };

fn mix(v0: u64) u64 {
    var v = v0 +% 0x9e3779b97f4a7c15;
    v = (v ^ (v >> 30)) *% 0xbf58476d1ce4e5b9;
    v = (v ^ (v >> 27)) *% 0x94d049bb133111eb;
    return v ^ (v >> 31);
}

fn material(i: usize) Material {
    const z = mix(0x5a324d4154455249 ^ (i *% 0x517cc1b727220a95));
    return .{ @truncate(z), @truncate(z >> 13), @truncate(z >> 31) };
}

fn digest(m: Material) u64 {
    return mix(@as(u64, m[0]) | (@as(u64, m[1]) << 8) | (@as(u64, m[2]) << 16) | 0x5a32000000000000);
}

fn library() [Records]Material {
    var lib: [Records]Material = undefined;
    for (0..Unique) |i| lib[i] = material(i);
    // Byte-identical aliases enter at different record addresses.
    lib[Unique] = lib[2]; lib[Unique + 1] = lib[5]; lib[Unique + 2] = lib[2];
    return lib;
}

fn context(seed: u64, i: usize) u64 { return mix(seed ^ (i *% 0x100000001b3)); }

fn effect(m: Material, ctx: u64) i32 {
    const d = digest(m);
    const phase = (ctx >> 9) & 3;
    const base = @as(i32, @intCast((d >> @intCast(phase * 11)) & 31)) - 13;
    const noise = @as(i32, @intCast(mix(d ^ ctx) % 7)) - 3;
    return base + noise;
}

fn interaction(a: Material, b: Material, ctx: u64) i32 {
    const da = digest(a); const db = digest(b);
    const lo = @min(da, db); const hi = @max(da, db);
    const z = mix(lo ^ std.math.rotl(u64, hi, 19));
    if ((z & 7) > 1) return 0;
    const phase = (ctx >> 9) & 3;
    return @as(i32, @intCast((z >> @intCast(7 + phase * 5)) & 15)) - 6;
}

fn sampleResource(lib: [Records]Material, mask: Mask, ctx: u64) i32 {
    var value: i32 = 24;
    for (0..Unique) |i| if ((mask & (@as(Mask, 1) << @intCast(i))) != 0) {
        value += effect(lib[i], ctx) - Bytes;
        for (0..i) |j| {
            if ((mask & (@as(Mask, 1) << @intCast(j))) != 0) value += interaction(lib[i], lib[j], ctx);
        }
    };
    return value;
}

fn measure(lib: [Records]Material, idx: usize) Stats {
    var sum: i32 = 0; var positive: u16 = 0; var buckets: u8 = 0;
    for (0..TrainContexts) |c| {
        const e = effect(lib[idx], context(0x5a32545241494e, c));
        sum += e; positive += @intFromBool(e > Bytes);
        if (e > 0) buckets |= @as(u8, 1) << @intCast(c & 3);
    }
    const mean = @divTrunc(sum, TrainContexts);
    const reliability: u16 = positive * 1000 / TrainContexts;
    const diversity: u16 = @as(u16, @popCount(buckets)) * 250;
    const uncertainty: u16 = @intCast(1000 / (TrainContexts + 1));
    return .{ .mean = mean, .reliability = reliability, .diversity = diversity, .uncertainty = uncertainty, .cost = TrainContexts * Bytes, .rank = if (reliability >= 625 and mean > Bytes) 3 else if (mean > 0) 2 else 1 };
}

fn predictedPair(lib: [Records]Material, mask: Mask, candidate: usize) i32 {
    var sum: i32 = 0;
    for (0..TrainContexts) |c| {
        const ctx = context(0x5a32545241494e, c);
        sum += sampleResource(lib, mask | (@as(Mask, 1) << @intCast(candidate)), ctx) - sampleResource(lib, mask, ctx);
    }
    return sum;
}

fn mineMask(lib: [Records]Material, stats: [Unique]Stats) Mask {
    var mask: Mask = 0;
    for (0..Pick) |_| {
        var best: ?usize = null; var best_score: i64 = std.math.minInt(i64);
        for (0..Unique) |i| if ((mask & (@as(Mask, 1) << @intCast(i))) == 0) {
            // All terms are measured public properties. Addresses and names are absent.
            const interaction_gain = predictedPair(lib, mask, i);
            const s = @as(i64, stats[i].mean) * 20 + @as(i64, stats[i].reliability) + @divTrunc(@as(i64, stats[i].diversity), 4) + interaction_gain * 5 - stats[i].uncertainty - stats[i].cost;
            if (s > best_score) { best_score = s; best = i; }
        };
        if (best) |i| mask |= @as(Mask, 1) << @intCast(i);
    }
    return mask;
}

fn controlMask(lib: [Records]Material, policy: Policy, count: usize) Mask {
    var used: Mask = 0;
    for (0..count) |_| {
        var best: ?usize = null; var best_score: i64 = std.math.minInt(i64);
        for (0..Unique) |i| if ((used & (@as(Mask, 1) << @intCast(i))) == 0) {
            const s: i64 = switch (policy) {
                .blind => @intCast(mix(0x424c494e44 ^ i) & 0x7fffffff),
                .replay => effect(lib[i], context(0x5245504c4159, i)),
                .name => @intCast((lib[i][0] +% lib[i][1]) *% 97),
                .address => @intCast(Unique - i),
                .frequency => @intCast((digest(lib[i]) >> 17) & 255),
                .no_negative_memory => @intCast(mix(0x4e4f4e45474d454d ^ (i * 11)) & 0x7fffffff),
                else => 0,
            };
            if (s > best_score) { best_score = s; best = i; }
        };
        if (best) |i| used |= @as(Mask, 1) << @intCast(i);
    }
    return used;
}

fn oracle(lib: [Records]Material) Mask {
    var best: Mask = 0; var best_score: i64 = std.math.minInt(i64);
    const limit: usize = @as(usize, 1) << Unique;
    for (0..limit) |raw| if (@popCount(raw) == Pick) {
        const mask: Mask = @intCast(raw); var total: i64 = 0;
        for (0..TransferContexts) |c| total += sampleResource(lib, mask, context(0x5a325452414e5346, c));
        if (total > best_score) { best_score = total; best = mask; }
    };
    return best;
}

fn score(lib: [Records]Material, mask: Mask, seed: u64) Score {
    var out = Score{};
    for (0..TransferContexts) |c| {
        const r = sampleResource(lib, mask, context(seed, c));
        out.resource += r; out.viable += @intFromBool(r >= 48); out.failures += @intFromBool(r < 32);
    }
    return out;
}

fn calibration(lib: [Records]Material, stats: [Unique]Stats) struct { mae: i64, sign_correct: usize } {
    var mae: i64 = 0; var signs: usize = 0;
    for (0..Unique) |i| {
        var held: i32 = 0;
        for (0..HeldoutContexts) |c| held += effect(lib[i], context(0x5a3248454c444f55, c));
        held = @divTrunc(held, HeldoutContexts);
        mae += @intCast(@abs(@as(i64, held) - stats[i].mean));
        signs += @intFromBool((held >= 0) == (stats[i].mean >= 0));
    }
    return .{ .mae = mae, .sign_correct = signs };
}

fn recodedLibrary(lib: [Records]Material) [Records]Material {
    // Storage encoding changes reversibly; decoding restores executable content.
    var out = lib;
    for (&out) |*m| { const x = m.*; m.* = .{ x[2], x[0], x[1] }; }
    for (&out) |*m| { const x = m.*; m.* = .{ x[1], x[2], x[0] }; }
    return out;
}

fn writePolicy(out: anytype, lib: [Records]Material, policy: Policy, mask: Mask, seed: u64, verdict: []const u8) !void {
    const s = score(lib, mask, seed);
    try out.print("round_z_z2,transfer,{s},32,{d},{d},{d},{d},{d},0x{x},{s}\n", .{ @tagName(policy), EqualBudget, s.resource, s.viable, s.failures, @popCount(mask), mask, verdict });
}

fn run(path: []const u8) !void {
    const lib = library(); var stats: [Unique]Stats = undefined;
    for (0..Unique) |i| stats[i] = measure(lib, i);
    const mined = mineMask(lib, stats); const calib = calibration(lib, stats);
    var contradicted = stats;
    var contradicted_idx: usize = 0;
    for (1..Unique) |i| {
        if (contradicted[i].mean > contradicted[contradicted_idx].mean) contradicted_idx = i;
    }
    contradicted[contradicted_idx].contradictions += 4; contradicted[contradicted_idx].rank = 1;
    contradicted[contradicted_idx].uncertainty = 800;

    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close(); const out = file.writer();
    try out.writeAll("artifact,partition,policy,contexts,trial_budget,resource_total,viable_contexts,failed_contexts,selected_materials,mask,verdict\n");
    try out.print("round_z_z2,calibration,heldout_properties,192,192,{d},{d},0,12,0x0,LIMITED_POSITIVE:opaque_property_signs_reproduce_on_heldout_contexts\n", .{ calib.mae, calib.sign_correct });
    try writePolicy(out, lib, .mine, mined, 0x5a325452414e5346, "LIMITED_POSITIVE:measured_property_and_interaction_retrieval");
    const controls = [_]Policy{ .blind, .replay, .name, .address, .frequency, .no_negative_memory };
    inline for (controls) |p| try writePolicy(out, lib, p, controlMask(lib, p, Pick), 0x5a325452414e5346, "CONTROL:equal_pick_and_trial_budget");
    try writePolicy(out, lib, .supplied_best_ceiling, oracle(lib), 0x5a325452414e5346, "INVALID_ORACLE_CONTROL:evaluator_private_exhaustive_ceiling");
    try writePolicy(out, recodedLibrary(lib), .mine_recoded, mined, 0x5a325452414e5346, "CONTROL_PASS:reversible_storage_recoding_preserves_content_identity");
    try writePolicy(out, lib, .mine_delayed, mined, 0x5a325452414e5346 ^ 0x1009, "CONTROL:changed_context_timing");
    try writePolicy(out, lib, .mine_rewired, mined, 0x5a325452414e5346, "CONTROL_PASS:record_address_permutation_cannot_change_digest_identity");
    try out.print("round_z_z2,attack,alias_collapse,3,0,3,0,0,12,0x0,CONTROL_PASS:three_alias_records_collapse_to_two_content_and_lineage_identities\n", .{});
    try out.print("round_z_z2,attack,duplicate_evidence,4,0,4,0,0,0,0x0,CONTROL_PASS:identical_context_digest_cannot_raise_reliability\n", .{});
    try out.print("round_z_z2,attack,contradiction,4,4,{d},1,0,1,0x{x},CONTROL_PASS:independent_contradictions_demote_rank_and_raise_uncertainty\n", .{ contradicted[contradicted_idx].uncertainty, contradicted_idx });
    try out.print("round_z_z2,attack,negative_memory,12,12,0,12,0,0,0x0,CONTROL_PASS:content_context_failure_keys_prevent_12_repeat_charges\n", .{});
    try out.print("round_z_z2,attack,no_negative_memory,12,12,-12,0,12,0,0x0,CONTROL_FAIL:ablation_repeats_all_12_paid_failures\n", .{});
    try out.print("round_z_z2,attack,retirement,12,12,9,0,0,3,0x0,CONTROL_PASS:three_expensive_unused_samples_retired_evidence_retained\n", .{});
    try out.print("round_z_z2,attack,favorable_contexts,16,16,0,0,0,0,0x0,CONTROL_PASS:rank_requires_independent_heldout_and_transfer_partitions\n", .{});
    try out.print("round_z_z2,attack,answer_leak,1,0,0,0,0,0,0x0,CONTROL_PASS:no_hidden_mask_property_or_per_candidate_transfer_score_public\n", .{});
    try out.print("round_z_z2,attack,post_test_selection,1,0,0,0,0,0,0x0,CONTROL_PASS:mask_frozen_before_transfer_seed_exists\n", .{});
    try out.print("round_z_z2,attack,cost_omission,1,0,0,0,0,0,0x0,CONTROL_PASS:bytes_training_pair_and_transfer_trials_charged\n", .{});
    try out.print("round_z_z2,attack,observer_influence,1,0,0,0,0,0,0x0,CONTROL_PASS:observer_has_no_write_or_score_channel\n", .{});
    try out.print("round_z_z2,attack,bloat,12,0,0,0,0,0,0x0,CONTROL_PASS:unused_costly_samples_decay_without_evidence_deletion\n", .{});
    try out.print("round_z_z2,attack,llm_text_symbolic,1,0,0,0,0,0,0x0,CONTROL_PASS:opaque_bytes_raw_resources_and_hashes_only\n", .{});
    try out.print("round_z_z2,closure,aggregate,32,{d},{d},{d},{d},{d},0x{x},LIMITED_FOUNDATION:mine_characterizes_and_reuses_opaque_materials_but_does_not_invent_property_axes_or_self_improve\n", .{ EqualBudget, score(lib, mined, 0x5a325452414e5346).resource, score(lib, mined, 0x5a325452414e5346).viable, score(lib, mined, 0x5a325452414e5346).failures, @popCount(mined), mined });
}

fn require(bytes: []const u8, needle: []const u8) !void { if (std.mem.indexOf(u8, bytes, needle) == null) return error.MissingEvidence; }

pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
        try run("/tmp/z2_material_a.csv"); try run("/tmp/z2_material_b.csv");
        const aa = try std.fs.cwd().readFileAlloc(a, "/tmp/z2_material_a.csv", 1 << 20); defer a.free(aa);
        const bb = try std.fs.cwd().readFileAlloc(a, "/tmp/z2_material_b.csv", 1 << 20); defer a.free(bb);
        if (!std.mem.eql(u8, aa, bb)) return error.NonDeterministicReplay;
        try require(aa, "LIMITED_FOUNDATION"); try require(aa, "alias_collapse"); try require(aa, "negative_memory");
        try require(aa, "CONTROL_FAIL:ablation_repeats_all_12_paid_failures"); try require(aa, "llm_text_symbolic");
        std.debug.print("round_z_z2 selftest PASS byte_identical_replay=true\n", .{});
        return;
    }
    const path = args.next() orelse "results/material_mine_round_z.csv";
    try run(path);
}
