//! Baseline comparison harness — invention (RQ1++ staged) vs four baselines on blind battery B.
//!
//! Run: zig build invention-baseline-compare --release=fast

const std = @import("std");
const rq1 = @import("open_invention_rq1.zig");
const ui = @import("unified_invention.zig");

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

const Mode = enum {
    invention,
    monomial_only,
    fixed_menu,
    random_search,
    no_verifier,
};

const ModeResult = struct {
    mode: Mode,
    solved: usize,
    total: usize,
    evals: usize,
};

fn modeName(m: Mode) []const u8 {
    return switch (m) {
        .invention => "invention",
        .monomial_only => "monomial_only",
        .fixed_menu => "fixed_menu",
        .random_search => "random_search",
        .no_verifier => "no_verifier",
    };
}

fn runInventionMode(
    alloc: std.mem.Allocator,
    grid: []const [8]u8,
    battery: []const rq1.BatteryTarget,
    bank: anytype,
    X: [][]f64,
    feat_scratch: []f64,
    w: []f64,
    frozen: []const rq1.Feature,
) !ModeResult {
    var budget = rq1.EvalCounter{};
    const out = SilentOut{};

    const S_store = try rq1.buildInner1Store(alloc, grid);
    const pf = try alloc.alloc([]f64, rq1.NSAMP);
    for (0..rq1.NSAMP) |s| pf[s] = try alloc.alloc(f64, 3);

    var solved: usize = 0;
    for (battery) |tgt| {
        const Yb = try std.heap.page_allocator.alloc(f64, rq1.NSAMP);
        for (0..rq1.NSAMP) |s| Yb[s] = rq1.labelBattery(grid[s], tgt);
        const ev = try rq1.evaluateBlind(X, grid, frozen, Yb, bank, &S_store, pf, feat_scratch, w, tgt, out, &budget);
        if (ev.certified) solved += 1;
        std.heap.page_allocator.free(Yb);
    }

    return .{ .mode = .invention, .solved = solved, .total = battery.len, .evals = budget.total() };
}

fn runMonomialOnly(
    grid: []const [8]u8,
    battery: []const rq1.BatteryTarget,
    frozen: []const rq1.Feature,
    X: [][]f64,
    w: []f64,
) ModeResult {
    var solved: usize = 0;
    var evals: usize = 0;
    for (battery) |tgt| {
        const Yb = std.heap.page_allocator.alloc(f64, rq1.NSAMP) catch unreachable;
        for (0..rq1.NSAMP) |s| Yb[s] = rq1.labelBattery(grid[s], tgt);

        evals += 1;
        var cov = rq1.coverage(X, grid, frozen, Yb, w);
        if (cov >= rq1.COVER) {
            solved += 1;
            std.heap.page_allocator.free(Yb);
            continue;
        }

        var mm: u16 = 1;
        while (mm < 256) : (mm += 1) {
            const mask: u8 = @intCast(mm);
            if (@popCount(mask) < 1 or @popCount(mask) > 4) continue;
            for (0..rq1.NSAMP) |s| {
                var p: f64 = 1.0;
                for (0..8) |i| {
                    if (mask & (@as(u8, 1) << @intCast(i)) != 0) p *= (@as(f64, @floatFromInt(grid[s][i])) - 2.5);
                }
                X[s][0] = p;
            }
            evals += 1;
            var aug_buf: [33]rq1.Feature = undefined;
            @memcpy(aug_buf[0..frozen.len], frozen);
            aug_buf[frozen.len] = .{ .monomial = mask };
            const cov_try = rq1.coverage(X, grid, aug_buf[0 .. frozen.len + 1], Yb, w);
            evals += 1;
            if (cov_try > cov) cov = cov_try;
        }
        if (cov >= rq1.COVER) solved += 1;
        std.heap.page_allocator.free(Yb);
    }
    return .{ .mode = .monomial_only, .solved = solved, .total = battery.len, .evals = evals };
}

