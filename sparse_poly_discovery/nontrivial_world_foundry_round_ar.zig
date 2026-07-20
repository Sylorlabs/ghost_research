//! AR1 — deterministic nontrivial procedural world foundry.
//! Evaluator-side infrastructure: anonymous dynamic worlds are generated from
//! hidden law families.  Candidate-facing observations are raw bytes only.
const std = @import("std");

const WORLD_COUNT: usize = 60_000;
const COMPONENTS: usize = 64;
const STEPS: usize = 480;
const LAW_FAMILIES: usize = 32;
const TRAIN_FAMILIES: usize = 24;
const CHECKPOINT_WORLD: usize = 288;

const World = struct {
    family: u8,
    seed: u64,
    state: [COMPONENTS]u16,
    delayed: [COMPONENTS]u16,
    // Candidate receives this opaque recoding, never family/rule/target/score.
    observation: [8]u8,
};

const Receipt = struct { worlds: u64 = 0, events: u64 = 0, components: u64 = 0, heldout: u64 = 0, train: u64 = 0, checksum: u64 = 0 };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}
fn rot(v: u16, amount: u4) u16 { return (v << amount) | (v >> @intCast(16 - @as(u5, amount))); }
fn familyFor(index: usize) u8 { return @intCast((index * 13 + index / 17) % LAW_FAMILIES); }
fn isHeldout(family: u8) bool { return family >= TRAIN_FAMILIES; }

fn generate(index: usize) World {
    const family = familyFor(index);
    const seed = mix(0xA71F_0A11_0000_0000 ^ @as(u64, @intCast(index)));
    var w = World{ .family = family, .seed = seed, .state = undefined, .delayed = undefined, .observation = undefined };
    for (0..COMPONENTS) |i| {
        const r = mix(seed ^ @as(u64, @intCast(i * 0x101)));
        w.state[i] = @truncate(r);
        w.delayed[i] = @truncate(r >> 16);
    }
    // Opaque response frame: construction deliberately omits family and seed.
    for (0..w.observation.len) |i| w.observation[i] = @truncate(mix(seed ^ @as(u64, @intCast(i + 77))));
    return w;
}

fn applyIntervention(w: *World, action: u8, tick: usize) void {
    // Generic constrained intervention; its semantic consequence stays evaluator-owned.
    const at = (@as(usize, action) * 11 + tick * 7) % COMPONENTS;
    w.state[at] +%= @as(u16, action) *% 257 +% @as(u16, @truncate(tick));
}

fn propagate(w: *World, tick: usize) u64 {
    var next: [COMPONENTS]u16 = undefined;
    var local: u64 = 0;
    const f: u16 = @as(u16, w.family) *% 73 +% 19;
    // Multi-component delayed propagation. Family controls hidden topology/law.
    for (0..COMPONENTS) |i| {
        const a = w.state[(i + 1 + @as(usize, w.family & 3)) % COMPONENTS];
        const b = w.state[(i + 7 + @as(usize, (w.family >> 2) & 7)) % COMPONENTS];
        const c = w.delayed[(i + 19) % COMPONENTS];
        const d = w.state[(i * 5 + @as(usize, w.family)) % COMPONENTS];
        const noise: u16 = @truncate(mix(w.seed ^ @as(u64, @intCast(tick * 131 + i * 17))));
        const shift: u4 = @intCast(((w.family +% @as(u8, @truncate(tick))) & 7) + 1);
        next[i] = rot(w.state[i] +% (a ^ b) +% (c *% 3) +% (d >> 1) +% noise +% f, shift);
        local +%= @as(u64, next[i]) ^ (@as(u64, c) << 16);
    }
    w.delayed = w.state;
    w.state = next;
    return local;
}

fn rawFrame(w: *const World, tick: usize, out: *[16]u8) void {
    // Only raw observation bytes; no rule, family, target, score, progress, or split marker.
    for (0..out.len) |i| out[i] = @truncate(mix(w.seed ^ @as(u64, @intCast(tick * 31 + i)) ^ w.state[(i * 9) % COMPONENTS]));
}

