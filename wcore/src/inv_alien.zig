//! The ALIEN substrate — a deliberately non-human primitive space (RESEARCH §2).
//!
//! The lesson from the bricks: a human-shaped op-set (tanh, +, ×, gates) can only
//! re-derive points humans already mapped — give it scan-shaped ops, it finds the
//! scan; give it Mamba-shaped ops, it finds Mamba. Novelty has to come from the
//! SUBSTRATE, not the search loop. So this substrate is built from low-level,
//! non-intuitive integer primitives — the territory humans skip because it doesn't
//! look like the math they trust:
//!
//!   • u64 registers + bit-mixing ops (XOR/AND/OR/SHL/SHR/ROTR/POPCOUNT/MUM/BSWAP)
//!   • an addressable MEMORY bank with DATA-DEPENDENT addresses (load/store)
//!   • comparison/select masks (branchless conditionals)
//!
//! Crucially, NEITHER softmax-attention NOR a clean float running-product is a
//! natural low-complexity point here. Content addressing is reachable — but via
//! HASHING into addressable memory, not via softmax over all pairs. Accumulation
//! is reachable — but via XOR/bit-mixing, not a float recurrence. The two known
//! mechanisms' *capabilities* are reachable by alien routes; whether SEARCH finds
//! a single program that gets BOTH (the empty top-right corner of the Phase-0 map)
//! — and whether that program is novel or a bolted union — is the research question.
//!
//! This file is PHASE 2: the substrate + executor + a hand-written reachability
//! proof (alien programs that reach each corner, and the top-right). The SEARCH
//! over this space is Phase 3 (next). Scoring/fingerprinting mirror inv_frontier
//! exactly so alien programs are graded on the same axes as the known anchors.

const std = @import("std");
const fr = @import("inv_frontier.zig");

pub const R: usize = 12; // u64 registers (persist across positions)
pub const M: usize = 64; // addressable memory cells (≥ MAX_K so hashing CAN be exact)
pub const REG_TOK: u8 = 0; // input: current token (written each position)
pub const REG_TYP: u8 = 1; // input: token type (0=key/binding, 1=value, 2=query)
pub const OUT_P: u8 = 2; // parity output read from here (low bit → sign)
pub const OUT_R: u8 = 3; // recall output read from here (mod VAL_VOCAB → value)

const MUM_C: u64 = 0x9E3779B97F4A7C15;

pub const Op = enum(u8) {
    a_set, // reg[out] = imm
    a_mov, // reg[out] = reg[a]
    a_xor,
    a_and,
    a_or,
    a_add, // wrapping
    a_sub, // wrapping
    a_mul, // wrapping
    a_shl, // reg[a] << (imm & 63)
    a_shr, // reg[a] >> (imm & 63)
    a_rotr, // rotr(reg[a], imm & 63)
    a_popcnt, // @popCount(reg[a])
    a_mum, // x=reg[a]; x*=MUM_C; x^=x>>29  (a strong bit-mixer)
    a_bswap, // @byteSwap(reg[a])
    a_eq, // reg[out] = (reg[a]==reg[b]) ? ~0 : 0   (mask)
    a_sel, // reg[out] = (reg[c]!=0) ? reg[a] : reg[b]
    a_load, // reg[out] = mem[reg[a] % M]
    a_store, // mem[reg[a] % M] = reg[b]
    nop,
    pub fn count() usize {
        return @typeInfo(Op).@"enum".fields.len;
    }
};

pub const Instr = struct { op: Op = .nop, a: u8 = 0, b: u8 = 0, c: u8 = 0, out: u8 = 0, imm: u64 = 0 };

pub const MAX_INSTR: usize = 16;
pub const Component = std.BoundedArray(Instr, MAX_INSTR);

pub const Program = struct {
    setup: Component = .{},
    step: Component = .{},
    pub fn len(self: *const Program) usize {
        return self.setup.len + self.step.len;
    }
};

inline fn ri(i: u8) usize {
    return @as(usize, i) % R;
}

