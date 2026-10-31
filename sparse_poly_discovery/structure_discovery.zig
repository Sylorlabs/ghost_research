//! FRONTIER 24 — autonomous structure discovery: argmax over (inner-transform ⊗ outer-operator)
//!
//! The project has, one probe at a time, built every PIECE of a structure discoverer:
//!   - spectral_discovery / period_candidate_search : the accuracy-grid spectral OUTER operator
//!       that finds a periodic generator's ω (parity-of-count, period-3, AND-composition).
//!   - antisymmetric_relational : the Clifford grade-2 bivector INNER feature sin(θ(v1−v0))
//!       that exposes an ORIENTED relation a symmetric product cannot.
//!   - concentration_control / representation_discovery : the order statistic max() as an inner.
//!   - composed_discovery : staged (inner, outer) discovery — but staged BY HAND, knowing the
//!       decomposition in advance.
//!
//! What was never assembled: a SINGLE blind loop that, handed a black-box predicate with NO
//! hint, discovers its (inner, outer) structure by argmax over the candidate menu — the step
//! three docs explicitly name as next (operator_inference.md: "argmax_{inner_Q} spectral_acc(Q)";
//! composed_discovery.md: "a search over (inner transform, outer operator) pairs — itself a
//! closure problem one level up").
//!
//! This is that loop. It also runs the deepest test in the repo, one level up: the discoverer's
//! MENU is itself a closed set. The zoo therefore includes a deliberately OUT-OF-MENU predicate
//! (a degree-2 relation on a HIDDEN pair (2,5), while the menu's relational inners are hardwired
//! to the focal pair (0,1)). A working discoverer must:
//!   (a) route every in-menu predicate to its true (inner,outer) AND beat the closed-substrate
//!       baseline — the ESCAPE corollary, re-instantiated at the structure level; and
//!   (b) FAIL on the out-of-menu one — the CEILING corollary — exactly while a richer closed
//!       substrate (degree-2 over raw cells) cracks it, naming the generator the menu lacks
//!       (the c2·c5 cross-term = "the product of the RIGHT pair"). The menu HAS product-of-a-pair,
//!       but hardwired to (0,1); the escape is to discover WHICH cells. That is the target of the
//!       next step (#3): grow the menu, not add an operator.
//!
//! Selection discipline: a 3-way split. Outer params are fit on TRAIN; the (inner,outer) pair and
//! the spectral ω are selected on VALIDATION; the reported number is TEST. (period_candidate_search
//! selected ω on the eval set; this tightens that so "discovery" is held-out, not selection-on-test.)
//!
//! Run: zig build structure-discovery

const std = @import("std");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3; // bit b_i = (cell_i >= THRESH)
const THETA: f64 = 0.40; // Cl(2,0) encoding angle; grade-2 blade = sin(θ(v1−v0))
const FOCAL_A: usize = 0; // the menu's relational inners are hardwired to this pair
const FOCAL_B: usize = 1;
const HIDDEN_A: usize = 2; // the out-of-menu predicate lives on this pair
const HIDDEN_B: usize = 5;
const MID: f64 = @as(f64, @floatFromInt(VMAX)) / 2.0;

const NSAMP: usize = 9000;
const NTR: usize = NSAMP / 2; //      [0, NTR)        train  (fit params)
const NVA: usize = NSAMP * 3 / 4; //  [NTR, NVA)      val    (select inner/outer/ω)
//                                    [NVA, NSAMP)    test   (report)

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

// ── inner transforms: grid → scalar ─────────────────────────────────────────
const Inner = enum { count, sum, max_cell, inversion, oriented, product };
const N_INNER = 6;
const inner_name = [N_INNER][]const u8{ "count", "sum", "max", "inversion", "oriented(0,1)", "product(0,1)" };

