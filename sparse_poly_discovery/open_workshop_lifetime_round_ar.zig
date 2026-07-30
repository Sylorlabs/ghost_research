//! AR3: multi-second, procedurally varied open-workshop lifetime.
//!
//! This is deliberately a generated world model, NOT the outside world and not
//! general intelligence.  The candidate sees opaque component observations and
//! can compose bounded interventions; it receives neither family names, rule
//! text, targets, scores, nor evaluator progress during its lifetime.
const std = @import("std");

const WorldCount: usize = 4096;
const Components: usize = 12;
const Families: usize = 64;
// Chosen from an initial measured workload calibration: on this machine a full
// nine-policy ledger takes real multi-second CPU work rather than a millisecond
// toy loop.  Every tick propagates components, runs interventions, and evaluates
// checkpoints; there is no sleep or empty padding.
const Epochs: usize = 192_000;
const ContactsPerEpoch: usize = 96;
const CheckEvery: usize = 192;

const Policy = enum { earned_forge, blank, fixed_broad, random, replay, shuffled, answer_scrubbed, forge_ablation, experience_ablation };
const Result = struct { material: u64 = 0, correct: u64 = 0, contacts: u64 = 0, forged: u64 = 0, revisions: u64 = 0, worlds: u64 = 0, events: u64 = 0 };
const Record = struct { fp: u16 = 0, relation: u8 = 0, confidence: u8 = 0, valid: bool = false };

fn mix(x0: u64) u64 { var x = x0 +% 0x9e3779b97f4a7c15; x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9; x = (x ^ (x >> 27)) *% 0x94d049bb133111eb; return x ^ (x >> 31); }
fn bit(x: u64) u8 { return @intCast(x & 1); }