const Machine = struct {
    reg: [R]u64 = [_]u64{0} ** R,
    mem: [M]u64 = [_]u64{0} ** M,

    fn exec(m: *Machine, instrs: []const Instr) void {
        for (instrs) |ins| {
            const sh: u6 = @truncate(ins.imm);
            switch (ins.op) {
                .a_set => m.reg[ri(ins.out)] = ins.imm,
                .a_mov => m.reg[ri(ins.out)] = m.reg[ri(ins.a)],
                .a_xor => m.reg[ri(ins.out)] = m.reg[ri(ins.a)] ^ m.reg[ri(ins.b)],
                .a_and => m.reg[ri(ins.out)] = m.reg[ri(ins.a)] & m.reg[ri(ins.b)],
                .a_or => m.reg[ri(ins.out)] = m.reg[ri(ins.a)] | m.reg[ri(ins.b)],
                .a_add => m.reg[ri(ins.out)] = m.reg[ri(ins.a)] +% m.reg[ri(ins.b)],
                .a_sub => m.reg[ri(ins.out)] = m.reg[ri(ins.a)] -% m.reg[ri(ins.b)],
                .a_mul => m.reg[ri(ins.out)] = m.reg[ri(ins.a)] *% m.reg[ri(ins.b)],
                .a_shl => m.reg[ri(ins.out)] = m.reg[ri(ins.a)] << sh,
                .a_shr => m.reg[ri(ins.out)] = m.reg[ri(ins.a)] >> sh,
                .a_rotr => m.reg[ri(ins.out)] = std.math.rotr(u64, m.reg[ri(ins.a)], @as(u64, sh)),
                .a_popcnt => m.reg[ri(ins.out)] = @popCount(m.reg[ri(ins.a)]),
                .a_mum => {
                    var x = m.reg[ri(ins.a)];
                    x *%= MUM_C;
                    x ^= x >> 29;
                    m.reg[ri(ins.out)] = x;
                },
                .a_bswap => m.reg[ri(ins.out)] = @byteSwap(m.reg[ri(ins.a)]),
                .a_eq => m.reg[ri(ins.out)] = if (m.reg[ri(ins.a)] == m.reg[ri(ins.b)]) ~@as(u64, 0) else 0,
                .a_sel => m.reg[ri(ins.out)] = if (m.reg[ri(ins.c)] != 0) m.reg[ri(ins.a)] else m.reg[ri(ins.b)],
                .a_load => m.reg[ri(ins.out)] = m.mem[m.reg[ri(ins.a)] % M],
                .a_store => m.mem[m.reg[ri(ins.a)] % M] = m.reg[ri(ins.b)],
                .nop => {},
            }
        }
    }
};

// ===========================================================================
// Task drivers — same two tasks as inv_frontier, fed as integer token streams
// ===========================================================================

/// Run prefix-parity: tokens are bits (1 = the symbol −1, 0 = +1). Per-position
/// sign accuracy. `persist`=false models the no-carried-state baseline.
pub fn parityAcc(prog: *const Program, L: usize, n_seq: usize, seed: u64, persist: bool) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var correct: usize = 0;
    var total: usize = 0;
    for (0..n_seq) |_| {
        var m = Machine{};
        m.exec(prog.setup.slice());
        const base = m;
        var par: u1 = 0;
        for (0..L) |_| {
            if (!persist) m = base;
            const neg = rng.boolean(); // true ⇒ symbol is −1
            par ^= @intFromBool(neg);
            m.reg[REG_TOK] = @intFromBool(neg);
            m.reg[REG_TYP] = 0;
            m.exec(prog.step.slice());
            const pred_neg: u1 = @truncate(m.reg[ri(OUT_P)]); // low bit
            total += 1;
            if (pred_neg == par) correct += 1; // both encode "product is −1"
        }
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(total));
}

/// Run associative recall: K binding positions (key in REG_TOK, value in REG_TYP-
/// adjacent channel) then a query. Output read at the final position.
pub fn recallAcc(prog: *const Program, k: usize, n_inst: usize, seed: u64, persist: bool) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var correct: usize = 0;
    for (0..n_inst) |_| {
        const inst = fr.RecallInst.gen(rng, k);
        const pred = runRecall(prog, &inst, persist);
        if (pred == inst.vals[inst.qpos]) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(n_inst));
}

/// DENSE recall grading (the Brick-A fix): present K bindings, then query ALL K
/// keys in RANDOM order and score the fraction retrieved. Random order defeats a
/// "return last value" shortcut; querying every key turns one sparse exact-match
/// into K graded outcomes per instance, giving search a gradient to climb toward
/// the load+store mechanism instead of a flat chance plateau.
pub fn recallAccDense(prog: *const Program, k: usize, n_inst: usize, seed: u64, persist: bool) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var correct: usize = 0;
    var total: usize = 0;
    var order: [fr.MAX_K]usize = undefined;
    for (0..n_inst) |_| {
        const inst = fr.RecallInst.gen(rng, k);
        var m = Machine{};
        m.exec(prog.setup.slice());
        const base = m;
        for (0..k) |i| { // bind
            if (!persist) m = base;
            m.reg[REG_TOK] = inst.keys[i];
            m.reg[REG_TYP] = 0;
            m.reg[5] = @intFromFloat(inst.vals[i]);
            m.exec(prog.step.slice());
        }
        for (0..k) |i| order[i] = i;
        rng.shuffle(usize, order[0..k]);
        for (order[0..k]) |qi| { // query every key, random order
            if (!persist) m = base;
            m.reg[REG_TOK] = inst.keys[qi];
            m.reg[REG_TYP] = 2;
            m.reg[5] = 0;
            m.exec(prog.step.slice());
            const pred = m.reg[ri(OUT_R)] % fr.VAL_VOCAB;
            total += 1;
            if (@as(f64, @floatFromInt(pred)) == inst.vals[qi]) correct += 1;
        }
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(total));
}

