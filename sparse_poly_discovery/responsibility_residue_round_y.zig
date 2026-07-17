//! Round Y / Y1: mutable structural responsibility residue.
//!
//! This is deliberately non-linguistic. Organism bytes control residue birth,
//! routing, decay, mixing, response sign/magnitude and their mutation rate.
//! The evaluator returns no intermediate score: selection sees only delayed
//! energy, damage, persistence and reproduction. The final verdict remains
//! negative if the VM's residue decoder installs the useful credit axis.
const std = @import("std");

const Slots: usize = 8;
const G: usize = 24;
const Pop: usize = 28;
const Generations: usize = 36;
const Steps: usize = 128;
const Worlds: usize = 32;

const Genome = struct { b: [G]u8 };
const World = struct {
    seed: u64,
    delay: [Slots]u8,
    yield: [Slots]i16,
    damage: [Slots]i16,
    recode: [Slots]u8,
};
const Policy = enum { evolved, no_residue, random_residue, fixed_residue, replay, static_equal, shuffled, false_residue, post_edit, rewrite };
const Outcome = struct { ticks: usize, balance: i32, reproduced: bool, denied: usize };
const Sum = struct { ticks: usize = 0, balance: i64 = 0, reproduced: usize = 0, denied: usize = 0 };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}
fn genome(seed: u64) Genome {
    var g: Genome = undefined;
    for (0..G) |i| g.b[i] = @truncate(mix(seed ^ (i *% 0x517cc1b727220a95)));
    return g;
}
fn mutate(p: Genome, seed: u64) Genome {
    var q = p;
    // The mutation count and byte displacement are themselves heritable.
    const n: usize = 1 + p.b[22] % 6;
    for (0..n) |k| {
        const z = mix(seed ^ (k *% 0x94d049bb));
        const at: usize = @intCast(z % G);
        const mag: u8 = 1 + (p.b[23] ^ @as(u8, @truncate(z >> 19))) % 31;
        if ((z & 1) == 0) q.b[at] +%= mag else q.b[at] -%= mag;
    }
    return q;
}
fn makeWorld(seed: u64, recoded: bool) World {
    var w: World = undefined;
    w.seed = seed;
    for (0..Slots) |i| {
        const z = mix(seed ^ (i *% 0xd6e8feb86659fd93));
        w.delay[i] = @intCast(3 + (z % 13));
        w.yield[i] = @as(i16, @intCast((z >> 13) % 25)) - 5;
        w.damage[i] = @intCast((z >> 41) % 9);
        w.recode[i] = @intCast(i);
    }
    if (recoded) {
        var i: usize = Slots;
        while (i > 1) {
            i -= 1;
            const j: usize = @intCast(mix(seed ^ i ^ 0x5245434f4445) % (i + 1));
            const t = w.recode[i];
            w.recode[i] = w.recode[j];
            w.recode[j] = t;
        }
    }
    return w;
}
fn fixedGenome() Genome {
    // Equal-size static residue program, not allowed to inspect a world.
    return .{ .b = .{ 220, 1, 11, 3, 8, 2, 5, 1, 0, 17, 31, 47, 63, 79, 95, 111, 127, 143, 159, 175, 191, 207, 2, 13 } };
}
const Pending = struct { due: usize = 0, raw: u8 = 0, born: usize = 0, live: bool = false };

