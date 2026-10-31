//! NON-HUMAN GRAMMAR — does BULK MACHINE-INVENTED atom composition escape the
//! human-primitive-family wall? (round 2026-07-10d)
//!
//! THE HYPOTHESIS UNDER TEST (Micah's "it thinks the same way as humans"): every
//! primitive FAMILY the wcore atom-forge line has ever used (g_xor, g_add, pk_xor,
//! pk_add, shift, hashtbl, distinct-count) was HAND-DESIGNED by a human, and every
//! one of them is built from exactly six opcodes: a_set, a_mov, a_xor, a_add,
//! a_load, a_store. The alien substrate (inv_alien.zig) exposes 19 opcodes; the
//! other 12 (a_and, a_or, a_sub, a_mul, a_shl, a_shr, a_rotr, a_popcnt, a_mum,
//! a_bswap, a_eq, a_sel) have NEVER been used by a human-authored mechanism in
//! this codebase. This file asks: does the atom-forge's BULK, UNGUIDED,
//! machine-invented atom pool (not hand-picked solvers) contain atoms that are
//! genuinely outside the human families' span -- and does composing THOSE atoms
//! (and only those) reach a target that is PROVEN unreachable by any human-family
//! composition or by any program built purely from the human opcode vocabulary?
//!
//! HONEST FRAMING (mandatory culture): "machine-invented atoms span the same
//! closures as human families, no escape" is a valid, complete finding. An atom
//! only counts as "genuinely non-human" if BOTH:
//!   (1) BEHAVIOURAL: its output does not match (>=0.95 agreement) any depth<=3
//!       composition of the 7 deduped human-family reference atoms, and
//!   (2) MECHANISTIC: it uses >=1 opcode outside the human vocabulary, AND that
//!       opcode is LOAD-BEARING (stripping every non-human-vocab instruction
//!       measurably changes the atom's own behaviour).
//! Both are verified per-atom, not assumed. An atom that merely CONTAINS an
//! alien opcode but behaves identically once that opcode is stripped is NOT
//! counted as non-human (decorative, not load-bearing).
//!
//! DESIGN (4 phases, one binary, one CSV):
//!   Phase 0  Human-family library: 10 candidate hand-authored mechanisms,
//!            deduped by direct behavioural agreement + a "clean" (non-degenerate
//!            output) filter -- verified, not assumed, which ones are actually
//!            distinct families under the OUT_R convention this codebase uses.
//!            Human opcode vocabulary derived by scanning the survivors' actual
//!            instructions (not hand-typed).
//!   Phase 1  BULK atom pool: N_SEEDS diverse, UNAIMED atom-forge runs (novelty
//!            search + irreducibility census vs the 5 base atoms, exactly the
//!            inv_atomforge/inv_iterate protocol) -- collected into one pool,
//!            not curated, not hand-picked. Every pooled atom is classified:
//!            HUMAN_VOCAB / ALIEN_DECORATIVE / ALIEN_MECH_HUMAN_FUNC /
//!            GENUINELY_NON_HUMAN (both criteria above, jointly).
//!   Phase 2  THE TARGET: descent-parity (out[i] = parity of the number of
//!            positions <=i where sym[i] < sym[i-1] -- a running ORDER-RELATION
//!            aggregate, the streaming analogue of Tier 8's C09 inversion-count
//!            parity). Proven outside the human span three ways: (a) each human
//!            atom alone, (b) exhaustive depth<=3 composition of the human
//!            library, (c) a genuine SEARCH proof -- evolutionary search
//!            restricted to the human opcode vocabulary at a generous budget.
//!            A feasibility positive control (a hand-written 5-instruction alien
//!            program using a_sub+a_shr, NOT part of the human library) confirms
//!            the target is achievable in the substrate at all.
//!   Phase 3  THE REACH TEST, equal budget: (i) exhaustive depth<=3 composition
//!            of a size-capped, diversity-prioritised subset of the BULK machine
//!            atom pool vs the target; (ii) an unrestricted (full-opcode) raw
//!            program search at the SAME evaluation budget as (i)'s combo count,
//!            as a control (does the raw vocabulary trivially contain the answer
//!            without needing forged atoms at all?); (iii) the human-op-restricted
//!            search at that same matched budget, for a clean apples-to-apples row.
//!   Phase 4  Retro-audit + sharp classification: any solve (>=0.95) is
//!            re-verified on an independent, larger, disjoint-seed sample and a
//!            local depth+1 neighbourhood is probed; the winning chain's
//!            constituent atoms are looked up in the Phase-1 classification to
//!            answer the sharp question directly.
//!
//! This file is standalone: it imports inv_alien / inv_coevo / inv_open /
//! inv_atomforge / inv_frontier READ-ONLY (all already pub) and does not modify
//! any existing file. Single-threaded. Deterministic given the seed list.
//!
//! Build:  zig build-exe -O ReleaseFast src/nonhuman_grammar.zig -femit-bin=bin/nonhuman_grammar
//! Run:    ./bin/nonhuman_grammar selftest
//!         ./bin/nonhuman_grammar full ../results/nonhuman_grammar_2026_07_10.csv

const std = @import("std");
const alien = @import("inv_alien.zig");
const coevo = @import("inv_coevo.zig");
const open = @import("inv_open.zig");
const forge = @import("inv_atomforge.zig");
const fr = @import("inv_frontier.zig");