/// One recall instance → predicted value. Bindings are presented one per position
/// (key in REG_TOK, value in a third channel reg[4]); the query position carries
/// the query key with type 2. Value channel for the binding goes in reg[5].
fn runRecall(prog: *const Program, inst: *const fr.RecallInst, persist: bool) f64 {
    var m = Machine{};
    m.exec(prog.setup.slice());
    const base = m;
    // K bindings
    for (0..inst.k) |i| {
        if (!persist) m = base;
        m.reg[REG_TOK] = inst.keys[i];
        m.reg[REG_TYP] = 0; // binding
        m.reg[5] = @intFromFloat(inst.vals[i]); // value channel
        m.exec(prog.step.slice());
    }
    // query
    if (!persist) m = base;
    m.reg[REG_TOK] = inst.keys[inst.qpos];
    m.reg[REG_TYP] = 2; // query
    m.reg[5] = 0;
    m.exec(prog.step.slice());
    return @floatFromInt(m.reg[ri(OUT_R)] % fr.VAL_VOCAB);
}

/// PER-KEY COUNTING (the insufficiency task): tokens are symbols from a vocab;
/// per position, output how many times the CURRENT symbol has appeared so far
/// (mod VAL_VOCAB). Neither a scan (one global counter, not per-key) nor a
/// hash-table (stores/retrieves, doesn't accumulate) nor their bolted union can
/// do it — it requires per-key accumulation INSIDE the addressed cell (a fused
/// read-modify-write). Graded per position (a dense signal, like parity).
pub fn countingAcc(prog: *const Program, vocab: usize, L: usize, n_seq: usize, seed: u64, persist: bool) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var counts: [256]usize = undefined;
    var correct: usize = 0;
    var total: usize = 0;
    for (0..n_seq) |_| {
        var m = Machine{};
        m.exec(prog.setup.slice());
        const base = m;
        for (0..vocab) |v| counts[v] = 0;
        for (0..L) |_| {
            if (!persist) m = base;
            const sym = rng.uintLessThan(usize, vocab);
            counts[sym] += 1;
            const truth = counts[sym] % fr.VAL_VOCAB;
            m.reg[REG_TOK] = @as(u64, sym) + 1; // +1 so symbol 0 isn't address 0 only
            m.reg[REG_TYP] = 0;
            m.reg[5] = 0;
            m.exec(prog.step.slice());
            const pred = m.reg[ri(OUT_R)] % fr.VAL_VOCAB;
            total += 1;
            if (pred == truth) correct += 1;
        }
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(total));
}

// ===========================================================================
// Hand-written ALIEN references — the reachability proof
// ===========================================================================

/// XOR-accumulator: parity by bit-mixing, not a float product. step: reg2 ^= tok.
/// Reaches the LENGTH-GEN corner (correct at any L) via an alien route.
pub fn alienXorScan() Program {
    var p = Program{};
    p.step.appendAssumeCapacity(.{ .op = .a_xor, .a = OUT_P, .b = REG_TOK, .out = OUT_P });
    return p;
}

/// Hash-table: content addressing by HASHING into addressable memory, not softmax.
/// step: reg3 = mem[tok % M]; mem[tok % M] = value. Load-before-store means the
/// query position reads the stored binding. Reaches the RECALL corner exactly
/// (M ≥ K ⇒ no collisions), an alien route to attention's capability.
pub fn alienHashTable() Program {
    var p = Program{};
    p.step.appendAssumeCapacity(.{ .op = .a_load, .a = REG_TOK, .out = OUT_R }); // read first
    p.step.appendAssumeCapacity(.{ .op = .a_store, .a = REG_TOK, .b = 5 }); // then bind key→value
    return p;
}

