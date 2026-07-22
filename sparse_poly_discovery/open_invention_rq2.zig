//! RESEARCH Q2 — E2 XOR gap closure via minimal xor_popcount(mask) readout.
//!
//! Reuses E2 adversarial 24 targets (seed 0xE2C0FFEE20260629). Compares:
//!   BEFORE — E2 forge menu (monomial + spectral/Walsh/Clifford + world mod_p)
//!   AFTER  — same menu + mask search over xor_popcount(mask) (NOT full Walsh enumeration)
//!
//! xor_popcount(mask) = popcount-parity of XOR of masked cell values (GF(2) lift).
//!
//! PASS bar: every E2 oracle-only target (forge<0.90, oracle≥0.95) reaches forge≥0.90
//! after xor_popcount injection.
//!
//! Run: zig build open-invention-rq2 --release=fast

const std = @import("std");
const e2 = @import("open_invention_e2.zig");

pub const RQ2Summary = struct {
    targets_kept: usize,
    baseline_forge_solved: usize,
    baseline_oracle_only: usize,
    oracle_only_closed: usize,
    oracle_only_total: usize,
    pass: bool,
};

fn isOracleOnlyGap(kt: e2.KeptTarget, forge_cov: f64) bool {
    return forge_cov < e2.FORGE_THRESH and kt.oracle_cov >= e2.ORACLE_THRESH;
}

fn isXorFamily(spec: e2.PredSpec) bool {
    return spec.kind == .xor_cells or spec.kind == .parity_xor;
}

pub fn runExperiment(alloc: std.mem.Allocator, out: anytype, seed: u64) !RQ2Summary {
    try out.print("=== RESEARCH Q2: E2 XOR gap closure (xor_popcount mask readout) ===\n\n", .{});
    try out.print("Pool: E2 adversarial filter (lib<0.60, oracle≥0.95), seed 0x{X:0>16}\n", .{seed});
    try out.print("BEFORE menu: E2 forge (no xor_popcount).  AFTER: + xor_popcount(mask) search.\n", .{});
    try out.print("PASS bar: all oracle-only XOR-family targets forge-solved after injection.\n\n", .{});

    const pool = try e2.collectAdversarialPool(alloc, out, seed);
    const grid = pool.grid;
    const kept = pool.kept;

    const X = try alloc.alloc([]f64, e2.NSAMP);
    const scratch = try alloc.alloc(f64, e2.NSAMP);
    for (0..e2.NSAMP) |s| X[s] = try alloc.alloc(f64, e2.MAXFEAT);
    var w: [e2.MAXFEAT + 1]f64 = undefined;
    const Yscratch = try alloc.alloc(f64, e2.NSAMP);

    try out.print("\n── Per-target before / after (oracle-only XOR gaps highlighted) ──\n\n", .{});

    var baseline_forge_solved: usize = 0;
    var baseline_oracle_only: usize = 0;
    var oracle_only_total: usize = 0;
    var oracle_only_closed: usize = 0;
    var xor_oracle_only: usize = 0;
    var xor_closed: usize = 0;

    for (kept) |*kt| {
        for (0..e2.NSAMP) |s| Yscratch[s] = e2.label(grid[s], kt.spec);

        const before = e2.runForgeOnTarget(X, grid, Yscratch, scratch, &w);
        const after = e2.runForgeOnTargetWithXorPopcount(X, grid, Yscratch, scratch, &w);

        if (before >= e2.FORGE_THRESH) baseline_forge_solved += 1;
        const baseline_gap = isOracleOnlyGap(kt.*, before);
        if (baseline_gap) baseline_oracle_only += 1;

        const after_gap = isOracleOnlyGap(kt.*, after);
        const closed = baseline_gap and !after_gap;

        if (baseline_gap) {
            oracle_only_total += 1;
            if (closed) oracle_only_closed += 1;
            if (isXorFamily(kt.spec)) {
                xor_oracle_only += 1;
                if (closed) xor_closed += 1;
            }
        }

        var buf: [64]u8 = undefined;
        const tag: []const u8 = if (baseline_gap and closed)
            " CLOSED"
        else if (baseline_gap and after_gap)
            " STUCK"
        else if (before >= e2.FORGE_THRESH)
            ""
        else
            "";

        try out.print("  {s}: before={d:.3} after={d:.3}{s}\n", .{
            kt.spec.fmt(&buf),
            before,
            after,
            tag,
        });
    }

    const pass = oracle_only_total > 0 and oracle_only_closed == oracle_only_total;

    try out.print("\n════════════════════ SUMMARY ════════════════════\n", .{});
    try out.print("  targets kept:              {d}\n", .{kept.len});
    try out.print("  BEFORE forge solved:       {d}/{d}\n", .{ baseline_forge_solved, kept.len });
    try out.print("  BEFORE oracle-only gaps:   {d}\n", .{baseline_oracle_only});
    try out.print("  oracle-only (all families): {d}\n", .{oracle_only_total});
    try out.print("  closed by xor_popcount:    {d}/{d}\n", .{ oracle_only_closed, oracle_only_total });
    try out.print("  XOR-family oracle-only:    {d} (closed {d})\n\n", .{ xor_oracle_only, xor_closed });

    try out.print("VERDICT: ", .{});
    if (oracle_only_total == 0) {
        try out.print("N/A — no oracle-only targets in pool this seed.\n", .{});
    } else if (pass) {
        try out.print("PASS — xor_popcount(mask) closes all {d}/{d} oracle-only gaps.\n", .{
            oracle_only_closed,
            oracle_only_total,
        });
    } else {
        try out.print("FAIL — xor_popcount closes {d}/{d} oracle-only gaps (need {d}/{d}).\n", .{
            oracle_only_closed,
            oracle_only_total,
            oracle_only_total,
            oracle_only_total,
        });
    }

    try out.print("\nSee: open_invention_rq2.md, open_invention_e2.md\n", .{});

    return .{
        .targets_kept = kept.len,
        .baseline_forge_solved = baseline_forge_solved,
        .baseline_oracle_only = baseline_oracle_only,
        .oracle_only_closed = oracle_only_closed,
        .oracle_only_total = oracle_only_total,
        .pass = pass,
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();
    _ = try runExperiment(alloc, out, e2.RNG_SEED);
}