const V: usize = alien.CANON_BASE; // 4-symbol alphabet
const MATCH_THRESHOLD: f64 = forge.MATCH_THRESHOLD; // 0.95, same bar the whole arc uses

// =============================================================================
// PHASE 0 — the human-family library, derived and deduped, not hand-typed.
// =============================================================================

const HFCand = struct { name: []const u8, prog: alien.Program };

fn humanCandidates() [10]HFCand {
    return .{
        .{ .name = "g_xor", .prog = coevo.refSolver(.g_xor) },
        .{ .name = "g_add", .prog = coevo.refSolver(.g_add) },
        .{ .name = "pk_xor", .prog = coevo.refSolver(.pk_xor) },
        .{ .name = "pk_add", .prog = coevo.refSolver(.pk_add) },
        .{ .name = "shift", .prog = forge.shiftAtom() },
        .{ .name = "hashtbl", .prog = alien.alienHashTable() },
        .{ .name = "distinct", .prog = coevo.distinctCountProg() },
        .{ .name = "union", .prog = alien.alienUnion() },
        .{ .name = "rmw_counter", .prog = alien.alienRMWCounter() },
        .{ .name = "xor_scan", .prog = alien.alienXorScan() },
    };
}

fn opInSet(op: alien.Op, set: []const alien.Op) bool {
    for (set) |o| if (o == op) return true;
    return false;
}

fn scanOps(prog: *const alien.Program, seen: []bool) void {
    for (prog.setup.slice()) |ins| seen[@intFromEnum(ins.op)] = true;
    for (prog.step.slice()) |ins| seen[@intFromEnum(ins.op)] = true;
}

// generic single-program-vs-single-program behavioural agreement, via the SAME
// chain machinery (forge.applyChain / alien.runStream) the rest of the arc uses.
fn chainAgree(
    lib_a: []const alien.Program,
    idxs_a: []const usize,
    lib_b: []const alien.Program,
    idxs_b: []const usize,
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
        forge.applyChain(lib_a, idxs_a, syms[0..L], out_a[0..L]);
        forge.applyChain(lib_b, idxs_b, syms[0..L], out_b[0..L]);
        for (0..L) |i| {
            total += 1;
            if (out_a[i] == out_b[i]) agree += 1;
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total));
}

fn singleAgreement(a: *const alien.Program, b: *const alien.Program, n: usize, L: usize, seed: u64) f64 {
    var la = [1]alien.Program{a.*};
    var lb = [1]alien.Program{b.*};
    const zi = [_]usize{0};
    return chainAgree(&la, &zi, &lb, &zi, n, L, seed);
}

const HUMAN_LIB_MAX = 10;
pub const HumanLib = struct {
    names: [HUMAN_LIB_MAX][]const u8 = undefined,
    progs: [HUMAN_LIB_MAX]alien.Program = undefined,
    n: usize = 0,
    fn slice(self: *const HumanLib) []const alien.Program {
        return self.progs[0..self.n];
    }
};

/// Build the deduped human-family library, printing the process (dedup by
/// direct agreement, exclude degenerate/non-"clean" candidates) so the result is
/// VERIFIED, not assumed.
fn buildHumanLib(out: anytype, seed: u64) !HumanLib {
    const cands = humanCandidates();
    var lib = HumanLib{};
    try out.writeAll("\n-- Phase 0: human-family library construction --\n");
    for (cands) |c| {
        if (!forge.clean(&c.prog, seed)) {
            try out.print("  DROP  {s:<12} (degenerate: OUT_R entropy <= 0.30 -- not a real family)\n", .{c.name});
            continue;
        }
        var dup_of: ?[]const u8 = null;
        for (0..lib.n) |i| {
            const a = singleAgreement(&c.prog, &lib.progs[i], 16, 28, seed);
            if (a >= MATCH_THRESHOLD) {
                dup_of = lib.names[i];
                break;
            }
        }
        if (dup_of) |d| {
            try out.print("  DROP  {s:<12} (duplicate of {s}, behavioural agreement >= {d:.2})\n", .{ c.name, d, MATCH_THRESHOLD });
            continue;
        }
        lib.names[lib.n] = c.name;
        lib.progs[lib.n] = c.prog;
        lib.n += 1;
        try out.print("  KEEP  {s:<12}\n", .{c.name});
    }
    try out.print("  final human library: {d} distinct families: ", .{lib.n});
    for (0..lib.n) |i| try out.print("{s} ", .{lib.names[i]});
    try out.writeAll("\n");
    return lib;
}

const ALL_OPS_N = alien.Op.count();

fn deriveHumanOps(al: std.mem.Allocator, lib: *const HumanLib, out: anytype) ![]alien.Op {
    var seen = [_]bool{false} ** ALL_OPS_N;
    for (0..lib.n) |i| scanOps(&lib.progs[i], &seen);
    var buf: [ALL_OPS_N]alien.Op = undefined;
    var n: usize = 0;
    try out.writeAll("  human opcode vocabulary (scanned, not hand-typed): ");
    for (0..ALL_OPS_N) |i| {
        if (seen[i]) {
            const op: alien.Op = @enumFromInt(i);
            buf[n] = op;
            n += 1;
            try out.print("{s} ", .{@tagName(op)});
        }
    }
    try out.writeAll("\n");
    return al.dupe(alien.Op, buf[0..n]); // heap-owned: buf is stack-local, must not be returned as-is
}