/// The UNION: XOR-accumulate AND hash-table in one step-body, driving the two
/// output registers independently. Reaches the EMPTY TOP-RIGHT corner — proving
/// the alien op-space CAN host a frontier-breaker. (Honest: this is two known
/// mechanisms bolted together, not a unified novel primitive — the certifier will
/// still flag it NOVEL vs the single-mechanism anchors, which is exactly the
/// subtlety Phase 4's gauntlet must resolve.)
pub fn alienUnion() Program {
    var p = Program{};
    p.step.appendAssumeCapacity(.{ .op = .a_xor, .a = OUT_P, .b = REG_TOK, .out = OUT_P });
    p.step.appendAssumeCapacity(.{ .op = .a_load, .a = REG_TOK, .out = OUT_R });
    p.step.appendAssumeCapacity(.{ .op = .a_store, .a = REG_TOK, .b = 5 });
    return p;
}

/// Read-modify-write per-key counter (the fused mechanism the counting task needs):
/// r3 = mem[key]; r3 += 1; mem[key] = r3. Solves counting; is MORE than the bolted
/// union (which has a separate static store and a separate global accumulator).
pub fn alienRMWCounter() Program {
    var p = Program{};
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 6, .imm = 1 }); // r6 = 1
    p.step.appendAssumeCapacity(.{ .op = .a_load, .a = REG_TOK, .out = OUT_R }); // r3 = mem[key]
    p.step.appendAssumeCapacity(.{ .op = .a_add, .a = OUT_R, .b = 6, .out = OUT_R }); // r3 += 1
    p.step.appendAssumeCapacity(.{ .op = .a_store, .a = REG_TOK, .b = OUT_R }); // mem[key] = r3
    return p;
}

// ===========================================================================
// Fingerprint (mirrors inv_frontier.fingerprint, for alien Programs)
// ===========================================================================

/// Compute the SAME 6-feature behavioural fingerprint as inv_frontier, so an
/// alien program can be certified against the known anchors on equal footing.
pub fn fingerprint(prog: *const Program, seed: u64) fr.Fingerprint {
    var fp: fr.Fingerprint = undefined;
    fp[0] = parityAcc(prog, 16, 64, seed, true);
    fp[1] = parityAcc(prog, 256, 16, seed +% 1, true);
    fp[2] = recallAcc(prog, 4, 256, seed +% 2, true);
    fp[3] = recallAcc(prog, 48, 256, seed +% 3, true);
    fp[4] = x0Sensitivity(prog, seed +% 4);
    fp[5] = localAgreement(prog, seed +% 5);
    return fp;
}

fn x0Sensitivity(prog: *const Program, seed: u64) f64 {
    const L: usize = 64;
    const n: usize = 64;
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var bits: [512]u1 = undefined;
    var a: [512]u1 = undefined;
    var b: [512]u1 = undefined;
    var flips: usize = 0;
    var total: usize = 0;
    for (0..n) |_| {
        for (0..L) |i| bits[i] = @intFromBool(rng.boolean());
        runParityBits(prog, bits[0..L], a[0..L]);
        bits[0] ^= 1;
        runParityBits(prog, bits[0..L], b[0..L]);
        for (L / 2..L) |i| {
            total += 1;
            if (a[i] != b[i]) flips += 1;
        }
    }
    return @as(f64, @floatFromInt(flips)) / @as(f64, @floatFromInt(total));
}

fn localAgreement(prog: *const Program, seed: u64) f64 {
    const L: usize = 32;
    const n: usize = 64;
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var bits: [512]u1 = undefined;
    var out: [512]u1 = undefined;
    var agree: usize = 0;
    var total: usize = 0;
    for (0..n) |_| {
        for (0..L) |i| bits[i] = @intFromBool(rng.boolean());
        runParityBits(prog, bits[0..L], out[0..L]);
        var prev: u1 = 0;
        for (0..L) |i| {
            const loc: u1 = bits[i] ^ prev; // width-2 local parity
            total += 1;
            if (out[i] == loc) agree += 1;
            prev = bits[i];
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total));
}

/// Run a program on an explicit bit sequence, recording the low-bit parity output.
fn runParityBits(prog: *const Program, bits: []const u1, out: []u1) void {
    var m = Machine{};
    m.exec(prog.setup.slice());
    for (bits, 0..) |bit, i| {
        m.reg[REG_TOK] = bit;
        m.reg[REG_TYP] = 0;
        m.exec(prog.step.slice());
        out[i] = @truncate(m.reg[ri(OUT_P)]);
    }
}

// ===========================================================================
// PHASE 3 — the hunt: execution-search over the alien space, QD-niched on the
// recall × length-gen plane (MAP-Elites). Diversity by frontier position so the
// search fills the map and surfaces anything reaching the empty top-right corner.
// ===========================================================================

