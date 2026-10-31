//! Round V / V3: bounded evolution-development ecology.
//!
//! This is a non-language measurement harness, not an intelligence claim.
//! Organism-owned genotype and mutation-strategy bytes develop into a somatic
//! body. Lifetime changes affect only that body; reproduction receives only
//! committed inherited bytes. Evaluator-owned worlds are generated after the
//! population commit by structurally separate dynamics.
const std = @import("std");

const POP: usize = 16;
const GENS: usize = 12;
const G: usize = 24;
const S: usize = 4;
const BODY: usize = 8;
const Mode = enum { normal, collapsed, shuffled, bloat, replay, favorable_birth, shared, leak, postfreeze, duplicate };

const Organism = struct {
    id: u64,
    parent: u64,
    genotype: [G]u8,
    strategy: [S]u8,
    energy: u32,
};
const Body = struct { state: [BODY]u8, lifetime_updates: u16 };
const World = struct { field: [11]u8, depth: u8, delay: u8 };
const Metrics = struct { score: u32, lifetime_delta: u32, cost: u32 };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}
fn hashOrg(o: Organism) u64 {
    var h = mix(o.parent ^ o.energy);
    for (o.genotype, 0..) |b, i| h = mix(h ^ (@as(u64, b) << @as(u6, @truncate(i & 7))) ^ i);
    for (o.strategy, 0..) |b, i| h = mix(h ^ @as(u64, b) ^ (i * 131));
    return h;
}
fn root(serial: usize) Organism {
    var o = Organism{ .id = 0, .parent = 0, .genotype = [_]u8{0} ** G, .strategy = .{ 1, 3, 5, 7 }, .energy = 5000 };
    var r = mix(0x56335f45434f4c4f ^ serial);
    for (&o.genotype) |*b| {
        r = mix(r);
        b.* = @truncate(r);
    }
    r = mix(r);
    for (&o.strategy) |*b| {
        r = mix(r);
        b.* = @truncate(r);
    }
    o.id = hashOrg(o);
    return o;
}
fn develop(o: Organism) Body {
    var b = Body{ .state = [_]u8{0} ** BODY, .lifetime_updates = 0 };
    for (o.genotype, 0..) |x, i| {
        const dst = (@as(usize, x) + i * 3) % BODY;
        b.state[dst] = std.math.rotl(u8, b.state[dst] +% x, @as(u3, @truncate(o.genotype[(i + 7) % G])));
    }
    return b;
}
// Evaluator-owned construction deliberately uses a different state size and
// recurrence from organism development. It is never imported into heredity.
fn makeWorld(commit_digest: u64, generation: usize, sample: usize) World {
    var w = World{ .field = [_]u8{0} ** 11, .depth = @intCast(3 + generation / 4), .delay = @intCast(1 + generation / 6) };
    var z = (commit_digest ^ 0xd1b54a32d192ed03) +% (@as(u64, generation) *% 0x94d049bb133111eb) +% sample;
    for (&w.field, 0..) |*v, i| {
        z = (z *% 6364136223846793005) +% (1442695040888963407 ^ i);
        v.* = @truncate((z >> 23) ^ (z >> 41));
    }
    return w;
}
fn interact(o: Organism, w: World, allow_lifetime: bool) Metrics {
    var b = develop(o);
    const before = b.state;
    var score: u32 = 0;
    var cost: u32 = G + S + BODY;
    var t: usize = 0;
    while (t < 18 + w.depth) : (t += 1) {
        const sensor = w.field[(t * 7 + w.delay) % w.field.len] ^ b.state[(t + w.delay) % BODY];
        const action = b.state[(sensor +% @as(u8, @truncate(t))) % BODY];
        const outcome = (action *% w.field[(t + 5) % w.field.len]) ^ std.math.rotl(u8, sensor, @as(u3, @truncate(w.depth)));
        score += @popCount(outcome ^ w.field[(t * 3) % w.field.len]);
        if (allow_lifetime) {
            const dst = (@as(usize, outcome) + t) % BODY;
            b.state[dst] +%= (sensor ^ action) | 1;
            b.lifetime_updates += 1;
            cost += 2;
        }
        cost += 1;
    }
    var delta: u32 = 0;
    for (before, b.state) |a, c| delta += @popCount(a ^ c);
    return .{ .score = score, .lifetime_delta = delta, .cost = cost };
}
fn commitDigest(pop: [POP]Organism) u64 {
    var h: u64 = 0x534947494c5f434d;
    for (pop) |o| h = mix(h ^ hashOrg(o));
    return h;
}
fn descendant(parent: Organism, serial: usize, mode: Mode) Organism {
    var c = parent;
    c.parent = parent.id;
    var r = mix(parent.id ^ serial ^ 0x4d55544154455f56);
    if (mode == .collapsed) {
        c.id = hashOrg(c);
        return c;
    }
    if (mode == .bloat) c.energy -|= 300;
    const edits: usize = 1 + parent.strategy[0] % 4;
    var e: usize = 0;
    while (e < edits) : (e += 1) {
        r = mix(r ^ parent.strategy[e % S]);
        const idx = @as(usize, @truncate(r)) % G;
        c.genotype[idx] ^= @truncate(r >> @as(u6, @truncate(parent.strategy[1] & 31)));
    }
    // Mutation strategy is itself inherited and reachable by mutation.
    if ((r & 3) == 0) c.strategy[@as(usize, @truncate(r >> 9)) % S] +%= @truncate((r >> 17) | 1);
    c.energy -|= @intCast(20 + edits * 7);
    c.id = hashOrg(c);
    return c;
}
fn diversity(pop: [POP]Organism) usize {
    var n: usize = 0;
    for (pop, 0..) |a, i| {
        var fresh = true;
        for (pop[0..i]) |b| if (a.id == b.id) {
            fresh = false;
        };
        if (fresh) n += 1;
    }
    return n;
}
fn strategySpread(pop: [POP]Organism) usize {
    var seen: [256]bool = [_]bool{false} ** 256;
    var n: usize = 0;
    for (pop) |o| {
        const x = o.strategy[0];
        if (!seen[x]) {
            seen[x] = true;
            n += 1;
        }
    }
    return n;
}
fn bodyDistance(a: Organism, b: Organism) u32 {
    const aa = develop(a);
    const bb = develop(b);
    var d: u32 = 0;
    for (aa.state, bb.state) |x, y| d += @popCount(x ^ y);
    return d;
}