// =============================================================================
// THE TARGET — descent-parity: a running ORDER-RELATION aggregate. Streaming
// analogue of Tier 8's C09 (inversion-count parity). Ground truth is a plain
// Zig function (no alien execution), exactly the convention distinctCountTarget
// uses.
// =============================================================================

fn descentParityTarget(syms: []const u8, out: []u8) void {
    var cnt: usize = 0;
    for (syms, 0..) |s, i| {
        if (i > 0 and s < syms[i - 1]) cnt += 1;
        out[i] = @intCast(cnt % 2);
    }
}

/// Feasibility POSITIVE CONTROL: a hand-written alien program that computes
/// descent-parity exactly, via a_sub (wrapping subtract) + a_shr (extract the
/// sign bit of the wraparound) -- two opcodes NO human-authored mechanism in
/// this codebase has ever used. NOT part of the human library; exists only to
/// prove the target is reachable in the substrate at all (so a "no escape"
/// result downstream means genuinely "search didn't find it", not "nothing
/// could ever compute this").
fn descentParityAlienProg() alien.Program {
    var p = alien.Program{};
    p.step.appendAssumeCapacity(.{ .op = .a_mov, .a = alien.REG_TOK, .out = 4 }); // r4 = cur
    p.step.appendAssumeCapacity(.{ .op = .a_sub, .a = 4, .b = 9, .out = 5 }); // r5 = cur -% prev
    p.step.appendAssumeCapacity(.{ .op = .a_shr, .a = 5, .out = 6, .imm = 63 }); // r6 = 1 iff cur<prev
    p.step.appendAssumeCapacity(.{ .op = .a_xor, .a = alien.OUT_R, .b = 6, .out = alien.OUT_R }); // OUT_R ^= r6
    p.step.appendAssumeCapacity(.{ .op = .a_mov, .a = 4, .out = 9 }); // prev = cur
    return p;
}

fn chainVsTarget(lib: []const alien.Program, idxs: []const usize, n: usize, L: usize, seed: u64) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var tgt: [256]u8 = undefined;
    var got: [256]u8 = undefined;
    var agree: usize = 0;
    var total: usize = 0;
    for (0..n) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        descentParityTarget(syms[0..L], tgt[0..L]);
        forge.applyChain(lib, idxs, syms[0..L], got[0..L]);
        for (0..L) |i| {
            total += 1;
            if (got[i] == tgt[i]) agree += 1;
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total));
}

fn targetAgreement(prog: *const alien.Program, n: usize, L: usize, seed: u64) f64 {
    var la = [1]alien.Program{prog.*};
    const zi = [_]usize{0};
    return chainVsTarget(&la, &zi, n, L, seed);
}

const ComposeResult = struct { best: f64 = 0, depth: usize = 0, idxs: [3]usize = .{ 0, 0, 0 }, n_combos: usize = 0 };

/// Exhaustive depth<=max_depth composition search of `lib` vs the descent-parity
/// target. Returns the TRUE best (no early exit), so "closest approach" is honest
/// even on a non-solve, matching the claimc_attack reporting convention.
fn exhaustiveComposeVsTarget(lib: []const alien.Program, max_depth: usize, n: usize, L: usize, seed: u64) ComposeResult {
    var res = ComposeResult{};
    const m = lib.len;
    if (m == 0) return res;
    var d: usize = 1;
    while (d <= max_depth) : (d += 1) {
        var total: usize = 1;
        for (0..d) |_| total *= m;
        var idx: usize = 0;
        while (idx < total) : (idx += 1) {
            var idxs: [8]usize = undefined;
            var x = idx;
            for (0..d) |j| {
                idxs[j] = x % m;
                x /= m;
            }
            const a = chainVsTarget(lib, idxs[0..d], n, L, seed);
            res.n_combos += 1;
            if (a > res.best) {
                res.best = a;
                res.depth = d;
                for (0..d) |j| res.idxs[j] = idxs[j];
            }
        }
    }
    return res;
}

/// Best behavioural agreement of any depth<=max_depth composition of `lib`
/// against a single candidate atom (chain-vs-chain, not chain-vs-target). Used
/// for Phase-1 classification: "does this pooled atom span the human family?"
fn bestComposeVsAtomPerDepth(lib: []const alien.Program, max_depth: usize, atom: *const alien.Program, n: usize, L: usize, seed: u64) [3]f64 {
    var out = [_]f64{ 0, 0, 0 };
    const m = lib.len;
    if (m == 0) return out;
    var la = [1]alien.Program{atom.*};
    const zi = [_]usize{0};
    var d: usize = 1;
    while (d <= max_depth) : (d += 1) {
        var total: usize = 1;
        for (0..d) |_| total *= m;
        var idx: usize = 0;
        var best: f64 = 0;
        while (idx < total) : (idx += 1) {
            var idxs: [8]usize = undefined;
            var x = idx;
            for (0..d) |j| {
                idxs[j] = x % m;
                x /= m;
            }
            const a = chainAgree(lib, idxs[0..d], &la, &zi, n, L, seed);
            if (a > best) best = a;
        }
        out[d - 1] = best;
    }
    return out;
}

// =============================================================================
// Op-vocabulary mechanism check: does an atom use only human ops? if not, is the
// alien-opcode usage LOAD-BEARING (does stripping it change the atom's own
// behaviour)?
// =============================================================================

