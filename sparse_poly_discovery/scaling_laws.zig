//! H50–H52 scaling-law harness — yield curves for the production invention engine.
//!
//! Sweeps a hard eval-budget cap across a log-spaced ladder x >=3 seed pairs and
//! runs the standard blind battery B (invention_engine.zig ladder) under the
//! strict equivalence tax (v4 basis). Records, per (cap, seed):
//!   solves, evals actually consumed, promotions checked, strict-witness novel
//!   count (verdict==novel from the tax log), v4-lane survivors, remix-blocked,
//!   final library size, prep wall-seconds, battery wall-seconds.
//! Plus per-target rows: evals consumed by that target, solved flag, source.
//!
//! Budget unit — IMPORTANT, be honest about this:
//!   One "eval" is the engine's own EvalCounter unit (fit / certify / probe
//!   events at ladder-stage granularity), the same unit printed as
//!   "battery evals" by invention_engine.zig. It is NOT one raw sample-label
//!   evaluation; each unit internally evaluates up to a few hundred candidate
//!   features over NSAMP=7000 samples. The cap is enforced at ladder-stage
//!   boundaries (4 gates per target), so a stage that has already started may
//!   overshoot the cap; the CSV records evals ACTUALLY consumed, which is the
//!   honest x-axis. Wall-clock CPU seconds are recorded as the second,
//!   fully-measured cost axis.
//!
//! No existing file is modified: prepareBlindBatterySeed and solveBlindTarget
//! are ported here (battery seed parameterized; budget gates added).
//!
//! Build:  zig build-exe scaling_laws.zig -O ReleaseFast
//! Run:    ./scaling_laws [--seed=N] [--no-header]   (CSV on stdout, log on stderr)
//! Single-threaded; each per-seed invocation completes in a few minutes.

const std = @import("std");
const rq1 = @import("open_invention_rq1.zig");
const ui = @import("unified_invention.zig");
const eqtax = @import("equivalence_tax.zig");
const engine = @import("invention_engine.zig");

const EvalCounter = rq1.EvalCounter;
const COVER = rq1.COVER;

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

const SeedPair = struct { grid: u64, battery: u64 };

/// Seed 0 is the canonical production pair (same as invention_engine.zig).
const SEEDS = [_]SeedPair{
    .{ .grid = rq1.GRID_SEED, .battery = rq1.BATTERY_SEED },
    .{ .grid = 0xA5A5A5A5DEADBEEF, .battery = 0x1234567890ABCDEF },
    .{ .grid = 0xC0FFEE1234567890, .battery = 0xFACEB00CDEADF00D },
    .{ .grid = 0x9E3779B97F4A7C15, .battery = 0x243F6A8885A308D3 },
};

/// Log-spaced (x2) cap ladder in engine eval units, straddling the observed
/// full-battery consumption (~372 units on the canonical seed). 1536 is
/// effectively uncapped and demonstrates saturation. Denser in the 6..96 knee
/// because a single mod/pipeline escalation stage consumes ~265 units at once
/// (ProgBank is 256 programs, probed in one stage), so caps 96..1536 all land
/// on the same consumed-evals point — that IS the saturation finding.
const CAPS = [_]usize{ 6, 12, 24, 48, 96, 384, 1536 };

