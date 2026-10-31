//! I53 — Falsification attack on the Closure Principle (2026-07-10).
//!
//! Standalone re-implementation of the synergy.zig substrate (straight-line
//! register programs, r0=x, r1=1, output r0) generalized over:
//!   - domain width W (u1, u2, u4, u8)   -> attack (a): boundary abuse / vacuity
//!   - search depth (BFS with dedup, far beyond the repo's MAXL=3)
//!                                        -> attack (b): depth-limited closure?
//!   - register count K (2, 3, 5)        -> attack (b'): op-closure vs register bound
//!
//! Attacked claims (CLOSURE_PRINCIPLE.md "Refinement" block + emergent_escape.md):
//!   C1: "x&(x-1) needs {AND,SUB}"   (stated WITHOUT depth/register qualifiers)
//!   C2: "x|(x*x) needs {OR,MUL}"    (same)
//!   C3: "the affine base reaches 0/5 nonlinear targets" (claimed as closure fact)
//!
//! Methods:
//!   1. Exact BFS with state dedup over (r0..rK-1) truth tables: min-depth
//!      reachability, and where the reachable set SATURATES (fixpoint), an exact
//!      INFINITE-depth closure answer — strictly stronger than the repo's MAXL=3.
//!   2. Hand-constructed explicit witness programs, verified exhaustively over
//!      every input, that compute the pair-claim targets WITHOUT either op of
//!      the claimed necessary pair (using one or three extra registers).
//!   3. Width-boundary enumeration: at W=1 and W=2 several of the five
//!      "provably outside the affine closure" targets are in fact affine.
//!
//! Build:  zig build-exe -O ReleaseFast falsify_closure_i53.zig
//! Run:    ./falsify_closure_i53          (single thread, bounded memory)

const std = @import("std");

// ---------------------------------------------------------------- ops -------

const Op = enum(u8) {
    XOR,
    SHL,
    SHR,
    NOTA,
    AND,
    OR,
    ADD,
    SUB,
    MUL,

    fn isUnary(self: Op) bool {
        return self == .SHL or self == .SHR or self == .NOTA;
    }
    fn name(self: Op) []const u8 {
        return switch (self) {
            .XOR => "XOR",
            .SHL => "SHL",
            .SHR => "SHR",
            .NOTA => "NOT",
            .AND => "AND",
            .OR => "OR ",
            .ADD => "ADD",
            .SUB => "SUB",
            .MUL => "MUL",
        };
    }
};

inline fn applyScalar(comptime op: Op, x: u8, y: u8, mask: u8) u8 {
    return switch (op) {
        .XOR => x ^ y,
        .SHL => (x << 1) & mask,
        .SHR => x >> 1,
        .NOTA => (~x) & mask,
        .AND => x & y,
        .OR => x | y,
        .ADD => (x +% y) & mask,
        .SUB => (x -% y) & mask,
        .MUL => (x *% y) & mask,
    };
}

fn applyScalarRt(op: Op, x: u8, y: u8, mask: u8) u8 {
    return switch (op) {
        inline else => |o| applyScalar(o, x, y, mask),
    };
}

// ------------------------------------------------------------- targets ------

const TargetDef = struct { name: []const u8, f: *const fn (u16, u8) u8 };

fn tAndShr(x: u16, mask: u8) u8 {
    const b: u8 = @intCast(x);
    return (b & (b >> 1)) & mask;
}
fn tClearLow(x: u16, mask: u8) u8 {
    const b: u8 = @intCast(x);
    return (b & ((b -% 1) & mask)) & mask;
}
fn tSquare(x: u16, mask: u8) u8 {
    return @intCast((x * x) & mask);
}
fn tOrShl(x: u16, mask: u8) u8 {
    const b: u8 = @intCast(x);
    return (b | ((b << 1) & mask)) & mask;
}
fn tOrSquare(x: u16, mask: u8) u8 {
    const sq: u8 = @intCast((x * x) & mask);
    const b: u8 = @intCast(x);
    return (b | sq) & mask;
}

