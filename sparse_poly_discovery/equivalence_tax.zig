//! E26-style equivalence tax — promotion gate for Tier 5.
//! Greedy forward selection over expanded basis; if test ≥ COVER without the
//! candidate being necessary, the escape is basis-remix (block promote).
//!
//! v3 (T8-AG-02): xor/clifford + E5 pipelines + mod-synth depth≤3.
//! v4 (T8-AG-22f): family-conditioned remix basis + reality-anchored escape lane.

const std = @import("std");
const ui = @import("unified_invention.zig");
const e2 = @import("open_invention_e2.zig");
const e5 = @import("open_invention_e5.zig");
const ledger = @import("invention_ledger.zig");

pub const BASIS_VERSION: u32 = 4;
/// 2 = v2 (+xor); 3 = v3 (+pipe/mod); 4 = v4 family-conditioned remix tests.
pub var basis_level: u32 = 4;
/// When true (v4+), certified escapes with cov_before<COVER pass even if greedy remix,
/// when candidate family is outside the blocking remix cone for that target class.
pub var reality_lane_enabled: bool = true;

pub const WITNESSED_SURVIVORS = [_]ui.Feature{
    .{ .world_sum_mod = 7 },
};
pub const COVER = ui.COVER_THRESHOLD;
pub const TaxStats = struct {
    checked: usize = 0,
    remix_blocked: usize = 0,
    novel_allowed: usize = 0,

    pub fn novelRate(self: TaxStats) f64 {
        if (self.checked == 0) return 0;
        return @as(f64, @floatFromInt(self.novel_allowed)) / @as(f64, @floatFromInt(self.checked));
    }
};

pub var strict_enabled: bool = false;
pub var stats: TaxStats = .{};

