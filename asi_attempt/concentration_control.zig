//! Concentration control: does an ORDER-STATISTIC constraint defeat the quadratic basis?
//!
//! basis_degree_control.zig showed: a quadratic basis over the raw state solves the
//! polynomial band constraints (sum/left/right) perfectly. H4 asked whether a per-cell
//! MAX constraint — an order statistic, NOT a fixed-degree polynomial — defeats it.
//! That test was degenerate in the shared env (uniform dynamics couple max and sum).
//!
//! Here we build a PURPOSE-BUILT env where the max constraint is (a) separable from
//! the sum band and (b) genuinely hard for a polynomial proxy:
//!
//!   - The agent must hold the bulk of cells near the threshold (sum forced high),
//!     so sum(x_i^2) is dominated by the bulk and a single spiking cell barely moves it.
//!   - Failure = any cell >= T (order statistic) OR sum out of band (polynomial).
//!   - knockdown (the only max-control action) COSTS sum. So the agent cannot just
//!     always-knockdown; it must detect WHEN max is near T — i.e., it must represent
//!     the order statistic. Over-knock -> sum underflow; under-knock -> overflow.
//!
//! Three bases, ONLY the basis changes:
//!   linear    : [1, x_i/S]
//!   quadratic : + [x_i^2/S^2, x_i x_j/S^2]            (the polynomial closure)
//!   quad_max  : quadratic + [max(x)/S]                (one order-statistic feature)
//!
//! PREDICTION: quadratic handles the sum band but leaves RESIDUAL OVERFLOW failures
//! (sum x_i^2 is a weak proxy for max in this regime); quad_max closes the gap to ~0.
//! If so, the order-statistic boundary is isolated: the residual is specifically the
//! max constraint, and ONE order-statistic feature fixes it.
//!
//! Run: zig build concentration-control

const std = @import("std");

const NCELL = 16;
const S: f32 = 5.0;

const Basis = enum { linear, quadratic, quad_max };

const NLIN = NCELL;
const NSQ = NCELL;
const NCROSS = 120; // C(16,2)
const NFEAT = 1 + NLIN + NSQ + NCROSS + 1; // +1 bias, +1 max feature = 154

fn nActive(basis: Basis) usize {
    return switch (basis) {
        .linear => 1 + NLIN,
        .quadratic => 1 + NLIN + NSQ + NCROSS,
        .quad_max => 1 + NLIN + NSQ + NCROSS + 1,
    };
}

fn features(grid: [NCELL]u8, basis: Basis, phi: *[NFEAT]f32) void {
    phi[0] = 1.0;
    var idx: usize = 1;
    for (0..NCELL) |i| {
        phi[idx] = @as(f32, @floatFromInt(grid[i])) / S;
        idx += 1;
    }
    if (basis == .quadratic or basis == .quad_max) {
        for (0..NCELL) |i| {
            const g = @as(f32, @floatFromInt(grid[i])) / S;
            phi[idx] = g * g;
            idx += 1;
        }
        for (0..NCELL) |i| {
            for (i + 1..NCELL) |j| {
                const gi = @as(f32, @floatFromInt(grid[i])) / S;
                const gj = @as(f32, @floatFromInt(grid[j])) / S;
                phi[idx] = gi * gj;
                idx += 1;
            }
        }
    }
    if (basis == .quad_max) {
        var mx: u8 = 0;
        for (grid) |c| mx = @max(mx, c);
        phi[idx] = @as(f32, @floatFromInt(mx)) / S;
        idx += 1;
    }
}

const FailKind = enum { none, overflow, band };

// Purpose-built concentration environment.
const ConcEnv = struct {
    grid: [NCELL]u8,
    failed: bool,
    fail_kind: FailKind,
    // params
    start: u8,
    thresh: u8, // cell >= thresh fails (order statistic)
    min_sum: u32,
    max_sum: u32,
    knock_mag: u8, // amount removed from max cell on knockdown
    drip_mag: u8, // amount added to a random cell each step

    fn init(start: u8, thresh: u8, min_sum: u32, max_sum: u32, knock_mag: u8, drip_mag: u8) ConcEnv {
        return .{
            .grid = [_]u8{start} ** NCELL,
            .failed = false,
            .fail_kind = .none,
            .start = start,
            .thresh = thresh,
            .min_sum = min_sum,
            .max_sum = max_sum,
            .knock_mag = knock_mag,
            .drip_mag = drip_mag,
        };
    }

    fn reset(self: *ConcEnv) void {
        self.grid = [_]u8{self.start} ** NCELL;
        self.failed = false;
        self.fail_kind = .none;
    }

    fn sum(self: *const ConcEnv) u32 {
        var s: u32 = 0;
        for (self.grid) |c| s += c;
        return s;
    }

    fn argmax(self: *const ConcEnv) usize {
        var mi: usize = 0;
        for (1..NCELL) |i| if (self.grid[i] > self.grid[mi]) {
            mi = i;
        };
        return mi;
    }

    fn argmin(self: *const ConcEnv) usize {
        var mi: usize = 0;
        for (1..NCELL) |i| if (self.grid[i] < self.grid[mi]) {
            mi = i;
        };
        return mi;
    }

    // action 0 = knockdown (max cell -= knock_mag; sum down; controls overflow)
    // action 1 = fill     (min cell += 1; sum up)
    // action 2 = rest     (no extra change)
    fn step(self: *ConcEnv, action: u8, rng: std.Random) void {
        if (self.failed) {
            self.reset();
            return;
        }
        // Disturbance: a random cell gains drip_mag (concentration / spike pressure).
        const dcell = rng.intRangeLessThan(usize, 0, NCELL);
        self.grid[dcell] +|= self.drip_mag;

        switch (action) {
            0 => { // knockdown the current peak
                const mi = self.argmax();
                const k = self.knock_mag;
                self.grid[mi] = if (self.grid[mi] > k) self.grid[mi] - k else 0;
            },
            1 => { // fill the lowest cell
                const mi = self.argmin();
                self.grid[mi] +|= 1;
            },
            else => {}, // rest
        }

        // Failure checks. Overflow (order statistic) first, then sum band (polynomial).
        var mx: u8 = 0;
        for (self.grid) |c| mx = @max(mx, c);
        if (mx >= self.thresh) {
            self.failed = true;
            self.fail_kind = .overflow;
            return;
        }
        const s = self.sum();
        if (s < self.min_sum or s > self.max_sum) {
            self.failed = true;
            self.fail_kind = .band;
            return;
        }
    }
};

const QCtrl = struct {
    w: [3][NFEAT]f32,
    n: usize,
    lr: f32,
    gamma: f32,

    fn init(n_active: usize, lr: f32, gamma: f32) QCtrl {
        var q: QCtrl = undefined;
        for (0..3) |a| {
            for (0..NFEAT) |k| q.w[a][k] = 0;
        }
        q.n = n_active;
        q.lr = lr;
        q.gamma = gamma;
        return q;
    }

    fn value(self: *const QCtrl, phi: *const [NFEAT]f32, a: usize) f32 {
        var z: f32 = 0;
        for (0..self.n) |k| z += self.w[a][k] * phi[k];
        return z;
    }

    fn minValue(self: *const QCtrl, phi: *const [NFEAT]f32) f32 {
        var best: f32 = 1e9;
        for (0..3) |a| {
            const v = self.value(phi, a);
            if (v < best) best = v;
        }
        return best;
    }

    fn choose(self: *const QCtrl, phi: *const [NFEAT]f32, rng: std.Random, eps: f32) u8 {
        if (rng.float(f32) < eps) return @intCast(rng.intRangeLessThan(usize, 0, 3));
        var best: u8 = 0;
        var best_v: f32 = 1e9;
        for (0..3) |a| {
            const v = self.value(phi, a);
            if (v < best_v) {
                best_v = v;
                best = @intCast(a);
            }
        }
        return best;
    }

    fn tdUpdate(self: *QCtrl, phi: *const [NFEAT]f32, a: usize, cost: f32, phi_next: *const [NFEAT]f32, failed: bool) void {
        var target: f32 = cost;
        if (!failed) target += self.gamma * self.minValue(phi_next);
        if (target < 0) target = 0;
        if (target > 1) target = 1;
        const v = self.value(phi, a);
        const err = v - target;
        for (0..self.n) |k| self.w[a][k] -= self.lr * err * phi[k];
    }
};