const target_defs = [_]TargetDef{
    .{ .name = "x&(x>>1)", .f = &tAndShr },
    .{ .name = "x&(x-1) ", .f = &tClearLow },
    .{ .name = "x*x     ", .f = &tSquare },
    .{ .name = "x|(x<<1)", .f = &tOrShl },
    .{ .name = "x|(x*x) ", .f = &tOrSquare },
};

// Is a truth table an affine GF(2) map y = Mx + c ? (exact test on all pairs)
fn isAffineTt(tt: []const u8) bool {
    const n = tt.len;
    const c = tt[0];
    var x: usize = 0;
    while (x < n) : (x += 1) {
        var y: usize = 0;
        while (y < n) : (y += 1) {
            if (tt[x ^ y] != (tt[x] ^ tt[y] ^ c)) return false;
        }
    }
    return true;
}

// -------------------------------------------------------- BFS engine --------

fn Engine(comptime W: u4, comptime K: usize) type {
    return struct {
        const Self = @This();
        pub const N: usize = @as(usize, 1) << W;
        pub const MASK: u8 = @intCast((@as(u16, 1) << W) - 1);
        pub const Tt = [N]u8;
        pub const State = struct { r: [K]Tt };
        const Meta = struct { parent: u32, instr: u16 };
        const MAXD = 16;

        fn applyTt(op: Op, a: *const Tt, b: *const Tt, out: *Tt) void {
            switch (op) {
                inline else => |o| {
                    for (0..N) |i| out[i] = applyScalar(o, a[i], b[i], MASK);
                },
            }
        }

        fn stateKey(s: *const State) u128 {
            var h1 = std.hash.Wyhash.init(0x9E3779B97F4A7C15);
            var h2 = std.hash.Wyhash.init(0xC2B2AE3D27D4EB4F);
            for (0..K) |i| {
                h1.update(&s.r[i]);
                h2.update(&s.r[i]);
            }
            return (@as(u128, h1.final()) << 64) | h2.final();
        }

        fn r0Key(t: *const Tt) u128 {
            const a = std.hash.Wyhash.hash(0xA076_1D64_78BD_642F, t);
            const b = std.hash.Wyhash.hash(0xE703_7ED1_A0B4_28DB, t);
            return (@as(u128, a) << 64) | b;
        }

        pub const TargetTrack = struct {
            name: []const u8,
            tt: Tt,
            found_depth: ?u32 = null,
            prog: [MAXD]u16 = [_]u16{0} ** MAXD,
        };

        pub const Outcome = struct {
            fixpoint: bool = false,
            hit_state_cap: bool = false,
            hit_time_cap: bool = false,
            depth_completed: u32 = 0,
            states_total: usize = 0,
            distinct_r0: usize = 0,
        };

        pub fn makeTargets() [target_defs.len]TargetTrack {
            var out: [target_defs.len]TargetTrack = undefined;
            for (target_defs, 0..) |td, i| {
                out[i] = .{ .name = td.name, .tt = undefined };
                for (0..N) |x| out[i].tt[x] = td.f(@intCast(x), MASK);
            }
            return out;
        }

        pub fn bfs(
            alloc: std.mem.Allocator,
            ops: []const Op,
            targets: []TargetTrack,
            max_depth: u32,
            max_states: usize,
            budget_ns: u64,
        ) !Outcome {
            var out = Outcome{};
            var timer = try std.time.Timer.start();

            var variants = std.ArrayList(u16).init(alloc);
            defer variants.deinit();
            for (ops) |op| {
                const nb: usize = if (op.isUnary()) 1 else K;
                for (0..K) |d| {
                    for (0..K) |a| {
                        for (0..nb) |b| {
                            const code: u16 = (@as(u16, @intFromEnum(op)) << 6) |
                                (@as(u16, @intCast(d)) << 4) |
                                (@as(u16, @intCast(a)) << 2) |
                                @as(u16, @intCast(b));
                            try variants.append(code);
                        }
                    }
                }
            }

            var visited = std.AutoHashMap(u128, void).init(alloc);
            defer visited.deinit();
            try visited.ensureTotalCapacity(@intCast(max_states + 256));
            var r0set = std.AutoHashMap(u128, void).init(alloc);
            defer r0set.deinit();

            var metas = std.ArrayList([]Meta).init(alloc);
            defer {
                for (metas.items) |m| alloc.free(m);
                metas.deinit();
            }

            var cur = std.ArrayList(State).init(alloc);
            defer cur.deinit();

            var start: State = undefined;
            for (0..N) |i| start.r[0][i] = @intCast(i);
            for (0..N) |i| start.r[1][i] = 1;
            if (K > 2) {
                for (2..K) |ri| {
                    for (0..N) |i| start.r[ri][i] = 0;
                }
            }
            try cur.append(start);
            visited.putAssumeCapacity(stateKey(&start), {});
            try r0set.put(r0Key(&start.r[0]), {});
            for (targets) |*t| {
                if (std.mem.eql(u8, &t.tt, &start.r[0])) t.found_depth = 0;
            }

            var depth: u32 = 0;
            while (depth < max_depth) {
                const d = depth + 1;
                var next = std.ArrayList(State).init(alloc);
                var meta_list = std.ArrayList(Meta).init(alloc);
                var stop = false;
                var tick: usize = 0;

                for (cur.items, 0..) |*st, si| {
                    for (variants.items) |code| {
                        tick += 1;
                        if ((tick & 0x1FFF) == 0 and timer.read() > budget_ns) {
                            out.hit_time_cap = true;
                            stop = true;
                        }
                        if (stop) break;

                        const op: Op = @enumFromInt(code >> 6);
                        const dd: usize = (code >> 4) & 3;
                        const aa: usize = (code >> 2) & 3;
                        const bb: usize = code & 3;

                        var ns: State = st.*;
                        var tmp: Tt = undefined;
                        applyTt(op, &st.r[aa], &st.r[bb], &tmp);
                        ns.r[dd] = tmp;

                        const k = stateKey(&ns);
                        if (visited.contains(k)) continue;
                        visited.putAssumeCapacity(k, {});
                        try r0set.put(r0Key(&ns.r[0]), {});

                        for (targets) |*t| {
                            if (t.found_depth == null and std.mem.eql(u8, &t.tt, &ns.r[0])) {
                                t.found_depth = d;
                                t.prog[d - 1] = code;
                                var lvl: u32 = d - 1;
                                var pi: u32 = @intCast(si);
                                while (lvl >= 1) : (lvl -= 1) {
                                    const m = metas.items[lvl - 1][pi];
                                    t.prog[lvl - 1] = m.instr;
                                    pi = m.parent;
                                }
                            }
                        }

                        try next.append(ns);
                        try meta_list.append(.{ .parent = @intCast(si), .instr = code });
                        if (visited.count() >= max_states) {
                            out.hit_state_cap = true;
                            stop = true;
                        }
                    }
                    if (stop) break;
                }

                try metas.append(try meta_list.toOwnedSlice());
                cur.deinit();
                cur = next;
                depth = d;
                if (!stop) out.depth_completed = d;

                var all_found = true;
                for (targets) |t| {
                    if (t.found_depth == null) all_found = false;
                }
                if (stop or all_found) break;
                if (cur.items.len == 0) {
                    out.fixpoint = true;
                    break;
                }
            }
            out.states_total = visited.count();
            out.distinct_r0 = r0set.count();
            return out;
        }

        // Verify a found program by direct scalar execution over ALL inputs.
        pub fn verifyProg(prog: []const u16, target: *const Tt) bool {
            var x: usize = 0;
            while (x < N) : (x += 1) {
                var r = [_]u8{0} ** K;
                r[0] = @intCast(x);
                r[1] = 1;
                for (prog) |code| {
                    const op: Op = @enumFromInt(code >> 6);
                    const dd: usize = (code >> 4) & 3;
                    const aa: usize = (code >> 2) & 3;
                    const bb: usize = code & 3;
                    r[dd] = applyScalarRt(op, r[aa], r[bb], MASK);
                }
                if (r[0] != target[x]) return false;
            }
            return true;
        }

        pub fn printProg(w: anytype, prog: []const u16) !void {
            for (prog) |code| {
                const op: Op = @enumFromInt(code >> 6);
                const dd: usize = (code >> 4) & 3;
                const aa: usize = (code >> 2) & 3;
                const bb: usize = code & 3;
                if (op.isUnary()) {
                    try w.print(" r{d}={s}(r{d});", .{ dd, op.name(), aa });
                } else {
                    try w.print(" r{d}={s}(r{d},r{d});", .{ dd, op.name(), aa, bb });
                }
            }
            try w.print("\n", .{});
        }
    };
}