pub const Params = struct {
    max_evals: usize = 200_000,
    init_rate: f64 = 0.15, // fraction of fresh-random proposals (vs mutated elites)
    lambda: f64 = 5e-4, // tiny MDL tie-breaker (shorter programs win ties)
    // search-time fitness fidelity (cheap; the champion is re-validated long)
    fit_L: usize = 24,
    fit_n_seq: usize = 8,
    fit_K: usize = 20,
    fit_n_inst: usize = 64,
    grid: usize = 5, // NP = NR = grid (behaviour-descriptor resolution)
    // REFUTED by the Phase-3 probe: dense (query-all) recall grading does NOT
    // break the needle — it makes recall HARDER (0.34 vs sparse 0.55), because
    // content-addressed retrieval is an all-or-nothing conjunction, not a
    // partial-credit slope. Kept as a toggle for the experiment; default off.
    dense_recall: bool = false,
    // Curriculum warm-start: seed a quarter of the initial population with this
    // program (and mutants of it) so search EXTENDS a stepping-stone from an
    // easier rung instead of assembling the whole mechanism from scratch.
    seed_prog: ?*const Program = null,
    // "Forbid the attractor": restrict the op-space to this set (null = all ops).
    allowed_ops: ?[]const Op = null,
    count_vocab: usize = 6, // distinct symbols in the per-key counting task
    // "Get recall" reliability levers (attack the register-coordination conjunction):
    active_regs: usize = R, // search only addresses registers 0..active_regs (fewer ⇒ less miswiring)
    mem_bias: f64 = 0, // proposal prob of forcing a load/store op (biased proposer)
};

/// Search-time recall score — dense (gradient-giving) or sparse (single query).
pub fn recallScore(prog: *const Program, p: Params, seed: u64) f64 {
    return if (p.dense_recall)
        recallAccDense(prog, p.fit_K, p.fit_n_inst, seed +% 101, true)
    else
        recallAcc(prog, p.fit_K, p.fit_n_inst, seed +% 101, true);
}

pub const Scored = struct { parity: f64, recall: f64 };

/// The two map axes for one program, at search-time fidelity.
pub fn score(prog: *const Program, p: Params, seed: u64) Scored {
    return .{
        .parity = parityAcc(prog, p.fit_L, p.fit_n_seq, seed, true),
        .recall = recallScore(prog, p, seed),
    };
}

const Elite = struct { prog: Program, s: Scored, quality: f64 };

pub const HuntResult = struct {
    grid: usize,
    filled: [25]bool = [_]bool{false} ** 25, // up to 5×5
    best_topright: ?Program = null,
    tr_parity: f64 = 0,
    tr_recall: f64 = 0,
    best_min: f64 = 0, // best min(parity,recall) seen anywhere
    evals: usize = 0,
};

fn bucket(v: f64, n: usize) usize {
    const b: usize = @intFromFloat(v * @as(f64, @floatFromInt(n)));
    return @min(n - 1, b);
}

/// Quality within a niche: reward BOTH axes (min) with a small sum tie-breaker and
/// the MDL penalty — so the top-right niche is filled by genuinely dual-capable
/// programs, not one-trick ponies that happen to bucket high on one axis.
fn quality(s: Scored, prog_len: usize, lambda: f64) f64 {
    return @min(s.parity, s.recall) + 0.01 * (s.parity + s.recall) - lambda * @as(f64, @floatFromInt(prog_len));
}

pub fn hunt(al: std.mem.Allocator, rng: std.Random, p: Params, seed: u64) !HuntResult {
    const n = p.grid;
    const cells = n * n;
    const grid = try al.alloc(?Elite, cells);
    defer al.free(grid);
    for (grid) |*c| c.* = null;

    var res = HuntResult{ .grid = n };
    var evals: usize = 0;

    const consider = struct {
        fn f(g: []?Elite, nn: usize, prog: Program, s: Scored, lambda: f64, r: *HuntResult) void {
            const pb = bucket(s.parity, nn);
            const rb = bucket(s.recall, nn);
            const ci = pb * nn + rb;
            const q = quality(s, prog.len(), lambda);
            if (g[ci] == null or q > g[ci].?.quality) {
                g[ci] = .{ .prog = prog, .s = s, .quality = q };
            }
            const mn = @min(s.parity, s.recall);
            if (mn > r.best_min) r.best_min = mn;
            // top-right = highest parity AND recall bucket
            if (pb == nn - 1 and rb == nn - 1) {
                if (r.best_topright == null or mn > @min(r.tr_parity, r.tr_recall)) {
                    r.best_topright = prog;
                    r.tr_parity = s.parity;
                    r.tr_recall = s.recall;
                }
            }
        }
    }.f;

    // seed the grid with random programs
    const n_init = @min(p.max_evals / 4, 2000);
    for (0..n_init) |_| {
        const prog = randProg(rng, p.allowed_ops);
        const s = score(&prog, p, seed);
        evals += 1;
        consider(grid, n, prog, s, p.lambda, &res);
    }

    while (evals < p.max_evals) {
        var child: Program = undefined;
        if (rng.float(f64) < p.init_rate) {
            child = randProg(rng, p.allowed_ops);
        } else {
            // pick a random occupied cell, mutate its elite
            var tries: usize = 0;
            var ci = rng.uintLessThan(usize, cells);
            while (grid[ci] == null and tries < 8) : (tries += 1) ci = rng.uintLessThan(usize, cells);
            if (grid[ci] == null) {
                child = randProg(rng, p.allowed_ops);
            } else {
                child = grid[ci].?.prog;
                mutate(rng, &child, p.allowed_ops);
            }
        }
        const s = score(&child, p, seed);
        evals += 1;
        consider(grid, n, child, s, p.lambda, &res);
    }

    for (0..cells) |i| res.filled[i] = grid[i] != null;
    res.evals = evals;
    return res;
}