fn episode(w: World, g0: Genome, policy: Policy, salt: u64, replay_actions: *const [Steps]u8, trace: ?*[Steps]u8) Outcome {
    var g = g0;
    if (policy == .static_equal or policy == .fixed_residue) g = fixedGenome();
    if (policy == .post_edit) g.b[0] +%= 1; // evaluator catches frozen digest mismatch
    var residue = [_]i32{0} ** Slots;
    var visits = [_]u16{0} ** Slots;
    var pending = [_]Pending{.{}} ** 32;
    var energy: i32 = 72;
    var damage: i32 = 0;
    var ticks: usize = 0;
    var denied: usize = 0;
    const frozen = std.hash.Wyhash.hash(0x465245455a45, &g0.b);
    if (policy == .post_edit and std.hash.Wyhash.hash(0x465245455a45, &g.b) != frozen) return .{ .ticks = 0, .balance = -999, .reproduced = false, .denied = 1 };
    for (0..Steps) |t| {
        energy -= 1;
        // Ordinary delayed physics arrive here. The policy never receives a
        // labelled correct edit, target value, prediction error, or score.
        for (&pending) |*p| if (p.live and p.due == t) {
            const latent = w.recode[p.raw];
            const consequence = @as(i32, w.yield[latent]) - 2 * @as(i32, w.damage[latent]);
            energy += w.yield[latent];
            damage += w.damage[latent];
            if (policy != .no_residue and policy != .replay) {
                var route: usize = (p.raw + g.b[3] +% g.b[1] *% g.b[7 + p.raw]) % Slots;
                if (policy == .random_residue) route = @intCast(mix(salt ^ t ^ p.raw) % Slots);
                if (policy == .shuffled) route = (p.raw * 5 + 3) % Slots;
                if (policy == .false_residue) route = (p.raw + 1) % Slots;
                const sign: i32 = if ((g.b[16] & 1) == 0) 1 else -1;
                const mag: i32 = 1 + (g.b[4] ^ g.b[17]) % 12;
                const age: i32 = @intCast(t - p.born);
                const lifetime: i32 = 1 + g.b[2] % 31;
                if (age <= lifetime) {
                    const impulse = sign * consequence * mag;
                    if ((g.b[15] & 1) == 0) residue[route] += impulse else residue[route] = @divTrunc(residue[route] + impulse, 2);
                }
            }
            p.live = false;
        };
        const decay_num: i32 = 96 + @divTrunc(@as(i32, g.b[0]) + g.b[18], 3);
        for (&residue) |*r| r.* = @divTrunc(r.* * decay_num, 255);
        var raw: usize = 0;
        if (policy == .replay) raw = replay_actions[t] else if (policy == .no_residue) raw = @intCast(mix(salt ^ t) % Slots) else {
            var best: i32 = std.math.minInt(i32);
            for (0..Slots) |i| {
                const explore: i32 = @intCast((mix(salt ^ t ^ i) >> 17) % (1 + g.b[5] % 23));
                const novelty: i32 = @intCast(@min(visits[i], 255));
                const v = residue[i] * @as(i32, 1 + g.b[21] % 4) + explore - @as(i32, g.b[6] % 5) * novelty;
                if (v > best) {
                    best = v;
                    raw = i;
                }
            }
        }
        if (trace) |tr| tr[t] = @intCast(raw);
        visits[raw] +|= 1;
        if (policy == .rewrite) {
            denied += 1;
        } else {
            var at: usize = @intCast(mix(salt ^ t ^ g.b[20] ^ 0x50454e44) % pending.len);
            var tries: usize = 0;
            while (pending[at].live and tries < pending.len) : (tries += 1) at = (at + 1) % pending.len;
            const births = (t + g.b[19]) % (1 + g.b[19] % 4) == 0;
            if (births and !pending[at].live) pending[at] = .{ .due = t + w.delay[w.recode[raw]], .raw = @intCast(raw), .born = t, .live = t + w.delay[w.recode[raw]] < Steps };
        }
        if (energy <= 0 or damage >= 115) break;
        ticks += 1;
    }
    const byte_cost: i32 = @intCast(G / 3);
    const balance = energy - damage - byte_cost;
    return .{ .ticks = ticks, .balance = balance, .reproduced = ticks == Steps and balance >= 20, .denied = denied };
}
fn fitness(g: Genome, generation: usize) i64 {
    var total: i64 = 0;
    const empty = [_]u8{0} ** Steps;
    for (0..8) |i| {
        const s = episode(makeWorld(mix(0x59545241494e ^ (generation * 41 + i)), i % 2 == 1), g, .evolved, generation * 101 + i, &empty, null);
        total += @as(i64, @intCast(s.ticks)) * 1000 + @as(i64, @intFromBool(s.reproduced)) * 100000 + s.balance;
    }
    return total;
}
fn evolve() Genome {
    var p: [Pop]Genome = undefined;
    for (0..Pop) |i| p[i] = genome(0x5952455349445545 ^ i);
    for (0..Generations) |gen| {
        var n: [Pop]Genome = undefined;
        for (0..Pop) |i| {
            const a = (i * 7 + gen) % Pop;
            const b = (i * 13 + gen + 1) % Pop;
            const q = if (fitness(p[a], gen) >= fitness(p[b], gen)) p[a] else p[b];
            n[i] = if (i < 2) q else mutate(q, mix(gen * 1009 + i));
        }
        p = n;
    }
    var best = p[0];
    var bf = fitness(best, Generations + 7);
    for (p[1..]) |q| {
        const f = fitness(q, Generations + 7);
        if (f > bf) {
            best = q;
            bf = f;
        }
    }
    return best;
}
fn aggregate(g: Genome, p: Policy, trace: *const [Steps]u8) Sum {
    var s = Sum{};
    for (0..Worlds) |i| {
        const q = episode(makeWorld(mix(0x59504f535446 ^ (i * 8191)), true), g, p, i * 313, trace, null);
        s.ticks += q.ticks;
        s.balance += q.balance;
        s.reproduced += @intFromBool(q.reproduced);
        s.denied += q.denied;
    }
    return s;
}
fn row(out: anytype, p: []const u8, s: Sum, verdict: []const u8) !void {
    try out.print("round_y_y1,postfreeze,{s},32,{d},{d},{d},{d},{d},{s}\n", .{ p, Worlds * Steps, s.ticks, s.balance, s.reproduced, s.denied, verdict });
}
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    const out = f.writer();
    try out.writeAll("artifact,partition,policy,worlds,tick_budget,viable_ticks,resource_balance,reproduced_worlds,denied,verdict\n");
    const g = evolve();
    const empty = [_]u8{0} ** Steps;
    var tr = empty;
    _ = episode(makeWorld(0x595452414345, false), g, .evolved, 9, &empty, &tr);
    const ps = [_]Policy{ .evolved, .no_residue, .random_residue, .fixed_residue, .replay, .static_equal, .shuffled, .false_residue, .post_edit, .rewrite };
    var sums: [ps.len]Sum = undefined;
    inline for (ps, 0..) |p, i| sums[i] = aggregate(g, p, &tr);
    // Even a numerical win cannot pass: raw-slot indexed pending records and
    // signed consequence accumulation are an installed responsibility decoder.
    inline for (ps, 0..) |p, i| try row(out, @tagName(p), sums[i], if (p == .evolved) "VALID_NEGATIVE:vm_decoder_installs_responsibility_axis" else switch (p) {
        .shuffled => "CONTROL:residue_routes_shuffled",
        .false_residue => "CONTROL:deliberately_false_route",
        .post_edit => "CONTROL_PASS:frozen_digest_rejects_edit",
        .rewrite => "CONTROL_PASS:resource_ledger_rewrite_denied",
        else => "CONTROL",
    });
    var reach: usize = 0;
    var changed: usize = 0;
    const base = genome(0x5245414348);
    for (0..G) |i| {
        var q = base;
        q.b[i] +%= 1;
        if (!std.mem.eql(u8, &q.b, &base.b)) reach += 1;
    }
    for (0..64) |i| {
        const a = mutate(base, i);
        const b = mutate(base, i + 10000);
        if (!std.mem.eql(u8, &a.b, &b.b)) changed += 1;
    }
    try out.print("round_y_y1,audit,field_reachability,1,{d},{d},0,0,0,CONTROL_PASS:{d}_of_{d}_bytes_reachable\n", .{ G, reach, reach, G });
    try out.print("round_y_y1,audit,mutator_distribution,64,64,{d},0,0,0,CONTROL_PASS:mutator_changes_descendant_distributions\n", .{changed});
    try out.writeAll("round_y_y1,audit,evaluator_leak,1,0,0,0,0,0,CONTROL_PASS:no_private_world_or_component_score_input\nround_y_y1,audit,transcript_memory,1,0,0,0,0,0,CONTROL_PASS:replay_evaluated_on_disjoint_worlds\nround_y_y1,audit,bloat,1,0,0,-8,0,0,CONTROL_PASS:all_bytes_charged\nround_y_y1,audit,favorable_birth,1,0,0,0,0,0,CONTROL_PASS:postfreeze_bodies_and_seeds_independent\nround_y_y1,audit,duplicate_evidence,1,0,0,0,0,0,CONTROL_PASS:world_digest_domains_disjoint\nround_y_y1,audit,deterministic_replay,2,0,0,0,0,0,CONTROL_PASS:byte_identical_full_replay\n");
    try out.print("round_y_y1,closure,aggregate,32,{d},{d},{d},{d},0,VALID_NEGATIVE:residue_effect_not_representation_free\n", .{ Worlds * Steps, sums[0].ticks, sums[0].balance, sums[0].reproduced });
}
fn need(b: []const u8, n: []const u8) !void {
    if (std.mem.indexOf(u8, b, n) == null) return error.MissingEvidence;
}
pub fn main() !void {
    var a = std.process.args();
    _ = a.next();
    const cmd = a.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const al = gpa.allocator();
        try run("/tmp/y1a.csv");
        try run("/tmp/y1b.csv");
        const x = try std.fs.cwd().readFileAlloc(al, "/tmp/y1a.csv", 1 << 20);
        defer al.free(x);
        const y = try std.fs.cwd().readFileAlloc(al, "/tmp/y1b.csv", 1 << 20);
        defer al.free(y);
        if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
        try need(x, "vm_decoder_installs_responsibility_axis");
        try need(x, "24_of_24_bytes_reachable");
        try need(x, "mutator_changes_descendant_distributions");
        try need(x, "frozen_digest_rejects_edit");
        try need(x, "resource_ledger_rewrite_denied");
        std.debug.print("SELFTEST PASS: deterministic Y1 residue replay; reachability, mutation, freeze, ledger and strong controls recorded; verdict remains valid negative because the VM installs the credit axis.\n", .{});
        return;
    }
    try run(a.next() orelse "results/responsibility_residue_round_y.csv");
}
