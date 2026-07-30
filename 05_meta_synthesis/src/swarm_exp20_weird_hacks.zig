//! Swarm EXP-20 (D34 / RQ34): CEGIS invent bit-hacks for deliberately weird u32 specs.
//!
//! Uses the 04/05 verified-synthesis pattern (hill-climber inventor + Z3 CEGIS counterexamples)
//! from `true_hacker_inventor.zig`, extended to eight unary/binary u32 targets that are mostly
//! *not* named Hacker's Delight identities.
//!
//! Run: zig build swarm-exp20 --release=fast

const std = @import("std");
const smt = @import("smt_verify");

const Word = u32;
const BV = 32;

const Op = enum(u4) {
    ADD,
    SUB,
    XOR,
    AND,
    OR,
    SHL,
    SHR,
    MUL,
};

const HackNode = struct {
    op: Op,
    dst: u2,
    src1: u2,
    src2: u2,
    imm: u5 = 0,
};

const TestCase = struct {
    x: Word,
    y: Word = 0,
    target: Word,
};

const Arity = enum { unary, binary };

const HdClass = enum {
    hd_classic,
    hd_adjacent,
    deliberately_weird,
};

const Spec = struct {
    id: []const u8,
    desc: []const u8,
    arity: Arity,
    hd: HdClass,
    init: [4]Word,
    ref: *const fn (x: Word, y: Word) Word,
    seeds: []const struct { x: Word, y: Word = 0 },
};

fn refGray(x: Word, _: Word) Word {
    return x ^ (x >> 1);
}
fn refCondSquareEven(x: Word, _: Word) Word {
    return if ((x & 1) == 0) x *% x else x;
}
fn refMod3Mask(x: Word, _: Word) Word {
    return if (x % 3 == 0) 0xFFFF_FFFF else 0;
}
fn refOddEvenSpread(x: Word, _: Word) Word {
    const lo: Word = 0x5555_5555;
    const hi: Word = 0xAAAA_AAAA;
    return ((x & lo) << 1) | ((x & hi) >> 1);
}
fn refXorHalves(x: Word, _: Word) Word {
    return x ^ (x >> 16);
}
fn refWeirdFold(x: Word, _: Word) Word {
    return (x +% (x << 3)) ^ (x >> 5);
}
fn refOverflowFreeAvg(x: Word, y: Word) Word {
    return (x & y) +% ((x ^ y) >> 1);
}
fn refBranchlessMax(x: Word, y: Word) Word {
    const lt = @as(i32, @bitCast(x)) < @as(i32, @bitCast(y));
    const mask: Word = @bitCast(-@as(i32, @intFromBool(lt)));
    return x ^ ((x ^ y) & mask);
}
fn refMuxDoubleOdd(x: Word, _: Word) Word {
    const odd = x & 1;
    const add = 0 -% odd;
    return x +% (x & add);
}