// ---- single-objective probe: is one axis a gradient-free needle? -----------

pub const Axis = enum { parity, recall, joint, counting };

/// Build the op-set with some ops excluded (for the "forbid the attractor"
/// experiment). Returns a slice into `buf`.
pub fn opsExcept(buf: []Op, excluded: []const Op) []Op {
    var n: usize = 0;
    for (0..Op.count()) |i| {
        const op: Op = @enumFromInt(i);
        var skip = false;
        for (excluded) |e| {
            if (op == e) skip = true;
        }
        if (!skip) {
            buf[n] = op;
            n += 1;
        }
    }
    return buf[0..n];
}

pub const ProbeResult = struct { best: Program, best_score: f64, evals_to_solve: ?usize };

/// Plain regularized (aging) evolution maximising ONE axis. Diagnostic: if even a
/// dedicated search can't climb an axis, that axis is a gradient-free needle in
/// this substrate (the Brick-A fitness-signal problem), not merely hard to reach
/// jointly. `solve` = score ≥ 0.95.
pub fn evolveAxis(al: std.mem.Allocator, rng: std.Random, p: Params, seed: u64, axis: Axis) !ProbeResult {
    const Indiv = struct { prog: Program, fit: f64 };
    const pop_size: usize = 600;
    const pop = try al.alloc(Indiv, pop_size);
    defer al.free(pop);

    const evalAxis = struct {
        fn f(prog: *const Program, pp: Params, sd: u64, ax: Axis) f64 {
            return switch (ax) {
                .parity => parityAcc(prog, pp.fit_L, pp.fit_n_seq, sd, true),
                .recall => recallScore(prog, pp, sd),
                // the top-right corner objective: must be good at BOTH at once
                .joint => @min(parityAcc(prog, pp.fit_L, pp.fit_n_seq, sd, true), recallScore(prog, pp, sd)),
                .counting => countingAcc(prog, pp.count_vocab, pp.fit_L, pp.fit_n_seq, sd +% 303, true),
            };
        }
    }.f;

    var best: Program = .{};
    var best_score: f64 = -1;
    var best_adj: f64 = -1e9;
    var evals: usize = 0;
    var ett: ?usize = null;

    for (pop, 0..) |*ind, i| {
        if (p.seed_prog) |sp| {
            // keep one exact copy of the stepping-stone, mutate the rest of the seeded quarter
            if (i < pop_size / 4) {
                ind.prog = sp.*;
                if (i > 0) mutate(rng, &ind.prog, p.allowed_ops);
            } else ind.prog = randProg(rng, p.allowed_ops);
        } else ind.prog = randProg(rng, p.allowed_ops);
        const raw = evalAxis(&ind.prog, p, seed, axis);
        ind.fit = raw - p.lambda * @as(f64, @floatFromInt(ind.prog.len()));
        evals += 1;
        if (ind.fit > best_adj) {
            best_adj = ind.fit;
            best_score = raw;
            best = ind.prog;
        }
        if (ett == null and raw >= 0.95) ett = evals;
    }
    var oldest: usize = 0;
    while (evals < p.max_evals) {
        var child: Program = undefined;
        if (rng.float(f64) < p.init_rate) {
            child = randProg(rng, p.allowed_ops);
        } else {
            var par = rng.uintLessThan(usize, pop_size);
            for (0..7) |_| {
                const c = rng.uintLessThan(usize, pop_size);
                if (pop[c].fit > pop[par].fit) par = c;
            }
            child = pop[par].prog;
            mutate(rng, &child, p.allowed_ops);
        }
        const raw = evalAxis(&child, p, seed, axis);
        const adj = raw - p.lambda * @as(f64, @floatFromInt(child.len()));
        evals += 1;
        pop[oldest] = .{ .prog = child, .fit = adj };
        oldest = (oldest + 1) % pop_size;
        if (adj > best_adj) {
            best_adj = adj;
            best_score = raw;
            best = child;
        }
        if (ett == null and raw >= 0.95) ett = evals;
    }
    return .{ .best = best, .best_score = best_score, .evals_to_solve = ett };
}

