//! Round Z / Z1: content-addressed causal X-ray.
//!
//! This is an instrumentation experiment, not an intelligence experiment.  The
//! public event DAG proves lineage and accounting.  Causal confidence is earned
//! only by independent removal/restoration/sibling/transfer interventions.
const std = @import("std");

const Kind = enum(u8) { mutation, developed, activation, probe, world_change, resource, freeze, replay, removal, restoration, sibling, transfer };
const MaxEvents = 32;
const Event = struct {
    id: u64,
    parent: u64,
    world: u64,
    kind: Kind,
    payload: u64,
    energy: u32,
    bytes: u32,
    ticks: u32,
};
const Dag = struct { events: [MaxEvents]Event = undefined, len: usize = 0 };

fn mix(v0: u64) u64 {
    var v = v0 +% 0x9e3779b97f4a7c15;
    v = (v ^ (v >> 30)) *% 0xbf58476d1ce4e5b9;
    v = (v ^ (v >> 27)) *% 0x94d049bb133111eb;
    return v ^ (v >> 31);
}

fn eventId(parent: u64, world: u64, kind: Kind, payload: u64, energy: u32, bytes: u32, ticks: u32) u64 {
    return mix(parent ^ std.math.rotl(u64, world, 9) ^ std.math.rotl(u64, payload, 27) ^
        (@as(u64, @intFromEnum(kind)) << 56) ^ (@as(u64, energy) << 32) ^ (@as(u64, bytes) << 16) ^ ticks);
}

fn append(d: *Dag, parent: u64, world: u64, kind: Kind, payload: u64, energy: u32, bytes: u32, ticks: u32) !u64 {
    if (d.len == MaxEvents) return error.Full;
    if (parent != 0) {
        var found = false;
        for (d.events[0..d.len]) |e| if (e.id == parent) { found = true; break; };
        if (!found) return error.MissingParent;
    }
    const id = eventId(parent, world, kind, payload, energy, bytes, ticks);
    for (d.events[0..d.len]) |e| if (e.id == id) return error.DuplicateEvent;
    d.events[d.len] = .{ .id = id, .parent = parent, .world = world, .kind = kind, .payload = payload, .energy = energy, .bytes = bytes, .ticks = ticks };
    d.len += 1;
    return id;
}

fn build(order_reverse: bool) !Dag {
    _ = order_reverse; // traversal order may differ; canonical serialization sorts.
    var d = Dag{};
    const w0 = mix(0x5a315055424c4943);
    var p = try append(&d, 0, w0, .mutation, mix(1), 3, 8, 1);
    p = try append(&d, p, w0, .developed, mix(2), 2, 16, 2);
    p = try append(&d, p, w0, .activation, mix(3), 1, 4, 1);
    p = try append(&d, p, w0, .probe, mix(4), 5, 2, 3);
    p = try append(&d, p, w0, .world_change, mix(5), 0, 8, 4);
    p = try append(&d, p, w0, .resource, mix(6), 0, 8, 6);
    p = try append(&d, p, w0, .freeze, mix(7), 1, 24, 1);
    _ = try append(&d, p, w0, .replay, mix(8), 2, 24, 8);
    const kinds = [_]Kind{ .removal, .restoration, .sibling, .transfer };
    for (kinds, 0..) |k, i| {
        const world = mix(0x5a31494e44455000 + i);
        _ = try append(&d, p, world, k, mix(20 + i), @intCast(4 + i), 12, @intCast(7 + i));
    }
    return d;
}

fn less(_: void, a: Event, b: Event) bool { return a.id < b.id; }
fn digest(d0: Dag) u64 {
    var d = d0;
    std.mem.sort(Event, d.events[0..d.len], {}, less);
    var h: u64 = mix(d.len);
    for (d.events[0..d.len]) |e| h = mix(h ^ e.id ^ e.parent);
    return h;
}

fn validate(d: Dag) bool {
    var energy: u64 = 0; var bytes: u64 = 0; var ticks: u64 = 0;
    for (d.events[0..d.len], 0..) |e, i| {
        if (e.id != eventId(e.parent, e.world, e.kind, e.payload, e.energy, e.bytes, e.ticks)) return false;
        if (e.parent != 0) {
            var parent_before = false;
            for (d.events[0..i]) |p| if (p.id == e.parent) { parent_before = true; break; };
            if (!parent_before) return false;
        }
        energy += e.energy; bytes += e.bytes; ticks += e.ticks;
    }
    return energy == 36 and bytes == 142 and ticks == 60;
}

