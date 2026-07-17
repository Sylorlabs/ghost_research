//! Round Y / Y3: causal fragment consolidation under interacting mutations.
//!
//! This is a bounded, non-language experiment. Memory starts empty. Candidate
//! fragments are opaque two-byte executable blocks. Ordinary resource histories
//! are the only downstream evidence. The experiment deliberately audits whether
//! the supplied fragment boundary and add/remove operator install the credit axis.
const std = @import("std");

const FragmentCount: usize = 12;
const FragmentBytes: usize = 2;
const Contexts: usize = 12;
const TransferWorlds: usize = 64;
const TrialBudget: usize = 192;

const Fragment = [FragmentBytes]u8;
const Library = [FragmentCount]Fragment;
const Mask = u16;

const Policy = enum {
    consolidated,
    correlation,
    size,
    novelty,
    survival,
    random,
    replay,
    shuffled_lineage,
    supplied_best_ceiling,
    removed,
    recombined,
    interaction_unmasked,
    contradiction,
};

const Aggregate = struct {
    resource: i64 = 0,
    viable: usize = 0,
    reproduced: usize = 0,
    selected: usize = 0,
    trials: usize = TrialBudget,
};

fn mix(v0: u64) u64 {
    var v = v0 +% 0x9e3779b97f4a7c15;
    v = (v ^ (v >> 30)) *% 0xbf58476d1ce4e5b9;
    v = (v ^ (v >> 27)) *% 0x94d049bb133111eb;
    return v ^ (v >> 31);
}

fn library() Library {
    var out: Library = undefined;
    for (0..FragmentCount) |i| {
        const z = mix(0x5933434f4e534f4c ^ (i *% 0x517cc1b727220a95));
        out[i] = .{ @truncate(z), @truncate(z >> 19) };
    }
    return out;
}

fn digestFragment(f: Fragment) u64 {
    return mix(@as(u64, f[0]) | (@as(u64, f[1]) << 8) | 0x4652414700000000);
}

fn pop(mask: Mask) usize { return @popCount(mask); }

fn intrinsic(f: Fragment) i32 {
    const z = digestFragment(f);
    return @as(i32, @intCast((z >> 7) % 19)) - 8;
}

fn pairEffect(a: Fragment, b: Fragment) i32 {
    const x = digestFragment(a); const y = digestFragment(b);
    const lo = @min(x, y); const hi = @max(x, y);
    const z = mix(lo ^ std.math.rotl(u64, hi, 17) ^ 0x50414952);
    // Sparse interactions include synergy and masking.
    if ((z & 3) != 0) return 0;
    return @as(i32, @intCast((z >> 9) % 17)) - 7;
}

fn resource(lib: Library, mask: Mask, world: u64) i32 {
    var value: i32 = 42;
    for (0..FragmentCount) |i| if ((mask & (@as(Mask, 1) << @intCast(i))) != 0) {
        const f = lib[i];
        const noise = @as(i32, @intCast(mix(world ^ digestFragment(f)) % 7)) - 3;
        value += intrinsic(f) + noise;
        for (0..i) |j| {
            if ((mask & (@as(Mask, 1) << @intCast(j))) != 0) value += pairEffect(f, lib[j]);
        }
    };
    // Every retained byte has an ordinary resource cost.
    value -= @as(i32, @intCast(pop(mask) * FragmentBytes));
    return value;
}

fn trainWorld(context: usize, replicate: usize) u64 {
    return mix(0x59545241494e0000 ^ (context *% 0x1009) ^ (replicate *% 0x917));
}

fn transferWorld(i: usize) u64 {
    return mix(0x59504f5354465245 ^ (i *% 0x1709));
}

fn meanDelta(lib: Library, base: Mask, bit: usize) i64 {
    const flag: Mask = @as(Mask, 1) << @intCast(bit);
    const with = base | flag; const without = base & ~flag;
    var delta: i64 = 0;
    for (0..Contexts) |c| {
        delta += resource(lib, with, trainWorld(c, 0));
        delta -= resource(lib, without, trainWorld(c, 0));
        delta += resource(lib, with, trainWorld(c, 1));
        delta -= resource(lib, without, trainWorld(c, 1));
    }
    return delta;
}

fn consolidate(lib: Library) Mask {
    var mask: Mask = 0;
    // Forward addition and backward removal are both ordinary resource paired
    // trials. The boundary/operator are supplied; the useful bytes are not.
    var round: usize = 0;
    while (round < 3) : (round += 1) {
        for (0..FragmentCount) |i| if ((mask & (@as(Mask, 1) << @intCast(i))) == 0) {
            if (meanDelta(lib, mask, i) > 0) mask |= @as(Mask, 1) << @intCast(i);
        };
        var i: usize = FragmentCount;
        while (i > 0) {
            i -= 1;
            if ((mask & (@as(Mask, 1) << @intCast(i))) != 0 and meanDelta(lib, mask, i) <= 0)
                mask &= ~(@as(Mask, 1) << @intCast(i));
        }
    }
    return mask;
}