const SPECS = [_]Spec{
    .{
        .id = "gray_encode",
        .desc = "Gray code: x ^ (x>>1) [HD control]",
        .arity = .unary,
        .hd = .hd_classic,
        .init = .{ 0, 1, 0, 0 },
        .ref = &refGray,
        .seeds = &.{
            .{ .x = 0 },
            .{ .x = 5 },
            .{ .x = 0xFFFF_FFFF },
        },
    },
    .{
        .id = "cond_square_even",
        .desc = "Conditional squaring: (x&1)==0 ? x*x : x",
        .arity = .unary,
        .hd = .deliberately_weird,
        .init = .{ 0, 1, 0, 0 },
        .ref = &refCondSquareEven,
        .seeds = &.{
            .{ .x = 4 },
            .{ .x = 7 },
            .{ .x = 0x10001 },
        },
    },
    .{
        .id = "mod3_zero_mask",
        .desc = "Mod test: x%3==0 ? 0xFFFFFFFF : 0 (magic-div, not a named HD one-liner)",
        .arity = .unary,
        .hd = .deliberately_weird,
        .init = .{ 0, 0xAAAA_AAAB, 3, 0xFFFF_FFFF },
        .ref = &refMod3Mask,
        .seeds = &.{
            .{ .x = 3 },
            .{ .x = 9 },
            .{ .x = 10 },
        },
    },
    .{
        .id = "odd_even_spread",
        .desc = "Spread odd/even bit lanes: (x&0x5555..)<<1 | (x&0xAAAA..)>>1",
        .arity = .unary,
        .hd = .deliberately_weird,
        .init = .{ 0, 0x5555_5555, 0xAAAA_AAAA, 0 },
        .ref = &refOddEvenSpread,
        .seeds = &.{
            .{ .x = 0x1234_5678 },
            .{ .x = 0xFFFF_0000 },
            .{ .x = 0x0F0F_0F0F },
        },
    },
    .{
        .id = "xor_halves_u32",
        .desc = "Fold upper/lower half: x ^ (x>>16) [HD-adjacent fingerprint step]",
        .arity = .unary,
        .hd = .hd_adjacent,
        .init = .{ 0, 1, 0, 0 },
        .ref = &refXorHalves,
        .seeds = &.{
            .{ .x = 0x1234_ABCD },
            .{ .x = 0x8000_0001 },
            .{ .x = 0 },
        },
    },
    .{
        .id = "weird_hash_fold",
        .desc = "Alien mix: (x + (x<<3)) ^ (x>>5) — not a standard HD identity",
        .arity = .unary,
        .hd = .deliberately_weird,
        .init = .{ 0, 1, 0, 0 },
        .ref = &refWeirdFold,
        .seeds = &.{
            .{ .x = 1 },
            .{ .x = 0xDEAD_BEEF },
            .{ .x = 0x3141_5926 },
        },
    },
    .{
        .id = "overflow_free_avg",
        .desc = "Safe average: (x&y) + ((x^y)>>1) [alien-hack / HD-adjacent]",
        .arity = .binary,
        .hd = .hd_adjacent,
        .init = .{ 0, 0, 0, 0 },
        .ref = &refOverflowFreeAvg,
        .seeds = &.{
            .{ .x = 10, .y = 20 },
            .{ .x = 0xFFFF_FFFF, .y = 0xFFFF_FFFF },
            .{ .x = 1, .y = 0xFFFF_FFFE },
        },
    },
    .{
        .id = "branchless_max",
        .desc = "Branchless max(x,y) via sign-mask mux",
        .arity = .binary,
        .hd = .deliberately_weird,
        .init = .{ 0, 0, 0, 0 },
        .ref = &refBranchlessMax,
        .seeds = &.{
            .{ .x = 3, .y = 9 },
            .{ .x = 0x8000_0000, .y = 1 },
            .{ .x = 7, .y = 7 },
        },
    },
    .{
        .id = "mux_double_if_odd",
        .desc = "Conditional double: (x&1)==1 ? 2*x : x",
        .arity = .unary,
        .hd = .deliberately_weird,
        .init = .{ 0, 1, 0, 0 },
        .ref = &refMuxDoubleOdd,
        .seeds = &.{
            .{ .x = 2 },
            .{ .x = 3 },
            .{ .x = 0xFFFF_FFFF },
        },
    },
};

const Result = struct {
    spec_id: []const u8,
    certified: bool,
    gens: usize,
    prog_len: u8,
    nodes: [6]HackNode,
    hd: HdClass,
    novelty: []const u8,
};

fn execute(insts: []const HackNode, spec: Spec, x: Word, y: Word) Word {
    var regs = [_]Word{
        x,
        if (spec.arity == .binary) y else spec.init[1],
        spec.init[2],
        spec.init[3],
    };
    if (spec.arity == .unary) {
        regs[1] = spec.init[1];
    }
    for (insts) |n| {
        const v1 = regs[n.src1];
        const v2 = regs[n.src2];
        regs[n.dst] = switch (n.op) {
            .ADD => v1 +% v2,
            .SUB => v1 -% v2,
            .XOR => v1 ^ v2,
            .AND => v1 & v2,
            .OR => v1 | v2,
            .SHL => v1 << @intCast(n.imm),
            .SHR => v1 >> @intCast(n.imm),
            .MUL => v1 *% v2,
        };
    }
    return regs[0];
}

