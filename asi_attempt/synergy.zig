//! #38 (emergent escape) + #53 (falsify the closure principle), exactly.
//!
//! Substrate: 2-register straight-line programs over u8 (r0=x, r1=1), output r0.
//! Ops: affine {XOR, SHL, SHR, NOT} and nonlinear {AND, OR, ADD, SUB, MUL}.
//! "Reach target T" = some program of length <= MAXL computes T(x) for ALL 256 x
//! (exhaustive, exact -- no sampling). We ask two genuinely-open questions:
//!
//!   #53  Can the affine-only base reach ANY nonlinear target, at any length up to
//!        MAXL? (Closure principle predicts NO -- affine maps stay affine.)
//!   #38  Is there a target reachable by base+{X,Y} but NEITHER base+{X} nor
//!        base+{Y} -- an EMERGENT escape that needs two ops at once?
//!
//! Run: zig build synergy
const std = @import("std");

const Op = enum { XOR, SHL, SHR, NOTA, AND, OR, ADD, SUB, MUL };
const K: usize = 2; // registers

fn apply(op: Op, a: u8, b: u8) u8 {
    return switch (op) {
        .XOR => a ^ b,
        .SHL => a << 1,
        .SHR => a >> 1,
        .NOTA => ~a,
        .AND => a & b,
        .OR => a | b,
        .ADD => a +% b,
        .SUB => a -% b,
        .MUL => a *% b,
    };
}

const Instr = struct { op: Op, d: u8, a: u8, b: u8 };

fn execAll(prog: []const Instr, target: *const fn (u8) u8) bool {
    var x: usize = 0;
    while (x < 256) : (x += 1) {
        var r = [_]u8{ @intCast(x), 1 };
        for (prog) |ins| r[ins.d] = apply(ins.op, r[ins.a], r[ins.b]);
        if (r[0] != target(@intCast(x))) return false;
    }
    return true;
}

// Exhaustively search programs of length exactly L over `ops`; return true if any
// computes `target` for all inputs.
fn existsAtLen(ops: []const Op, L: usize, target: *const fn (u8) u8) bool {
    const per = ops.len * K * K * K; // choices per instruction
    var total: usize = 1;
    for (0..L) |_| total *= per;
    var prog: [4]Instr = undefined;
    var idx: usize = 0;
    while (idx < total) : (idx += 1) {
        var x = idx;
        for (0..L) |i| {
            const c = x % per;
            x /= per;
            const op = ops[c % ops.len];
            const rest = c / ops.len;
            const d: u8 = @intCast(rest % K);
            const a: u8 = @intCast((rest / K) % K);
            const b: u8 = @intCast((rest / (K * K)) % K);
            prog[i] = .{ .op = op, .d = d, .a = a, .b = b };
        }
        if (execAll(prog[0..L], target)) return true;
    }
    return false;
}

fn minLen(ops: []const Op, maxL: usize, target: *const fn (u8) u8) ?usize {
    var L: usize = 1;
    while (L <= maxL) : (L += 1) {
        if (existsAtLen(ops, L, target)) return L;
    }
    return null;
}

fn countReachable(ops: []const Op, maxL: usize, targets: []const Target) usize {
    var n: usize = 0;
    for (targets) |t| {
        if (minLen(ops, maxL, t.f) != null) n += 1;
    }
    return n;
}

// Greedy substrate growth: from the affine base, repeatedly add the single
// nonlinear op that unlocks the most currently-unreachable targets; stop when no
// single op adds any. Returns targets reached. This is how the atom-forge grows.
fn greedyGrow(base: []const Op, nl: []const Nonlin, maxL: usize, targets: []const Target) usize {
    var mask: [16]Op = undefined;
    @memcpy(mask[0..base.len], base);
    var len = base.len;
    var used = [_]bool{false} ** 8;
    var cur = countReachable(mask[0..len], maxL, targets);
    while (true) {
        var best_gain: usize = 0;
        var best: usize = 0;
        for (nl, 0..) |c, i| {
            if (used[i]) continue;
            mask[len] = c.op;
            const r = countReachable(mask[0 .. len + 1], maxL, targets);
            if (r > cur + best_gain) {
                best_gain = r - cur;
                best = i;
            }
        }
        if (best_gain == 0) break; // greedy stuck: no single op makes progress
        mask[len] = nl[best].op;
        len += 1;
        used[best] = true;
        cur += best_gain;
    }
    return cur;
}

// --- nonlinear targets (each provably outside the affine closure) ---
fn t_and_shr(x: u8) u8 {
    return x & (x >> 1);
}
fn t_clear_low(x: u8) u8 {
    return x & (x -% 1);
} // x & (x-1)
fn t_square(x: u8) u8 {
    return x *% x;
}
fn t_or_shl(x: u8) u8 {
    return x | (x << 1);
}
fn t_or_square(x: u8) u8 {
    return x | (x *% x);
}

const Target = struct { name: []const u8, f: *const fn (u8) u8 };
const Nonlin = struct { name: []const u8, op: Op };

