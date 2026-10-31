//! G49 — Cross-audit: native SAT prover (AIG miter + CDCL-lite) vs libz3.
//!
//! Battery of boolean equivalence checks. Both verifiers ask
//! "∃ input where left ≠ right?" — UNSAT ⇒ equivalent.
//!
//! Usage: z3_cross_audit [--cases=N] [--timeout-ms=N] [--json=PATH]

const std = @import("std");
const prover = @import("native_prover");
const smt = @import("smt_verify");

const Expr = union(enum) {
    var_id: u8,
    c0,
    c1,
    not_e: *const Expr,
    and_e: [2]*const Expr,
    or_e: [2]*const Expr,
    xor_e: [2]*const Expr,
};

const Case = struct {
    name: []const u8,
    expect_equiv: bool,
    left: *const Expr,
    right: *const Expr,
    num_vars: u8,
};

const NativeVerdict = enum { equivalent, different, fault };
const Z3Verdict = enum { equivalent, different, unknown, fault };

const Row = struct {
    name: []const u8,
    expect_equiv: bool,
    native_v: NativeVerdict,
    z3_v: Z3Verdict,
    agree: bool,
    native_ms: u64,
    z3_ms: u64,
};

const Eb = struct {
    a: std.mem.Allocator,

    fn v(self: *Eb, id: u8) !*const Expr {
        const e = try self.a.create(Expr);
        e.* = .{ .var_id = id };
        return e;
    }
    fn c0(self: *Eb) !*const Expr {
        const e = try self.a.create(Expr);
        e.* = .c0;
        return e;
    }
    fn c1(self: *Eb) !*const Expr {
        const e = try self.a.create(Expr);
        e.* = .c1;
        return e;
    }
    fn not(self: *Eb, x: *const Expr) !*const Expr {
        const e = try self.a.create(Expr);
        e.* = .{ .not_e = x };
        return e;
    }
    fn land(self: *Eb, x: *const Expr, y: *const Expr) !*const Expr {
        const e = try self.a.create(Expr);
        e.* = .{ .and_e = .{ x, y } };
        return e;
    }
    fn lor(self: *Eb, x: *const Expr, y: *const Expr) !*const Expr {
        const e = try self.a.create(Expr);
        e.* = .{ .or_e = .{ x, y } };
        return e;
    }
    fn lxor(self: *Eb, x: *const Expr, y: *const Expr) !*const Expr {
        const e = try self.a.create(Expr);
        e.* = .{ .xor_e = .{ x, y } };
        return e;
    }
};

fn litAssertTrue(node: prover.NodeId) prover.Lit {
    const var_idx: prover.Lit = @intCast((node >> 1) + 1);
    return if ((node & 1) != 0) -var_idx else var_idx;
}

fn lowerExpr(aig: *prover.Aig, e: *const Expr, env: []const prover.NodeId) !prover.NodeId {
    return switch (e.*) {
        .var_id => |v| env[v],
        .c0 => @as(prover.NodeId, 0),
        .c1 => @as(prover.NodeId, 1),
        .not_e => |p| aig.notNode(try lowerExpr(aig, p, env)),
        .and_e => |pair| try aig.andNodes(
            try lowerExpr(aig, pair[0], env),
            try lowerExpr(aig, pair[1], env),
        ),
        .or_e => |pair| try aig.orNodes(
            try lowerExpr(aig, pair[0], env),
            try lowerExpr(aig, pair[1], env),
        ),
        .xor_e => |pair| try aig.xorNodes(
            try lowerExpr(aig, pair[0], env),
            try lowerExpr(aig, pair[1], env),
        ),
    };
}

