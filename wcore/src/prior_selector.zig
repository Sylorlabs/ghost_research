//! PRIOR SELECTOR: can the machine infer WHICH structural prior a target needs
//! from the target's own failure signature -- a generator-of-generators --
//! rather than being handed the prior by a human? (round 2026-07-11b, F1)
//!
//! THE FRONTIER THIS FILE ATTACKS: E3 (`smart_gen.zig`) proved a smart
//! generator CAN auto-discover a mechanism from scratch, but only when HANDED
//! the right structural prior (the RMW read-then-write-same-address shape, as
//! a coverage inclusion). E2 (`target_router.zig`) proved a learned router can
//! pick the right AIM lens from a target's cheap failure descriptor. This file
//! asks the fused question one level up: can a learned SELECTOR pick the right
//! GENERATION PRIOR (not just the right aim lens) from a target's failure
//! signature, on targets it never saw labeled -- or does the prior have to be
//! handed in every time, which would mean the residual human insight IS the
//! prior itself?
//!
//! SCOPE, STATED HONESTLY UP FRONT: this is a fresh, small, fully self-
//! contained re-instantiation of the four structural-prior SHAPES the round
//! has now named (RMW/counting from E3; mixed-radix-residue, comparison/order,
//! and run/adjacency from E1's family menu) -- not a literal import of E1's or
//! E3's production substrate (`inv_alien.zig`'s Machine and COVER apparatus are
//! private to `smart_gen.zig`; only `GenMode` is `pub`, so nothing there is
//! importable). A tiny new 5-register/14-op VM is built here, deliberately
//! shaped so exhaustive length-1..4 coverage stays tractable in minutes, and
//! four families of targets are hand-constructed (5 concrete instances each,
//! 20 total) whose ground-truth mechanisms need exactly the four shapes below.
//! The question under test -- can a descriptor-driven selector infer which
//! shape a NEVER-labeled target needs -- is answered on this substrate with
//! the same discipline (train/val/test split over TARGETS, leakage guard,
//! independent re-verification, honest negative reporting) the round uses
//! throughout.
//!
//! Build: cd wcore && zig build-exe -O ReleaseFast src/prior_selector.zig -femit-bin=bin/prior_selector
//! Run:   ./bin/prior_selector selftest
//!        ./bin/prior_selector run ../results/prior_selector_2026_07_11.csv
//! Single-threaded throughout (no std.Thread spawned). Deterministic (every
//! seed fixed in source). CSV opens in append mode.

const std = @import("std");

// =============================================================================
// SECTION 1 -- the mini substrate (self-contained; no dependency on any other
// project file, so this file's build/behaviour cannot be affected by, and
// cannot affect, `inv_alien.zig` or anything else already in the tree).
// =============================================================================

const V: u8 = 4; // token alphabet size {0,1,2,3}
const MEM: usize = 4; // memory cells, addressed mod MEM
const R: usize = 5; // registers: 0=TOK,1=A,2=B,3=C,4=OUT
const OUT_REG: u8 = 4;
const MAX_STEP: usize = 4; // matches the longest hand stone (RUN family)

const Op = enum(u8) {
    set0,
    set1,
    mov,
    add,
    xor,
    and_,
    mod3,
    gt,
    eq,
    sel,
    load,
    store,
    shr1,

    fn count() usize {
        return @typeInfo(Op).@"enum".fields.len;
    }
};

const Instr = struct { op: Op, a: u8 = 0, b: u8 = 0, c: u8 = 0, out: u8 = 0 };

const Prog = struct {
    has_setup: bool = false,
    setup: Instr = .{ .op = .set0 },
    step: [MAX_STEP]Instr = undefined,
    step_len: usize = 0,

    fn stepSlice(self: *const Prog) []const Instr {
        return self.step[0..self.step_len];
    }
    fn setupOpt(self: *const Prog) ?Instr {
        return if (self.has_setup) self.setup else null;
    }
};

const Machine = struct {
    reg: [R]u8 = [_]u8{0} ** R,
    mem: [MEM]u8 = [_]u8{0} ** MEM,

    fn execOne(self: *Machine, ins: Instr) void {
        const a = self.reg[ins.a % R];
        const b = self.reg[ins.b % R];
        const c = self.reg[ins.c % R];
        switch (ins.op) {
            .set0 => self.reg[ins.out % R] = 0,
            .set1 => self.reg[ins.out % R] = 1,
            .mov => self.reg[ins.out % R] = a,
            .add => self.reg[ins.out % R] = a +% b,
            .xor => self.reg[ins.out % R] = a ^ b,
            .and_ => self.reg[ins.out % R] = a & b,
            .mod3 => self.reg[ins.out % R] = a % 3,
            .gt => self.reg[ins.out % R] = if (a > b) 1 else 0,
            .eq => self.reg[ins.out % R] = if (a == b) 1 else 0,
            .sel => self.reg[ins.out % R] = if (c != 0) a else b,
            .load => self.reg[ins.out % R] = self.mem[a % MEM],
            .store => self.mem[a % MEM] = b,
            .shr1 => self.reg[ins.out % R] = a >> 1,
        }
    }
};

fn runProg(setup: ?Instr, step: []const Instr, toks: []const u8, out_buf: []u8) void {
    var m = Machine{};
    if (setup) |s| m.execOne(s);
    for (toks, 0..) |t, i| {
        m.reg[0] = t; // TOK reset each step, like inv_alien's REG_TOK convention
        for (step) |ins| m.execOne(ins);
        out_buf[i] = m.reg[OUT_REG];
    }
}

// =============================================================================
// SECTION 2 -- the four structural priors, each a precise coverage-inclusion
// SIGNATURE: a syntactic (mechanism-blind) predicate over an instruction list,
// exactly in the spirit of `smart_gen.zig`'s `hasRMWShape`. None reference any
// specific target; all four are checkable on ANY candidate program.
// =============================================================================

const Family = enum { rmw, cmp, mod, run };

/// RMW / counting shape (E3's prior): a load addressed by register `r`, and a
/// store ALSO addressed by register `r`, somewhere in the same step body.
fn hasRMWShape(step: []const Instr) bool {
    for (step) |li| {
        if (li.op != .load) continue;
        for (step) |si| {
            if (si.op == .store and si.a == li.a) return true;
        }
    }
    return false;
}

/// Comparison/order shape: a `gt` whose result feeds a LATER instruction (not
/// just written to OUT and left alone -- must be consumed by something else,
/// the "pair-compare-then-aggregate" pattern for order statistics).
fn hasCMPShape(step: []const Instr) bool {
    for (step, 0..) |gi, gi_idx| {
        if (gi.op != .gt) continue;
        for (step[gi_idx + 1 ..]) |later| {
            if (later.a == gi.out or later.b == gi.out or later.c == gi.out) return true;
        }
    }
    return false;
}

