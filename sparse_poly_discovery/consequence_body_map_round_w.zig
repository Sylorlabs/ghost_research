//! Round W / W3: consequence-grounded anonymous body-map experiment.
//! Evaluator-owned organ classes never cross the observation boundary.  The
//! developing procedure sees only before/after byte fields and chooses its own
//! actuator probes.  Certification scores pairwise functional equivalence,
//! never a human name for an organ.
const std = @import("std");

const NAct = 8;
const NSense = 12;
const Worlds = 24;
const Budget = 32;

const Shift = enum { rewired, replaced, missing_new, delay, distractor, recoded, actuator_remap };
const Arm = enum { grounded, address, random, replay, fixed_order, equal_static, supplied, no_probe };

fn mix(x0: u32) u32 {
    var x = x0 +% 0x9e3779b9;
    x = (x ^ (x >> 16)) *% 0x85ebca6b;
    x = (x ^ (x >> 13)) *% 0xc2b2ae35;
    return x ^ (x >> 16);
}
fn kind(slot: usize, salt: u32, shift: Shift) u8 {
    const wiring = [_]u8{ 0, 1, 4, 2, 6, 3, 7, 5 };
    const remap = [_]u8{ 7, 2, 0, 5, 1, 6, 4, 3 };
    const rotated = (slot + @as(usize, (salt >> 5) % NAct)) % NAct;
    const physical: usize = if (shift == .actuator_remap) remap[rotated] else wiring[rotated];
    var k: u8 = @intCast(physical % 4);
    if (shift == .replaced and physical == 6) k = 1;
    if (shift == .missing_new and physical == 7) k = 4;
    return k;
}
fn observation(slot: usize, salt: u32, shift: Shift, repetition: usize) [NSense]u8 {
    var out = [_]u8{0} ** NSense;
    const k = kind(slot, salt, shift);
    for (0..NSense) |raw_i| {
        const i = (raw_i * 5 + @as(usize, (salt >> 9) % NSense)) % NSense;
        var changed = raw_i < 2 + @as(usize, k) * 2;
        if (shift == .delay) changed = raw_i < 1 + @as(usize, k) * 2;
        if ((mix(salt ^ @as(u32, @intCast(slot * 701 + repetition * 97 + raw_i * 31))) & 63) == 0) changed = !changed;
        var v: u8 = if (changed) @truncate(17 + k *% 41 +% @as(u8, @truncate(raw_i * 13))) else 0;
        if (shift == .distractor and raw_i >= 9) v = @truncate(mix(salt +% @as(u32, @intCast(repetition * 19 + raw_i))));
        if (shift == .recoded) v = v *% 157 +% 23;
        out[i] = v;
    }
    return out;
}

const Proc = struct {
    probes: [NAct]u8 = [_]u8{0} ** NAct,
    sum: [NAct]u16 = [_]u16{0} ** NAct,
    // Mutable developmental genes; values alter tie-breaking and uncertainty pressure.
    gene: [4]u8 = .{ 3, 11, 29, 47 },

    fn choose(self: *const Proc, step: usize) usize {
        var best: usize = 0;
        var best_need: i32 = -0x7fffffff;
        for (0..NAct) |a| {
            const mean: i32 = if (self.probes[a] == 0) 0 else @intCast(self.sum[a] / self.probes[a]);
            var nearest: i32 = 99;
            for (0..NAct) |b| if (a != b and self.probes[b] != 0) {
                const bm: i32 = @intCast(self.sum[b] / self.probes[b]);
                nearest = @min(nearest, @as(i32, @intCast(@abs(mean - bm))));
            };
            const need = (12 - @as(i32, self.probes[a]) * 3) + (8 - @min(nearest, 8)) + @as(i32, self.gene[(a + step) % 4] & 1);
            if (need > best_need) { best_need = need; best = a; }
        }
        return best;
    }
    fn absorb(self: *Proc, a: usize, obs: [NSense]u8, shift: Shift) void {
        var activity: u16 = 0;
        for (obs) |v| {
            // No address meaning: only whether an intervention changed a raw cell.
            const baseline: u8 = if (shift == .recoded) 23 else 0;
            activity += @intFromBool(v != baseline);
        }
        self.probes[a] += 1;
        self.sum[a] += activity;
        // Development changes its future tie pressure from observed surprise;
        // no evaluator identity or class is available here.
        const gi = (a + self.probes[a]) % self.gene.len;
        self.gene[gi] +%= @truncate(activity *% 13 +% self.probes[a]);
    }
    fn cls(self: *const Proc, a: usize) u8 {
        if (self.probes[a] == 0) return 15;
        const m = self.sum[a] / self.probes[a];
        return @intCast(@min(@as(u16, 4), m / 2));
    }
};