const Result = struct { fail_1k: f64, overflow_1k: f64, band_1k: f64 };

fn episode(env_proto: ConcEnv, basis: Basis, train_steps: usize, eval_steps: usize, seed: u64, lr: f32, gamma: f32) Result {
    var phi: [NFEAT]f32 = undefined;
    var phi_next: [NFEAT]f32 = undefined;
    var q = QCtrl.init(nActive(basis), lr, gamma);
    var env = env_proto;
    env.reset();
    var rng = std.Random.DefaultPrng.init(seed);
    var prev_failed = false;

    const decay_end: f32 = @floatFromInt(train_steps / 2);
    for (0..train_steps) |step| {
        features(env.grid, basis, &phi);
        const sf: f32 = @floatFromInt(step);
        const eps = @max(0.1, 1.0 - sf / decay_end);
        const a = q.choose(&phi, rng.random(), eps);
        env.step(a, rng.random());
        const failed = env.failed;
        features(env.grid, basis, &phi_next);
        if (!prev_failed) q.tdUpdate(&phi, a, if (failed) 1.0 else 0.0, &phi_next, failed);
        prev_failed = failed;
    }

    var fails: u32 = 0;
    var overflow: u32 = 0;
    var band: u32 = 0;
    for (0..eval_steps) |_| {
        features(env.grid, basis, &phi);
        const a = q.choose(&phi, rng.random(), 0.0);
        env.step(a, rng.random());
        if (env.failed) {
            fails += 1;
            if (env.fail_kind == .overflow) overflow += 1 else band += 1;
        }
    }
    const e: f64 = @floatFromInt(eval_steps);
    return .{
        .fail_1k = @as(f64, @floatFromInt(fails)) / e * 1000.0,
        .overflow_1k = @as(f64, @floatFromInt(overflow)) / e * 1000.0,
        .band_1k = @as(f64, @floatFromInt(band)) / e * 1000.0,
    };
}

// ---- Oracle feasibility floor ----
// A hand-coded max-rationing policy with PERFECT access to the true max and sum.
// It knocks ONLY when a cell is one drip from the threshold (max >= thresh-1), refills
// sum when low, else rests. This measures whether the regime is CONTROLLABLE AT ALL by
// a max-aware policy -- the feasibility floor. If the oracle ~0 but quadratic has
// overflow residual, the gap is REPRESENTATIONAL (quad can't see max), not feasibility.
fn oracleEpisode(env_proto: ConcEnv, eval_steps: usize, seed: u64) Result {
    var env = env_proto;
    env.reset();
    var rng = std.Random.DefaultPrng.init(seed);
    const r = rng.random();
    var fails: u32 = 0;
    var overflow: u32 = 0;
    var band: u32 = 0;
    const margin: u32 = 2;
    for (0..eval_steps) |_| {
        // Decide on the CURRENT (pre-step) state, same timing the learners get.
        var mx: u8 = 0;
        for (env.grid) |c| mx = @max(mx, c);
        const s = env.sum();
        var a: u8 = 2; // rest
        if (mx + 1 >= env.thresh) {
            a = 0; // knock: a cell is one drip from overflow
        } else if (s <= env.min_sum + margin) {
            a = 1; // fill: sum getting low
        } else if (s + margin >= env.max_sum) {
            a = 0; // knock to shed sum before band-overflow
        }
        env.step(a, r);
        if (env.failed) {
            fails += 1;
            if (env.fail_kind == .overflow) overflow += 1 else band += 1;
        }
    }
    const e: f64 = @floatFromInt(eval_steps);
    return .{
        .fail_1k = @as(f64, @floatFromInt(fails)) / e * 1000.0,
        .overflow_1k = @as(f64, @floatFromInt(overflow)) / e * 1000.0,
        .band_1k = @as(f64, @floatFromInt(band)) / e * 1000.0,
    };
}

fn meanOracle(env_proto: ConcEnv, eval_steps: usize, n_seeds: usize) Result {
    var tf: f64 = 0;
    var to: f64 = 0;
    var tb: f64 = 0;
    for (0..n_seeds) |s| {
        const r = oracleEpisode(env_proto, eval_steps, 0xABC0 +% @as(u64, s) *% 0x9E37);
        tf += r.fail_1k;
        to += r.overflow_1k;
        tb += r.band_1k;
    }
    const ns: f64 = @floatFromInt(n_seeds);
    return .{ .fail_1k = tf / ns, .overflow_1k = to / ns, .band_1k = tb / ns };
}

fn meanEpisode(env_proto: ConcEnv, basis: Basis, train_steps: usize, eval_steps: usize, n_seeds: usize, lr: f32, gamma: f32) Result {
    var tf: f64 = 0;
    var to: f64 = 0;
    var tb: f64 = 0;
    for (0..n_seeds) |s| {
        const r = episode(env_proto, basis, train_steps, eval_steps, 0xABC0 +% @as(u64, s) *% 0x9E37, lr, gamma);
        tf += r.fail_1k;
        to += r.overflow_1k;
        tb += r.band_1k;
    }
    const ns: f64 = @floatFromInt(n_seeds);
    return .{ .fail_1k = tf / ns, .overflow_1k = to / ns, .band_1k = tb / ns };
}

fn runRegime(out: anytype, name: []const u8, env_proto: ConcEnv, train: usize, eval: usize, seeds: usize, lr: f32, gamma: f32) !void {
    try out.print("\n=== REGIME: {s} (start={d}, thresh={d}, sum[{d},{d}], knock={d}, drip={d}) ===\n", .{
        name, env_proto.start, env_proto.thresh, env_proto.min_sum, env_proto.max_sum, env_proto.knock_mag, env_proto.drip_mag,
    });
    try out.print("  basis     | fail/1k | overflow/1k | band/1k\n", .{});
    try out.print("  ----------+---------+-------------+--------\n", .{});
    const rl = meanEpisode(env_proto, .linear, train, eval, seeds, lr, gamma);
    try out.print("  linear    | {d:7.2} | {d:11.2} | {d:7.2}\n", .{ rl.fail_1k, rl.overflow_1k, rl.band_1k });
    const rq = meanEpisode(env_proto, .quadratic, train, eval, seeds, lr, gamma);
    try out.print("  quadratic | {d:7.2} | {d:11.2} | {d:7.2}\n", .{ rq.fail_1k, rq.overflow_1k, rq.band_1k });
    const rm = meanEpisode(env_proto, .quad_max, train, eval, seeds, lr, gamma);
    try out.print("  quad+max  | {d:7.2} | {d:11.2} | {d:7.2}\n", .{ rm.fail_1k, rm.overflow_1k, rm.band_1k });

    try out.print("  --- reading ---\n", .{});
    if (rm.fail_1k < 5.0 and rq.overflow_1k > rm.overflow_1k + 5.0) {
        try out.print("  >>> ORDER-STATISTIC BOUNDARY ISOLATED: quad leaves overflow residual\n", .{});
        try out.print("      ({d:.2}/1k), quad+max closes it ({d:.2}/1k). The max feature is the fix.\n", .{ rq.overflow_1k, rm.overflow_1k });
    } else if (rq.fail_1k < 5.0) {
        try out.print("  >>> quadratic ALSO solves it: sum(x_i^2) is an adequate max proxy here.\n", .{});
    } else {
        try out.print("  >>> inconclusive at this regime (quad+max={d:.2}, quad={d:.2}).\n", .{ rm.fail_1k, rq.fail_1k });
    }
}

