//! EXPERIMENT E25 — novelty-usefulness Pareto (E10++).
//!
//! Sweep R² gate {0.2,0.3,0.4,0.5} × escape {0.85,0.90,0.95}; measure useful-forge vs
//! novelty-only (random-target) hit rate on the E10 battery. Find Pareto-optimal tradeoffs.
//!
//! Pass bar: ∃ point with useful/random ≥5× AND ≥3 promotions per 100 battery targets.
//!
//! Reuses: open_invention_e10.zig (grid, battery, parameterized forges).
//!
//! Run: zig build open-invention-e25 --release=fast

const std = @import("std");
const e10 = @import("open_invention_e10.zig");

const NR2: usize = 4;
const NESC: usize = 3;
const R2_GATES = [_]f64{ 0.20, 0.30, 0.40, 0.50 };
const ESCAPE_GATES = [_]f64{ 0.85, 0.90, 0.95 };
const PASS_RATIO: f64 = 5.0;
const PASS_PROM_PER_100: f64 = 3.0;
const NCELL = e10.NCELL;

pub const SweepPoint = struct {
    r2_gate: f64,
    escape: f64,
    novelty_promoted: usize,
    novelty_battery_hits: usize,
    novelty_zoo_hits: usize,
    useful_promoted: usize,
    useful_battery_hits: usize,
    useful_zoo_hits: usize,
    useful_random_ratio: f64,
    prom_per_100: f64,
    pass_point: bool,
};

pub const ExperimentResult = struct {
    points: [NR2 * NESC]SweepPoint,
    pareto_count: usize,
    pareto_indices: [NR2 * NESC]usize,
    best_pass: ?usize,
    any_pass: bool,
};

fn zooHits(
    X: [][]f64,
    grid: []const [NCELL]u8,
    atoms: []const u8,
    Yzoo: [][]f64,
    Ybuf: []f64,
    w: []f64,
    cover: f64,
) usize {
    const zoo_mono_masks = [_]u8{ e10.ZOO[0].mask, e10.ZOO[1].mask, e10.ZOO[2].mask, e10.ZOO[3].mask };
    const mono = e10.countHitsCfg(X, grid, atoms, &zoo_mono_masks, Ybuf, w, cover);
    const t5: usize = if (e10.coverage(X, grid, atoms, Yzoo[4], w) >= cover) 1 else 0;
    return mono + t5;
}

fn dominates(a: SweepPoint, b: SweepPoint) bool {
    const a_better_use = a.useful_battery_hits > b.useful_battery_hits or
        (a.useful_battery_hits == b.useful_battery_hits and a.useful_zoo_hits > b.useful_zoo_hits);
    const a_better_nov = a.useful_promoted > b.useful_promoted or
        (a.useful_promoted == b.useful_promoted and a.novelty_battery_hits > b.novelty_battery_hits);
    const a_not_worse_use = a.useful_battery_hits >= b.useful_battery_hits and a.useful_zoo_hits >= b.useful_zoo_hits;
    const a_not_worse_nov = a.useful_promoted >= b.useful_promoted;
    return a_better_use and a_not_worse_nov or a_better_nov and a_not_worse_use;
}

fn computePareto(points: []const SweepPoint, out_idx: []usize) usize {
    var count: usize = 0;
    for (points, 0..) |p, i| {
        var dominated = false;
        for (points) |q| {
            if (dominates(q, p)) {
                dominated = true;
                break;
            }
        }
        if (!dominated) {
            out_idx[count] = i;
            count += 1;
        }
    }
    return count;
}

