//! Tax gate as PROMOTION gate — A/B/C compounding experiment (2026-07-10).
//!
//! Question: the strict equivalence tax currently only MEASURES which promotions
//! are remix. Does making tax-survival a PROMOTION CONDITION help or hurt when
//! later targets can benefit from earlier promotions?
//!
//! Arms (identical ladder, identical targets, identical seeds protocol):
//!   A gated   — strict tax ON, v4 reality lane OFF: remix-verdict candidates are
//!               NOT promoted (and cannot solve via the promoting ladder rung).
//!   B current — strict tax ON, v4 reality lane ON: every certified candidate
//!               promotes; tax verdict is measured only (shipped default).
//!   C none    — no library carryover: library reset to the trained monomial
//!               forge before EVERY target (within-target promotion allowed by
//!               the ladder, then discarded).
//!
//! Two-phase battery per seed:
//!   Phase 1 = battery B (B1..B11, fixed order, battery seed 0xE1B10D20A11CE01).
//!   Phase 2 = 8 designed follow-up targets: 4 repeats (need phase-1 promotions),
//!             1 composition reusing the two known tax-SURVIVORS (sum%7, parity),
//!             3 fresh controls no arm has seen.
//!
//! Budget: all arms attempt the same 19 targets with the same ladder; evals are
//! counted with rq1.EvalCounter and reported per arm (cost side of the gate).
//!
//! Threads: main + 1 worker (big stack for equivalence_tax greedyFit). ≤2 total.
//!
//! Build: zig build-exe tier8_tax_gate_ab.zig -O ReleaseFast
//! Run:   ./tier8_tax_gate_ab [--csv=PATH]   (default results/taxgate_ab_2026_07_10.csv)

const std = @import("std");
const ie = @import("invention_engine.zig");
const rq1 = @import("open_invention_rq1.zig");
const ui = @import("unified_invention.zig");
const eqtax = @import("equivalence_tax.zig");

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

const SEEDS = [_]u64{
    0xF0235A11CE0FF1CE, // canonical grid seed (all prior Tier-8 runs)
    0x1CEB00DA20260710,
    0xBADC0FFEE0DDF00D,
};

const Arm = enum {
    gated,
    current,
    none,

    fn name(self: Arm) []const u8 {
        return switch (self) {
            .gated => "A_gated",
            .current => "B_current",
            .none => "C_no_promotion",
        };
    }
};

const N_P2 = 8;

fn makePhase2(b1_mask: u8, b2_mask: u8) [N_P2]rq1.BatteryTarget {
    return .{
        // Repeats: solvable instantly IF the phase-1 promotion survived into the library.
        .{ .name = "P1 repeat Walsh chi{0x11}", .kind = .walsh_subset, .walsh_s = 0x11 },
        .{ .name = "P2 repeat Walsh chi{0xA4}", .kind = .walsh_subset, .walsh_s = 0xA4 },
        .{ .name = "P3 repeat sum%7", .kind = .sum_mod, .modulus = 7 },
        .{ .name = "P5 repeat monomial deg2", .kind = .random_monomial, .mask = b1_mask },
        // Composition: linearly separable from {parity feature, sum%7 feature} —
        // both were tax-SURVIVORS in the 2026-07-10 baseline. Direct compounding probe.
        .{ .name = "P4 compose parity AND sum%7", .kind = .composed_parity_and_sum, .sum_mod = 7 },
        // Fresh controls: no phase-1 promotion targets these directly.
        .{ .name = "P6 fresh Walsh chi{0x51}", .kind = .walsh_subset, .walsh_s = 0x51 },
        .{ .name = "P7 fresh monomial deg3", .kind = .random_monomial, .mask = b2_mask ^ 0x21 },
        .{ .name = "P8 fresh parity AND sum%3", .kind = .composed_parity_and_sum, .sum_mod = 3 },
    };
}