// ---- Representational probe: can a basis CLASSIFY the predicate max(x) >= T? ----
// This strips out control feasibility and tests REPRESENTATION directly (the project's
// readout-ceiling methodology). max>=T is an OR over cells -> its decision boundary is a
// UNION of 16 axis-aligned planes. A quadratic level set is a SINGLE quadric, so it
// cannot represent that union; it should degrade as the bulk nears T (spike buried in
// sum x_i^2). One max() feature represents it trivially.

const MAXN = 4000;

fn gridMax(g: [NCELL]u8) u8 {
    var mx: u8 = 0;
    for (g) |c| mx = @max(mx, c);
    return mx;
}

fn gridMinNonzeroIdx(g: [NCELL]u8) usize {
    var mi: usize = 0;
    var found = false;
    for (0..NCELL) |i| {
        if (g[i] > 0 and (!found or g[i] < g[mi])) {
            mi = i;
            found = true;
        }
    }
    return mi;
}

fn gridArgmax(g: [NCELL]u8) usize {
    var mi: usize = 0;
    for (1..NCELL) |i| if (g[i] > g[mi]) {
        mi = i;
    };
    return mi;
}

// Matched-sum generator. Start all cells at level L (sum = 16L EXACTLY, identical for
// both classes -> linear/sum is provably uninformative, forced to chance). Apply M
// sum-preserving random moves for variety. Then:
//   negative: keep only if max < T (reject otherwise) -> varied states, max below T
//   positive: force one cell up to >= T by moving units onto it (sum preserved)
// Result: both classes have IDENTICAL sum and OVERLAPPING sum(x_i^2); only the order
// statistic max(x) separates them. This is the impossibility witness for any quadratic.
fn genMatched(rng: std.Random, L: u8, T: u8, cap: u8, moves: usize, positive: bool) [NCELL]u8 {
    var attempts: usize = 0;
    while (true) {
        attempts += 1;
        var g = [_]u8{L} ** NCELL;
        for (0..moves) |_| {
            const src = rng.intRangeLessThan(usize, 0, NCELL);
            const dst = rng.intRangeLessThan(usize, 0, NCELL);
            if (g[src] > 0 and g[dst] < cap) {
                g[src] -= 1;
                g[dst] += 1;
            }
        }
        if (positive) {
            // Raise one cell to >= T, pulling units from low cells (sum preserved).
            var guard: usize = 0;
            while (gridMax(g) < T and guard < 10_000) : (guard += 1) {
                const dst = gridArgmax(g);
                const src = gridMinNonzeroIdx(g);
                if (src == dst or g[src] == 0) break;
                g[src] -= 1;
                g[dst] += 1;
            }
            if (gridMax(g) >= T) return g;
        } else {
            if (gridMax(g) < T) return g;
        }
        if (attempts > 100_000) return g; // give up; caller tolerates rare degeneracy
    }
}

// Logistic regression over a chosen basis; features computed on the fly from grids.
fn trainAndTest(grids_tr: []const [NCELL]u8, y_tr: []const f32, grids_te: []const [NCELL]u8, y_te: []const f32, basis: Basis, epochs: usize, lr: f32) f64 {
    var w = [_]f32{0} ** NFEAT;
    const n = nActive(basis);
    var phi: [NFEAT]f32 = undefined;
    for (0..epochs) |_| {
        for (grids_tr, y_tr) |g, y| {
            features(g, basis, &phi);
            var z: f32 = 0;
            for (0..n) |k| z += w[k] * phi[k];
            if (z > 30) z = 30;
            if (z < -30) z = -30;
            const p = 1.0 / (1.0 + @exp(-z));
            const grad = p - y;
            for (0..n) |k| w[k] -= lr * grad * phi[k];
        }
    }
    // Test accuracy
    var correct: u32 = 0;
    for (grids_te, y_te) |g, y| {
        features(g, basis, &phi);
        var z: f32 = 0;
        for (0..n) |k| z += w[k] * phi[k];
        const pred: f32 = if (z >= 0) 1.0 else 0.0;
        if (pred == y) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(grids_te.len));
}

fn sumSq(g: [NCELL]u8) f64 {
    var s: f64 = 0;
    for (g) |c| {
        const v: f64 = @floatFromInt(c);
        s += v * v;
    }
    return s;
}

fn sumSqU(g: [NCELL]u8) u32 {
    var s: u32 = 0;
    for (g) |c| {
        const v: u32 = c;
        s += v * v;
    }
    return s;
}