/// Modular/residue shape: a `mod3` whose result feeds a later instruction
/// (accumulate-then-mod-then-use, the mixed-radix/residue family's signature).
fn hasMODShape(step: []const Instr) bool {
    for (step, 0..) |mi, mi_idx| {
        if (mi.op != .mod3) continue;
        for (step[mi_idx + 1 ..]) |later| {
            if (later.a == mi.out or later.b == mi.out or later.c == mi.out) return true;
        }
    }
    return false;
}

/// Run/adjacency shape: an `eq` whose result feeds a LATER `sel`'s CONDITION
/// register specifically (the increment-or-reset accumulator pattern).
fn hasRUNShape(step: []const Instr) bool {
    for (step, 0..) |ei, ei_idx| {
        if (ei.op != .eq) continue;
        for (step[ei_idx + 1 ..]) |later| {
            if (later.op == .sel and later.c == ei.out) return true;
        }
    }
    return false;
}

fn matchesPrior(step: []const Instr, fam: Family) bool {
    return switch (fam) {
        .rmw => hasRMWShape(step),
        .cmp => hasCMPShape(step),
        .mod => hasMODShape(step),
        .run => hasRUNShape(step),
    };
}

fn containsOp(step: []const Instr, op: Op) bool {
    for (step) |ins| if (ins.op == op) return true;
    return false;
}

/// A target's shape does not always complete in one instruction (RMW needs an
/// address-computation instruction BEFORE its load;store pair; RUN needs an
/// `eq` several slots before the `sel` that consumes it). A capping scheme
/// that only rewards the FULLY-completed shape starves these longer lineages
/// at the earlier levels where the shape is only half-built (measured: an
/// early version of this file capped on `matchesPrior` alone and silently
/// lost RMW_C/D/E, CMP_B/D, MOD_B/C, and all of RUN_A/B/E -- 13-15 misses out
/// of 20). This widens the coverage-inclusion signature to ALSO prioritize
/// programs carrying the family's characteristic OP even before the full
/// shape is wired up -- still a syntactic, mechanism-blind, per-family
/// signature (not a hint about any specific target), just a level-appropriate
/// one for a variable-length shape.
fn matchesPriorOrPrecursor(step: []const Instr, fam: Family) bool {
    if (matchesPrior(step, fam)) return true;
    return switch (fam) {
        .rmw => containsOp(step, .load) or containsOp(step, .store),
        .cmp => containsOp(step, .gt),
        .mod => containsOp(step, .mod3),
        .run => containsOp(step, .eq) or containsOp(step, .sel),
    };
}

fn familyName(fam: Family) []const u8 {
    return switch (fam) {
        .rmw => "rmw",
        .cmp => "cmp",
        .mod => "mod",
        .run => "run",
    };
}

// =============================================================================
// SECTION 3 -- the 20 targets (5 concrete instances x 4 families). Each is a
// hand-built reference Prog whose TRUE function is used both (a) to generate
// ground-truth output streams for descriptor/agreement computation, and (b)
// as the structural-distinctness comparison point for the genuineness check.
// None of these reference programs are ever fed to the generator/certifier --
// only their (input,output) BEHAVIOUR is used, exactly D5/E3's discipline.
// =============================================================================

const Target = struct { name: []const u8, family: Family, prog: Prog };

fn mkI(op: Op, a: u8, b: u8, c: u8, out: u8) Instr {
    return .{ .op = op, .a = a, .b = b, .c = c, .out = out };
}

