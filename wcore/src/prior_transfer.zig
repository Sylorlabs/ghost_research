//! PRIOR TRANSFER: once E3 (`smart_gen.zig`, round 2026-07-11 exp E3) auto-discovered
//! the `noveltyflag` mechanism via the RMW structural prior + exhaustive COVER, does
//! that discovery AMORTIZE across a family of related counting targets — or does every
//! new target need the prior re-supplied and the search re-run from scratch?
//! (round 2026-07-11b, experiment F4)
//!
//! This is the D5/A1-A6 generalisation question (`a1a6_iterated_promotion.md`: promoted
//! atoms mostly DON'T generalise, corrected held-out 3/18->4/18), re-asked with E3's
//! WORKING method (exhaustive coverage + RMW-shape structural prior) instead of blind
//! promotion.
//!
//! DESIGN
//! ------
//! Phase 1 (seed the mechanism): reproduce E3's COVER-fair auto-discovery of an atom
//! behaviourally equivalent to `noveltyFlagProg` against the `distinct` target, promote
//! it. This is a faithful re-run of E3's own headline result, used here only to OBTAIN
//! the mechanism + confirm the apparatus still works byte-for-byte.
//!
//! Phase 2 (the transfer test): for each of 10 OTHER family targets — the 6 wall-family
//! compositions of distinct-count ported verbatim from `smart_gen.zig`'s SPECS (dist->gxor,
//! gadd->dist, dist->dist, dist->rmw, shift->dist, shift->dist->gxor), the 2 already-
//! climbable members (hashtbl, union), and 2 NEW counting-family targets designed for
//! this file (`togglecount`, `eqflag`, see below) — measure auto-discovery cost under
//! three conditions:
//!   (A) FULL TRANSFER   — library = base atoms + the Phase-1 PROMOTED atom; the prior
//!       (COVER-fair) is also available as a fallback generator.
//!   (B) PRIOR-ONLY      — library = base atoms only (promoted atom withheld); the SAME
//!       COVER-fair prior/generator is available, run fresh.
//!   (C) COLD            — library = base atoms only; NO structural prior — a pure-random
//!       blind pool of the SAME size as the COVER-fair chunk (E3's established-failing
//!       generator class: blind bulk, D5/GRAD/PRIOR_WEAK/PRIOR_STRONG all scored 0/9).
//! Every target is FIRST checked for solvability by pure depth-<=3 CHAIN COMPOSITION over
//! the condition's library alone (cost ~0, no generation) before any generator is invoked
//! — this is what separates "reached by composing the promoted atom" (real transfer) from
//! "a fresh atom had to be generated" (no transfer, re-solving).
//!
//! THE TWO NEW COUNTING TARGETS (same RMW read-then-write-same-address family as
//! `noveltyflag`, but each a genuinely DIFFERENT completion, so Phase 2 is not just
//! "rediscover literally the same program"):
//!   `eqflag`       — load;store(const);EQ(loaded,const)  (same instruction ORDER as
//!                    noveltyflag, only the combining op changes XOR->EQ) — the
//!                    NEAR-TRANSFER case.
//!   `togglecount`  — load;XOR(loaded,const);store(computed)  (same three primitives,
//!                    but the STORE now writes the COMPUTED value instead of a constant,
//!                    and comes LAST instead of second) — the FAR-TRANSFER case, designed
//!                    to test whether COVER-fair's "RMW-shaped L2 inclusion" (which checks
//!                    the 2-instruction PREFIX for load+store co-occurrence before adding a
//!                    3rd instruction) still fires when the store is the LAST instruction
//!                    rather than the middle one — i.e. whether the prior generalises to a
//!                    REORDERED member of the same family or is order-specific.
//! Both use ONLY registers {0,2,3} and immediate {1} — within COVER's reduced alphabet
//! (COVER_REGS=4, COVER_IMM={0,1}) by construction, so they are expressible-in-principle,
//! mirroring `smart_gen.zig`'s own `noveltyFlagRemapped` expressiveness check.
//!
//! Everything in the "PORTED" sections below is copied byte-for-byte in BEHAVIOUR from
//! `smart_gen.zig` (itself ported byte-for-byte from `auto_curriculum.zig`/D5) — this file
//! only ADDS the two new targets, the three-condition harness, and the composition-vs-
//! generation cost accounting. `smart_gen.zig` is imported nowhere (its useful pieces are
//! not `pub`); everything needed is re-derived from the shared `pub` substrate modules
//! (`inv_alien.zig`, `inv_coevo.zig`, `inv_atomforge.zig`) exactly as `smart_gen.zig` itself
//! does, per this repo's established pattern for standalone experiment files.
//!
//! Build: cd wcore && zig build-exe -O ReleaseFast src/prior_transfer.zig -femit-bin=bin/prior_transfer
//! Run:   ./bin/prior_transfer selftest
//!        ./bin/prior_transfer phase1 ../results/prior_transfer_2026_07_11.csv
//!        ./bin/prior_transfer phase2 <a|b|c> ../results/prior_transfer_2026_07_11.csv [--start=N] [--count=N] [--chunk=N] [--seed=0x..]
//! Single-threaded throughout (no std.Thread spawned anywhere in this file).

const std = @import("std");
const alien = @import("inv_alien.zig");
const coevo = @import("inv_coevo.zig");
const forge = @import("inv_atomforge.zig");

const V: usize = alien.CANON_BASE;
const DEPTH: usize = forge.COMPOSE_DEPTH; // 3 — production certifier / payoff / composition-check depth
const GATE_DEPTH: usize = DEPTH + 1; // 4 — the settled +1-depth promotion gate
const MATCH_SEQ: usize = 8;
const MATCH_L: usize = 28;
const RSEED: u64 = 0x0F17ED;
const BATTERY_SEED: u64 = 0xBA77E71;
const RESIDUAL_SEED: u64 = 0x2E51DA1;