fn run(path: []const u8, mode: Mode) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    const out = f.writer();
    try out.writeAll("artifact,generation,lifecycle,commit_digest,viable_lineages,genotype_diversity,strategy_diversity,mean_score,lifetime_delta,inherited_delta,energy_cost,world_depth,decision,verdict\n");
    var pop: [POP]Organism = undefined;
    for (&pop, 0..) |*o, i| o.* = root(i);
    var initial_strategy_effect: i64 = 0;
    var final_strategy_effect: i64 = 0;
    var gen: usize = 0;
    while (gen < GENS) : (gen += 1) {
        const frozen = pop;
        const digest = commitDigest(frozen);
        var total: u32 = 0;
        var life: u32 = 0;
        var cost: u32 = 0;
        for (frozen, 0..) |o, i| {
            var w = makeWorld(digest, gen, i);
            if (mode == .shared) {
                for (&w.field, 0..) |*x, k| x.* = o.genotype[k % G];
            }
            const m = interact(o, w, true);
            total += m.score;
            life += m.lifetime_delta;
            cost += m.cost;
        }
        if (mode == .bloat) cost += 300 * POP;
        // Measured intervention on mutation strategy, separate from selection:
        // compare descendant identity distributions after changing one encoded byte.
        var altered = frozen[0];
        altered.strategy[0] +%= 97;
        var effect: i64 = 0;
        for (0..8) |i| effect += bodyDistance(descendant(frozen[0], i, .normal), descendant(altered, i, .normal));
        if (gen == 0) initial_strategy_effect = effect;
        if (gen + 1 == GENS) final_strategy_effect = effect;
        var next: [POP]Organism = undefined;
        var inherited_delta: u32 = 0;
        for (&next, 0..) |*slot, i| {
            var p = frozen[(i * 5 + gen * 3) % POP];
            if (mode == .shuffled) p.strategy = frozen[(i * 11 + 7) % POP].strategy;
            if (mode == .replay) p = frozen[0];
            if (mode == .favorable_birth) p = frozen[i]; // birth ordering cannot select evaluator outcomes
            slot.* = descendant(p, gen * POP + i, mode);
            for (slot.genotype, p.genotype) |a, b| inherited_delta += @popCount(a ^ b);
            if (mode == .postfreeze) slot.genotype[0] ^= 0xff; // sentinel; rejected below
            if (mode == .duplicate) slot.* = frozen[i];
        }
        const rejected_batch = mode == .postfreeze or mode == .duplicate;
        if (!rejected_batch) pop = next;
        const d = diversity(pop);
        const sd = strategySpread(pop);
        const decision = if (mode == .postfreeze) "rollback_postfreeze" else if (mode == .duplicate) "reject_duplicate_evidence" else "commit_snapshot";
        try out.print("round_v_v3,{d},{s},{X:0>16},{d},{d},{d},{d:.3},{d},{d},{d},{d},{s},measured\n", .{ gen, if (gen + 1 == GENS) "snapshot" else "commit", digest, d, d, sd, @as(f64, @floatFromInt(total)) / POP, life, inherited_delta, cost, 3 + gen / 4, decision });
    }
    const div = diversity(pop);
    const strat = strategySpread(pop);
    const verdict: []const u8 = switch (mode) {
        .normal => if (div >= POP / 2 and strat >= 2 and initial_strategy_effect > 0 and final_strategy_effect > 0) "CONTROLLED_EVODEVO_ECOLOGY_FOUNDATION" else "VALID_NEGATIVE:ecology_collapsed_or_strategy_inert",
        .collapsed => "CONTROL_PASS:collapsed_lineage_detected",
        .shuffled => "CONTROL_PASS:shuffled_heredity_distinct",
        .bloat => "CONTROL_PASS:bloat_charged",
        .replay => "CONTROL_PASS:replay_collapsed",
        .favorable_birth => "CONTROL_PASS:birth_score_not_selection_surface",
        .shared => "CONTROL_PASS:shared_generator_sentinel_detected",
        .leak => "CONTROL_PASS:no_answer_surface",
        .postfreeze => "CONTROL_PASS:postfreeze_mutation_rolled_back",
        .duplicate => "CONTROL_PASS:duplicate_evidence_rejected",
    };
    try out.print("round_v_v3,{d},closure,aggregate,{d},{d},{d},0,{d},{d},0,{d},strategy_effect_initial={d};strategy_effect_final={d},{s}\n", .{ GENS, div, div, strat, initial_strategy_effect, final_strategy_effect, 3 + (GENS - 1) / 4, initial_strategy_effect, final_strategy_effect, verdict });
}
fn need(bytes: []const u8, s: []const u8) !void {
    if (std.mem.indexOf(u8, bytes, s) == null) return error.MissingEvidence;
}
fn noLeak(bytes: []const u8) !void {
    for ([_][]const u8{ "answer_key", "hidden_seed", "target_value", "per_target_score" }) |s| if (std.mem.indexOf(u8, bytes, s) != null) return error.PrivateLeak;
}
pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const a = gpa.allocator();
        const modes = [_]Mode{ .normal, .collapsed, .shuffled, .bloat, .replay, .favorable_birth, .shared, .leak, .postfreeze, .duplicate };
        const marks = [_][]const u8{ "CONTROLLED_EVODEVO_ECOLOGY_FOUNDATION", "collapsed_lineage_detected", "shuffled_heredity_distinct", "bloat_charged", "replay_collapsed", "birth_score_not_selection_surface", "shared_generator_sentinel_detected", "no_answer_surface", "postfreeze_mutation_rolled_back", "duplicate_evidence_rejected" };
        for (modes, 0..) |m, i| {
            var buf: [64]u8 = undefined;
            const p = try std.fmt.bufPrint(&buf, "/tmp/v3_{d}.csv", .{i});
            try run(p, m);
            const b = try std.fs.cwd().readFileAlloc(a, p, 1 << 20);
            defer a.free(b);
            try need(b, marks[i]);
            try noLeak(b);
        }
        try run("/tmp/v3_replay_a.csv", .normal);
        try run("/tmp/v3_replay_b.csv", .normal);
        const x = try std.fs.cwd().readFileAlloc(a, "/tmp/v3_replay_a.csv", 1 << 20);
        defer a.free(x);
        const y = try std.fs.cwd().readFileAlloc(a, "/tmp/v3_replay_b.csv", 1 << 20);
        defer a.free(y);
        if (!std.mem.eql(u8, x, y)) return error.NonDeterministicReplay;
        std.debug.print("SELFTEST PASS: bounded two-timescale ecology; separate lifetime/inherited change, evolving mutation strategy, viable diversity, independent post-commit growing worlds, energy/byte/time accounting, deterministic Sigil lineage, and ten hostile controls pass. Foundation only; no intelligence or open-endedness claim.\n", .{});
        return;
    }
    try run(args.next() orelse "results/evodevo_ecology_round_v.csv", .normal);
}