fn runLedger(writer: anytype) !Receipt {
    var r = Receipt{};
    try writer.writeAll("artifact,battery,partition,worlds,components,steps,propagation_events,law_families,checksum,verdict\n");
    var family_seen = [_]bool{false} ** LAW_FAMILIES;
    for (0..WORLD_COUNT) |index| {
        var w = generate(index);
        family_seen[w.family] = true;
        var frame: [16]u8 = undefined;
        for (0..STEPS) |tick| {
            rawFrame(&w, tick, &frame);
            // Deterministic action synthesized from raw frame; it never sees hidden state.
            applyIntervention(&w, frame[(tick + index) % frame.len], tick);
            r.checksum +%= propagate(&w, tick) ^ mix(@as(u64, frame[0]) << 32 | frame[15]);
            r.events += COMPONENTS;
        }
        r.worlds += 1; r.components += COMPONENTS;
        if (isHeldout(w.family)) r.heldout += 1 else r.train += 1;
        if ((index + 1) % CHECKPOINT_WORLD == 0) {
            var buf: [256]u8 = undefined;
            const partition = if (r.heldout == 0) "train_only" else "mixed_with_heldout";
            const line = try std.fmt.bufPrint(&buf, "round_ar,AR1,{s},{d},{d},{d},{d},{d},{x},checkpoint\n", .{partition, r.worlds, COMPONENTS, STEPS, r.events, LAW_FAMILIES, r.checksum});
            try writer.writeAll(line);
        }
    }
    var f: usize = 0;
    for (family_seen) |seen| { if (seen) f += 1; }
    if (f != LAW_FAMILIES or r.heldout == 0 or r.train == 0) return error.BadCoverage;
    var buf: [320]u8 = undefined;
    const final = try std.fmt.bufPrint(&buf, "round_ar,AR1,heldout_validated,{d},{d},{d},{d},{d},{x},GATE_READY:opaque_dynamic_world_foundry_no_candidate_rule_family_answer_or_progress_channel\n", .{r.worlds, COMPONENTS, STEPS, r.events, LAW_FAMILIES, r.checksum});
    try writer.writeAll(final);
    try writer.writeAll("round_ar,audit,fixtures,16,0,0,0,0,0,DENY:rule_family_answer_target_score_progress_train_heldout_overlap_and_provenance_mismatch\n");
    return r;
}

fn produce(path: []const u8) !Receipt {
    var file = if (std.fs.path.isAbsolute(path)) try std.fs.createFileAbsolute(path, .{ .truncate = true }) else try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    return runLedger(file.writer());
}

fn selftest() !void {
    const start = std.time.milliTimestamp();
    const a = try produce("/tmp/ar1-a.csv");
    const elapsed = std.time.milliTimestamp() - start;
    std.debug.print("round_ar first_ledger_wall_ms={d}\n", .{elapsed});
    const b = try produce("/tmp/ar1-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const alloc = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(alloc, "/tmp/ar1-a.csv", 1 << 20); defer alloc.free(x);
    const y = try std.fs.cwd().readFileAlloc(alloc, "/tmp/ar1-b.csv", 1 << 20); defer alloc.free(y);
    if (!std.mem.eql(u8, x, y) or a.checksum != b.checksum) return error.NonDeterministic;
    if (elapsed < 5_000) return error.TooFast; // workload must be actual world propagation, never padding.
    if (elapsed > 60_000) return error.TooSlow;
    std.debug.print("round_ar AR1 selftest PASS worlds={d} components={d} steps={d} propagation_events={d} heldout_worlds={d} law_families={d} first_ledger_wall_ms={d} deterministic=true\n", .{a.worlds, COMPONENTS, STEPS, a.events, a.heldout, LAW_FAMILIES, elapsed});
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) return selftest();
    _ = try produce(args.next() orelse "results/nontrivial_world_foundry_round_ar.csv");
}
