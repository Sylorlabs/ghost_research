//! Phase C (#3) — the open inner-transform forge: does promotion SATURATE or GROW?
//!
//! Phase B fixed the arity at pairs; the wall relocated to triples. Phase C removes the fixed arity:
//! an OPEN forge over a monomial substrate of inner transforms, and the decisive measurement —
//! does iterated certified promotion bottom out (cover the substrate's closure and stop, as wcore's
//! atom-forge did over its opcode VM) or grow unboundedly?
//!
//! Substrate. An inner transform is a centered-cell-subset MONOMIAL: for a subset S ⊆ cells,
//!   φ_S(grid) = Π_{i∈S} (c_i − MID).
//! Base atom set = the 8 singletons (degree 1). The forge may promote any subset (any degree) — the
//! arity is NOT fixed. This is the cleanest possible inventable substrate: its primitives (subsets)
//! are themselves composable, and "degree" is unbounded a priori.
//!
//! Target zoo (coverage = a logistic readout over the current atoms reaches ≥0.90 held-out test):
//!   T1 sign φ_{2,5}      (degree 2)   T2 sign φ_{1,3,6}   (degree 3)
//!   T3 sign φ_{0,4,5,7}  (degree 4)   T4 sign (c3−MID)    (degree 1, base-covered)
//!   T5 parity-of-count   (NOT a monomial sign — the cross-family witness)
//!
//! Forge loop (objective: irreducible AND useful — the algebraic-irreducibility driver wcore did not
//! run in this form). Each round, for every unsolved target: discover the subset whose φ_S best
//! classifies it (validation), CERTIFY escape (adding φ_S lifts held-out test ≥0.90 where the current
//! set sat at chance) AND irreducibility (φ_S not reconstructible from the current atoms, held-out
//! R²<0.40), then PROMOTE. Stop when a full pass promotes nothing — saturation.
//!
//! Contrast: a NOVELTY-ONLY driver (promote the most-irreducible atom, target-agnostic) — to show the
//! novelty↔usefulness tension (wcore §21–22): pure novelty promotes atoms that don't improve coverage.
//!
//! Run: zig build inner-forge --release=fast

const std = @import("std");
const oml = @import("operator_menu_lib.zig");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
const NSAMP: usize = 7000;
const NTR: usize = 3500;
const NVA: usize = 5250;
const MAXATOMS: usize = 24;
const MAXOPS: usize = 8;
const MAXDEG: usize = 4;

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn popcount(m: u8) usize {
    return @popCount(m);
}

// centered-subset monomial φ_S
fn phi(g: [NCELL]u8, mask: u8) f64 {
    var p: f64 = 1.0;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) != 0) p *= (@as(f64, @floatFromInt(g[i])) - MID);
    }
    return p;
}

// build feature matrix X[s][0..k] = monomial φ_S + promoted operator features, standardized on train
fn buildFeat(X: [][]f64, grid: []const [NCELL]u8, masks: []const u8, ops: []const oml.PromotedOp) void {
    const nm = masks.len;
    const k = nm + ops.len;
    for (0..NSAMP) |s| {
        for (0..nm) |c| X[s][c] = phi(grid[s], masks[c]);
        for (0..ops.len) |c| X[s][nm + c] = ops[c].eval(grid[s]);
    }
    for (0..k) |c| {
        var mu: f64 = 0;
        for (0..NTR) |s| mu += X[s][c];
        mu /= @floatFromInt(NTR);
        var sd: f64 = 0;
        for (0..NTR) |s| sd += (X[s][c] - mu) * (X[s][c] - mu);
        sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
        for (0..NSAMP) |s| X[s][c] = (X[s][c] - mu) / sd;
    }
}

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