fn innerScalar(kind: Inner, g: [NCELL]u8) f64 {
    switch (kind) {
        .count => {
            var c: usize = 0;
            for (g) |v| if (v >= THRESH) {
                c += 1;
            };
            return @floatFromInt(c);
        },
        .sum => {
            var s: u32 = 0;
            for (g) |v| s += v;
            return @floatFromInt(s);
        },
        .max_cell => {
            var m: u8 = 0;
            for (g) |v| m = @max(m, v);
            return @floatFromInt(m);
        },
        .inversion => {
            var inv: usize = 0;
            for (0..NCELL) |i| for (i + 1..NCELL) |j| {
                if (g[i] > g[j]) inv += 1;
            };
            return @floatFromInt(inv);
        },
        // Cl(2,0) grade-2 blade of geo(C_a, C_b) with C_i = cos(θv_i)e1 + sin(θv_i)e2,
        // = cos(θv0)sin(θv1) − sin(θv0)cos(θv1) = sin(θ(v1−v0)). The antisymmetric (oriented) feature.
        .oriented => {
            const v0: f64 = @floatFromInt(g[FOCAL_A]);
            const v1: f64 = @floatFromInt(g[FOCAL_B]);
            return @sin(THETA * (v1 - v0));
        },
        .product => {
            return @as(f64, @floatFromInt(g[FOCAL_A])) * @as(f64, @floatFromInt(g[FOCAL_B]));
        },
    }
}

// ── outer operators ──────────────────────────────────────────────────────────
const Outer = enum { threshold, spectral, poly2 };
const N_OUTER = 3;
const outer_name = [N_OUTER][]const u8{ "threshold", "spectral", "poly2" };

const ValTest = struct { val: f64, tst: f64, detail: f64 };

// logistic over a dim-D standardized feature view; fit on train, eval on val and test
fn logit(X: []const []f64, Y: []const f64, dim: usize, epochs: usize, lr: f64, w: []f64) ValTest {
    @memset(w[0 .. dim + 1], 0);
    for (0..epochs) |_| for (0..NTR) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        const e = sigmoid(z) - Y[s];
        for (0..dim) |j| w[j] -= lr * e * X[s][j];
        w[dim] -= lr * e;
    };
    return .{ .val = accRange(X, Y, w, dim, NTR, NVA), .tst = accRange(X, Y, w, dim, NVA, NSAMP), .detail = 0 };
}