fn buildTargets() [20]Target {
    var t: [20]Target = undefined;
    var i: usize = 0;

    // ---- RMW family: read-then-write-same-address (E3's prior) ----
    // A: addr=tok (identity), combine=xor
    t[i] = .{ .name = "RMW_A", .family = .rmw, .prog = .{
        .has_setup = true,
        .setup = mkI(.set1, 0, 0, 0, 1),
        .step = .{ mkI(.load, 0, 0, 0, 2), mkI(.store, 0, 1, 0, 0), mkI(.xor, 2, 1, 0, 4), undefined },
        .step_len = 3,
    } };
    i += 1;
    // B: addr=tok (identity), combine=and
    t[i] = .{ .name = "RMW_B", .family = .rmw, .prog = .{
        .has_setup = true,
        .setup = mkI(.set1, 0, 0, 0, 2),
        .step = .{ mkI(.load, 0, 0, 0, 1), mkI(.store, 0, 2, 0, 0), mkI(.and_, 1, 2, 0, 4), undefined },
        .step_len = 3,
    } };
    i += 1;
    // C: addr=tok%2 (coarse, and-with-1), combine=xor
    t[i] = .{ .name = "RMW_C", .family = .rmw, .prog = .{
        .has_setup = true,
        .setup = mkI(.set1, 0, 0, 0, 1),
        .step = .{ mkI(.and_, 0, 1, 0, 3), mkI(.load, 3, 0, 0, 2), mkI(.store, 3, 1, 0, 0), mkI(.xor, 2, 1, 0, 4) },
        .step_len = 4,
    } };
    i += 1;
    // D: addr=tok>>1 (coarse, div-2), combine=and
    t[i] = .{ .name = "RMW_D", .family = .rmw, .prog = .{
        .has_setup = true,
        .setup = mkI(.set1, 0, 0, 0, 2),
        .step = .{ mkI(.shr1, 0, 0, 0, 3), mkI(.load, 3, 0, 0, 1), mkI(.store, 3, 2, 0, 0), mkI(.and_, 1, 2, 0, 4) },
        .step_len = 4,
    } };
    i += 1;
    // E: addr=tok%2, combine=and
    t[i] = .{ .name = "RMW_E", .family = .rmw, .prog = .{
        .has_setup = true,
        .setup = mkI(.set1, 0, 0, 0, 1),
        .step = .{ mkI(.and_, 0, 1, 0, 3), mkI(.load, 3, 0, 0, 2), mkI(.store, 3, 1, 0, 0), mkI(.and_, 2, 1, 0, 4) },
        .step_len = 4,
    } };
    i += 1;

    // ---- CMP family: pair-compare-then-aggregate (order statistics) ----
    // A: ascending 1-lag (tok > prevTok)
    t[i] = .{ .name = "CMP_A", .family = .cmp, .prog = .{
        .has_setup = false,
        .step = .{ mkI(.gt, 0, 1, 0, 2), mkI(.mov, 0, 0, 0, 1), mkI(.mov, 2, 0, 0, 4), undefined },
        .step_len = 3,
    } };
    i += 1;
    // B: descending 1-lag (prevTok > tok)
    t[i] = .{ .name = "CMP_B", .family = .cmp, .prog = .{
        .has_setup = false,
        .step = .{ mkI(.gt, 1, 0, 0, 2), mkI(.mov, 0, 0, 0, 1), mkI(.mov, 2, 0, 0, 4), undefined },
        .step_len = 3,
    } };
    i += 1;
    // C: running max -- flag = new max reached
    t[i] = .{ .name = "CMP_C", .family = .cmp, .prog = .{
        .has_setup = false,
        .step = .{ mkI(.gt, 0, 1, 0, 2), mkI(.sel, 0, 1, 2, 1), mkI(.mov, 2, 0, 0, 4), undefined },
        .step_len = 3,
    } };
    i += 1;
    // D: running max -- flag = ties the (pre-update) running max
    t[i] = .{ .name = "CMP_D", .family = .cmp, .prog = .{
        .has_setup = false,
        .step = .{ mkI(.eq, 0, 1, 0, 3), mkI(.gt, 0, 1, 0, 2), mkI(.sel, 0, 1, 2, 1), mkI(.mov, 3, 0, 0, 4) },
        .step_len = 4,
    } };
    i += 1;
    // E: running max -- flag = strictly below the (pre-update) running max
    t[i] = .{ .name = "CMP_E", .family = .cmp, .prog = .{
        .has_setup = false,
        .step = .{ mkI(.gt, 1, 0, 0, 3), mkI(.gt, 0, 1, 0, 2), mkI(.sel, 0, 1, 2, 1), mkI(.mov, 3, 0, 0, 4) },
        .step_len = 4,
    } };
    i += 1;

    // ---- MOD family: accumulate-then-mod-then-compare (mixed-radix/residue) ----
    // A: sum accumulation, mod3 > 1 (i.e. == 2)
    t[i] = .{ .name = "MOD_A", .family = .mod, .prog = .{
        .has_setup = true,
        .setup = mkI(.set1, 0, 0, 0, 2),
        .step = .{ mkI(.add, 1, 0, 0, 1), mkI(.mod3, 1, 0, 0, 3), mkI(.gt, 3, 2, 0, 4), undefined },
        .step_len = 3,
    } };
    i += 1;
    // B: sum accumulation, mod3 == 1
    t[i] = .{ .name = "MOD_B", .family = .mod, .prog = .{
        .has_setup = true,
        .setup = mkI(.set1, 0, 0, 0, 2),
        .step = .{ mkI(.add, 1, 0, 0, 1), mkI(.mod3, 1, 0, 0, 3), mkI(.eq, 3, 2, 0, 4), undefined },
        .step_len = 3,
    } };
    i += 1;
    // C: xor accumulation, mod3 > 1
    t[i] = .{ .name = "MOD_C", .family = .mod, .prog = .{
        .has_setup = true,
        .setup = mkI(.set1, 0, 0, 0, 2),
        .step = .{ mkI(.xor, 1, 0, 0, 1), mkI(.mod3, 1, 0, 0, 3), mkI(.gt, 3, 2, 0, 4), undefined },
        .step_len = 3,
    } };
    i += 1;
    // D: xor accumulation, mod3 == 1
    t[i] = .{ .name = "MOD_D", .family = .mod, .prog = .{
        .has_setup = true,
        .setup = mkI(.set1, 0, 0, 0, 2),
        .step = .{ mkI(.xor, 1, 0, 0, 1), mkI(.mod3, 1, 0, 0, 3), mkI(.eq, 3, 2, 0, 4), undefined },
        .step_len = 3,
    } };
    i += 1;
    // E: sum accumulation, mod3 == 0 (no setup needed -- compares against the
    // naturally-zero, never-written register 3)
    t[i] = .{ .name = "MOD_E", .family = .mod, .prog = .{
        .has_setup = false,
        .step = .{ mkI(.add, 1, 0, 0, 1), mkI(.mod3, 1, 0, 0, 2), mkI(.eq, 2, 3, 0, 4), undefined },
        .step_len = 3,
    } };
    i += 1;

    // ---- RUN family: compare-then-conditionally-accumulate-or-reset ----
    // A: run-length of exact repeats of the PREVIOUS token, reset-to-1 on break
    t[i] = .{ .name = "RUN_A", .family = .run, .prog = .{
        .has_setup = true,
        .setup = mkI(.set1, 0, 0, 0, 2),
        .step = .{ mkI(.eq, 0, 1, 0, 3), mkI(.add, 4, 2, 0, 1), mkI(.sel, 1, 2, 3, 4), mkI(.mov, 0, 0, 0, 1) },
        .step_len = 4,
    } };
    i += 1;
    // B: same, reset-to-0 on break ("extra repeats" count)
    t[i] = .{ .name = "RUN_B", .family = .run, .prog = .{
        .has_setup = true,
        .setup = mkI(.set1, 0, 0, 0, 3),
        .step = .{ mkI(.eq, 0, 2, 0, 1), mkI(.add, 4, 3, 0, 2), mkI(.sel, 2, 0, 1, 4), mkI(.mov, 0, 0, 0, 2) },
        .step_len = 4,
    } };
    i += 1;
    // C: run-length of consecutive occurrences of the FIXED value 1, reset-to-1
    t[i] = .{ .name = "RUN_C", .family = .run, .prog = .{
        .has_setup = true,
        .setup = mkI(.set1, 0, 0, 0, 2),
        .step = .{ mkI(.eq, 0, 2, 0, 1), mkI(.add, 4, 2, 0, 3), mkI(.sel, 3, 2, 1, 4), undefined },
        .step_len = 3,
    } };
    i += 1;
    // D: same fixed-value-1 run, reset-to-0
    t[i] = .{ .name = "RUN_D", .family = .run, .prog = .{
        .has_setup = true,
        .setup = mkI(.set1, 0, 0, 0, 2),
        .step = .{ mkI(.eq, 0, 2, 0, 1), mkI(.add, 4, 2, 0, 3), mkI(.sel, 3, 0, 1, 4), undefined },
        .step_len = 3,
    } };
    i += 1;
    // E: sticky run counter that never resets (records longest run reached so far)
    t[i] = .{ .name = "RUN_E", .family = .run, .prog = .{
        .has_setup = true,
        .setup = mkI(.set1, 0, 0, 0, 2),
        .step = .{ mkI(.eq, 0, 1, 0, 3), mkI(.add, 4, 2, 0, 1), mkI(.sel, 1, 4, 3, 4), mkI(.mov, 0, 0, 0, 1) },
        .step_len = 4,
    } };
    i += 1;

    std.debug.assert(i == 20);
    return t;
}

// =============================================================================
// SECTION 4 -- COVER: exhaustive small-program enumeration over the full
// alphabet (all 5 registers used as operand fields, R^4 combos per op), levels
// 1..MAX_STEP, deduplicated by FULL-machine-state fingerprint. At any level
// whose kept set exceeds COVER_BASE_CAP, the base carried into the NEXT level
// is selected either by a PRIOR's coverage-inclusion signature (shape-matching
// programs first, fairness inclusion) or, for the `none` ablation, by a fixed-
// seed uniform random sample -- the direct generalization of `smart_gen.zig`'s
// single (RMW-only) `--l3=uniform` toggle to four selectable priors.
// =============================================================================

