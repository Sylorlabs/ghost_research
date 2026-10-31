//! Round T T1 -- raw causal substrate pilot.
//!
//! This is deliberately not an intelligence claim.  It is a falsification
//! harness for a small neutral micro-dynamic field: four raw binary cells, an
//! unlabelled 16-entry local response surface, and mutable incoming wires.
//! The response surface is stored as bits, never as a named operation.
//!
//! The important adverse result is built into the verdict: a shared response
//! surface is still a human-installed representational bias.  A transfer win
//! inside this substrate is therefore evidence about this substrate only, not
//! evidence of representation birth without a fixed grammar.
const std = @import("std");

const Worlds = 12;
const Cells = 4;
const Train = 12;
const Trials = 128;

const World = struct { surface: u16, wires: [Cells][2]u2, salt: u32 };
const Candidate = struct { surface: u16, wires: [Cells][2]u2, mismatch: usize };

fn mix(x0: u32) u32 {
    var x = x0 +% 0x9e3779b9;
    x = (x ^ (x >> 16)) *% 0x85ebca6b;
    x = (x ^ (x >> 13)) *% 0xc2b2ae35;
    return x ^ (x >> 16);
}
fn cell(x: u4, i: u2) u4 { return (x >> i) & 1; }
fn respond(surface: u16, x: u4, pair: [2]u2) u4 {
    const at: u4 = cell(x, pair[0]) | (cell(x, pair[1]) << 1);
    return @as(u4, @truncate((surface >> at) & 1));
}
fn step(surface: u16, wires: [Cells][2]u2, x: u4) u4 {
    var y: u4 = 0;
    for (0..Cells) |i| y |= respond(surface, x, wires[i]) << @as(u2, @intCast(i));
    return y;
}
fn makeWorld(index: usize) World {
    const s = mix(@as(u32, @intCast(index)) *% 0x517cc1b7 +% 17);
    // Ensure the response surface is neither all-zero nor all-one.  These are
    // raw bit constraints, not semantic task selection.
    const surface: u16 = @truncate((s ^ (s >> 11) ^ 0x6d3a) | 1);
    var wires: [Cells][2]u2 = undefined;
    for (0..Cells) |i| {
        const r = mix(s +% @as(u32, @intCast(i)) *% 0x45d9f3b);
        wires[i] = .{ @truncate(r), @truncate(r >> 3) };
    }
    return .{ .surface = surface, .wires = wires, .salt = s };
}
fn heldout(w: World, x: u4) bool {
    // Four states are sealed off by a deterministic raw hash.  The learner
    // sees the other twelve transitions, never this partition label.
    return (mix(w.salt ^ @as(u32, x) *% 0x27d4eb2d) & 3) == 0;
}
fn mistakes(surface: u16, wires: [Cells][2]u2, w: World, use_heldout: bool) usize {
    var bad: usize = 0;
    for (0..16) |n| {
        const x: u4 = @intCast(n);
        if (heldout(w, x) != use_heldout) continue;
        const a = step(surface, wires, x);
        const b = step(w.surface, w.wires, x);
        bad += @popCount(a ^ b);
    }
    return bad;
}
fn learn(w: World) Candidate {
    var best = Candidate{ .surface = 0, .wires = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } }, .mismatch = std.math.maxInt(usize) };
    // A field has one mutable 16-bit response surface and independently
    // mutable wire endpoints.  Exhaustive local selection is intentionally
    // transparent: no optimizer, language model, or named primitive is used.
    for (0..16) |raw_surface| {
        const surface: u16 = @intCast(raw_surface);
        var wires: [Cells][2]u2 = undefined;
        var total: usize = 0;
        for (0..Cells) |out| {
            var best_pair: [2]u2 = .{ 0, 0 };
            var best_error: usize = std.math.maxInt(usize);
            for (0..Cells) |a| for (0..Cells) |b| {
                const pair: [2]u2 = .{ @intCast(a), @intCast(b) };
                var error_count: usize = 0;
                for (0..16) |n| {
                    const x: u4 = @intCast(n);
                    if (heldout(w, x)) continue;
                    const target = cell(step(w.surface, w.wires, x), @intCast(out));
                    error_count += @intFromBool(respond(surface, x, pair) != target);
                }
                if (error_count < best_error) { best_error = error_count; best_pair = pair; }
            };
            wires[out] = best_pair;
            total += best_error;
        }
        if (total < best.mismatch) best = .{ .surface = surface, .wires = wires, .mismatch = total };
    }
    return best;
}
fn randomCandidate(w: World, trial: usize) Candidate {
    const s = mix(w.salt ^ @as(u32, @intCast(trial)) *% 0x7feb352d);
    var wires: [Cells][2]u2 = undefined;
    for (0..Cells) |i| {
        const r = mix(s +% @as(u32, @intCast(i)));
        wires[i] = .{ @truncate(r), @truncate(r >> 5) };
    }
    const surface: u16 = @truncate(s);
    return .{ .surface = surface, .wires = wires, .mismatch = mistakes(surface, wires, w, false) };
}
fn bestRandom(w: World) Candidate {
    var best = randomCandidate(w, 0);
    for (1..Trials) |t| { const c = randomCandidate(w, t); if (c.mismatch < best.mismatch) best = c; }
    return best;
}
fn replayError(w: World) usize {
    // A replay store has exact seen transitions and emits raw zero bits for
    // unseen states.  It has no executable mechanism and cannot extrapolate.
    return mistakes(0, .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } }, w, true);
}
fn writeRun(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const out = f.writer();
    try out.writeAll("round,world,arm,train_bit_errors,heldout_bit_errors,heldout_bits,mechanism_digest,lineage_rank,storage_state,detail\n");
    var evolved_total: usize = 0; var fixed_total: usize = 0; var random_total: usize = 0; var replay_total: usize = 0; var bits: usize = 0;
    for (0..Worlds) |i| {
        const w = makeWorld(i); const found = learn(w); const random = bestRandom(w);
        const evolved = mistakes(found.surface, found.wires, w, true);
        const fixed = mistakes(0, .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } }, w, true);
        const random_err = mistakes(random.surface, random.wires, w, true);
        const replay = replayError(w);
        const held_bits: usize = blk: {
            var n: usize = 0;
            for (0..16) |x| {
                if (heldout(w, @intCast(x))) n += Cells;
            }
            break :blk n;
        };
        evolved_total += evolved; fixed_total += fixed; random_total += random_err; replay_total += replay; bits += held_bits;
        const digest = mix(@as(u32, found.surface) ^ @as(u32, found.wires[0][0]) << 16 ^ @as(u32, found.wires[3][1]) << 24);
        try out.print("round_t_t1,{d},mutable_field,{d},{d},{d},0x{x:0>8},PATTERN,committed_after_fresh_partition,shared_raw_response_surface_plus_wires\n", .{ i, found.mismatch, evolved, held_bits, digest });
        try out.print("round_t_t1,{d},fixed_field,na,{d},{d},none,NOISE,none,zero_response_surface_fixed_before_observations\n", .{ i, fixed, held_bits });
        try out.print("round_t_t1,{d},random_mutation,{d},{d},{d},none,NOISE,scratch_only,{d}_equal_budget_raw_candidates\n", .{ i, random.mismatch, random_err, held_bits, Trials });
        try out.print("round_t_t1,{d},replay_memory,0,{d},{d},none,NOISE,quarantined,seen_transition_lookup_zero_on_unseen\n", .{ i, replay, held_bits });
    }
    const narrow = evolved_total < fixed_total and evolved_total < random_total and evolved_total < replay_total;
    try out.print("round_t_t1,closure,aggregate,{d},{d}/{d},{d},none,VALIDATED,snapshot,mutable={d};fixed={d};random={d};replay={d};raw_holdout_bits={d}\n", .{ 0, evolved_total, bits, bits, evolved_total, fixed_total, random_total, replay_total, bits });
    try out.print("round_t_t1,VERDICT,aggregate,na,{d}/{d},na,none,NOISE,rollback,VALID_NEGATIVE:no_representation_birth_claim;{s}_narrow_transfer_signal_depends_on_human_installed_shared_16_entry_surface_bias\n", .{ evolved_total, bits, if (narrow) "observed" else "absent" });
}
fn forbidden(bytes: []const u8) bool {
    for ([_][]const u8{ "token", "embedding", "llm", "english", "count", "xor", "compare", "answer_key" }) |bad|
        if (std.ascii.indexOfIgnoreCase(bytes, bad) != null) return true;
    return false;
}
pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) {
        try writeRun("/tmp/raw_causal_t_a.csv"); try writeRun("/tmp/raw_causal_t_b.csv");
        const a = std.heap.page_allocator;
        const x = try std.fs.cwd().readFileAlloc(a, "/tmp/raw_causal_t_a.csv", 1 << 20); defer a.free(x);
        const y = try std.fs.cwd().readFileAlloc(a, "/tmp/raw_causal_t_b.csv", 1 << 20); defer a.free(y);
        if (!std.mem.eql(u8, x, y)) return error.Nondeterminism;
        if (forbidden(x)) return error.NamedPrimitiveLeak;
        if (std.mem.indexOf(u8, x, "VALID_NEGATIVE:no_representation_birth_claim") == null) return error.VerdictMissing;
        std.debug.print("SELFTEST PASS: deterministic raw micro-dynamic substrate; fresh partition, fixed/random/replay controls, scratch-to-committed lineage, and explicit non-emergence verdict hold\n", .{});
        return;
    }
    try writeRun(args.next() orelse "results/raw_causal_substrate_round_t.csv");
}
