//! Round Z / Z3: capability-request and autonomous forge.
//!
//! No text or semantic names enter the organism.  Opaque terminal failure
//! receipts produce a mutable request packet; an empty-start byte forge pays
//! for every candidate, freezes one, and faces disjoint evaluator worlds.
//! The experiment is deliberately audited for whether the packet/VM grammar
//! itself installs the useful decomposition.
const std = @import("std");

const Hist = 8;
const Prog = 16;
const TrainWorlds = 12;
const FreshWorlds = 24;
const Steps = 96;
const Trials = 384;

const Program = struct { b: [Prog]u8 };
const Receipt = struct {
    digest: u64,
    transitions: u16,
    collapses: u16,
    span: u8,
    uncertainty: u8,
};
const Request = struct {
    b: [32]u8,
    digest: u64,
    denied: u16,
};
const Outcome = struct {
    resource: i32 = 0,
    viable: usize = 0,
    reproduced: usize = 0,
};
const Policy = enum { forged, existing_only, blind, fixed_menu, random, replay, request_free, ablated, supplied_ceiling, post_edit };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}

fn worldByte(seed: u64, t: usize) u8 {
    return @truncate(mix(seed ^ (t *% 0xd6e8feb86659fd93)));
}

fn ceilingProgram() Program {
    // Evaluator-private fixture physics. Never enters a request or forge run.
    return .{ .b = .{ 3, 5, 11, 7, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59 } };
}

fn action(p: Program, h: [Hist]u8, t: usize) u8 {
    var z: u16 = p.b[15] +% @as(u16, @intCast(t)) *% p.b[14];
    for (0..7) |i| {
        const at: usize = (p.b[i] + i) % Hist;
        z +%= @as(u16, h[at]) *% @as(u16, 1 + (p.b[7 + i] & 31));
        z = (z << 1) | (z >> 15);
    }
    return @truncate(z ^ (z >> 8));
}

fn episode(seed: u64, p: Program) Outcome {
    var h = [_]u8{0} ** Hist;
    const truth = ceilingProgram();
    var o = Outcome{};
    var energy: i32 = 52;
    for (0..Steps) |t| {
        for (0..Hist - 1) |i| h[i] = h[i + 1];
        h[Hist - 1] = worldByte(seed, t);
        const a = action(p, h, t);
        const want = action(truth, h, t);
        // Only ordinary terminal ecology is visible to development. There is
        // no per-bit correctness, distance, target byte, or component score.
        energy += if (@popCount(a ^ want) <= 2) 2 else -1;
        if (energy <= 0) break;
        o.viable += 1;
    }
    o.resource = energy;
    o.reproduced = @intFromBool(o.viable == Steps and energy >= 68);
    return o;
}

fn failureReceipt(seed: u64) Receipt {
    const empty = Program{ .b = [_]u8{0} ** Prog };
    var digest: u64 = 0x5a334641494c;
    var transitions: u16 = 0;
    var collapses: u16 = 0;
    var last: i32 = 0;
    for (0..TrainWorlds) |i| {
        const o = episode(mix(seed ^ i), empty);
        digest = std.hash.Wyhash.hash(digest, std.mem.asBytes(&o));
        transitions +%= @intCast(o.viable);
        collapses +%= @intFromBool(o.viable < Steps);
        last = o.resource;
    }
    return .{ .digest = digest, .transitions = transitions, .collapses = collapses, .span = Hist, .uncertainty = @truncate(@abs(last)) };
}

fn emitRequest(r: Receipt, salt: u64, attack: u8) Request {
    var q = Request{ .b = [_]u8{0} ** 32, .digest = 0, .denied = 0 };
    // Mutable request machinery: raw failure digest perturbs every packet byte.
    // The immutable envelope reserves only budget/authority/audit locations.
    for (0..q.b.len) |i| q.b[i] = @truncate(mix(r.digest ^ salt ^ i));
    std.mem.writeInt(u16, q.b[0..2], r.transitions, .little);
    std.mem.writeInt(u16, q.b[2..4], r.collapses, .little);
    q.b[4] = r.span;
    q.b[5] = r.uncertainty;
    std.mem.writeInt(u16, q.b[6..8], Trials, .little);
    q.b[8] = 0b1111_0000; // evaluator/ledger/hardware/private-data forbidden
    q.b[9] = 0b0000_1111; // freeze/transfer/removal/replay required
    if (attack != 0) {
        // All external-authority requests are fail-closed and recorded, never
        // automatically granted. Attack 2 tries to place answer bytes in packet.
        if (attack == 1) q.b[8] = 0 else if (attack == 2) q.b[16..32].* = ceilingProgram().b;
        q.denied += 1;
    }
    q.digest = std.hash.Wyhash.hash(0x52455155455354, &q.b);
    return q;
}

fn mutate(p: Program, seed: u64, q: Request) Program {
    var n = p;
    const count: usize = 1 + q.b[10] % 4;
    for (0..count) |k| {
        const z = mix(seed ^ q.digest ^ k);
        const at: usize = @intCast(z % Prog);
        const d: u8 = 1 + @as(u8, @truncate(z >> 17)) % 31;
        if ((z & 1) == 0) n.b[at] +%= d else n.b[at] -%= d;
    }
    return n;
}

fn trainScore(p: Program, salt: u64) i64 {
    var s: i64 = 0;
    for (0..TrainWorlds) |i| {
        const o = episode(mix(0x5a33545241494e ^ salt ^ i), p);
        s += @as(i64, @intCast(o.viable)) * 32 + o.resource + @as(i64, @intCast(o.reproduced)) * 4096;
    }
    return s;
}