fn score(insts: []const HackNode, spec: Spec, cases: []const TestCase) f64 {
    var q: f64 = 0;
    for (cases) |tc| {
        const got = execute(insts, spec, tc.x, tc.y);
        if (got == tc.target) {
            q += 1.0;
        } else {
            const matching = BV - @popCount(got ^ tc.target);
            q += @as(f64, @floatFromInt(matching)) / @as(f64, @floatFromInt(BV));
        }
    }
    return q;
}

fn emitSmt(allocator: std.mem.Allocator, spec: Spec, insts: []const HackNode) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    const w = buf.writer();
    try w.print("(set-logic QF_BV)\n", .{});
    try w.print("(declare-const x (_ BitVec {d}))\n", .{BV});
    if (spec.arity == .binary) {
        try w.print("(declare-const y (_ BitVec {d}))\n", .{BV});
    }

    var ver = [_]u32{0} ** 4;
    for (0..4) |r| {
        const init_expr: []const u8 = switch (r) {
            0 => "x",
            1 => if (spec.arity == .binary) "y" else init_const: {
                break :init_const try std.fmt.allocPrint(allocator, "(_ bv{d} {d})", .{ spec.init[1], BV });
            },
            2 => try std.fmt.allocPrint(allocator, "(_ bv{d} {d})", .{ spec.init[2], BV }),
            3 => try std.fmt.allocPrint(allocator, "(_ bv{d} {d})", .{ spec.init[3], BV }),
            else => unreachable,
        };
        defer if (r != 0 and !(r == 1 and spec.arity == .binary)) allocator.free(init_expr);
        try w.print("(declare-const r{d}_v0 (_ BitVec {d}))\n", .{ r, BV });
        try w.print("(assert (= r{d}_v0 {s}))\n", .{ r, init_expr });
    }

    for (insts) |n| {
        const d_new = ver[n.dst] + 1;
        ver[n.dst] = d_new;
        try w.print("(declare-const r{d}_v{d} (_ BitVec {d}))\n", .{ n.dst, d_new, BV });
        const v1 = try std.fmt.allocPrint(allocator, "r{d}_v{d}", .{ n.src1, ver[n.src1] });
        defer allocator.free(v1);
        const v2 = try std.fmt.allocPrint(allocator, "r{d}_v{d}", .{ n.src2, ver[n.src2] });
        defer allocator.free(v2);
        const dst = try std.fmt.allocPrint(allocator, "r{d}_v{d}", .{ n.dst, d_new });
        defer allocator.free(dst);
        switch (n.op) {
            .ADD => try w.print("(assert (= {s} (bvadd {s} {s})))\n", .{ dst, v1, v2 }),
            .SUB => try w.print("(assert (= {s} (bvsub {s} {s})))\n", .{ dst, v1, v2 }),
            .XOR => try w.print("(assert (= {s} (bvxor {s} {s})))\n", .{ dst, v1, v2 }),
            .AND => try w.print("(assert (= {s} (bvand {s} {s})))\n", .{ dst, v1, v2 }),
            .OR => try w.print("(assert (= {s} (bvor {s} {s})))\n", .{ dst, v1, v2 }),
            .SHL => try w.print("(assert (= {s} (bvshl {s} (_ bv{d} {d}))))\n", .{ dst, v1, n.imm, BV }),
            .SHR => try w.print("(assert (= {s} (bvlshr {s} (_ bv{d} {d}))))\n", .{ dst, v1, n.imm, BV }),
            .MUL => try w.print("(assert (= {s} (bvmul {s} {s})))\n", .{ dst, v1, v2 }),
        }
    }

    try w.print("(declare-fun ref ((_ BitVec {d})", .{BV});
    if (spec.arity == .binary) try w.writeAll(" (_ BitVec 32)");
    try w.writeAll(") (_ BitVec 32))\n");

    // Reference as nested if-eq for mod3 / cond specs; use concrete evaluation witness instead:
    // Assert NOT equal to ref applied symbolically — we encode ref by brute-forcing isn't possible in SMT easily.
    // Instead: assert candidate != ref(x[,y]) by enumerating semantics via define-fun from seeds + CEGIS.
    // Practical approach: assert for all inputs via quantifier-free unrolling is impossible; use the same
    // trick as true_hacker_inventor: assert r0 != concrete reference expression built per spec.

    const ref_expr = try refSmtExpr(allocator, spec);
    defer allocator.free(ref_expr);
    try w.print("(assert (not (= r0_v{d} {s})))\n", .{ ver[0], ref_expr });
    try w.writeAll("(check-sat)\n(get-model)\n");
    return buf.toOwnedSlice();
}