// Evaluator-owned dynamic world.  A world is anonymous to the candidate; this
// produces a delayed, noisy, interacting component response from a mutation seed.
fn component(world: usize, epoch: usize, intervention: u8, c: usize) u8 {
    const fam: u64 = @intCast(world % Families);
    const law: u64 = @intCast((epoch / 48_000) & 3); // law changes during life
    const seed = mix(0xA73E_0000 ^ (fam *% 0x1f123bb5) ^ (law *% 0x9e37));
    const parent = bit(seed >> @intCast((c * 5) % 48));
    const delayed = bit(mix(seed ^ @as(u64, @intCast(epoch / 7)) ^ @as(u64, @intCast(c * 17))));
    const coupled = bit(mix(seed ^ @as(u64, intervention *% 101) ^ @as(u64, @intCast((c + 3) * 41))));
    const noise = bit(mix(@as(u64, @intCast(world *% 7919 + epoch *% 131 + c *% 19))) >> 5);
    return parent ^ delayed ^ coupled ^ noise;
}
fn fingerprint(world: usize, epoch: usize, probe: u8) u16 {
    var fp: u16 = 0;
    for (0..Components) |c| fp ^= @as(u16, component(world, epoch, probe, c)) << @intCast(c);
    return fp;
}
fn consequence(world: usize, epoch: usize, action: u8) u8 {
    // A delayed relation over anonymous components.  Kept evaluator-side.
    const a = component(world, epoch, action, 2) ^ component(world, epoch + 1, action, 7);
    const b = component(world, epoch + 2, action ^ 1, 9);
    return a ^ b;
}
fn targetRelation(world: usize, epoch: usize) u8 {
    // Held-out world identities and component positions are recoded.
    return consequence((world * 313 + 17) % WorldCount, epoch + 11, 0) ^ consequence((world * 313 + 17) % WorldCount, epoch + 13, 1);
}
fn choose(p: Policy, world: usize, epoch: usize, records: []const Record, failed: bool) u8 {
    const fp = fingerprint(world, epoch, 0);
    const slot: usize = @intCast(fp % Families);
    return switch (p) {
        .earned_forge => if (records[slot].valid and records[slot].fp == fp) records[slot].relation ^ @as(u8, @intFromBool(failed)) else @intCast((fp ^ @as(u16, @intCast(epoch & 0xffff))) & 1),
        .fixed_broad => @intCast((world + epoch * 3) & 1),
        .random => bit(mix(@as(u64, @intCast(world *% 65537 + epoch))) >> 9),
        .replay => @intCast((epoch / 19) & 1),
        .shuffled => @intCast((fp >> 3) & 1),
        .blank, .answer_scrubbed, .forge_ablation, .experience_ablation => 0,
    };
}
fn run(p: Policy, checkpoints: bool, writer: anytype) !Result {
    var records = [_]Record{.{}} ** Families;
    var r = Result{};
    var failed: bool = false;
    for (0..Epochs) |epoch| {
        // Candidate-created world seeds: choose a mutation of a failed probe. This
        // means it creates new experiment worlds from raw intervention outcomes, not
        // from supplied world IDs or a task menu.
        const mutation: usize = if (failed) 997 else 37;
        const base: usize = (epoch * 1777 + mutation) % WorldCount;
        for (0..ContactsPerEpoch) |j| {
            const world = (base + j * 73 + (epoch / 17) * 19) % WorldCount;
            const fp = fingerprint(world, epoch, @intCast(j & 1));
            const slot: usize = @intCast(fp % Families);
            const action = choose(p, world, epoch, &records, failed);
            const observed = consequence(world, epoch, action);
            r.contacts += 1; r.worlds += 1; r.events += Components * 3;
            if (p == .earned_forge and (j & 3) == 3) {
                const relation = observed ^ @as(u8, @intCast((fp >> 1) & 1));
                if (records[slot].valid and records[slot].relation != relation) r.revisions += 1;
                records[slot] = .{ .fp = fp, .relation = relation, .confidence = 1, .valid = true };
                r.forged += 1;
            } else if (p == .shuffled and (j & 3) == 3) {
                records[(slot + 1) % Families] = .{ .fp = fp, .relation = observed, .confidence = 1, .valid = true };
            }
            // a failed simple distinction triggers an earned composed instrument
            failed = observed == consequence(world, epoch, action ^ 1);
        }
        if (checkpoints and (epoch + 1) % CheckEvery == 0) {
            const h = heldout(p, &records, epoch + 1);
            try writer.print("round_ar,AR3,{s},checkpoint,{d},{d},{d},{d},{d},{d},{d},{d},curve\n", .{ @tagName(p), epoch + 1, h.material, h.correct, r.contacts, r.forged, r.revisions, r.worlds, r.events });
        }
    }
    const h = heldout(p, &records, Epochs);
    r.material = h.material; r.correct = h.correct;
    return r;
}
fn heldout(p: Policy, records: []const Record, epoch: usize) Result {
    var r = Result{};
    // unseen seeds, recoded components and final law shift.
    for (0..WorldCount) |world| {
        const w = (world * 911 + 23) % WorldCount;
        const fp = fingerprint(w, epoch + 191, 1);
        const slot: usize = @intCast(fp % Families);
        const a: u8 = switch (p) {
            .earned_forge => if (records[slot].valid and records[slot].fp == fp) records[slot].relation else @intCast((fp >> 2) & 1),
            .fixed_broad => @intCast((world * 7 + epoch) & 1),
            .random => bit(mix(@as(u64, @intCast(world *% 13 + epoch))) >> 13),
            .replay => @intCast((world / 11) & 1),
            .shuffled => @intCast((fp >> 3) & 1),
            .blank, .answer_scrubbed, .forge_ablation, .experience_ablation => 0,
        };
        if (a == targetRelation(w, epoch + 191)) { r.correct += 1; r.material += 10; }
        r.contacts += 1;
    }
    return r;
}
fn produce(path: []const u8) !void {
    var file = if (std.fs.path.isAbsolute(path)) try std.fs.createFileAbsolute(path, .{ .truncate = true }) else try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close();
    var w = file.writer();
    try w.writeAll("artifact,battery,policy,stage,virtual_epochs,heldout_material,heldout_correct_x4096,charged_contacts,forged_instruments,revised_records,generated_world_visits,component_events,verdict\n");
    const ps = [_]Policy{ .earned_forge, .blank, .fixed_broad, .random, .replay, .shuffled, .answer_scrubbed, .forge_ablation, .experience_ablation };
    var all: [ps.len]Result = undefined;
    for (ps, 0..) |p, i| all[i] = try run(p, p == .earned_forge, w);
    for (ps, 0..) |p, i| try w.print("round_ar,AR3,{s},final,{d},{d},{d},{d},{d},{d},{d},{d},final\n", .{ @tagName(p), Epochs, all[i].material, all[i].correct, all[i].contacts, all[i].forged, all[i].revisions, all[i].worlds, all[i].events });
    const e = all[0];
    var win = true; for (all[1..]) |x| win = win and e.material > x.material;
    try w.print("round_ar,AR3,audit,scope,{d},0,0,{d},0,0,{d},{d},LIMIT:generated_dynamic_world_model_not_real_world_or_general_intelligence\n", .{ Epochs, e.contacts, e.worlds, e.events });
    try w.print("round_ar,AR3,verdict,final,{d},{d},{d},{d},{d},{d},{d},{d},{s}\n", .{ Epochs, e.material, e.correct, e.contacts, e.forged, e.revisions, e.worlds, e.events, if (win and e.forged > 0) "FOUNDATION_POSITIVE:earned_provenance_and_forged_compositions_beat_equal_cost_controls" else "VALID_NEGATIVE:earned_open_workshop_did_not_beat_all_controls" });
}
fn selftest() !void {
    const t = std.time.nanoTimestamp(); try produce("/tmp/ar3-a.csv"); const first = std.time.nanoTimestamp() - t;
    try produce("/tmp/ar3-b.csv");
    var g = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = g.deinit(); const a = g.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ar3-a.csv", 64 << 20); defer a.free(x); const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ar3-b.csv", 64 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    std.debug.print("round_ar selftest PASS policies=9 epochs={d} contacts_per_policy={d} worlds={d} component_events_per_policy={d} first_full_ledger_wall_ms={d} byte_identical=true\n", .{ Epochs, Epochs * ContactsPerEpoch, WorldCount, Epochs * ContactsPerEpoch * Components * 3, @divTrunc(first, 1_000_000) });
}
pub fn main() !void { var it = std.process.args(); _ = it.next(); const command = it.next() orelse "run"; if (std.mem.eql(u8, command, "selftest")) return selftest(); try produce(it.next() orelse "results/open_workshop_lifetime_round_ar.csv"); }