fn usesOnlyOps(prog: *const alien.Program, allowed: []const alien.Op) bool {
    for (prog.setup.slice()) |ins| if (ins.op != .nop and !opInSet(ins.op, allowed)) return false;
    for (prog.step.slice()) |ins| if (ins.op != .nop and !opInSet(ins.op, allowed)) return false;
    return true;
}

fn stripNonAllowed(prog: alien.Program, allowed: []const alien.Op) alien.Program {
    var p = prog;
    for (p.setup.slice()) |*ins| if (!opInSet(ins.op, allowed)) {
        ins.* = .{};
    };
    for (p.step.slice()) |*ins| if (!opInSet(ins.op, allowed)) {
        ins.* = .{};
    };
    return p;
}

fn alienOpsUsed(prog: *const alien.Program, human_ops: []const alien.Op, buf: []u8) []const u8 {
    var seen = [_]bool{false} ** ALL_OPS_N;
    scanOps(prog, &seen);
    var w = std.io.fixedBufferStream(buf);
    const writer = w.writer();
    var first = true;
    for (0..ALL_OPS_N) |i| {
        if (!seen[i]) continue;
        const op: alien.Op = @enumFromInt(i);
        if (op == .nop) continue; // a no-op instruction slot is never a "mechanism", human or alien
        if (opInSet(op, human_ops)) continue;
        if (!first) writer.writeAll("+") catch {};
        writer.writeAll(@tagName(op)) catch {};
        first = false;
    }
    return w.getWritten();
}

// =============================================================================
// PHASE 1 — bulk, unaimed atom-forge pool (many diverse seeds, one round each,
// the exact inv_atomforge/inv_iterate census protocol; NOT hand-picked).
// =============================================================================

const Classification = enum { human_vocab, alien_decorative, alien_mech_human_func, genuinely_non_human };

fn classLabel(c: Classification) []const u8 {
    return switch (c) {
        .human_vocab => "HUMAN_VOCAB",
        .alien_decorative => "ALIEN_DECORATIVE",
        .alien_mech_human_func => "ALIEN_MECH_HUMAN_FUNC",
        .genuinely_non_human => "GENUINELY_NON_HUMAN",
    };
}

const PooledAtom = struct {
    prog: alien.Program,
    src_seed: u64,
    length: usize,
    d1: f64 = 0,
    d2: f64 = 0,
    d3: f64 = 0,
    uses_only_human: bool = false,
    alien_load_bearing: bool = false,
    class: Classification = .human_vocab,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const al = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(al);
    defer std.process.argsFree(al, args);
    if (args.len < 2) {
        try out.writeAll("usage: nonhuman_grammar selftest\n       nonhuman_grammar full <csv_path> [--nseeds=N] [--reach_cap=N]\n");
        return;
    }

    if (std.mem.eql(u8, args[1], "selftest")) {
        try runSelftest(al, out);
        return;
    }

    if (!std.mem.eql(u8, args[1], "full") or args.len < 3) {
        try out.writeAll("usage: nonhuman_grammar full <csv_path> [--nseeds=N] [--reach_cap=N]\n");
        return;
    }
    const csv_path = args[2];
    var nseeds: usize = 24;
    var reach_cap: usize = 120;
    var pop: usize = 90;
    var gens: usize = 45;
    for (args[3..]) |a| {
        if (std.mem.startsWith(u8, a, "--nseeds=")) {
            nseeds = try std.fmt.parseInt(usize, a[9..], 10);
        } else if (std.mem.startsWith(u8, a, "--reach_cap=")) {
            reach_cap = try std.fmt.parseInt(usize, a[12..], 10);
        } else if (std.mem.startsWith(u8, a, "--pop=")) {
            pop = try std.fmt.parseInt(usize, a[6..], 10);
        } else if (std.mem.startsWith(u8, a, "--gens=")) {
            gens = try std.fmt.parseInt(usize, a[7..], 10);
        }
    }

    try runFull(al, out, csv_path, nseeds, reach_cap, pop, gens);
}

fn runSelftest(al: std.mem.Allocator, out: anytype) !void {
    try out.writeAll("=== SELFTEST ===\n");
    const seed: u64 = 0xA70F;

    var lib = try buildHumanLib(out, seed);
    const hops = try deriveHumanOps(al, &lib, out);
    defer al.free(hops);

    // feasibility positive control
    const ap = descentParityAlienProg();
    const fa = targetAgreement(&ap, 32, 32, seed);
    try out.print("  feasibility (alien sub+shr solver) vs descent-parity target: {d:.4} (expect > 0.99)\n", .{fa});
    if (fa <= 0.99) {
        try out.writeAll("  FAIL: feasibility control does not reach target -- target definition or alien program is wrong\n");
        return error.SelftestFailed;
    }

    // basic sanity: g_xor matches itself trivially through the classifier
    var gx_idx: ?usize = null;
    for (0..lib.n) |i| if (std.mem.eql(u8, lib.names[i], "g_xor")) {
        gx_idx = i;
    };
    if (gx_idx) |gi| {
        const d = bestComposeVsAtomPerDepth(lib.slice(), 3, &lib.progs[gi], 8, 28, seed);
        try out.print("  g_xor vs itself through classifier (depth1/2/3): {d:.3} {d:.3} {d:.3} (expect d1 ~1.0)\n", .{ d[0], d[1], d[2] });
        if (d[0] < 0.99) {
            try out.writeAll("  FAIL: an atom does not match itself at depth 1\n");
            return error.SelftestFailed;
        }
    }

    // op-vocab check
    try out.print("  human ops count: {d} (expect 6: a_set a_mov a_xor a_add a_load a_store)\n", .{hops.len});

    // uses_only_human should be true for every human-lib member
    for (0..lib.n) |i| {
        if (!usesOnlyOps(&lib.progs[i], hops)) {
            try out.print("  FAIL: human family '{s}' itself uses a non-human op -- vocabulary derivation is broken\n", .{lib.names[i]});
            return error.SelftestFailed;
        }
    }

    try out.writeAll("=== SELFTEST PASS ===\n");
}