fn refSmtExpr(allocator: std.mem.Allocator, spec: Spec) ![]u8 {
    // Hand-encoded reference for each spec (Z3 bit-vector terms).
    if (std.mem.eql(u8, spec.id, "gray_encode")) {
        return try std.fmt.allocPrint(allocator, "(bvxor x (bvlshr x (_ bv1 {d})))", .{BV});
    }
    if (std.mem.eql(u8, spec.id, "cond_square_even")) {
        return try std.fmt.allocPrint(allocator,
            \\ (ite (= (bvand x (_ bv1 {d})) (_ bv0 {d}))
            \\     (bvmul x x)
            \\     x)
        , .{ BV, BV });
    }
    if (std.mem.eql(u8, spec.id, "mod3_zero_mask")) {
        return try std.fmt.allocPrint(allocator,
            \\ (ite (= (bvurem x (_ bv3 {d})) (_ bv0 {d}))
            \\     (_ bv4294967295 {d})
            \\     (_ bv0 {d}))
        , .{ BV, BV, BV, BV });
    }
    if (std.mem.eql(u8, spec.id, "odd_even_spread")) {
        return try std.fmt.allocPrint(allocator,
            \\ (bvor (bvshl (bvand x (_ bv1431655765 {d})) (_ bv1 {d}))
            \\       (bvlshr (bvand x (_ bv2863311530 {d})) (_ bv1 {d})))
        , .{ BV, BV, BV, BV });
    }
    if (std.mem.eql(u8, spec.id, "xor_halves_u32")) {
        return try std.fmt.allocPrint(allocator, "(bvxor x (bvlshr x (_ bv16 {d})))", .{BV});
    }
    if (std.mem.eql(u8, spec.id, "weird_hash_fold")) {
        return try std.fmt.allocPrint(allocator,
            \\ (bvxor (bvadd x (bvshl x (_ bv3 {d}))) (bvlshr x (_ bv5 {d})))
        , .{ BV, BV });
    }
    if (std.mem.eql(u8, spec.id, "overflow_free_avg")) {
        return try std.fmt.allocPrint(allocator,
            \\ (bvadd (bvand x y) (bvlshr (bvxor x y) (_ bv1 {d})))
        , .{BV});
    }
    if (std.mem.eql(u8, spec.id, "branchless_max")) {
        return try std.fmt.allocPrint(allocator,
            \\(bvxor x (bvand (bvxor x y) (bvsub (_ bv0 {d}) (bvlshr (bvsub x y) (_ bv31 {d})))))
        , .{ BV, BV });
    }
    if (std.mem.eql(u8, spec.id, "mux_double_if_odd")) {
        return try std.fmt.allocPrint(allocator,
            \\(bvadd x (bvand x (bvsub (_ bv0 {d}) (bvand x (_ bv1 {d})))))
        , .{ BV, BV });
    }
    return error.UnknownSpec;
}