const COVER_BASE_CAP: usize = 2400;

fn shuffleIdx(idxs: []usize, seed: u64) void {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var i = idxs.len;
    while (i > 1) {
        i -= 1;
        const j = rng.uintLessThan(usize, i + 1);
        const tmp = idxs[i];
        idxs[i] = idxs[j];
        idxs[j] = tmp;
    }
}

fn stateFingerprint(setup: ?Instr, step: []const Instr, seed: u64) u64 {
    var h: u64 = seed;
    const n_variants: usize = 3; // 0 = fresh-zero memory; 1,2 = pre-seeded (D5/E3's wrinkle)
    var vi: usize = 0;
    while (vi < n_variants) : (vi += 1) {
        var prng = std.Random.DefaultPrng.init(seed +% @as(u64, vi) *% 0x9E3779B97F4A7C15);
        const rng = prng.random();
        var m = Machine{};
        if (vi > 0) {
            for (&m.mem) |*c| c.* = @intCast(rng.uintLessThan(usize, MEM));
        }
        if (setup) |s| m.execOne(s);
        const L: usize = 6;
        for (0..L) |_| {
            const tk: u8 = @intCast(rng.uintLessThan(usize, V));
            m.reg[0] = tk;
            for (step) |ins| m.execOne(ins);
            for (m.reg) |rv| h = std.hash.Wyhash.hash(h, std.mem.asBytes(&rv));
            for (m.mem) |cv| h = std.hash.Wyhash.hash(h, std.mem.asBytes(&cv));
        }
    }
    return h;
}

fn extendLevel(al: std.mem.Allocator, base: []const Prog, seed: u64) ![]Prog {
    var seen = std.AutoHashMap(u64, void).init(al);
    defer seen.deinit();
    var kept = std.ArrayList(Prog).init(al);
    const n_ops = Op.count();
    for (base) |bp| {
        if (bp.step_len >= MAX_STEP) continue;
        var op_i: usize = 0;
        while (op_i < n_ops) : (op_i += 1) {
            const op: Op = @enumFromInt(op_i);
            for (0..R) |a| {
                for (0..R) |b| {
                    for (0..R) |c| {
                        for (0..R) |o| {
                            var np = bp;
                            np.step[np.step_len] = .{ .op = op, .a = @intCast(a), .b = @intCast(b), .c = @intCast(c), .out = @intCast(o) };
                            np.step_len += 1;
                            const fp = stateFingerprint(np.setupOpt(), np.stepSlice(), seed);
                            const gp = try seen.getOrPut(fp);
                            if (!gp.found_existing) try kept.append(np);
                        }
                    }
                }
            }
        }
    }
    return kept.toOwnedSlice();
}

/// Cap `base` down to `cap` entries, shape-first under `prior` (fairness
/// inclusion) or uniformly-at-random when `prior == null` (the `none`
/// ablation -- coverage with NO structural steering at all). Both the
/// shape-matching bucket AND the remainder are independently SHUFFLED (fixed
/// seed) before truncation -- a plain "first N in raw enumeration order"
/// prefix was measured to systematically starve whichever lineage happens to
/// enumerate late (an early version of this file had exactly that bug: it
/// silently dropped several targets whose shape only completes a few
/// instructions into a longer program). Shuffling gives every member of each
/// bucket an equal chance of surviving the cap, independent of enumeration
/// position.
fn selectBase(al: std.mem.Allocator, base: []const Prog, prior: ?Family, cap: usize, seed: u64) ![]Prog {
    if (base.len <= cap) {
        const out = try al.alloc(Prog, base.len);
        @memcpy(out, base);
        return out;
    }
    var matched = std.ArrayList(usize).init(al);
    defer matched.deinit();
    var rest = std.ArrayList(usize).init(al);
    defer rest.deinit();
    for (base, 0..) |p, idx| {
        if (prior != null and matchesPriorOrPrecursor(p.stepSlice(), prior.?)) {
            try matched.append(idx);
        } else {
            try rest.append(idx);
        }
    }
    shuffleIdx(matched.items, seed);
    shuffleIdx(rest.items, seed +% 0x9E3779B9);

    var out = std.ArrayList(Prog).init(al);
    for (matched.items) |idx| {
        if (out.items.len >= cap) break;
        try out.append(base[idx]);
    }
    for (rest.items) |idx| {
        if (out.items.len >= cap) break;
        try out.append(base[idx]);
    }
    return out.toOwnedSlice();
}

const CoverPool = struct {
    progs: []Prog,
    n_kept: [MAX_STEP]usize,
    n_base_capped: [MAX_STEP]bool,
};

/// `prior = null` builds the `none` ablation pool (uniform-random base
/// selection whenever a level exceeds the cap -- no structural steering).
fn buildCoverPool(al: std.mem.Allocator, prior: ?Family) !CoverPool {
    const seed: u64 = 0xC0FFEE;
    var lvl0 = std.ArrayList(Prog).init(al);
    try lvl0.append(.{}); // no setup
    for (1..R) |ridx| {
        try lvl0.append(.{ .has_setup = true, .setup = mkI(.set1, 0, 0, 0, @intCast(ridx)) });
    }
    const level0 = try lvl0.toOwnedSlice();

    var pool = std.ArrayList(Prog).init(al);
    var n_kept: [MAX_STEP]usize = undefined;
    var n_capped: [MAX_STEP]bool = undefined;
    var cur_base: []Prog = level0;
    var lvl: usize = 0;
    while (lvl < MAX_STEP) : (lvl += 1) {
        const capped = cur_base.len > COVER_BASE_CAP;
        n_capped[lvl] = capped;
        const base_for_ext = try selectBase(al, cur_base, prior, COVER_BASE_CAP, seed +% lvl);
        if (cur_base.ptr != level0.ptr) al.free(cur_base);
        const kept = try extendLevel(al, base_for_ext, seed +% (1000 + lvl));
        al.free(base_for_ext);
        n_kept[lvl] = kept.len;
        for (kept) |p| try pool.append(p);
        cur_base = kept;
    }
    al.free(cur_base);
    al.free(level0);
    return .{ .progs = try pool.toOwnedSlice(), .n_kept = n_kept, .n_base_capped = n_capped };
}

// =============================================================================
// SECTION 5 -- behavioural matching. Every one of the 20 hand targets emits a
// BINARY (0/1) output stream, so exact agreement over a modest random stream
// is, for all practical purposes, a certificate of functional identity (the
// chance of two genuinely different deterministic functions matching on 64
// i.i.d. random bits is 2^-64) -- this licenses a fast canonical-stream HASH
// bucket per pool instead of an O(pool_size) agreement scan per target.
// =============================================================================