// Decisive probe: match BOTH sum (by construction) AND sum(x^2) EXACTLY, by keeping
// only states whose integer Σx² value occurs in BOTH classes, in equal counts (sorted
// merge over Σx² bins). For exchangeable data the best quadratic depends only on
// (sum, Σx²); matching both forces ANY quadratic to chance, while max() still separates.
const BIGPOOL = 12000;
fn runProbeMatched(out: anytype, level: u8, thresh: u8, cap: u8, moves: usize, seed: u64, scratch: []u8) !void {
    var rng = std.Random.DefaultPrng.init(seed);
    const r = rng.random();

    // scratch holds nothing; we use static-ish arrays via the caller's allocator slices.
    _ = scratch;
    const PoolArr = struct {
        var pos: [BIGPOOL][NCELL]u8 = undefined;
        var neg: [BIGPOOL][NCELL]u8 = undefined;
        var pos_sq: [BIGPOOL]u32 = undefined;
        var neg_sq: [BIGPOOL]u32 = undefined;
        var pos_idx: [BIGPOOL]usize = undefined;
        var neg_idx: [BIGPOOL]usize = undefined;
        var grids: [2 * BIGPOOL][NCELL]u8 = undefined;
        var labels: [2 * BIGPOOL]f32 = undefined;
    };
    for (0..BIGPOOL) |k| {
        PoolArr.pos[k] = genMatched(r, level, thresh, cap, moves, true);
        PoolArr.neg[k] = genMatched(r, level, thresh, cap, moves, false);
        PoolArr.pos_sq[k] = sumSqU(PoolArr.pos[k]);
        PoolArr.neg_sq[k] = sumSqU(PoolArr.neg[k]);
        PoolArr.pos_idx[k] = k;
        PoolArr.neg_idx[k] = k;
    }
    const Cp = struct {
        sq: []u32,
        fn lt(ctx: @This(), a: usize, b: usize) bool {
            return ctx.sq[a] < ctx.sq[b];
        }
    };
    std.sort.pdq(usize, &PoolArr.pos_idx, Cp{ .sq = &PoolArr.pos_sq }, Cp.lt);
    std.sort.pdq(usize, &PoolArr.neg_idx, Cp{ .sq = &PoolArr.neg_sq }, Cp.lt);

    // Sorted merge: for each Σx² value present in both, take equal counts from each.
    var i: usize = 0;
    var j: usize = 0;
    var n: usize = 0;
    var sq_pos_sel: u64 = 0;
    var sq_neg_sel: u64 = 0;
    while (i < BIGPOOL and j < BIGPOOL) {
        const vp = PoolArr.pos_sq[PoolArr.pos_idx[i]];
        const vn = PoolArr.neg_sq[PoolArr.neg_idx[j]];
        if (vp < vn) {
            i += 1;
        } else if (vn < vp) {
            j += 1;
        } else {
            // same Σx² bin; count run lengths
            var ri: usize = i;
            while (ri < BIGPOOL and PoolArr.pos_sq[PoolArr.pos_idx[ri]] == vp) ri += 1;
            var rj: usize = j;
            while (rj < BIGPOOL and PoolArr.neg_sq[PoolArr.neg_idx[rj]] == vn) rj += 1;
            const m = @min(ri - i, rj - j);
            for (0..m) |t| {
                PoolArr.grids[n] = PoolArr.pos[PoolArr.pos_idx[i + t]];
                PoolArr.labels[n] = 1.0;
                sq_pos_sel += vp;
                n += 1;
                PoolArr.grids[n] = PoolArr.neg[PoolArr.neg_idx[j + t]];
                PoolArr.labels[n] = 0.0;
                sq_neg_sel += vn;
                n += 1;
            }
            i = ri;
            j = rj;
        }
    }
    if (n < 200) {
        try out.print("  L={d} T={d}: Σx^2 overlap too thin (n={d}); inconclusive\n", .{ level, thresh, n });
        return;
    }
    const ntr = (n * 7) / 10;
    const acc_lin = trainAndTest(PoolArr.grids[0..ntr], PoolArr.labels[0..ntr], PoolArr.grids[ntr..n], PoolArr.labels[ntr..n], .linear, 80, 0.1);
    const acc_quad = trainAndTest(PoolArr.grids[0..ntr], PoolArr.labels[0..ntr], PoolArr.grids[ntr..n], PoolArr.labels[ntr..n], .quadratic, 80, 0.1);
    const acc_max = trainAndTest(PoolArr.grids[0..ntr], PoolArr.labels[0..ntr], PoolArr.grids[ntr..n], PoolArr.labels[ntr..n], .quad_max, 80, 0.1);
    const hn: f64 = @floatFromInt(n / 2);
    try out.print("  L={d} (T={d}) | lin {d:.3} | quad {d:.3} | quad+max {d:.3} | n={d} | <x^2> EXACT-matched pos={d:.1} neg={d:.1}\n", .{
        level, thresh, acc_lin, acc_quad, acc_max, n, @as(f64, @floatFromInt(sq_pos_sel)) / hn, @as(f64, @floatFromInt(sq_neg_sel)) / hn,
    });
}

fn runProbe(out: anytype, level: u8, thresh: u8, cap: u8, moves: usize, seed: u64) !void {
    var rng = std.Random.DefaultPrng.init(seed);
    const r = rng.random();

    var grids: [MAXN][NCELL]u8 = undefined;
    var labels: [MAXN]f32 = undefined;
    const half = MAXN / 2;
    var sq_pos: f64 = 0;
    var sq_neg: f64 = 0;
    for (0..half) |k| {
        const gp = genMatched(r, level, thresh, cap, moves, true);
        grids[2 * k] = gp;
        labels[2 * k] = 1.0;
        sq_pos += sumSq(gp);
        const gn = genMatched(r, level, thresh, cap, moves, false);
        grids[2 * k + 1] = gn;
        labels[2 * k + 1] = 0.0;
        sq_neg += sumSq(gn);
    }
    const total = MAXN;
    // shuffle-free split is fine since classes are interleaved
    const ntr = (total * 7) / 10;
    const grids_tr = grids[0..ntr];
    const y_tr = labels[0..ntr];
    const grids_te = grids[ntr..total];
    const y_te = labels[ntr..total];

    const acc_lin = trainAndTest(grids_tr, y_tr, grids_te, y_te, .linear, 80, 0.1);
    const acc_quad = trainAndTest(grids_tr, y_tr, grids_te, y_te, .quadratic, 80, 0.1);
    const acc_max = trainAndTest(grids_tr, y_tr, grids_te, y_te, .quad_max, 80, 0.1);

    const hn: f64 = @floatFromInt(half);
    try out.print("  L={d} (sum={d}, T={d}) | lin {d:.3} | quad {d:.3} | quad+max {d:.3} | <x^2> pos={d:.1} neg={d:.1}\n", .{
        level, @as(u32, level) * NCELL, thresh, acc_lin, acc_quad, acc_max, sq_pos / hn, sq_neg / hn,
    });
}

// ---- Representation DISCOVERY: can gradient find the right rung of the power-mean ladder? ----
// We proved max = lim_{p→∞} ( (1/N) Σ (x_i/S)^p )^{1/p}. Instead of HANDING the controller a
// max feature, give it ONE feature with a learnable exponent p: the power mean f_p(x). p=1 is
// the arithmetic mean (linear/sum); p→∞ is max. Train p by gradient alongside a logistic
// readout. Ground-truth check on two matched tasks differing ONLY in which order statistic
// they need:
//   MAX task : sum matched (constant), max differs  -> p SHOULD climb toward max.
//   SUM task : max matched (constant), sum differs  -> p SHOULD stay near 1 (mean).
// If learned p lands on the correct rung, the system DISCOVERED the representation it needed.

const PMResult = struct { f: f64, dfdp: f64 };

// Power mean f_p and its derivative w.r.t. p, via a numerically stable log-sum-exp form.
fn powerMean(g: [NCELL]u8, p: f64) PMResult {
    const eps: f64 = 1e-3;
    const N: f64 = @floatFromInt(NCELL);
    var ln_u: [NCELL]f64 = undefined;
    var m: f64 = -1e30;
    for (0..NCELL) |i| {
        const u = @as(f64, @floatFromInt(g[i])) / S + eps;
        ln_u[i] = @log(u);
        const a = p * ln_u[i];
        if (a > m) m = a;
    }
    var sw: f64 = 0; // Σ exp(p·ln u_i − m)
    var swl: f64 = 0; // Σ exp(p·ln u_i − m)·ln u_i
    for (0..NCELL) |i| {
        const w = @exp(p * ln_u[i] - m);
        sw += w;
        swl += w * ln_u[i];
    }
    const logM = m + @log(sw) - @log(N);
    const dlogMdp = swl / sw; // = (Σ u^p ln u)/(Σ u^p)
    const f = @exp(logM / p);
    const dfdp = f * (p * dlogMdp - logM) / (p * p);
    return .{ .f = f, .dfdp = dfdp };
}

const DiscoverResult = struct { p_final: f64, acc: f64 };

// Train [b + w·f_p] logistic with p learnable. lrp=0 freezes p (fixed-p baseline).
fn trainDiscover(out: anytype, label: []const u8, grids: []const [NCELL]u8, ys: []const f32, p_init: f64, epochs: usize, lrw: f64, lrp: f64, trace: bool) !DiscoverResult {
    var b: f64 = 0;
    var w: f64 = 0;
    var p: f64 = p_init;
    if (trace) try out.print("    {s}: p {d:5.2}", .{ label, p });
    for (0..epochs) |ep| {
        for (grids, ys) |g, yf| {
            const y: f64 = yf;
            const pm = powerMean(g, p);
            var z = b + w * pm.f;
            if (z > 30) z = 30;
            if (z < -30) z = -30;
            const pr = 1.0 / (1.0 + @exp(-z));
            const d = pr - y; // dL/dz
            const gp = d * w * pm.dfdp; // dL/dp (uses current w)
            b -= lrw * d;
            w -= lrw * d * pm.f;
            p -= lrp * gp;
            if (p < 0.2) p = 0.2;
            if (p > 64) p = 64;
        }
        if (trace and (ep + 1) % (epochs / 5) == 0) try out.print(" -> {d:5.2}", .{p});
    }
    var correct: usize = 0;
    for (grids, ys) |g, yf| {
        const pm = powerMean(g, p);
        const z = b + w * pm.f;
        const pred: f64 = if (z >= 0) 1.0 else 0.0;
        if (pred == yf) correct += 1;
    }
    const acc = @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(grids.len));
    if (trace) try out.print("  | final p={d:.2}, acc={d:.3}\n", .{ p, acc });
    return .{ .p_final = p, .acc = acc };
}