pub fn runExperiment(alloc: std.mem.Allocator, out: anytype, verbose: bool) !ExperimentResult {
    var prng = std.Random.DefaultPrng.init(e10.GRID_SEED);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, e10.NSAMP);
    for (0..e10.NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, e10.VMAX);
    };

    const X = try alloc.alloc([]f64, e10.NSAMP);
    const Xrec = try alloc.alloc([]f64, e10.NSAMP);
    for (0..e10.NSAMP) |s| {
        X[s] = try alloc.alloc(f64, e10.MAXATOMS);
        Xrec[s] = try alloc.alloc(f64, e10.MAXATOMS);
    }
    const phiTgt = try alloc.alloc(f64, e10.NSAMP);
    const Ybuf = try alloc.alloc(f64, e10.NSAMP);
    const Yzoo = try alloc.alloc([]f64, e10.NZOO);
    for (0..e10.NZOO) |t| Yzoo[t] = try alloc.alloc(f64, e10.NSAMP);
    for (0..e10.NZOO) |t| e10.labelGrid(grid, Yzoo[t], e10.ZOO[t]);

    var bat_prng = std.Random.DefaultPrng.init(e10.BATTERY_SEED);
    const battery_masks = try e10.genBatteryMasks(alloc, bat_prng.random());
    defer alloc.free(battery_masks);

    var w: [e10.MAXATOMS + 1]f64 = undefined;
    var points: [NR2 * NESC]SweepPoint = undefined;

    if (verbose) {
        try out.print("=== E25: novelty-usefulness Pareto (E10++) ===\n\n", .{});
        try out.print("Sweep: R² gate {any} × escape {any} on shared grid/battery (E10 seeds).\n", .{ R2_GATES, ESCAPE_GATES });
        try out.print("Control: novelty-only forge at each R² gate (target-agnostic).\n", .{});
        try out.print("Fused: inner_forge objective (irreducible ∧ escape) at each (R², escape).\n", .{});
        try out.print("Pass: useful/random ≥{d:.0}× AND ≥{d:.0} promotions per 100 battery targets.\n\n", .{ PASS_RATIO, PASS_PROM_PER_100 });
        try out.print("  R²   esc   nov_prom  nov_rand  use_prom  use_rand  zoo  ratio   prom/100  pass\n", .{});
        try out.print("  ---- ----- -------- --------- --------- --------- ---- ------- --------- ----\n", .{});
    }

    var pi: usize = 0;
    for (R2_GATES) |r2| {
        for (ESCAPE_GATES) |esc| {
            const escape_before = esc - 0.20;
            const cfg = e10.ForgeParams{
                .r2_max = r2,
                .escape_cover = esc,
                .escape_before = escape_before,
            };

            var novelty_atoms: [e10.MAXATOMS]u8 = undefined;
            const n_nov = e10.noveltyOnlyForgeCfg(grid, Xrec, phiTgt, &w, &novelty_atoms, r2);

            var useful_atoms: [e10.MAXATOMS]u8 = undefined;
            const n_use = e10.usefulnessForgeCfg(grid, X, Xrec, phiTgt, Yzoo, &w, &useful_atoms, cfg);

            const nov_hits = e10.countHitsCfg(X, grid, novelty_atoms[0..n_nov], battery_masks, Ybuf, &w, esc);
            const use_hits = e10.countHitsCfg(X, grid, useful_atoms[0..n_use], battery_masks, Ybuf, &w, esc);
            const nov_zoo = zooHits(X, grid, novelty_atoms[0..n_nov], Yzoo, Ybuf, &w, esc);
            const use_zoo = zooHits(X, grid, useful_atoms[0..n_use], Yzoo, Ybuf, &w, esc);

            const nov_prom = n_nov - NCELL;
            const use_prom = n_use - NCELL;
            const nov_rate = @as(f64, @floatFromInt(nov_hits)) / @as(f64, @floatFromInt(e10.NBATTERY));
            const use_rate = @as(f64, @floatFromInt(use_hits)) / @as(f64, @floatFromInt(e10.NBATTERY));
            const ratio: f64 = if (nov_rate > 1e-9)
                use_rate / nov_rate
            else if (use_hits > 0)
                @as(f64, 999.0)
            else
                0.0;
            const prom_per_100 = @as(f64, @floatFromInt(use_prom)) * 100.0 / @as(f64, @floatFromInt(e10.NBATTERY));
            const pass_point = ratio >= PASS_RATIO and prom_per_100 >= PASS_PROM_PER_100;

            points[pi] = .{
                .r2_gate = r2,
                .escape = esc,
                .novelty_promoted = nov_prom,
                .novelty_battery_hits = nov_hits,
                .novelty_zoo_hits = nov_zoo,
                .useful_promoted = use_prom,
                .useful_battery_hits = use_hits,
                .useful_zoo_hits = use_zoo,
                .useful_random_ratio = ratio,
                .prom_per_100 = prom_per_100,
                .pass_point = pass_point,
            };

            if (verbose) {
                try out.print("  {d:.1}  {d:.2}   {d:>4}     {d:>3}/{d:<3}   {d:>4}     {d:>3}/{d:<3}   {d}/{}  {d:>5.2}×  {d:>6.2}   {s}\n", .{
                    r2,
                    esc,
                    nov_prom,
                    nov_hits,
                    e10.NBATTERY,
                    use_prom,
                    use_hits,
                    e10.NBATTERY,
                    use_zoo,
                    e10.NZOO,
                    ratio,
                    prom_per_100,
                    if (pass_point) "PASS" else "—",
                });
            }
            pi += 1;
        }
    }

    var pareto_indices: [NR2 * NESC]usize = undefined;
    const pareto_count = computePareto(points[0..pi], pareto_indices[0..]);

    var best_pass: ?usize = null;
    var any_pass = false;
    for (points[0..pi], 0..) |p, i| {
        if (!p.pass_point) continue;
        any_pass = true;
        if (best_pass) |bi| {
            const b = points[bi];
            if (p.useful_zoo_hits > b.useful_zoo_hits or
                (p.useful_zoo_hits == b.useful_zoo_hits and p.useful_battery_hits > b.useful_battery_hits))
                best_pass = i;
        } else {
            best_pass = i;
        }
    }

    if (verbose) {
        try out.print("\n── Pareto frontier ({d} non-dominated) ──\n", .{pareto_count});
        for (pareto_indices[0..pareto_count]) |idx| {
            const p = points[idx];
            try out.print("  R²={d:.1} esc={d:.2}: prom={d} rand_hits={d}/{d} zoo={d}/{} ratio={d:.2}×\n", .{
                p.r2_gate,
                p.escape,
                p.useful_promoted,
                p.useful_battery_hits,
                e10.NBATTERY,
                p.useful_zoo_hits,
                e10.NZOO,
                p.useful_random_ratio,
            });
        }

        try out.print("\n── Verdict ──\n", .{});
        if (any_pass) {
            const bp = points[best_pass.?];
            try out.print("PASS — best point R²={d:.1} escape={d:.2}: useful/random={d:.2}×, prom/100={d:.2}, zoo={d}/{}.\n", .{
                bp.r2_gate,
                bp.escape,
                bp.useful_random_ratio,
                bp.prom_per_100,
                bp.useful_zoo_hits,
                e10.NZOO,
            });
        } else {
            try out.print("FAIL — no (R², escape) satisfies useful/random≥{d:.0}× AND prom/100≥{d:.0}.\n", .{ PASS_RATIO, PASS_PROM_PER_100 });
            // Report best ratio and best prom for diagnosis
            var best_ratio_i: usize = 0;
            var best_prom_i: usize = 0;
            for (points[1..pi], 1..) |p, i| {
                if (p.useful_random_ratio > points[best_ratio_i].useful_random_ratio) best_ratio_i = i;
                if (p.prom_per_100 > points[best_prom_i].prom_per_100) best_prom_i = i;
            }
            const br = points[best_ratio_i];
            const bp = points[best_prom_i];
            try out.print("Best ratio: R²={d:.1} esc={d:.2} → {d:.2}× (use {d}/{d} rand, nov {d}/{d}).\n", .{
                br.r2_gate, br.escape, br.useful_random_ratio, br.useful_battery_hits, e10.NBATTERY, br.novelty_battery_hits, e10.NBATTERY,
            });
            try out.print("Best prom/100: R²={d:.1} esc={d:.2} → {d:.2} (zoo {d}/{}).\n", .{
                bp.r2_gate, bp.escape, bp.prom_per_100, bp.useful_zoo_hits, e10.NZOO,
            });
        }

        const report_i = if (best_pass) |i| i else best_ratio_i: {
            var bi: usize = 0;
            for (points[1..pi], 1..) |p, i| {
                if (p.useful_zoo_hits > points[bi].useful_zoo_hits or
                    (p.useful_zoo_hits == points[bi].useful_zoo_hits and p.useful_random_ratio > points[bi].useful_random_ratio))
                    bi = i;
            }
            break :best_ratio_i bi;
        };
        const rp = points[report_i];
        try out.print("\nE25_RESULT pass={} best_r2={d:.1} best_esc={d:.2} ratio={d:.2} prom_per_100={d:.2} doc=docs/research/open_invention_e25.md\n", .{
            any_pass,
            rp.r2_gate,
            rp.escape,
            rp.useful_random_ratio,
            rp.prom_per_100,
        });
        try out.print("See: open_invention_e10.zig, open_invention_e10.md, inner_forge.zig\n", .{});
    }

    return .{
        .points = points,
        .pareto_count = pareto_count,
        .pareto_indices = pareto_indices,
        .best_pass = best_pass,
        .any_pass = any_pass,
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();
    _ = try runExperiment(alloc, out, true);
}