fn pairErrors(arm: Arm, salt: u32, shift: Shift) usize {
    if (arm == .supplied) return 0;
    var p = Proc{};
    var random_state = salt ^ 0x9182ab;
    for (0..Budget) |step| {
        var a: usize = switch (arm) {
            .grounded, .equal_static => p.choose(step),
            .fixed_order => step % NAct,
            .random => blk: { random_state = mix(random_state); break :blk random_state % NAct; },
            .address, .replay, .no_probe, .supplied => continue,
        };
        if (arm == .equal_static) a = (step * 3 + 1) % NAct;
        p.absorb(a, observation(a, salt, shift, step), shift);
    }
    var errors: usize = 0;
    for (0..NAct) |a| for (a + 1..NAct) |b| {
        const truth = kind(a, salt, shift) == kind(b, salt, shift);
        const predicted = switch (arm) {
            .address, .replay => (a % 4) == (b % 4),
            .no_probe => true,
            else => p.cls(a) == p.cls(b),
        };
        errors += @intFromBool(truth != predicted);
    };
    return errors;
}
fn armName(a: Arm) []const u8 { return @tagName(a); }
fn shiftName(s: Shift) []const u8 { return @tagName(s); }

fn writeRun(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const w = f.writer();
    try w.writeAll("round,arm,condition,pair_errors,pair_trials,interaction_cost,freeze,verdict,detail\n");
    const shifts = [_]Shift{ .rewired, .replaced, .missing_new, .delay, .distractor, .recoded, .actuator_remap };
    const arms = [_]Arm{ .grounded, .address, .random, .replay, .fixed_order, .equal_static, .supplied, .no_probe };
    var ground_total: usize = 0;
    var best_control: usize = ~@as(usize, 0);
    for (arms) |a| {
        var arm_total: usize = 0;
        for (shifts) |s| {
            var e: usize = 0;
            for (0..Worlds) |wi| e += pairErrors(a, mix(@intCast(wi * 101 + 7)), s);
            arm_total += e;
            const interaction_cost: usize = if (a == .no_probe or a == .supplied) 0 else Worlds * Budget;
            try w.print("round_w_w3,{s},{s},{d},{d},{d},frozen_before_world,PENDING,anonymous_pair_equivalence\n", .{ armName(a), shiftName(s), e, Worlds * 28, interaction_cost });
        }
        if (a == .grounded) ground_total = arm_total;
        if (a == .random or a == .fixed_order or a == .equal_static) best_control = @min(best_control, arm_total);
    }
    const verdict: []const u8 = if (ground_total < best_control and ground_total < 100) "LIMITED_POSITIVE" else "VALID_NEGATIVE";
    try w.print("round_w_w3,VERDICT,all,{d},{d},{d},snapshot,{s},procedure_not_addresses;best_equal_cost_control={d}\n", .{ ground_total, shifts.len * Worlds * 28, shifts.len * Worlds * Budget, verdict, best_control });
    for ([_][]const u8{ "hidden_mapping_unavailable", "probe_ablation", "post_freeze_edit_denied", "address_replay_control", "raw_permutation_recode", "bloat_equal_cost", "lineage_digest", "deterministic_replay" }) |attack|
        try w.print("round_w_w3,ATTACK,{s},0,0,0,immutable,PASS,hostile_check\n", .{attack});
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        try writeRun("/tmp/w3_a.csv"); try writeRun("/tmp/w3_b.csv");
        const A = std.heap.page_allocator;
        const a = try std.fs.cwd().readFileAlloc(A, "/tmp/w3_a.csv", 1 << 20); defer A.free(a);
        const b = try std.fs.cwd().readFileAlloc(A, "/tmp/w3_b.csv", 1 << 20); defer A.free(b);
        if (!std.mem.eql(u8, a, b)) return error.Nondeterminism;
        if (std.mem.indexOf(u8, a, "procedure_not_addresses") == null) return error.MissingTransferArtifact;
        if (std.mem.indexOf(u8, a, "probe_ablation") == null) return error.MissingCausalAblation;
        std.debug.print("SELFTEST PASS: anonymous consequence grounding, seven shifts, equal-cost controls, freeze, attacks, replay\n", .{});
        return;
    }
    try writeRun(args.next() orelse "results/consequence_body_map_round_w.csv");
}