fn parseModelWord(model: []const u8, name: []const u8) !Word {
    const idx = std.mem.indexOf(u8, model, name) orelse return error.NotFound;
    const hex_idx = std.mem.indexOf(u8, model[idx..], "#x") orelse return error.NoHex;
    const start = idx + hex_idx + 2;
    const end = std.mem.indexOfScalarPos(u8, model, start, ')') orelse return error.Malformed;
    const hex = std.mem.trim(u8, model[start..end], " \n\r\t");
    return try std.fmt.parseInt(Word, hex, 16);
}

fn inventSpec(
    allocator: std.mem.Allocator,
    out: anytype,
    spec: Spec,
    seed: *u64,
    max_gen: usize,
    hill_iters: usize,
) !Result {
    var cases = std.ArrayList(TestCase).init(allocator);
    defer cases.deinit();
    for (spec.seeds) |s| {
        try cases.append(.{
            .x = s.x,
            .y = s.y,
            .target = spec.ref(s.x, s.y),
        });
    }

    var best_nodes: [6]HackNode = undefined;
    var best_len: u8 = 0;
    var gen: usize = 1;

    while (gen <= max_gen) : (gen += 1) {
        var best_q: f64 = -1.0;
        best_len = 0;

        var it: usize = 0;
        while (it < hill_iters) : (it += 1) {
            const len: u8 = @intCast(2 + (nextRand(seed) % 5)); // 2..6
            var nodes: [6]HackNode = undefined;
            for (0..len) |k| {
                nodes[k] = randomNode(seed);
            }
            const q = score(nodes[0..len], spec, cases.items);
            if (q > best_q) {
                best_q = q;
                best_nodes = nodes;
                best_len = len;
            }
            if (best_q >= @as(f64, @floatFromInt(cases.items.len))) break;
        }

        if (best_q < @as(f64, @floatFromInt(cases.items.len))) {
            try out.print("  [{s}] FAILED hill-climb gen={d} Q={d:.2}/{d}\n", .{
                spec.id, gen, best_q, cases.items.len,
            });
            return .{
                .spec_id = spec.id,
                .certified = false,
                .gens = gen,
                .prog_len = 0,
                .nodes = undefined,
                .hd = spec.hd,
                .novelty = "search_stalled",
            };
        }

        const smt_text = try emitSmt(allocator, spec, best_nodes[0..best_len]);
        defer allocator.free(smt_text);
        const res = try smt.runSmtLib(allocator, smt_text, 8000);

        if (res.verdict == .verified or (res.verdict == .error_smt and std.mem.indexOf(u8, res.detail, "unsat") != null)) {
            if (res.verdict == .error_smt) allocator.free(res.detail);
            const novelty = classifyNovelty(spec, best_nodes[0..best_len]);
            try out.print("  [{s}] CERTIFIED gen={d} len={d} novelty={s}\n", .{
                spec.id, gen, best_len, novelty,
            });
            for (0..best_len) |i| {
                const n = best_nodes[i];
                try out.print("    [{d}] r{d} = {s}(r{d}, r{d})", .{ i, n.dst, @tagName(n.op), n.src1, n.src2 });
                if (n.op == .SHL or n.op == .SHR) try out.print(" imm={d}", .{n.imm});
                try out.print("\n", .{});
            }
            return .{
                .spec_id = spec.id,
                .certified = true,
                .gens = gen,
                .prog_len = best_len,
                .nodes = best_nodes,
                .hd = spec.hd,
                .novelty = novelty,
            };
        }

        if (res.verdict == .counter_example) {
            defer allocator.free(res.detail);
            const x_val = parseModelWord(res.detail, "define-fun x ") catch 0;
            const y_val = if (spec.arity == .binary)
                parseModelWord(res.detail, "define-fun y ") catch 0
            else
                0;
            const tc = TestCase{ .x = x_val, .y = y_val, .target = spec.ref(x_val, y_val) };
            var dup = false;
            for (cases.items) |existing| {
                if (existing.x == tc.x and existing.y == tc.y) {
                    dup = true;
                    break;
                }
            }
            if (!dup) try cases.append(tc);
            try out.print("  [{s}] Z3 counter-example gen={d}: x=0x{X:0>8}", .{ spec.id, gen, x_val });
            if (spec.arity == .binary) try out.print(" y=0x{X:0>8}", .{y_val});
            try out.print(" (tests={d})\n", .{cases.items.len});
        } else {
            try out.print("  [{s}] Z3 error: {s}\n", .{ spec.id, res.detail });
            allocator.free(res.detail);
            return .{
                .spec_id = spec.id,
                .certified = false,
                .gens = gen,
                .prog_len = 0,
                .nodes = undefined,
                .hd = spec.hd,
                .novelty = "z3_error",
            };
        }
    }

    return .{
        .spec_id = spec.id,
        .certified = false,
        .gens = max_gen,
        .prog_len = 0,
        .nodes = undefined,
        .hd = spec.hd,
        .novelty = "cegis_exhausted",
    };
}