fn runFull(al: std.mem.Allocator, out: anytype, csv_path: []const u8, nseeds: usize, reach_cap: usize, pop: usize, gens: usize) !void {
    var timer_all = try std.time.Timer.start();
    const csv = try std.fs.cwd().createFile(csv_path, .{});
    defer csv.close();
    const cw = csv.writer();
    try cw.writeAll("phase,label,seed,atom_idx,length,agree1,agree2,agree3,flag,extra\n");

    // ---- Phase 0 ----
    var human_lib = try buildHumanLib(out, 0xA70F);
    const human_ops = try deriveHumanOps(al, &human_lib, out);
    defer al.free(human_ops);
    for (0..human_lib.n) |i| {
        try cw.print("phase0,human_family,0,{d},{d},0,0,0,1,{s}\n", .{ i, human_lib.progs[i].len(), human_lib.names[i] });
    }
    for (human_ops) |o| {
        try cw.print("phase0,human_op,0,0,0,0,0,0,1,{s}\n", .{@tagName(o)});
    }

    // ---- feasibility control ----
    const ap = descentParityAlienProg();
    const feas = targetAgreement(&ap, 32, 64, 0x0FEA5);
    try out.print("\n-- feasibility control: alien sub+shr solver vs descent-parity: {d:.4} --\n", .{feas});
    try cw.print("phase0,feasibility_control,0,0,{d},{d:.6},0,0,{d},alien_sub_shr\n", .{ ap.len(), feas, @as(u32, if (feas >= MATCH_THRESHOLD) 1 else 0) });

    // ---- Phase 1: bulk atom pool ----
    try out.print("\n-- Phase 1: bulk atom-forge pool, {d} diverse seeds, pop={d} gens={d} --\n", .{ nseeds, pop, gens });
    const base_atoms = forge.baseAtoms();
    var pool = std.ArrayList(PooledAtom).init(al);
    defer pool.deinit();
    const MAX_POOL: usize = 1200;
    const CENSUS_CAP: usize = 80;
    const BASE_SEED: u64 = 0xC0FFEE;

    var seed_i: usize = 0;
    while (seed_i < nseeds and pool.items.len < MAX_POOL) : (seed_i += 1) {
        var pt = try std.time.Timer.start();
        const seed = BASE_SEED +% seed_i *% 0x9E3779B97F4A7C15;
        const dseed = seed ^ 0x1F0;
        const fseed = seed +% 0xA70F;
        var prng = std.Random.DefaultPrng.init(seed);
        var archive = try open.search(al, prng.random(), .{ .pop = pop, .gens = gens, .info = true, .seed = dseed });
        defer archive.deinit();

        var cleanlist = std.ArrayList(open.Member).init(al);
        defer cleanlist.deinit();
        for (archive.items) |m| if (forge.clean(&m.prog, dseed)) try cleanlist.append(m);
        std.mem.sort(open.Member, cleanlist.items, {}, struct {
            fn lt(_: void, a: open.Member, b: open.Member) bool {
                return a.prog.len() < b.prog.len();
            }
        }.lt);

        const n_checked = @min(CENSUS_CAP, cleanlist.items.len);
        var n_irred: usize = 0;
        for (cleanlist.items[0..n_checked]) |m| {
            if (!forge.reducibleLib(&m.prog, base_atoms.slice(), forge.COMPOSE_DEPTH, fseed)) {
                n_irred += 1;
                if (pool.items.len < MAX_POOL) {
                    try pool.append(.{ .prog = m.prog, .src_seed = seed, .length = m.prog.len() });
                }
            }
        }
        const ms = pt.read() / std.time.ns_per_ms;
        try out.print("  seed 0x{X:0>8}: archive={d} clean={d} checked={d} irreducible={d} pool_total={d} ({d} ms)\n", .{ seed, archive.items.len, cleanlist.items.len, n_checked, n_irred, pool.items.len, ms });
        try cw.print("phase1,pool_seed,0x{X},{d},{d},{d},{d},0,0,\n", .{ seed, archive.items.len, cleanlist.items.len, n_checked, n_irred });
    }
    try out.print("  BULK MACHINE ATOM POOL: {d} atoms across {d} seeds (unaimed, unranked)\n", .{ pool.items.len, seed_i });
    try out.print("  phase 1 elapsed: {d} ms\n", .{timer_all.read() / std.time.ns_per_ms});

    // ---- classify every pooled atom ----
    try out.writeAll("\n-- classifying pool vs human family (behavioural) and human op vocabulary (mechanistic) --\n");
    var counts = [_]usize{0} ** 4;
    var pt2 = try std.time.Timer.start();
    for (pool.items, 0..) |*pa, i| {
        const d = bestComposeVsAtomPerDepth(human_lib.slice(), 3, &pa.prog, 8, 28, 0x51DE1);
        pa.d1 = d[0];
        pa.d2 = d[1];
        pa.d3 = d[2];
        const spans_human = @max(d[0], @max(d[1], d[2])) >= MATCH_THRESHOLD;
        pa.uses_only_human = usesOnlyOps(&pa.prog, human_ops);
        if (pa.uses_only_human) {
            pa.class = .human_vocab;
        } else {
            const stripped = stripNonAllowed(pa.prog, human_ops);
            const self_agree = singleAgreement(&pa.prog, &stripped, 16, 28, 0x57219);
            pa.alien_load_bearing = self_agree < MATCH_THRESHOLD;
            if (!pa.alien_load_bearing) {
                pa.class = .alien_decorative;
            } else if (spans_human) {
                pa.class = .alien_mech_human_func;
            } else {
                pa.class = .genuinely_non_human;
            }
        }
        counts[@intFromEnum(pa.class)] += 1;

        var opbuf: [256]u8 = undefined;
        const ops_str = alienOpsUsed(&pa.prog, human_ops, &opbuf);
        try cw.print("phase1,classify,0x{X},{d},{d},{d:.6},{d:.6},{d:.6},{d},{s};ops={s}\n", .{
            pa.src_seed, i, pa.length, pa.d1, pa.d2, pa.d3, @as(u32, if (spans_human) 1 else 0), classLabel(pa.class), ops_str,
        });
    }
    try out.print("  classification: HUMAN_VOCAB={d}  ALIEN_DECORATIVE={d}  ALIEN_MECH_HUMAN_FUNC={d}  GENUINELY_NON_HUMAN={d}  (total {d})\n", .{
        counts[@intFromEnum(Classification.human_vocab)],
        counts[@intFromEnum(Classification.alien_decorative)],
        counts[@intFromEnum(Classification.alien_mech_human_func)],
        counts[@intFromEnum(Classification.genuinely_non_human)],
        pool.items.len,
    });
    try out.print("  classification elapsed: {d} ms\n", .{pt2.read() / std.time.ns_per_ms});

    // ---- Phase 2: reproduce the human-family wall on the target ----
    try out.writeAll("\n-- Phase 2: reproduce the family-level wall on descent-parity --\n");
    for (0..human_lib.n) |i| {
        const a = targetAgreement(&human_lib.progs[i], 16, 32, 0x2A5E7);
        try out.print("  human atom alone: {s:<12} agreement={d:.4}\n", .{ human_lib.names[i], a });
        try cw.print("phase2,human_atom_alone,0,{d},{d},{d:.6},0,0,{d},{s}\n", .{ i, human_lib.progs[i].len(), a, @as(u32, if (a >= MATCH_THRESHOLD) 1 else 0), human_lib.names[i] });
    }
    const human_compose = exhaustiveComposeVsTarget(human_lib.slice(), 3, 8, 28, 0x2A5E7);
    try out.print("  human-family exhaustive depth<=3 composition: best={d:.4} at depth {d} ({d} combos)\n", .{ human_compose.best, human_compose.depth, human_compose.n_combos });
    try cw.print("phase2,human_compose_d3,0,0,0,{d:.6},{d},{d},{d},composition\n", .{ human_compose.best, human_compose.depth, human_compose.n_combos, @as(u32, if (human_compose.best >= MATCH_THRESHOLD) 1 else 0) });

    // ---- search proof: human-op-restricted raw programs, generous budget ----
    const WALL_BUDGET: usize = 300_000;
    try out.print("  human-op-restricted raw-program search (budget={d}/seed, 2 seeds):\n", .{WALL_BUDGET});
    var wall_best: f64 = 0;
    for ([_]u64{ 0xA70F, 0x5EED2 }) |sseed| {
        var prng = std.Random.DefaultPrng.init(sseed);
        const r = try evolveVsTarget(al, prng.random(), human_ops, WALL_BUDGET, 10, sseed +% 0x9999);
        wall_best = @max(wall_best, r.best_score);
        try out.print("    seed 0x{X}: best={d:.4} (len {d})\n", .{ sseed, r.best_score, r.best.len() });
        try cw.print("phase2,human_op_search,0x{X},0,{d},{d:.6},0,0,{d},budget={d}\n", .{ sseed, r.best.len(), r.best_score, @as(u32, if (r.best_score >= MATCH_THRESHOLD) 1 else 0), WALL_BUDGET });
    }
    try out.print("  WALL VERDICT: human family (named atoms, compositions, AND raw-op-restricted search) best = {d:.4} vs {d:.2} bar\n", .{ @max(human_compose.best, wall_best), MATCH_THRESHOLD });

    // ---- Phase 3: the reach test, equal budget ----
    try out.writeAll("\n-- Phase 3: machine-atom-pool reach test (equal budget vs human arms) --\n");
    // select reach pool: prioritise interesting classifications first
    var reach_idx = std.ArrayList(usize).init(al);
    defer reach_idx.deinit();
    inline for ([_]Classification{ .genuinely_non_human, .alien_mech_human_func, .alien_decorative, .human_vocab }) |want| {
        for (pool.items, 0..) |pa, i| {
            if (reach_idx.items.len >= reach_cap) break;
            if (pa.class == want) try reach_idx.append(i);
        }
    }
    var reach_pool = try al.alloc(alien.Program, reach_idx.items.len);
    defer al.free(reach_pool);
    for (reach_idx.items, 0..) |src, i| reach_pool[i] = pool.items[src].prog;
    try out.print("  reach pool size: {d} (cap {d}), selection priority: non-human first\n", .{ reach_pool.len, reach_cap });

    var pt3 = try std.time.Timer.start();
    const machine_compose = exhaustiveComposeVsTarget(reach_pool, 3, 8, 28, 0x3B7E1);
    const ms3 = pt3.read() / std.time.ns_per_ms;
    try out.print("  machine-atom-pool exhaustive depth<=3 composition: best={d:.4} at depth {d} ({d} combos, {d} ms)\n", .{ machine_compose.best, machine_compose.depth, machine_compose.n_combos, ms3 });
    try out.print("    witness indices (into reach pool): ", .{});
    for (0..machine_compose.depth) |j| try out.print("{d} ", .{machine_compose.idxs[j]});
    try out.writeAll("\n");
    try cw.print("phase3,machine_pool_compose,0,0,0,{d:.6},{d},{d},{d},pool={d}\n", .{ machine_compose.best, machine_compose.depth, machine_compose.n_combos, @as(u32, if (machine_compose.best >= MATCH_THRESHOLD) 1 else 0), reach_pool.len });

    const BUDGET = machine_compose.n_combos; // equal-budget: same eval count for the search arms
    try out.print("  equal-budget control arms (budget={d}):\n", .{BUDGET});
    var unrestricted_best: f64 = 0;
    var restricted_best_matched: f64 = 0;
    for ([_]u64{ 0xA70F, 0x5EED2 }) |sseed| {
        var prng_u = std.Random.DefaultPrng.init(sseed +% 0x1111);
        const ru = try evolveVsTarget(al, prng_u.random(), null, BUDGET, 10, sseed +% 0x2222);
        unrestricted_best = @max(unrestricted_best, ru.best_score);
        try out.print("    unrestricted raw search  seed 0x{X}: best={d:.4} (len {d})\n", .{ sseed, ru.best_score, ru.best.len() });
        try cw.print("phase3,unrestricted_search,0x{X},0,{d},{d:.6},0,0,{d},budget={d}\n", .{ sseed, ru.best.len(), ru.best_score, @as(u32, if (ru.best_score >= MATCH_THRESHOLD) 1 else 0), BUDGET });

        var prng_r = std.Random.DefaultPrng.init(sseed +% 0x3333);
        const rr = try evolveVsTarget(al, prng_r.random(), human_ops, BUDGET, 10, sseed +% 0x4444);
        restricted_best_matched = @max(restricted_best_matched, rr.best_score);
        try out.print("    human-op-restricted search (matched budget) seed 0x{X}: best={d:.4} (len {d})\n", .{ sseed, rr.best_score, rr.best.len() });
        try cw.print("phase3,human_op_search_matched,0x{X},0,{d},{d:.6},0,0,{d},budget={d}\n", .{ sseed, rr.best.len(), rr.best_score, @as(u32, if (rr.best_score >= MATCH_THRESHOLD) 1 else 0), BUDGET });
    }
    try out.print("\n  REACH TEST SUMMARY (equal budget={d}):\n", .{BUDGET});
    try out.print("    human-family composition (depth<=3, {d} combos): {d:.4}\n", .{ human_compose.n_combos, human_compose.best });
    try out.print("    human-op-restricted search (matched budget):     {d:.4}\n", .{restricted_best_matched});
    try out.print("    MACHINE-ATOM-POOL composition (depth<=3):        {d:.4}\n", .{machine_compose.best});
    try out.print("    unrestricted raw search (matched budget):        {d:.4}\n", .{unrestricted_best});

    // ---- Phase 4: retro-audit + sharp classification of any winner ----
    try out.writeAll("\n-- Phase 4: retro-audit + sharp classification --\n");
    const solved = machine_compose.best >= MATCH_THRESHOLD;
    try cw.print("phase4,verdict,0,0,0,{d:.6},0,0,{d},solved={any}\n", .{ machine_compose.best, @as(u32, if (solved) 1 else 0), solved });

    // independent-sample re-verification of the best chain found (solve or not)
    const indep = chainVsTarget(reach_pool, machine_compose.idxs[0..machine_compose.depth], 48, 96, 0x9DE9E9);
    try out.print("  independent-sample re-verification (fresh disjoint seed, 48x96): {d:.6} (search-sample value was {d:.6})\n", .{ indep, machine_compose.best });
    try cw.print("phase4,retro_independent,0,0,{d},{d:.6},0,0,{d},orig={d:.6}\n", .{ machine_compose.depth, indep, @as(u32, if (indep >= MATCH_THRESHOLD) 1 else 0), machine_compose.best });

    // local depth+1 neighbourhood probe (append one more pool atom, either side)
    var neigh_best: f64 = machine_compose.best;
    var neigh_idxs: [4]usize = .{ 0, 0, 0, 0 };
    var neigh_depth: usize = machine_compose.depth;
    if (machine_compose.depth < 4 and reach_pool.len > 0) {
        for (0..reach_pool.len) |extra| {
            var idxs_front: [4]usize = undefined;
            idxs_front[0] = extra;
            for (0..machine_compose.depth) |j| idxs_front[j + 1] = machine_compose.idxs[j];
            const af = chainVsTarget(reach_pool, idxs_front[0 .. machine_compose.depth + 1], 8, 28, 0x3B7E1);
            if (af > neigh_best) {
                neigh_best = af;
                neigh_idxs = idxs_front;
                neigh_depth = machine_compose.depth + 1;
            }
            var idxs_back: [4]usize = undefined;
            for (0..machine_compose.depth) |j| idxs_back[j] = machine_compose.idxs[j];
            idxs_back[machine_compose.depth] = extra;
            const ab = chainVsTarget(reach_pool, idxs_back[0 .. machine_compose.depth + 1], 8, 28, 0x3B7E1);
            if (ab > neigh_best) {
                neigh_best = ab;
                neigh_idxs = idxs_back;
                neigh_depth = machine_compose.depth + 1;
            }
        }
    }
    try out.print("  local depth+1 neighbourhood probe: best={d:.6} at depth {d} (vs depth-{d} best {d:.6})\n", .{ neigh_best, neigh_depth, machine_compose.depth, machine_compose.best });
    try cw.print("phase4,retro_depth_plus1,0,0,{d},{d:.6},0,0,{d},base={d:.6}\n", .{ neigh_depth, neigh_best, @as(u32, if (neigh_best > machine_compose.best + 0.001) 1 else 0), machine_compose.best });

    // sharp classification of the winning chain's constituent atoms
    try out.writeAll("  winning-chain constituent atom classification:\n");
    for (0..machine_compose.depth) |j| {
        const src = reach_idx.items[machine_compose.idxs[j]];
        const pa = pool.items[src];
        var opbuf: [256]u8 = undefined;
        const ops_str = alienOpsUsed(&pa.prog, human_ops, &opbuf);
        try out.print("    witness[{d}] (reach_pool idx {d}, src_seed 0x{X}, len {d}): class={s}  alien_ops_used=[{s}]  best_human_span(d1/d2/d3)={d:.3}/{d:.3}/{d:.3}\n", .{
            j, machine_compose.idxs[j], pa.src_seed, pa.length, classLabel(pa.class), ops_str, pa.d1, pa.d2, pa.d3,
        });
        try cw.print("phase4,winner_atom,0x{X},{d},{d},{d:.6},{d:.6},{d:.6},{d},{s};ops={s}\n", .{
            pa.src_seed, src, pa.length, pa.d1, pa.d2, pa.d3, @as(u32, if (pa.class == .genuinely_non_human) 1 else 0), classLabel(pa.class), ops_str,
        });
    }

    try out.print("\n=== TOTAL ELAPSED: {d} ms ===\n", .{timer_all.read() / std.time.ns_per_ms});
}