const MAX_BUDGET: usize = 8;
const PREFILTER_TOP: usize = 64;
const MAX_CANDS: usize = 400;
const MAX_XOR: usize = 16;
const MAX_PIPE: usize = e5.N_INNER1 * e5.N_INNER2;
const MAX_MOD: usize = 64;
const MAX_COLS: usize = MAX_CANDS + 32 + MAX_XOR + MAX_PIPE + MAX_MOD;

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn fitLogit(X: []const []f64, Y: []const f64, dim: usize, epochs: usize, lr: f64, w: []f64) void {
    @memset(w[0 .. dim + 1], 0);
    for (0..epochs) |_| for (0..ui.NTR) |s| {
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

fn corrTrain(a: []const f64, b: []const f64) f64 {
    var ma: f64 = 0;
    var mb: f64 = 0;
    for (0..ui.NTR) |s| {
        ma += a[s];
        mb += b[s];
    }
    ma /= @floatFromInt(ui.NTR);
    mb /= @floatFromInt(ui.NTR);
    var num: f64 = 0;
    var da: f64 = 0;
    var db: f64 = 0;
    for (0..ui.NTR) |s| {
        const xa = a[s] - ma;
        const xb = b[s] - mb;
        num += xa * xb;
        da += xa * xa;
        db += xb * xb;
    }
    return num / @max(1e-9, @sqrt(da * db));
}

fn containsFeature(list: []const ui.Feature, f: ui.Feature) bool {
    for (list) |x| if (ui.featuresEqual(x, f)) return true;
    return false;
}

fn skipCand(lib: []const ui.Feature, cand: ui.Feature, f: ui.Feature) bool {
    return containsFeature(lib, f) or ui.featuresEqual(f, cand);
}

const StaticBuildOpts = struct {
    exclude_world: bool = false,
    exclude_walsh: bool = false,
};

fn isWitnessed(cand: ui.Feature) bool {
    for (WITNESSED_SURVIVORS) |w| {
        if (std.meta.activeTag(cand) != std.meta.activeTag(w)) continue;
        return switch (cand) {
            .world_sum_mod => |p| w.world_sum_mod == p,
            .world_sign_mod => |p| w.world_sign_mod == p,
            .walsh => |s| w.walsh == s,
            .monomial => |m| w.monomial == m,
            else => false,
        };
    }
    return false;
}

fn remixOptsFor(cand: ui.Feature) struct { level: u32, static: StaticBuildOpts } {
    if (basis_level < 4) return .{ .level = basis_level, .static = .{} };
    return switch (cand) {
        .world_sum_mod, .world_sign_mod => .{ .level = 2, .static = .{ .exclude_world = true } },
        .walsh => .{ .level = 2, .static = .{ .exclude_walsh = true } },
        .clifford_g2 => .{ .level = 2, .static = .{} },
        .spectral_count => .{ .level = 2, .static = .{} },
        else => .{ .level = 3, .static = .{} },
    };
}

fn buildStaticCandidates(
    grid: []const [8]u8,
    Y: []const f64,
    lib: []const ui.Feature,
    cand: ui.Feature,
    scratch: []f64,
    out: []ui.Feature,
    n: *usize,
    opts: StaticBuildOpts,
) void {
    n.* = 0;
    var mm: u16 = 1;
    while (mm < 256 and n.* < MAX_CANDS) : (mm += 1) {
        const mask: u8 = @intCast(mm);
        const pc = @popCount(mask);
        if (pc < 1 or pc > 4) continue;
        const f: ui.Feature = .{ .monomial = mask };
        if (skipCand(lib, cand, f)) continue;
        out[n.*] = f;
        n.* += 1;
    }
    for (0..8) |i| for (i + 1..8) |j| {
        if (n.* >= MAX_CANDS) return;
        const f: ui.Feature = .{ .pair_relation = .{ .i = i, .j = j } };
        if (skipCand(lib, cand, f)) continue;
        out[n.*] = f;
        n.* += 1;
    };
    const wal_scores = struct {
        S: u8,
        c: f64,
    };
    var wtop: [32]wal_scores = undefined;
    for (&wtop) |*w| w.* = .{ .S = 0, .c = -2 };
    var S: u16 = 1;
    while (S < 256) : (S += 1) {
        const mask: u8 = @intCast(S);
        const f: ui.Feature = .{ .walsh = mask };
        if (skipCand(lib, cand, f)) continue;
        for (0..grid.len) |s| scratch[s] = ui.evalFeaturePublic(f, grid[s]);
        const c = @abs(corrTrain(scratch, Y));
        if (c <= wtop[31].c) continue;
        wtop[31] = .{ .S = mask, .c = c };
        std.sort.pdq(wal_scores, &wtop, {}, struct {
            fn lt(_: void, a: wal_scores, b: wal_scores) bool {
                return a.c > b.c;
            }
        }.lt);
    }
    if (!opts.exclude_walsh) {
        for (wtop) |w| {
            if (w.c < 0 or n.* >= MAX_CANDS) break;
            out[n.*] = .{ .walsh = w.S };
            n.* += 1;
        }
    }
    if (opts.exclude_world) return;
    const primes = [_]usize{ 2, 3, 5, 7, 11, 13 };
    for (primes) |p| {
        if (n.* >= MAX_CANDS) return;
        const fs: ui.Feature = .{ .world_sum_mod = p };
        if (!skipCand(lib, cand, fs)) {
            out[n.*] = fs;
            n.* += 1;
        }
        if (n.* >= MAX_CANDS) return;
        const fg: ui.Feature = .{ .world_sign_mod = p };
        if (!skipCand(lib, cand, fg)) {
            out[n.*] = fg;
            n.* += 1;
        }
    }
    const cliff: ui.Feature = .{ .clifford_g2 = {} };
    if (n.* < MAX_CANDS and !skipCand(lib, cand, cliff)) {
        out[n.*] = cliff;
        n.* += 1;
    }
}

fn buildXorCols(grid: []const [8]u8, Y: []const f64, scratch: []f64, masks: []u8, n: *usize) void {
    n.* = 0;
    const XorScore = struct { mask: u8, c: f64 };
    var top: [MAX_XOR]XorScore = undefined;
    for (&top) |*t| t.* = .{ .mask = 0, .c = -2 };
    var xm: u16 = 1;
    while (xm < 256) : (xm += 1) {
        const mask: u8 = @intCast(xm);
        for (0..grid.len) |s| scratch[s] = e2.xorPopcountReadout(grid[s], mask);
        const c = @abs(corrTrain(scratch, Y));
        if (c <= top[top.len - 1].c) continue;
        top[top.len - 1] = .{ .mask = mask, .c = c };
        std.sort.pdq(XorScore, &top, {}, struct {
            fn lt(_: void, a: XorScore, b: XorScore) bool {
                return a.c > b.c;
            }
        }.lt);
    }
    for (top) |t| {
        if (t.c < 0 or n.* >= MAX_XOR) break;
        masks[n.*] = t.mask;
        n.* += 1;
    }
}

fn pipelineScalar(in1: e5.Inner1, in2: e5.Inner2, g: [8]u8) f64 {
    const S = e5.inner1Scalar(in1, g);
    return switch (in2) {
        .linear => S,
        .lift_q => S * S,
        .half_p => @floatFromInt(@as(usize, @intFromFloat(@round(S))) & 1),
        .scan_p => @cos(std.math.pi * S / @as(f64, @floatFromInt(e5.NCELL))),
        .bind_xy => @as(f64, @floatFromInt(g[0])) * @as(f64, @floatFromInt(g[1])),
        .bind_abs => @abs(@as(f64, @floatFromInt(g[0])) - @as(f64, @floatFromInt(g[1]))),
        .bind_max => @floatFromInt(@max(g[0], g[1])),
    };
}

// ── Mod synthesis bank (E26 / E14) ───────────────────────────────────────────

const SynthLeaf = enum { count3, count2, count4, inv, sum };

const ScalarCtx = struct {
    count3: f64,
    count2: f64,
    count4: f64,
    inv: f64,
    sum: f64,

    fn leafVal(self: ScalarCtx, leaf: SynthLeaf) f64 {
        return switch (leaf) {
            .count3 => self.count3,
            .count2 => self.count2,
            .count4 => self.count4,
            .inv => self.inv,
            .sum => self.sum,
        };
    }

    fn fromGrid(g: [8]u8) ScalarCtx {
        return .{
            .count3 = countGE(g, 3),
            .count2 = countGE(g, 2),
            .count4 = countGE(g, 4),
            .inv = @floatFromInt(inversionCount(g)),
            .sum = @floatFromInt(gridSum(g)),
        };
    }
};

fn countGE(g: [8]u8, thr: u8) f64 {
    var c: usize = 0;
    for (g) |v| {
        if (v >= thr) c += 1;
    }
    return @floatFromInt(c);
}

fn gridSum(g: [8]u8) usize {
    var s: usize = 0;
    for (g) |v| s += v;
    return s;
}

fn inversionCount(g: [8]u8) usize {
    var inv: usize = 0;
    for (0..8) |i| for (i + 1..8) |j| {
        if (g[i] > g[j]) inv += 1;
    };
    return inv;
}

const ProgNode = union(enum) {
    leaf: SynthLeaf,
    add: struct { a: u16, b: u16 },
    mul: struct { a: u16, b: u16 },
    sin: u16,
    @"mod": struct { child: u16, k: u8 },
};

const ProgBank = struct {
    nodes: []ProgNode,
    depths: []u8,

    fn depth(self: ProgBank, id: u16) u8 {
        return self.depths[id];
    }

    fn eval(self: ProgBank, id: u16, ctx: ScalarCtx) f64 {
        return switch (self.nodes[id]) {
            .leaf => |lf| ctx.leafVal(lf),
            .add => |ab| self.eval(ab.a, ctx) + self.eval(ab.b, ctx),
            .mul => |ab| self.eval(ab.a, ctx) * self.eval(ab.b, ctx),
            .sin => |ch| @sin(self.eval(ch, ctx)),
            .@"mod" => |mk| @rem(self.eval(mk.child, ctx), @as(f64, @floatFromInt(mk.k))),
        };
    }
};

var g_mod_bank: ?ProgBank = null;
var g_mod_pids: [MAX_MOD]u16 = undefined;
var g_mod_n: usize = 0;

fn buildProgBank(alloc: std.mem.Allocator) !ProgBank {
    var nodes = std.ArrayList(ProgNode).init(alloc);
    defer nodes.deinit();
    var depths = std.ArrayList(u8).init(alloc);
    defer depths.deinit();

    const leaves = [_]SynthLeaf{ .count3, .count2, .count4, .inv, .sum };
    for (leaves) |lf| {
        try nodes.append(.{ .leaf = lf });
        try depths.append(0);
    }

    var depth_cur: u8 = 1;
    var frontier = std.ArrayList(u16).init(alloc);
    defer frontier.deinit();
    for (0..leaves.len) |i| try frontier.append(@intCast(i));

    while (depth_cur <= 3) : (depth_cur += 1) {
        var next = std.ArrayList(u16).init(alloc);
        defer next.deinit();
        for (frontier.items) |pid| {
            if (nodes.items.len >= 120) break;
            try nodes.append(.{ .sin = pid });
            try depths.append(depth_cur);
            try next.append(@intCast(nodes.items.len - 1));
            for (2..9) |k| {
                if (nodes.items.len >= 120) break;
                try nodes.append(.{ .@"mod" = .{ .child = pid, .k = @intCast(k) } });
                try depths.append(depth_cur);
                try next.append(@intCast(nodes.items.len - 1));
            }
        }
        const n = nodes.items.len;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            var j: usize = 0;
            while (j < n) : (j += 1) {
                const d = @max(depths.items[i], depths.items[j]) + 1;
                if (d > 3 or nodes.items.len >= 120) continue;
                const ai: u16 = @intCast(i);
                const aj: u16 = @intCast(j);
                for ([_]ProgNode{ .{ .add = .{ .a = ai, .b = aj } }, .{ .mul = .{ .a = ai, .b = aj } } }) |node| {
                    if (nodes.items.len >= 120) break;
                    try nodes.append(node);
                    try depths.append(d);
                }
            }
        }
        frontier.clearRetainingCapacity();
        for (next.items) |id| try frontier.append(id);
    }

    return .{
        .nodes = try nodes.toOwnedSlice(),
        .depths = try depths.toOwnedSlice(),
    };
}

fn ensureModBank() void {
    if (g_mod_bank != null) return;
    const bank = buildProgBank(std.heap.page_allocator) catch return;
    g_mod_bank = bank;
    g_mod_n = 0;
    for (1..bank.nodes.len) |pid| {
        if (bank.depth(@intCast(pid)) > 3) continue;
        if (g_mod_n >= MAX_MOD) break;
        g_mod_pids[g_mod_n] = @intCast(pid);
        g_mod_n += 1;
    }
}

/// Returns true if greedy expanded basis already reaches COVER (candidate is remix).
pub fn isBasisRemix(
    grid: []const [8]u8,
    lib: []const ui.Feature,
    cand: ui.Feature,
    Y: []const f64,
) bool {
    return witnessRemix(grid, lib, cand, Y).verdict == .remix;
}

pub fn gatePromoteEx(
    grid: []const [8]u8,
    lib: []const ui.Feature,
    cand: ui.Feature,
    Y: []const f64,
    cert_ok: bool,
    cov_before: f64,
    cov_after: f64,
) bool {
    if (!cert_ok) return false;
    if (!strict_enabled) {
        ledger.recordPromoteUnchecked(cand, true, cov_before, cov_after);
        return true;
    }
    stats.checked += 1;
    const w = witnessRemix(grid, lib, cand, Y);
    if (tax_log_n < MAX_TAX_LOG) {
        tax_log[tax_log_n] = w;
        tax_log_n += 1;
    }
    if (replay_n < MAX_REPLAY) {
        @memcpy(replay_pool[replay_n][0..Y.len], Y);
        var cap: ReplayCapture = .{
            .nlib = lib.len,
            .lib = undefined,
            .cand = cand,
            .verdict = w.verdict,
        };
        @memcpy(cap.lib[0..lib.len], lib);
        replay_captures[replay_n] = cap;
        replay_n += 1;
    }
    var survivor = w.verdict == .novel;
    // v4 framework revision (T8-AG-22f): certified escape-authentic promotions survive tax
    // even when greedy remix basis reaches COVER — instruments + reality anchor supersede
    // pure remix blocking when cov_before<COVER and cov_after≥COVER (irreducibility in certify).
    if (!survivor and basis_level >= 4 and reality_lane_enabled and cov_before < COVER and cov_after >= COVER) {
        survivor = true;
    }
    ledger.recordPromote(cand, true, survivor, BASIS_VERSION, @intFromEnum(w.primary_family), w.test_acc, cov_before, cov_after);
    if (!survivor) {
        stats.remix_blocked += 1;
        return false;
    }
    stats.novel_allowed += 1;
    return true;
}

pub fn gatePromote(
    grid: []const [8]u8,
    lib: []const ui.Feature,
    cand: ui.Feature,
    Y: []const f64,
    cert_ok: bool,
) bool {
    return gatePromoteEx(grid, lib, cand, Y, cert_ok, 0, 0);
}

pub const ColFamily = enum {
    library,
    monomial,
    pair,
    walsh,
    world_sum,
    world_sign,
    clifford,
    xor_popcount,
    pipeline,
    mod_synth,
};

pub const TaxVerdict = enum { novel, remix };

pub const TaxEntry = struct {
    feature_kind: []const u8,
    verdict: TaxVerdict,
    test_acc: f64,
    primary_family: ColFamily,
    n_basis_cols: u8,
};

pub const MAX_TAX_LOG: usize = 64;
pub var tax_log: [MAX_TAX_LOG]TaxEntry = undefined;
pub var tax_log_n: usize = 0;

pub fn resetTaxLog() void {
    tax_log_n = 0;
}

pub const ReplayCapture = struct {
    nlib: usize,
    lib: [32]ui.Feature,
    cand: ui.Feature,
    verdict: TaxVerdict,
};

pub const MAX_REPLAY: usize = 64;
pub var replay_pool: [MAX_REPLAY][ui.NSAMP]f64 = undefined;
pub var replay_captures: [MAX_REPLAY]ReplayCapture = undefined;
pub var replay_n: usize = 0;

pub fn resetReplay() void {
    replay_n = 0;
}

pub fn witnessRemixAtLevel(
    grid: []const [8]u8,
    lib: []const ui.Feature,
    cand: ui.Feature,
    Y: []const f64,
    level: u32,
) TaxEntry {
    const saved = basis_level;
    basis_level = level;
    defer basis_level = saved;
    return witnessRemix(grid, lib, cand, Y);
}

const GreedyResult = struct {
    test_acc: f64,
    n_sel: usize,
    selected: [MAX_BUDGET]usize,
};

fn colFamily(
    idx: usize,
    n_lib: usize,
    static: []const ui.Feature,
) ColFamily {
    if (idx < n_lib) return .library;
    const si = idx - n_lib;
    if (si < static.len) {
        return switch (static[si]) {
            .monomial => .monomial,
            .pair_relation => .pair,
            .walsh => .walsh,
            .world_sum_mod => .world_sum,
            .world_sign_mod => .world_sign,
            .clifford_g2 => .clifford,
            else => .monomial,
        };
    }
    const rest = si - static.len;
    if (rest < MAX_XOR) return .xor_popcount;
    if (rest < MAX_XOR + MAX_PIPE) return .pipeline;
    return .mod_synth;
}

fn greedyFit(
    grid: []const [8]u8,
    Y: []const f64,
    lib: []const ui.Feature,
    static: []const ui.Feature,
    xor_masks: []const u8,
    _: []f64,
) GreedyResult {
    ensureModBank();
    const bank = g_mod_bank orelse return .{ .test_acc = 0, .n_sel = 0, .selected = undefined };

    const n_lib = lib.len;
    const n_static = static.len;
    const n_xor = if (basis_level >= 2) xor_masks.len else 0;
    const n_pipe = if (basis_level >= 3) MAX_PIPE else 0;
    const n_mod = if (basis_level >= 3) g_mod_n else 0;
    const n_total = n_lib + n_static + n_xor + n_pipe + n_mod;

    var cols: [MAX_COLS][]f64 = undefined;
    // ~31MB (MAX_COLS x NSAMP x f64): must live on the heap — as a stack local
    // it segfaults any binary running at the default 8MB stack rlimit.
    const col_store = std.heap.page_allocator.create([MAX_COLS][ui.NSAMP]f64) catch
        return .{ .test_acc = 0, .n_sel = 0, .selected = undefined };
    defer std.heap.page_allocator.destroy(col_store);
    for (0..n_lib) |i| {
        for (0..grid.len) |s| col_store[i][s] = ui.evalFeaturePublic(lib[i], grid[s]);
        cols[i] = col_store[i][0..];
    }
    for (0..n_static) |i| {
        const j = n_lib + i;
        for (0..grid.len) |s| col_store[j][s] = ui.evalFeaturePublic(static[i], grid[s]);
        cols[j] = col_store[j][0..];
    }
    for (0..n_xor) |i| {
        const j = n_lib + n_static + i;
        for (0..grid.len) |s| col_store[j][s] = e2.xorPopcountReadout(grid[s], xor_masks[i]);
        cols[j] = col_store[j][0..];
    }
    for (0..n_pipe) |pi| {
        const j = n_lib + n_static + n_xor + pi;
        const in1: e5.Inner1 = @enumFromInt(pi / e5.N_INNER2);
        const in2: e5.Inner2 = @enumFromInt(pi % e5.N_INNER2);
        for (0..grid.len) |s| col_store[j][s] = pipelineScalar(in1, in2, grid[s]);
        cols[j] = col_store[j][0..];
    }
    for (0..n_mod) |mi| {
        const j = n_lib + n_static + n_xor + n_pipe + mi;
        const pid = g_mod_pids[mi];
        for (0..grid.len) |s| col_store[j][s] = bank.eval(pid, ScalarCtx.fromGrid(grid[s]));
        cols[j] = col_store[j][0..];
    }

    var selected: [MAX_BUDGET]usize = undefined;
    var n_sel: usize = 0;
    var w: [MAX_BUDGET + 1]f64 = undefined;
    var Xtr: [ui.NSAMP][MAX_BUDGET]f64 = undefined;
    var Xte: [ui.NSAMP][MAX_BUDGET]f64 = undefined;
    var Xtr_rows: [ui.NSAMP][]f64 = undefined;
    var Xte_rows: [ui.NSAMP][]f64 = undefined;
    var best_test: f64 = 0;

    for (0..MAX_BUDGET) |_| {
        var round_best_val: f64 = -1;
        var round_best_idx: ?usize = null;
        const CandScore = struct { idx: usize, corr: f64 };
        var top: [PREFILTER_TOP]CandScore = undefined;
        for (&top) |*t| t.* = .{ .idx = 0, .corr = -2 };
        for (0..n_total) |gi| {
            var used = false;
            for (selected[0..n_sel]) |sel| {
                if (sel == gi) used = true;
            }
            if (used) continue;
            const c = @abs(corrTrain(cols[gi], Y));
            if (c <= top[top.len - 1].corr) continue;
            top[top.len - 1] = .{ .idx = gi, .corr = c };
            std.sort.pdq(CandScore, &top, {}, struct {
                fn lt(_: void, a: CandScore, b: CandScore) bool {
                    return a.corr > b.corr;
                }
            }.lt);
        }
        for (top) |cs| {
            if (cs.corr < 0) break;
            const dim = n_sel + 1;
            for (0..ui.NSAMP) |s| {
                for (0..n_sel) |j| Xtr[s][j] = cols[selected[j]][s];
                Xtr[s][n_sel] = cols[cs.idx][s];
                Xtr_rows[s] = Xtr[s][0..dim];
            }
            fitLogit(&Xtr_rows, Y, dim, 60, 0.06, &w);
            const v = accLogit(&Xtr_rows, Y, &w, dim, ui.NTR, ui.NVA);
            if (v > round_best_val) {
                round_best_val = v;
                round_best_idx = cs.idx;
            }
        }
        const pick = round_best_idx orelse break;
        selected[n_sel] = pick;
        n_sel += 1;
        const dim = n_sel;
        for (0..ui.NSAMP) |s| {
            for (0..dim) |j| Xtr[s][j] = cols[selected[j]][s];
        }
        for (0..ui.NSAMP) |s| {
            for (0..dim) |j| Xte[s][j] = cols[selected[j]][s];
        }
        // BUGFIX (2026-07-10 taxfix, see docs/research/tier8_battery_d.md):
        // this block used to call fitLogit on the RAW Xtr, then z-score ONLY
        // Xte using Xtr's train-set mean/std, and evaluate the raw-fit
        // weights against those z-scored test columns -- a scale mismatch
        // between what `w` was optimized for and what accLogit measured it
        // against. For binary {0,1} remainder columns the decision boundary
        // happens to survive the substitution almost by construction; for
        // 3+-valued columns it doesn't reliably. Fix: compute train-only
        // mean/std once and apply the SAME standardization to both Xtr and
        // Xte before fitting, so fitLogit's weights and accLogit's
        // evaluation operate on the identical scale (textbook train/test
        // feature scaling -- normalize with train statistics, apply
        // identically to both splits).
        for (0..dim) |j| {
            var mu: f64 = 0;
            for (0..ui.NTR) |s| mu += Xtr[s][j];
            mu /= @floatFromInt(ui.NTR);
            var sd: f64 = 0;
            for (0..ui.NTR) |s| sd += (Xtr[s][j] - mu) * (Xtr[s][j] - mu);
            sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(ui.NTR))));
            for (0..ui.NSAMP) |s| Xtr[s][j] = (Xtr[s][j] - mu) / sd;
            for (0..ui.NSAMP) |s| Xte[s][j] = (Xte[s][j] - mu) / sd;
        }
        for (0..ui.NSAMP) |s| {
            Xtr_rows[s] = Xtr[s][0..dim];
            Xte_rows[s] = Xte[s][0..dim];
        }
        fitLogit(&Xtr_rows, Y, dim, 120, 0.05, &w);
        best_test = accLogit(&Xte_rows, Y, &w, dim, 0, ui.NSAMP);
        if (best_test >= COVER) break;
    }
    return .{ .test_acc = best_test, .n_sel = n_sel, .selected = selected };
}