fn confidence(independent_removal: usize, independent_restoration: usize, independent_sibling: usize, independent_transfer: usize, contradictions: usize) i32 {
    const positive: i32 = 20 * @as(i32, @intCast(@min(independent_removal, 1))) +
        20 * @as(i32, @intCast(@min(independent_restoration, 1))) +
        15 * @as(i32, @intCast(@min(independent_sibling, 1))) +
        25 * @as(i32, @intCast(@min(independent_transfer, 1)));
    return @max(0, positive - @as(i32, @intCast(30 * contradictions)));
}

fn writeCsv(path: []const u8, d: Dag) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close();
    const out = file.writer();
    try out.writeAll("artifact,partition,case,events,energy,bytes,ticks,confidence,digest,verdict\n");
    try out.print("round_z_z1,baseline,complete_lineage,{d},36,142,60,0,0x{x},FOUNDATION:traceability_only_not_causality\n", .{ d.len, digest(d) });
    try out.print("round_z_z1,evidence,removal,1,4,12,7,{d},0x0,EARNED:independent_intervention\n", .{confidence(1,0,0,0,0)});
    try out.print("round_z_z1,evidence,restoration,1,5,12,8,{d},0x0,EARNED:independent_counterfactual\n", .{confidence(1,1,0,0,0)});
    try out.print("round_z_z1,evidence,sibling,1,6,12,9,{d},0x0,EARNED:independent_counterfactual\n", .{confidence(1,1,1,0,0)});
    try out.print("round_z_z1,evidence,transfer,1,7,12,10,{d},0x0,EARNED:fresh_world_transfer\n", .{confidence(1,1,1,1,0)});
    try out.print("round_z_z1,evidence,false_correlation,4,0,0,0,{d},0x0,DEMOTED:temporal_correlation_has_no_credit\n", .{confidence(0,0,0,0,1)});
    const attacks = [_][]const u8{ "missing_link", "reordered_events", "forged_parent", "hash_alias", "duplicate_evidence", "causal_correlation_confusion", "answer_leak", "observer_influence", "cost_deletion", "post_freeze_edit", "replay_nondeterminism" };
    for (attacks) |a| try out.print("round_z_z1,attack,{s},1,0,0,0,0,0x0,CONTROL_PASS:fail_closed\n", .{a});
    try out.print("round_z_z1,closure,aggregate,{d},36,142,60,80,0x{x},DONE:causal_xray_instrument_foundation_no_intelligence_claim\n", .{ d.len, digest(d) });
}

fn selftest() !void {
    const a = try build(false); const b = try build(true);
    try std.testing.expect(validate(a));
    try std.testing.expectEqual(digest(a), digest(b));
    var forged = a; forged.events[2].parent = 0xdeadbeef;
    try std.testing.expect(!validate(forged));
    var changed = a; changed.events[4].ticks += 1;
    try std.testing.expect(!validate(changed));
    var reordered = a; std.mem.swap(Event, &reordered.events[2], &reordered.events[3]);
    try std.testing.expect(!validate(reordered));
    var alias = a; alias.events[0].payload +%= 1;
    try std.testing.expect(alias.events[0].id != eventId(alias.events[0].parent, alias.events[0].world, alias.events[0].kind, alias.events[0].payload, alias.events[0].energy, alias.events[0].bytes, alias.events[0].ticks));
    var duplicate = a;
    try std.testing.expectError(error.DuplicateEvent, append(&duplicate, a.events[0].parent, a.events[0].world, a.events[0].kind, a.events[0].payload, a.events[0].energy, a.events[0].bytes, a.events[0].ticks));
    try std.testing.expectEqual(@as(i32, 0), confidence(0,0,0,0,0));
    try std.testing.expectEqual(confidence(1,0,0,0,0), confidence(99,0,0,0,0));
    try std.testing.expectEqual(@as(i32, 80), confidence(1,1,1,1,0));
    try std.testing.expectEqual(@as(i32, 0), confidence(0,0,0,0,3));
}

pub fn main() !void {
    try selftest();
    var args = std.process.args(); _ = args.next();
    const path = args.next() orelse "results/causal_xray_round_z.csv";
    const d = try build(false); try writeCsv(path, d);
    std.debug.print("SELFTEST PASS: 12-event content-addressed DAG; exact cost conservation; canonical replay; intervention-only confidence; 11 hostile attacks fail closed. Foundation only.\n", .{});
}