const PhaseStats = struct {
    solved: usize = 0,
    targets: usize = 0,
    lib_hits: usize = 0, // solved instantly from library coverage ("frozen/grown monomials")
    evals: usize = 0,
    tax_checked: usize = 0,
    tax_blocked: usize = 0,
    verdict_novel: usize = 0, // witnessRemix verdicts (measured in arms A and B)
    verdict_remix: usize = 0,
};

const ArmSeedResult = struct {
    arm: Arm,
    seed: u64,
    p1: PhaseStats = .{},
    p2: PhaseStats = .{},
    nlib_trained: usize = 0,
    nlib_final: usize = 0,
    transient_promos: usize = 0, // arm C: promotions made within a target then discarded
    overflow_warn: bool = false,
};

fn armSetup(arm: Arm) void {
    switch (arm) {
        .gated => {
            eqtax.strict_enabled = true;
            eqtax.reality_lane_enabled = false;
        },
        .current => {
            eqtax.strict_enabled = true;
            eqtax.reality_lane_enabled = true;
        },
        .none => {
            eqtax.strict_enabled = false;
            eqtax.reality_lane_enabled = true;
        },
    }
    eqtax.resetStats();
    eqtax.resetTaxLog();
    eqtax.resetReplay();
}

fn armRestoreDefaults() void {
    eqtax.strict_enabled = false;
    eqtax.reality_lane_enabled = true;
}

fn runArm(
    arm: Arm,
    seed: u64,
    ctx: *ie.BlindBatteryCtx,
    trained: []const ui.Feature,
    phase2: []const rq1.BatteryTarget,
    Yb: []f64,
    csv: anytype,
    out: anytype,
) !ArmSeedResult {
    armSetup(arm);
    defer armRestoreDefaults();

    var res = ArmSeedResult{ .arm = arm, .seed = seed, .nlib_trained = trained.len };

    var lib: [32]ui.Feature = undefined;
    var nlib: usize = trained.len;
    @memcpy(lib[0..trained.len], trained);

    var budget = rq1.EvalCounter{};

    try out.print("  arm {s}\n", .{arm.name()});

    for (0..2) |phase_i| {
        const targets: []const rq1.BatteryTarget = if (phase_i == 0) ctx.battery else phase2;
        var ps = PhaseStats{ .targets = targets.len };
        const evals0 = budget.total();
        const checked0 = eqtax.stats.checked;
        const blocked0 = eqtax.stats.remix_blocked;
        const log0 = eqtax.tax_log_n;

        for (targets) |tgt| {
            if (arm == .none) {
                @memcpy(lib[0..trained.len], trained);
                nlib = trained.len;
            }
            for (0..rq1.NSAMP) |s| Yb[s] = rq1.labelBattery(ctx.grid[s], tgt);
            const r = try ie.solveBlindTarget(
                ctx.X,
                ctx.grid,
                &lib,
                &nlib,
                Yb,
                ctx.phiTgt,
                ctx.w[0..],
                tgt,
                ctx.bank,
                &ctx.S_store,
                ctx.pf,
                ctx.feat,
                &budget,
                SilentOut{},
                true,
            );
            const lib_hit = r.solved and std.mem.eql(u8, r.label, "frozen/grown monomials");
            if (r.solved) ps.solved += 1;
            if (lib_hit) ps.lib_hits += 1;
            if (arm == .none and nlib > trained.len) res.transient_promos += nlib - trained.len;
            if (nlib >= 30) res.overflow_warn = true;
            try out.print("    P{d} {s}: {s}{s} cov={d:.3} nlib={d}\n", .{
                phase_i + 1,
                tgt.name,
                if (r.solved) "SOLVED" else "saturated",
                if (lib_hit) " [library hit]" else "",
                r.cov,
                nlib,
            });
            try csv.print("0x{X:0>16},{s},{d},\"{s}\",{d},{d},\"{s}\",{d:.4},{d},{d},{d},{d}\n", .{
                seed,
                arm.name(),
                phase_i + 1,
                tgt.name,
                @intFromBool(r.solved),
                @intFromBool(lib_hit),
                r.label,
                r.cov,
                nlib,
                eqtax.stats.checked,
                eqtax.stats.remix_blocked,
                budget.total(),
            });
        }

        ps.evals = budget.total() - evals0;
        ps.tax_checked = eqtax.stats.checked - checked0;
        ps.tax_blocked = eqtax.stats.remix_blocked - blocked0;
        for (log0..eqtax.tax_log_n) |i| {
            if (eqtax.tax_log[i].verdict == .novel) ps.verdict_novel += 1 else ps.verdict_remix += 1;
        }
        if (phase_i == 0) res.p1 = ps else res.p2 = ps;
    }

    res.nlib_final = nlib;
    return res;
}