/// Port of invention_engine.prepareBlindBatterySeed with the battery seed
/// parameterized (the original hardcodes rq1.BATTERY_SEED).
fn prepareSeeded(
    alloc: std.mem.Allocator,
    grid_seed: u64,
    battery_seed: u64,
) !engine.BlindBatteryPrep {
    var prng = std.Random.DefaultPrng.init(grid_seed);
    const rand = prng.random();

    const grid = try alloc.alloc([8]u8, rq1.NSAMP);
    for (0..rq1.NSAMP) |s| {
        for (0..8) |i| grid[s][i] = rand.intRangeAtMost(u8, 0, 5);
    }

    const X = try alloc.alloc([]f64, rq1.NSAMP);
    const phiTgt = try alloc.alloc(f64, rq1.NSAMP);
    for (0..rq1.NSAMP) |s| X[s] = try alloc.alloc(f64, 32);
    var w_store: [33]f64 = undefined;

    const Yzoo = try alloc.alloc([]f64, 4);
    const zoo_masks = [_]u8{
        (1 << 2) | (1 << 5),
        (1 << 1) | (1 << 3) | (1 << 6),
        (1 << 0) | (1 << 4) | (1 << 5) | (1 << 7),
        (1 << 3),
    };
    for (0..4) |t| {
        Yzoo[t] = try alloc.alloc(f64, rq1.NSAMP);
        for (0..rq1.NSAMP) |s| {
            var p: f64 = 1.0;
            for (0..8) |i| {
                if (zoo_masks[t] & (@as(u8, 1) << @intCast(i)) != 0)
                    p *= (@as(f64, @floatFromInt(grid[s][i])) - 2.5);
            }
            Yzoo[t][s] = if (p > 0) 1.0 else 0.0;
        }
    }

    const trained = try rq1.trainZooA(X, grid, Yzoo, phiTgt, &w_store, SilentOut{});
    const bank = try rq1.buildProgBank(alloc);
    const S_store = try rq1.buildInner1Store(alloc, grid);
    const pf = try alloc.alloc([]f64, rq1.NSAMP);
    for (0..rq1.NSAMP) |s| pf[s] = try alloc.alloc(f64, 3);
    const feat = try alloc.alloc(f64, rq1.NSAMP);

    var bprng = std.Random.DefaultPrng.init(battery_seed);
    const battery = try rq1.generateBatteryB(bprng.random(), alloc);

    return .{
        .ctx = .{
            .grid = grid,
            .X = X,
            .phiTgt = phiTgt,
            .w = w_store,
            .bank = bank,
            .S_store = S_store,
            .pf = pf,
            .feat = feat,
            .battery = battery,
        },
        .trained_lib = trained.lib[0..trained.nlib],
        .trained_nlib = trained.nlib,
    };
}

/// Port of invention_engine.solveBlindTarget with a hard budget cap enforced
/// before each ladder stage (base check, unified escalation, mod/pipeline,
/// pair/Walsh). Stages already started may overshoot; consumption is recorded.
fn solveBlindTargetCapped(
    X: [][]f64,
    grid: []const [8]u8,
    lib: []ui.Feature,
    nlib: *usize,
    Y: []const f64,
    phiTgt: []f64,
    w: []f64,
    tgt: rq1.BatteryTarget,
    bank: rq1.ProgBank,
    S_store: *const [rq1.N_INNER1][]f64,
    pf: []const []f64,
    feat: []f64,
    budget: *EvalCounter,
    cap: usize,
) !engine.BlindSolveResult {
    if (budget.total() >= cap) {
        return .{ .solved = false, .cov = 0, .source = .base, .label = "budget-exhausted" };
    }

    budget.fit += 1;
    const cov0 = ui.measureCoverage(X, grid, lib[0..nlib.*], Y, w);
    if (cov0 >= COVER) {
        return .{ .solved = true, .cov = cov0, .source = .base, .label = "frozen/grown monomials" };
    }

    if (budget.total() >= cap) {
        return .{ .solved = false, .cov = cov0, .source = .base, .label = "budget-exhausted" };
    }
    const m = ui.solveOneTarget(X, grid, lib, nlib, Y, phiTgt, w, SilentOut{}, true);
    budget.certify += m.iters_to_certify;
    budget.probe += 2;
    if (m.solved) {
        return .{ .solved = true, .cov = m.cov, .source = m.source, .label = "unified escalation" };
    }

    if (rq1.needsMod(tgt.kind) and budget.total() < cap) {
        var rq_frozen: [32]rq1.Feature = undefined;
        for (0..nlib.*) |i| rq_frozen[i] = .{ .monomial = lib[i].monomial };
        if (try rq1.tryModEscalation(X, grid, rq_frozen[0..nlib.*], Y, bank, S_store, w, cov0, tgt, SilentOut{}, budget)) |ev| {
            if (ev.certified) {
                return .{ .solved = true, .cov = ev.test_acc, .source = .menu, .label = "mod/pipeline" };
            }
        }
    }

    if (budget.total() < cap) {
        var rq_frozen2: [32]rq1.Feature = undefined;
        for (0..nlib.*) |i| rq_frozen2[i] = .{ .monomial = lib[i].monomial };
        if (try rq1.tryPairWalshEscalation(grid, rq_frozen2[0..nlib.*], Y, pf, feat, w, cov0, tgt, SilentOut{}, budget)) |ev| {
            if (ev.certified) {
                const src: ui.Source = switch (ev.method) {
                    .pair_router => .pair,
                    .walsh_corr => .walsh,
                    else => .menu,
                };
                return .{ .solved = true, .cov = ev.test_acc, .source = src, .label = "pair/walsh" };
            }
        }
    }

    return .{ .solved = false, .cov = m.cov, .source = .base, .label = "saturated" };
}