// --------------------------------------------- explicit witness programs ----

// A hand-written instruction for the witness interpreter (any K, any W).
const WInstr = struct { op: Op, d: u8, a: u8, b: u8 };

fn runWitness(comptime W: u4, comptime K: usize, prog: []const WInstr, x: u8) u8 {
    const mask: u8 = @intCast((@as(u16, 1) << W) - 1);
    var r = [_]u8{0} ** K;
    r[0] = x & mask;
    r[1] = 1;
    for (prog) |ins| {
        r[ins.d] = applyScalarRt(ins.op, r[ins.a], r[ins.b], mask);
    }
    return r[0];
}

fn opsUsed(prog: []const WInstr, banned: []const Op) bool {
    for (prog) |ins| {
        for (banned) |b| {
            if (ins.op == b) return true;
        }
    }
    return false;
}

// Witness A: x&(x-1) on u8, K=3 registers, ops {OR, SHL, XOR} only.
// CLOSURE_PRINCIPLE.md claims this target "needs {AND,SUB}". It uses NEITHER.
// Idea: q = x<<1 | x<<2 | ... | x<<7 (prefix-OR via doubling), then
//       x & q = (x|q) ^ (x^q), which clears exactly the lowest set bit.
const witness_clearlow_or = [_]WInstr{
    .{ .op = .OR, .d = 1, .a = 0, .b = 0 }, // r1 = x
    .{ .op = .SHL, .d = 1, .a = 1, .b = 0 }, // r1 = x<<1
    .{ .op = .OR, .d = 2, .a = 1, .b = 1 }, // r2 = x<<1
    .{ .op = .SHL, .d = 2, .a = 2, .b = 0 }, // r2 = x<<2
    .{ .op = .OR, .d = 1, .a = 1, .b = 2 }, // r1 = x<<1|x<<2
    .{ .op = .OR, .d = 2, .a = 1, .b = 1 }, // r2 = shifts{1,2}
    .{ .op = .SHL, .d = 2, .a = 2, .b = 0 }, // r2 = shifts{2,3}<<... = x<<2|x<<3
    .{ .op = .SHL, .d = 2, .a = 2, .b = 0 }, // r2 = x<<3|x<<4
    .{ .op = .OR, .d = 1, .a = 1, .b = 2 }, // r1 = shifts{1..4}
    .{ .op = .OR, .d = 2, .a = 1, .b = 1 }, // r2 = shifts{1..4}
    .{ .op = .SHL, .d = 2, .a = 2, .b = 0 },
    .{ .op = .SHL, .d = 2, .a = 2, .b = 0 },
    .{ .op = .SHL, .d = 2, .a = 2, .b = 0 },
    .{ .op = .SHL, .d = 2, .a = 2, .b = 0 }, // r2 = shifts{5..8} (x<<8 drops out)
    .{ .op = .OR, .d = 1, .a = 1, .b = 2 }, // r1 = q = x<<1 | ... | x<<7
    .{ .op = .XOR, .d = 2, .a = 0, .b = 1 }, // r2 = x^q
    .{ .op = .OR, .d = 0, .a = 0, .b = 1 }, // r0 = x|q
    .{ .op = .XOR, .d = 0, .a = 0, .b = 2 }, // r0 = (x|q)^(x^q) = x&q = x&(x-1)
};