// =============================================================================
// Evolutionary raw-program search vs the descent-parity target -- op-vocabulary
// can be restricted (human-op ceiling proof) or unrestricted (control).
// =============================================================================

const EvoResult = struct { best_score: f64, best: alien.Program, evals: usize };

fn evolveVsTarget(
    al: std.mem.Allocator,
    rng: std.Random,
    allowed_ops: ?[]const alien.Op,
    max_evals: usize,
    active_regs: usize,
    seed: u64,
) !EvoResult {
    _ = al;
    const Indiv = struct { prog: alien.Program, fit: f64 };
    const pop_size: usize = 400;
    var pop_buf: [400]Indiv = undefined;
    const pop = pop_buf[0..pop_size];
    var sp = alien.Params{ .active_regs = active_regs, .mem_bias = 0.25, .allowed_ops = allowed_ops };
    const lambda: f64 = 1e-4;
    const fit_L: usize = 32;
    const fit_n: usize = 10;

    var best: alien.Program = .{};
    var best_fit: f64 = -1;
    var best_adj: f64 = -1e9;
    var evals: usize = 0;

    for (pop) |*ind| {
        ind.prog = alien.randProg(rng, &sp);
        const raw = targetAgreement(&ind.prog, fit_n, fit_L, seed);
        ind.fit = raw - lambda * @as(f64, @floatFromInt(ind.prog.len()));
        evals += 1;
        if (ind.fit > best_adj) {
            best_adj = ind.fit;
            best_fit = raw;
            best = ind.prog;
        }
    }
    var oldest: usize = 0;
    while (evals < max_evals) {
        var child: alien.Program = undefined;
        if (rng.float(f64) < 0.18) {
            child = alien.randProg(rng, &sp);
        } else {
            var par = rng.uintLessThan(usize, pop_size);
            for (0..7) |_| {
                const c = rng.uintLessThan(usize, pop_size);
                if (pop[c].fit > pop[par].fit) par = c;
            }
            child = pop[par].prog;
            alien.mutate(rng, &child, &sp);
        }
        const raw = targetAgreement(&child, fit_n, fit_L, seed);
        const adj = raw - lambda * @as(f64, @floatFromInt(child.len()));
        evals += 1;
        pop[oldest] = .{ .prog = child, .fit = adj };
        oldest = (oldest + 1) % pop_size;
        if (adj > best_adj) {
            best_adj = adj;
            best_fit = raw;
            best = child;
        }
    }
    return .{ .best_score = best_fit, .best = best, .evals = evals };
}