// =============================================================================
// PORTED (byte-for-byte behaviour) from smart_gen.zig / auto_curriculum.zig —
// the battery, hand stones, certify+payoff apparatus. EXTENDED with 2 new
// hidden targets (indices 13, 14) and 2 new SPECS entries.
// =============================================================================

const HIDDEN_N: usize = 15; // 13 (D5/E3 original) + 2 new counting targets

fn togglecountProg() alien.Program {
    var p = alien.Program{};
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 2, .imm = 1 }); // r2 = 1 (toggle const)
    p.step.appendAssumeCapacity(.{ .op = .a_load, .a = 0, .out = 3 }); // r3 = mem[tok] (prior parity)
    p.step.appendAssumeCapacity(.{ .op = .a_xor, .a = 3, .b = 2, .out = 3 }); // r3 = toggle(prior)
    p.step.appendAssumeCapacity(.{ .op = .a_store, .a = 0, .b = 3 }); // mem[tok] = COMPUTED new parity
    return p;
}

fn eqflagProg() alien.Program {
    var p = alien.Program{};
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 2, .imm = 1 }); // r2 = 1 (seen marker)
    p.step.appendAssumeCapacity(.{ .op = .a_load, .a = 0, .out = 3 }); // r3 = mem[tok] (prior mark)
    p.step.appendAssumeCapacity(.{ .op = .a_store, .a = 0, .b = 2 }); // mem[tok] = 1 (mark seen)
    p.step.appendAssumeCapacity(.{ .op = .a_eq, .a = 3, .b = 2, .out = 3 }); // r3 = (prior==1)?~0:0
    return p;
}

fn buildHidden() [HIDDEN_N]alien.Program {
    var h: [HIDDEN_N]alien.Program = undefined;
    h[0] = coevo.refSolver(.g_xor);
    h[1] = coevo.refSolver(.g_add);
    h[2] = coevo.refSolver(.pk_xor);
    h[3] = coevo.refSolver(.pk_add);
    h[4] = forge.shiftAtom();
    h[5] = coevo.distinctCountProg();
    h[6] = alien.alienRMWCounter();
    h[7] = alien.alienXorScan();
    h[8] = alien.alienHashTable();
    h[9] = alien.alienUnion();
    var sp = alien.Params{ .active_regs = 8 };
    var prng = std.Random.DefaultPrng.init(BATTERY_SEED);
    const rng = prng.random();
    var n: usize = 10;
    while (n < 13) {
        const p = alien.randProg(rng, &sp);
        if (forge.clean(&p, BATTERY_SEED)) {
            h[n] = p;
            n += 1;
        }
    }
    h[13] = togglecountProg(); // NEW: far-transfer counting target
    h[14] = eqflagProg(); // NEW: near-transfer counting target
    return h;
}

const TSpec = struct { name: []const u8, idxs: []const usize };

const SPECS = [_]TSpec{
    .{ .name = "distinct", .idxs = &.{5} }, // 0
    .{ .name = "rmw", .idxs = &.{6} }, // 1
    .{ .name = "xorscan", .idxs = &.{7} }, // 2
    .{ .name = "hashtbl", .idxs = &.{8} }, // 3
    .{ .name = "union", .idxs = &.{9} }, // 4
    .{ .name = "decoy1", .idxs = &.{10} }, // 5
    .{ .name = "decoy2", .idxs = &.{11} }, // 6
    .{ .name = "decoy3", .idxs = &.{12} }, // 7
    .{ .name = "dist->gxor", .idxs = &.{ 5, 0 } }, // 8
    .{ .name = "gadd->dist", .idxs = &.{ 1, 5 } }, // 9
    .{ .name = "dist->dist", .idxs = &.{ 5, 5 } }, // 10
    .{ .name = "rmw->pkxor", .idxs = &.{ 6, 2 } }, // 11
    .{ .name = "dist->rmw", .idxs = &.{ 5, 6 } }, // 12
    .{ .name = "shift->dist", .idxs = &.{ 4, 5 } }, // 13
    .{ .name = "shift->dist->gxor", .idxs = &.{ 4, 5, 0 } }, // 14
    .{ .name = "pkadd->dist->pkadd", .idxs = &.{ 3, 5, 3 } }, // 15
    .{ .name = "rmw->rmw->gadd", .idxs = &.{ 6, 6, 1 } }, // 16
    .{ .name = "dist->shift->rmw", .idxs = &.{ 5, 4, 6 } }, // 17
    .{ .name = "togglecount", .idxs = &.{13} }, // 18  NEW (far-transfer)
    .{ .name = "eqflag", .idxs = &.{14} }, // 19  NEW (near-transfer)
};
const N_TARGETS: usize = SPECS.len;

const WALL_IDX = [_]usize{ 0, 8, 9, 10, 12, 13, 14 }; // distinct + its 6 compositions (Phase-1 target family)
// Phase-2 "OTHER family" targets: the 6 wall compositions of distinct (excluding
// distinct itself, which IS Phase 1's own target), the 2 already-climbable members,
// and the 2 new counting targets designed for this file.
const OTHER_IDX = [_]usize{ 3, 4, 8, 9, 10, 12, 13, 14, 18, 19 };

fn chainAgreement(
    lib_a: []const alien.Program,
    a_idxs: []const usize,
    lib_b: []const alien.Program,
    b_idxs: []const usize,
    n: usize,
    L: usize,
    seed: u64,
) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var out_a: [256]u8 = undefined;
    var out_b: [256]u8 = undefined;
    var agree: usize = 0;
    var total: usize = 0;
    for (0..n) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        forge.applyChain(lib_a, a_idxs, syms[0..L], out_a[0..L]);
        forge.applyChain(lib_b, b_idxs, syms[0..L], out_b[0..L]);
        for (0..L) |i| {
            total += 1;
            if (out_a[i] == out_b[i]) agree += 1;
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total));
}