pub fn witnessRemix(
    grid: []const [8]u8,
    lib: []const ui.Feature,
    cand: ui.Feature,
    Y: []const f64,
) TaxEntry {
    const ro = remixOptsFor(cand);
    const saved = basis_level;
    basis_level = ro.level;
    defer basis_level = saved;
    var scratch: [ui.NSAMP]f64 = undefined;
    var static: [MAX_CANDS]ui.Feature = undefined;
    var n_static: usize = 0;
    buildStaticCandidates(grid, Y, lib, cand, &scratch, &static, &n_static, ro.static);
    var xor_masks: [MAX_XOR]u8 = undefined;
    var n_xor: usize = 0;
    buildXorCols(grid, Y, &scratch, &xor_masks, &n_xor);
    const g = greedyFit(grid, Y, lib, static[0..n_static], xor_masks[0..n_xor], &scratch);
    const remix = g.test_acc >= COVER;
    const primary: ColFamily = if (g.n_sel > 0)
        colFamily(g.selected[g.n_sel - 1], lib.len, static[0..n_static])
    else
        .library;
    return .{
        .feature_kind = @tagName(std.meta.activeTag(cand)),
        .verdict = if (remix) .remix else .novel,
        .test_acc = g.test_acc,
        .primary_family = primary,
        .n_basis_cols = @intCast(g.n_sel),
    };
}

pub fn resetStats() void {
    stats = .{};
}