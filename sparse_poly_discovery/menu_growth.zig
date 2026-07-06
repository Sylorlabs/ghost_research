//! Phase B (#3, inventable-primitive substrate) — certified menu-growth.
//!
//! Frontier 24 (structure_discovery) ended on a meta-ceiling: a degree-2 relation on a HIDDEN pair
//! (2,5) that the fixed (inner ⊗ outer) menu could not route (best 0.591), because the menu's
//! relational inner is pinned to the focal pair (0,1). This probe grows the menu just enough to
//! escape that *specific* ceiling, with certification, and then shows the escape RELOCATES the wall.
//!
//! Growable family: a pair-relation inner φ(i,j) = [c_i, c_j, c_i·c_j] for every pair (i,j) — the
//! degree-2 features of one pair. A linear readout over φ(i,j) is the "outer".
//!
//! The loop:
//!   1. DISCOVER  — search all pairs; fit the readout on train, select the pair by validation acc.
//!   2. CERTIFY   — (escape) the chosen pair solves the target on held-out TEST where the fixed menu
//!                  sat at chance; (irreducibility) the new inner's cross-term c_i·c_j is NOT
//!                  reconstructible from the existing menu inners (held-out R² low) — wcore's
//!                  `reducible` test, lifted from opcode programs to inner transforms. Kill-test:
//!                  adding the pair makes its own cross-term trivially reconstructible (non-vacuous).
//!   3. PROMOTE   — add the certified pair to the menu; re-select → the target is now solved.
//!
//! Then target-2 (a HIDDEN TRIPLE) shows the pair-family's OWN bottom: no single pair escapes it.
//! Target-3 grows arity again — triple-relation φ(i,j,k) = [c_i−μ, c_j−μ, c_k−μ, triple-product] —
//! with the same discover / certify / promote loop against the pair-grown menu. Target-4 shows the
//! triple-family's own bottom on a hidden quad (0,4,5,7). Target-5 grows quad-relation
//! φ(i,j,k,l) = [c_i−μ, …, quad-product] with the same loop against the triple-grown menu.
//! Target-6 shows the quad-family's own bottom on a hidden quint (0,1,2,3,6).
//! The wall moved from "which operator" (F24) → "which pair" → "which triple" → "which quad" →
//! which arity (new bottom). Escape of a named ceiling, not repeal of the law.
//!
//! Run: zig build menu-growth --release=fast

const std = @import("std");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const THETA: f64 = 0.40;
const MID: f64 = 2.5;
const NSAMP: usize = 9000;
const NTR: usize = 4500; // train
const NVA: usize = 6750; // val end ([NTR,NVA) val, [NVA,NSAMP) test)

const HIDDEN_PAIR = [2]usize{ 2, 5 };
const HIDDEN_TRIPLE = [3]usize{ 1, 3, 6 };
const HIDDEN_QUAD = [4]usize{ 0, 4, 5, 7 };
const HIDDEN_QUINT = [5]usize{ 0, 1, 2, 3, 6 };
const MAXMENU: usize = 28; // 12 fixed + 3 pair + 4 triple + 5 quad + spare

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
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

