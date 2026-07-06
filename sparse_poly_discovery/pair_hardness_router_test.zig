//! EXP-2: pair-selection hardness router vs brute O(N²) pair search.
//! Compares guided routing on hidden-pair predicate + 5 random degree-2 targets.
//! Run: zig build pair-hardness-router-test --release=fast

const std = @import("std");
const router = @import("pair_hardness_router.zig");

const Target = struct {
    name: []const u8,
    true_i: usize,
    true_j: usize,

    fn label(self: Target, g: [router.NCELL]u8) f64 {
        if (self.true_i == router.HIDDEN_PAIR[0] and self.true_j == router.HIDDEN_PAIR[1]) {
            return router.hiddenPairLabel(g);
        }
        return router.degree2PairLabel(g, self.true_i, self.true_j);
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    const grid = try router.makeGrid(alloc, 0x9E3B1D0FA5172C44);
    const menuX2 = try router.buildMenuX2(alloc, grid);

    const feat = try alloc.alloc([]f64, router.NSAMP);
    for (0..router.NSAMP) |s| feat[s] = try alloc.alloc(f64, 1);
    const pf = try alloc.alloc([]f64, router.NSAMP);
    for (0..router.NSAMP) |s| pf[s] = try alloc.alloc(f64, 3);
    var w: [16]f64 = undefined;

    // 5 random degree-2 targets (fixed seeds for reproducibility)
    const rand_pairs = [_][2]usize{
        .{ 1, 4 },
        .{ 0, 6 },
        .{ 3, 7 },
        .{ 2, 6 },
        .{ 4, 5 },
    };

    var targets: [6]Target = undefined;
    var name_bufs: [6][32]u8 = undefined;
    targets[0] = .{
        .name = "hidden_pair(2,5)",
        .true_i = router.HIDDEN_PAIR[0],
        .true_j = router.HIDDEN_PAIR[1],
    };
    for (rand_pairs, 0..) |p, t| {
        const idx = t + 1;
        targets[idx] = .{
            .name = try std.fmt.bufPrint(&name_bufs[idx], "deg2({d},{d})", .{ p[0], p[1] }),
            .true_i = p[0],
            .true_j = p[1],
        };
    }

    try out.print("=== EXP-2: Pair Hardness Router vs Brute ({d} targets, {d} pairs) ===\n\n", .{
        targets.len, router.N_PAIRS,
    });
    try out.print("Guided cost: {d} cell probes + {d} menu + {d} focal + {d} cheap corrs + 1 pair verify\n", .{
        router.NCELL, 1, 1, router.N_PAIRS,
    });
    try out.print("Brute cost:  {d} full pair logistic fits\n\n", .{router.N_PAIRS});

    var n_match: usize = 0;
    var n_acc_match: usize = 0;
    var total_guided_val: f64 = 0;
    var total_brute_val: f64 = 0;

    for (targets) |tgt| {
        const Y = try alloc.alloc(f64, router.NSAMP);
        for (0..router.NSAMP) |s| Y[s] = tgt.label(grid[s]);
        const routed = router.route(grid, menuX2, Y, feat, pf, &w);
        const brute = router.brutePairSearch(pf, grid, Y, &w);

        const matched = router.pairsMatch(
            routed.proposal.i, routed.proposal.j,
            brute.i, brute.j,
        );
        const acc_ok = routed.proposal.val_acc >= brute.val_acc - 0.01;
        if (matched) n_match += 1;
        if (acc_ok) n_acc_match += 1;
        total_guided_val += routed.proposal.val_acc;
        total_brute_val += brute.val_acc;

        try out.print("--- {s} ---\n", .{tgt.name});
        try out.print("  task_class: {s}  menu={d:.3}  focal(0,1)={d:.3}\n", .{
            @tagName(routed.task_class), routed.menu_val, routed.focal_val,
        });
        try out.print("  guided: ({d},{d}) val={d:.3} tst={d:.3}\n", .{
            routed.proposal.i, routed.proposal.j, routed.proposal.val_acc, routed.proposal.tst_acc,
        });
        try out.print("  brute:  ({d},{d}) val={d:.3} tst={d:.3}\n", .{
            brute.i, brute.j, brute.val_acc, brute.tst_acc,
        });
        try out.print("  truth:  ({d},{d})  pair_match={s}  acc_ok={s}\n\n", .{
            tgt.true_i, tgt.true_j,
            if (matched) "YES" else "NO",
            if (acc_ok) "YES" else "NO",
        });
    }

    const cost_ratio = @as(f64, @floatFromInt(router.N_PAIRS)) /
        @as(f64, @floatFromInt(router.NCELL + 2 + 1)); // probes + menu + focal + 1 verify
    const pair_acc_rate = @as(f64, @floatFromInt(n_match)) / @as(f64, @floatFromInt(targets.len));
    const val_acc_rate = @as(f64, @floatFromInt(n_acc_match)) / @as(f64, @floatFromInt(targets.len));

    try out.print("=== VERDICT ===\n", .{});
    try out.print("  Pair identity match (guided == brute): {d}/{d} ({d:.0}%)\n", .{
        n_match, targets.len, pair_acc_rate * 100.0,
    });
    try out.print("  Val-acc match (guided >= brute - 0.01): {d}/{d} ({d:.0}%)\n", .{
        n_acc_match, targets.len, val_acc_rate * 100.0,
    });
    try out.print("  Mean val acc: guided={d:.3}  brute={d:.3}\n", .{
        total_guided_val / @as(f64, @floatFromInt(targets.len)),
        total_brute_val / @as(f64, @floatFromInt(targets.len)),
    });
    try out.print("  Cost ratio (brute/guided pair-fits): {d:.1}x\n", .{cost_ratio});

    const pass = n_match == targets.len and n_acc_match == targets.len;
    if (pass) {
        try out.print("  RESULT: PASS — guided routing matches brute on all targets.\n", .{});
    } else {
        try out.print("  RESULT: FAIL — guided routing diverges from brute on {d} target(s).\n", .{
            targets.len - @min(n_match, n_acc_match),
        });
    }
}