/// Process CPU seconds (user+sys) via getrusage — robust to machine load,
/// unlike wall clock. This is the denominator for invention-per-CPU-second.
fn cpuSeconds() f64 {
    const ru = std.posix.getrusage(std.posix.rusage.SELF);
    const u = @as(f64, @floatFromInt(ru.utime.sec)) + @as(f64, @floatFromInt(ru.utime.usec)) / 1e6;
    const s = @as(f64, @floatFromInt(ru.stime.sec)) + @as(f64, @floatFromInt(ru.stime.usec)) / 1e6;
    return u + s;
}

const TargetRow = struct {
    kind: rq1.BatteryKind,
    solved: bool,
    source: ui.Source,
    evals: usize,
};

const RunResult = struct {
    solves: usize,
    total: usize,
    evals: usize,
    promos_checked: usize,
    novel_strict: usize,
    survivors_v4: usize,
    remix_blocked: usize,
    final_nlib: usize,
    prep_sec: f64,
    battery_sec: f64,
    prep_cpu_sec: f64,
    battery_cpu_sec: f64,
    targets: [16]TargetRow,
    n_targets: usize,
};

fn runOnce(alloc: std.mem.Allocator, seed: SeedPair, cap: usize) !RunResult {
    var timer = try std.time.Timer.start();
    const cpu0 = cpuSeconds();
    var prep = try prepareSeeded(alloc, seed.grid, seed.battery);
    const prep_sec = @as(f64, @floatFromInt(timer.read())) / 1e9;
    const prep_cpu_sec = cpuSeconds() - cpu0;

    // Strict tax on; reset all global tax state AFTER prep so only battery-phase
    // promotions are counted (prep never touches eqtax — rq1 has no dependency).
    eqtax.strict_enabled = true;
    eqtax.resetStats();
    eqtax.resetTaxLog();
    eqtax.resetReplay();

    var lib: [32]ui.Feature = undefined;
    var nlib: usize = 0;
    engine.seedUiFromRq1(prep.trained_lib, &lib, &nlib);

    var budget = EvalCounter{};
    var result: RunResult = undefined;
    result.n_targets = 0;
    result.prep_sec = prep_sec;
    result.prep_cpu_sec = prep_cpu_sec;

    timer.reset();
    const cpu1 = cpuSeconds();
    var solved: usize = 0;
    const ctx = &prep.ctx;
    for (ctx.battery) |tgt| {
        const Yb = try alloc.alloc(f64, rq1.NSAMP);
        defer alloc.free(Yb);
        for (0..rq1.NSAMP) |s| Yb[s] = rq1.labelBattery(ctx.grid[s], tgt);
        const evals_before = budget.total();
        const r = try solveBlindTargetCapped(
            ctx.X, ctx.grid, &lib, &nlib, Yb, ctx.phiTgt, ctx.w[0..], tgt,
            ctx.bank, &ctx.S_store, ctx.pf, ctx.feat, &budget, cap,
        );
        if (r.solved) solved += 1;
        if (result.n_targets < result.targets.len) {
            result.targets[result.n_targets] = .{
                .kind = tgt.kind,
                .solved = r.solved,
                .source = r.source,
                .evals = budget.total() - evals_before,
            };
            result.n_targets += 1;
        }
    }
    result.battery_sec = @as(f64, @floatFromInt(timer.read())) / 1e9;
    result.battery_cpu_sec = cpuSeconds() - cpu1;

    var novel_strict: usize = 0;
    for (eqtax.tax_log[0..eqtax.tax_log_n]) |entry| {
        if (entry.verdict == .novel) novel_strict += 1;
    }

    result.solves = solved;
    result.total = ctx.battery.len;
    result.evals = budget.total();
    result.promos_checked = eqtax.stats.checked;
    result.novel_strict = novel_strict;
    result.survivors_v4 = eqtax.stats.novel_allowed;
    result.remix_blocked = eqtax.stats.remix_blocked;
    result.final_nlib = nlib;
    return result;
}

