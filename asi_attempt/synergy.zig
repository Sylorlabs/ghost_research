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
        try out.print("PAIR: neither op alone makes progress, only both together. Implication: greedy\n", .{});
        try out.print("one-op-at-a-time substrate growth (e.g. the atom-forge) PROVABLY MISSES these --\n", .{});
        try out.print("you must add ops simultaneously. A non-obvious refinement of the closure principle.\n", .{});
    } else {
        try out.print("VERDICT: no emergent pairs at this depth -- every escape was achievable one op at a time.\n", .{});
    }
}