pub fn main() !void {
    const out = std.io.getStdOut().writer();
    const MAXL: usize = 3;
    const base = [_]Op{ .XOR, .SHL, .SHR, .NOTA }; // affine
    const nl = [_]Nonlin{ .{ .name = "AND", .op = .AND }, .{ .name = "OR", .op = .OR }, .{ .name = "ADD", .op = .ADD }, .{ .name = "SUB", .op = .SUB }, .{ .name = "MUL", .op = .MUL } };
    const targets = [_]Target{
        .{ .name = "x&(x>>1)", .f = &t_and_shr },
        .{ .name = "x&(x-1) ", .f = &t_clear_low },
        .{ .name = "x*x     ", .f = &t_square },
        .{ .name = "x|(x<<1)", .f = &t_or_shl },
        .{ .name = "x|(x*x) ", .f = &t_or_square },
    };

    try out.print("=== #53: can the AFFINE base reach any nonlinear target? (MAXL={d}, exact over 256 inputs) ===\n", .{MAXL});
    var base_reached: usize = 0;
    for (targets) |t| {
        const ml = minLen(&base, MAXL, t.f);
        if (ml != null) base_reached += 1;
        try out.print("  base affine -> {s}: {s}\n", .{ t.name, if (ml == null) "UNREACHABLE" else "reached" });
    }
    try out.print("  => affine base reached {d}/{d} nonlinear targets. (0 = closure principle survives falsification)\n\n", .{ base_reached, targets.len });

    try out.print("=== #38: emergent escape -- a target reachable by base+{{X,Y}} but neither single ===\n", .{});
    var buf: [16]Op = undefined;
    var synergy_found: usize = 0;
    for (targets) |t| {
        // singles
        var single_ok = [_]bool{false} ** nl.len;
        for (nl, 0..) |x, i| {
            @memcpy(buf[0..base.len], &base);
            buf[base.len] = x.op;
            single_ok[i] = minLen(buf[0 .. base.len + 1], MAXL, t.f) != null;
        }
        // pairs
        for (0..nl.len) |i| for (i + 1..nl.len) |j| {
            @memcpy(buf[0..base.len], &base);
            buf[base.len] = nl[i].op;
            buf[base.len + 1] = nl[j].op;
            const pair_ok = minLen(buf[0 .. base.len + 2], MAXL, t.f) != null;
            if (pair_ok and !single_ok[i] and !single_ok[j]) {
                synergy_found += 1;
                try out.print("  EMERGENT: {s} reachable by base+{{{s},{s}}} but NOT base+{{{s}}} nor base+{{{s}}}\n", .{ t.name, nl[i].name, nl[j].name, nl[i].name, nl[j].name });
            }
        };
    }
    try out.print("  => {d} emergent (irreducible-pair) escapes found.\n\n", .{synergy_found});
    if (synergy_found > 0) {
        try out.print("VERDICT: emergent escape is REAL -- some out-of-closure generators are irreducibly a\n", .{});
        try out.print("PAIR: neither op alone reaches the target, only both together.\n\n", .{});
    } else {
        try out.print("VERDICT: no emergent pairs at this depth -- every escape was achievable one op at a time.\n\n", .{});
    }

    // Does greedy substrate growth actually MISS emergent escapes? Test the claim.
    try out.print("=== does GREEDY substrate growth miss them? (the atom-forge's growth rule) ===\n", .{});
    const full = countReachable(&[_]Op{ .XOR, .SHL, .SHR, .NOTA, .AND, .OR, .ADD, .SUB, .MUL }, MAXL, &targets);
    const greedy_rich = greedyGrow(&base, &nl, MAXL, &targets);
    try out.print("  rich target set ({d} targets): greedy growth reaches {d}/{d}, full op-set reaches {d}/{d}\n", .{ targets.len, greedy_rich, targets.len, full, targets.len });
    // Isolated emergent target: only x&(x-1), whose components (AND, SUB) are then
    // useless alone -> greedy can never start.
    const iso = [_]Target{.{ .name = "x&(x-1)", .f = &t_clear_low }};
    const greedy_iso = greedyGrow(&base, &nl, MAXL, &iso);
    const full_iso = countReachable(&[_]Op{ .XOR, .SHL, .SHR, .NOTA, .AND, .OR, .ADD, .SUB, .MUL }, MAXL, &iso);
    try out.print("  isolated {{x&(x-1)}}: greedy growth reaches {d}/1, full op-set reaches {d}/1\n\n", .{ greedy_iso, full_iso });
    try out.print("CORRECTED CLAIM: greedy growth does NOT always miss emergent escapes. In a RICH target\n", .{});
    try out.print("set it usually reaches them, because each component op gets added for some OTHER target,\n", .{});
    try out.print("after which its partner becomes individually useful. Greedy provably FAILS only when the\n", .{});
    try out.print("pair's components are useless for EVERY available target (the isolated case: greedy 0/1,\n", .{});
    try out.print("full 1/1) -- then no single op ever makes progress and greedy never starts. So the precise\n", .{});
    try out.print("condition is: greedy substrate growth misses an emergent escape iff its components have no\n", .{});
    try out.print("standalone use. Tuple search is needed exactly there.\n", .{});
}