pub fn main() !void {
    var only_seed: ?usize = null;
    var header = true;
    var args = std.process.args();
    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--seed=")) {
            only_seed = try std.fmt.parseInt(usize, arg["--seed=".len..], 10);
        } else if (std.mem.eql(u8, arg, "--no-header")) {
            header = false;
        }
    }

    // The strict-tax witness (equivalence_tax.greedyFit) places a ~31 MB
    // col_store on the stack; the default 8 MB main stack segfaults (the
    // stock invention_engine --strict-tax binary does too). Run the sweep
    // on one worker thread with a 256 MB stack. Total threads: 2 (main idle).
    const t = try std.Thread.spawn(
        .{ .stack_size = 256 * 1024 * 1024 },
        sweep,
        .{ only_seed, header },
    );
    t.join();
}

fn sweep(only_seed: ?usize, header: bool) !void {
    const out = std.io.getStdOut().writer();
    const err = std.io.getStdErr().writer();

    if (header) {
        try out.print("row,cap,seed_idx,grid_seed,battery_seed,target_idx,target_kind,target_solved,target_source,solves,total,evals_consumed,promos_checked,novel_strict,survivors_v4,remix_blocked,final_nlib,prep_sec,battery_sec,prep_cpu_sec,battery_cpu_sec\n", .{});
    }

    for (SEEDS, 0..) |seed, si| {
        if (only_seed) |o| {
            if (si != o) continue;
        }
        for (CAPS) |cap| {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const r = try runOnce(arena.allocator(), seed, cap);

            try out.print("run,{d},{d},0x{X:0>16},0x{X:0>16},,,,,{d},{d},{d},{d},{d},{d},{d},{d},{d:.3},{d:.3},{d:.3},{d:.3}\n", .{
                cap, si, seed.grid, seed.battery,
                r.solves, r.total, r.evals,
                r.promos_checked, r.novel_strict, r.survivors_v4, r.remix_blocked,
                r.final_nlib, r.prep_sec, r.battery_sec, r.prep_cpu_sec, r.battery_cpu_sec,
            });
            for (r.targets[0..r.n_targets], 0..) |t, ti| {
                try out.print("target,{d},{d},0x{X:0>16},0x{X:0>16},{d},{s},{d},{s},,,{d},,,,,,,,,\n", .{
                    cap, si, seed.grid, seed.battery,
                    ti, @tagName(t.kind),
                    @as(u8, if (t.solved) 1 else 0), @tagName(t.source),
                    t.evals,
                });
            }
            try err.print("[seed {d} cap {d:>5}] solves {d}/{d}  evals {d}  novel_strict {d}  survivors_v4 {d}  blocked {d}  prep {d:.1}s battery {d:.1}s cpu {d:.1}s\n", .{
                si, cap, r.solves, r.total, r.evals,
                r.novel_strict, r.survivors_v4, r.remix_blocked,
                r.prep_sec, r.battery_sec, r.battery_cpu_sec,
            });
        }
    }
}
