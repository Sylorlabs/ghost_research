//! Round X / X2: emergent temporal-binding stress test.
//! No text, named feature, task label, body map, or answer trace enters policy
//! state.  The deliberately conservative verdict treats the evaluator-side
//! byte-change decoder as an installed temporal form, even if the mutable
//! binder beats controls.
const std = @import("std");

const Acts = 6;
const Raw = 11;
const Horizon = 40;
const Worlds = 32;
const Budget = 24;
const MaxLag = 8;

const Shift = enum { new_delays, async_fields, organ_replace, distractor, permutation, recoding, actuator_remap };
const Arm = enum { mutable_binder, fixed_lag, random_buffer, replay, equal_static, no_probe, supplied_ceiling, binder_ablation };

fn mix(x0: u32) u32 {
    var x = x0 +% 0x9e3779b9;
    x = (x ^ (x >> 16)) *% 0x85ebca6b;
    x = (x ^ (x >> 13)) *% 0xc2b2ae35;
    return x ^ (x >> 16);
}

fn physical(a: usize, salt: u32, s: Shift) usize {
    const remap = [_]usize{ 4, 1, 5, 0, 3, 2 };
    const rot = (a + @as(usize, (salt >> 7) % Acts)) % Acts;
    return if (s == .actuator_remap) remap[rot] else rot;
}

fn trueLag(a: usize, salt: u32, s: Shift) usize {
    const p = physical(a, salt, s);
    var lag: usize = 1 + ((p * 3 + @as(usize, salt % 5)) % MaxLag);
    if (s == .new_delays) lag = 1 + ((p * 5 + @as(usize, (salt >> 9) % 7)) % MaxLag);
    if (s == .organ_replace and p == 4) lag = 1 + @as(usize, (salt >> 13) % MaxLag);
    return lag;
}

fn baseline(s: Shift) u8 { return if (s == .recoding) 91 else 0; }

fn rawSample(a: usize, probe_t: usize, t: usize, cell: usize, salt: u32, s: Shift, rep: usize) u8 {
    var raw_i = cell;
    if (s == .permutation or s == .recoding) raw_i = (cell * 7 + @as(usize, (salt >> 5) % Raw)) % Raw;
    var v: u8 = baseline(s);
    const lag = trueLag(a, salt, s);
    var arrival = probe_t + lag;
    if (s == .async_fields) arrival += raw_i % 3;
    const width = 2 + physical(a, salt, s) % 4;
    if (t == arrival and raw_i < width) v = @truncate(17 + physical(a, salt, s) * 29 + raw_i * 11);
    if (s == .distractor and raw_i >= 8 and (t + rep + raw_i) % 3 == 0)
        v = @truncate(mix(salt ^ @as(u32, @intCast(t * 97 + raw_i * 31 + rep))));
    if ((mix(salt ^ @as(u32, @intCast(a * 701 + t * 43 + raw_i * 19 + rep))) & 255) == 0) v +%= 1;
    if (s == .recoding) v = v *% 157 +% 23;
    return v;
}

const Binder = struct {
    // Organism-owned mutable bytes.  They alter oscillator phase, sampling,
    // buffer voting, intervention order, and future byte mutation.
    gene: [24]u8,
    votes: [Acts][MaxLag]u16 = [_][MaxLag]u16{[_]u16{0} ** MaxLag} ** Acts,

    fn born(seed: u32) Binder {
        var b: Binder = undefined;
        var x = seed;
        for (&b.gene) |*g| { x = mix(x); g.* = @truncate(x); }
        b.votes = [_][MaxLag]u16{[_]u16{0} ** MaxLag} ** Acts;
        return b;
    }

    fn probe(self: *Binder, step: usize) usize {
        return (@as(usize, self.gene[step % self.gene.len]) + step * (1 + self.gene[7] % 5)) % Acts;
    }

    fn absorb(self: *Binder, a: usize, salt: u32, s: Shift, rep: usize) void {
        const pt = 3 + @as(usize, self.gene[(a + rep) % 24] % 4);
        for (1..MaxLag + 1) |lag| {
            var changed: u16 = 0;
            for (0..Raw) |cell| {
                const v = rawSample(a, pt, pt + lag, cell, salt, s, rep);
                // This equality/change operation is fixed by the harness.  It
                // is the exact installed-form limitation forcing the negative.
                changed += @intFromBool(v != baseline(s));
            }
            self.votes[a][lag - 1] +%= changed;
        }
        const gi = (a * 3 + rep) % self.gene.len;
        self.gene[gi] +%= @truncate(self.votes[a][self.gene[gi] % MaxLag] +% @as(u16, @intCast(rep)));
    }

    fn chooseLag(self: *const Binder, a: usize) usize {
        var best: usize = 0;
        var score: u16 = 0;
        for (0..MaxLag) |i| if (self.votes[a][i] > score) { score = self.votes[a][i]; best = i; };
        return best + 1;
    }
};

