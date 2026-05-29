const std = @import("std");
const domain = @import("domain_u64_mixer_mulfree");
const verify = @import("smt_verify");

// ─────────────────────────────────────────────────────────────────────────
// AFFINE-CLOSURE ANALYZER  (Tier-A of the MUL-necessity proof program)
//
// φ (the property):  For a mixer program P over the LINEAR opset
//   L_lin = { XOR, ROTL, ROTR, SHL_XOR, SHR_XOR, BSWAP }
// with the fixed register initialization used by the runtime, the function
// P : GF(2)^64 → GF(2)^64 is AFFINE:  ∃ M ∈ GF(2)^{64×64}, c ∈ GF(2)^64 such
// that P(x) = M·x + c for all x.  An affine recurrence x_{n+1} = M·x_n + c
// satisfies a GF(2) linear recurrence of order ≤ 64 (Cayley–Hamilton), so its
// output stream has bounded binary rank — which is exactly what PractRand's
// BRank test detected as the failure mode of every committed constrained
// champion (`BRank(12):score:256(10)`).
//
// This turns the EMPIRICAL observation "MUL-free search collapses to xorshift
// cascades that fail BRank" into a PROVABLE statement about the subspace the
// search lives in.
//
// THREE INDEPENDENT WITNESSES (Dual-Proof discipline, extended):
//   1. GF(2) matrix tracker (this file, pure linear algebra) → explicit (M,c)
//      + rank(M).  Constructive.  Refuses to claim affinity if any nonlinear
//      op (ADD*, AND_NOT, OR_SHIFT, MUL, MUM, SPLITMIX) is present.
//   2. Numerical spot-check: M·x + c == domain.Program.execute(x) over many
//      random x, using the REAL runtime execute().  Independent of (1) and (3).
//   3. Z3: UNSAT on  ∃X: P(X) ≠ M·X + c , with RUNTIME-FAITHFUL shift
//      semantics (shift = imm%63+1).  All-inputs symbolic guarantee.
//
// NOTE (audit catch): smt_verify.zig models shift as `imm & 63`, but the
// runtime (domain_u64_mixer_mulfree.execute) uses `imm % 63 + 1`.  For an
// all-shift program those are DIFFERENT programs, so we do NOT reuse
// smt_verify's op-emitter for shifts here — only its Z3 runner (runSmtLib).
// ─────────────────────────────────────────────────────────────────────────

const K1: u64 = 0x9E3779B97F4A7C15;
const K2: u64 = 0xBF58476D1CE4E5B9;
const K3: u64 = 0x94D049BB133111EB;

// Runtime shift amount (mirrors private domain.shift63): range 1..63.
fn shift63(imm: u64) u6 {
    return @as(u6, @intCast(imm % 63 + 1));
}

// An affine form over the 64 input bits.
//   value bit j  =  ( XOR over i in coeff[j] of x_i )  XOR  konst_j
// coeff[j] is the row of M for output bit j (bit i set ⇒ x_i feeds bit j).
const Affine = struct {
    coeff: [64]u64,
    konst: u64,

    fn identity() Affine {
        var a = Affine{ .coeff = [_]u64{0} ** 64, .konst = 0 };
        var j: usize = 0;
        while (j < 64) : (j += 1) a.coeff[j] = @as(u64, 1) << @intCast(j);
        return a;
    }

    fn constant(v: u64) Affine {
        return Affine{ .coeff = [_]u64{0} ** 64, .konst = v };
    }

    fn xorWith(a: Affine, b: Affine) Affine {
        var r = Affine{ .coeff = undefined, .konst = a.konst ^ b.konst };
        var j: usize = 0;
        while (j < 64) : (j += 1) r.coeff[j] = a.coeff[j] ^ b.coeff[j];
        return r;
    }

    // value << s  (logical):  out bit j = in bit (j-s) for j>=s else 0.
    fn shl(a: Affine, s: u6) Affine {
        var r = Affine{ .coeff = [_]u64{0} ** 64, .konst = a.konst << s };
        var j: usize = s;
        while (j < 64) : (j += 1) r.coeff[j] = a.coeff[j - s];
        return r;
    }

    // value >> s  (logical):  out bit j = in bit (j+s) for j+s<64 else 0.
    fn shr(a: Affine, s: u6) Affine {
        var r = Affine{ .coeff = [_]u64{0} ** 64, .konst = a.konst >> s };
        var j: usize = 0;
        while (j + @as(usize, s) < 64) : (j += 1) r.coeff[j] = a.coeff[j + s];
        return r;
    }

    fn rotl(a: Affine, s: u6) Affine {
        var r = Affine{ .coeff = undefined, .konst = std.math.rotl(u64, a.konst, @as(u64, s)) };
        var j: usize = 0;
        while (j < 64) : (j += 1) r.coeff[j] = a.coeff[(j + 64 - @as(usize, s)) % 64];
        return r;
    }

    fn rotr(a: Affine, s: u6) Affine {
        var r = Affine{ .coeff = undefined, .konst = std.math.rotr(u64, a.konst, @as(u64, s)) };
        var j: usize = 0;
        while (j < 64) : (j += 1) r.coeff[j] = a.coeff[(j + @as(usize, s)) % 64];
        return r;
    }

    // @byteSwap: result byte b = source byte (7-b); bit-in-byte preserved.
    fn bswap(a: Affine) Affine {
        var r = Affine{ .coeff = undefined, .konst = @byteSwap(a.konst) };
        var p: usize = 0;
        while (p < 64) : (p += 1) {
            const byte = p / 8;
            const off = p % 8;
            r.coeff[p] = a.coeff[8 * (7 - byte) + off];
        }
        return r;
    }
};