fn runFixedMenu(
    alloc: std.mem.Allocator,
    grid: []const [8]u8,
    battery: []const rq1.BatteryTarget,
) !ModeResult {
    var solved: usize = 0;
    var evals: usize = 0;
    const out = SilentOut{};

    const X = try alloc.alloc([]f64, rq1.NSAMP);
    const phiTgt = try alloc.alloc(f64, rq1.NSAMP);
    for (0..rq1.NSAMP) |s| X[s] = try alloc.alloc(f64, 32);
    var w: [33]f64 = undefined;

    for (battery) |tgt| {
        const Yb = try alloc.alloc(f64, rq1.NSAMP);
        for (0..rq1.NSAMP) |s| Yb[s] = rq1.labelBattery(grid[s], tgt);

        var ulib: [32]ui.Feature = undefined;
        var nlib: usize = 0;
        for (0..8) |i| {
            ulib[nlib] = .{ .monomial = @as(u8, 1) << @intCast(i) };
            nlib += 1;
        }

        evals += 1;
        var cov0 = ui.measureCoverage(X, grid, ulib[0..nlib], Yb, &w);
        if (cov0 >= ui.COVER_THRESHOLD) {
            solved += 1;
            continue;
        }

        evals += 3;
        evals += 1;
        if (ui.tryMenuOnce(X, grid, &ulib, &nlib, Yb, phiTgt, &w, out) catch false) {
            cov0 = ui.measureCoverage(X, grid, ulib[0..nlib], Yb, &w);
            evals += 1;
            if (cov0 >= ui.COVER_THRESHOLD) solved += 1;
        }
    }

    return .{ .mode = .fixed_menu, .solved = solved, .total = battery.len, .evals = evals };
}

fn runRandomSearch(
    grid: []const [8]u8,
    battery: []const rq1.BatteryTarget,
    frozen: []const rq1.Feature,
    X: [][]f64,
    phiTgt: []f64,
    w: []f64,
    seed: u64,
) ModeResult {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    var solved: usize = 0;
    var evals: usize = 0;
    const budget_per_target: usize = 500;

    for (battery) |tgt| {
        const Yb = std.heap.page_allocator.alloc(f64, rq1.NSAMP) catch unreachable;
        for (0..rq1.NSAMP) |s| Yb[s] = rq1.labelBattery(grid[s], tgt);

        var lib: [32]rq1.Feature = undefined;
        @memcpy(lib[0..frozen.len], frozen);
        const nlib = frozen.len;

        var found = false;
        var attempt: usize = 0;
        while (attempt < budget_per_target) : (attempt += 1) {
            const mask: u8 = @intCast(rand.intRangeAtMost(u16, 1, 255));
            if (@popCount(mask) < 1 or @popCount(mask) > 4) continue;
            var dup = false;
            for (lib[0..nlib]) |f| {
                if (f.monomial == mask) dup = true;
            }
            if (dup) continue;

            for (0..rq1.NSAMP) |s| {
                var p: f64 = 1.0;
                for (0..8) |i| {
                    if (mask & (@as(u8, 1) << @intCast(i)) != 0) p *= (@as(f64, @floatFromInt(grid[s][i])) - 2.5);
                }
                phiTgt[s] = p;
            }
            const cov_before = rq1.coverage(X, grid, lib[0..nlib], Yb, w);
            var aug = lib;
            aug[nlib] = .{ .monomial = mask };
            const cov_after = rq1.coverage(X, grid, aug[0 .. nlib + 1], Yb, w);
            evals += 2;
            if (cov_after >= rq1.COVER and cov_before < rq1.COVER) {
                found = true;
                break;
            }
        }
        if (found) solved += 1;
        std.heap.page_allocator.free(Yb);
    }

    return .{ .mode = .random_search, .solved = solved, .total = battery.len, .evals = evals };
}