// SUM-task generator: one cell fixed at C (max constant), others in [0,C-1]; label sum>=K.
fn genFixedMax(rng: std.Random, C: u8, K: u32, positive: bool) [NCELL]u8 {
    while (true) {
        var g: [NCELL]u8 = undefined;
        for (0..NCELL) |i| g[i] = rng.intRangeLessThan(u8, 0, C);
        g[rng.intRangeLessThan(usize, 0, NCELL)] = C;
        var s: u32 = 0;
        for (g) |c| s += c;
        if (positive and s >= K) return g;
        if (!positive and s < K) return g;
    }
}

// ---- Degree-general probe: is max in the degree-d SYMMETRIC POLYNOMIAL closure? ----
// For exchangeable (coordinate-symmetric) data the best degree-d polynomial classifier
// depends ONLY on the power sums p_k = Σ x_i^k, k=1..d. And max(x) = lim_{k→∞}(p_k)^{1/k}
// is the k→∞ limit — so NO finite d captures it. We test this with a MINIMAL power-sum
// basis [1, p_1..p_d] (no coordinate monomials → no overfitting confound), and a probe
// that matches p_1..p_d EXACTLY between the two classes (integer-key bin-merge). If the
// degree-2 AND degree-3 PS bases both fall to chance while [..,max] stays ~1.0, the order
// statistic is outside the polynomial closure at degree 2 and 3 — and by the limit
// argument, at every finite degree.
const MAXDEG = 4;

fn psFeatures(g: [NCELL]u8, degree: usize, with_max: bool, phi: *[MAXDEG + 2]f32) usize {
    phi[0] = 1.0;
    var k: usize = 1;
    while (k <= degree) : (k += 1) phi[k] = 0;
    for (g) |c| {
        const xs = @as(f32, @floatFromInt(c)) / S;
        var p: f32 = 1.0;
        var kk: usize = 1;
        while (kk <= degree) : (kk += 1) {
            p *= xs;
            phi[kk] += p;
        }
    }
    var n = degree + 1;
    if (with_max) {
        var mx: u8 = 0;
        for (g) |c| mx = @max(mx, c);
        phi[n] = @as(f32, @floatFromInt(mx)) / S;
        n += 1;
    }
    return n;
}

// Exact integer power-sum key up to degree d (d in {2,3}). p_1 (=sum) is matched by the
// generator's construction; here we additionally match p_2 (and p_3 for d=3).
fn psKey(g: [NCELL]u8, degree: usize) u64 {
    var p2: u64 = 0;
    var p3: u64 = 0;
    for (g) |c| {
        const x: u64 = c;
        p2 += x * x;
        if (degree >= 3) p3 += x * x * x;
    }
    if (degree >= 3) return (p2 << 24) | p3; // p3 < 2^24 for our caps -> no overlap
    return p2;
}

fn trainPS(grids_tr: []const [NCELL]u8, y_tr: []const f32, grids_te: []const [NCELL]u8, y_te: []const f32, degree: usize, with_max: bool, epochs: usize, lr: f32) f64 {
    var w = [_]f32{0} ** (MAXDEG + 2);
    var phi: [MAXDEG + 2]f32 = undefined;
    var n: usize = 0;
    for (0..epochs) |_| {
        for (grids_tr, y_tr) |g, y| {
            n = psFeatures(g, degree, with_max, &phi);
            var z: f32 = 0;
            for (0..n) |k| z += w[k] * phi[k];
            if (z > 30) z = 30;
            if (z < -30) z = -30;
            const p = 1.0 / (1.0 + @exp(-z));
            const grad = p - y;
            for (0..n) |k| w[k] -= lr * grad * phi[k];
        }
    }
    var correct: u32 = 0;
    for (grids_te, y_te) |g, y| {
        n = psFeatures(g, degree, with_max, &phi);
        var z: f32 = 0;
        for (0..n) |k| z += w[k] * phi[k];
        const pred: f32 = if (z >= 0) 1.0 else 0.0;
        if (pred == y) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(grids_te.len));
}

fn runProbePS(out: anytype, level: u8, thresh: u8, cap: u8, moves: usize, seed: u64, degree: usize) !void {
    var rng = std.Random.DefaultPrng.init(seed);
    const r = rng.random();
    const Pool = struct {
        var pos: [BIGPOOL][NCELL]u8 = undefined;
        var neg: [BIGPOOL][NCELL]u8 = undefined;
        var pos_k: [BIGPOOL]u64 = undefined;
        var neg_k: [BIGPOOL]u64 = undefined;
        var pi: [BIGPOOL]usize = undefined;
        var ni: [BIGPOOL]usize = undefined;
        var grids: [2 * BIGPOOL][NCELL]u8 = undefined;
        var labels: [2 * BIGPOOL]f32 = undefined;
    };
    for (0..BIGPOOL) |k| {
        Pool.pos[k] = genMatched(r, level, thresh, cap, moves, true);
        Pool.neg[k] = genMatched(r, level, thresh, cap, moves, false);
        Pool.pos_k[k] = psKey(Pool.pos[k], degree);
        Pool.neg_k[k] = psKey(Pool.neg[k], degree);
        Pool.pi[k] = k;
        Pool.ni[k] = k;
    }
    const Cp = struct {
        key: []u64,
        fn lt(ctx: @This(), a: usize, b: usize) bool {
            return ctx.key[a] < ctx.key[b];
        }
    };
    std.sort.pdq(usize, &Pool.pi, Cp{ .key = &Pool.pos_k }, Cp.lt);
    std.sort.pdq(usize, &Pool.ni, Cp{ .key = &Pool.neg_k }, Cp.lt);

    var i: usize = 0;
    var j: usize = 0;
    var n: usize = 0;
    while (i < BIGPOOL and j < BIGPOOL) {
        const vp = Pool.pos_k[Pool.pi[i]];
        const vn = Pool.neg_k[Pool.ni[j]];
        if (vp < vn) {
            i += 1;
        } else if (vn < vp) {
            j += 1;
        } else {
            var ri: usize = i;
            while (ri < BIGPOOL and Pool.pos_k[Pool.pi[ri]] == vp) ri += 1;
            var rj: usize = j;
            while (rj < BIGPOOL and Pool.neg_k[Pool.ni[rj]] == vn) rj += 1;
            const m = @min(ri - i, rj - j);
            for (0..m) |t| {
                Pool.grids[n] = Pool.pos[Pool.pi[i + t]];
                Pool.labels[n] = 1.0;
                n += 1;
                Pool.grids[n] = Pool.neg[Pool.ni[j + t]];
                Pool.labels[n] = 0.0;
                n += 1;
            }
            i = ri;
            j = rj;
        }
    }
    if (n < 200) {
        try out.print("  L={d} T={d} deg={d}: p1..p{d}-matched overlap too thin (n={d}); inconclusive\n", .{ level, thresh, degree, degree, n });
        return;
    }
    const ntr = (n * 7) / 10;
    const ps = trainPS(Pool.grids[0..ntr], Pool.labels[0..ntr], Pool.grids[ntr..n], Pool.labels[ntr..n], degree, false, 120, 0.05);
    const psm = trainPS(Pool.grids[0..ntr], Pool.labels[0..ntr], Pool.grids[ntr..n], Pool.labels[ntr..n], degree, true, 120, 0.05);
    try out.print("  L={d} T={d} | [1,p1..p{d}] {d:.3} | [..,max] {d:.3} | n={d} (p1..p{d} EXACT-matched)\n", .{ level, thresh, degree, ps, psm, n, degree });
}