const CANON_SEED: u64 = 0xCA4001;
const CANON_L: usize = 64;

fn canonHash(setup: ?Instr, step: []const Instr) u64 {
    var prng = std.Random.DefaultPrng.init(CANON_SEED);
    const rng = prng.random();
    var toks: [CANON_L]u8 = undefined;
    for (&toks) |*tk| tk.* = @intCast(rng.uintLessThan(usize, V));
    var outp: [CANON_L]u8 = undefined;
    runProg(setup, step, &toks, &outp);
    return std.hash.Wyhash.hash(0, &outp);
}

const MATCH_N: usize = 200;
const MATCH_L: usize = 16;
const MATCH_THRESHOLD: f64 = 0.97;

fn agreement(setupA: ?Instr, stepA: []const Instr, setupB: ?Instr, stepB: []const Instr, seed: u64) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var agree: usize = 0;
    var total: usize = 0;
    var toks: [MATCH_L]u8 = undefined;
    var outA: [MATCH_L]u8 = undefined;
    var outB: [MATCH_L]u8 = undefined;
    for (0..MATCH_N) |_| {
        for (&toks) |*tk| tk.* = @intCast(rng.uintLessThan(usize, V));
        runProg(setupA, stepA, &toks, &outA);
        runProg(setupB, stepB, &toks, &outB);
        for (0..MATCH_L) |k| {
            total += 1;
            if (outA[k] == outB[k]) agree += 1;
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total));
}

const PoolIndex = struct {
    map: std.AutoHashMap(u64, usize), // canonHash -> pool index (first seen)
    pool: []const Prog,

    fn build(al: std.mem.Allocator, pool: []const Prog) !PoolIndex {
        var map = std.AutoHashMap(u64, usize).init(al);
        for (pool, 0..) |p, idx| {
            const h = canonHash(p.setupOpt(), p.stepSlice());
            const gp = try map.getOrPut(h);
            if (!gp.found_existing) gp.value_ptr.* = idx;
        }
        return .{ .map = map, .pool = pool };
    }
};

const FoundResult = struct { found: bool, idx: usize = 0, agree: f64 = 0 };

fn lookupTarget(idx: *const PoolIndex, target: *const Prog, seed: u64) FoundResult {
    const h = canonHash(target.setupOpt(), target.stepSlice());
    const cand_idx = idx.map.get(h) orelse return .{ .found = false };
    const cand = idx.pool[cand_idx];
    const ag = agreement(cand.setupOpt(), cand.stepSlice(), target.setupOpt(), target.stepSlice(), seed);
    return .{ .found = ag >= MATCH_THRESHOLD, .idx = cand_idx, .agree = ag };
}

/// Structural distinctness: candidate's instruction list differs from the
/// target's own reference encoding (field-by-field) -- evidence of genuine
/// independent rediscovery rather than a trivial copy (E3's r2-vs-r6 check).
fn structurallyDistinct(cand: *const Prog, target: *const Prog) bool {
    if (cand.has_setup != target.has_setup) return true;
    if (cand.has_setup and !std.meta.eql(cand.setup, target.setup)) return true;
    if (cand.step_len != target.step_len) return true;
    for (0..cand.step_len) |k| {
        if (!std.meta.eql(cand.step[k], target.step[k])) return true;
    }
    return false;
}

/// "Clean": no strict prefix (any length 1..len-1) of the candidate already
/// reaches the match threshold against the target -- every instruction is
/// load-bearing. The scaled-down analogue of the round's "clean at depth 4"
/// gate (this substrate's stones cap at length 4, so the natural minimality
/// check is prefix-irreducibility rather than a separate +1-depth re-search).
fn isClean(cand: *const Prog, target: *const Prog, seed: u64) bool {
    if (cand.step_len <= 1) return true;
    for (1..cand.step_len) |plen| {
        const ag = agreement(cand.setupOpt(), cand.step[0..plen], target.setupOpt(), target.stepSlice(), seed);
        if (ag >= MATCH_THRESHOLD) return false;
    }
    return true;
}

// =============================================================================
// SECTION 6 -- the failure descriptor: 6 features computed WITHOUT knowing
// the target's family, from generic canonical partial-mechanism probes (the
// same spirit as `target_router.zig`'s d1..d10 near-miss statistics) plus two
// base-rate diagnostics. Sign-invariant (max(agree,1-agree)) so a target whose
// true mechanism is a complement of the probe (e.g. RMW_A's xor vs RMW_B's
// and) still registers as informative.
// =============================================================================

const N_FEAT: usize = 6;
const DESC_N: usize = 400;
const DESC_SEED: u64 = 0x0DE5C0DE;

fn signInv(p: f64) f64 {
    return @max(p, 1 - p);
}

fn computeDescriptor(setup: ?Instr, step: []const Instr) [N_FEAT]f64 {
    var prng = std.Random.DefaultPrng.init(DESC_SEED);
    const rng = prng.random();
    var toks: [DESC_N]u8 = undefined;
    for (&toks) |*tk| tk.* = @intCast(rng.uintLessThan(usize, V));
    var outp: [DESC_N]u8 = undefined;
    runProg(setup, step, &toks, &outp);

    var agree_rmw: usize = 0;
    var agree_cmp: usize = 0;
    var agree_run: usize = 0;
    var agree_base: usize = 0;
    var agree_mod: [3]usize = .{ 0, 0, 0 };
    var ones: usize = 0;
    var runsum: usize = 0;

    for (0..DESC_N) |pos| {
        const tok = toks[pos];
        const out = outp[pos];
        ones += out;

        var seen = false;
        for (0..pos) |j| {
            if (toks[j] == tok) {
                seen = true;
                break;
            }
        }
        if ((if (seen) @as(u8, 1) else 0) == out) agree_rmw += 1;

        const prev: u8 = if (pos == 0) 0 else toks[pos - 1];
        const ascend: u8 = if (tok > prev) 1 else 0;
        if (ascend == out) agree_cmp += 1;
        const eqprev: u8 = if (tok == prev) 1 else 0;
        if (eqprev == out) agree_run += 1;
        const baseflag: u8 = if (tok >= V / 2) 1 else 0;
        if (baseflag == out) agree_base += 1;

        runsum += tok;
        const modv = runsum % 3;
        for (0..3) |r| {
            const flag: u8 = if (modv == r) 1 else 0;
            if (flag == out) agree_mod[r] += 1;
        }
    }

    const n_f: f64 = @floatFromInt(DESC_N);
    var best_mod: f64 = 0;
    for (0..3) |r| {
        const p = signInv(@as(f64, @floatFromInt(agree_mod[r])) / n_f);
        if (p > best_mod) best_mod = p;
    }
    const mean_out = @as(f64, @floatFromInt(ones)) / n_f;

    return .{
        signInv(@as(f64, @floatFromInt(agree_rmw)) / n_f),
        signInv(@as(f64, @floatFromInt(agree_cmp)) / n_f),
        best_mod,
        signInv(@as(f64, @floatFromInt(agree_run)) / n_f),
        signInv(@as(f64, @floatFromInt(agree_base)) / n_f),
        @abs(mean_out - 0.5),
    };
}