// held-out R² of reconstructing target t from features X[0..dim] (linear regression)
fn reconR2(X: []const []f64, t: []const f64, dim: usize, w: []f64) f64 {
    @memset(w[0 .. dim + 1], 0);
    for (0..400) |_| for (0..NTR) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        const e = z - t[s];
        for (0..dim) |j| w[j] -= 0.01 * e * X[s][j];
        w[dim] -= 0.01 * e;
    };
    var mu: f64 = 0;
    for (NVA..NSAMP) |s| mu += t[s];
    mu /= @floatFromInt(NSAMP - NVA);
    var ssr: f64 = 0;
    var sst: f64 = 0;
    for (NVA..NSAMP) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        ssr += (t[s] - z) * (t[s] - z);
        sst += (t[s] - mu) * (t[s] - mu);
    }
    return 1.0 - ssr / @max(1e-9, sst);
}

const NT = 5;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var prng = std.Random.DefaultPrng.init(0xF0235A11CE0FF1CE);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    };

    // scratch matrices
    const X = try alloc.alloc([]f64, NSAMP); // up to MAXATOMS cols
    const Xrec = try alloc.alloc([]f64, NSAMP); // recon input
    for (0..NSAMP) |s| {
        X[s] = try alloc.alloc(f64, MAXATOMS);
        Xrec[s] = try alloc.alloc(f64, MAXATOMS);
    }
    const phiTgt = try alloc.alloc(f64, NSAMP); // candidate φ as recon target

    // targets
    const hidden = [_]u8{
        (1 << 2) | (1 << 5), // T1 pair
        (1 << 1) | (1 << 3) | (1 << 6), // T2 triple
        (1 << 0) | (1 << 4) | (1 << 5) | (1 << 7), // T3 quad
        (1 << 3), // T4 single
        0, // T5 parity (special)
    };
    const tname = [NT][]const u8{ "T1 sign φ{2,5}  (deg2)", "T2 sign φ{1,3,6} (deg3)", "T3 sign φ{0,4,5,7}(deg4)", "T4 sign(c3−MID) (deg1)", "T5 parity-of-count(≠mono)" };
    const Y = try alloc.alloc([]f64, NT);
    for (0..NT) |t| Y[t] = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| {
        const g = grid[s];
        for (0..4) |t| Y[t][s] = if (phi(g, hidden[t]) > 0) 1.0 else 0.0;
        var cnt: usize = 0;
        for (g) |v| if (v >= THRESH) {
            cnt += 1;
        };
        Y[4][s] = @floatFromInt(cnt & 1);
    }

    var w: [MAXATOMS + 1]f64 = undefined;

    // atom set: start with the 8 singletons (degree 1)
    var atoms: [MAXATOMS]u8 = undefined;
    var natoms: usize = 0;
    for (0..NCELL) |i| {
        atoms[natoms] = @as(u8, 1) << @intCast(i);
        natoms += 1;
    }

    var ops: [MAXOPS]oml.PromotedOp = undefined;
    const nops0: usize = 0;
    const empty_ops = ops[0..nops0];

    const coverage = struct {
        fn f(Xb: [][]f64, grid_: []const [NCELL]u8, masks: []const u8, opv: []const oml.PromotedOp, yv: []const f64, ws: []f64) f64 {
            buildFeat(Xb, grid_, masks, opv);
            const dim = masks.len + opv.len;
            fitLogit(Xb, yv, dim, 150, 0.05, ws);
            return accLogit(Xb, yv, ws, dim, NVA, NSAMP);
        }
    }.f;

    try out.print("=== Phase C (#3): the open inner-transform forge — saturate or grow? ===\n\n", .{});
    try out.print("substrate: centered-subset monomials φ_S; base = 8 singletons (deg1); promote any subset (deg≤{d}).\n", .{MAXDEG});
    try out.print("objective: promote φ_S iff IRREDUCIBLE to current atoms (R²<0.40) AND USEFUL (lifts an unsolved target ≥0.90).\n", .{});
    try out.print("train/val/test {d}/{d}/{d}\n\n", .{ NTR, NVA - NTR, NSAMP - NVA });

    // initial coverage
    try out.print("round 0 (base singletons): coverage = ", .{});
    var solved = [_]bool{false} ** NT;
    var nsolved0: usize = 0;
    for (0..NT) |t| {
        const cov = coverage(X, grid, atoms[0..natoms], empty_ops, Y[t], &w);
        solved[t] = cov >= 0.90;
        if (solved[t]) nsolved0 += 1;
        try out.print("{s}={d:.2}{s}  ", .{ tname[t][0..2], cov, if (solved[t]) "*" else " " });
    }
    try out.print(" → {d}/{d} solved\n\n", .{ nsolved0, NT });

    // ── the forge ──
    var round: usize = 1;
    while (round <= 8) : (round += 1) {
        var promoted = false;
        for (0..NT) |t| {
            if (solved[t]) continue;
            const cov_now = coverage(X, grid, atoms[0..natoms], empty_ops, Y[t], &w);
            if (cov_now >= 0.90) {
                solved[t] = true;
                continue;
            }
            // DISCOVER: best non-atom subset (deg 1..MAXDEG) by validation acc of φ_S ALONE on this target
            var best_val: f64 = -1;
            var best_mask: u8 = 0;
            var mm: u16 = 1;
            while (mm < 256) : (mm += 1) {
                const cand: u8 = @intCast(mm);
                const d = popcount(cand);
                if (d < 1 or d > MAXDEG) continue;
                var is_atom = false;
                for (0..natoms) |a| if (atoms[a] == cand) {
                    is_atom = true;
                };
                if (is_atom) continue;
                const one = [_]u8{cand};
                buildFeat(X, grid, &one, empty_ops);
                fitLogit(X, Y[t], 1, 70, 0.06, &w);
                const v = accLogit(X, Y[t], &w, 1, NTR, NVA);
                if (v > best_val) {
                    best_val = v;
                    best_mask = cand;
                }
            }
            // CERTIFY escape: does adding best_mask lift held-out test ≥0.90 (current set could not)?
            var aug: [MAXATOMS]u8 = undefined;
            @memcpy(aug[0..natoms], atoms[0..natoms]);
            aug[natoms] = best_mask;
            const cov_aug = coverage(X, grid, aug[0 .. natoms + 1], empty_ops, Y[t], &w);
            const escape = cov_aug >= 0.90 and cov_now < 0.70;
            // CERTIFY irreducibility: φ_{best_mask} reconstructible from current atoms?
            for (0..NSAMP) |s| phiTgt[s] = phi(grid[s], best_mask);
            buildFeat(Xrec, grid, atoms[0..natoms], empty_ops);
            const rr = reconR2(Xrec, phiTgt, natoms, &w);
            const irreducible = rr < 0.40;

            if (escape and irreducible) {
                atoms[natoms] = best_mask;
                natoms += 1;
                solved[t] = true;
                promoted = true;
                try out.print("  round {d}: target {s} unsolved ({d:.2}) → DISCOVER φ(mask=0x{X:0>2}, deg {d}); " ++
                    "escape {d:.2}≥0.90, irreducible R²={d:.2}<0.40 → PROMOTE (atoms now {d})\n", .{ round, tname[t][0..2], cov_now, best_mask, popcount(best_mask), cov_aug, rr, natoms });
            } else {
                try out.print("  round {d}: target {s} unsolved ({d:.2}) → best φ(0x{X:0>2}) escape {d:.2} / R²={d:.2} → NO promotion (not certified)\n", .{ round, tname[t][0..2], cov_now, best_mask, cov_aug, rr });
            }
        }
        if (!promoted) {
            try out.print("\n  round {d}: a full pass promoted NOTHING → SATURATED (monomial closure).\n", .{round});
            break;
        }
    }

    // monomial-phase final coverage (before operator escape)
    const t5_mono = coverage(X, grid, atoms[0..natoms], empty_ops, Y[4], &w);
    try out.print("\nmonomial-phase coverage: ", .{});
    var nsolvedM: usize = 0;
    for (0..NT) |t| {
        const cov = coverage(X, grid, atoms[0..natoms], empty_ops, Y[t], &w);
        const sv = cov >= 0.90;
        if (sv) nsolvedM += 1;
        try out.print("{s}={d:.2}{s}  ", .{ tname[t][0..2], cov, if (sv) "*" else " " });
    }
    try out.print(" → {d}/{d} solved; atom set size {d} (started 8)\n", .{ nsolvedM, NT, natoms });

    // ── Fork 1: operator menu escape when monomial forge saturates ──
    try out.print("\n──────── Fork 1: operator menu escape (spectral / Walsh) on saturated targets ────────\n", .{});
    try out.print("  T5 before operator escape: {d:.2}\n", .{t5_mono});

    var nops: usize = nops0;
    var setbuf: [32]u8 = undefined;
    for (0..NT) |t| {
        if (solved[t]) continue;
        const cov_now = coverage(X, grid, atoms[0..natoms], ops[0..nops], Y[t], &w);
        const menu = oml.runMenu(grid, Y[t], phiTgt, NTR, NVA, NSAMP);

        var trial_ops: [MAXOPS]oml.PromotedOp = undefined;
        @memcpy(trial_ops[0..nops], ops[0..nops]);
        trial_ops[nops] = menu.promoted;
        const cov_aug = coverage(X, grid, atoms[0..natoms], trial_ops[0 .. nops + 1], Y[t], &w);

        for (0..NSAMP) |s| phiTgt[s] = menu.promoted.eval(grid[s]);
        buildFeat(Xrec, grid, atoms[0..natoms], ops[0..nops]);
        const rr = reconR2(Xrec, phiTgt, natoms + nops, &w);

        const escape = cov_aug >= 0.90 and cov_now < 0.70;
        const certified = escape and menu.tst >= 0.90 and rr < 0.40;

        const detail: []const u8 = switch (menu.promoted.kind) {
            .spectral => blk: {
                var buf: [64]u8 = undefined;
                const s = try std.fmt.bufPrint(&buf, "cos(ω·#≥{d}), ω={d:.4}", .{ oml.THRESH, menu.promoted.omega });
                break :blk s;
            },
            .walsh => blk: {
                const ws = oml.fmtWalshSet(&setbuf, menu.promoted.walsh_s);
                var buf: [64]u8 = undefined;
                const s = try std.fmt.bufPrint(&buf, "chi{s}", .{ws});
                break :blk s;
            },
        };

        if (certified) {
            ops[nops] = menu.promoted;
            nops += 1;
            solved[t] = true;
            try out.print("  {s}: menu→{s} ({s}) val={d:.2} test={d:.2} escape={d:.2} R²={d:.2} → PROMOTE (ops now {d})\n", .{
                tname[t][0..2], oml.op_name[@intFromEnum(menu.winner)], detail, menu.val, menu.tst, cov_aug, rr, nops,
            });
        } else {
            try out.print("  {s}: menu→{s} ({s}) val={d:.2} test={d:.2} escape={d:.2} R²={d:.2} → NO promotion\n", .{
                tname[t][0..2], oml.op_name[@intFromEnum(menu.winner)], detail, menu.val, menu.tst, cov_aug, rr,
            });
        }
    }

    const t5_after = coverage(X, grid, atoms[0..natoms], ops[0..nops], Y[4], &w);
    try out.print("  T5 after operator escape:  {d:.2}{s}\n", .{ t5_after, if (t5_after >= 0.90) " *" else "" });

    // final coverage (monomials + promoted operators)
    try out.print("\nfinal coverage: ", .{});
    var nsolvedF: usize = 0;
    for (0..NT) |t| {
        const cov = coverage(X, grid, atoms[0..natoms], ops[0..nops], Y[t], &w);
        const sv = cov >= 0.90;
        if (sv) nsolvedF += 1;
        try out.print("{s}={d:.2}{s}  ", .{ tname[t][0..2], cov, if (sv) "*" else " " });
    }
    try out.print(" → {d}/{d} solved; atoms {d} + ops {d}\n", .{ nsolvedF, NT, natoms, nops });

    // ── novelty-only contrast: promote the MOST-irreducible atom, target-agnostic, 3× ──
    try out.print("\n──────── contrast: NOVELTY-ONLY driver (most-irreducible, target-agnostic) ────────\n", .{});
    var natoms2: usize = 8; // fresh base
    var atoms2: [MAXATOMS]u8 = undefined;
    @memcpy(atoms2[0..8], atoms[0..8]);
    for (0..3) |it| {
        var worst_r2: f64 = 2.0;
        var nov_mask: u8 = 0;
        var mm: u16 = 1;
        while (mm < 256) : (mm += 1) {
            const cand: u8 = @intCast(mm);
            const d = popcount(cand);
            if (d < 2 or d > MAXDEG) continue;
            var is_atom = false;
            for (0..natoms2) |a| if (atoms2[a] == cand) {
                is_atom = true;
            };
            if (is_atom) continue;
            for (0..NSAMP) |s| phiTgt[s] = phi(grid[s], cand);
            buildFeat(Xrec, grid, atoms2[0..natoms2], empty_ops);
            const rr = reconR2(Xrec, phiTgt, natoms2, &w);
            if (rr < worst_r2) {
                worst_r2 = rr;
                nov_mask = cand;
            }
        }
        atoms2[natoms2] = nov_mask;
        natoms2 += 1;
        // coverage of targets after this novelty promotion
        var ns: usize = 0;
        for (0..NT) |t| {
            if (coverage(X, grid, atoms2[0..natoms2], empty_ops, Y[t], &w) >= 0.90) ns += 1;
        }
        try out.print("  novelty round {d}: promoted most-irreducible φ(0x{X:0>2}, deg {d}, R²={d:.2}) → target coverage {d}/{d}\n", .{ it + 1, nov_mask, popcount(nov_mask), worst_r2, ns, NT });
    }

    // ── verdict ──
    try out.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    const saturated_at_monomials = nsolvedM == 4 and t5_mono < 0.70;
    const escaped_via_menu = t5_after >= 0.90 and nops > 0;

    try out.print("Fork 1 T5: {d:.2} (monomial saturation) → {d:.2} (after operator menu).\n\n", .{ t5_mono, t5_after });

    if (saturated_at_monomials and escaped_via_menu) {
        try out.print("MONOMIAL SATURATION CONFIRMED, then OPERATOR-MENU ESCAPE. The open forge bottomed at products-of-\n", .{});
        try out.print("cells (4/5 solved, T5 stuck at chance), then the spectral/Walsh menu discovered a certified\n", .{});
        try out.print("cross-family primitive and promoted it (test≥0.90, irreducible R²<0.40). The closure boundary\n", .{});
        try out.print("is real for monomials alone; the menu is the principled escape hatch wired in at saturation.\n\n", .{});
    } else if (saturated_at_monomials) {
        try out.print("SATURATES at monomial closure; operator menu did NOT certify an escape for T5 (test={d:.2}).\n\n", .{t5_after});
    } else {
        try out.print("UNEXPECTED monomial phase: {d}/5 solved at T5={d:.2}. Inspect.\n\n", .{ nsolvedM, t5_mono });
    }

    try out.print("INVENTION VERDICT: ", .{});
    if (escaped_via_menu) {
        try out.print("NOT a blind new-family discovery — the menu was HANDED two operator families (spectral count-\n", .{});
        try out.print("Fourier, Walsh χ_S). The system ROUTED to the right one (spectral for parity) and CERTIFIED\n", .{});
        try out.print("promotion. That is principled operator selection + escape, not inventing a family from scratch.\n", .{});
    } else {
        try out.print("No escape — monomial bottom stands; menu could not certify parity.\n", .{});
    }

    try out.print("\nAGI RELEVANCE: This chain scales to unknown predicates ONLY if (a) the operator menu is rich\n", .{});
    try out.print("enough to span the target's family WITHOUT naming it, and (b) saturation detection triggers\n", .{});
    try out.print("the menu automatically. Here parity's family (Z₂ on count) is IN the menu by design — so the\n", .{});
    try out.print("escape works but does not prove open-ended invention. For unknown predicates, you'd need either\n", .{});
    try out.print("a complete operator basis (Walsh is universal on Boolean cubes) or a meta-menu that grows when\n", .{});
    try out.print("existing operators saturate — the next fork.\n", .{});

    try out.print("\nThe algebraic-irreducibility+usefulness objective changed the CLIMB, not the monomial BOTTOM.\n", .{});
    try out.print("See: operator_menu.zig, menu_growth.md (Phase B), inner_forge.md, CLOSURE_PRINCIPLE.md.\n", .{});
}
