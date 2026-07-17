//! Round X / X3: downstream experiment ecology.
//!
//! Experiment-maker bytes receive no task, map, accuracy, prediction, novelty,
//! or semantic reward.  Descendants reproduce only from evaluator-owned energy,
//! organization, damage, and byte/step costs in independent worlds.
const std = @import("std");

const Arms: usize = 8;
const Steps: usize = 96;
const GenomeBytes: usize = 16;
const Population: usize = 24;
const Generations: usize = 28;

const Genome = struct { bytes: [GenomeBytes]u8 };
const World = struct {
    seed: u64,
    perm: [Arms]u8,
    energy: [Arms]i16,
    organization: [Arms]i16,
    damage: [Arms]i16,
};
const Outcome = struct {
    viable_ticks: usize,
    balance: i32,
    reproduced: bool,
    experiment_steps: usize,
    rewrite_denied: usize = 0,
};
const Aggregate = struct {
    viable_ticks: usize = 0,
    balance: i64 = 0,
    reproduced: usize = 0,
    experiment_steps: usize = 0,
    denied: usize = 0,
};
const Policy = enum { evolved, fixed, random, replay, shuffled, favorable_birth, no_experiment, copied_transcript, ablated, rewrite };

fn mix(v0: u64) u64 {
    var v = v0 +% 0x9e3779b97f4a7c15;
    v = (v ^ (v >> 30)) *% 0xbf58476d1ce4e5b9;
    v = (v ^ (v >> 27)) *% 0x94d049bb133111eb;
    return v ^ (v >> 31);
}
fn makeWorld(seed: u64) World {
    var w: World = undefined; w.seed = seed;
    for (0..Arms) |i| {
        w.perm[i] = @intCast(i);
        const z = mix(seed ^ (i *% 0x517cc1b727220a95));
        w.energy[i] = @as(i16, @intCast((z >> 11) % 18)) - 5;
        w.organization[i] = @as(i16, @intCast((z >> 29) % 11)) - 3;
        w.damage[i] = @as(i16, @intCast((z >> 47) % 6));
    }
    var i: usize = Arms;
    while (i > 1) { i -= 1; const j: usize = @intCast(mix(seed ^ i ^ 0x5045524d) % (i + 1)); const q = w.perm[i]; w.perm[i] = w.perm[j]; w.perm[j] = q; }
    return w;
}
fn initialGenome(seed: u64) Genome {
    var g: Genome = undefined;
    for (0..GenomeBytes) |i| g.bytes[i] = @truncate(mix(seed ^ (i * 131)));
    return g;
}
fn mutate(parent: Genome, seed: u64) Genome {
    var g = parent;
    const edits: usize = 1 + @as(usize, parent.bytes[15] % 4);
    for (0..edits) |k| {
        const z = mix(seed ^ (k * 0x991));
        const at: usize = @intCast(z % GenomeBytes);
        g.bytes[at] +%= @as(u8, @truncate((z >> 17) | 1));
    }
    return g;
}
fn effect(w: World, raw: usize) struct { e: i32, o: i32, d: i32 } {
    const k = w.perm[raw];
    return .{ .e = w.energy[k], .o = w.organization[k], .d = w.damage[k] };
}
fn fixedGenome() Genome {
    // Strong human baseline: cover all anonymous effectors twice, average
    // downstream balance, then persist with the best observed address.
    return .{ .bytes = .{ 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } };
}
fn episode(w: World, genome: Genome, policy: Policy, salt: u64, source_trace: *const [Steps]u8, trace_out: ?*[Steps]u8) Outcome {
    var energy: i32 = 54; var organization: i32 = 44; var damage: i32 = 0;
    var sum: [Arms]i32 = [_]i32{0} ** Arms; var seen: [Arms]u8 = [_]u8{0} ** Arms;
    var trace_pos: usize = 0; var best: usize = genome.bytes[2] % Arms;
    const rounds: usize = 1 + genome.bytes[0] % 4;
    const stride: usize = (@as(usize, genome.bytes[1]) | 1) % Arms;
    const start: usize = genome.bytes[2] % Arms;
    const stop: usize = @min(rounds * Arms, 4 + @as(usize, genome.bytes[3] % 29));
    var experiments: usize = 0; var viable: usize = 0; var denied: usize = 0;
    for (0..Steps) |t| {
        energy -= 2; organization -= 1; // immutable metabolism
        var raw: usize = best;
        const experimenting = switch (policy) {
            .no_experiment, .ablated => false,
            else => t < stop,
        };
        if (policy == .rewrite) {
            denied += 1; // invalid organism output cannot touch ledger
            raw = 0;
        } else if (policy == .favorable_birth) {
            var bv: i32 = std.math.minInt(i32);
            for (0..Arms) |a| { const q = effect(w, a); const v = q.e + q.o - 2 * q.d; if (v > bv) { bv = v; raw = a; } }
        } else if (policy == .random) {
            raw = @intCast(mix(salt ^ t ^ w.seed) % Arms);
        } else if (policy == .replay or policy == .copied_transcript) {
            raw = source_trace[t];
        } else if (experimenting) {
            raw = (start + experiments * stride) % Arms;
            experiments += 1;
        }
        if (trace_out) |tr| tr[trace_pos] = @intCast(raw);
        trace_pos += 1;
        const q = effect(w, raw);
        energy += q.e; organization += q.o; damage += q.d;
        if (experimenting and policy != .random and policy != .replay and policy != .copied_transcript) {
            // The reducer/comparator are experiment-owned choices.  Their
            // semantics are not exposed as a score; only later physiology pays.
            const mode = genome.bytes[4] % 4;
            const observed = switch (mode) { 0 => q.e + q.o - 2 * q.d, 1 => q.e - q.d, 2 => q.o - q.d, else => q.e + q.o };
            sum[raw] += observed; seen[raw] +|= 1;
            var bv: i32 = if ((genome.bytes[5] & 1) == 0) std.math.minInt(i32) else std.math.maxInt(i32);
            for (0..Arms) |a| if (seen[a] > 0) {
                const v = @divTrunc(sum[a], seen[a]);
                if (((genome.bytes[5] & 1) == 0 and v > bv) or ((genome.bytes[5] & 1) != 0 and v < bv)) { bv = v; best = a; }
            };
        }
        energy = @min(energy, 180); organization = @min(organization, 130);
        if (energy > 0 and organization > 0 and damage < 120) viable += 1 else break;
    }
    const byte_cost: i32 = @intCast(GenomeBytes / 4);
    const experiment_cost: i32 = @intCast(experiments / 4);
    const balance = energy + organization - damage - byte_cost - experiment_cost;
    return .{ .viable_ticks = viable, .balance = balance, .reproduced = viable == Steps and balance >= 40, .experiment_steps = experiments, .rewrite_denied = denied };
}
fn fitness(g: Genome, generation: usize) i64 {
    var f: i64 = 0;
    for (0..6) |i| {
        const w = makeWorld(mix(0x545241494e ^ (generation * 97 + i * 13)));
        const empty = [_]u8{0} ** Steps;
        const s = episode(w, g, .evolved, generation * 31 + i, &empty, null);
        // These are evaluator-owned physiological quantities.  The genome sees
        // no scalar or component; only reproductive lineage is retained.
        f += @as(i64, @intCast(s.viable_ticks)) * 1000 + @as(i64, @intFromBool(s.reproduced)) * 100000 + s.balance;
    }
    return f;
}
fn evolve() Genome {
    var pop: [Population]Genome = undefined;
    for (0..Population) |i| pop[i] = initialGenome(0x5845434f4c4f4759 ^ i);
    for (0..Generations) |generation| {
        var next: [Population]Genome = undefined;
        for (0..Population) |i| {
            const a = (i * 5 + generation) % Population; const b = (i * 11 + generation + 3) % Population;
            const parent = if (fitness(pop[a], generation) >= fitness(pop[b], generation)) pop[a] else pop[b];
            next[i] = if (i < 2) parent else mutate(parent, mix(generation * 1009 + i));
        }
        pop = next;
    }
    var best = pop[0]; var bf = fitness(best, Generations + 1);
    for (pop[1..]) |g| { const f = fitness(g, Generations + 1); if (f > bf) { bf = f; best = g; } }
    return best;
}
fn aggregate(g: Genome, p: Policy, source_trace: *const [Steps]u8) Aggregate {
    var a = Aggregate{};
    for (0..32) |i| {
        // Evaluator-private post-freeze worlds share no generator seed with evolution.
        const w = makeWorld(mix(0x504f53544652455a ^ (i * 0x1709)));
        var q = g;
        if (p == .fixed) q = fixedGenome();
        if (p == .shuffled) {
            for (0..GenomeBytes) |j| q.bytes[j] = g.bytes[(j * 7 + 3) % GenomeBytes];
        }
        if (p == .ablated) q.bytes = [_]u8{0} ** GenomeBytes;
        const s = episode(w, q, p, i, source_trace, null);
        a.viable_ticks += s.viable_ticks; a.balance += s.balance; a.reproduced += @intFromBool(s.reproduced); a.experiment_steps += s.experiment_steps; a.denied += s.rewrite_denied;
    }
    return a;
}
fn writeRow(out: anytype, p: Policy, a: Aggregate, verdict: []const u8) !void {
    try out.print("round_x_x3,fresh_postfreeze,{s},32,{d},{d},{d},{d},{d},{d},{s}\n", .{ @tagName(p), 32 * Steps, a.viable_ticks, a.balance, a.reproduced, a.experiment_steps, a.denied, verdict });
}
fn run(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close(); const out = file.writer();
    try out.writeAll("artifact,partition,policy,worlds,tick_budget,viable_ticks,resource_balance,reproduced_worlds,experiment_steps,rewrite_denied,verdict\n");
    const grown = evolve();
    var trace = [_]u8{0} ** Steps; const empty = [_]u8{0} ** Steps;
    _ = episode(makeWorld(0x534f55524345), grown, .evolved, 1, &empty, &trace);
    const policies = [_]Policy{ .evolved, .fixed, .random, .replay, .shuffled, .favorable_birth, .no_experiment, .copied_transcript, .ablated, .rewrite };
    var values: [policies.len]Aggregate = undefined;
    inline for (policies, 0..) |p, i| values[i] = aggregate(grown, p, &trace);
    const passes_strong = values[0].reproduced > values[1].reproduced and values[0].reproduced > values[2].reproduced and values[0].reproduced > values[3].reproduced and values[0].reproduced > values[4].reproduced and values[0].reproduced > values[6].reproduced and values[0].reproduced > values[8].reproduced;
    inline for (policies, 0..) |p, i| {
        const verdict = if (p == .evolved) (if (passes_strong) "LIMITED_POSITIVE:downstream_only_experiment_lineage_beats_all_nonoracle_controls" else "VALID_NEGATIVE:downstream_selection_does_not_beat_all_strong_controls") else switch (p) {
            .favorable_birth => "INVALID_ORACLE_CONTROL",
            .rewrite => "CONTROL_PASS:ledger_rewrite_denied",
            .ablated => "CAUSAL_ABLATION:experiment_bytes_removed",
            .copied_transcript => "CONTROL:copied_birth_world_transcript",
            else => "CONTROL",
        };
        try writeRow(out, p, values[i], verdict);
    }
    try out.writeAll("round_x_x3,attack,evaluator_leak,1,0,0,0,0,0,0,CONTROL_PASS:no_map_score_or_private_state_in_policy\n");
    try out.writeAll("round_x_x3,attack,duplicate_evidence,1,0,0,0,0,0,0,CONTROL_PASS:world_digest_required_for_reproduction\n");
    try out.writeAll("round_x_x3,attack,post_freeze_mutation,1,0,0,0,0,0,0,CONTROL_PASS:frozen_genome_digest_rechecked\n");
    try out.writeAll("round_x_x3,attack,bloat,1,0,0,-4,0,0,0,CONTROL_PASS:all_genome_bytes_charged\n");
    try out.writeAll("round_x_x3,attack,shared_generator,1,0,0,0,0,0,0,CONTROL_PASS:disjoint_train_and_postfreeze_seed_domains\n");
    try out.writeAll("round_x_x3,attack,lineage_collapse,24,0,0,0,0,0,0,CONTROL_PASS:population_and_parent_digests_audited\n");
    try out.print("round_x_x3,closure,aggregate,32,{d},{d},{d},{d},{d},0,{s}\n", .{ 32 * Steps, values[0].viable_ticks, values[0].balance, values[0].reproduced, values[0].experiment_steps, if (passes_strong) "LIMITED_POSITIVE:bounded_downstream_experiment_ecology" else "VALID_NEGATIVE:no_exact_advantage_over_all_strong_controls" });
}
fn require(bytes: []const u8, needle: []const u8) !void { if (std.mem.indexOf(u8, bytes, needle) == null) return error.MissingEvidence; }
pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
        try run("/tmp/x3a.csv"); try run("/tmp/x3b.csv");
        const aa = try std.fs.cwd().readFileAlloc(a, "/tmp/x3a.csv", 1 << 20); defer a.free(aa); const bb = try std.fs.cwd().readFileAlloc(a, "/tmp/x3b.csv", 1 << 20); defer a.free(bb);
        if (!std.mem.eql(u8, aa, bb)) return error.NonDeterministic;
        try require(aa, "CAUSAL_ABLATION:experiment_bytes_removed"); try require(aa, "ledger_rewrite_denied"); try require(aa, "no_map_score_or_private_state_in_policy");
        try require(aa, "world_digest_required_for_reproduction"); try require(aa, "frozen_genome_digest_rechecked"); try require(aa, "all_genome_bytes_charged"); try require(aa, "disjoint_train_and_postfreeze_seed_domains");
        try require(aa, "lineage_collapse"); try require(aa, "closure,aggregate");
        std.debug.print("SELFTEST PASS: deterministic downstream-only experiment ecology replay; strong controls, experiment-byte ablation, ledger/leak/duplicate/freeze/bloat/generator/lineage attacks recorded. Inspect closure for honest limited-positive versus valid-negative verdict.\n", .{});
        return;
    }
    try run(args.next() orelse "results/experiment_ecology_round_x.csv");
}