// ---- Feasibility-aware regime sweep ----
// Hunt for a CLEAN control witness: oracle ~0 (regime is feasible for a max-aware
// policy), quad+max ~ oracle (learner recovers it), but quad has overflow residual
// (the polynomial basis can't time knockdowns -> the representational gap shows up as
// a CONTROL gap, not just a classifier gap). This is what B/C failed to isolate
// because they were near-infeasible (oracle itself can't reach 0).
fn runSweep(out: anytype, train: usize, eval: usize, seeds: usize, lr: f32, gamma: f32) !void {
    try out.print("=== FEASIBILITY-AWARE SWEEP (train {d}, eval {d}, {d} seeds) ===\n", .{ train, eval, seeds });
    try out.print("oracle = hand max-rationing policy (feasibility floor). WITNESS = oracle<5,\n", .{});
    try out.print("quad+max<oracle+5, and quad.overflow > quad+max.overflow + 5.\n\n", .{});
    try out.print("  start thr  sum-band   kn dr | oracle | quad  (ovf) | q+max (ovf) | verdict\n", .{});
    try out.print("  -----------------------------+--------+------------+-------------+--------\n", .{});

    const starts = [_]u8{ 3, 4, 5 };
    const heads = [_]u8{ 2, 3 };
    const knocks = [_]u8{ 2, 3 };
    const halfs = [_]u32{ 10, 16 };
    const drip: u8 = 1;

    var best_gap: f64 = 0;
    var best_desc: [128]u8 = undefined;
    var best_len: usize = 0;

    for (starts) |start| {
        for (heads) |h| {
            const thresh = start + h;
            const base_sum: u32 = @as(u32, start) * NCELL;
            for (halfs) |hw| {
                if (hw >= base_sum) continue;
                const min_sum = base_sum - hw;
                const max_sum = base_sum + hw;
                for (knocks) |kn| {
                    const env = ConcEnv.init(start, thresh, min_sum, max_sum, kn, drip);
                    const ro = meanOracle(env, eval, seeds);
                    const rq = meanEpisode(env, .quadratic, train, eval, seeds, lr, gamma);
                    const rm = meanEpisode(env, .quad_max, train, eval, seeds, lr, gamma);

                    const feasible = ro.fail_1k < 5.0;
                    const learned = rm.fail_1k < ro.fail_1k + 5.0;
                    const gap = rq.overflow_1k - rm.overflow_1k;
                    const witness = feasible and learned and gap > 5.0;

                    const verdict = if (witness) ">>> WITNESS" else if (!feasible) "infeasible" else if (gap > 5.0) "gap,noisy" else "no-gap";
                    try out.print("  {d:5} {d:3}  [{d:3},{d:3}] {d:2} {d:2} | {d:6.2} | {d:5.1}({d:4.1}) | {d:5.1}({d:4.1}) | {s}\n", .{
                        start, thresh, min_sum, max_sum, kn, drip,
                        ro.fail_1k, rq.fail_1k, rq.overflow_1k, rm.fail_1k, rm.overflow_1k, verdict,
                    });

                    if (witness and gap > best_gap) {
                        best_gap = gap;
                        const w = std.fmt.bufPrint(&best_desc, "start={d} thresh={d} sum[{d},{d}] knock={d} drip={d}", .{ start, thresh, min_sum, max_sum, kn, drip }) catch best_desc[0..0];
                        best_len = w.len;
                    }
                }
            }
        }
    }
    if (best_len > 0) {
        try out.print("\n  BEST WITNESS (overflow gap {d:.2}/1k): {s}\n", .{ best_gap, best_desc[0..best_len] });
    } else {
        try out.print("\n  NO clean witness found in this grid -- the representational gap does NOT\n", .{});
        try out.print("  cleanly transfer to control here (feasibility-visibility tension).\n", .{});
    }
}

// Confirm a single regime at high budget with mean AND worst-case across seeds
// (the project's rigor standard). Reports oracle floor + all three bases, split by
// overflow vs band so the residual is attributable to the order statistic.
const Stat = struct { mean: f64, worst: f64, ovf_mean: f64, band_mean: f64 };

fn confirmBasis(env: ConcEnv, basis: Basis, train: usize, eval: usize, seeds: usize, lr: f32, gamma: f32) Stat {
    var tf: f64 = 0;
    var to: f64 = 0;
    var tb: f64 = 0;
    var worst: f64 = 0;
    for (0..seeds) |s| {
        const r = episode(env, basis, train, eval, 0xABC0 +% @as(u64, s) *% 0x9E37, lr, gamma);
        tf += r.fail_1k;
        to += r.overflow_1k;
        tb += r.band_1k;
        if (r.fail_1k > worst) worst = r.fail_1k;
    }
    const ns: f64 = @floatFromInt(seeds);
    return .{ .mean = tf / ns, .worst = worst, .ovf_mean = to / ns, .band_mean = tb / ns };
}

fn confirmRegime(out: anytype, env: ConcEnv, train: usize, eval: usize, seeds: usize, lr: f32, gamma: f32) !void {
    try out.print("\n=== CONFIRM WITNESS: start={d} thresh={d} sum[{d},{d}] knock={d} drip={d} ===\n", .{
        env.start, env.thresh, env.min_sum, env.max_sum, env.knock_mag, env.drip_mag,
    });
    try out.print("  train {d}, eval {d}, {d} seeds. mean / worst / (overflow, band) means.\n", .{ train, eval, seeds });
    try out.print("  basis     |    mean |   worst | overflow | band\n", .{});
    try out.print("  ----------+---------+---------+----------+------\n", .{});

    // Oracle floor (no training; worst across seeds too).
    var of: f64 = 0;
    var ow: f64 = 0;
    var oo: f64 = 0;
    var ob: f64 = 0;
    for (0..seeds) |s| {
        const r = oracleEpisode(env, eval, 0xABC0 +% @as(u64, s) *% 0x9E37);
        of += r.fail_1k;
        oo += r.overflow_1k;
        ob += r.band_1k;
        if (r.fail_1k > ow) ow = r.fail_1k;
    }
    const ns: f64 = @floatFromInt(seeds);
    try out.print("  oracle    | {d:7.2} | {d:7.2} | {d:8.2} | {d:5.2}\n", .{ of / ns, ow, oo / ns, ob / ns });

    const sl = confirmBasis(env, .linear, train, eval, seeds, lr, gamma);
    try out.print("  linear    | {d:7.2} | {d:7.2} | {d:8.2} | {d:5.2}\n", .{ sl.mean, sl.worst, sl.ovf_mean, sl.band_mean });
    const sq = confirmBasis(env, .quadratic, train, eval, seeds, lr, gamma);
    try out.print("  quadratic | {d:7.2} | {d:7.2} | {d:8.2} | {d:5.2}\n", .{ sq.mean, sq.worst, sq.ovf_mean, sq.band_mean });
    const sm = confirmBasis(env, .quad_max, train, eval, seeds, lr, gamma);
    try out.print("  quad+max  | {d:7.2} | {d:7.2} | {d:8.2} | {d:5.2}\n", .{ sm.mean, sm.worst, sm.ovf_mean, sm.band_mean });

    try out.print("  --- reading ---\n", .{});
    if (of / ns < 5.0 and sm.mean < of / ns + 5.0 and sq.ovf_mean > sm.ovf_mean + 5.0) {
        try out.print("  >>> CONTROL WITNESS CONFIRMED: regime is FEASIBLE (oracle {d:.2}), quad+max\n", .{of / ns});
        try out.print("      recovers it ({d:.2}), quadratic leaves an OVERFLOW residual ({d:.2} vs {d:.2}).\n", .{ sm.mean, sq.ovf_mean, sm.ovf_mean });
        try out.print("      The representational gap (quad can't see max) becomes a CONTROL gap.\n", .{});
    } else {
        try out.print("  >>> not confirmed at full budget (oracle {d:.2}, quad ovf {d:.2}, q+max ovf {d:.2}).\n", .{ of / ns, sq.ovf_mean, sm.ovf_mean });
    }
}