fn targetSolvable(
    hidden: []const alien.Program,
    t_idxs: []const usize,
    lib: []const alien.Program,
    max_depth: usize,
    seed: u64,
) bool {
    const n = lib.len;
    if (n == 0) return false;
    var d: usize = 1;
    while (d <= max_depth) : (d += 1) {
        var total: usize = 1;
        for (0..d) |_| total *= n;
        var idx: usize = 0;
        while (idx < total) : (idx += 1) {
            var idxs: [8]usize = undefined;
            var x = idx;
            for (0..d) |j| {
                idxs[j] = x % n;
                x /= n;
            }
            if (chainAgreement(hidden, t_idxs, lib, idxs[0..d], MATCH_SEQ, MATCH_L, seed) >= forge.MATCH_THRESHOLD) {
                return true;
            }
        }
    }
    return false;
}

// ---- hand-designed stones — VERIFICATION-ONLY (never used to steer generation,
// fitness, certify, or payoff — only in genuineness checks after a discovery) ----

fn membershipProg() alien.Program {
    var p = alien.Program{};
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 6, .imm = 1 });
    p.step.appendAssumeCapacity(.{ .op = .a_load, .a = 0, .out = 3 });
    p.step.appendAssumeCapacity(.{ .op = .a_store, .a = 0, .b = 6 });
    return p;
}

fn noveltyFlagProg() alien.Program {
    var p = alien.Program{};
    p.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 6, .imm = 1 });
    p.step.appendAssumeCapacity(.{ .op = .a_load, .a = 0, .out = 3 });
    p.step.appendAssumeCapacity(.{ .op = .a_store, .a = 0, .b = 6 });
    p.step.appendAssumeCapacity(.{ .op = .a_xor, .a = 3, .b = 6, .out = 3 });
    return p;
}

fn progAgreement(a: *const alien.Program, b: *const alien.Program, n: usize, L: usize, seed: u64) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var out_a: [256]u8 = undefined;
    var out_b: [256]u8 = undefined;
    var agree: usize = 0;
    var total: usize = 0;
    for (0..n) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        alien.runStream(a, syms[0..L], out_a[0..L]);
        alien.runStream(b, syms[0..L], out_b[0..L]);
        for (0..L) |i| {
            total += 1;
            if (out_a[i] == out_b[i]) agree += 1;
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total));
}

fn familyResidualOne(hidden: []const alien.Program, t_idxs: []const usize, cand: *const alien.Program) f64 {
    var single = [1]alien.Program{cand.*};
    const zero_idx = [_]usize{0};
    return chainAgreement(hidden, t_idxs, single[0..1], &zero_idx, MATCH_SEQ, MATCH_L, RESIDUAL_SEED);
}

fn certifiableDepth3(cand: *const alien.Program, atoms: []const alien.Program, fseed: u64) bool {
    return !forge.reducibleLib(cand, atoms, DEPTH, fseed);
}

fn certifiableDepth4(cand: *const alien.Program, atoms: []const alien.Program, fseed: u64) bool {
    return !forge.reducibleLib(cand, atoms, GATE_DEPTH, fseed);
}

fn includesIdx(idxs: []const usize, new_idx: usize) bool {
    for (idxs) |v| if (v == new_idx) return true;
    return false;
}

const PayoffResult = struct { count: usize, hits: [OTHER_IDX.len]usize = undefined };

fn payoffTest(
    hidden: []const alien.Program,
    atoms: []const alien.Program,
    cand: *const alien.Program,
    unsolved: []const usize,
) PayoffResult {
    var trial = forge.AtomLib{};
    for (atoms) |a| trial.appendAssumeCapacity(a);
    trial.appendAssumeCapacity(cand.*);
    const lib = trial.slice();
    const new_idx = atoms.len;
    var res = PayoffResult{ .count = 0 };
    for (unsolved) |ti| {
        if (targetSolvableNew(hidden, SPECS[ti].idxs, lib, new_idx, DEPTH, RSEED)) {
            res.hits[res.count] = ti;
            res.count += 1;
        }
    }
    return res;
}

fn targetSolvableNew(
    hidden: []const alien.Program,
    t_idxs: []const usize,
    lib: []const alien.Program,
    new_idx: usize,
    max_depth: usize,
    seed: u64,
) bool {
    const n = lib.len;
    if (n == 0) return false;
    var d: usize = 1;
    while (d <= max_depth) : (d += 1) {
        var total: usize = 1;
        for (0..d) |_| total *= n;
        var idx: usize = 0;
        while (idx < total) : (idx += 1) {
            var idxs: [8]usize = undefined;
            var x = idx;
            for (0..d) |j| {
                idxs[j] = x % n;
                x /= n;
            }
            if (!includesIdx(idxs[0..d], new_idx)) continue;
            if (chainAgreement(hidden, t_idxs, lib, idxs[0..d], MATCH_SEQ, MATCH_L, seed) >= forge.MATCH_THRESHOLD) {
                return true;
            }
        }
    }
    return false;
}

const FoundStone = struct { prog: alien.Program, payoff: usize, len: usize };

fn discoverStone(
    hidden: []const alien.Program,
    atoms: []const alien.Program,
    unsolved: []const usize,
    pool: []const alien.Program,
    fseed: u64,
    n_d3: *usize,
    n_payoff_pos: *usize,
    n_certified: *usize,
) ?FoundStone {
    var best: ?FoundStone = null;
    var cnt_d3: usize = 0;
    var cnt_payoff: usize = 0;
    var cnt_cert: usize = 0;
    for (pool) |cand| {
        if (!certifiableDepth3(&cand, atoms, fseed)) continue;
        cnt_d3 += 1;
        const pr = payoffTest(hidden, atoms, &cand, unsolved);
        if (pr.count == 0) continue;
        cnt_payoff += 1;
        if (!certifiableDepth4(&cand, atoms, fseed)) continue;
        cnt_cert += 1;
        const cl = cand.len();
        const better = if (best) |b| (pr.count > b.payoff or (pr.count == b.payoff and cl < b.len)) else true;
        if (better) best = .{ .prog = cand, .payoff = pr.count, .len = cl };
    }
    n_d3.* = cnt_d3;
    n_payoff_pos.* = cnt_payoff;
    n_certified.* = cnt_cert;
    return best;
}