// =============================================================================
// SECTION 7 -- k-NN prior-selector over standardized descriptors, trained on
// (target, empirically-true-family) pairs, evaluated on held-out targets.
// Directly reuses `target_router.zig`'s design (k-NN on standardized features,
// k chosen by leave-one-out on the fit pool, refit on fit+val, scored once).
// =============================================================================

const Standardizer = struct {
    mean: [N_FEAT]f64,
    sd: [N_FEAT]f64,

    fn fit(rows: []const [N_FEAT]f64) Standardizer {
        var mean: [N_FEAT]f64 = .{0} ** N_FEAT;
        for (rows) |r| for (0..N_FEAT) |f| {
            mean[f] += r[f];
        };
        const n: f64 = @floatFromInt(rows.len);
        for (0..N_FEAT) |f| mean[f] /= n;
        var sd: [N_FEAT]f64 = .{0} ** N_FEAT;
        for (rows) |r| for (0..N_FEAT) |f| {
            const d = r[f] - mean[f];
            sd[f] += d * d;
        };
        for (0..N_FEAT) |f| {
            sd[f] = @sqrt(sd[f] / n);
            if (sd[f] < 1e-9) sd[f] = 1.0;
        }
        return .{ .mean = mean, .sd = sd };
    }

    fn apply(self: *const Standardizer, row: [N_FEAT]f64) [N_FEAT]f64 {
        var out: [N_FEAT]f64 = undefined;
        for (0..N_FEAT) |f| out[f] = (row[f] - self.mean[f]) / self.sd[f];
        return out;
    }
};

fn sqDist(a: [N_FEAT]f64, b: [N_FEAT]f64) f64 {
    var s: f64 = 0;
    for (0..N_FEAT) |f| {
        const d = a[f] - b[f];
        s += d * d;
    }
    return s;
}

fn knnPredict(query: [N_FEAT]f64, fit_x: []const [N_FEAT]f64, fit_y: []const Family, k: usize) Family {
    var dist_buf: [64]f64 = undefined;
    var idx_buf: [64]usize = undefined;
    const n = fit_x.len;
    for (0..n) |ii| {
        dist_buf[ii] = sqDist(query, fit_x[ii]);
        idx_buf[ii] = ii;
    }
    // partial selection sort for the k smallest
    const kk = @min(k, n);
    for (0..kk) |ii| {
        var mi = ii;
        for (ii + 1..n) |jj| if (dist_buf[jj] < dist_buf[mi]) {
            mi = jj;
        };
        std.mem.swap(f64, &dist_buf[ii], &dist_buf[mi]);
        std.mem.swap(usize, &idx_buf[ii], &idx_buf[mi]);
    }
    var counts = [_]usize{0} ** 4;
    for (0..kk) |ii| counts[@intFromEnum(fit_y[idx_buf[ii]])] += 1;
    var best: usize = 0;
    for (1..4) |f| if (counts[f] > counts[best]) {
        best = f;
    };
    // tie-break: nearest single neighbor
    if (kk > 1) {
        var tie = false;
        for (0..4) |f| if (f != best and counts[f] == counts[best]) {
            tie = true;
        };
        if (tie) best = @intFromEnum(fit_y[idx_buf[0]]);
    }
    return @enumFromInt(best);
}

// =============================================================================
// SECTION 8 -- main experiment: build pools, empirically label true families,
// compute descriptors, split train/val/test, run leakage guard, fit selector,
// run the 3 arms on TEST, verify genuineness+clean on every success, emit CSV.
// =============================================================================

const CSV_HEADER = "phase,target,family,arm,predicted,evals,success,agree,genuine,clean\n";

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

const N_TARGETS: usize = 20;
const FAMILIES = [_]Family{ .rmw, .cmp, .mod, .run };

fn runSelftest(al: std.mem.Allocator, out: anytype) !void {
    const targets = buildTargets();

    try out.print("[selftest] built {d} targets across 4 families\n", .{N_TARGETS});

    // 1. instrument fidelity: each family's own predicate fires on its own targets,
    //    and never fires on the other 3 families' targets.
    var pred_ok = true;
    for (targets) |tg| {
        const s = tg.prog.stepSlice();
        const has = [4]bool{ hasRMWShape(s), hasCMPShape(s), hasMODShape(s), hasRUNShape(s) };
        const own_idx: usize = switch (tg.family) {
            .rmw => 0,
            .cmp => 1,
            .mod => 2,
            .run => 3,
        };
        if (!has[own_idx]) {
            try out.print("[selftest] FAIL: {s} does not trigger its own family predicate\n", .{tg.name});
            pred_ok = false;
        }
        for (0..4) |f| {
            if (f != own_idx and has[f]) {
                try out.print("[selftest] NOTE: {s} (family {s}) also triggers predicate {d} (incidental overlap)\n", .{ tg.name, familyName(tg.family), f });
            }
        }
    }
    try out.print("[selftest] own-predicate fidelity: {s}\n", .{if (pred_ok) "PASS" else "FAIL"});

    // 2. non-degeneracy + pairwise distinctness: no target constant, no two
    //    targets behaviourally identical (agreement ~1.0 or ~0.0 both flagged).
    var rates: [N_TARGETS]f64 = undefined;
    for (targets, 0..) |tg, ti| {
        var prng = std.Random.DefaultPrng.init(0x51DE + ti);
        const rng = prng.random();
        var toks: [200]u8 = undefined;
        for (&toks) |*tk| tk.* = @intCast(rng.uintLessThan(usize, V));
        var outp: [200]u8 = undefined;
        runProg(tg.prog.setupOpt(), tg.prog.stepSlice(), &toks, &outp);
        var ones: usize = 0;
        for (outp) |o| ones += o;
        rates[ti] = @as(f64, @floatFromInt(ones)) / 200.0;
        if (rates[ti] < 0.02 or rates[ti] > 0.98) {
            try out.print("[selftest] WARNING: {s} looks degenerate (rate={d:.3})\n", .{ tg.name, rates[ti] });
        }
    }
    var dup_found = false;
    for (0..N_TARGETS) |ai| {
        for (ai + 1..N_TARGETS) |bi| {
            const ag = agreement(targets[ai].prog.setupOpt(), targets[ai].prog.stepSlice(), targets[bi].prog.setupOpt(), targets[bi].prog.stepSlice(), 0x9999);
            if (ag > 0.995 or ag < 0.005) {
                try out.print("[selftest] DUPLICATE/complement risk: {s} vs {s} agree={d:.4}\n", .{ targets[ai].name, targets[bi].name, ag });
                dup_found = true;
            }
        }
    }
    try out.print("[selftest] pairwise exact-duplicate scan: {s}\n", .{if (dup_found) "FOUND (see above)" else "clean"});

    // 3. COVER pool sizes + own-family recall: build all 5 pools once, verify
    //    every target is found in its OWN family's pool (sanity: the substrate
    //    can express every hand stone given the matching prior).
    var pools: [5]CoverPool = undefined;
    const prior_opts = [_]?Family{ .rmw, .cmp, .mod, .run, null };
    for (prior_opts, 0..) |po, pi| {
        pools[pi] = try buildCoverPool(al, po);
        const nm: []const u8 = if (po) |f| familyName(f) else "none";
        try out.print("[selftest] pool[{s}] size={d} per-level kept={any} capped={any}\n", .{ nm, pools[pi].progs.len, pools[pi].n_kept, pools[pi].n_base_capped });
    }
    var idxs: [5]PoolIndex = undefined;
    for (0..5) |pi| idxs[pi] = try PoolIndex.build(al, pools[pi].progs);

    var own_hits: usize = 0;
    for (targets) |tg| {
        const own_idx: usize = switch (tg.family) {
            .rmw => 0,
            .cmp => 1,
            .mod => 2,
            .run => 3,
        };
        const r = lookupTarget(&idxs[own_idx], &tg.prog, 0x1234);
        if (r.found) own_hits += 1 else try out.print("[selftest] MISS: {s} not found in its own family's pool\n", .{tg.name});
    }
    try out.print("[selftest] own-family recall: {d}/{d}\n", .{ own_hits, N_TARGETS });

    var none_hits: usize = 0;
    for (targets) |tg| {
        const r = lookupTarget(&idxs[4], &tg.prog, 0x1234);
        if (r.found) none_hits += 1;
    }
    try out.print("[selftest] `none` (no-prior) ablation recall: {d}/{d} (expect low -- this is the control)\n", .{ none_hits, N_TARGETS });
}