const TrackResult = struct {
    out: Affine,
    nonlinear: ?domain.Op, // first nonlinear op encountered, if any
    linear_ops: usize,
};

// Symbolically execute P, mirroring domain.Program.execute, but carrying
// affine forms instead of concrete values. Returns the affine form of the
// output register (reg[NumRegs-1]) — or flags the first nonlinear op.
fn trackAffine(p: domain.Program) TrackResult {
    var regs: [domain.NumRegs]Affine = undefined;
    regs[0] = Affine.identity();
    regs[1] = Affine.constant(K1);
    regs[2] = Affine.constant(K2);
    regs[3] = Affine.constant(K3);
    var r: usize = 4;
    while (r < domain.NumRegs) : (r += 1) regs[r] = Affine.constant(0);

    var linear_ops: usize = 0;
    var i: usize = 0;
    while (i < p.used) : (i += 1) {
        const inst = p.instructions[i];
        const a = regs[inst.src1];
        const b = regs[inst.src2];
        const s = shift63(inst.imm);
        const result: Affine = switch (inst.op) {
            .XOR => a.xorWith(b),
            .ROTL => a.rotl(s),
            .ROTR => a.rotr(s),
            .SHL_XOR => a.xorWith(a.shl(s)),
            .SHR_XOR => a.xorWith(a.shr(s)),
            .BSWAP => a.bswap(),
            // Everything below leaves the affine subspace (carry chains or
            // AND/OR/MUL bit products). Tier A says nothing about them.
            .ADD, .ADD_CONST, .ADD_ROT, .AND_NOT, .OR_SHIFT, .MUL, .MUM, .SPLITMIX_STEP, .CALL_LIB => {
                return .{ .out = regs[domain.NumRegs - 1], .nonlinear = inst.op, .linear_ops = linear_ops };
            },
        };
        regs[inst.dst] = result;
        linear_ops += 1;
    }
    return .{ .out = regs[domain.NumRegs - 1], .nonlinear = null, .linear_ops = linear_ops };
}

// GF(2) rank of the 64 row-vectors (= rank of M; row rank = column rank).
fn gf2Rank(rows: [64]u64) usize {
    var basis = [_]u64{0} ** 64; // basis[lead] holds a vector whose leading set bit is `lead`
    var rank: usize = 0;
    for (rows) |row| {
        var v = row;
        while (v != 0) {
            const lead: u6 = @intCast(63 - @clz(v));
            if (basis[lead] == 0) {
                basis[lead] = v;
                rank += 1;
                break;
            }
            v ^= basis[lead];
        }
    }
    return rank;
}

// Evaluate the affine model y = M·x + c on a concrete input.
fn affineEval(coeff: [64]u64, konst: u64, x: u64) u64 {
    var y: u64 = konst;
    var j: usize = 0;
    while (j < 64) : (j += 1) {
        const par: u64 = @popCount(coeff[j] & x) & 1;
        y ^= par << @intCast(j);
    }
    return y;
}