// =============================================================================
// PORTED (byte-for-byte behaviour) from smart_gen.zig — the COVER-fair generator
// (the one arm of E3 that crossed the wall). Only the FAIR mode is ported (the
// uniform ablation isn't needed here — this file's purpose is to use E3's
// WORKING method as "the prior", not re-litigate the ablation).
// =============================================================================

fn hasRMWShape(prog: *const alien.Program) bool {
    const s = prog.step.slice();
    for (s) |li| {
        if (li.op != .a_load) continue;
        for (s) |si| {
            if (si.op == .a_store and si.a == li.a) return true;
        }
    }
    return false;
}

const COVER_REGS: usize = 4;
const COVER_IMM = [_]u64{ 0, 1 };
const COVER_FRONTIER_CAP: usize = 4000;
const COVER_L3_BASE_CAP: usize = 1000;
const COVER_MAX_LEVEL: usize = 3;

const MiniMachine = struct {
    reg: [alien.R]u64 = [_]u64{0} ** alien.R,
    mem: [alien.M]u64 = [_]u64{0} ** alien.M,

    fn exec(m: *MiniMachine, instrs: []const alien.Instr) void {
        for (instrs) |ins| {
            const sh: u6 = @truncate(ins.imm);
            const ra = @as(usize, ins.a) % alien.R;
            const rb = @as(usize, ins.b) % alien.R;
            const rc = @as(usize, ins.c) % alien.R;
            const ro = @as(usize, ins.out) % alien.R;
            switch (ins.op) {
                .a_set => m.reg[ro] = ins.imm,
                .a_mov => m.reg[ro] = m.reg[ra],
                .a_xor => m.reg[ro] = m.reg[ra] ^ m.reg[rb],
                .a_and => m.reg[ro] = m.reg[ra] & m.reg[rb],
                .a_or => m.reg[ro] = m.reg[ra] | m.reg[rb],
                .a_add => m.reg[ro] = m.reg[ra] +% m.reg[rb],
                .a_sub => m.reg[ro] = m.reg[ra] -% m.reg[rb],
                .a_mul => m.reg[ro] = m.reg[ra] *% m.reg[rb],
                .a_shl => m.reg[ro] = m.reg[ra] << sh,
                .a_shr => m.reg[ro] = m.reg[ra] >> sh,
                .a_rotr => m.reg[ro] = std.math.rotr(u64, m.reg[ra], @as(u64, sh)),
                .a_popcnt => m.reg[ro] = @popCount(m.reg[ra]),
                .a_mum => {
                    var x = m.reg[ra];
                    x *%= 0x9E3779B97F4A7C15;
                    x ^= x >> 29;
                    m.reg[ro] = x;
                },
                .a_bswap => m.reg[ro] = @byteSwap(m.reg[ra]),
                .a_eq => m.reg[ro] = if (m.reg[ra] == m.reg[rb]) ~@as(u64, 0) else 0,
                .a_sel => m.reg[ro] = if (m.reg[rc] != 0) m.reg[ra] else m.reg[rb],
                .a_load => m.reg[ro] = m.mem[m.reg[ra] % alien.M],
                .a_store => m.mem[m.reg[ra] % alien.M] = m.reg[rb],
                .nop => {},
            }
        }
    }
};

fn stateFingerprint(prog: *const alien.Program, seed: u64) u64 {
    var h: u64 = seed;
    const n_variants: usize = 3;
    for (0..n_variants) |vi| {
        var prng = std.Random.DefaultPrng.init(seed +% @as(u64, @intCast(vi)) *% 0x9E3779B97F4A7C15);
        const rng = prng.random();
        var m = MiniMachine{};
        if (vi > 0) {
            for (&m.mem) |*c| c.* = rng.uintLessThan(u64, V);
        }
        m.exec(prog.setup.slice());
        const L: usize = 5;
        for (0..L) |_| {
            const s: u64 = rng.uintLessThan(usize, V);
            m.reg[alien.REG_TOK] = s;
            m.reg[alien.REG_TYP] = 0;
            m.reg[5] = s;
            m.exec(prog.step.slice());
            for (m.reg) |r| h = std.hash.Wyhash.hash(h, std.mem.asBytes(&r));
            for (m.mem) |c| h = std.hash.Wyhash.hash(h, std.mem.asBytes(&c));
        }
    }
    return h;
}

const CoverLevel = struct { kept: std.ArrayList(alien.Program), kept_tags: std.ArrayList(u8), n_distinct_seen: usize };