// ---- random programs + mutation over the alien op-space --------------------

fn randImm(rng: std.Random) u64 {
    const c = [_]u64{ 0, 1, 2, 3, 4, 5, 8, 16, 29, 32, 48, 63, MUM_C };
    return c[rng.uintLessThan(usize, c.len)];
}
fn pickOp(rng: std.Random, allowed: ?[]const Op) Op {
    if (allowed) |set| return set[rng.uintLessThan(usize, set.len)];
    return @enumFromInt(rng.uintLessThan(usize, Op.count()));
}
fn randInstr(rng: std.Random, allowed: ?[]const Op) Instr {
    return .{
        .op = pickOp(rng, allowed),
        .a = @intCast(rng.uintLessThan(usize, R)),
        .b = @intCast(rng.uintLessThan(usize, R)),
        .c = @intCast(rng.uintLessThan(usize, R)),
        .out = @intCast(rng.uintLessThan(usize, R)),
        .imm = randImm(rng),
    };
}
fn randComp(rng: std.Random, max: usize, allowed: ?[]const Op) Component {
    var comp = Component{};
    const k = rng.uintLessThan(usize, max + 1);
    for (0..k) |_| comp.appendAssumeCapacity(randInstr(rng, allowed));
    return comp;
}
fn randProg(rng: std.Random, allowed: ?[]const Op) Program {
    return .{ .setup = randComp(rng, 3, allowed), .step = randComp(rng, 8, allowed) };
}
fn mutate(rng: std.Random, prog: *Program, allowed: ?[]const Op) void {
    const comp = if (rng.boolean()) &prog.setup else &prog.step;
    switch (rng.uintLessThan(usize, 3)) {
        0 => if (comp.len < MAX_INSTR) {
            comp.insert(rng.uintLessThan(usize, comp.len + 1), randInstr(rng, allowed)) catch {};
        },
        1 => if (comp.len > 0) {
            _ = comp.orderedRemove(rng.uintLessThan(usize, comp.len));
        },
        else => if (comp.len > 0) {
            const i = rng.uintLessThan(usize, comp.len);
            const ins = &comp.slice()[i];
            switch (rng.uintLessThan(usize, 5)) {
                0 => ins.op = pickOp(rng, allowed),
                1 => ins.a = @intCast(rng.uintLessThan(usize, R)),
                2 => ins.b = @intCast(rng.uintLessThan(usize, R)),
                3 => ins.out = @intCast(rng.uintLessThan(usize, R)),
                else => ins.imm = randImm(rng),
            }
        } else comp.appendAssumeCapacity(randInstr(rng, allowed)),
    }
}

pub fn writeProgram(prog: *const Program, w: anytype) !void {
    try w.writeAll("    setup: ");
    for (prog.setup.slice()) |ins| try writeInstr(ins, w);
    try w.writeAll("\n    step:  ");
    for (prog.step.slice()) |ins| try writeInstr(ins, w);
    try w.writeAll("\n");
}
fn writeInstr(ins: Instr, w: anytype) !void {
    switch (ins.op) {
        .a_set => try w.print("r{d}={d}; ", .{ ri(ins.out), ins.imm }),
        .a_mov, .a_popcnt, .a_bswap => try w.print("r{d}={s}(r{d}); ", .{ ri(ins.out), @tagName(ins.op), ri(ins.a) }),
        .a_shl, .a_shr, .a_rotr => try w.print("r{d}={s}(r{d},{d}); ", .{ ri(ins.out), @tagName(ins.op), ri(ins.a), ins.imm & 63 }),
        .a_mum => try w.print("r{d}=mum(r{d}); ", .{ ri(ins.out), ri(ins.a) }),
        .a_sel => try w.print("r{d}=sel(r{d}?r{d}:r{d}); ", .{ ri(ins.out), ri(ins.c), ri(ins.a), ri(ins.b) }),
        .a_load => try w.print("r{d}=mem[r{d}]; ", .{ ri(ins.out), ri(ins.a) }),
        .a_store => try w.print("mem[r{d}]=r{d}; ", .{ ri(ins.a), ri(ins.b) }),
        .nop => {},
        else => try w.print("r{d}={s}(r{d},r{d}); ", .{ ri(ins.out), @tagName(ins.op), ri(ins.a), ri(ins.b) }),
    }
}