// ─── Witness 3: runtime-faithful SMT for  ∃X: P(X) ≠ M·X + c ───────────────
fn buildAffinitySmt(
    allocator: std.mem.Allocator,
    p: domain.Program,
    coeff: [64]u64,
    konst: u64,
) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    const w = buf.writer();

    try w.writeAll("(set-logic QF_BV)\n");
    try w.writeAll("(declare-const X (_ BitVec 64))\n");

    // ── Program P(X), SSA over 8 registers, runtime semantics ──
    var ver: [domain.NumRegs]u32 = [_]u32{0} ** domain.NumRegs;
    try w.writeAll("(declare-const p_r0_v0 (_ BitVec 64))\n(assert (= p_r0_v0 X))\n");
    const inits = [_]u64{ 0, K1, K2, K3, 0, 0, 0, 0 };
    var r: usize = 1;
    while (r < domain.NumRegs) : (r += 1) {
        try w.print("(declare-const p_r{d}_v0 (_ BitVec 64))\n(assert (= p_r{d}_v0 (_ bv{d} 64)))\n", .{ r, r, inits[r] });
    }

    var i: usize = 0;
    while (i < p.used) : (i += 1) {
        const inst = p.instructions[i];
        const av = ver[inst.src1];
        const bv = ver[inst.src2];
        const dv = ver[inst.dst] + 1;
        ver[inst.dst] = dv;
        const sh: u64 = shift63(inst.imm);
        try w.print("(declare-const p_r{d}_v{d} (_ BitVec 64))\n", .{ inst.dst, dv });
        switch (inst.op) {
            .XOR => try w.print(
                "(assert (= p_r{d}_v{d} (bvxor p_r{d}_v{d} p_r{d}_v{d})))\n",
                .{ inst.dst, dv, inst.src1, av, inst.src2, bv },
            ),
            .SHL_XOR => try w.print(
                "(assert (= p_r{d}_v{d} (bvxor p_r{d}_v{d} (bvshl p_r{d}_v{d} (_ bv{d} 64)))))\n",
                .{ inst.dst, dv, inst.src1, av, inst.src1, av, sh },
            ),
            .SHR_XOR => try w.print(
                "(assert (= p_r{d}_v{d} (bvxor p_r{d}_v{d} (bvlshr p_r{d}_v{d} (_ bv{d} 64)))))\n",
                .{ inst.dst, dv, inst.src1, av, inst.src1, av, sh },
            ),
            .ROTL => try w.print(
                "(assert (= p_r{d}_v{d} ((_ rotate_left {d}) p_r{d}_v{d})))\n",
                .{ inst.dst, dv, sh, inst.src1, av },
            ),
            .ROTR => try w.print(
                "(assert (= p_r{d}_v{d} ((_ rotate_right {d}) p_r{d}_v{d})))\n",
                .{ inst.dst, dv, sh, inst.src1, av },
            ),
            .BSWAP => try w.print(
                "(assert (= p_r{d}_v{d} (concat ((_ extract 7 0) p_r{d}_v{d}) ((_ extract 15 8) p_r{d}_v{d}) ((_ extract 23 16) p_r{d}_v{d}) ((_ extract 31 24) p_r{d}_v{d}) ((_ extract 39 32) p_r{d}_v{d}) ((_ extract 47 40) p_r{d}_v{d}) ((_ extract 55 48) p_r{d}_v{d}) ((_ extract 63 56) p_r{d}_v{d}))))\n",
                .{ inst.dst, dv, inst.src1, av, inst.src1, av, inst.src1, av, inst.src1, av, inst.src1, av, inst.src1, av, inst.src1, av, inst.src1, av },
            ),
            else => return error.NonLinearOpInSmt, // unreachable: tracker gates this
        }
    }
    const out_reg = domain.NumRegs - 1;
    const out_ver = ver[out_reg];

    // ── Model  M·X + c  as concat of 64 one-bit expressions ──
    try w.writeAll("(declare-const MODEL (_ BitVec 64))\n(assert (= MODEL (concat");
    var jj: isize = 63;
    while (jj >= 0) : (jj -= 1) {
        const j: usize = @intCast(jj);
        const kbit: u1 = @intCast((konst >> @intCast(j)) & 1);
        // collect input-bit terms
        var terms: usize = @popCount(coeff[j]);
        if (kbit == 1) terms += 1;
        if (terms == 0) {
            try w.writeAll(" (_ bv0 1)");
        } else if (terms == 1) {
            if (kbit == 1 and coeff[j] == 0) {
                try w.writeAll(" (_ bv1 1)");
            } else {
                const i_only: usize = @ctz(coeff[j]);
                try w.print(" ((_ extract {d} {d}) X)", .{ i_only, i_only });
            }
        } else {
            try w.writeAll(" (bvxor");
            var m = coeff[j];
            while (m != 0) {
                const i_bit: usize = @ctz(m);
                try w.print(" ((_ extract {d} {d}) X)", .{ i_bit, i_bit });
                m &= m - 1;
            }
            if (kbit == 1) try w.writeAll(" (_ bv1 1)");
            try w.writeAll(")");
        }
    }
    try w.writeAll(")))\n");

    // ── Negation of equivalence: a witness where P and the model differ ──
    try w.print("(assert (distinct p_r{d}_v{d} MODEL))\n", .{ out_reg, out_ver });
    try w.writeAll("(check-sat)\n");
    return buf.toOwnedSlice();
}