fn accRange(X: []const []f64, Y: []const f64, w: []const f64, dim: usize, lo: usize, hi: usize) f64 {
    var c: usize = 0;
    for (lo..hi) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        if ((z >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(hi - lo));
}

// accuracy-grid spectral (the fixed operator from period_candidate_search): scan ω with a CHEAP
// fit to rank by validation accuracy, then REFIT carefully at the winning ω. The ω the family's
// signal selects is sharp, so a light scan ranks it; the refit gives the reported a·cos(ω·s)+b.
fn fitCos(raw: []const f64, Y: []const f64, w: f64, epochs: usize) [2]f64 {
    var a: f64 = 1.0;
    var b: f64 = 0.0;
    for (0..epochs) |_| for (0..NTR) |s| {
        const cw = @cos(w * raw[s]);
        const e = sigmoid(a * cw + b) - Y[s];
        a -= 0.08 * e * cw;
        b -= 0.08 * e;
    };
    return .{ a, b };
}

fn cosAccRange(raw: []const f64, Y: []const f64, a: f64, b: f64, w: f64, lo: usize, hi: usize) f64 {
    var c: usize = 0;
    for (lo..hi) |s| {
        if ((a * @cos(w * raw[s]) + b >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(hi - lo));
}

fn spectral(raw: []const f64, Y: []const f64, freqs: usize, scan_ep: usize, final_ep: usize) ValTest {
    var best_val: f64 = -1;
    var best_w: f64 = 0;
    for (1..freqs + 1) |fi| {
        const w = @as(f64, @floatFromInt(fi)) * std.math.pi / @as(f64, @floatFromInt(freqs));
        const ab = fitCos(raw, Y, w, scan_ep);
        const val = cosAccRange(raw, Y, ab[0], ab[1], w, NTR, NVA);
        if (val > best_val) {
            best_val = val;
            best_w = w;
        }
    }
    const ab = fitCos(raw, Y, best_w, final_ep); // careful refit at the winner
    return .{
        .val = cosAccRange(raw, Y, ab[0], ab[1], best_w, NTR, NVA),
        .tst = cosAccRange(raw, Y, ab[0], ab[1], best_w, NVA, NSAMP),
        .detail = best_w,
    };
}

fn standardize(X: [][]f64, dim: usize) void {
    for (0..dim) |j| {
        var mu: f64 = 0;
        for (0..NTR) |s| mu += X[s][j];
        mu /= @floatFromInt(NTR);
        var sd: f64 = 0;
        for (0..NTR) |s| sd += (X[s][j] - mu) * (X[s][j] - mu);
        sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
        for (0..X.len) |s| X[s][j] = (X[s][j] - mu) / sd;
    }
}

fn chanceOf(Y: []const f64) f64 {
    var pos: f64 = 0;
    for (NVA..NSAMP) |s| pos += Y[s];
    const n: f64 = @floatFromInt(NSAMP - NVA);
    return @max(pos, n - pos) / n;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var prng = std.Random.DefaultPrng.init(0x57B17C7012345678);
    const rand = prng.random();

    // ── one shared grid set ──
    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    };

    // ── precompute every inner transform once: raw scalar + standardized [s, s²] view ──
    const raw = try alloc.alloc([]f64, N_INNER); // raw[inner][sample]
    const feat = try alloc.alloc([][]f64, N_INNER); // feat[inner][sample] = [z(s), z(s²)]
    for (0..N_INNER) |ti| {
        raw[ti] = try alloc.alloc(f64, NSAMP);
        feat[ti] = try alloc.alloc([]f64, NSAMP);
        const kind: Inner = @enumFromInt(ti);
        for (0..NSAMP) |s| {
            const v = innerScalar(kind, grid[s]);
            raw[ti][s] = v;
            feat[ti][s] = try alloc.alloc(f64, 2);
            feat[ti][s][0] = v;
            feat[ti][s][1] = v * v;
        }
        standardize(feat[ti], 2);
    }

    // ── closed-substrate baselines over RAW cells (the "is it even hard?" controls) ──
    // linear-raw: NCELL cell values. poly2-raw: cells + squares + all pairwise products.
    const npoly = NCELL + NCELL + NCELL * (NCELL - 1) / 2;
    const Xlin = try alloc.alloc([]f64, NSAMP);
    const Xpoly = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| {
        Xlin[s] = try alloc.alloc(f64, NCELL);
        for (0..NCELL) |i| Xlin[s][i] = @floatFromInt(grid[s][i]);
        Xpoly[s] = try alloc.alloc(f64, npoly);
        var k: usize = 0;
        for (0..NCELL) |i| {
            Xpoly[s][k] = @floatFromInt(grid[s][i]);
            k += 1;
        }
        for (0..NCELL) |i| {
            Xpoly[s][k] = @as(f64, @floatFromInt(grid[s][i])) * @as(f64, @floatFromInt(grid[s][i]));
            k += 1;
        }
        for (0..NCELL) |i| for (i + 1..NCELL) |j| {
            Xpoly[s][k] = @as(f64, @floatFromInt(grid[s][i])) * @as(f64, @floatFromInt(grid[s][j]));
            k += 1;
        };
    }
    standardize(Xlin, NCELL);
    standardize(Xpoly, npoly);

    // ── the predicate zoo (all from existing project work; last one OUT-OF-MENU) ──
    const NPRED = 8;
    const pred_name = [NPRED][]const u8{
        "parity-of-count",
        "sum-threshold",
        "max-threshold",
        "inversion-parity",
        "oriented sign(v1-v0)",
        "product-threshold",
        "AND-composition",
        "HIDDEN-pair degree-2  (OUT-OF-MENU)",
    };
    // expected true structure for the in-menu ones (−1 outer = "no menu pair", the ceiling case)
    const exp_inner = [NPRED]Inner{ .count, .sum, .max_cell, .inversion, .oriented, .product, .count, .count };
    const exp_outer = [NPRED]i32{ 1, 0, 0, 1, 0, 0, 1, -1 }; // index into Outer; -1 = out-of-menu

    const Y = try alloc.alloc([]f64, NPRED);
    for (0..NPRED) |p| Y[p] = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| {
        const g = grid[s];
        var cnt: usize = 0;
        for (g) |v| if (v >= THRESH) {
            cnt += 1;
        };
        var sm: u32 = 0;
        for (g) |v| sm += v;
        var mx: u8 = 0;
        for (g) |v| mx = @max(mx, v);
        var inv: usize = 0;
        for (0..NCELL) |i| for (i + 1..NCELL) |j| {
            if (g[i] > g[j]) inv += 1;
        };
        Y[0][s] = @floatFromInt(cnt & 1); // parity of count            → (count, spectral)
        Y[1][s] = if (sm >= NCELL * VMAX / 2) 1.0 else 0.0; // sum band  → (sum, threshold)
        Y[2][s] = if (mx >= VMAX) 1.0 else 0.0; // a maximal cell exists → (max, threshold)
        Y[3][s] = @floatFromInt(inv & 1); // parity of inversions       → (inversion, spectral)
        Y[4][s] = if (g[FOCAL_B] > g[FOCAL_A]) 1.0 else 0.0; // oriented → (oriented, threshold)
        const prod = @as(usize, g[FOCAL_A]) * @as(usize, g[FOCAL_B]);
        Y[5][s] = if (prod > @as(usize, VMAX) * VMAX / 2) 1.0 else 0.0; // → (product, threshold)
        Y[6][s] = if (cnt % 6 == 0) 1.0 else 0.0; // even AND div-by-3   → (count, spectral) sparse
        // OUT-OF-MENU: degree-2 relation on the HIDDEN pair (2,5): same side of MID.
        const da = @as(f64, @floatFromInt(g[HIDDEN_A])) - MID;
        const db = @as(f64, @floatFromInt(g[HIDDEN_B])) - MID;
        Y[7][s] = if (da * db > 0) 1.0 else 0.0;
    }

    try out.print("=== FRONTIER 24: autonomous structure discovery — argmax over (inner ⊗ outer) ===\n\n", .{});
    try out.print("NCELL={d} VMAX={d} THRESH={d} | focal pair ({d},{d}) hidden pair ({d},{d}) | train/val/test = {d}/{d}/{d}\n", .{ NCELL, VMAX, THRESH, FOCAL_A, FOCAL_B, HIDDEN_A, HIDDEN_B, NTR, NVA - NTR, NSAMP - NVA });
    try out.print("inner menu : count  sum  max  inversion  oriented(0,1)  product(0,1)\n", .{});
    try out.print("outer menu : threshold  spectral  poly2\n", .{});
    try out.print("pick rule  : select (inner,outer) and ω by VALIDATION acc; report TEST acc (held-out discovery).\n", .{});
    try out.print("tie-break  : within 0.01 val, prefer the simpler outer (threshold > poly2 > spectral).\n\n", .{});

    var w: [64]f64 = undefined; // logistic scratch (dim ≤ npoly < 64)

    // per-predicate summary accumulators
    var n_struct: usize = 0; // correct (inner,outer) discovered
    var n_escape: usize = 0; // ...of which are genuine out-of-linear-closure escapes
    var n_ceiling_correct: usize = 0;

    for (0..NPRED) |p| {
        const yv = Y[p];
        const chance = chanceOf(yv);

        // full (inner × outer) val/test matrix
        var val_m: [N_INNER][N_OUTER]f64 = undefined;
        var tst_m: [N_INNER][N_OUTER]f64 = undefined;
        for (0..N_INNER) |ti| {
            // threshold (dim1 over standardized s), poly2 (dim2 over [s,s²])
            const rt = logit(feat[ti], yv, 1, 120, 0.05, &w);
            const rp = logit(feat[ti], yv, 2, 160, 0.04, &w);
            const rs = spectral(raw[ti], yv, 300, 12, 80);
            val_m[ti][0] = rt.val;
            tst_m[ti][0] = rt.tst;
            val_m[ti][1] = rs.val;
            tst_m[ti][1] = rs.tst;
            val_m[ti][2] = rp.val;
            tst_m[ti][2] = rp.tst;
        }

        // select: best VALIDATION acc; ties (within 0.01) broken toward the simpler outer.
        const simplicity = [N_OUTER]u8{ 0, 2, 1 }; // threshold(0) simplest, poly2(1), spectral(2)
        var bi: usize = 0;
        var bo: usize = 0;
        var bestv: f64 = -1;
        for (0..N_INNER) |ti| for (0..N_OUTER) |oi| {
            if (val_m[ti][oi] > bestv) {
                bestv = val_m[ti][oi];
                bi = ti;
                bo = oi;
            }
        };
        // among cells within 0.01 of the best, prefer the simplest outer (ties → higher val)
        var best_simpl: u8 = simplicity[bo];
        for (0..N_INNER) |ti| for (0..N_OUTER) |oi| {
            if (val_m[ti][oi] >= bestv - 0.01) {
                if (simplicity[oi] < best_simpl or (simplicity[oi] == best_simpl and val_m[ti][oi] > val_m[bi][bo])) {
                    bi = ti;
                    bo = oi;
                    best_simpl = simplicity[oi];
                }
            }
        };
        const pick_tst = tst_m[bi][bo];

        // closed-substrate baselines
        const lin = logit(Xlin, yv, NCELL, 200, 0.02, &w).tst;
        const poly = logit(Xpoly, yv, npoly, 240, 0.015, &w).tst;

        // ── print matrix ──
        try out.print("── P{d}  {s}   (chance {d:.3}) ──\n", .{ p, pred_name[p], chance });
        try out.print("   inner \\ outer  |  threshold   spectral    poly2\n", .{});
        for (0..N_INNER) |ti| {
            try out.print("   {s:<14} |", .{inner_name[ti]});
            for (0..N_OUTER) |oi| {
                const mark: []const u8 = if (ti == bi and oi == bo) " *" else "  ";
                try out.print("   {d:.3}{s}", .{ tst_m[ti][oi], mark });
            }
            try out.print("\n", .{});
        }
        const ok_inner = (bi == @as(usize, @intFromEnum(exp_inner[p])));
        const ok_outer = (exp_outer[p] >= 0 and bo == @as(usize, @intCast(exp_outer[p])));
        if (exp_outer[p] >= 0) {
            const ok_struct = ok_inner and ok_outer and pick_tst >= 0.90;
            const is_escape = ok_struct and pick_tst > lin + 0.05; // linear baseline can't do it → genuine escape
            if (ok_struct) n_struct += 1;
            if (is_escape) n_escape += 1;
            const lab: []const u8 = if (!ok_struct) "MISROUTE ✗" else if (is_escape) "ROUTED ✓ (escape)" else "ROUTED ✓ (linearly solvable)";
            try out.print("   → discovered ({s}, {s})  test={d:.3}   expected ({s}, {s})   {s}\n", .{
                inner_name[bi],                         outer_name[bo],                                  pick_tst,
                inner_name[@intFromEnum(exp_inner[p])], outer_name[@as(usize, @intCast(exp_outer[p]))], lab,
            });
            try out.print("   baselines: linear-raw {d:.3}  poly2-raw {d:.3}\n\n", .{ lin, poly });
        } else {
            // out-of-menu: success = menu CANNOT clear 0.90, while poly2-raw (richer closure) can
            const ceiling = pick_tst < 0.90;
            const escape_exists = poly > 0.90 and poly > lin + 0.10;
            if (ceiling and escape_exists) n_ceiling_correct += 1;
            try out.print("   → best menu pick ({s}, {s})  test={d:.3}   [no in-menu structure expected]\n", .{ inner_name[bi], outer_name[bo], pick_tst });
            try out.print("   baselines: linear-raw {d:.3}  poly2-raw {d:.3}\n", .{ lin, poly });
            try out.print("   CEILING: menu best {d:.3} (<0.90) — the menu is a closure. ", .{pick_tst});
            if (escape_exists)
                try out.print("poly2-raw escapes at {d:.3}\n   via the c{d}·c{d} cross-term = 'product of the RIGHT pair' — the generator the menu lacks.\n\n", .{ poly, HIDDEN_A, HIDDEN_B })
            else
                try out.print("(poly2-raw {d:.3} did not cleanly escape — check class balance)\n\n", .{poly});
        }
    }

    // ── verdict ──
    try out.print("════════════════════ VERDICT ════════════════════\n", .{});
    try out.print("In-menu structure correctly discovered (right inner AND outer, test ≥ 0.90): {d}/7\n", .{n_struct});
    try out.print("  ...of which genuine out-of-linear-closure ESCAPES (menu route beats linear-raw): {d}/7\n", .{n_escape});
    try out.print("  ...the other {d} are linearly-solvable: routed correctly, but linear-raw also suffices (no escape to show).\n", .{n_struct - n_escape});
    try out.print("Out-of-menu predicate: menu hits its CEILING while a richer closure escapes: {d}/1\n\n", .{n_ceiling_correct});

    if (n_struct >= 6 and n_ceiling_correct == 1) {
        try out.print("ASSEMBLED. One blind argmax loop discovers the (inner,outer) structure across the whole\n", .{});
        try out.print("zoo — periodic (spectral), threshold, order-statistic, and oriented/relational — with NO\n", .{});
        try out.print("per-predicate hint. The scattered pieces (spectral_discovery, antisymmetric_relational,\n", .{});
        try out.print("concentration_control, composed_discovery) are now a single autonomous discoverer: the\n", .{});
        try out.print("step operator_inference.md and composed_discovery.md named as next.\n\n", .{});
        try out.print("AND the deeper result, one level up: the discoverer's MENU is itself a closure. It fails on\n", .{});
        try out.print("the hidden-pair predicate — not because that predicate is complex (a degree-2 raw readout\n", .{});
        try out.print("cracks it), but because the menu's relational inner is hardwired to the focal pair (0,1).\n", .{});
        try out.print("The escaping generator is concrete and named: the product of the RIGHT pair. 'Discover the\n", .{});
        try out.print("generator' has simply moved up a level — to discovering WHICH cells / growing the menu.\n", .{});
        try out.print("That is exactly #3 (an inventable-primitive substrate): make the menu itself growable.\n", .{});
    } else {
        try out.print("PARTIAL / SURPRISE. Structure {d}/7, ceiling {d}/1 — inspect the matrices above:\n", .{ n_struct, n_ceiling_correct });
        try out.print("a misroute means a flexible outer (poly2/spectral) spuriously cleared validation on a\n", .{});
        try out.print("wrong inner — i.e. raw held-out accuracy is not a sufficient structure certificate, and\n", .{});
        try out.print("the discoverer needs an Occam/irreducibility tie-break beyond accuracy. That is itself a\n", .{});
        try out.print("real finding about what 'discovery' requires.\n", .{});
    }

    try out.print("\nClosure all the way up: every rung of 'discover the generator' presupposes a richer menu to\n", .{});
    try out.print("search within (wcore Claim C; CLOSURE_PRINCIPLE.md). This frontier makes the menu explicit,\n", .{});
    try out.print("assembles the blind selector over it, and shows precisely where the menu's own closure bites.\n", .{});
    try out.print("\nSee: operator_inference.md, composed_discovery.md, antisymmetric_relational.md,\n", .{});
    try out.print("spectral_discovery.md, period_candidate_search.md, repo-root CLOSURE_PRINCIPLE.md.\n", .{});
}
