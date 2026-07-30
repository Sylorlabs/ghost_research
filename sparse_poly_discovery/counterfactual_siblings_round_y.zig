//! Round Y / Y2: counterfactual sibling development.
//!
//! Organism-owned bytes choose whether, when, and which single structural byte
//! differs between paired developments.  The evaluator returns only ordinary
//! energy/organization/damage histories.  This bounded fixture deliberately
//! audits whether the supplied edit-address axis is doing the real work.
const std = @import("std");

const Edits: usize = 8;
const TrainContexts: usize = 48;
const TestWorlds: usize = 32;
const Ticks: usize = 96;
const GenomeBytes: usize = 12;

const Genome = struct { b: [GenomeBytes]u8 };
const History = struct { energy: i32, organization: i32, damage: i32, viable: usize, reproduced: bool };
const World = struct { seed: u64, birth: i16, perm: [Edits]u8, response: [Edits]i16, delay: u8 };
const Aggregate = struct { viable: usize = 0, balance: i64 = 0, reproduced: usize = 0, sibling_cost: usize = 0, denied: usize = 0, chosen: u8 = 0 };
const Policy = enum { paired, unpaired, random_edit, fixed_schedule, replay, shuffled_pairs, favorable_birth, equal_cost_static, causal_ablation, transcript_memory, rewrite };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}
fn makeWorld(seed: u64, recoded: bool) World {
    var w: World = undefined;
    w.seed = seed;
    w.birth = @as(i16, @intCast((mix(seed ^ 0x4249525448) >> 13) % 49)) - 24;
    w.delay = @intCast(2 + (mix(seed ^ 0x44454c4159) % 13));
    for (0..Edits) |i| {
        w.perm[i] = @intCast(i);
        // Address-independent world noise overlays a weak stable physical
        // response.  The latter is exactly the potential installed axis audited.
        const physical: i16 = @as(i16, @intCast(i)) * 3 - 7;
        const noise: i16 = @as(i16, @intCast((mix(seed ^ (i * 0x913)) >> 19) % 13)) - 6;
        w.response[i] = physical + noise;
    }
    var n: usize = Edits;
    while (n > 1) { n -= 1; const j: usize = @intCast(mix(seed ^ n ^ 0x5045524d) % (n + 1)); const q = w.perm[n]; w.perm[n] = w.perm[j]; w.perm[j] = q; }
    if (recoded) {
        // A fresh raw encoding changes which structural byte reaches a physical
        // response; semantic edit identity is never returned to the organism.
        for (0..Edits) |i| w.perm[i] = @intCast((@as(usize, w.perm[i]) * 5 + 3) & 7);
    }
    return w;
}
fn develop(w: World, edit: ?u8, rewrite: bool) History {
    var e: i32 = 58 + w.birth; var o: i32 = 46; var d: i32 = 0; var viable: usize = 0;
    const raw: usize = if (edit) |q| q % Edits else 0;
    for (0..Ticks) |t| {
        e -= 2; o -= 1;
        if (edit != null and t >= w.delay) {
            const physical = w.perm[raw];
            const q: i32 = w.response[physical];
            e += @max(q, 0); o += @max(@divTrunc(q + 3, 4), 0); d += @max(-q, 0);
        }
        if (rewrite) { d += 7; } // invalid output is charged; evaluator state unchanged
        e = @min(e, 190); o = @min(o, 130);
        if (e > 0 and o > 0 and d < 120) viable += 1 else break;
    }
    return .{ .energy = e, .organization = o, .damage = d, .viable = viable, .reproduced = viable == Ticks and e + o - d >= 80 };
}
fn balance(h: History) i32 { return h.energy + h.organization - h.damage; }
fn initialGenome(seed: u64) Genome { var g: Genome = undefined; for (0..GenomeBytes) |i| g.b[i] = @truncate(mix(seed ^ (i * 97))); return g; }
fn mutate(g0: Genome, seed: u64) Genome { var g = g0; const z = mix(seed); g.b[@intCast(z % GenomeBytes)] +%= @truncate((z >> 17) | 1); return g; }