fn xrng(state: *u64) u64 {
    // splitmix64
    state.* +%= 0x9E3779B97F4A7C15;
    var z = state.*;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    var csv_path: []const u8 = "";
    var samples: usize = 1 << 18;
    var timeout_ms: u32 = 60_000;
    var dump_smt = false;
    var z3_enabled = true;
    for (args) |a| {
        if (std.mem.startsWith(u8, a, "--csv=")) csv_path = a["--csv=".len..]
        else if (std.mem.startsWith(u8, a, "--samples=")) samples = std.fmt.parseInt(usize, a["--samples=".len..], 10) catch samples
        else if (std.mem.startsWith(u8, a, "--timeout-ms=")) timeout_ms = std.fmt.parseInt(u32, a["--timeout-ms=".len..], 10) catch timeout_ms
        else if (std.mem.startsWith(u8, a, "--z3=")) z3_enabled = !std.mem.eql(u8, a["--z3=".len..], "0")
        else if (std.mem.eql(u8, a, "--dump-smt")) dump_smt = true;
    }

    const out = std.io.getStdOut().writer();
    if (csv_path.len == 0) {
        try std.io.getStdErr().writer().writeAll("usage: affine_closure --csv=PATH [--samples=N] [--timeout-ms=N] [--z3=0|1] [--dump-smt]\n");
        return error.MissingArg;
    }

    const prog = try domain.programFromCsv(alloc, csv_path);
    try out.print("affine_closure  csv={s}  used={d}\n", .{ csv_path, prog.used });

    // ── Witness 1: constructive GF(2) tracker ──
    const tr = trackAffine(prog);
    if (tr.nonlinear) |op| {
        try out.print("\nVERDICT: NON-AFFINE (op {s} present) — Tier A inapplicable to this program.\n", .{domain.opName(op)});
        try out.print("This program leaves the GF(2)-affine subspace; the affine-closure theorem does not cover it.\n", .{});
        return;
    }
    const M = tr.out.coeff;
    const c = tr.out.konst;
    const rank = gf2Rank(M);
    try out.print("\n[W1] tracker: all {d} ops linear (L_lin). rank(M) over GF(2) = {d}/64  ({s} as a linear map)\n", .{
        tr.linear_ops, rank,
        if (rank == 64) "invertible — affine bijection" else "rank-deficient — NOT a bijection",
    });
    try out.print("     constant c = 0x{X:0>16}\n", .{c});

    // ── Witness 2: numerical M·x+c == real runtime execute(x) ──
    var state: u64 = 0xA5A5_5A5A_1234_9876;
    var mismatches: usize = 0;
    var first_bad_x: u64 = 0;
    var n: usize = 0;
    while (n < samples) : (n += 1) {
        const x = xrng(&state);
        const model = affineEval(M, c, x);
        const real = prog.execute(x);
        if (model != real) {
            if (mismatches == 0) first_bad_x = x;
            mismatches += 1;
        }
    }
    // include structural edge cases
    for ([_]u64{ 0, 1, ~@as(u64, 0), 0x8000_0000_0000_0000, K1, K2, K3 }) |x| {
        if (affineEval(M, c, x) != prog.execute(x)) {
            if (mismatches == 0) first_bad_x = x;
            mismatches += 1;
        }
    }
    if (mismatches == 0) {
        try out.print("[W2] numerical: M·x+c == runtime execute(x) on {d} random + 7 edge inputs — MATCH\n", .{samples});
    } else {
        try out.print("[W2] numerical: {d} MISMATCHES (first at x=0x{X:0>16}) — tracker is WRONG, halting affine claim\n", .{ mismatches, first_bad_x });
        try out.print("\nVERDICT: CRACKED (witness 2) — affine model disagrees with runtime.\n", .{});
        return;
    }

    // ── Witness 2b: DETERMINISTIC all-inputs proof via the affine basis ──
    // P is affine (W1), so it is fully determined by its values on the 65-point
    // affine basis {0, e_0 .. e_63}: for any x = XOR of unit vectors e_i,
    // P(x) = P(0) XOR ( XOR_i [P(e_i) XOR P(0)] ). If the model and the runtime
    // agree on those 65 points, they are identical on ALL 2^64 inputs — no
    // sampling, no solver. This is the real all-inputs proof; W3 is a bonus.
    var basis_ok = true;
    var bad_basis: i64 = -2;
    if (affineEval(M, c, 0) != prog.execute(0)) {
        basis_ok = false;
        bad_basis = -1; // the constant term (x=0)
    } else {
        var bi: usize = 0;
        while (bi < 64) : (bi += 1) {
            const x = @as(u64, 1) << @intCast(bi);
            if (affineEval(M, c, x) != prog.execute(x)) {
                basis_ok = false;
                bad_basis = @intCast(bi);
                break;
            }
        }
    }
    if (basis_ok) {
        try out.print("[W2b] affine-basis: model == runtime on all 65 basis points {{0, e_0..e_63}} — PROVEN EXACT over all 2^64 inputs (P affine ⇒ basis determines P)\n", .{});
    } else {
        try out.print("[W2b] affine-basis: MISMATCH at {s} — model is NOT the affine closure of P\n", .{
            if (bad_basis == -1) "x=0 (constant term)" else "a unit vector e_i",
        });
        try out.print("\nVERDICT: CRACKED (witness 2b).\n", .{});
        return;
    }

    if (!z3_enabled) {
        try out.print("[W3] Z3: skipped (--z3=0). All-inputs proof already established by W1+W2b.\n", .{});
        try printAffineVerdict(out, rank);
        return;
    }

    // ── Witness 3: Z3 over all 2^64 inputs (REDUNDANT bonus oracle) ──
    // NOTE: 64-bit XOR/shift-circuit equivalence is near-worst-case for CDCL
    // SAT (XOR reasoning); Z3 can exceed 30 min on diffusion-dense programs.
    // This is a *redundant* re-derivation — the verdict rests on W1+W2b.
    const smt = try buildAffinitySmt(alloc, prog, M, c);
    defer alloc.free(smt);
    if (dump_smt) {
        try out.writeAll("\n--- SMT-LIB2 ---\n");
        try out.writeAll(smt);
        try out.writeAll("--- end SMT ---\n");
    }
    const z3 = try verify.runSmtLib(alloc, smt, timeout_ms);
    switch (z3.verdict) {
        .verified => try out.print("[W3] Z3: UNSAT on ∃X P(X)≠M·X+c — affine model EXACT over all 2^64 inputs ({d} ms)\n", .{z3.elapsed_ms}),
        .counter_example => {
            try out.print("[W3] Z3: SAT — found X where P(X) ≠ M·X+c ({d} ms). Tracker/emitter WRONG.\n", .{z3.elapsed_ms});
            try out.print("detail:\n{s}\n\nVERDICT: CRACKED (witness 3).\n", .{z3.detail});
            return;
        },
        .unknown => {
            try out.print("[W3] Z3: UNKNOWN/timeout ({d} ms) — redundant oracle inconclusive (XOR-equivalence is hard for CDCL). The all-inputs proof already stands on W1+W2b.\n", .{z3.elapsed_ms});
        },
        .error_smt => {
            try out.print("[W3] Z3: ERROR — {s}\n", .{z3.detail});
            return;
        },
    }

    try printAffineVerdict(out, rank);
}

fn printAffineVerdict(out: anytype, rank: usize) !void {
    try out.print(
        \\
        \\VERDICT: AFFINE_CONFIRMED.
        \\  P(x) = M·x + c with rank(M) = {d}/64, proven exact over all 2^64 inputs (W1+W2b).
        \\  An affine recurrence x_{{n+1}} = M·x_n + c obeys a GF(2) linear recurrence
        \\  of order ≤ 64 (Cayley–Hamilton), so the iterated output stream has binary
        \\  rank bounded by ~64 — the structural cause of the BRank(12) failure logged
        \\  for this champion. The "MUL-free fails BRank" result is, for this program,
        \\  a THEOREM about the affine subspace the search collapsed into, not a search
        \\  outcome.
        \\
    , .{rank});
}