// Witness B: x|(x*x) on u4, K=5 registers, ops {SHR, SHL, XOR, NOT, AND} only.
// CLOSURE_PRINCIPLE.md claims this target "needs {OR,MUL}". It uses NEITHER.
// u4 square: x*x mod 16 = x0  |  (x1&~x0)<<2  |  (x0&(x1^x2))<<3  (disjoint bits)
// then x|sq = ~(~x & ~sq).
const witness_orsquare_and = [_]WInstr{
    .{ .op = .SHR, .d = 2, .a = 0, .b = 0 }, // r2 = x>>1
    .{ .op = .SHR, .d = 3, .a = 2, .b = 0 }, // r3 = x>>2
    .{ .op = .XOR, .d = 3, .a = 2, .b = 3 }, // r3 = (x>>1)^(x>>2)
    .{ .op = .AND, .d = 3, .a = 3, .b = 0 }, // r3 &= x   (bit0 = x0&(x1^x2))
    .{ .op = .AND, .d = 3, .a = 3, .b = 1 }, // r3 = t3 in {0,1}
    .{ .op = .SHL, .d = 3, .a = 3, .b = 0 },
    .{ .op = .SHL, .d = 3, .a = 3, .b = 0 },
    .{ .op = .SHL, .d = 3, .a = 3, .b = 0 }, // r3 = t3<<3
    .{ .op = .NOTA, .d = 4, .a = 0, .b = 0 }, // r4 = ~x
    .{ .op = .AND, .d = 2, .a = 2, .b = 4 }, // r2 = (x>>1)&~x (bit0 = x1&~x0)
    .{ .op = .AND, .d = 2, .a = 2, .b = 1 }, // r2 = t2 in {0,1}
    .{ .op = .SHL, .d = 2, .a = 2, .b = 0 },
    .{ .op = .SHL, .d = 2, .a = 2, .b = 0 }, // r2 = t2<<2
    .{ .op = .XOR, .d = 2, .a = 2, .b = 3 }, // r2 = t2<<2 ^ t3<<3
    .{ .op = .AND, .d = 3, .a = 0, .b = 1 }, // r3 = x0
    .{ .op = .XOR, .d = 2, .a = 2, .b = 3 }, // r2 = sq = x*x mod 16
    .{ .op = .NOTA, .d = 2, .a = 2, .b = 0 }, // r2 = ~sq
    .{ .op = .AND, .d = 2, .a = 4, .b = 2 }, // r2 = ~x & ~sq
    .{ .op = .NOTA, .d = 0, .a = 2, .b = 0 }, // r0 = x | sq
};