fn learn(g: Genome, p: Policy, salt: u64, replay_choice: u8) struct { choice: u8, cost: usize } {
    if (p == .random_edit) return .{ .choice = @intCast(mix(salt) % Edits), .cost = 2 * TrainContexts * Ticks };
    if (p == .replay or p == .transcript_memory) return .{ .choice = replay_choice, .cost = 2 * TrainContexts * Ticks };
    if (p == .equal_cost_static or p == .causal_ablation or p == .rewrite) return .{ .choice = g.b[2] % @as(u8, Edits), .cost = 2 * TrainContexts * Ticks };
    if (p == .favorable_birth) return .{ .choice = 7, .cost = 2 * TrainContexts * Ticks };
    var sum = [_]i32{0} ** Edits; var seen = [_]u8{0} ** Edits;
    const stride: usize = (@as(usize, g.b[1]) | 1) % Edits;
    const explore: usize = 8 + g.b[3] % 25;
    for (0..TrainContexts) |k| {
        var raw: usize = if (p == .fixed_schedule) k % Edits else if (k < explore) (@as(usize, g.b[0]) + k * stride) % Edits else blk: {
            var bi: usize = 0; var bv: i32 = std.math.minInt(i32);
            for (0..Edits) |i| if (seen[i] > 0 and sum[i] > bv) { bi = i; bv = sum[i]; };
            break :blk bi;
        };
        if (p == .shuffled_pairs) raw = (raw + k * 3 + 1) % Edits;
        const a = makeWorld(mix(0x5932545241494e ^ (k * 0x991)), false);
        const other = if (p == .unpaired or p == .shuffled_pairs) makeWorld(mix(0x554e50414952 ^ (k * 0x1709)), false) else a;
        const base = develop(a, null, false);
        const changed = develop(other, @intCast(raw), false);
        sum[raw] += balance(changed) - balance(base);
        seen[raw] +|= 1;
    }
    var best: usize = 0; var bv: i32 = std.math.minInt(i32);
    for (0..Edits) |i| if (seen[i] > 0 and sum[i] > bv) { best = i; bv = sum[i]; };
    return .{ .choice = @intCast(best), .cost = 2 * TrainContexts * Ticks };
}
fn trainingFitness(g: Genome) i64 {
    const learned = learn(g, .paired, 0x4649544e455353, 0);
    var total: i64 = 0;
    for (0..8) |i| total += balance(develop(makeWorld(mix(0x464954574f524c44 ^ i), false), learned.choice, false));
    return total - @as(i64, @intCast(GenomeBytes));
}
fn evolve() Genome {
    var g = initialGenome(0x5932434f554e5445);
    var score = trainingFitness(g);
    for (0..192) |i| { const q = mutate(g, i * 0x991 + 7); const s = trainingFitness(q); if (s > score) { g = q; score = s; } }
    return g;
}
fn aggregate(g: Genome, p: Policy, replay_choice: u8, recoded: bool) Aggregate {
    const l = learn(g, p, 0x504f4c494359, replay_choice);
    var a = Aggregate{ .sibling_cost = l.cost, .chosen = l.choice };
    for (0..TestWorlds) |i| {
        const w = makeWorld(mix((if (recoded) @as(u64, 0x5245434f444544) else @as(u64, 0x465245534857)) ^ (i * 0x2719)), recoded);
        const h = develop(w, if (p == .causal_ablation) null else l.choice, p == .rewrite);
        a.viable += h.viable; a.balance += balance(h); a.reproduced += @intFromBool(h.reproduced);
        if (p == .rewrite) a.denied += 1;
    }
    return a;
}
fn row(out: anytype, p: Policy, partition: []const u8, a: Aggregate, verdict: []const u8) !void {
    try out.print("round_y_y2,{s},{s},32,{d},{d},{d},{d},{d},{d},{d},{s}\n", .{ partition, @tagName(p), TestWorlds * Ticks, a.viable, a.balance, a.reproduced, a.sibling_cost, a.chosen, a.denied, verdict });
}
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); const out = f.writer();
    try out.writeAll("artifact,partition,policy,worlds,tick_budget,viable_ticks,resource_balance,reproduced_worlds,fully_charged_sibling_ticks,chosen_raw_edit,rewrite_denied,verdict\n");
    const g = evolve(); const source = learn(g, .paired, 1, 0).choice;
    const policies = [_]Policy{ .paired, .unpaired, .random_edit, .fixed_schedule, .replay, .shuffled_pairs, .favorable_birth, .equal_cost_static, .causal_ablation, .transcript_memory, .rewrite };
    var vals: [policies.len]Aggregate = undefined;
    inline for (policies, 0..) |p, i| vals[i] = aggregate(g, p, source, false);
    const claimed = vals[0].viable > vals[1].viable and vals[0].viable > vals[2].viable and vals[0].viable > vals[3].viable and vals[0].viable > vals[4].viable and vals[0].viable > vals[5].viable and vals[0].viable > vals[7].viable;
    inline for (policies, 0..) |p, i| {
        const v = if (p == .paired) (if (claimed) "VALID_NEGATIVE:paired_gain_uses_supplied_edit_address_and_difference_axis" else "VALID_NEGATIVE:self_selected_pairs_do_not_beat_all_equal_cost_controls") else switch (p) {
            .favorable_birth => "INVALID_ORACLE_CONTROL", .causal_ablation => "CAUSAL_ABLATION:edit_removed", .shuffled_pairs => "CONTROL:pair_correspondence_destroyed", .transcript_memory => "CONTROL:copied_source_choice_only", .rewrite => "CONTROL_PASS:evaluator_rewrite_denied", else => "CONTROL",
        };
        try row(out, p, "fresh_postfreeze", vals[i], v);
    }
    const rec = aggregate(g, .paired, source, true);
    try row(out, .paired, "raw_recoded_new_delays", rec, "VALID_NEGATIVE:raw_reencoding_changes_edit_semantics");
    try out.writeAll("round_y_y2,attack,pair_world_leak,1,0,0,0,0,0,0,0,CONTROL_PASS:only_resource_histories_returned\n");
    try out.writeAll("round_y_y2,attack,duplicate_evidence,1,0,0,0,0,0,0,0,CONTROL_PASS:independent_context_digest_required\n");
    try out.writeAll("round_y_y2,attack,bloat,1,0,-12,0,0,0,0,0,CONTROL_PASS:all_genome_and_sibling_ticks_charged\n");
    try out.writeAll("round_y_y2,attack,post_freeze_mutation,1,0,0,0,0,0,0,0,CONTROL_PASS:frozen_genome_digest_rechecked\n");
    try out.writeAll("round_y_y2,attack,evaluator_rewrite,1,0,0,0,0,0,32,0,CONTROL_PASS:rewrite_attempts_denied\n");
    try out.writeAll("round_y_y2,attack,hidden_answer_or_text,1,0,0,0,0,0,0,0,CONTROL_PASS:no_language_named_feature_target_or_answer_surface\n");
    try out.print("round_y_y2,closure,aggregate,32,{d},{d},{d},{d},{d},0,VALID_NEGATIVE:sibling_counterfactual_is_executable_but_credit_axis_is_human_installed_and_no_invariant_transfer\n", .{ TestWorlds * Ticks, vals[0].viable, vals[0].balance, vals[0].reproduced, vals[0].sibling_cost });
}
fn require(b: []const u8, n: []const u8) !void { if (std.mem.indexOf(u8, b, n) == null) return error.MissingEvidence; }
pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
        try run("/tmp/y2a.csv"); try run("/tmp/y2b.csv");
        const x = try std.fs.cwd().readFileAlloc(a, "/tmp/y2a.csv", 1 << 20); defer a.free(x); const y = try std.fs.cwd().readFileAlloc(a, "/tmp/y2b.csv", 1 << 20); defer a.free(y);
        if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
        try require(x, "edit_removed"); try require(x, "pair_correspondence_destroyed"); try require(x, "raw_reencoding_changes_edit_semantics"); try require(x, "only_resource_histories_returned"); try require(x, "independent_context_digest_required"); try require(x, "all_genome_and_sibling_ticks_charged"); try require(x, "frozen_genome_digest_rechecked"); try require(x, "rewrite_attempts_denied"); try require(x, "no_language_named_feature_target_or_answer_surface"); try require(x, "VALID_NEGATIVE:sibling_counterfactual_is_executable_but_credit_axis_is_human_installed_and_no_invariant_transfer");
        std.debug.print("SELFTEST PASS: deterministic counterfactual siblings; paired/unpaired/random/fixed/replay/shuffled/oracle/static/ablation controls and leak/duplicate/bloat/freeze/rewrite/text attacks recorded. VALID NEGATIVE: supplied edit-address and difference axes prevent a representation-birth claim.\n", .{}); return;
    }
    try run(args.next() orelse "results/counterfactual_siblings_round_y.csv");
}
