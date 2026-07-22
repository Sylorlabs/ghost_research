//! EXPERIMENT E20 — POET curriculum stress test (E12/RQ8 hardened).
//!
//! Extends RQ8 hard mutators to 200 POET rounds and measures whether the curriculum
//! sustains a richer population under stricter pass criteria than RQ8.
//!
//! Reuses:
//!   • open_invention_rq8.zig — hard mutators, noisy-label solver, pair readout
//!   • open_invention_e12.zig — frontier-depth ratchet pattern (solved tier tracking)
//!
//! Pass bar:
//!   • curriculum size ≥20 in band for ≥50 consecutive rounds
//!   • solve rate ∈ [30%, 60%]
//!
//! Run: zig build open-invention-e20 --release=fast

const std = @import("std");
const unified = @import("unified_invention.zig");
const rq8 = @import("open_invention_rq8.zig");
const e12 = @import("open_invention_e12.zig");

const N_ROUNDS: usize = 200;
const CHECKPOINT_EVERY: usize = 20;
const N_CHECKPOINTS: usize = N_ROUNDS / CHECKPOINT_EVERY;
const CURR_PASS_SIZE: usize = 20;
const CURR_PASS_CONSECUTIVE: usize = 50;
const SOLVE_LO: f64 = 0.30;
const SOLVE_HI: f64 = 0.60;
const SEED: u64 = 0xE20C0FFEE12A11CE;

pub const ExperimentResult = struct {
    rounds: usize,
    proposals: usize,
    solved_count: usize,
    solve_rate: f64,
    curriculum_size: usize,
    curriculum_peak: usize,
    solved_frontier: usize,
    curriculum_ge20_rounds: usize,
    max_consecutive_ge20: usize,
    consecutive_pass: bool,
    solve_rate_pass: bool,
    stress_pass: bool,
    curriculum_trace: [N_CHECKPOINTS]usize,
    frontier_trace: [N_CHECKPOINTS]usize,
    solve_rate_trace: [N_CHECKPOINTS]f64,
};

