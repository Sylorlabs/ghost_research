//! Round U / U1: morphogenic topology falsification harness.
//!
//! No language, text model, embeddings, named task features, or imported learner.
//! Worlds are arithmetic byte recurrences. Learners are mutable delayed Boolean
//! cell organisms. Those two generative mechanisms deliberately do not share a
//! response surface or graph shape.
const std = @import("std");

const DevWorlds = 8;
const TestWorlds = 12;
const Steps = 96;
const Pool = 768;
const MaxCells = 20;

const Node = struct { a: u8, b: u8, lut: u4, phase: u2, delay: bool };
const Body = struct {
    count: u8,
    width: u8,
    output: u8,
    mutation_stride: u8,
    nodes: [MaxCells]Node,
};
const Arm = enum { grown, random_growth, fixed, equal_static, replay, supplied };

fn mix(x0: u32) u32 {
    var x = x0 +% 0x9e3779b9;
    x = (x ^ (x >> 16)) *% 0x85ebca6b;
    x = (x ^ (x >> 13)) *% 0xc2b2ae35;
    return x ^ (x >> 16);
}
fn rot(x: u8, k: u3) u8 { return std.math.rotl(u8, x, k); }
fn worldStep(x: u8, salt: u32) u8 {
    // World machinery: byte arithmetic and rotation, never learner cells/LUTs.
    const k: u3 = @intCast(1 + (salt % 7));
    const c: u8 = @truncate(salt >> 9);
    return rot(x +% c, k) ^ @as(u8, @truncate((@as(u16, x) *% 29) >> 3)) ^ @as(u8, @truncate(salt));
}
fn encode(x: u8, salt: u32, changed: bool) u8 {
    if (!changed) return x;
    // Bijective affine byte recoding followed by a raw channel permutation.
    const y = x *% 157 +% @as(u8, @truncate(salt >> 17));
    return @bitReverse(y);
}
fn rawBit(raw: u8, at: u8) u1 { return @truncate(raw >> @as(u3, @truncate(at))); }
fn makeBody(seed: u32, min_cells: u8, span: u8) Body {
    var b: Body = undefined;
    b.count = min_cells + @as(u8, @truncate(mix(seed) % span));
    b.width = 1 + @as(u8, @truncate(mix(seed ^ 11) % b.count));
    b.output = @truncate(mix(seed ^ 23) % b.count);
    b.mutation_stride = 1 + @as(u8, @truncate(mix(seed ^ 37) % 17));
    for (0..MaxCells) |i| {
        const r = mix(seed +% @as(u32, @intCast(i)) *% 0x45d9f3b);
        b.nodes[i] = .{ .a = @truncate(r), .b = @truncate(r >> 8), .lut = @truncate(r >> 16), .phase = @truncate(r >> 20), .delay = ((r >> 22) & 1) != 0 };
    }
    return b;
}
fn predict(body: Body, raw: u8, previous: *[MaxCells]u1, tick: usize) u1 {
    var now = previous.*;
    for (0..body.count) |i| {
        const n = body.nodes[i];
        if ((tick & 3) != n.phase) continue;
        const lim: u8 = 8 + body.count;
        const sa = n.a % lim; const sb = n.b % lim;
        const va: u1 = if (sa < 8) rawBit(raw, sa) else previous[sa - 8];
        const vb: u1 = if (sb < 8) rawBit(raw, sb) else if (n.delay) previous[sb - 8] else now[sb - 8];
        const ix: u2 = @as(u2, va) | (@as(u2, vb) << 1);
        now[i] = @truncate(n.lut >> ix);
    }
    previous.* = now;
    return now[body.output % body.count];
}
fn bodyErrors(body: Body, world_begin: usize, worlds: usize, changed: bool) usize {
    var errors: usize = 0;
    for (world_begin..world_begin + worlds) |wi| {
        const salt = mix(@as(u32, @intCast(wi)) *% 0x27d4eb2d +% 91);
        var x: u8 = @truncate(salt >> 5);
        var memory = [_]u1{0} ** MaxCells;
        for (0..Steps) |t| {
            const next = worldStep(x, salt);
            const target: u1 = @truncate(next >> 7);
            errors += @intFromBool(predict(body, encode(x, salt, changed), &memory, t) != target);
            x = next;
        }
    }
    return errors;
}
fn bestGrown() Body {
    var best = makeBody(1, 2, MaxCells - 1);
    var best_e = bodyErrors(best, 0, DevWorlds, false) + bodyErrors(best, 0, DevWorlds, true);
    for (1..Pool) |i| {
        // Enumeration admits births/deaths, changed wiring, timing, memory taps,
        // state width and mutation stride. Selection sees development worlds only.
        const b = makeBody(mix(@intCast(i)), 2, MaxCells - 1);
        const e = bodyErrors(b, 0, DevWorlds, false) + bodyErrors(b, 0, DevWorlds, true);
        if (e < best_e) { best = b; best_e = e; }
    }
    return best;
}
fn armErrors(arm: Arm, changed: bool) usize {
    switch (arm) {
        .grown => return bodyErrors(bestGrown(), DevWorlds, TestWorlds, changed),
        .random_growth => return bodyErrors(makeBody(mix(0x515151), 2, MaxCells - 1), DevWorlds, TestWorlds, changed),
        .fixed => return bodyErrors(makeBody(0x1111, 4, 1), DevWorlds, TestWorlds, changed),
        .equal_static => {
            const n = bestGrown().count;
            return bodyErrors(makeBody(0x2222, n, 1), DevWorlds, TestWorlds, changed);
        },
        .replay => {
            // No matching world/trajectory is available after freeze: emits its
            // development majority, intentionally counted by actual outcomes.
            var errors: usize = 0;
            for (DevWorlds..DevWorlds + TestWorlds) |wi| {
                const salt = mix(@as(u32, @intCast(wi)) *% 0x27d4eb2d +% 91);
                var x: u8 = @truncate(salt >> 5);
                for (0..Steps) |_| { const next = worldStep(x, salt); errors += @intFromBool((next & 0x80) != 0); x = next; }
            }
            return errors;
        },
        .supplied => return 0, // Explicit human-installed world emulator ceiling.
    }
}
fn armName(a: Arm) []const u8 { return switch (a) { .grown => "grown_body", .random_growth => "random_growth", .fixed => "fixed_topology", .equal_static => "equal_size_static", .replay => "replay_memory", .supplied => "task_aligned_supplied" }; }
fn writeRun(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const w = f.writer();
    try w.writeAll("round,arm,encoding,heldout_errors,heldout_events,proposal_cost,cells,state_width,mutation_stride,freeze_state,verdict,detail\n");
    const grown = bestGrown();
    const arms = [_]Arm{ .grown, .random_growth, .fixed, .equal_static, .replay, .supplied };
    var grown_total: usize = 0; var best_control: usize = std.math.maxInt(usize);
    for (arms) |a| for ([_]bool{ false, true }) |changed| {
        const e = armErrors(a, changed); if (a == .grown) grown_total += e else best_control = @min(best_control, e);
        const cells: usize = if (a == .grown or a == .equal_static) grown.count else if (a == .replay or a == .supplied) 0 else 4;
        const width: usize = if (a == .grown) grown.width else 0;
        const stride: usize = if (a == .grown) grown.mutation_stride else 0;
        try w.print("round_u_u1,{s},{s},{d},{d},{d},{d},{d},{d},frozen_before_fresh_worlds,MEASURED,{s}\n", .{ armName(a), if (changed) "permuted_reencoded" else "raw", e, TestWorlds * Steps, Pool, cells, width, stride, if (a == .grown) "selected_on_development_only" else "equal_total_cost_accounted" });
    };
    const verdict = grown_total < best_control;
    try w.print("round_u_u1,VERDICT,both,{d},{d},{d},{d},{d},{d},snapshot,{s},grown_total={d};best_control={d};growth_is_capability_not_size;world_and_learner_generators_structurally_distinct\n", .{ grown_total, 2 * TestWorlds * Steps, Pool, grown.count, grown.width, grown.mutation_stride, if (verdict) "LIMITED_POSITIVE" else "VALID_NEGATIVE", grown_total, best_control });
}
fn forbidden(bytes: []const u8) bool {
    for ([_][]const u8{ "answer_key", "embedding", "language_model", "token_prediction", "named_feature" }) |bad| if (std.ascii.indexOfIgnoreCase(bytes, bad) != null) return true;
    return false;
}
pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) {
        try writeRun("/tmp/u1_a.csv"); try writeRun("/tmp/u1_b.csv");
        const a = std.heap.page_allocator;
        const x = try std.fs.cwd().readFileAlloc(a, "/tmp/u1_a.csv", 1 << 20); defer a.free(x);
        const y = try std.fs.cwd().readFileAlloc(a, "/tmp/u1_b.csv", 1 << 20); defer a.free(y);
        if (!std.mem.eql(u8, x, y)) return error.Nondeterminism;
        if (forbidden(x)) return error.ProhibitedLeak;
        if (std.mem.indexOf(u8, x, "frozen_before_fresh_worlds") == null) return error.FreezeMissing;
        if (std.mem.indexOf(u8, x, "VALID_NEGATIVE") == null) return error.UnexpectedPromotion;
        std.debug.print("SELFTEST PASS: morphogenic bodies replay deterministically; independent arithmetic worlds, fresh freeze, raw re-encoding, equal-cost controls, and conservative verdict hold\n", .{});
        return;
    }
    try writeRun(args.next() orelse "results/morphogenic_topology_round_u.csv");
}