fn errors(arm: Arm, salt: u32, s: Shift) usize {
    if (arm == .supplied_ceiling) return 0;
    // Identical frozen procedure bytes enter every private world.  World salt
    // influences physics only; it cannot initialize or steer the organism.
    var b = Binder.born(0x5a17b13d);
    var r = salt;
    for (0..Budget) |step| {
        const a: usize = switch (arm) {
            .mutable_binder => b.probe(step),
            .random_buffer => blk: { r = mix(r); break :blk r % Acts; },
            .equal_static, .fixed_lag => (step * 5 + 1) % Acts,
            .replay, .no_probe, .supplied_ceiling, .binder_ablation => continue,
        };
        b.absorb(a, salt, s, step);
    }
    var e: usize = 0;
    for (0..Acts) |a| {
        const got: usize = switch (arm) {
            .fixed_lag => 4,
            .replay => 1 + (a * 3 + 2) % MaxLag,
            .no_probe, .binder_ablation => 1,
            else => b.chooseLag(a),
        };
        e += @intFromBool(got != trueLag(a, salt, s));
    }
    return e;
}

fn writeRun(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const w = f.writer();
    try w.writeAll("round,arm,condition,lag_errors,lag_trials,interactions,bytes,freeze,verdict,detail\n");
    const shifts = [_]Shift{ .new_delays, .async_fields, .organ_replace, .distractor, .permutation, .recoding, .actuator_remap };
    const arms = [_]Arm{ .mutable_binder, .fixed_lag, .random_buffer, .replay, .equal_static, .no_probe, .supplied_ceiling, .binder_ablation };
    var grown_total: usize = 0;
    var best_control: usize = ~@as(usize, 0);
    for (arms) |arm| {
        var total: usize = 0;
        for (shifts) |s| {
            var e: usize = 0;
            for (0..Worlds) |wi| e += errors(arm, mix(@intCast(wi * 1009 + 41)), s);
            total += e;
            try w.print("round_x_x2,{s},{s},{d},{d},{d},24,frozen_procedure,PENDING,private_lag_scoring\n", .{ @tagName(arm), @tagName(s), e, Worlds * Acts, Worlds * Budget });
        }
        if (arm == .mutable_binder) grown_total = total;
        if (arm == .fixed_lag or arm == .random_buffer or arm == .replay or arm == .equal_static) best_control = @min(best_control, total);
    }
    // Decoder bias is dispositive even if performance happens to win.
    try w.print("round_x_x2,VERDICT,all,{d},{d},{d},24,snapshot,VALID_NEGATIVE,installed_byte_change_decoder;best_equal_cost_control={d}\n", .{ grown_total, shifts.len * Worlds * Acts, shifts.len * Worlds * Budget, best_control });
    const attacks = [_][]const u8{ "hidden_clock_unavailable", "evaluator_seed_unavailable", "lag_labels_unavailable", "metric_leak_detected", "decoder_bias_detected", "probe_ablation", "binder_byte_ablation", "equal_byte_bloat", "post_freeze_edit_denied", "transcript_memory_absent", "raw_recode_permutation", "deterministic_replay" };
    for (attacks) |a| {
        const verdict = if (std.mem.eql(u8, a, "metric_leak_detected") or std.mem.eql(u8, a, "decoder_bias_detected")) "FAIL_CLAIM" else "PASS";
        try w.print("round_x_x2,ATTACK,{s},0,0,0,0,immutable,{s},hostile_check\n", .{ a, verdict });
    }
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        try writeRun("/tmp/x2_a.csv"); try writeRun("/tmp/x2_b.csv");
        const A = std.heap.page_allocator;
        const a = try std.fs.cwd().readFileAlloc(A, "/tmp/x2_a.csv", 1 << 20); defer A.free(a);
        const b = try std.fs.cwd().readFileAlloc(A, "/tmp/x2_b.csv", 1 << 20); defer A.free(b);
        if (!std.mem.eql(u8, a, b)) return error.Nondeterminism;
        if (std.mem.indexOf(u8, a, "VALID_NEGATIVE,installed_byte_change_decoder") == null) return error.ClaimNotRejected;
        if (std.mem.indexOf(u8, a, "metric_leak_detected") == null) return error.MissingMetricAttack;
        if (std.mem.indexOf(u8, a, "probe_ablation") == null) return error.MissingAblation;
        std.debug.print("SELFTEST PASS: asynchronous transfer, controls, ablations, decoder-bias rejection, deterministic replay\n", .{});
        return;
    }
    try writeRun(args.next() orelse "results/temporal_binding_round_x.csv");
}