fn checkNative(allocator: std.mem.Allocator, c: Case) !struct { NativeVerdict, u64 } {
    const start = std.time.milliTimestamp();
    var aig = prover.Aig.init(allocator);
    defer aig.deinit();

    var env: [8]prover.NodeId = undefined;
    var vi: u8 = 0;
    while (vi < c.num_vars) : (vi += 1) {
        env[vi] = try aig.createInput();
        aig.setInputSimValue(env[vi], 0xA5A5_A5A5_A5A5_A5A5 ^ (@as(u64, vi) * 0x1111_1111_1111_1111));
    }

    const left = try lowerExpr(&aig, c.left, env[0..c.num_vars]);
    const right = try lowerExpr(&aig, c.right, env[0..c.num_vars]);
    const miter = try aig.createMiter(left, right);

    var solver = try aig.toSat(allocator);
    defer solver.deinit();
    try solver.addClause(&[_]prover.Lit{litAssertTrue(miter)});

    const sat = solver.solve();
    const elapsed: u64 = @intCast(std.time.milliTimestamp() - start);
    return .{ if (sat) .different else .equivalent, elapsed };
}

fn emitExpr(w: anytype, e: *const Expr) !void {
    switch (e.*) {
        .var_id => |v| try w.print("v_{d}", .{v}),
        .c0 => try w.writeAll("false"),
        .c1 => try w.writeAll("true"),
        .not_e => |p| {
            try w.writeAll("(not ");
            try emitExpr(w, p);
            try w.writeAll(")");
        },
        .and_e => |pair| {
            try w.writeAll("(and ");
            try emitExpr(w, pair[0]);
            try w.writeAll(" ");
            try emitExpr(w, pair[1]);
            try w.writeAll(")");
        },
        .or_e => |pair| {
            try w.writeAll("(or ");
            try emitExpr(w, pair[0]);
            try w.writeAll(" ");
            try emitExpr(w, pair[1]);
            try w.writeAll(")");
        },
        .xor_e => |pair| {
            try w.writeAll("(or (and ");
            try emitExpr(w, pair[0]);
            try w.writeAll(" (not ");
            try emitExpr(w, pair[1]);
            try w.writeAll(")) (and (not ");
            try emitExpr(w, pair[0]);
            try w.writeAll(") ");
            try emitExpr(w, pair[1]);
            try w.writeAll("))");
        },
    }
}

fn emitZ3Equivalence(allocator: std.mem.Allocator, c: Case) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    const w = buf.writer();
    try w.writeAll("(set-logic QF_UF)\n");
    var vi: u8 = 0;
    while (vi < c.num_vars) : (vi += 1) {
        try w.print("(declare-const v_{d} Bool)\n", .{vi});
    }
    try w.writeAll("(assert (not (= ");
    try emitExpr(w, c.left);
    try w.writeAll(" ");
    try emitExpr(w, c.right);
    try w.writeAll(")))\n(check-sat)\n");
    return buf.toOwnedSlice();
}

fn checkZ3(allocator: std.mem.Allocator, c: Case, timeout_ms: u32) !struct { Z3Verdict, u64 } {
    const smt_text = try emitZ3Equivalence(allocator, c);
    defer allocator.free(smt_text);
    const res = try smt.runSmtLib(allocator, smt_text, timeout_ms);
    defer if (res.verdict == .counter_example or res.verdict == .error_smt) allocator.free(res.detail);
    const z3_v: Z3Verdict = switch (res.verdict) {
        .verified => .equivalent,
        .counter_example => .different,
        .unknown => .unknown,
        .error_smt => .fault,
    };
    return .{ z3_v, res.elapsed_ms };
}

fn verdictsAgree(n: NativeVerdict, z: Z3Verdict) bool {
    return switch (n) {
        .equivalent => z == .equivalent,
        .different => z == .different,
        .fault => false,
    };
}

fn addCase(list: *std.ArrayList(Case), name: []const u8, expect: bool, l: *const Expr, r: *const Expr, nv: u8) !void {
    try list.append(.{ .name = name, .expect_equiv = expect, .left = l, .right = r, .num_vars = nv });
}