// logistic classifier: fit on train, return accuracy on [lo,hi)
fn fitLogit(X: []const []f64, Y: []const f64, dim: usize, epochs: usize, lr: f64, w: []f64) void {
    @memset(w[0 .. dim + 1], 0);
    for (0..epochs) |_| for (0..NTR) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        const e = sigmoid(z) - Y[s];
        for (0..dim) |j| w[j] -= lr * e * X[s][j];
        w[dim] -= lr * e;
    };
}
fn accLogit(X: []const []f64, Y: []const f64, w: []const f64, dim: usize, lo: usize, hi: usize) f64 {
    var c: usize = 0;
    for (lo..hi) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        if ((z >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(hi - lo));
}

// linear regression (identity activation): fit on train, return held-out R² on [lo,hi)
fn fitLinReg(X: []const []f64, t: []const f64, dim: usize, epochs: usize, lr: f64, w: []f64) void {
    @memset(w[0 .. dim + 1], 0);
    for (0..epochs) |_| for (0..NTR) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        const e = z - t[s];
        for (0..dim) |j| w[j] -= lr * e * X[s][j];
        w[dim] -= lr * e;
    };
}
fn r2(X: []const []f64, t: []const f64, w: []const f64, dim: usize, lo: usize, hi: usize) f64 {
    var mu: f64 = 0;
    for (lo..hi) |s| mu += t[s];
    mu /= @floatFromInt(hi - lo);
    var ss_res: f64 = 0;
    var ss_tot: f64 = 0;
    for (lo..hi) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        ss_res += (t[s] - z) * (t[s] - z);
        ss_tot += (t[s] - mu) * (t[s] - mu);
    }
    return 1.0 - ss_res / @max(1e-9, ss_tot);
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

    var prng = std.Random.DefaultPrng.init(0x9E3B1D0FA5172C44);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    };

    // ── the fixed menu's 6 inner scalars, + a degree-2 expansion [s, s²] = 12-dim joint readout ──
    const menuX = try alloc.alloc([]f64, NSAMP); // 6 raw menu inners
    const menuX2 = try alloc.alloc([]f64, NSAMP); // 12: the 6 + their squares (the menu's best poly readout)
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
        const m = [6]f64{
            @floatFromInt(cnt),
            @floatFromInt(sm),
            @floatFromInt(mx),
            @floatFromInt(inv),
            @sin(THETA * (@as(f64, @floatFromInt(g[1])) - @as(f64, @floatFromInt(g[0])))),
            @as(f64, @floatFromInt(g[0])) * @as(f64, @floatFromInt(g[1])),
        };
        menuX[s] = try alloc.alloc(f64, 6);
        @memcpy(menuX[s], &m);
        menuX2[s] = try alloc.alloc(f64, 12);
        for (0..6) |k| {
            menuX2[s][k] = m[k];
            menuX2[s][6 + k] = m[k] * m[k];
        }
    }
    standardize(menuX, 6);
    standardize(menuX2, 12);

    // ── targets ──
    const Y1 = try alloc.alloc(f64, NSAMP); // hidden PAIR (2,5): sign((c2−mid)(c5−mid))>0
    const Y2 = try alloc.alloc(f64, NSAMP); // hidden TRIPLE (1,3,6): sign of triple product >0
    const Y3 = try alloc.alloc(f64, NSAMP); // hidden QUAD (0,4,5,7): sign of quad product >0
    const Y4 = try alloc.alloc(f64, NSAMP); // hidden QUINT (0,1,2,3,6): sign of quint product >0
    for (0..NSAMP) |s| {
        const g = grid[s];
        const a = @as(f64, @floatFromInt(g[HIDDEN_PAIR[0]])) - MID;
        const b = @as(f64, @floatFromInt(g[HIDDEN_PAIR[1]])) - MID;
        Y1[s] = if (a * b > 0) 1.0 else 0.0;
        const p = (@as(f64, @floatFromInt(g[HIDDEN_TRIPLE[0]])) - MID) *
            (@as(f64, @floatFromInt(g[HIDDEN_TRIPLE[1]])) - MID) *
            (@as(f64, @floatFromInt(g[HIDDEN_TRIPLE[2]])) - MID);
        Y2[s] = if (p > 0) 1.0 else 0.0;
        const q = (@as(f64, @floatFromInt(g[HIDDEN_QUAD[0]])) - MID) *
            (@as(f64, @floatFromInt(g[HIDDEN_QUAD[1]])) - MID) *
            (@as(f64, @floatFromInt(g[HIDDEN_QUAD[2]])) - MID) *
            (@as(f64, @floatFromInt(g[HIDDEN_QUAD[3]])) - MID);
        Y3[s] = if (q > 0) 1.0 else 0.0;
        const r = (@as(f64, @floatFromInt(g[HIDDEN_QUINT[0]])) - MID) *
            (@as(f64, @floatFromInt(g[HIDDEN_QUINT[1]])) - MID) *
            (@as(f64, @floatFromInt(g[HIDDEN_QUINT[2]])) - MID) *
            (@as(f64, @floatFromInt(g[HIDDEN_QUINT[3]])) - MID) *
            (@as(f64, @floatFromInt(g[HIDDEN_QUINT[4]])) - MID);
        Y4[s] = if (r > 0) 1.0 else 0.0;
    }

    var w: [MAXMENU + 1]f64 = undefined; // scratch (max dim 28)

    // reusable pair/triple/quad feature matrices
    const pf = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| pf[s] = try alloc.alloc(f64, 3);
    const tf = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| tf[s] = try alloc.alloc(f64, 4);
    const qf = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| qf[s] = try alloc.alloc(f64, 5);

    // pair-grown menu: fixed 12 + promoted pair (2,5) inner [c2, c5, c2·c5]
    const menuPair = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| {
        menuPair[s] = try alloc.alloc(f64, 15);
        @memcpy(menuPair[s][0..12], menuX2[s]);
        const c2: f64 = @as(f64, @floatFromInt(grid[s][HIDDEN_PAIR[0]]));
        const c5: f64 = @as(f64, @floatFromInt(grid[s][HIDDEN_PAIR[1]]));
        menuPair[s][12] = c2;
        menuPair[s][13] = c5;
        menuPair[s][14] = c2 * c5;
    }
    standardize(menuPair, 15);

    // evaluate one pair (i,j) on target Y: fit readout on train, return {val,test}
    const PairRes = struct { val: f64, tst: f64 };
    const Eval = struct {
        fn pair(pfm: []const []f64, g: []const [NCELL]u8, i: usize, j: usize, Y: []const f64, ws: []f64) PairRes {
            for (0..NSAMP) |s| {
                const ci: f64 = @floatFromInt(g[s][i]);
                const cj: f64 = @floatFromInt(g[s][j]);
                pfm[s][0] = ci;
                pfm[s][1] = cj;
                pfm[s][2] = ci * cj;
            }
            standardize(@constCast(pfm), 3);
            fitLogit(pfm, Y, 3, 160, 0.04, ws);
            return .{ .val = accLogit(pfm, Y, ws, 3, NTR, NVA), .tst = accLogit(pfm, Y, ws, 3, NVA, NSAMP) };
        }
        fn triple(tfm: []const []f64, g: []const [NCELL]u8, i: usize, j: usize, k: usize, Y: []const f64, ws: []f64) PairRes {
            for (0..NSAMP) |s| {
                const a: f64 = @as(f64, @floatFromInt(g[s][i])) - MID;
                const b: f64 = @as(f64, @floatFromInt(g[s][j])) - MID;
                const c: f64 = @as(f64, @floatFromInt(g[s][k])) - MID;
                tfm[s][0] = a;
                tfm[s][1] = b;
                tfm[s][2] = c;
                tfm[s][3] = a * b * c;
            }
            standardize(@constCast(tfm), 4);
            fitLogit(tfm, Y, 4, 200, 0.03, ws);
            return .{ .val = accLogit(tfm, Y, ws, 4, NTR, NVA), .tst = accLogit(tfm, Y, ws, 4, NVA, NSAMP) };
        }
        fn quad(qfm: []const []f64, g: []const [NCELL]u8, i: usize, j: usize, k: usize, l: usize, Y: []const f64, ws: []f64) PairRes {
            for (0..NSAMP) |s| {
                const a: f64 = @as(f64, @floatFromInt(g[s][i])) - MID;
                const b: f64 = @as(f64, @floatFromInt(g[s][j])) - MID;
                const c: f64 = @as(f64, @floatFromInt(g[s][k])) - MID;
                const d: f64 = @as(f64, @floatFromInt(g[s][l])) - MID;
                qfm[s][0] = a;
                qfm[s][1] = b;
                qfm[s][2] = c;
                qfm[s][3] = d;
                qfm[s][4] = a * b * c * d;
            }
            standardize(@constCast(qfm), 5);
            fitLogit(qfm, Y, 5, 220, 0.025, ws);
            return .{ .val = accLogit(qfm, Y, ws, 5, NTR, NVA), .tst = accLogit(qfm, Y, ws, 5, NVA, NSAMP) };
        }
    };

    try out.print("=== Phase B (#3): certified menu-growth — discover the pair, certify, promote ===\n\n", .{});
    try out.print("NCELL={d} | hidden pair ({d},{d}) | hidden triple ({d},{d},{d}) | train/val/test {d}/{d}/{d}\n", .{ NCELL, HIDDEN_PAIR[0], HIDDEN_PAIR[1], HIDDEN_TRIPLE[0], HIDDEN_TRIPLE[1], HIDDEN_TRIPLE[2], NTR, NVA - NTR, NSAMP - NVA });
    try out.print("growable family (pairs):   φ(i,j)=[c_i, c_j, c_i·c_j], all {d} pairs; outer=linear readout\n", .{NCELL * (NCELL - 1) / 2});
    try out.print("growable family (triples): φ(i,j,k)=[c_i−μ, c_j−μ, c_k−μ, triple-product], all {d} triples\n", .{NCELL * (NCELL - 1) * (NCELL - 2) / 6});
    try out.print("growable family (quads):   φ(i,j,k,l)=[c_i−μ, …, quad-product], all {d} quads\n\n", .{NCELL * (NCELL - 1) * (NCELL - 2) * (NCELL - 3) / 24});

    // ════════════════ TARGET 1 — the hidden PAIR (Frontier-24's ceiling) ════════════════
    try out.print("──────── TARGET 1: hidden-pair predicate (Frontier-24 menu ceiling was 0.591) ────────\n", .{});

    // fixed-menu baseline: best the WHOLE menu can do (joint degree-2 readout over all 6 inners)
    fitLogit(menuX2, Y1, 12, 240, 0.02, &w);
    const menu_base1 = accLogit(menuX2, Y1, &w, 12, NVA, NSAMP);

    // DISCOVER: search all pairs, select by validation
    var best_val: f64 = -1;
    var bi: usize = 0;
    var bj: usize = 1;
    var best_tst: f64 = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        const r = Eval.pair(pf, grid, i, j, Y1, &w);
        if (r.val > best_val) {
            best_val = r.val;
            best_tst = r.tst;
            bi = i;
            bj = j;
        }
    };
    try out.print("  fixed menu (joint degree-2 over 6 inners):  test {d:.3}   (chance {d:.3})\n", .{ menu_base1, chanceOf(Y1) });
    try out.print("  DISCOVER: best pair = ({d},{d})  val {d:.3}  test {d:.3}\n", .{ bi, bj, best_val, best_tst });

    // CERTIFY escape
    const escape1 = best_tst >= 0.90 and menu_base1 < 0.70;

    // CERTIFY irreducibility (wcore's `reducible`, lifted): can the menu's FULL degree-2 readout
    // (6 inners + their squares, incl. sum²) reconstruct the new cross-term c_bi·c_bj? Standardize
    // the target for numerical stability (R² is scale-invariant).
    const crossZ = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| crossZ[s] = @as(f64, @floatFromInt(grid[s][bi])) * @as(f64, @floatFromInt(grid[s][bj]));
    {
        var mu: f64 = 0;
        for (0..NTR) |s| mu += crossZ[s];
        mu /= @floatFromInt(NTR);
        var sd: f64 = 0;
        for (0..NTR) |s| sd += (crossZ[s] - mu) * (crossZ[s] - mu);
        sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
        for (0..NSAMP) |s| crossZ[s] = (crossZ[s] - mu) / sd;
    }
    fitLinReg(menuX2, crossZ, 12, 500, 0.01, &w);
    const recon_r2 = r2(menuX2, crossZ, &w, 12, NVA, NSAMP);
    // kill-test: append the cross-term itself as a 13th feature → reconstruction must become trivial.
    const menuPlus = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| {
        menuPlus[s] = try alloc.alloc(f64, 13);
        @memcpy(menuPlus[s][0..12], menuX2[s]);
        menuPlus[s][12] = crossZ[s];
    }
    var wk: [16]f64 = undefined;
    fitLinReg(menuPlus, crossZ, 13, 500, 0.01, &wk);
    const kill_r2 = r2(menuPlus, crossZ, &wk, 13, NVA, NSAMP);
    const irreducible1 = recon_r2 < 0.40 and kill_r2 > 0.90 and menu_base1 < chanceOf(Y1) + 0.10;

    try out.print("  CERTIFY escape:        {s}  (new pair {d:.3} ≥ 0.90, menu {d:.3} < 0.70)\n", .{ if (escape1) "PASS" else "fail", best_tst, menu_base1 });
    try out.print("  CERTIFY irreducible:   {s}  (menu°2 reconstructs c{d}·c{d}: held-out R²={d:.3} < 0.40,\n", .{ if (irreducible1) "PASS" else "fail", bi, bj, recon_r2 });
    try out.print("                          behavioral: menu {d:.3} ≈ chance {d:.3}; kill-test menu+cross R²={d:.3} > 0.90 → non-vacuous)\n", .{ menu_base1, chanceOf(Y1), kill_r2 });

    // PROMOTE + re-select (the pair is now in the menu; the target is solved)
    const promoted1 = escape1 and irreducible1 and (bi == HIDDEN_PAIR[0] and bj == HIDDEN_PAIR[1]);
    try out.print("  PROMOTE: add pair-relation ({d},{d}) to the menu → ceiling 0.591 → {d:.3}.  {s}\n\n", .{ bi, bj, best_tst, if (promoted1) "CEILING BROKEN ✓" else "incomplete ✗" });

    // ════════════════ TARGET 2 — the hidden TRIPLE (the pair-family's own bottom) ════════════════
    try out.print("──────── TARGET 2: hidden-TRIPLE predicate (the pair-family's own ceiling) ────────\n", .{});
    fitLogit(menuX2, Y2, 12, 240, 0.02, &w);
    const menu_base2 = accLogit(menuX2, Y2, &w, 12, NVA, NSAMP);
    var best_val2: f64 = -1;
    var bi2: usize = 0;
    var bj2: usize = 1;
    var best_tst2: f64 = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        const r = Eval.pair(pf, grid, i, j, Y2, &w);
        if (r.val > best_val2) {
            best_val2 = r.val;
            best_tst2 = r.tst;
            bi2 = i;
            bj2 = j;
        }
    };
    try out.print("  fixed menu:                 test {d:.3}   (chance {d:.3})\n", .{ menu_base2, chanceOf(Y2) });
    try out.print("  best PAIR (the grown family): ({d},{d}) test {d:.3}  → CEILING: no pair reaches it\n\n", .{ bi2, bj2, best_tst2 });

    // ════════════════ TARGET 3 — certified TRIPLE growth (break the pair-family ceiling) ════════════════
    try out.print("──────── TARGET 3: hidden-TRIPLE predicate — certified triple-relation growth ────────\n", .{});

    // pair-grown menu baseline on the triple target
    fitLogit(menuPair, Y2, 15, 240, 0.02, &w);
    const pair_menu_base = accLogit(menuPair, Y2, &w, 15, NVA, NSAMP);

    // DISCOVER: search all triples, select by validation
    var best_val3: f64 = -1;
    var ti: usize = 0;
    var tj: usize = 1;
    var tk: usize = 2;
    var best_tst3: f64 = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| for (j + 1..NCELL) |k| {
        const r = Eval.triple(tf, grid, i, j, k, Y2, &w);
        if (r.val > best_val3) {
            best_val3 = r.val;
            best_tst3 = r.tst;
            ti = i;
            tj = j;
            tk = k;
        }
    };
    try out.print("  pair-grown menu (fixed+pair): test {d:.3}   (chance {d:.3})\n", .{ pair_menu_base, chanceOf(Y2) });
    try out.print("  DISCOVER: best triple = ({d},{d},{d})  val {d:.3}  test {d:.3}\n", .{ ti, tj, tk, best_val3, best_tst3 });

    // CERTIFY escape
    const escape3 = best_tst3 >= 0.90 and pair_menu_base < 0.70;

    // CERTIFY irreducibility: triple cross-term not reconstructible from pair-grown menu
    const tripleCrossZ = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| {
        const a: f64 = @as(f64, @floatFromInt(grid[s][ti])) - MID;
        const b: f64 = @as(f64, @floatFromInt(grid[s][tj])) - MID;
        const c: f64 = @as(f64, @floatFromInt(grid[s][tk])) - MID;
        tripleCrossZ[s] = a * b * c;
    }
    {
        var mu: f64 = 0;
        for (0..NTR) |s| mu += tripleCrossZ[s];
        mu /= @floatFromInt(NTR);
        var sd: f64 = 0;
        for (0..NTR) |s| sd += (tripleCrossZ[s] - mu) * (tripleCrossZ[s] - mu);
        sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
        for (0..NSAMP) |s| tripleCrossZ[s] = (tripleCrossZ[s] - mu) / sd;
    }
    fitLinReg(menuPair, tripleCrossZ, 15, 500, 0.01, &w);
    const recon_r2_3 = r2(menuPair, tripleCrossZ, &w, 15, NVA, NSAMP);
    const menuPlus3 = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| {
        menuPlus3[s] = try alloc.alloc(f64, 16);
        @memcpy(menuPlus3[s][0..15], menuPair[s]);
        menuPlus3[s][15] = tripleCrossZ[s];
    }
    var wk3: [MAXMENU + 1]f64 = undefined;
    fitLinReg(menuPlus3, tripleCrossZ, 16, 500, 0.01, &wk3);
    const kill_r2_3 = r2(menuPlus3, tripleCrossZ, &wk3, 16, NVA, NSAMP);
    const irreducible3 = recon_r2_3 < 0.40 and kill_r2_3 > 0.90 and pair_menu_base < chanceOf(Y2) + 0.10;

    try out.print("  CERTIFY escape:        {s}  (new triple {d:.3} ≥ 0.90, pair-menu {d:.3} < 0.70)\n", .{ if (escape3) "PASS" else "fail", best_tst3, pair_menu_base });
    try out.print("  CERTIFY irreducible:   {s}  (pair-menu reconstructs triple-cross: held-out R²={d:.3} < 0.40,\n", .{ if (irreducible3) "PASS" else "fail", recon_r2_3 });
    try out.print("                          behavioral: pair-menu {d:.3} ≈ chance {d:.3}; kill-test menu+triple R²={d:.3} > 0.90 → non-vacuous)\n", .{ pair_menu_base, chanceOf(Y2), kill_r2_3 });

    const promoted3 = escape3 and irreducible3 and (ti == HIDDEN_TRIPLE[0] and tj == HIDDEN_TRIPLE[1] and tk == HIDDEN_TRIPLE[2]);
    try out.print("  PROMOTE: add triple-relation ({d},{d},{d}) to menu → pair-ceiling → {d:.3}.  {s}\n\n", .{ ti, tj, tk, best_tst3, if (promoted3) "CEILING BROKEN ✓" else "incomplete ✗" });

    // ════════════════ TARGET 4 — hidden QUAD (the triple-family's own bottom) ════════════════
    try out.print("──────── TARGET 4: hidden-QUAD predicate (the triple-family's own ceiling) ────────\n", .{});

    // triple-grown menu: pair-grown 15 + promoted triple inner
    const menuTriple = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| {
        menuTriple[s] = try alloc.alloc(f64, 19);
        @memcpy(menuTriple[s][0..15], menuPair[s]);
        const a: f64 = @as(f64, @floatFromInt(grid[s][HIDDEN_TRIPLE[0]])) - MID;
        const b: f64 = @as(f64, @floatFromInt(grid[s][HIDDEN_TRIPLE[1]])) - MID;
        const c: f64 = @as(f64, @floatFromInt(grid[s][HIDDEN_TRIPLE[2]])) - MID;
        menuTriple[s][15] = a;
        menuTriple[s][16] = b;
        menuTriple[s][17] = c;
        menuTriple[s][18] = a * b * c;
    }
    standardize(menuTriple, 19);
    fitLogit(menuTriple, Y3, 19, 240, 0.02, &w);
    const triple_menu_base = accLogit(menuTriple, Y3, &w, 19, NVA, NSAMP);

    var best_val4: f64 = -1;
    var tri_i: usize = 0;
    var tri_j: usize = 1;
    var tri_k: usize = 2;
    var best_tst4: f64 = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| for (j + 1..NCELL) |k| {
        const r = Eval.triple(tf, grid, i, j, k, Y3, &w);
        if (r.val > best_val4) {
            best_val4 = r.val;
            best_tst4 = r.tst;
            tri_i = i;
            tri_j = j;
            tri_k = k;
        }
    };

    // control: quad-relation inner on the true hidden quad
    const quad_ctrl = Eval.quad(qf, grid, HIDDEN_QUAD[0], HIDDEN_QUAD[1], HIDDEN_QUAD[2], HIDDEN_QUAD[3], Y3, &w);

    try out.print("  triple-grown menu:              test {d:.3}   (chance {d:.3})\n", .{ triple_menu_base, chanceOf(Y3) });
    try out.print("  best TRIPLE (the grown family): ({d},{d},{d}) test {d:.3}  → CEILING: no triple reaches it\n", .{ tri_i, tri_j, tri_k, best_tst4 });
    try out.print("  a QUAD-relation inner:          test {d:.3}  → the NEXT family escapes (wall relocated, not repealed)\n\n", .{quad_ctrl.tst});

    // ════════════════ TARGET 5 — certified QUAD growth (break the triple-family ceiling) ════════════════
    try out.print("──────── TARGET 5: hidden-QUAD predicate — certified quad-relation growth ────────\n", .{});

    // DISCOVER: search all quads, select by validation
    var best_val5: f64 = -1;
    var qi: usize = 0;
    var qj: usize = 1;
    var qk: usize = 2;
    var ql: usize = 3;
    var best_tst5: f64 = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| for (j + 1..NCELL) |k| for (k + 1..NCELL) |l| {
        const r = Eval.quad(qf, grid, i, j, k, l, Y3, &w);
        if (r.val > best_val5) {
            best_val5 = r.val;
            best_tst5 = r.tst;
            qi = i;
            qj = j;
            qk = k;
            ql = l;
        }
    };
    try out.print("  triple-grown menu (fixed+pair+triple): test {d:.3}   (chance {d:.3})\n", .{ triple_menu_base, chanceOf(Y3) });
    try out.print("  DISCOVER: best quad = ({d},{d},{d},{d})  val {d:.3}  test {d:.3}\n", .{ qi, qj, qk, ql, best_val5, best_tst5 });

    // CERTIFY escape
    const escape5 = best_tst5 >= 0.90 and triple_menu_base < 0.70;

    // CERTIFY irreducibility: quad cross-term not reconstructible from triple-grown menu
    const quadCrossZ = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| {
        const a: f64 = @as(f64, @floatFromInt(grid[s][qi])) - MID;
        const b: f64 = @as(f64, @floatFromInt(grid[s][qj])) - MID;
        const c: f64 = @as(f64, @floatFromInt(grid[s][qk])) - MID;
        const d: f64 = @as(f64, @floatFromInt(grid[s][ql])) - MID;
        quadCrossZ[s] = a * b * c * d;
    }
    {
        var mu: f64 = 0;
        for (0..NTR) |s| mu += quadCrossZ[s];
        mu /= @floatFromInt(NTR);
        var sd: f64 = 0;
        for (0..NTR) |s| sd += (quadCrossZ[s] - mu) * (quadCrossZ[s] - mu);
        sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
        for (0..NSAMP) |s| quadCrossZ[s] = (quadCrossZ[s] - mu) / sd;
    }
    fitLinReg(menuTriple, quadCrossZ, 19, 500, 0.01, &w);
    const recon_r2_5 = r2(menuTriple, quadCrossZ, &w, 19, NVA, NSAMP);
    const menuPlus5 = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| {
        menuPlus5[s] = try alloc.alloc(f64, 20);
        @memcpy(menuPlus5[s][0..19], menuTriple[s]);
        menuPlus5[s][19] = quadCrossZ[s];
    }
    var wk5: [MAXMENU + 1]f64 = undefined;
    fitLinReg(menuPlus5, quadCrossZ, 20, 500, 0.01, &wk5);
    const kill_r2_5 = r2(menuPlus5, quadCrossZ, &wk5, 20, NVA, NSAMP);
    const irreducible5 = recon_r2_5 < 0.40 and kill_r2_5 > 0.90 and triple_menu_base < chanceOf(Y3) + 0.10;

    try out.print("  CERTIFY escape:        {s}  (new quad {d:.3} ≥ 0.90, triple-menu {d:.3} < 0.70)\n", .{ if (escape5) "PASS" else "fail", best_tst5, triple_menu_base });
    try out.print("  CERTIFY irreducible:   {s}  (triple-menu reconstructs quad-cross: held-out R²={d:.3} < 0.40,\n", .{ if (irreducible5) "PASS" else "fail", recon_r2_5 });
    try out.print("                          behavioral: triple-menu {d:.3} ≈ chance {d:.3}; kill-test menu+quad R²={d:.3} > 0.90 → non-vacuous)\n", .{ triple_menu_base, chanceOf(Y3), kill_r2_5 });

    const promoted5 = escape5 and irreducible5 and
        (qi == HIDDEN_QUAD[0] and qj == HIDDEN_QUAD[1] and qk == HIDDEN_QUAD[2] and ql == HIDDEN_QUAD[3]);
    try out.print("  PROMOTE: add quad-relation ({d},{d},{d},{d}) to menu → triple-ceiling → {d:.3}.  {s}\n\n", .{ qi, qj, qk, ql, best_tst5, if (promoted5) "CEILING BROKEN ✓" else "incomplete ✗" });

    // ════════════════ TARGET 6 — hidden QUINT (the quad-family's own bottom) ════════════════
    try out.print("──────── TARGET 6: hidden-QUINT predicate (the quad-family's own ceiling) ────────\n", .{});

    // quad-grown menu: triple-grown 19 + promoted quad inner
    const menuQuad = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| {
        menuQuad[s] = try alloc.alloc(f64, 24);
        @memcpy(menuQuad[s][0..19], menuTriple[s]);
        const a: f64 = @as(f64, @floatFromInt(grid[s][HIDDEN_QUAD[0]])) - MID;
        const b: f64 = @as(f64, @floatFromInt(grid[s][HIDDEN_QUAD[1]])) - MID;
        const c: f64 = @as(f64, @floatFromInt(grid[s][HIDDEN_QUAD[2]])) - MID;
        const d: f64 = @as(f64, @floatFromInt(grid[s][HIDDEN_QUAD[3]])) - MID;
        menuQuad[s][19] = a;
        menuQuad[s][20] = b;
        menuQuad[s][21] = c;
        menuQuad[s][22] = d;
        menuQuad[s][23] = a * b * c * d;
    }
    standardize(menuQuad, 24);
    fitLogit(menuQuad, Y4, 24, 240, 0.02, &w);
    const quad_menu_base = accLogit(menuQuad, Y4, &w, 24, NVA, NSAMP);

    var best_val6: f64 = -1;
    var quad_i: usize = 0;
    var quad_j: usize = 1;
    var quad_k: usize = 2;
    var quad_l: usize = 3;
    var best_tst6: f64 = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| for (j + 1..NCELL) |k| for (k + 1..NCELL) |l| {
        const r = Eval.quad(qf, grid, i, j, k, l, Y4, &w);
        if (r.val > best_val6) {
            best_val6 = r.val;
            best_tst6 = r.tst;
            quad_i = i;
            quad_j = j;
            quad_k = k;
            quad_l = l;
        }
    };

    // control: quint-relation inner on the true hidden quint
    const quintf = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| quintf[s] = try alloc.alloc(f64, 6);
    for (0..NSAMP) |s| {
        const a: f64 = @as(f64, @floatFromInt(grid[s][HIDDEN_QUINT[0]])) - MID;
        const b: f64 = @as(f64, @floatFromInt(grid[s][HIDDEN_QUINT[1]])) - MID;
        const c: f64 = @as(f64, @floatFromInt(grid[s][HIDDEN_QUINT[2]])) - MID;
        const d: f64 = @as(f64, @floatFromInt(grid[s][HIDDEN_QUINT[3]])) - MID;
        const e: f64 = @as(f64, @floatFromInt(grid[s][HIDDEN_QUINT[4]])) - MID;
        quintf[s][0] = a;
        quintf[s][1] = b;
        quintf[s][2] = c;
        quintf[s][3] = d;
        quintf[s][4] = e;
        quintf[s][5] = a * b * c * d * e;
    }
    standardize(quintf, 6);
    fitLogit(quintf, Y4, 6, 240, 0.025, &w);
    const quint_tst = accLogit(quintf, Y4, &w, 6, NVA, NSAMP);

    try out.print("  quad-grown menu:              test {d:.3}   (chance {d:.3})\n", .{ quad_menu_base, chanceOf(Y4) });
    try out.print("  best QUAD (the grown family): ({d},{d},{d},{d}) test {d:.3}  → CEILING: no quad reaches it\n", .{ quad_i, quad_j, quad_k, quad_l, best_tst6 });
    try out.print("  a QUINT-relation inner:       test {d:.3}  → the NEXT family escapes (wall relocated, not repealed)\n\n", .{quint_tst});

    // ════════════════ VERDICT ════════════════
    try out.print("════════════════════ VERDICT ════════════════════\n", .{});
    if (promoted1) {
        try out.print("TARGET 1 — POSITIVE. The forge DISCOVERED the right pair ({d},{d}) blind (val-selected),\n", .{ bi, bj });
        try out.print("CERTIFIED it (escape {d:.3}≥0.90 with menu at {d:.3}; irreducible — menu can't reconstruct\n", .{ best_tst, menu_base1 });
        try out.print("c{d}·c{d}, R²={d:.3}, kill-test R²={d:.3}), and PROMOTED it — breaking Frontier-24's 0.591 ceiling\n", .{ bi, bj, recon_r2, kill_r2 });
        try out.print("to {d:.3}. A growable menu escapes the SPECIFIC ceiling a fixed menu could not.\n\n", .{best_tst});
    } else {
        try out.print("TARGET 1 — INCOMPLETE. Inspect: discovered ({d},{d}) tst {d:.3}, escape={}, irreducible={}.\n\n", .{ bi, bj, best_tst, escape1, irreducible1 });
    }
    try out.print("TARGET 2 — the escape RELOCATES the wall. The pair-family (which just escaped target 1)\n", .{});
    try out.print("has its OWN bottom: no pair reaches the hidden triple (best {d:.3}).\n\n", .{best_tst2});
    if (promoted3) {
        try out.print("TARGET 3 — POSITIVE. The forge DISCOVERED the right triple ({d},{d},{d}) blind (val-selected),\n", .{ ti, tj, tk });
        try out.print("CERTIFIED it (escape {d:.3}≥0.90 with pair-menu at {d:.3}; irreducible — pair-menu can't reconstruct\n", .{ best_tst3, pair_menu_base });
        try out.print("triple-cross, R²={d:.3}, kill-test R²={d:.3}), and PROMOTED it — breaking the pair-family ceiling\n", .{ recon_r2_3, kill_r2_3 });
        try out.print("to {d:.3}. Triple-arity menu-growth escapes the SPECIFIC ceiling pairs could not.\n\n", .{best_tst3});
    } else {
        try out.print("TARGET 3 — INCOMPLETE. Inspect: discovered ({d},{d},{d}) tst {d:.3}, escape={}, irreducible={}.\n\n", .{ ti, tj, tk, best_tst3, escape3, irreducible3 });
    }
    try out.print("TARGET 4 — the escape RELOCATES again. The triple-family that just escaped target 3\n", .{});
    try out.print("has its OWN bottom: no triple reaches the hidden quad (best {d:.3}), while a quad-relation\n", .{best_tst4});
    try out.print("inner does ({d:.3}).\n", .{quad_ctrl.tst});
    if (promoted5) {
        try out.print("TARGET 5 — POSITIVE. The forge DISCOVERED the right quad ({d},{d},{d},{d}) blind (val-selected),\n", .{ qi, qj, qk, ql });
        try out.print("CERTIFIED it (escape {d:.3}≥0.90 with triple-menu at {d:.3}; irreducible — triple-menu can't reconstruct\n", .{ best_tst5, triple_menu_base });
        try out.print("quad-cross, R²={d:.3}, kill-test R²={d:.3}), and PROMOTED it — breaking the triple-family ceiling\n", .{ recon_r2_5, kill_r2_5 });
        try out.print("to {d:.3}. Quad-arity menu-growth escapes the SPECIFIC ceiling triples could not.\n\n", .{best_tst5});
    } else {
        try out.print("TARGET 5 — INCOMPLETE. Inspect: discovered ({d},{d},{d},{d}) tst {d:.3}, escape={}, irreducible={}.\n\n", .{ qi, qj, qk, ql, best_tst5, escape5, irreducible5 });
    }
    try out.print("TARGET 6 — the escape RELOCATES again. The quad-family that just escaped target 5\n", .{});
    try out.print("has its OWN bottom: no quad reaches the hidden quint (best {d:.3}), while a quint-relation\n", .{best_tst6});
    try out.print("inner does ({d:.3}). The ceiling moved: operator (F24) → which-pair → which-triple → which-quad → which-arity.\n", .{quint_tst});
    try out.print("Each growable family is itself a closure with a bottom — exactly the unified ceiling.\n", .{});
    try out.print("Phase C asks whether an OPEN inner-transform forge (no fixed arity) saturates or grows.\n", .{});
    try out.print("\nSee: structure_discovery.md (the ceiling), inventable_substrate_design.md (the plan),\n", .{});
    try out.print("wcore/docs/research/alien_novelty_limit.md (the terminal purist answer), CLOSURE_PRINCIPLE.md.\n", .{});
}