pub fn runExperiment(alloc: std.mem.Allocator, out: anytype, verbose: bool) !ExperimentResult {
    var prng = std.Random.DefaultPrng.init(SEED);
    const rand = prng.random();

    var curriculum = std.ArrayList(rq8.CurriculumEntry).init(alloc);
    defer curriculum.deinit();

    var solved_count: usize = 0;
    var proposals: usize = 0;
    var solved_frontier: usize = 0;
    var curriculum_ge20_rounds: usize = 0;
    var consecutive_ge20: usize = 0;
    var max_consecutive_ge20: usize = 0;
    var curriculum_trace: [N_CHECKPOINTS]usize = .{0} ** N_CHECKPOINTS;
    var frontier_trace: [N_CHECKPOINTS]usize = .{0} ** N_CHECKPOINTS;
    var solve_rate_trace: [N_CHECKPOINTS]f64 = .{0} ** N_CHECKPOINTS;

    if (verbose) {
        try out.print("=== EXPERIMENT E20: POET curriculum stress test (E12/RQ8 hardened) ===\n\n", .{});
        try out.print("Mutators (RQ8): 10% label noise | Walsh deg 3–5 | composed AND (2-feature)\n", .{});
        try out.print("Frontier (E12): solved depth ratchet on hard-target tiers\n", .{});
        try out.print("Curate band: [{d:.2}, {d:.2}]  |  Pass: curriculum≥{d} for ≥{d} consecutive rounds AND solve∈[{d:.0}%,{d:.0}%]\n", .{
            rq8.CURR_LO, rq8.CURR_HI, CURR_PASS_SIZE, CURR_PASS_CONSECUTIVE, SOLVE_LO * 100, SOLVE_HI * 100,
        });
        try out.print("Rounds: {d} × {d} proposals = {d} total.\n\n", .{
            N_ROUNDS, rq8.PROPOSALS_PER_ROUND, N_ROUNDS * rq8.PROPOSALS_PER_ROUND,
        });
    }

    const grid = try alloc.alloc([rq8.NCELL]u8, rq8.NSAMP);
    var solve_scratch = rq8.SolveScratch{
        .Y_clean = undefined,
        .Y_train = undefined,
        .X = undefined,
        .phiTgt = undefined,
        .w = undefined,
    };

    var round: usize = 0;
    while (round < N_ROUNDS) : (round += 1) {
        var gprng = std.Random.DefaultPrng.init(SEED +% round *% 0x9E3779B9);
        const grid_rand = gprng.random();
        for (0..rq8.NSAMP) |s| for (0..rq8.NCELL) |i| {
            grid[s][i] = grid_rand.intRangeAtMost(u8, 0, rq8.VMAX);
        };

        var p: usize = 0;
        while (p < rq8.PROPOSALS_PER_ROUND) : (p += 1) {
            const parent = rq8.pickCurriculumParent(rand, curriculum.items);
            const spec = rq8.mutateTarget(rand, parent);
            const depth = rq8.targetDepth(spec);

            const result = rq8.runHardTarget(grid, spec, SEED +% round *% 17 +% p, &solve_scratch);
            proposals += 1;
            const cov = result.cov;

            try rq8.tryAddCurriculum(&curriculum, spec, cov);

            if (result.solved) {
                solved_count += 1;
                if (depth > solved_frontier) solved_frontier = depth;
            }

            if (verbose and round < 4) {
                var buf: [40]u8 = undefined;
                const sname = rq8.formatSpec(&buf, spec);
                try out.print("  r{d:>3} p{d} {s:<20} cov={d:.3}{s} depth={d}\n", .{
                    round,
                    p,
                    sname,
                    cov,
                    if (result.solved) " SOLVED" else "",
                    depth,
                });
            }
        }

        if (curriculum.items.len >= CURR_PASS_SIZE) {
            curriculum_ge20_rounds += 1;
            consecutive_ge20 += 1;
            max_consecutive_ge20 = @max(max_consecutive_ge20, consecutive_ge20);
        } else {
            consecutive_ge20 = 0;
        }

        if ((round + 1) % CHECKPOINT_EVERY == 0) {
            const slot = (round + 1) / CHECKPOINT_EVERY - 1;
            if (slot < N_CHECKPOINTS) {
                curriculum_trace[slot] = curriculum.items.len;
                frontier_trace[slot] = solved_frontier;
                solve_rate_trace[slot] = @as(f64, @floatFromInt(solved_count)) / @as(f64, @floatFromInt(proposals));
            }
        }

        if (verbose and (round + 1) % CHECKPOINT_EVERY == 0) {
            const rolling = @as(f64, @floatFromInt(solved_count)) / @as(f64, @floatFromInt(proposals));
            try out.print("  … round {d}: curriculum={d} peak_depth={d} solved_frontier={d} solve_rate={d:.1}% streak_ge{d}={d}\n", .{
                round,
                curriculum.items.len,
                rq8.curriculumPeakDepth(curriculum.items),
                solved_frontier,
                rolling * 100,
                CURR_PASS_SIZE,
                consecutive_ge20,
            });
        }
    }

    const solve_rate = @as(f64, @floatFromInt(solved_count)) / @as(f64, @floatFromInt(proposals));
    const curriculum_peak = rq8.curriculumPeakDepth(curriculum.items);
    const consecutive_pass = max_consecutive_ge20 >= CURR_PASS_CONSECUTIVE;
    const solve_rate_pass = solve_rate >= SOLVE_LO and solve_rate <= SOLVE_HI;
    const stress_pass = consecutive_pass and solve_rate_pass;

    if (verbose) {
        try out.print("\n── curriculum size trace (every {d} rounds) ──\n", .{CHECKPOINT_EVERY});
        for (curriculum_trace, 0..) |sz, i| {
            try out.print("  checkpoint {d:>3}: size {d}  frontier {d}  solve_rate {d:.1}%\n", .{
                (i + 1) * CHECKPOINT_EVERY,
                sz,
                frontier_trace[i],
                solve_rate_trace[i] * 100,
            });
        }
        try out.print("\n════════════════════ VERDICT ════════════════════\n", .{});
        try out.print("rounds:                      {d}\n", .{N_ROUNDS});
        try out.print("proposals:                   {d}\n", .{proposals});
        try out.print("solved (≥{d:.2}):             {d}\n", .{ unified.COVER_THRESHOLD, solved_count });
        try out.print("solve rate:                  {d:.1}%  (pass band {d:.0}–{d:.0}%)\n", .{ solve_rate * 100, SOLVE_LO * 100, SOLVE_HI * 100 });
        try out.print("curriculum size (final):     {d}  (band [{d:.2},{d:.2}])\n", .{ curriculum.items.len, rq8.CURR_LO, rq8.CURR_HI });
        try out.print("curriculum peak depth:       {d}\n", .{curriculum_peak});
        try out.print("solved frontier depth:       {d}  (E12-style ratchet)\n", .{solved_frontier});
        try out.print("rounds curriculum≥{d}:       {d}/{d}\n", .{ CURR_PASS_SIZE, curriculum_ge20_rounds, N_ROUNDS });
        try out.print("max consecutive curriculum≥{d}: {d}/{d}\n", .{ CURR_PASS_SIZE, max_consecutive_ge20, CURR_PASS_CONSECUTIVE });
        try out.print("consecutive curriculum pass: {s}\n", .{if (consecutive_pass) "PASS" else "FAIL"});
        try out.print("solve rate pass:             {s}\n", .{if (solve_rate_pass) "PASS" else "FAIL"});
        try out.print("stress test pass:            {s}\n", .{if (stress_pass) "PASS" else "FAIL"});
        try out.print("\nBaseline refs: E12 (easy mutators, empty curriculum), RQ8 (50-round hard mutators)\n", .{});
        try out.print("E12 frontier tiers:        mono 1–4 | parity/oriented=5 | sum_mod=6 | sign_mod=7\n", .{});
        try out.print("E12 baseline:              75 rounds, frontier depth 7/7 (see open_invention_e12.md)\n", .{});
        _ = e12.targetDepth;
        try out.print("See: open_invention_e12.zig, open_invention_rq8.zig, unified_invention.zig\n", .{});
    }

    return .{
        .rounds = N_ROUNDS,
        .proposals = proposals,
        .solved_count = solved_count,
        .solve_rate = solve_rate,
        .curriculum_size = curriculum.items.len,
        .curriculum_peak = curriculum_peak,
        .solved_frontier = solved_frontier,
        .curriculum_ge20_rounds = curriculum_ge20_rounds,
        .max_consecutive_ge20 = max_consecutive_ge20,
        .consecutive_pass = consecutive_pass,
        .solve_rate_pass = solve_rate_pass,
        .stress_pass = stress_pass,
        .curriculum_trace = curriculum_trace,
        .frontier_trace = frontier_trace,
        .solve_rate_trace = solve_rate_trace,
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();
    _ = try runExperiment(alloc, out, true);
}

test "E20 stress test runs 200 rounds on pinned seed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const NullOut = struct {
        pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
    };
    const result = try runExperiment(arena.allocator(), NullOut{}, false);
    try std.testing.expect(result.rounds == N_ROUNDS);
    try std.testing.expect(result.proposals == N_ROUNDS * rq8.PROPOSALS_PER_ROUND);
    try std.testing.expect(result.solve_rate > 0.05);
    try std.testing.expect(result.solve_rate < 0.98);
    try std.testing.expect(result.curriculum_size > 0);
}