// ------------------------------------------------------------------ main ----

const base_ops = [_]Op{ .XOR, .SHL, .SHR, .NOTA };

fn setWith(comptime extra: []const Op) [base_ops.len + extra.len]Op {
    var out: [base_ops.len + extra.len]Op = undefined;
    @memcpy(out[0..base_ops.len], &base_ops);
    @memcpy(out[base_ops.len..], extra);
    return out;
}

const OpSet = struct { name: []const u8, ops: []const Op };

fn runSuite(
    comptime W: u4,
    comptime K: usize,
    alloc: std.mem.Allocator,
    w: anytype,
    sets: []const OpSet,
    max_depth: u32,
    max_states: usize,
    budget_ns: u64,
) !void {
    const E = Engine(W, K);
    try w.print("\n--- width u{d}, K={d} registers, BFS to depth {d} (state cap {d}) ---\n", .{ W, K, max_depth, max_states });
    for (sets) |s| {
        var targets = E.makeTargets();
        const oc = try E.bfs(alloc, s.ops, &targets, max_depth, max_states, budget_ns);
        const status: []const u8 = if (oc.fixpoint)
            "FIXPOINT (exact infinite-depth closure)"
        else if (oc.hit_state_cap)
            "state-cap"
        else if (oc.hit_time_cap)
            "time-cap"
        else
            "depth-cap";
        try w.print("  {s:<14} | states={d:<9} distinct r0 fns={d:<8} depth done={d:<2} [{s}]\n", .{ s.name, oc.states_total, oc.distinct_r0, oc.depth_completed, status });
        for (&targets) |*t| {
            if (t.found_depth) |d| {
                const affine = isAffineTt(&t.tt);
                try w.print("      {s} REACHED at depth {d}{s} :", .{ t.name, d, if (affine) " (target is AFFINE at this width!)" else "" });
                if (d > 0) {
                    const ok = E.verifyProg(t.prog[0..d], &t.tt);
                    try E.printProg(w, t.prog[0..d]);
                    if (!ok) try w.print("      ^^ VERIFY FAILED (BUG IN HARNESS)\n", .{});
                } else {
                    try w.print(" (identity)\n", .{});
                }
            } else {
                if (oc.fixpoint) {
                    try w.print("      {s} UNREACHABLE at ANY depth (closure exhausted)\n", .{t.name});
                } else {
                    try w.print("      {s} not found within depth {d} ({s})\n", .{ t.name, oc.depth_completed, status });
                }
            }
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const w = std.io.getStdOut().writer();
    var total_timer = try std.time.Timer.start();

    try w.print("=====================================================================\n", .{});
    try w.print("I53 falsification attack on the Closure Principle  (2026-07-10)\n", .{});
    try w.print("=====================================================================\n", .{});

    const with_and = comptime setWith(&[_]Op{.AND});
    const with_or = comptime setWith(&[_]Op{.OR});
    const with_sub = comptime setWith(&[_]Op{.SUB});
    const with_mul = comptime setWith(&[_]Op{.MUL});
    const with_and_sub = comptime setWith(&[_]Op{ .AND, .SUB });
    const with_or_mul = comptime setWith(&[_]Op{ .OR, .MUL });
    const full = comptime setWith(&[_]Op{ .AND, .OR, .ADD, .SUB, .MUL });

    // ============ ATTACK (a): boundary abuse — small widths ============
    try w.print("\n### ATTACK (a): finite-domain boundary — are the 'nonlinear witnesses'\n", .{});
    try w.print("### even outside the affine closure at small widths?\n", .{});

    // Which of the 5 targets are affine, per width?
    inline for ([_]u4{ 1, 2, 4, 8 }) |WW| {
        const NN: usize = @as(usize, 1) << WW;
        const mask: u8 = @intCast((@as(u16, 1) << WW) - 1);
        try w.print("  width u{d}: ", .{WW});
        var n_affine: usize = 0;
        inline for (target_defs) |td| {
            var tt: [NN]u8 = undefined;
            for (0..NN) |x| tt[x] = td.f(@intCast(x), mask);
            const aff = isAffineTt(&tt);
            if (aff) n_affine += 1;
            try w.print("{s}={s}  ", .{ td.name, if (aff) "AFFINE" else "nonlin" });
        }
        try w.print("  ({d}/5 affine)\n", .{n_affine});
    }

    {
        const sets1 = [_]OpSet{
            .{ .name = "base (affine)", .ops = &base_ops },
            .{ .name = "full 9-op", .ops = &full },
        };
        try runSuite(1, 2, alloc, w, &sets1, 8, 100_000, 5 * std.time.ns_per_s);
        const sets2 = [_]OpSet{
            .{ .name = "base (affine)", .ops = &base_ops },
            .{ .name = "base+{AND}", .ops = &with_and },
            .{ .name = "base+{OR}", .ops = &with_or },
            .{ .name = "base+{MUL}", .ops = &with_mul },
            .{ .name = "full 9-op", .ops = &full },
        };
        try runSuite(2, 2, alloc, w, &sets2, 14, 200_000, 10 * std.time.ns_per_s);
    }

    // ============ ATTACK (b): depth push on the pair-claims ============
    try w.print("\n### ATTACK (b): is 'outside the closure' really 'outside the depth-3\n", .{});
    try w.print("### closure'? BFS far past MAXL=3, with exact-dedup (fixpoint = proof).\n", .{});

    {
        const sets4 = [_]OpSet{
            .{ .name = "base (affine)", .ops = &base_ops },
            .{ .name = "base+{AND}", .ops = &with_and },
            .{ .name = "base+{SUB}", .ops = &with_sub },
            .{ .name = "base+{OR}", .ops = &with_or },
            .{ .name = "base+{MUL}", .ops = &with_mul },
            .{ .name = "base+{AND,SUB}", .ops = &with_and_sub },
            .{ .name = "base+{OR,MUL}", .ops = &with_or_mul },
        };
        try runSuite(4, 2, alloc, w, &sets4, 14, 8_000_000, 75 * std.time.ns_per_s);
    }
    {
        const sets8 = [_]OpSet{
            .{ .name = "base (affine)", .ops = &base_ops },
            .{ .name = "base+{AND}", .ops = &with_and },
            .{ .name = "base+{SUB}", .ops = &with_sub },
            .{ .name = "base+{OR}", .ops = &with_or },
            .{ .name = "base+{MUL}", .ops = &with_mul },
        };
        try runSuite(8, 2, alloc, w, &sets8, 12, 1_200_000, 60 * std.time.ns_per_s);
    }

    // ============ ATTACK (b'): register bound vs op-closure ============
    try w.print("\n### ATTACK (b'): the substrate has K=2 registers. Is the 'closure' wall\n", .{});
    try w.print("### an OP-ALGEBRA fact or a REGISTER-FILE fact? Add one register.\n", .{});
    {
        const sets43 = [_]OpSet{
            .{ .name = "base+{AND}", .ops = &with_and },
            .{ .name = "base+{OR}", .ops = &with_or },
        };
        try runSuite(4, 3, alloc, w, &sets43, 8, 8_000_000, 75 * std.time.ns_per_s);
    }

    // ============ Explicit witnesses (no search needed) ============
    try w.print("\n### EXPLICIT WITNESSES against the pair-necessity claims\n", .{});
    try w.print("### (hand-constructed, verified exhaustively over every input)\n", .{});

    {
        // Witness A: x&(x-1) on u8 without AND and without SUB.
        var ok = true;
        var x: u16 = 0;
        while (x < 256) : (x += 1) {
            const got = runWitness(8, 3, &witness_clearlow_or, @intCast(x));
            const want = tClearLow(x, 0xFF);
            if (got != want) {
                ok = false;
                try w.print("  witness A MISMATCH at x={d}: got {d} want {d}\n", .{ x, got, want });
            }
        }
        const uses_banned = opsUsed(&witness_clearlow_or, &[_]Op{ .AND, .SUB, .ADD, .MUL });
        try w.print("  Witness A: x&(x-1) on u8, K=3, {d} instrs, ops {{OR,SHL,XOR}} only\n", .{witness_clearlow_or.len});
        try w.print("    verified on all 256 inputs: {s};  uses AND/SUB/ADD/MUL: {s}\n", .{ if (ok) "PASS" else "FAIL", if (uses_banned) "YES (invalid)" else "NO" });
        if (ok and !uses_banned) {
            try w.print("    => CLAIM \"x&(x-1) needs {{AND,SUB}}\" is FALSE as an op-closure\n", .{});
            try w.print("       statement. It holds only under (length<=3, K=2 registers).\n", .{});
        }
    }
    {
        // Witness B: x|(x*x) on u4 without OR and without MUL.
        var ok = true;
        var x: u16 = 0;
        while (x < 16) : (x += 1) {
            const got = runWitness(4, 5, &witness_orsquare_and, @intCast(x));
            const want = tOrSquare(x, 0xF);
            if (got != want) {
                ok = false;
                try w.print("  witness B MISMATCH at x={d}: got {d} want {d}\n", .{ x, got, want });
            }
        }
        const uses_banned = opsUsed(&witness_orsquare_and, &[_]Op{ .OR, .MUL, .ADD, .SUB });
        try w.print("  Witness B: x|(x*x) on u4, K=5, {d} instrs, ops {{SHR,SHL,XOR,NOT,AND}} only\n", .{witness_orsquare_and.len});
        try w.print("    verified on all 16 inputs: {s};  uses OR/MUL/ADD/SUB: {s}\n", .{ if (ok) "PASS" else "FAIL", if (uses_banned) "YES (invalid)" else "NO" });
        if (ok and !uses_banned) {
            try w.print("    => CLAIM \"x|(x*x) needs {{OR,MUL}}\" is FALSE as an op-closure\n", .{});
            try w.print("       statement (u4 form). It holds only under (length<=3, K=2 regs).\n", .{});
        }
    }

    try w.print("\ntotal wall time: {d} ms\n", .{total_timer.read() / std.time.ns_per_ms});
}