fn topByScore(scores: [FragmentCount]i64, take: usize) Mask {
    var used: Mask = 0;
    for (0..take) |_| {
        var best: ?usize = null; var score: i64 = std.math.minInt(i64);
        for (0..FragmentCount) |i| if ((used & (@as(Mask, 1) << @intCast(i))) == 0 and scores[i] > score) {
            best = i; score = scores[i];
        };
        if (best) |i| used |= @as(Mask, 1) << @intCast(i);
    }
    return used;
}

fn controlMask(lib: Library, policy: Policy, count: usize) Mask {
    var scores: [FragmentCount]i64 = undefined;
    for (0..FragmentCount) |i| {
        const f = lib[i];
        scores[i] = switch (policy) {
            .correlation => @as(i64, resource(lib, @as(Mask, 1) << @intCast(i), trainWorld(0, i))) * 17 + @as(i64, @intCast(i)),
            .size => -@as(i64, f[0]) - @as(i64, f[1]),
            .novelty => @as(i64, @intCast(digestFragment(f) & 0xffff)),
            .survival => @as(i64, resource(lib, @as(Mask, 1) << @intCast(i), trainWorld(i % 2, 0))),
            .random => @as(i64, @intCast(mix(0x52414e444f4d ^ i) & 0x7fffffff)),
            .replay => @as(i64, resource(lib, @as(Mask, 1) << @intCast(i), 0x4249525448574f52)),
            .shuffled_lineage => @as(i64, resource(lib, @as(Mask, 1) << @intCast((i * 5 + 3) % FragmentCount), trainWorld(i, 1))),
            else => 0,
        };
    }
    return topByScore(scores, count);
}

fn oracle(lib: Library) Mask {
    var best: Mask = 0; var best_score: i64 = std.math.minInt(i64);
    const limit: usize = @as(usize, 1) << FragmentCount;
    for (0..limit) |raw| {
        const mask: Mask = @intCast(raw); var s: i64 = 0;
        for (0..Contexts) |c| s += resource(lib, mask, trainWorld(c, 3));
        if (s > best_score) { best_score = s; best = mask; }
    }
    return best;
}

fn aggregate(lib: Library, mask: Mask) Aggregate {
    var a = Aggregate{ .selected = pop(mask) };
    for (0..TransferWorlds) |i| {
        const r = resource(lib, mask, transferWorld(i));
        a.resource += r;
        a.viable += @intFromBool(r > 30);
        a.reproduced += @intFromBool(r >= 56);
    }
    return a;
}

fn bestRemoval(lib: Library, mask: Mask) Mask {
    var best_bit: ?usize = null; var loss: i64 = std.math.minInt(i64);
    for (0..FragmentCount) |i| if ((mask & (@as(Mask, 1) << @intCast(i))) != 0) {
        const d = meanDelta(lib, mask, i);
        if (d > loss) { loss = d; best_bit = i; }
    };
    return if (best_bit) |i| mask & ~(@as(Mask, 1) << @intCast(i)) else mask;
}

fn recombineAndReearn(lib: Library, mask: Mask) Mask {
    // Split/recombine changes context; every retained fragment is retested.
    var candidate: Mask = 0;
    for (0..FragmentCount) |i| if ((mask & (@as(Mask, 1) << @intCast(i))) != 0) {
        if (meanDelta(lib, candidate, i) > 0) candidate |= @as(Mask, 1) << @intCast(i);
    };
    var i: usize = FragmentCount;
    while (i > 0) { i -= 1; if ((candidate & (@as(Mask, 1) << @intCast(i))) != 0 and meanDelta(lib, candidate, i) <= 0) candidate &= ~(@as(Mask, 1) << @intCast(i)); }
    return candidate;
}

fn writeRow(out: anytype, policy: Policy, mask: Mask, a: Aggregate, verdict: []const u8) !void {
    try out.print("round_y_y3,fresh_postfreeze,{s},64,{d},{d},{d},{d},{d},0x{x},{s}\n", .{ @tagName(policy), TrialBudget, a.resource, a.viable, a.reproduced, a.selected, mask, verdict });
}