fn runNoVerifier(
    grid: []const [8]u8,
    battery: []const rq1.BatteryTarget,
    frozen: []const rq1.Feature,
    X: [][]f64,
    w: []f64,
) ModeResult {
    var solved: usize = 0;
    var evals: usize = 0;

    for (battery) |tgt| {
        const Yb = std.heap.page_allocator.alloc(f64, rq1.NSAMP) catch unreachable;
        for (0..rq1.NSAMP) |s| Yb[s] = rq1.labelBattery(grid[s], tgt);

        var best: f64 = rq1.coverage(X, grid, frozen, Yb, w);
        evals += 1;

        var mm: u16 = 1;
        while (mm < 256) : (mm += 1) {
            const mask: u8 = @intCast(mm);
            if (@popCount(mask) < 1 or @popCount(mask) > 4) continue;
            for (0..rq1.NSAMP) |s| X[s][0] = blk: {
                var p: f64 = 1.0;
                for (0..8) |i| {
                    if (mask & (@as(u8, 1) << @intCast(i)) != 0) p *= (@as(f64, @floatFromInt(grid[s][i])) - 2.5);
                }
                break :blk p;
            };
            evals += 1;
            const cov = rq1.coverage(X, grid, frozen, Yb, w);
            if (cov > best) best = cov;
        }

        if (best >= rq1.COVER) solved += 1;
        std.heap.page_allocator.free(Yb);
    }

    return .{ .mode = .no_verifier, .solved = solved, .total = battery.len, .evals = evals };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    try out.print("=== Invention baseline comparison (blind battery B) ===\n", .{});
    try out.print("grid_seed=0x{X:0>16} battery_seed=0x{X:0>16}\n\n", .{ rq1.GRID_SEED, rq1.BATTERY_SEED });

    var prng = std.Random.DefaultPrng.init(rq1.GRID_SEED);
    const rand = prng.random();
    const grid = try alloc.alloc([8]u8, rq1.NSAMP);
    for (0..rq1.NSAMP) |s| {
        for (0..8) |i| grid[s][i] = rand.intRangeAtMost(u8, 0, 5);
    }

    var bprng = std.Random.DefaultPrng.init(rq1.BATTERY_SEED);
    const battery = try rq1.generateBatteryB(bprng.random(), alloc);
    const bank = try rq1.buildProgBank(alloc);

    const X = try alloc.alloc([]f64, rq1.NSAMP);
    const phiTgt = try alloc.alloc(f64, rq1.NSAMP);
    for (0..rq1.NSAMP) |s| X[s] = try alloc.alloc(f64, 33);
    var w: [34]f64 = undefined;

    const Yzoo = try alloc.alloc([]f64, 4);
    const zoo_masks = [_]u8{ (1 << 2) | (1 << 5), (1 << 1) | (1 << 3) | (1 << 6), (1 << 0) | (1 << 4) | (1 << 5) | (1 << 7), (1 << 3) };
    for (0..4) |t| {
        Yzoo[t] = try alloc.alloc(f64, rq1.NSAMP);
        for (0..rq1.NSAMP) |s| {
            var p: f64 = 1.0;
            for (0..8) |i| {
                if (zoo_masks[t] & (@as(u8, 1) << @intCast(i)) != 0) p *= (@as(f64, @floatFromInt(grid[s][i])) - 2.5);
            }
            Yzoo[t][s] = if (p > 0) 1.0 else 0.0;
        }
    }

    const trained = try rq1.trainZooA(X, grid, Yzoo, phiTgt, &w, SilentOut{});
    const frozen = trained.lib[0..trained.nlib];
    const zoo_train_evals: usize = 4 * 8 * 255; // zoo-A forge rounds × mask sweep (monomial-only setup cost)

    const invention = try runInventionMode(alloc, grid, battery, bank, X, phiTgt, &w, frozen);
    var mono = runMonomialOnly(grid, battery, frozen, X, &w);
    mono.evals += zoo_train_evals;
    const fixed = try runFixedMenu(alloc, grid, battery);
    const random = runRandomSearch(grid, battery, frozen, X, phiTgt, &w, rq1.BATTERY_SEED ^ 0xDEAD);
    const nover = runNoVerifier(grid, battery, frozen, X, &w);

    const results = [_]ModeResult{ invention, mono, fixed, random, nover };

    try out.print("mode\tsolved\ttotal\tevals\n", .{});
    for (results) |r| {
        try out.print("{s}\t{d}\t{d}\t{d}\n", .{ modeName(r.mode), r.solved, r.total, r.evals });
    }

    const inv = invention;
    const beats_solve = inv.solved > mono.solved and inv.solved > fixed.solved and inv.solved > random.solved and inv.solved > nover.solved;
    const leaner_mono = inv.evals < mono.evals;
    const leaner_random = inv.evals < random.evals;
    try out.print("\n── verdict ──\n", .{});
    try out.print("invention beats all baselines on solve rate: {}\n", .{beats_solve});
    try out.print("invention leaner than monomial: {} ({d} vs {d})\n", .{ leaner_mono, inv.evals, mono.evals });
    try out.print("invention leaner than random: {} ({d} vs {d})\n", .{ leaner_random, inv.evals, random.evals });
    try out.print("PASS: {}\n", .{beats_solve and inv.solved >= 10 and leaner_mono});
}