fn extendLevel(al: std.mem.Allocator, base: []const alien.Program, base_tags: []const u8, seed: u64, per_bucket_cap: usize) !CoverLevel {
    var seen = std.AutoHashMap(u64, void).init(al);
    defer seen.deinit();
    var kept = std.ArrayList(alien.Program).init(al);
    var kept_tags = std.ArrayList(u8).init(al);
    const n_tags: usize = 2;
    var kept_per_tag_op: [n_tags][32]usize = .{[_]usize{0} ** 32} ** n_tags;
    for (base, 0..) |bp, bi| {
        const tag = base_tags[bi];
        var op_i: usize = 0;
        while (op_i < alien.Op.count()) : (op_i += 1) {
            const op: alien.Op = @enumFromInt(op_i);
            for (0..COVER_REGS) |a| {
                for (0..COVER_REGS) |b| {
                    for (0..COVER_REGS) |c| {
                        for (0..COVER_REGS) |out_r| {
                            for (COVER_IMM) |imm| {
                                if (bp.step.len >= alien.MAX_INSTR) continue;
                                var np = bp;
                                np.step.appendAssumeCapacity(.{ .op = op, .a = @intCast(a), .b = @intCast(b), .c = @intCast(c), .out = @intCast(out_r), .imm = imm });
                                const fp = stateFingerprint(&np, seed);
                                const gp = try seen.getOrPut(fp);
                                if (gp.found_existing) continue;
                                if (kept_per_tag_op[tag][op_i] < per_bucket_cap) {
                                    try kept.append(np);
                                    try kept_tags.append(tag);
                                    kept_per_tag_op[tag][op_i] += 1;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return .{ .kept = kept, .kept_tags = kept_tags, .n_distinct_seen = seen.count() };
}

const CoverResult = struct { pool: std.ArrayList(alien.Program), n_distinct: [COVER_MAX_LEVEL]usize };

/// Build the FAIR cover pool (RMW-shaped L2 programs included first in the L3 base) —
/// the one E3 arm that crosses the wall. Deterministic, seed-independent by construction.
fn buildCoverPool(al: std.mem.Allocator) !CoverResult {
    const seed: u64 = 0xC0E5A11;
    var level0 = std.ArrayList(alien.Program).init(al);
    defer level0.deinit();
    try level0.append(alien.Program{});
    var setup_const = alien.Program{};
    setup_const.setup.appendAssumeCapacity(.{ .op = .a_set, .out = 2, .imm = 1 });
    try level0.append(setup_const);

    var pool = std.ArrayList(alien.Program).init(al);
    var n_distinct: [COVER_MAX_LEVEL]usize = undefined;

    var tags0 = std.ArrayList(u8).init(al);
    defer tags0.deinit();
    try tags0.append(0);
    try tags0.append(1);

    var base = level0.items;
    var base_tags = tags0.items;
    var owned: ?std.ArrayList(alien.Program) = null;
    var owned_tags: ?std.ArrayList(u8) = null;
    var l3base = std.ArrayList(alien.Program).init(al);
    defer l3base.deinit();
    var l3tags = std.ArrayList(u8).init(al);
    defer l3tags.deinit();
    const n_tags: usize = 2;
    var lvl: usize = 0;
    while (lvl < COVER_MAX_LEVEL) : (lvl += 1) {
        if (lvl == COVER_MAX_LEVEL - 1 and base.len > COVER_L3_BASE_CAP) {
            l3base.clearRetainingCapacity();
            l3tags.clearRetainingCapacity();
            for (base, 0..) |bp, bi| { // RMW-shaped first (fairness inclusion)
                if (hasRMWShape(&bp)) {
                    try l3base.append(bp);
                    try l3tags.append(base_tags[bi]);
                }
            }
            for (base, 0..) |bp, bi| { // fill remainder up to the cap
                if (l3base.items.len >= COVER_L3_BASE_CAP) break;
                if (!hasRMWShape(&bp)) {
                    try l3base.append(bp);
                    try l3tags.append(base_tags[bi]);
                }
            }
            base = l3base.items;
            base_tags = l3tags.items;
        }
        const cap: usize = if (lvl < COVER_MAX_LEVEL - 1) std.math.maxInt(usize) else COVER_FRONTIER_CAP / (n_tags * alien.Op.count()) + 1;
        const res = try extendLevel(al, base, base_tags, seed +% lvl, cap);
        n_distinct[lvl] = res.n_distinct_seen;
        for (res.kept.items) |p| try pool.append(p);
        if (owned) |*o| o.deinit();
        if (owned_tags) |*t| t.deinit();
        owned = res.kept;
        owned_tags = res.kept_tags;
        base = res.kept.items;
        base_tags = res.kept_tags.items;
    }
    if (owned) |*o| o.deinit();
    if (owned_tags) |*t| t.deinit();
    // Reverse so the LAST level (L3, whose tail is the RMW-shaped lineage) is tested
    // FIRST — same trick as smart_gen.zig, so the stone is near the front of the pool.
    std.mem.reverse(alien.Program, pool.items);
    return .{ .pool = pool, .n_distinct = n_distinct };
}

/// The COLD/no-prior pool: pure uniform-random programs, no RMW bias, no exhaustive
/// coverage — the class of generator E3 established as failing (D5 blind bulk / GRAD /
/// PRIOR_WEAK all scored 0/9 against this same wall family).
fn buildBlindPool(rng: std.Random, n: usize, pool: *std.ArrayList(alien.Program)) !void {
    const sp = alien.Params{ .active_regs = 8 };
    for (0..n) |_| try pool.append(alien.randProg(rng, &sp));
}

// =============================================================================
// PHASE 1 — reproduce E3's auto-discovery of the noveltyflag mechanism, promote it.
// =============================================================================

const Phase1Result = struct {
    atom: alien.Program,
    found: bool,
    payoff: usize,
    n_d3: usize,
    n_payoff_pos: usize,
    n_certified: usize,
    pool_checked: usize,
    agree_s1: f64,
    agree_s2: f64,
};

const PHASE1_CHUNK: usize = 6000; // bounded leading (RMW-lineage-first) slice of the cover pool

fn runPhase1(hidden: []const alien.Program, cover_pool: []const alien.Program) Phase1Result {
    var atoms = forge.baseAtoms();
    const fseed: u64 = 0xA70F +% 0xA70F;
    const chunk = @min(PHASE1_CHUNK, cover_pool.len);
    var n_d3: usize = 0;
    var n_payoff: usize = 0;
    var n_cert: usize = 0;
    // Match E3 exactly: payoff is measured against ALL 7 currently-unsolved WALL_IDX
    // targets (not just "distinct" alone) -- this is what lets the genuine high-payoff
    // stone win the "better" comparison in discoverStone instead of an early single-
    // target tie-break.
    const found = discoverStone(hidden, atoms.slice(), &WALL_IDX, cover_pool[0..chunk], fseed, &n_d3, &n_payoff, &n_cert);
    if (found) |fs| {
        var s1 = membershipProg();
        var s2 = noveltyFlagProg();
        return .{
            .atom = fs.prog,
            .found = true,
            .payoff = fs.payoff,
            .n_d3 = n_d3,
            .n_payoff_pos = n_payoff,
            .n_certified = n_cert,
            .pool_checked = chunk,
            .agree_s1 = progAgreement(&fs.prog, &s1, MATCH_SEQ, MATCH_L, RESIDUAL_SEED),
            .agree_s2 = progAgreement(&fs.prog, &s2, MATCH_SEQ, MATCH_L, RESIDUAL_SEED),
        };
    }
    return .{ .atom = alien.Program{}, .found = false, .payoff = 0, .n_d3 = n_d3, .n_payoff_pos = n_payoff, .n_certified = n_cert, .pool_checked = chunk, .agree_s1 = -1, .agree_s2 = -1 };
}

// =============================================================================
// PHASE 2 — the transfer test
// =============================================================================

pub const Condition = enum { a, b, c };

const TargetResult = struct {
    target: usize,
    condition: Condition,
    lib_size: usize,
    solved: bool,
    event: []const u8, // "composition" | "auto_discovered" | "not_found"
    pool_size: usize,
    n_d3: usize,
    n_payoff_pos: usize,
    n_certified: usize,
    payoff: usize,
    cand_len: usize,
    agree_noveltyflag: f64,
    agree_own_stone: f64,
    ms: u64,
};

fn ownStoneFor(ti: usize) ?alien.Program {
    if (ti == 18) return togglecountProg();
    if (ti == 19) return eqflagProg();
    return null;
}

fn runPhase2Target(
    hidden: []const alien.Program,
    ti: usize,
    cond: Condition,
    promoted: ?alien.Program,
    cover_pool: []const alien.Program,
    chunk: usize,
    seed: u64,
) TargetResult {
    var timer = std.time.Timer.start() catch unreachable;
    const fseed = seed +% 0xA70F;

    var atoms = forge.baseAtoms();
    if (cond == .a) {
        if (promoted) |p| atoms.appendAssumeCapacity(p);
    }

    // Step 1: cheap composition-only check (cost ~0, no generation).
    if (targetSolvable(hidden, SPECS[ti].idxs, atoms.slice(), DEPTH, RSEED)) {
        return .{
            .target = ti,
            .condition = cond,
            .lib_size = atoms.len,
            .solved = true,
            .event = "composition",
            .pool_size = 0,
            .n_d3 = 0,
            .n_payoff_pos = 0,
            .n_certified = 0,
            .payoff = 0,
            .cand_len = 0,
            .agree_noveltyflag = -1,
            .agree_own_stone = -1,
            .ms = timer.read() / std.time.ns_per_ms,
        };
    }

    // Step 2: composition alone didn't solve it — invoke a generator.
    var owned_pool: ?std.ArrayList(alien.Program) = null;
    defer if (owned_pool) |*p| p.deinit();
    var pool_slice: []const alien.Program = undefined;
    switch (cond) {
        .a, .b => {
            pool_slice = cover_pool[0..@min(chunk, cover_pool.len)];
        },
        .c => {
            const gpa = std.heap.page_allocator;
            var lst = std.ArrayList(alien.Program).init(gpa);
            var prng = std.Random.DefaultPrng.init(seed +% ti *% 0x9E3779B97F4A7C15);
            buildBlindPool(prng.random(), chunk, &lst) catch {};
            owned_pool = lst;
            pool_slice = lst.items;
        },
    }

    var n_d3: usize = 0;
    var n_payoff: usize = 0;
    var n_cert: usize = 0;
    const found = discoverStone(hidden, atoms.slice(), &[_]usize{ti}, pool_slice, fseed, &n_d3, &n_payoff, &n_cert);

    var res = TargetResult{
        .target = ti,
        .condition = cond,
        .lib_size = atoms.len,
        .solved = found != null,
        .event = if (found != null) "auto_discovered" else "not_found",
        .pool_size = pool_slice.len,
        .n_d3 = n_d3,
        .n_payoff_pos = n_payoff,
        .n_certified = n_cert,
        .payoff = 0,
        .cand_len = 0,
        .agree_noveltyflag = -1,
        .agree_own_stone = -1,
        .ms = 0,
    };
    if (found) |fs| {
        res.payoff = fs.payoff;
        res.cand_len = fs.len;
        var nov = noveltyFlagProg();
        var fp = fs.prog;
        res.agree_noveltyflag = progAgreement(&fp, &nov, MATCH_SEQ, MATCH_L, RESIDUAL_SEED);
        if (ownStoneFor(ti)) |*os| {
            res.agree_own_stone = progAgreement(&fp, os, MATCH_SEQ, MATCH_L, RESIDUAL_SEED);
        }
    }
    res.ms = timer.read() / std.time.ns_per_ms;
    return res;
}

// =============================================================================
// CSV plumbing
// =============================================================================

const CSV_HEADER = "phase,condition,target,seed,lib_size,solved,event,pool_size,n_d3,n_payoff_pos,n_certified,payoff,cand_len,agree_noveltyflag,agree_own_stone,ms\n";

fn openCsv(path: []const u8) !std.fs.File {
    if (std.fs.cwd().openFile(path, .{ .mode = .write_only })) |f| {
        try f.seekFromEnd(0);
        return f;
    } else |_| {
        const f = try std.fs.cwd().createFile(path, .{});
        try f.writeAll(CSV_HEADER);
        return f;
    }
}

fn condName(c: Condition) []const u8 {
    return switch (c) {
        .a => "A_full_transfer",
        .b => "B_prior_only",
        .c => "C_cold",
    };
}

fn writeResult(cw: anytype, phase: []const u8, seed: u64, r: TargetResult) !void {
    try cw.print("{s},{s},{s},0x{X},{d},{d},{s},{d},{d},{d},{d},{d},{d},{d:.4},{d:.4},{d}\n", .{
        phase, condName(r.condition), SPECS[r.target].name, seed, r.lib_size, if (r.solved) @as(usize, 1) else @as(usize, 0), r.event, r.pool_size, r.n_d3, r.n_payoff_pos, r.n_certified, r.payoff, r.cand_len, r.agree_noveltyflag, r.agree_own_stone, r.ms,
    });
}

// =============================================================================
// selftest
// =============================================================================

fn runSelftest(al: std.mem.Allocator, out: anytype) !void {
    const hidden = buildHidden();
    const atoms0 = forge.baseAtoms();

    var wall_reach: usize = 0;
    for (WALL_IDX) |ti| {
        if (targetSolvable(&hidden, SPECS[ti].idxs, atoms0.slice(), DEPTH, RSEED)) wall_reach += 1;
    }
    try out.print("[selftest] baseline WALL reachability (base atoms only) = {d}/{d} (expect 0)\n", .{ wall_reach, WALL_IDX.len });

    var mem_p = membershipProg();
    var nov_p = noveltyFlagProg();
    const fseed: u64 = 0xA70F +% 0xA70F;
    const cert_mem = certifiableDepth3(&mem_p, atoms0.slice(), fseed) and certifiableDepth4(&mem_p, atoms0.slice(), fseed);
    const cert_nov = certifiableDepth3(&nov_p, atoms0.slice(), fseed) and certifiableDepth4(&nov_p, atoms0.slice(), fseed);
    try out.print("[selftest] membership(S1) certifiable={s}  noveltyflag(S2) certifiable={s} (expect both yes)\n", .{ if (cert_mem) "yes" else "no", if (cert_nov) "yes" else "no" });

    // NEW target instrument checks: are togglecount/eqflag irreducible relative to
    // (a) base atoms alone, and (b) base atoms + noveltyflag (the promoted mechanism)?
    var toggle_p = togglecountProg();
    var eq_p = eqflagProg();
    const toggle_vs_base = certifiableDepth3(&toggle_p, atoms0.slice(), fseed);
    const eq_vs_base = certifiableDepth3(&eq_p, atoms0.slice(), fseed);
    try out.print("[selftest] togglecount irreducible vs base atoms: {s}   eqflag irreducible vs base atoms: {s}\n", .{ if (toggle_vs_base) "yes" else "NO(reducible)", if (eq_vs_base) "yes" else "NO(reducible)" });

    var atoms_plus_nov = forge.baseAtoms();
    atoms_plus_nov.appendAssumeCapacity(nov_p);
    const toggle_vs_nov = certifiableDepth3(&toggle_p, atoms_plus_nov.slice(), fseed);
    const eq_vs_nov = certifiableDepth3(&eq_p, atoms_plus_nov.slice(), fseed);
    try out.print("[selftest] togglecount irreducible vs base+noveltyflag: {s}   eqflag irreducible vs base+noveltyflag: {s}\n", .{ if (toggle_vs_nov) "yes(mechanism doesn't help)" else "NO(mechanism composes it!)", if (eq_vs_nov) "yes(mechanism doesn't help)" else "NO(mechanism composes it!)" });

    try out.print("[selftest] hasRMWShape: togglecount={}  eqflag={}  noveltyflag={} (expect all true)\n", .{ hasRMWShape(&toggle_p), hasRMWShape(&eq_p), hasRMWShape(&nov_p) });

    try out.writeAll("[selftest] building COVER-fair pool (one-time, ~1-2 min)...\n");
    var cr = try buildCoverPool(al);
    defer cr.pool.deinit();
    try out.print("[selftest] COVER distinct behaviours: L1={d} L2={d} L3={d} -> pool size {d}\n", .{ cr.n_distinct[0], cr.n_distinct[1], cr.n_distinct[2], cr.pool.items.len });

    var n_equiv_nov: usize = 0;
    var n_equiv_toggle: usize = 0;
    var n_equiv_eq: usize = 0;
    for (cr.pool.items) |p| {
        var pp = p;
        if (pp.step.len == 3) {
            if (progAgreement(&pp, &nov_p, MATCH_SEQ, MATCH_L, RESIDUAL_SEED) >= forge.MATCH_THRESHOLD) n_equiv_nov += 1;
            if (progAgreement(&pp, &toggle_p, MATCH_SEQ, MATCH_L, RESIDUAL_SEED) >= forge.MATCH_THRESHOLD) n_equiv_toggle += 1;
            if (progAgreement(&pp, &eq_p, MATCH_SEQ, MATCH_L, RESIDUAL_SEED) >= forge.MATCH_THRESHOLD) n_equiv_eq += 1;
        }
    }
    try out.print("[selftest] COVER (fair) pool contains OUT_R-equivalents: noveltyflag={d}  togglecount={d}  eqflag={d}\n", .{ n_equiv_nov, n_equiv_toggle, n_equiv_eq });
    try out.print("[selftest] (in the leading PHASE1_CHUNK={d} slice: noveltyflag={d} togglecount={d} eqflag={d})\n", .{ PHASE1_CHUNK, countEquiv(cr.pool.items[0..@min(PHASE1_CHUNK, cr.pool.items.len)], &nov_p), countEquiv(cr.pool.items[0..@min(PHASE1_CHUNK, cr.pool.items.len)], &toggle_p), countEquiv(cr.pool.items[0..@min(PHASE1_CHUNK, cr.pool.items.len)], &eq_p) });

    try out.writeAll("[selftest] running Phase 1 discovery against the leading chunk...\n");
    const p1 = runPhase1(&hidden, cr.pool.items);
    try out.print("[selftest] Phase1: found={} payoff={d}/{d} agree_s1={d:.3} agree_s2={d:.3} n_d3={d} n_payoff_pos={d} n_certified={d}\n", .{ p1.found, p1.payoff, WALL_IDX.len, p1.agree_s1, p1.agree_s2, p1.n_d3, p1.n_payoff_pos, p1.n_certified });
}

fn countEquiv(pool: []const alien.Program, ref: *const alien.Program) usize {
    var n: usize = 0;
    for (pool) |p| {
        var pp = p;
        if (pp.step.len == 3 and progAgreement(&pp, ref, MATCH_SEQ, MATCH_L, RESIDUAL_SEED) >= forge.MATCH_THRESHOLD) n += 1;
    }
    return n;
}

// =============================================================================
// main
// =============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const al = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(al);
    defer std.process.argsFree(al, args);
    if (args.len < 2) {
        try out.writeAll("usage: prior_transfer selftest | phase1 <csv> | phase2 <a|b|c> <csv> [--start=N] [--count=N] [--chunk=N] [--seed=0x..]\n");
        return;
    }
    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "selftest")) {
        try runSelftest(al, out);
        return;
    }

    const hidden = buildHidden();
    try out.writeAll("[setup] building COVER-fair pool (one-time, ~1-2 min)...\n");
    var cr = try buildCoverPool(al);
    defer cr.pool.deinit();
    try out.print("[setup] COVER pool ready: L1={d} L2={d} L3={d} size={d}\n", .{ cr.n_distinct[0], cr.n_distinct[1], cr.n_distinct[2], cr.pool.items.len });
    try out.writeAll("[setup] running Phase 1 discovery (deterministic, reproduces E3)...\n");
    const p1 = runPhase1(&hidden, cr.pool.items);
    try out.print("[setup] Phase1: found={} payoff={d}/{d} agree_s1={d:.3} agree_s2={d:.3} len={d}\n", .{ p1.found, p1.payoff, WALL_IDX.len, p1.agree_s1, p1.agree_s2, p1.atom.len() });
    if (!p1.found) {
        try out.writeAll("[FATAL] Phase 1 failed to reproduce E3's discovery -- aborting.\n");
        return;
    }

    if (std.mem.eql(u8, cmd, "phase1")) {
        const csv = try openCsv(args[2]);
        defer csv.close();
        const cw = csv.writer();
        var r = TargetResult{ .target = 0, .condition = .b, .lib_size = forge.BASE_ATOMS, .solved = true, .event = "auto_discovered", .pool_size = p1.pool_checked, .n_d3 = p1.n_d3, .n_payoff_pos = p1.n_payoff_pos, .n_certified = p1.n_certified, .payoff = p1.payoff, .cand_len = p1.atom.len(), .agree_noveltyflag = p1.agree_s2, .agree_own_stone = -1, .ms = 0 };
        try writeResult(cw, "phase1_seed", 0, r);
        // Positive control: try the SAME target (distinct) COLD (condition C) to
        // reconfirm D5/E3's established 0/9-style failure, in-file.
        var prng = std.Random.DefaultPrng.init(0xC01D);
        var blind = std.ArrayList(alien.Program).init(al);
        defer blind.deinit();
        try buildBlindPool(prng.random(), @min(p1.pool_checked, cr.pool.items.len), &blind);
        var atoms0 = forge.baseAtoms();
        var n_d3: usize = 0;
        var n_payoff: usize = 0;
        var n_cert: usize = 0;
        const cold_found = discoverStone(&hidden, atoms0.slice(), &WALL_IDX, blind.items, 0xA70F +% 0xA70F, &n_d3, &n_payoff, &n_cert);
        try out.print("[phase1] cold control (blind pool, size {d}) vs WALL_IDX(7): found={} (expect false, matches D5/E3 0/9)\n", .{ blind.items.len, cold_found != null });
        r = .{ .target = 0, .condition = .c, .lib_size = forge.BASE_ATOMS, .solved = cold_found != null, .event = if (cold_found != null) "auto_discovered" else "not_found", .pool_size = blind.items.len, .n_d3 = n_d3, .n_payoff_pos = n_payoff, .n_certified = n_cert, .payoff = 0, .cand_len = 0, .agree_noveltyflag = -1, .agree_own_stone = -1, .ms = 0 };
        try writeResult(cw, "phase1_seed", 0, r);
        try out.print("\n[phase1] promoted atom (for reference — this is the mechanism Phase 2 condition A carries forward):\n", .{});
        var wp = p1.atom;
        try alien.writeProgram(&wp, out);
        return;
    }

    if (std.mem.eql(u8, cmd, "phase2")) {
        if (args.len < 4) {
            try out.writeAll("usage: prior_transfer phase2 <a|b|c> <csv> [--start=N] [--count=N] [--chunk=N] [--seed=0x..]\n");
            return;
        }
        const cond: Condition = if (std.mem.eql(u8, args[2], "a")) .a else if (std.mem.eql(u8, args[2], "b")) .b else if (std.mem.eql(u8, args[2], "c")) .c else {
            try out.writeAll("condition must be a, b, or c\n");
            return;
        };
        var start: usize = 0;
        var count: usize = OTHER_IDX.len;
        var chunk: usize = 3000;
        var seed: u64 = 0xA70F;
        for (args[4..]) |a| {
            if (std.mem.startsWith(u8, a, "--start=")) {
                start = try std.fmt.parseInt(usize, a[8..], 10);
            } else if (std.mem.startsWith(u8, a, "--count=")) {
                count = try std.fmt.parseInt(usize, a[8..], 10);
            } else if (std.mem.startsWith(u8, a, "--chunk=")) {
                chunk = try std.fmt.parseInt(usize, a[8..], 10);
            } else if (std.mem.startsWith(u8, a, "--seed=")) {
                seed = try std.fmt.parseInt(u64, a[7..], 0);
            }
        }
        const csv = try openCsv(args[3]);
        defer csv.close();
        const cw = csv.writer();
        const end = @min(start + count, OTHER_IDX.len);
        try out.print("[phase2 {s}] targets [{d}..{d}) of {d}, chunk={d}, seed=0x{X}\n", .{ condName(cond), start, end, OTHER_IDX.len, chunk, seed });
        for (OTHER_IDX[start..end]) |ti| {
            var timer = try std.time.Timer.start();
            const promoted: ?alien.Program = if (cond == .a) p1.atom else null;
            const r = runPhase2Target(&hidden, ti, cond, promoted, cr.pool.items, chunk, seed);
            try out.print("  target={s:<20} solved={} event={s:<16} pool={d} d3={d} payoff_pos={d} cert={d} payoff={d} agree_nov={d:.3} agree_own={d:.3} ({d} ms)\n", .{ SPECS[ti].name, r.solved, r.event, r.pool_size, r.n_d3, r.n_payoff_pos, r.n_certified, r.payoff, r.agree_noveltyflag, r.agree_own_stone, timer.read() / std.time.ns_per_ms });
            try writeResult(cw, "phase2", seed, r);
        }
        return;
    }

    try out.writeAll("unknown command\n");
}