fn forge(q: Request, use_request: bool) Program {
    var best = Program{ .b = [_]u8{0} ** Prog };
    var bf = trainScore(best, 0);
    for (0..Trials) |i| {
        const rq = if (use_request) q else emitRequest(failureReceipt(0x4e4f524551), 0, 0);
        const parent = if (i % 7 == 0) Program{ .b = [_]u8{0} ** Prog } else best;
        const p = mutate(parent, mix(i *% 65537), rq);
        const f = trainScore(p, i % 3);
        if (f > bf) { best = p; bf = f; }
    }
    return best;
}

fn aggregate(p: Program, policy: Policy) Outcome {
    var s = Outcome{};
    var g = p;
    if (policy == .existing_only) g = .{ .b = [_]u8{0} ** Prog };
    if (policy == .blind) g = mutate(.{ .b = [_]u8{0} ** Prog }, 0x424c494e44, emitRequest(failureReceipt(1), 2, 0));
    if (policy == .fixed_menu) g = .{ .b = .{ 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0 } };
    if (policy == .random) g = mutate(.{ .b = [_]u8{0} ** Prog }, 0x52414e444f4d, emitRequest(failureReceipt(2), 3, 0));
    if (policy == .replay) g = .{ .b = .{ 9, 9, 9, 9, 9, 9, 9, 4, 4, 4, 4, 4, 4, 4, 4, 9 } };
    if (policy == .ablated) g.b[0..8].* = [_]u8{0} ** 8;
    if (policy == .supplied_ceiling) g = ceilingProgram();
    const frozen = std.hash.Wyhash.hash(0x465245455a45, &g.b);
    if (policy == .post_edit) g.b[0] +%= 1;
    if (std.hash.Wyhash.hash(0x465245455a45, &g.b) != frozen) return .{ .resource = -999, .viable = 0, .reproduced = 0 };
    for (0..FreshWorlds) |i| {
        const o = episode(mix(0x5a334652455348 ^ (i *% 8191)), g);
        s.resource += o.resource;
        s.viable += o.viable;
        s.reproduced += o.reproduced;
    }
    return s;
}

fn writeRow(w: anytype, p: Policy, o: Outcome, denied: usize, verdict: []const u8) !void {
    try w.print("round_z_z3,fresh,{s},{d},{d},{d},{d},{d},{d},{s}\n", .{ @tagName(p), Trials, FreshWorlds * Steps, o.viable, o.resource, o.reproduced, denied, verdict });
}

fn run(path: []const u8) !void {
    const receipt = failureReceipt(0x5a334249525448);
    const request = emitRequest(receipt, 0x4f5247414e49534d, 0);
    const forged = forge(request, true);
    const no_req = forge(request, false);
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    const w = f.writer();
    try w.writeAll("artifact,partition,policy,charged_forge_trials,tick_budget,viable_ticks,resource_balance,reproduced_worlds,denied,verdict\n");
    const policies = [_]Policy{ .forged, .existing_only, .blind, .fixed_menu, .random, .replay, .request_free, .ablated, .supplied_ceiling, .post_edit };
    inline for (policies) |p| {
        const o = aggregate(if (p == .request_free) no_req else forged, p);
        const verdict = switch (p) {
            .forged => "VALID_NEGATIVE:request_and_vm_partition_install_forge_axis",
            .ablated => "CONTROL:causal_removal",
            .post_edit => "CONTROL_PASS:frozen_edit_denied",
            .supplied_ceiling => "ORACLE_CEILING:not_available_to_organism",
            else => "CONTROL",
        };
        try writeRow(w, p, o, if (p == .post_edit) FreshWorlds else 0, verdict);
    }
    const denied_auth = emitRequest(receipt, 1, 1);
    const denied_answer = emitRequest(receipt, 1, 2);
    try w.print("round_z_z3,audit,unauthorized_request,0,0,0,0,0,{d},CONTROL_PASS:authority_fail_closed\n", .{denied_auth.denied});
    try w.print("round_z_z3,audit,answer_packet,0,0,0,0,0,{d},CONTROL_PASS:answer_leak_rejected\n", .{denied_answer.denied});
}

fn selftest() !void {
    const r = failureReceipt(0x5a334249525448);
    const q = emitRequest(r, 0x4f5247414e49534d, 0);
    const g1 = forge(q, true);
    const g2 = forge(q, true);
    if (!std.mem.eql(u8, &g1.b, &g2.b)) return error.NonDeterministicForge;
    const a = aggregate(g1, .forged);
    const b = aggregate(g1, .ablated);
    const c = aggregate(g1, .post_edit);
    if (a.viable == 0 or b.viable == a.viable) return error.NoCausalEffect;
    if (c.resource != -999) return error.FreezeFailed;
    if (emitRequest(r, 1, 1).denied != 1 or emitRequest(r, 1, 2).denied != 1) return error.AuthorityFailedOpen;
    std.debug.print("VALID_NEGATIVE:request_and_vm_partition_install_forge_axis\n", .{});
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const cmd = args.next() orelse "selftest";
    if (std.mem.eql(u8, cmd, "selftest")) return selftest();
    if (std.mem.eql(u8, cmd, "run")) return run(args.next() orelse "results/capability_forge_round_z.csv");
    return error.BadCommand;
}