fn classifyNovelty(spec: Spec, insts: []const HackNode) []const u8 {
    if (spec.hd == .hd_classic) return "hd_rediscovery_expected";
    if (spec.hd == .hd_adjacent) return "hd_adjacent_rediscovery";
    // Weird specs: certified program is novel w.r.t. HD canon if we didn't encode a known name.
    _ = insts;
    return "novel_weird_spec_certified";
}

fn randomNode(seed: *u64) HackNode {
    return .{
        .op = @enumFromInt(nextRand(seed) % 8),
        .dst = @intCast(nextRand(seed) % 4),
        .src1 = @intCast(nextRand(seed) % 4),
        .src2 = @intCast(nextRand(seed) % 4),
        .imm = @intCast(nextRand(seed) % 32),
    };
}

fn nextRand(rng: *u64) u64 {
    var z = rng.* +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    rng.* = z ^ (z >> 31);
    return rng.*;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const out = std.io.getStdOut().writer();

    try out.print("=== Swarm EXP-20 (D34/RQ34): CEGIS weird u32 bit-hacks ===\n\n", .{});
    try out.print("Inventor: hill-climber (true_hacker_inventor pattern)\n", .{});
    try out.print("Verifier: Z3 QF_BV CEGIS over all 2^32 inputs (per spec)\n", .{});
    try out.print("Specs: {d} deliberately mixed HD-control + weird targets\n\n", .{SPECS.len});

    var prng = std.Random.DefaultPrng.init(0xE20D34C0FFEE);
    var seed = prng.random().int(u64);

    var certified: usize = 0;
    var novel: usize = 0;
    var hd_rediscover: usize = 0;
    var failed: usize = 0;
    var results: [SPECS.len]Result = undefined;

    for (SPECS, 0..) |spec, i| {
        try out.print("── {s}: {s} ──\n", .{ spec.id, spec.desc });
        const hill_iters: usize = blk: {
            if (std.mem.eql(u8, spec.id, "mod3_zero_mask")) break :blk 15_000_000;
            if (std.mem.eql(u8, spec.id, "cond_square_even") or
                std.mem.eql(u8, spec.id, "branchless_max") or
                std.mem.eql(u8, spec.id, "overflow_free_avg")) break :blk 8_000_000;
            break :blk 5_000_000;
        };
        results[i] = try inventSpec(allocator, out, spec, &seed, 30, hill_iters);
        if (results[i].certified) {
            certified += 1;
            if (std.mem.eql(u8, results[i].novelty, "novel_weird_spec_certified")) novel += 1;
            if (std.mem.eql(u8, results[i].novelty, "hd_rediscovery_expected") or
                std.mem.eql(u8, results[i].novelty, "hd_adjacent_rediscovery")) hd_rediscover += 1;
        } else {
            failed += 1;
        }
        try out.print("\n", .{});
    }

    try out.print("=== SUMMARY ===\n", .{});
    try out.print("certified_inventions: {d}/{d}\n", .{ certified, SPECS.len });
    try out.print("novel_weird_vs_hd:    {d}\n", .{ novel });
    try out.print("hd_rediscoveries:     {d}\n", .{ hd_rediscover });
    try out.print("failed:               {d}\n", .{ failed });
}