fn buildBattery(allocator: std.mem.Allocator, names: std.mem.Allocator) ![]Case {
    var list = std.ArrayList(Case).init(allocator);
    errdefer list.deinit();
    var eb = Eb{ .a = allocator };

    const a = try eb.v(0);
    const b = try eb.v(1);
    const c = try eb.v(2);
    const c0 = try eb.c0();
    const c1 = try eb.c1();
    const na = try eb.not(a);
    const nb = try eb.not(b);

    try addCase(&list, "idempotence_and", true, try eb.land(a, a), a, 1);
    try addCase(&list, "idempotence_or", true, try eb.lor(a, a), a, 1);
    try addCase(&list, "xor_self_zero", true, try eb.lxor(a, a), c0, 1);
    try addCase(&list, "and_zero", true, try eb.land(a, c0), c0, 1);
    try addCase(&list, "or_one", true, try eb.lor(a, c1), c1, 1);
    try addCase(&list, "and_one", true, try eb.land(a, c1), a, 1);
    try addCase(&list, "or_zero", true, try eb.lor(a, c0), a, 1);
    try addCase(&list, "complement_and", true, try eb.land(a, na), c0, 1);
    try addCase(&list, "complement_or", true, try eb.lor(a, na), c1, 1);
    try addCase(&list, "double_negation", true, try eb.not(na), a, 1);
    try addCase(&list, "demorgan_and", true, try eb.not(try eb.land(a, b)), try eb.lor(na, nb), 2);
    try addCase(&list, "demorgan_or", true, try eb.not(try eb.lor(a, b)), try eb.land(na, nb), 2);
    try addCase(&list, "absorption_or", true, try eb.lor(a, try eb.land(a, b)), a, 2);
    try addCase(&list, "absorption_and", true, try eb.land(a, try eb.lor(a, b)), a, 2);
    try addCase(&list, "distributivity", true, try eb.land(a, try eb.lor(b, c)), try eb.lor(try eb.land(a, b), try eb.land(a, c)), 3);
    try addCase(&list, "xor_identity", true, try eb.lxor(a, c0), a, 1);
    try addCase(&list, "xor_not", true, try eb.lxor(a, c1), na, 1);
    try addCase(&list, "commutativity_and", true, try eb.land(a, b), try eb.land(b, a), 2);
    try addCase(&list, "commutativity_or", true, try eb.lor(a, b), try eb.lor(b, a), 2);
    try addCase(&list, "commutativity_xor", true, try eb.lxor(a, b), try eb.lxor(b, a), 2);
    try addCase(&list, "associativity_and", true, try eb.land(a, try eb.land(b, c)), try eb.land(try eb.land(a, b), c), 3);
    try addCase(&list, "associativity_or", true, try eb.lor(a, try eb.lor(b, c)), try eb.lor(try eb.lor(a, b), c), 3);
    try addCase(&list, "consensus_invalid", false, try eb.lor(try eb.land(a, b), try eb.land(na, c)), try eb.lor(a, try eb.land(b, c)), 3);

    try addCase(&list, "neq_a_not_a", false, a, na, 1);
    try addCase(&list, "neq_and_or", false, try eb.land(a, b), try eb.lor(a, b), 2);
    try addCase(&list, "neq_xor_and", false, try eb.lxor(a, b), try eb.land(a, b), 2);
    try addCase(&list, "neq_a_const0", false, a, c0, 1);
    try addCase(&list, "neq_a_const1", false, a, c1, 1);
    try addCase(&list, "neq_abs_wrong", false, try eb.lor(a, try eb.land(a, b)), b, 2);
    try addCase(&list, "neq_demorgan_break", false, try eb.not(try eb.land(a, b)), try eb.not(try eb.lor(a, b)), 2);

    const v0 = try eb.v(0);
    const v1 = try eb.v(1);
    const v2 = try eb.v(2);
    const nv0 = try eb.not(v0);
    const nv1 = try eb.not(v1);
    const nv2 = try eb.not(v2);
    try addCase(&list, "sweep_id_and_v0", true, try eb.land(v0, v0), v0, 1);
    try addCase(&list, "sweep_xor_self_v0", true, try eb.lxor(v0, v0), c0, 1);
    try addCase(&list, "sweep_neq_v0", false, v0, nv0, 1);
    try addCase(&list, "sweep_id_and_v1", true, try eb.land(v1, v1), v1, 2);
    try addCase(&list, "sweep_xor_self_v1", true, try eb.lxor(v1, v1), c0, 2);
    try addCase(&list, "sweep_neq_v1", false, v1, nv1, 2);
    try addCase(&list, "sweep_id_and_v2", true, try eb.land(v2, v2), v2, 3);
    try addCase(&list, "sweep_xor_self_v2", true, try eb.lxor(v2, v2), c0, 3);
    try addCase(&list, "sweep_neq_v2", false, v2, nv2, 3);

    const tpl_inv_l = try eb.not(nv0);
    const tpl_and_comm_l = try eb.land(v0, v1);
    const tpl_and_comm_r = try eb.land(v1, v0);
    const tpl_or_comm_l = try eb.lor(v0, v1);
    const tpl_or_comm_r = try eb.lor(v1, v0);
    const tpl_xor_comm_l = try eb.lxor(v0, v1);
    const tpl_xor_comm_r = try eb.lxor(v1, v0);
    const tpl_and_or_l = try eb.land(v0, v1);
    const tpl_and_or_r = try eb.lor(v0, v1);
    const tpl_xor_or_l = try eb.lxor(v0, v1);
    const tpl_xor_or_r = try eb.lor(v0, v1);
    const tpl_nested_l = try eb.not(try eb.land(v0, nv1));
    const tpl_nested_r = try eb.lor(nv0, v1);
    const tpl_abs_l = try eb.lor(v0, try eb.land(v0, v1));

    const templates = [_]struct { []const u8, *const Expr, *const Expr, u8, bool }{
        .{ "tpl_involution", tpl_inv_l, v0, 1, true },
        .{ "tpl_and_comm", tpl_and_comm_l, tpl_and_comm_r, 2, true },
        .{ "tpl_or_comm", tpl_or_comm_l, tpl_or_comm_r, 2, true },
        .{ "tpl_xor_comm", tpl_xor_comm_l, tpl_xor_comm_r, 2, true },
        .{ "tpl_and_or_neq", tpl_and_or_l, tpl_and_or_r, 2, false },
        .{ "tpl_xor_or_neq", tpl_xor_or_l, tpl_xor_or_r, 2, false },
        .{ "tpl_nested_dem", tpl_nested_l, tpl_nested_r, 2, true },
        .{ "tpl_absorption", tpl_abs_l, v0, 2, true },
    };

    var rng = std.Random.DefaultPrng.init(0x6049_0000_0049);
    const random = rng.random();
    var i: usize = 0;
    while (i < 60) : (i += 1) {
        const t = templates[random.intRangeAtMost(usize, 0, templates.len - 1)];
        const nm = try std.fmt.allocPrint(names, "{s}_{d}", .{ t[0], i });
        try list.append(.{
            .name = nm,
            .expect_equiv = t[4],
            .left = t[1],
            .right = t[2],
            .num_vars = t[3],
        });
    }

    return list.toOwnedSlice();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const aalloc = arena.allocator();

    var max_cases: ?usize = null;
    var timeout_ms: u32 = 5_000;
    var json_path: ?[]const u8 = null;

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    for (args) |a| {
        if (std.mem.startsWith(u8, a, "--cases=")) {
            max_cases = try std.fmt.parseInt(usize, a["--cases=".len..], 10);
        } else if (std.mem.startsWith(u8, a, "--timeout-ms=")) {
            timeout_ms = try std.fmt.parseInt(u32, a["--timeout-ms=".len..], 10);
        } else if (std.mem.startsWith(u8, a, "--json=")) {
            json_path = a["--json=".len..];
        }
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== G49 Z3 Cross-Audit: native_prover vs libz3 ===\n", .{});
    try stdout.print("timeout_ms={d}\n\n", .{timeout_ms});

    const battery = try buildBattery(aalloc, alloc);
    defer alloc.free(battery);

    const limit = max_cases orelse battery.len;
    var rows = std.ArrayList(Row).init(alloc);
    defer rows.deinit();

    var idx: usize = 0;
    while (idx < limit and idx < battery.len) : (idx += 1) {
        const c = battery[idx];
        const native_r = try checkNative(alloc, c);
        const z3_r = try checkZ3(alloc, c, timeout_ms);
        const agree = verdictsAgree(native_r[0], z3_r[0]);
        try rows.append(.{
            .name = c.name,
            .expect_equiv = c.expect_equiv,
            .native_v = native_r[0],
            .z3_v = z3_r[0],
            .agree = agree,
            .native_ms = native_r[1],
            .z3_ms = z3_r[1],
        });
        if (!agree) {
            try stdout.print("  DISAGREE [{s}] expect={} native={s} z3={s}\n", .{
                c.name, c.expect_equiv, @tagName(native_r[0]), @tagName(z3_r[0]),
            });
        }
    }

    var agree_count: usize = 0;
    var decisive_count: usize = 0;
    var disagree: usize = 0;
    var native_errors: usize = 0;
    var z3_unknown: usize = 0;
    var expect_match_native: usize = 0;
    var expect_match_z3: usize = 0;

    for (rows.items) |r| {
        if (r.agree) agree_count += 1;
        const z3_decisive = r.z3_v == .equivalent or r.z3_v == .different;
        if (r.native_v != .fault and z3_decisive) decisive_count += 1;
        if (!r.agree) disagree += 1;
        if (r.native_v == .fault) native_errors += 1;
        if (r.z3_v == .unknown) z3_unknown += 1;
        if ((r.native_v == .equivalent) == r.expect_equiv) expect_match_native += 1;
        if ((r.z3_v == .equivalent) == r.expect_equiv) expect_match_z3 += 1;
    }

    const total = rows.items.len;
    const agreement_pct = if (total == 0) 0.0 else @as(f64, @floatFromInt(agree_count)) * 100.0 / @as(f64, @floatFromInt(total));
    const pass = disagree == 0 and native_errors == 0 and z3_unknown == 0 and expect_match_native == total and expect_match_z3 == total;

    try stdout.print("\n=== SUMMARY ===\n", .{});
    try stdout.print("cases_run: {d}\n", .{total});
    try stdout.print("agreement: {d}/{d} ({d:.2}%)\n", .{ agree_count, total, agreement_pct });
    try stdout.print("disagreements: {d}\n", .{disagree});
    try stdout.print("native_errors: {d}\n", .{native_errors});
    try stdout.print("z3_unknown: {d}\n", .{z3_unknown});
    try stdout.print("expect_match_native: {d}/{d}\n", .{ expect_match_native, total });
    try stdout.print("expect_match_z3: {d}/{d}\n", .{ expect_match_z3, total });
    try stdout.print("VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});

    if (json_path) |jp| {
        var jbuf = std.ArrayList(u8).init(alloc);
        defer jbuf.deinit();
        const jw = jbuf.writer();
        try jw.writeAll("{\n");
        try jw.print("  \"cases_run\": {d},\n", .{total});
        try jw.print("  \"agreement_pct\": {d:.4},\n", .{agreement_pct});
        try jw.print("  \"disagreements\": {d},\n", .{disagree});
        try jw.print("  \"verdict\": \"{s}\"\n", .{if (pass) "PASS" else "FAIL"});
        try jw.writeAll("}\n");
        try std.fs.cwd().writeFile(.{ .sub_path = jp, .data = jbuf.items });
    }
}