pub fn main() !void {
    const out = std.io.getStdOut().writer();

    // Arg-gated modes so the default decisive run is preserved.
    var args = std.process.args();
    _ = args.next(); // exe name
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "sweep")) {
            try runSweep(out, 30_000, 8_000, 3, 0.02, 0.9);
            return;
        }
        if (std.mem.eql(u8, arg, "sweep-full")) {
            try runSweep(out, 80_000, 10_000, 6, 0.02, 0.9);
            return;
        }
        if (std.mem.eql(u8, arg, "discover")) {
            try out.print("=== REPRESENTATION DISCOVERY: learn the exponent p of a power-mean feature ===\n", .{});
            try out.print("f_p(x) = ((1/N) Σ (x_i/S)^p)^(1/p).  p=1 -> mean (linear/sum);  p->inf -> max.\n", .{});
            try out.print("Two matched tasks, p learned by gradient. p init=2.0 for BOTH. Trace: p over epochs.\n\n", .{});

            const NPC = 2500; // per class
            const Buf = struct {
                var grids: [2 * NPC][NCELL]u8 = undefined;
                var ys: [2 * NPC]f32 = undefined;
            };
            var rng = std.Random.DefaultPrng.init(0xD15C0);
            const r = rng.random();

            // ---- MAX task: sum matched (constant), max differs. Truth: needs p->inf. ----
            const L: u8 = 4;
            const T: u8 = 9;
            for (0..NPC) |k| {
                Buf.grids[2 * k] = genMatched(r, L, T, 16, 24, true);
                Buf.ys[2 * k] = 1.0;
                Buf.grids[2 * k + 1] = genMatched(r, L, T, 16, 24, false);
                Buf.ys[2 * k + 1] = 0.0;
            }
            try out.print("  MAX task (sum matched at {d}, classify max>=T={d}); truth: p should CLIMB.\n", .{ @as(u32, L) * NCELL, T });
            _ = try trainDiscover(out, "learned-p", &Buf.grids, &Buf.ys, 2.0, 200, 0.05, 0.5, true);
            const m1 = try trainDiscover(out, "fixed p=1", &Buf.grids, &Buf.ys, 1.0, 200, 0.05, 0.0, false);
            const m32 = try trainDiscover(out, "fixed p=32", &Buf.grids, &Buf.ys, 32.0, 200, 0.05, 0.0, false);
            try out.print("    baselines: fixed p=1 acc={d:.3} (mean is blind to max) | fixed p=32 acc={d:.3}\n\n", .{ m1.acc, m32.acc });

            // ---- SUM task: max matched (constant=C), sum differs. Truth: needs p~1. ----
            const C: u8 = 8;
            const K: u32 = 60;
            for (0..NPC) |k| {
                Buf.grids[2 * k] = genFixedMax(r, C, K, true);
                Buf.ys[2 * k] = 1.0;
                Buf.grids[2 * k + 1] = genFixedMax(r, C, K, false);
                Buf.ys[2 * k + 1] = 0.0;
            }
            try out.print("  SUM task (max matched at C={d}, classify sum>=K={d}); truth: p should fall to ~1.\n", .{ C, K });
            _ = try trainDiscover(out, "learned-p  (from below, init 2) ", &Buf.grids, &Buf.ys, 2.0, 200, 0.05, 0.5, true);
            _ = try trainDiscover(out, "learned-p  (from above, init 12)", &Buf.grids, &Buf.ys, 12.0, 200, 0.05, 0.5, true);
            const s1 = try trainDiscover(out, "fixed p=1", &Buf.grids, &Buf.ys, 1.0, 200, 0.05, 0.0, false);
            const s32 = try trainDiscover(out, "fixed p=32", &Buf.grids, &Buf.ys, 32.0, 200, 0.05, 0.0, false);
            try out.print("    baselines: fixed p=1 acc={d:.3} | fixed p=32 acc={d:.3} (max is blind to sum)\n\n", .{ s1.acc, s32.acc });

            try out.print("  READING: if learned-p climbs high on MAX and stays ~1 on SUM, gradient DISCOVERED\n", .{});
            try out.print("  which rung of the power-mean ladder each task needs -- representational self-tuning,\n", .{});
            try out.print("  verified against the known closure requirement of each task.\n", .{});
            return;
        }
        if (std.mem.eql(u8, arg, "degree")) {
            try out.print("=== DEGREE-GENERAL CLOSURE PROBE: is max in the degree-d polynomial closure? ===\n", .{});
            try out.print("Minimal power-sum basis [1, p_1..p_d]; match p_1..p_d EXACTLY between classes.\n", .{});
            try out.print("max(x) = lim_k (p_k)^(1/k) -> outside EVERY finite-degree closure. Prediction:\n", .{});
            try out.print("[1,p1..pd] -> chance at d=2 AND d=3; [..,max] -> ~1.0.\n\n", .{});
            try out.print("  --- degree 2 (match p1=sum, p2=Σx²) ---\n", .{});
            try runProbePS(out, 2, 6, 12, 16, 0xC0FFEE, 2);
            try runProbePS(out, 3, 6, 12, 16, 0xC0FFEE, 2);
            try runProbePS(out, 4, 9, 16, 24, 0xC0FFEE, 2);
            try out.print("  --- degree 3 (match p1=sum, p2=Σx², p3=Σx³) ---\n", .{});
            try runProbePS(out, 2, 6, 12, 16, 0xC0FFEE, 3);
            try runProbePS(out, 3, 6, 12, 16, 0xC0FFEE, 3);
            try runProbePS(out, 4, 9, 16, 24, 0xC0FFEE, 3);
            try out.print("\n  If degree-3 also falls to chance, no quadratic OR cubic over the raw state\n", .{});
            try out.print("  can represent the max constraint; one order-statistic feature crosses it.\n", .{});
            return;
        }
        if (std.mem.eql(u8, arg, "robust")) {
            // Robustness of the CONFIRMED witness (4,6,[48,80],2,1):
            // (a) per-seed breakdown over 16 seeds -- is the overflow gap broad or one outlier?
            // (b) band-width neighborhood -- is it a regime, not a knife-edge?
            const TR: usize = 80_000;
            const EV: usize = 10_000;
            const NS: usize = 16;
            try out.print("=== ROBUSTNESS: confirmed witness start=4 thresh=6 knock=2 drip=1, band[48,80] ===\n", .{});
            try out.print("(a) PER-SEED over {d} seeds (overflow in parens):\n", .{NS});
            try out.print("  seed |   quad fail (ovf) |  q+max fail (ovf)\n", .{});
            try out.print("  -----+-------------------+------------------\n", .{});
            const wenv = ConcEnv.init(4, 6, 48, 80, 2, 1);
            var q_better: usize = 0;
            for (0..NS) |s| {
                const seed = 0xABC0 +% @as(u64, s) *% 0x9E37;
                const rq = episode(wenv, .quadratic, TR, EV, seed, 0.02, 0.9);
                const rm = episode(wenv, .quad_max, TR, EV, seed, 0.02, 0.9);
                const flag = if (rm.overflow_1k + 2.0 < rq.overflow_1k) " <- q+max wins ovf" else "";
                if (rm.overflow_1k + 2.0 < rq.overflow_1k) q_better += 1;
                try out.print("  {d:4} | {d:7.2} ({d:6.2}) | {d:7.2} ({d:6.2}){s}\n", .{ s, rq.fail_1k, rq.overflow_1k, rm.fail_1k, rm.overflow_1k, flag });
            }
            try out.print("  --> quad+max wins overflow (by >2/1k) on {d}/{d} seeds.\n", .{ q_better, NS });

            try out.print("\n(b) BAND-WIDTH NEIGHBORHOOD (8 seeds each), mean fail / overflow:\n", .{});
            try out.print("  half-width | sum-band  | quad fail(ovf) | q+max fail(ovf)\n", .{});
            try out.print("  -----------+-----------+----------------+----------------\n", .{});
            const hws = [_]u32{ 12, 14, 16, 18, 20 };
            for (hws) |hw| {
                const env = ConcEnv.init(4, 6, 64 - hw, 64 + hw, 2, 1);
                const rq = meanEpisode(env, .quadratic, TR, EV, 8, 0.02, 0.9);
                const rm = meanEpisode(env, .quad_max, TR, EV, 8, 0.02, 0.9);
                try out.print("  {d:10} | [{d:3},{d:3}] | {d:6.2}({d:6.2}) | {d:6.2}({d:6.2})\n", .{ hw, 64 - hw, 64 + hw, rq.fail_1k, rq.overflow_1k, rm.fail_1k, rm.overflow_1k });
            }
            return;
        }
        if (std.mem.eql(u8, arg, "confirm")) {
            // The two witness regimes from the sweep, confirmed at full budget / 8 seeds.
            try confirmRegime(out, ConcEnv.init(4, 7, 48, 80, 3, 1), 80_000, 10_000, 8, 0.02, 0.9);
            try confirmRegime(out, ConcEnv.init(4, 6, 48, 80, 2, 1), 80_000, 10_000, 8, 0.02, 0.9);
            return;
        }
    }

    const TRAIN: usize = 80_000;
    const EVAL: usize = 10_000;
    const SEEDS: usize = 6;
    const LR: f32 = 0.02;
    const GAMMA: f32 = 0.9;

    try out.print("=== CONCENTRATION CONTROL: does a MAX (order-statistic) constraint\n", .{});
    try out.print("    defeat the quadratic (polynomial) basis? ===\n", .{});
    try out.print("Per-action TD danger Q(x,a)=w_a.phi(x), raw 16 cells, no hand features\n", .{});
    try out.print("(except quad+max adds ONE order-statistic feature: max(x)).\n", .{});
    try out.print("Train {d}, eval {d} frozen, {d} seeds.\n", .{ TRAIN, EVAL, SEEDS });

    // Regime A: bulk well below threshold -> a spike stands out in sum(x^2) (easy for quad)
    const easy = ConcEnv.init(2, 5, 24, 44, 2, 1);
    try runRegime(out, "A bulk-low (spike visible to x^2)", easy, TRAIN, EVAL, SEEDS, LR, GAMMA);

    // Regime B: bulk near threshold -> a spike is buried in sum(x^2) (hard for quad)
    const hard = ConcEnv.init(3, 5, 40, 56, 2, 1);
    try runRegime(out, "B bulk-high (spike buried in x^2)", hard, TRAIN, EVAL, SEEDS, LR, GAMMA);

    // Regime C: even tighter — bulk at 4, threshold 6, must catch the rare 5->6 spike
    const hard2 = ConcEnv.init(4, 6, 56, 76, 2, 1);
    try runRegime(out, "C bulk-higher (tighter order-statistic)", hard2, TRAIN, EVAL, SEEDS, LR, GAMMA);

    try out.print("\n=== NOTE on control regimes ===\n", .{});
    try out.print("Control regimes B/C are near-INFEASIBLE: even quad+max can't prevent overflow\n", .{});
    try out.print("(one knockdown/step can't keep up with the drip when bulk is near T). So\n", .{});
    try out.print("control conflates feasibility with representation. The probe below isolates\n", .{});
    try out.print("the REPRESENTATIONAL question cleanly.\n", .{});

    // ---- Decisive probe: can each basis REPRESENT max(x) >= T? ----
    try out.print("\n=== REPRESENTATIONAL PROBE: classify max(x) >= T (test accuracy) ===\n", .{});
    try out.print("Balanced data, logistic regression per basis. Sweep bulk level (mean).\n", .{});
    try out.print("As mean -> T, a single spike is buried in sum(x_i^2): quadratic should DROP,\n", .{});
    try out.print("quad+max should stay ~1.0, linear (computes sum) stays poor.\n\n", .{});
    try out.print("  Matched sum (linear forced to chance); T=6, cap=12, moves=16.\n", .{});
    try out.print("  As level L -> T, the spike is buried in <x^2> overlap -> quad should drop:\n", .{});
    try runProbe(out, 1, 6, 12, 16, 0xC0FFEE);
    try runProbe(out, 2, 6, 12, 16, 0xC0FFEE);
    try runProbe(out, 3, 6, 12, 16, 0xC0FFEE);
    try runProbe(out, 4, 6, 12, 16, 0xC0FFEE);
    try out.print("\n  Higher threshold T=9 (cap=16) to push the boundary further out:\n", .{});
    try runProbe(out, 4, 9, 16, 24, 0xC0FFEE);
    try runProbe(out, 5, 9, 16, 24, 0xC0FFEE);
    try runProbe(out, 6, 9, 16, 24, 0xC0FFEE);
    try runProbe(out, 7, 9, 16, 24, 0xC0FFEE);

    try out.print("\n=== DECISIVE PROBE: match sum AND <x^2> EXACTLY (Σx^2-bin merge) ===\n", .{});
    try out.print("For exchangeable classes the optimal quadratic depends ONLY on (sum, sum x^2).\n", .{});
    try out.print("Matching both forces ANY quadratic to chance; max() still separates.\n\n", .{});
    var scratch: [1]u8 = undefined;
    try runProbeMatched(out, 2, 6, 12, 16, 0xC0FFEE, &scratch);
    try runProbeMatched(out, 3, 6, 12, 16, 0xC0FFEE, &scratch);
    try runProbeMatched(out, 4, 9, 16, 24, 0xC0FFEE, &scratch);
    try runProbeMatched(out, 5, 9, 16, 24, 0xC0FFEE, &scratch);

    try out.print("\n=== OVERALL ===\n", .{});
    try out.print("linear ~chance everywhere (sum matched, provably uninformative). If quadratic\n", .{});
    try out.print("degrades toward chance as L -> T while quad+max stays ~1.0, the\n", .{});
    try out.print("polynomial-vs-order-statistic closure boundary is demonstrated: a quadratic\n", .{});
    try out.print("function of the raw state cannot represent a max predicate (boundary = union of\n", .{});
    try out.print("axis-aligned planes); ONE order-statistic feature crosses it.\n", .{});
}