const Split = struct { train: [12]usize, val: [4]usize, tst: [4]usize };

fn buildSplit() Split {
    // per-family layout in buildTargets(): indices 0-4=rmw,5-9=cmp,10-14=mod,15-19=run
    // within each family: [0,1,2]=train [3]=val [4]=test
    var sp: Split = undefined;
    var ti: usize = 0;
    var vi: usize = 0;
    var si: usize = 0;
    for (0..4) |fam| {
        const base = fam * 5;
        sp.train[ti] = base + 0;
        ti += 1;
        sp.train[ti] = base + 1;
        ti += 1;
        sp.train[ti] = base + 2;
        ti += 1;
        sp.val[vi] = base + 3;
        vi += 1;
        sp.tst[si] = base + 4;
        si += 1;
    }
    return sp;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const al = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(al);
    defer std.process.argsFree(al, args);
    if (args.len < 2) {
        try out.writeAll("usage: prior_selector selftest | run <csv>\n");
        return;
    }
    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "selftest")) {
        try runSelftest(al, out);
        return;
    }

    if (std.mem.eql(u8, cmd, "run")) {
        if (args.len < 3) {
            try out.writeAll("usage: prior_selector run <csv>\n");
            return;
        }
        const csv = try openCsv(args[2]);
        defer csv.close();
        const cw = csv.writer();

        const targets = buildTargets();

        // 1. build all 5 pools once (4 real priors + `none` ablation).
        var pools: [5]CoverPool = undefined;
        const prior_opts = [_]?Family{ .rmw, .cmp, .mod, .run, null };
        for (prior_opts, 0..) |po, pi| pools[pi] = try buildCoverPool(al, po);
        var idxs: [5]PoolIndex = undefined;
        for (0..5) |pi| idxs[pi] = try PoolIndex.build(al, pools[pi].progs);
        try out.print("[run] pool sizes: rmw={d} cmp={d} mod={d} run={d} none={d}\n", .{ pools[0].progs.len, pools[1].progs.len, pools[2].progs.len, pools[3].progs.len, pools[4].progs.len });

        // 2. empirically determine the TRUE family for every target: which of
        //    the 4 real-prior pools actually certifies it (fixed precedence
        //    rmw>cmp>mod>run on ties, though by design ties are not expected).
        var true_family: [N_TARGETS]?Family = .{null} ** N_TARGETS;
        var certifies: [N_TARGETS][4]bool = undefined;
        for (targets, 0..) |tg, ti| {
            for (0..4) |pi| {
                const r = lookupTarget(&idxs[pi], &tg.prog, 0xABCD);
                certifies[ti][pi] = r.found;
            }
            for (0..4) |pi| {
                if (certifies[ti][pi]) {
                    true_family[ti] = FAMILIES[pi];
                    break;
                }
            }
            try out.print("[run] {s} (constructed family={s}) certifies-under: rmw={} cmp={} mod={} run={}\n", .{ tg.name, familyName(tg.family), certifies[ti][0], certifies[ti][1], certifies[ti][2], certifies[ti][3] });
        }

        // 3. descriptors for every target.
        var desc: [N_TARGETS][N_FEAT]f64 = undefined;
        for (targets, 0..) |tg, ti| desc[ti] = computeDescriptor(tg.prog.setupOpt(), tg.prog.stepSlice());

        // 4. split.
        const split = buildSplit();

        // 5. leakage guard: standardize on TRAIN, compute min TRAIN<->TEST
        //    distance; flag anything suspiciously close.
        var train_rows: [12][N_FEAT]f64 = undefined;
        for (split.train, 0..) |idx, k| train_rows[k] = desc[idx];
        const std_train = Standardizer.fit(&train_rows);
        var min_leak_dist: f64 = std.math.inf(f64);
        for (split.tst) |te_idx| {
            const q = std_train.apply(desc[te_idx]);
            for (split.train) |tr_idx| {
                const d = sqDist(q, std_train.apply(desc[tr_idx]));
                if (d < min_leak_dist) min_leak_dist = d;
            }
        }
        try out.print("[run] leakage guard: min standardized TRAIN<->TEST sq-dist = {d:.4} (warn threshold 0.05)\n", .{min_leak_dist});
        const leak_flag = min_leak_dist < 0.05;
        try out.print("[run] leakage guard verdict: {s}\n", .{if (leak_flag) "WARNING -- possible leak" else "clean"});

        // 6. fit pool = train+val (16 targets); choose k by leave-one-out over
        //    the fit pool; refit on the full fit pool; score once on TEST.
        var fit_idx_buf: [16]usize = undefined;
        for (split.train, 0..) |idx, k| fit_idx_buf[k] = idx;
        for (split.val, 0..) |idx, k| fit_idx_buf[12 + k] = idx;
        const std_fit = Standardizer.fit(blk: {
            var rows: [16][N_FEAT]f64 = undefined;
            for (fit_idx_buf, 0..) |idx, k| rows[k] = desc[idx];
            break :blk &rows;
        });
        var fit_x: [16][N_FEAT]f64 = undefined;
        var fit_y: [16]Family = undefined;
        for (fit_idx_buf, 0..) |idx, k| {
            fit_x[k] = std_fit.apply(desc[idx]);
            fit_y[k] = true_family[idx] orelse .rmw; // should never be null; see selftest
        }

        var best_k: usize = 3;
        var best_loo: f64 = -1;
        for ([_]usize{ 1, 3, 5 }) |k_try| {
            var correct: usize = 0;
            for (0..16) |leave_out| {
                var loo_x: [15][N_FEAT]f64 = undefined;
                var loo_y: [15]Family = undefined;
                var w: usize = 0;
                for (0..16) |k| {
                    if (k == leave_out) continue;
                    loo_x[w] = fit_x[k];
                    loo_y[w] = fit_y[k];
                    w += 1;
                }
                const pred = knnPredict(fit_x[leave_out], &loo_x, &loo_y, k_try);
                if (pred == fit_y[leave_out]) correct += 1;
            }
            const acc = @as(f64, @floatFromInt(correct)) / 16.0;
            try out.print("[run] LOO accuracy k={d}: {d:.3}\n", .{ k_try, acc });
            if (acc > best_loo) {
                best_loo = acc;
                best_k = k_try;
            }
        }
        try out.print("[run] selected k={d} (LOO acc {d:.3})\n", .{ best_k, best_loo });

        // 7. fixed-best-prior (arm B): whichever single family certifies the
        //    most targets in the fit pool (train+val), applied uniformly.
        var fam_hits: [4]usize = .{0} ** 4;
        for (fit_idx_buf) |idx| {
            for (0..4) |pi| if (certifies[idx][pi]) {
                fam_hits[pi] += 1;
            };
        }
        var fixed_best: Family = .rmw;
        var fixed_best_n: usize = 0;
        for (0..4) |pi| if (fam_hits[pi] > fixed_best_n) {
            fixed_best_n = fam_hits[pi];
            fixed_best = FAMILIES[pi];
        };
        try out.print("[run] fixed-best-prior on fit pool: {s} ({d}/16 targets certify under it)\n", .{ familyName(fixed_best), fixed_best_n });

        // 8. the 3 arms on the 4 TEST targets.
        var prng_rand = std.Random.DefaultPrng.init(0x2A2A2026_0711_0000);
        const rng_rand = prng_rand.random();

        var a_solves: usize = 0;
        var b_solves: usize = 0;
        var c_solves: usize = 0;
        var a_evals: usize = 0;
        var b_evals: usize = 0;
        var c_evals: usize = 0;

        try out.print("\n[HEADLINE] 3 arms on {d} held-out TEST targets:\n", .{split.tst.len});
        for (split.tst) |te_idx| {
            const tg = targets[te_idx];
            const q = std_fit.apply(desc[te_idx]);
            const pred_a = knnPredict(q, &fit_x, &fit_y, best_k);
            const pred_b = fixed_best;
            const pred_c = FAMILIES[rng_rand.uintLessThan(usize, 4)];

            const pi_a: usize = @intFromEnum(pred_a);
            const pi_b: usize = @intFromEnum(pred_b);
            const pi_c: usize = @intFromEnum(pred_c);

            const ok_a = certifies[te_idx][pi_a];
            const ok_b = certifies[te_idx][pi_b];
            const ok_c = certifies[te_idx][pi_c];

            if (ok_a) a_solves += 1;
            if (ok_b) b_solves += 1;
            if (ok_c) c_solves += 1;
            a_evals += pools[pi_a].progs.len;
            b_evals += pools[pi_b].progs.len;
            c_evals += pools[pi_c].progs.len;

            try out.print("  {s} (true={s}): router->{s}({s}) fixed->{s}({s}) random->{s}({s})\n", .{
                tg.name,               familyName(tg.family),
                familyName(pred_a),    if (ok_a) "HIT" else "miss",
                familyName(pred_b),    if (ok_b) "HIT" else "miss",
                familyName(pred_c),    if (ok_c) "HIT" else "miss",
            });

            // genuineness + clean, for every arm's HIT (report on the router's
            // pick primarily; also check fixed/random when they hit).
            inline for (.{ .{ "router", pi_a, ok_a }, .{ "fixed", pi_b, ok_b }, .{ "random", pi_c, ok_c } }) |arm| {
                const arm_name = arm[0];
                const pidx = arm[1];
                const hit = arm[2];
                var genuine = false;
                var clean = false;
                var agree_val: f64 = 0;
                if (hit) {
                    const r = lookupTarget(&idxs[pidx], &tg.prog, 0xF00D);
                    agree_val = r.agree;
                    const cand = pools[pidx].progs[r.idx];
                    genuine = structurallyDistinct(&cand, &tg.prog);
                    clean = isClean(&cand, &tg.prog, 0xF00D);
                }
                try cw.print("test,{s},{s},{s},{s},{d},{s},{d:.4},{s},{s}\n", .{
                    tg.name,
                    familyName(tg.family),
                    arm_name,
                    familyName(FAMILIES[pidx]),
                    pools[pidx].progs.len,
                    if (hit) "1" else "0",
                    agree_val,
                    if (hit and genuine) "yes" else if (hit) "no" else "n/a",
                    if (hit and clean) "yes" else if (hit) "no" else "n/a",
                });
            }
        }

        try out.print("\n[HEADLINE] solves/4: router={d} fixed-best={d} random={d}\n", .{ a_solves, b_solves, c_solves });
        try out.print("[HEADLINE] evals(sum over 4 targets): router={d} fixed-best={d} random={d}\n", .{ a_evals, b_evals, c_evals });
        try out.print("[HEADLINE] leakage guard: {s} (min dist^2={d:.4})\n", .{ if (leak_flag) "WARNING" else "clean", min_leak_dist });

        // also log a summary row + the split/LOO curve to CSV for the record.
        try cw.print("summary,-,-,router,-,{d},{d},-,-,-\n", .{ a_evals, a_solves });
        try cw.print("summary,-,-,fixed_best,-,{d},{d},-,-,-\n", .{ b_evals, b_solves });
        try cw.print("summary,-,-,random,-,{d},{d},-,-,-\n", .{ c_evals, c_solves });
        try cw.print("summary,-,-,leakage_min_dist2,-,-,-,{d:.4},-,-\n", .{min_leak_dist});
        try cw.print("summary,-,-,loo_best_k,-,{d},-,{d:.4},-,-\n", .{ best_k, best_loo });
        return;
    }

    try out.writeAll("unknown command\n");
}