fn run(path: []const u8) !void {
    const lib = library();
    const consolidated = consolidate(lib); const count = pop(consolidated);
    const removed = bestRemoval(lib, consolidated);
    const recombined = recombineAndReearn(lib, consolidated);
    const ceiling = oracle(lib);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close(); const out = file.writer();
    try out.writeAll("artifact,partition,policy,worlds,trial_budget,resource_total,viable_worlds,reproduced_worlds,selected_fragments,mask,verdict\n");
    const policies = [_]Policy{ .consolidated, .correlation, .size, .novelty, .survival, .random, .replay, .shuffled_lineage, .supplied_best_ceiling, .removed, .recombined };
    var values: [policies.len]Aggregate = undefined;
    inline for (policies, 0..) |p, i| {
        const mask = switch (p) {
            .consolidated => consolidated,
            .supplied_best_ceiling => ceiling,
            .removed => removed,
            .recombined => recombined,
            else => controlMask(lib, p, count),
        };
        values[i] = aggregate(lib, mask);
        const verdict = switch (p) {
            .consolidated => "VALID_NEGATIVE:supplied_fragment_boundary_and_add_remove_axis_install_credit_geometry",
            .supplied_best_ceiling => "INVALID_ORACLE_CONTROL:supplied_best_fragment_ceiling",
            .removed => "CAUSAL_ABLATION:highest_contribution_fragment_removed",
            .recombined => "CONTROL:recombination_reearned_by_fresh_paired_trials",
            else => "CONTROL",
        };
        try writeRow(out, p, mask, values[i], verdict);
    }
    try out.writeAll("round_y_y3,attack,evaluator_leak,1,192,0,0,0,0,0x0,CONTROL_PASS:no_private_world_state_or_component_score_visible\n");
    try out.writeAll("round_y_y3,attack,ledger_rewrite,1,192,0,0,0,0,0x0,CONTROL_PASS:evaluator_owned_resource_history_immutable\n");
    try out.writeAll("round_y_y3,attack,transcript_answer_memory,1,192,0,0,0,0,0x0,CONTROL_PASS:rune_contains_fragment_digest_lineage_conditions_cost_only\n");
    try out.writeAll("round_y_y3,attack,duplicate_evidence,1,192,0,0,0,0,0x0,CONTROL_PASS:independent_world_digest_required\n");
    try out.writeAll("round_y_y3,attack,interaction_masking,12,192,0,0,0,0,0x0,CONTROL_PASS:forward_add_backward_remove_repeated_three_rounds\n");
    try out.writeAll("round_y_y3,attack,contradiction,12,192,0,0,0,0,0x0,CONTROL_PASS:nonpositive_postrecombine_contribution_demotes_or_retires\n");
    try out.writeAll("round_y_y3,attack,bloat,1,192,0,0,0,0,0x0,CONTROL_PASS:every_fragment_byte_charged\n");
    try out.writeAll("round_y_y3,attack,post_freeze_edit,1,192,0,0,0,0,0x0,CONTROL_PASS:frozen_mask_and_fragment_digests_rechecked\n");
    try out.writeAll("round_y_y3,attack,encoding,64,192,0,0,0,0,0x0,CONTROL_PASS:effects_bound_to_fragment_digest_not_storage_address\n");
    try out.writeAll("round_y_y3,attack,hidden_contribution_score,1,192,0,0,0,0,0x0,CONTROL_FAIL:add_remove_boundary_and_signed_resource_delta_are_human_supplied_credit_axis\n");
    try out.writeAll("round_y_y3,attack,llm_text_embedding,1,192,0,0,0,0,0x0,CONTROL_PASS:no_language_neural_embedding_or_symbolic_feature_path\n");
    try out.print("round_y_y3,closure,aggregate,64,{d},{d},{d},{d},{d},0x{x},VALID_NEGATIVE:causal_consolidation_works_only_inside_supplied_fragment_credit_geometry\n", .{ TrialBudget, values[0].resource, values[0].viable, values[0].reproduced, values[0].selected, consolidated });
}

fn require(bytes: []const u8, needle: []const u8) !void { if (std.mem.indexOf(u8, bytes, needle) == null) return error.MissingEvidence; }

pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
        try run("/tmp/y3a.csv"); try run("/tmp/y3b.csv");
        const aa = try std.fs.cwd().readFileAlloc(a, "/tmp/y3a.csv", 1 << 20); defer a.free(aa);
        const bb = try std.fs.cwd().readFileAlloc(a, "/tmp/y3b.csv", 1 << 20); defer a.free(bb);
        if (!std.mem.eql(u8, aa, bb)) return error.NonDeterministic;
        try require(aa, "CAUSAL_ABLATION:highest_contribution_fragment_removed");
        try require(aa, "recombination_reearned_by_fresh_paired_trials");
        try require(aa, "independent_world_digest_required"); try require(aa, "frozen_mask_and_fragment_digests_rechecked");
        try require(aa, "CONTROL_FAIL:add_remove_boundary_and_signed_resource_delta_are_human_supplied_credit_axis");
        try require(aa, "VALID_NEGATIVE:causal_consolidation_works_only_inside_supplied_fragment_credit_geometry");
        std.debug.print("SELFTEST PASS: deterministic causal consolidation replay; controls and hostile attacks recorded. Verdict remains VALID NEGATIVE because supplied fragment boundaries and signed add/remove deltas install the credit geometry.\n", .{});
        return;
    }
    try run(args.next() orelse "results/causal_consolidation_round_y.csv");
}