fn run() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var csv_path: []const u8 = "results/taxgate_ab_2026_07_10.csv";
    var seed_filter: ?usize = null; // --seed=N runs only SEEDS[N] (keeps each run ≤15 min)
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--csv=")) csv_path = arg["--csv=".len..];
        if (std.mem.startsWith(u8, arg, "--seed=")) seed_filter = try std.fmt.parseInt(usize, arg["--seed=".len..], 10);
    }

    var csv_buf = std.ArrayList(u8).init(alloc);
    const csv = csv_buf.writer();
    try csv.print("seed,arm,phase,target,solved,lib_hit,label,cov,nlib_after,tax_checked_cum,tax_blocked_cum,evals_cum\n", .{});

    try out.print("=== Tax gate as promotion gate — A/B/C compounding experiment ===\n", .{});
    try out.print("basis v{d} | battery seed 0x{X:0>16} | {d} grid seeds | 19 targets/arm (11 + 8)\n\n", .{
        eqtax.BASIS_VERSION,
        ie.BATTERY_SEED,
        SEEDS.len,
    });

    var results: [SEEDS.len][3]ArmSeedResult = undefined;
    var ran: [SEEDS.len]bool = .{false} ** SEEDS.len;
    const Yb = try alloc.alloc(f64, rq1.NSAMP);

    for (SEEDS, 0..) |seed, si| {
        if (seed_filter) |sf| {
            if (sf != si) continue;
        }
        ran[si] = true;
        try out.print("── seed 0x{X:0>16} ──\n", .{seed});
        var prep = try ie.prepareBlindBatterySeed(alloc, seed, SilentOut{});
        // Copy the trained forge library immediately (prep.trained_lib slice lifetime).
        var trained: [32]ui.Feature = undefined;
        var ntrained: usize = 0;
        ie.seedUiFromRq1(prep.trained_lib, &trained, &ntrained);

        var b2_mask: u8 = 0;
        for (prep.ctx.battery) |t| {
            if (std.mem.eql(u8, t.name, "B2 random monomial deg3")) b2_mask = t.mask;
        }
        const phase2 = makePhase2(prep.ctx.battery[0].mask, b2_mask);

        for ([_]Arm{ .gated, .current, .none }, 0..) |arm, ai| {
            results[si][ai] = try runArm(arm, seed, &prep.ctx, trained[0..ntrained], phase2[0..], Yb, csv, out);
        }
        try out.print("\n", .{});
    }

    // ── Summary tables ─────────────────────────────────────────────────────────
    try out.print("═══════════════════════ SUMMARY (per arm, per seed) ═══════════════════════\n", .{});
    try out.print("{s:<16} {s:<18} | {s:>5} {s:>5} | {s:>7} | {s:>7} {s:>7} | {s:>5} {s:>5} | {s:>8}\n", .{
        "seed", "arm", "P1", "P2", "P2 hit", "checked", "blocked", "novel", "remix", "evals",
    });
    try csv.print("# summary: seed,arm,p1_solved,p2_solved,p2_lib_hits,tax_checked,tax_blocked,verdict_novel,verdict_remix,kept_promotions,transient_promotions,nlib_final,evals_total\n", .{});
    for (SEEDS, 0..) |seed, si| {
        if (!ran[si]) continue;
        for (results[si]) |r| {
            const checked = r.p1.tax_checked + r.p2.tax_checked;
            const blocked = r.p1.tax_blocked + r.p2.tax_blocked;
            const novel = r.p1.verdict_novel + r.p2.verdict_novel;
            const remix = r.p1.verdict_remix + r.p2.verdict_remix;
            const evals = r.p1.evals + r.p2.evals;
            const kept = if (r.arm == .none) 0 else r.nlib_final - r.nlib_trained;
            try out.print("{X:0>16} {s:<18} | {d:>2}/{d:<2} {d:>2}/{d:<2} | {d:>7} | {d:>7} {d:>7} | {d:>5} {d:>5} | {d:>8}\n", .{
                seed,           r.arm.name(),
                r.p1.solved,    r.p1.targets,
                r.p2.solved,    r.p2.targets,
                r.p2.lib_hits,  checked,
                blocked,        novel,
                remix,          evals,
            });
            try csv.print("# 0x{X:0>16},{s},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d}\n", .{
                seed,   r.arm.name(),
                r.p1.solved, r.p2.solved,
                r.p2.lib_hits, checked,
                blocked, novel,
                remix,  kept,
                r.transient_promos, r.nlib_final,
                evals,
            });
            if (r.overflow_warn) try out.print("  WARNING: library approached capacity (nlib>=30) — inspect\n", .{});
        }
    }

    // Aggregate across seeds.
    var n_ran: usize = 0;
    for (ran) |x| {
        if (x) n_ran += 1;
    }
    try out.print("\n─── Aggregate across {d} seed(s) ───\n", .{n_ran});
    for (0..3) |ai| {
        var p1s: usize = 0;
        var p2s: usize = 0;
        var hits: usize = 0;
        var evals: usize = 0;
        var blocked: usize = 0;
        var kept: usize = 0;
        for (0..SEEDS.len) |si| {
            if (!ran[si]) continue;
            const r = results[si][ai];
            p1s += r.p1.solved;
            p2s += r.p2.solved;
            hits += r.p2.lib_hits;
            evals += r.p1.evals + r.p2.evals;
            blocked += r.p1.tax_blocked + r.p2.tax_blocked;
            if (r.arm != .none) kept += r.nlib_final - r.nlib_trained;
        }
        const arm: Arm = @enumFromInt(ai);
        try out.print("  {s:<16} P1 {d:>2}/{d}  P2 {d:>2}/{d}  P2-library-hits {d:>2}  kept-promos {d:>2}  blocked {d:>2}  evals {d}\n", .{
            arm.name(),
            p1s,
            11 * n_ran,
            p2s,
            N_P2 * n_ran,
            hits,
            kept,
            blocked,
            evals,
        });
    }

    // Write CSV.
    if (std.fs.path.dirname(csv_path)) |dir| std.fs.cwd().makePath(dir) catch {};
    const f = try std.fs.cwd().createFile(csv_path, .{ .truncate = true });
    defer f.close();
    try f.writeAll(csv_buf.items);
    try out.print("\nCSV written: {s}\n", .{csv_path});
}

pub fn main() !void {
    // equivalence_tax greedyFit uses ~32 MB of stack; run on a dedicated big-stack
    // worker so the binary works under the default 8 MB rlimit. 2 threads total.
    const t = try std.Thread.spawn(.{ .stack_size = 512 * 1024 * 1024 }, runWrapped, .{});
    t.join();
}

fn runWrapped() void {
    run() catch |e| {
        std.debug.print("FATAL: {s}\n", .{@errorName(e)});
        std.process.exit(1);
    };
}