// ===========================================================================
// Tests — the Phase 2 kill-test: is the frontier (and its empty corner) reachable?
// ===========================================================================

test "PHASE 2 kill-test: an alien XOR-scan reaches the LENGTH-GEN corner" {
    const p = alienXorScan();
    try std.testing.expect(parityAcc(&p, 256, 32, 0xA11E, true) > 0.99); // length-generalises
    try std.testing.expect(recallAcc(&p, 32, 512, 0xA11E, true) < 0.65); // no content addressing
}

test "PHASE 2 kill-test: an alien hash-table reaches the RECALL corner (no softmax)" {
    const p = alienHashTable();
    try std.testing.expect(recallAcc(&p, 48, 512, 0xB22F, true) > 0.95); // content addressing via hashing
    try std.testing.expect(parityAcc(&p, 256, 32, 0xB22F, true) < 0.65); // no accumulation
}

test "PHASE 2 kill-test: an alien UNION reaches the EMPTY TOP-RIGHT corner" {
    const p = alienUnion();
    const lg = parityAcc(&p, 256, 32, 0xC33E, true);
    const rc = recallAcc(&p, 48, 512, 0xC33E, true);
    try std.testing.expect(lg > 0.99 and rc > 0.95); // BOTH — the substrate can host a frontier-breaker
}

test "PHASE 2: the top-right alien program certifies NOVEL vs the single-mechanism anchors" {
    const seed: u64 = 0xD44F;
    const p = alienUnion();
    const fp = fingerprint(&p, seed);
    const anchors = fr.knownAnchors(seed);
    const v = fr.classify(fp, &anchors, fr.NOVELTY_THRESHOLD);
    // far from attention (it does parity) and from scan (it does large-K recall)
    try std.testing.expect(v.novel);
    try std.testing.expect(fr.fpDist(fp, fr.fingerprint(fr.attention, seed)) > fr.NOVELTY_THRESHOLD);
    try std.testing.expect(fr.fpDist(fp, fr.fingerprint(fr.scan, seed)) > fr.NOVELTY_THRESHOLD);
}

test "PHASE 2: the no-carried-state baseline cannot accumulate (parity ≈ chance)" {
    const p = alienXorScan();
    const acc = parityAcc(&p, 64, 64, 0xE55F, false); // state reset each position
    try std.testing.expect(acc > 0.4 and acc < 0.6);
}

test "INSUFFICIENCY: per-key counting needs a fused RMW — known mechanisms FAIL it" {
    const vocab: usize = 6;
    // the fused read-modify-write counter solves it
    const rmw = alienRMWCounter();
    try std.testing.expect(countingAcc(&rmw, vocab, 32, 32, 0x0C01, true) > 0.95);
    // the bolted union (separate accumulator + static store) cannot
    const u = alienUnion();
    try std.testing.expect(countingAcc(&u, vocab, 32, 32, 0x0C01, true) < 0.65);
    // neither can the scan or the hash-table alone
    try std.testing.expect(countingAcc(&alienXorScan(), vocab, 32, 32, 0x0C01, true) < 0.65);
    try std.testing.expect(countingAcc(&alienHashTable(), vocab, 32, 32, 0x0C01, true) < 0.65);
}

test "op-masking: forbidding load/store removes them from generated programs" {
    var buf: [Op.count()]Op = undefined;
    const allowed = opsExcept(&buf, &.{ .a_load, .a_store });
    var p2 = std.Random.DefaultPrng.init(0x1357);
    const rng = p2.random();
    for (0..200) |_| {
        const prog = randProg(rng, allowed);
        for (prog.setup.slice()) |ins| try std.testing.expect(ins.op != .a_load and ins.op != .a_store);
        for (prog.step.slice()) |ins| try std.testing.expect(ins.op != .a_load and ins.op != .a_store);
    }
}

test "PHASE 3 smoke: the QD hunt runs and returns a valid grid" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var prng = std.Random.DefaultPrng.init(0x5EED);
    const r = try hunt(arena.allocator(), prng.random(), .{ .max_evals = 4000, .grid = 5 }, 1);
    try std.testing.expect(r.evals >= 4000);
    try std.testing.expect(r.best_min >= 0.0 and r.best_min <= 1.0);
}
