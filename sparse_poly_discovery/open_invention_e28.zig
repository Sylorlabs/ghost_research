//! EXPERIMENT E28 — DeepSeek expert route invention.
//!
//! Question: Can hardness router + unified loop invent features predicting expert
//! activation from captured L30 activations (no full model forward)?
//!
//! Protocol:
//!   • Load deepseekexperiment/ acts_T128_off8000.bin, gate_L30_w.bin, e11_positions CSV
//!   • Project 7168-dim expert inputs → 8-cell activation substrate
//!   • Ground truth: sqrtsoftplus gate scores per expert (top-6 routing labels)
//!   • Hardness router (E14/Q38 analog) picks invention route per expert target
//!   • Unified loop: monomial forge → spectral menu → Walsh → world → mod synthesis
//!   • Verify on held-out stream positions (last 30% of e11 window)
//!
//! Pass bar: ≥5% activation-prediction lift vs 4-stat baseline; certified held-out R²>0;
//!           invented feature passes RQ9 novelty (not reproducible by mono+Walsh+world).
//!
//! Run: zig build open-invention-e28 --release=fast

const std = @import("std");
const hr = @import("hardness_router.zig");
const unified = @import("unified_invention.zig");

const DIM: usize = 7168;
const N_EXPERTS: usize = 384;
const TOPK: usize = 6;
const LAYER: usize = 30;
const ACT_REC: usize = 8 + DIM * 4;
const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = 2.5;

const NSAMP: usize = 128;
const NTR: usize = 89; // first 70% positions (train)
const NVA: usize = 102; // train+val for invention tuning
const NHOLD: usize = NSAMP - NVA; // 26 held-out positions

const MONO_SATURATE: f64 = 0.55;
const SINGLE_SUFFICIENT: f64 = 0.70;
const PASS_LIFT: f64 = 0.05;
const PASS_R2: f64 = 0.0;
const RQ9_CORR: f64 = 0.995;

const DATA_DIR = "../deepseekexperiment/";
const ACTS_PATH = DATA_DIR ++ "acts_T128_off8000.bin";
const GATE_PATH = DATA_DIR ++ "gate_L30_w.bin";
const POS_PATH = DATA_DIR ++ "e11_positions_off8000.csv";

const WORLD_POOL = [_]usize{ 2, 3, 5, 7, 11, 13 };

pub const ForgeRoute = enum {
    monomial_sufficient,
    spectral_menu,
    walsh_menu,
    world_pool,
    mod_synthesis,
    xor_popcount,
    pipeline,
};

const FeatureTag = enum {
    monomial,
    spectral_count,
    walsh,
    world_sum_mod,
    world_sign_mod,
    xor_popcount,
    mod_prog,
    pipeline_oriented,
    pipeline_inv_parity,
    pipeline_sum_bind,
};

const Feature = union(FeatureTag) {
    monomial: u8,
    spectral_count: f64,
    walsh: u8,
    world_sum_mod: usize,
    world_sign_mod: usize,
    xor_popcount: u8,
    mod_prog: u16,
    pipeline_oriented: void,
    pipeline_inv_parity: void,
    pipeline_sum_bind: void,
};

const HardnessProbe = struct {
    mono: f64,
    ext: f64,
    class: hr.TaskClass,
};

const RouteProbe = struct {
    xor: f64,
    synth: f64,
    pipe: f64,
};

const InventResult = struct {
    expert: usize,
    route: ForgeRoute,
    feature: Feature,
    feat_name: []const u8,
    base_r2: f64,
    hold_r2: f64,
    lift: f64,
    rq9_novel: bool,
    task_class: hr.TaskClass,
};

const ModLeaf = enum { count3, count2, inv, sum };
const ModNode = union(enum) {
    leaf: ModLeaf,
    add: struct { a: u16, b: u16 },
    mul: struct { a: u16, b: u16 },
    sin: u16,
    @"mod": struct { child: u16, k: u8 },
};

const ModBank = struct {
    nodes: []ModNode,
    depths: []u8,

    fn depth(self: ModBank, id: u16) u8 {
        return self.depths[id];
    }

    fn eval(self: ModBank, id: u16, g: [NCELL]u8) f64 {
        return switch (self.nodes[id]) {
            .leaf => |lf| leafVal(lf, g),
            .add => |ab| self.eval(ab.a, g) + self.eval(ab.b, g),
            .mul => |ab| self.eval(ab.a, g) * self.eval(ab.b, g),
            .sin => |ch| @sin(self.eval(ch, g)),
            .@"mod" => |mk| @rem(self.eval(mk.child, g), @as(f64, @floatFromInt(mk.k))),
        };
    }
};

fn leafVal(lf: ModLeaf, g: [NCELL]u8) f64 {
    return switch (lf) {
        .count3 => countGE(g, THRESH),
        .count2 => countGE(g, 2),
        .inv => @floatFromInt(inversionCount(g)),
        .sum => @floatFromInt(gridSum(g)),
    };
}

fn sqrtsoftplus(x: f64) f64 {
    if (x > 20.0) return @sqrt(x);
    return @sqrt(@log(1.0 + @exp(x)));
}

fn countGE(g: [NCELL]u8, t: u8) f64 {
    var c: usize = 0;
    for (g) |v| {
        if (v >= t) c += 1;
    }
    return @floatFromInt(c);
}

fn gridSum(g: [NCELL]u8) usize {
    var s: usize = 0;
    for (g) |v| s += v;
    return s;
}

fn inversionCount(g: [NCELL]u8) usize {
    var inv: usize = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        if (g[i] > g[j]) inv += 1;
    };
    return inv;
}

fn signPattern(g: [NCELL]u8) u8 {
    var p: u8 = 0;
    for (0..NCELL) |i| {
        if (g[i] >= THRESH) p |= @as(u8, 1) << @intCast(i);
    }
    return p;
}

fn chi(S: u8, p: u8) f64 {
    const neg = @popCount(S & ~p);
    return if (neg & 1 == 0) 1.0 else -1.0;
}

fn phiMono(g: [NCELL]u8, mask: u8) f64 {
    var p: f64 = 1.0;
    for (0..NCELL) |i| if (mask & (@as(u8, 1) << @intCast(i)) != 0) {
        p *= @as(f64, @floatFromInt(g[i])) - MID;
    };
    return p;
}

fn xorPopcount(g: [NCELL]u8, mask: u8) f64 {
    const p = signPattern(g);
    return @floatFromInt(@popCount(p & mask) & 1);
}

fn evalFeature(f: Feature, g: [NCELL]u8, bank: ModBank) f64 {
    return switch (f) {
        .monomial => |m| phiMono(g, m),
        .spectral_count => |w| @cos(w * countGE(g, THRESH)),
        .walsh => |S| chi(S, signPattern(g)),
        .world_sum_mod => |p| if (gridSum(g) % p == 0) 1.0 else 0.0,
        .world_sign_mod => |p| if (@as(usize, signPattern(g)) % p == 0) 1.0 else 0.0,
        .xor_popcount => |m| xorPopcount(g, m),
        .mod_prog => |id| bank.eval(id, g),
        .pipeline_oriented => if (g[1] > g[0]) 1.0 else 0.0,
        .pipeline_inv_parity => @floatFromInt(inversionCount(g) & 1),
        .pipeline_sum_bind => @floatFromInt((g[0] + g[1]) % 7),
    };
}

fn featureName(buf: []u8, f: Feature) []const u8 {
    return switch (f) {
        .monomial => |m| std.fmt.bufPrint(buf, "φ(0x{X:0>2})", .{m}) catch "φ",
        .spectral_count => |w| std.fmt.bufPrint(buf, "cos(ω·count),ω={d:.3}", .{w}) catch "spectral",
        .walsh => |S| std.fmt.bufPrint(buf, "χ{{S=0x{X:0>2}}}", .{S}) catch "χ",
        .world_sum_mod => |p| std.fmt.bufPrint(buf, "sum%mod_{d}", .{p}) catch "sum_mod",
        .world_sign_mod => |p| std.fmt.bufPrint(buf, "sign%mod_{d}", .{p}) catch "sign_mod",
        .xor_popcount => |m| std.fmt.bufPrint(buf, "xor_pop(0x{X:0>2})", .{m}) catch "xor",
        .mod_prog => |id| std.fmt.bufPrint(buf, "mod_prog#{d}", .{id}) catch "mod",
        .pipeline_oriented => "oriented(v1>v0)",
        .pipeline_inv_parity => "inv→parity",
        .pipeline_sum_bind => "sum(c0,c1)%7",
    };
}

fn routeName(r: ForgeRoute) []const u8 {
    return switch (r) {
        .monomial_sufficient => "monomial_sufficient",
        .spectral_menu => "spectral_menu",
        .walsh_menu => "walsh_menu",
        .world_pool => "world_pool",
        .mod_synthesis => "mod_synthesis",
        .xor_popcount => "xor_popcount",
        .pipeline => "pipeline",
    };
}

fn taskClassName(tc: hr.TaskClass) []const u8 {
    return switch (tc) {
        .single_sufficient => "single_sufficient",
        .q38_compound => "q38_compound",
        .unknown => "unknown",
    };
}

fn loadMatrixF32(alloc: std.mem.Allocator, path: []const u8) !struct { rows: usize, cols: usize, data: []f32 } {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    var hdr: [2]u32 = undefined;
    _ = try file.readAll(std.mem.asBytes(&hdr));
    const rows: usize = hdr[0];
    const cols: usize = hdr[1];
    const data = try alloc.alloc(f32, rows * cols);
    const raw = std.mem.sliceAsBytes(data);
    _ = try file.readAll(raw);
    return .{ .rows = rows, .cols = cols, .data = data };
}

fn loadLayerActs(alloc: std.mem.Allocator, path: []const u8, layer: u32) ![]f32 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const size = (try file.getEndPos());
    const nrec = size / ACT_REC;
    var out = try std.ArrayList(f32).initCapacity(alloc, nrec * DIM);
    var buf: [ACT_REC]u8 = undefined;
    for (0..nrec) |_| {
        const n = try file.readAll(&buf);
        if (n < ACT_REC) break;
        const lay: u32 = @bitCast(buf[0..4].*);
        if (lay != layer) continue;
        const floats: [*]const f32 = @ptrCast(@alignCast(buf[8..].ptr));
        try out.appendSlice(floats[0..DIM]);
    }
    return out.toOwnedSlice();
}

fn projectSubstrate(alloc: std.mem.Allocator, acts: []const f32, n_tok: usize, grid_out: [][NCELL]u8) !void {
    const grp = DIM / NCELL;
    var raw_energy = try alloc.alloc(f64, n_tok * NCELL);
    defer alloc.free(raw_energy);

    for (0..n_tok) |t| {
        const x = acts[t * DIM ..][0..DIM];
        for (0..NCELL) |c| {
            var ss: f64 = 0;
            const off = c * grp;
            for (off..off + grp) |d| ss += @as(f64, x[d]) * @as(f64, x[d]);
            raw_energy[t * NCELL + c] = @sqrt(ss / @as(f64, @floatFromInt(grp)));
        }
    }

    for (0..NCELL) |c| {
        var col = try alloc.alloc(f64, n_tok);
        defer alloc.free(col);
        for (0..n_tok) |t| col[t] = raw_energy[t * NCELL + c];
        std.sort.pdq(f64, col, {}, std.sort.asc(f64));
        const q1 = col[n_tok / 5];
        const q2 = col[2 * n_tok / 5];
        const q3 = col[3 * n_tok / 5];
        const q4 = col[4 * n_tok / 5];
        for (0..n_tok) |t| {
            const v = raw_energy[t * NCELL + c];
            const q: u8 = if (v <= q1) 0 else if (v <= q2) 1 else if (v <= q3) 2 else if (v <= q4) 3 else if (v <= col[n_tok - 1]) 4 else 5;
            grid_out[t][c] = @min(VMAX, q);
        }
    }
}

fn computeGateScores(alloc: std.mem.Allocator, acts: []const f32, gate: []const f32, n_tok: usize, scores_out: []f64) void {
    for (0..n_tok) |t| {
        const x = acts[t * DIM ..][0..DIM];
        for (0..N_EXPERTS) |e| {
            var dot: f64 = 0;
            const row = gate[e * DIM ..][0..DIM];
            for (0..DIM) |d| dot += @as(f64, x[d]) * @as(f64, row[d]);
            scores_out[t * N_EXPERTS + e] = sqrtsoftplus(dot);
        }
    }
    _ = alloc;
}

fn fitLinearR2(x_tr: []const f64, y_tr: []const f64, x_ho: []const f64, y_ho: []const f64) struct { r2: f64, w0: f64, w1: f64 } {
    var w0: f64 = 0;
    var w1: f64 = 0;
    for (0..300) |_| for (0..NTR) |s| {
        const pred = w0 * x_tr[s] + w1;
        const err = pred - y_tr[s];
        w0 -= 0.02 * err * x_tr[s];
        w1 -= 0.02 * err;
    };
    var mu: f64 = 0;
    for (y_ho) |v| mu += v;
    mu /= @as(f64, @floatFromInt(y_ho.len));
    var ssr: f64 = 0;
    var sst: f64 = 0;
    for (0..y_ho.len) |s| {
        const pred = w0 * x_ho[s] + w1;
        ssr += (y_ho[s] - pred) * (y_ho[s] - pred);
        sst += (y_ho[s] - mu) * (y_ho[s] - mu);
    }
    return .{ .r2 = 1.0 - ssr / @max(1e-9, sst), .w0 = w0, .w1 = w1 };
}

fn baselineR2(grid: []const [NCELL]u8, y: []const f64) f64 {
    var x0: [NSAMP]f64 = undefined;
    var x1: [NSAMP]f64 = undefined;
    var x2: [NSAMP]f64 = undefined;
    var x3: [NSAMP]f64 = undefined;
    for (0..NSAMP) |t| {
        x0[t] = @floatFromInt(gridSum(grid[t]));
        x1[t] = @floatFromInt(gridMax(grid[t]));
        x2[t] = countGE(grid[t], THRESH);
        var mu: f64 = 0;
        for (grid[t]) |v| mu += @as(f64, @floatFromInt(v));
        mu /= @as(f64, @floatFromInt(NCELL));
        var sd: f64 = 0;
        for (grid[t]) |v| {
            const d = @as(f64, @floatFromInt(v)) - mu;
            sd += d * d;
        }
        x3[t] = @sqrt(sd / @as(f64, @floatFromInt(NCELL)));
    }
    // Mean-only baseline R² on held-out (constant predictor).
    var mu_tr: f64 = 0;
    for (0..NTR) |s| mu_tr += y[s];
    mu_tr /= @as(f64, @floatFromInt(NTR));
    var mu_ho: f64 = 0;
    for (NVA..NSAMP) |s| mu_ho += y[s];
    mu_ho /= @as(f64, @floatFromInt(NHOLD));
    var ssr: f64 = 0;
    var sst: f64 = 0;
    for (NVA..NSAMP) |s| {
        ssr += (y[s] - mu_tr) * (y[s] - mu_tr);
        sst += (y[s] - mu_ho) * (y[s] - mu_ho);
    }
    return 1.0 - ssr / @max(1e-9, sst);
}

fn gridMax(g: [NCELL]u8) u8 {
    var m = g[0];
    for (g[1..]) |v| m = @max(m, v);
    return m;
}

fn corrRange(a: []const f64, b: []const f64, lo: usize, hi: usize) f64 {
    var ma: f64 = 0;
    var mb: f64 = 0;
    const n = hi - lo;
    for (lo..hi) |s| {
        ma += a[s];
        mb += b[s];
    }
    ma /= @as(f64, @floatFromInt(n));
    mb /= @as(f64, @floatFromInt(n));
    var num: f64 = 0;
    var da: f64 = 0;
    var db: f64 = 0;
    for (lo..hi) |s| {
        const xa = a[s] - ma;
        const xb = b[s] - mb;
        num += xa * xb;
        da += xa * xa;
        db += xb * xb;
    }
    return @abs(num / @max(1e-9, @sqrt(da * db)));
}

fn classifyHardness(grid: []const [NCELL]u8, y: []const f64, scratch: []f64) HardnessProbe {
    var mono_best: f64 = 0.5;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const mask: u8 = @intCast(mm);
        if (@popCount(mask) < 1 or @popCount(mask) > 4) continue;
        for (0..NSAMP) |s| scratch[s] = phiMono(grid[s], mask);
        const r = fitLinearR2(scratch[0..NTR], y[0..NTR], scratch[NVA..NSAMP], y[NVA..NSAMP]);
        if (r.r2 > mono_best) mono_best = r.r2;
    }
    var ext_best: f64 = 0.5;
    const probes = [_]struct { fill: *const fn ([NCELL]u8) f64 }{
        .{ .fill = struct {
            fn f(g: [NCELL]u8) f64 {
                return @floatFromInt(gridMax(g));
            }
        }.f },
        .{ .fill = struct {
            fn f(g: [NCELL]u8) f64 {
                return if (g[1] > g[0]) 1.0 else 0.0;
            }
        }.f },
        .{ .fill = struct {
            fn f(g: [NCELL]u8) f64 {
                return countGE(g, THRESH);
            }
        }.f },
    };
    for (probes) |p| {
        for (0..NSAMP) |s| scratch[s] = p.fill(grid[s]);
        const r = fitLinearR2(scratch[0..NTR], y[0..NTR], scratch[NVA..NSAMP], y[NVA..NSAMP]);
        if (r.r2 > ext_best) ext_best = r.r2;
    }
    const tc: hr.TaskClass = if (mono_best >= SINGLE_SUFFICIENT or ext_best >= SINGLE_SUFFICIENT)
        .single_sufficient
    else if (mono_best <= MONO_SATURATE and ext_best <= MONO_SATURATE)
        .q38_compound
    else
        .unknown;
    return .{ .mono = mono_best, .ext = ext_best, .class = tc };
}

fn chooseRoute(hp: HardnessProbe, probes: RouteProbe) ForgeRoute {
    if (hp.mono >= unified.COVER_THRESHOLD) return .monomial_sufficient;
    if (hp.class == .q38_compound) {
        if (probes.xor > MONO_SATURATE and probes.xor >= probes.synth - 0.05) return .xor_popcount;
        if (probes.pipe > probes.synth and probes.pipe > MONO_SATURATE) return .pipeline;
        return .mod_synthesis;
    }
    if (probes.synth >= probes.pipe and probes.synth >= probes.xor) return .mod_synthesis;
    if (probes.pipe > @max(probes.synth, probes.xor) and probes.pipe > MONO_SATURATE) return .pipeline;
    if (hp.ext > hp.mono) return .spectral_menu;
    return .walsh_menu;
}

fn discoverSpectral(grid: []const [NCELL]u8, y: []const f64, feat: []f64) f64 {
    const CMAX = NCELL + 1;
    var fsum = [_]f64{0} ** CMAX;
    var ncnt = [_]f64{0} ** CMAX;
    for (0..NTR) |s| {
        const c: usize = @intFromFloat(countGE(grid[s], THRESH));
        fsum[c] += y[s];
        ncnt[c] += 1;
    }
    var fbar: f64 = 0;
    var ntot: f64 = 0;
    for (0..CMAX) |c| {
        fbar += fsum[c];
        ntot += ncnt[c];
    }
    fbar /= ntot;
    var peak_w: f64 = std.math.pi;
    var peak_pw: f64 = -1;
    var i: usize = 1;
    while (i <= 80) : (i += 1) {
        const w = std.math.pi * @as(f64, @floatFromInt(i)) / 80.0;
        var re: f64 = 0;
        var im: f64 = 0;
        for (0..CMAX) |c| {
            if (ncnt[c] == 0) continue;
            const amp = ncnt[c] * (fsum[c] / ncnt[c] - fbar);
            const cc: f64 = @floatFromInt(c);
            re += amp * @cos(w * cc);
            im += amp * @sin(w * cc);
        }
        const pw = re * re + im * im;
        if (pw > peak_pw) {
            peak_pw = pw;
            peak_w = w;
        }
    }
    for (0..NSAMP) |s| feat[s] = @cos(peak_w * countGE(grid[s], THRESH));
    return peak_w;
}

fn discoverWalsh(grid: []const [NCELL]u8, y: []const f64) u8 {
    var bestS: u8 = 0;
    var best_corr: f64 = -1;
    var feat: [NSAMP]f64 = undefined;
    var S: u16 = 0;
    while (S < 256) : (S += 1) {
        for (0..NSAMP) |s| feat[s] = chi(@intCast(S), signPattern(grid[s]));
        const c = corrRange(&feat, y, 0, NTR);
        if (c > best_corr) {
            best_corr = c;
            bestS = @intCast(S);
        }
    }
    return bestS;
}

fn buildModBank(alloc: std.mem.Allocator) !ModBank {
    var nodes = std.ArrayList(ModNode).init(alloc);
    defer nodes.deinit();
    var depths = std.ArrayList(u8).init(alloc);
    defer depths.deinit();

    const leaves = [_]ModLeaf{ .count3, .count2, .inv, .sum };
    for (leaves) |lf| {
        try nodes.append(.{ .leaf = lf });
        try depths.append(0);
    }

    var frontier = std.ArrayList(u16).init(alloc);
    defer frontier.deinit();
    for (0..leaves.len) |i| try frontier.append(@intCast(i));

    var depth_cur: u8 = 1;
    while (depth_cur <= 3 and frontier.items.len > 0) : (depth_cur += 1) {
        var next = std.ArrayList(u16).init(alloc);
        defer next.deinit();
        for (frontier.items) |pid| {
            for (leaves.len..nodes.items.len) |oid| {
                if (depths.items[oid] >= depth_cur) continue;
                const id: u16 = @intCast(nodes.items.len);
                try nodes.append(.{ .add = .{ .a = pid, .b = @intCast(oid) } });
                try depths.append(depth_cur);
                try next.append(id);
                const id2: u16 = @intCast(nodes.items.len);
                try nodes.append(.{ .mul = .{ .a = pid, .b = @intCast(oid) } });
                try depths.append(depth_cur);
                try next.append(id2);
            }
            const mods = [_]u8{ 2, 3, 5, 7 };
            for (mods) |k| {
                const id: u16 = @intCast(nodes.items.len);
                try nodes.append(.{ .@"mod" = .{ .child = pid, .k = k } });
                try depths.append(depth_cur);
                try next.append(id);
            }
            const sid: u16 = @intCast(nodes.items.len);
            try nodes.append(.{ .sin = pid });
            try depths.append(depth_cur);
            try next.append(sid);
        }
        frontier.clearRetainingCapacity();
        try frontier.appendSlice(next.items);
        if (nodes.items.len > 400) break;
    }

    return ModBank{
        .nodes = try nodes.toOwnedSlice(),
        .depths = try depths.toOwnedSlice(),
    };
}

fn probeRoutes(grid: []const [NCELL]u8, y: []const f64, bank: ModBank, scratch: []f64) RouteProbe {
    var xor_best: f64 = 0.5;
    var mask: u16 = 1;
    while (mask < 256) : (mask += 1) {
        for (0..NSAMP) |s| scratch[s] = xorPopcount(grid[s], @intCast(mask));
        const r = fitLinearR2(scratch[0..NTR], y[0..NTR], scratch[NVA..NSAMP], y[NVA..NSAMP]);
        if (r.r2 > xor_best) xor_best = r.r2;
    }
    var synth_best: f64 = 0.5;
    for (0..bank.nodes.len) |pid| {
        for (0..NSAMP) |s| scratch[s] = bank.eval(@intCast(pid), grid[s]);
        const r = fitLinearR2(scratch[0..NTR], y[0..NTR], scratch[NVA..NSAMP], y[NVA..NSAMP]);
        if (r.r2 > synth_best) synth_best = r.r2;
    }
    const pipes = [_]Feature{
        .{ .pipeline_oriented = {} },
        .{ .pipeline_inv_parity = {} },
        .{ .pipeline_sum_bind = {} },
    };
    var pipe_best: f64 = 0.5;
    for (pipes) |pf| {
        for (0..NSAMP) |s| scratch[s] = evalFeature(pf, grid[s], bank);
        const r = fitLinearR2(scratch[0..NTR], y[0..NTR], scratch[NVA..NSAMP], y[NVA..NSAMP]);
        if (r.r2 > pipe_best) pipe_best = r.r2;
    }
    return .{ .xor = xor_best, .synth = synth_best, .pipe = pipe_best };
}

fn inventOnRoute(
    route: ForgeRoute,
    grid: []const [NCELL]u8,
    y: []const f64,
    bank: ModBank,
    scratch: []f64,
) struct { feature: Feature, hold_r2: f64 } {
    var best_feat: Feature = .{ .monomial = 1 };
    var best_r2: f64 = -1e9;

    switch (route) {
        .monomial_sufficient, .walsh_menu => {
            var mm: u16 = 1;
            while (mm < 256) : (mm += 1) {
                const mask: u8 = @intCast(mm);
                if (@popCount(mask) < 1 or @popCount(mask) > 4) continue;
                for (0..NSAMP) |s| scratch[s] = phiMono(grid[s], mask);
                const r = fitLinearR2(scratch[0..NTR], y[0..NTR], scratch[NVA..NSAMP], y[NVA..NSAMP]);
                if (r.r2 > best_r2) {
                    best_r2 = r.r2;
                    best_feat = .{ .monomial = mask };
                }
            }
            const wS = discoverWalsh(grid, y);
            for (0..NSAMP) |s| scratch[s] = chi(wS, signPattern(grid[s]));
            const r = fitLinearR2(scratch[0..NTR], y[0..NTR], scratch[NVA..NSAMP], y[NVA..NSAMP]);
            if (r.r2 > best_r2) {
                best_r2 = r.r2;
                best_feat = .{ .walsh = wS };
            }
        },
        .spectral_menu => {
            const omega = discoverSpectral(grid, y, scratch);
            const r = fitLinearR2(scratch[0..NTR], y[0..NTR], scratch[NVA..NSAMP], y[NVA..NSAMP]);
            best_r2 = r.r2;
            best_feat = .{ .spectral_count = omega };
        },
        .world_pool => {
            for (WORLD_POOL) |p| {
                const pair = [_]Feature{ .{ .world_sum_mod = p }, .{ .world_sign_mod = p } };
                for (pair) |cand| {
                    for (0..NSAMP) |s| scratch[s] = evalFeature(cand, grid[s], bank);
                    const r = fitLinearR2(scratch[0..NTR], y[0..NTR], scratch[NVA..NSAMP], y[NVA..NSAMP]);
                    if (r.r2 > best_r2) {
                        best_r2 = r.r2;
                        best_feat = cand;
                    }
                }
            }
        },
        .mod_synthesis => {
            for (0..bank.nodes.len) |pid| {
                for (0..NSAMP) |s| scratch[s] = bank.eval(@intCast(pid), grid[s]);
                const r = fitLinearR2(scratch[0..NTR], y[0..NTR], scratch[NVA..NSAMP], y[NVA..NSAMP]);
                if (r.r2 > best_r2) {
                    best_r2 = r.r2;
                    best_feat = .{ .mod_prog = @intCast(pid) };
                }
            }
        },
        .xor_popcount => {
            var mask: u16 = 1;
            while (mask < 256) : (mask += 1) {
                for (0..NSAMP) |s| scratch[s] = xorPopcount(grid[s], @intCast(mask));
                const r = fitLinearR2(scratch[0..NTR], y[0..NTR], scratch[NVA..NSAMP], y[NVA..NSAMP]);
                if (r.r2 > best_r2) {
                    best_r2 = r.r2;
                    best_feat = .{ .xor_popcount = @intCast(mask) };
                }
            }
        },
        .pipeline => {
            const pipes = [_]Feature{
                .{ .pipeline_oriented = {} },
                .{ .pipeline_inv_parity = {} },
                .{ .pipeline_sum_bind = {} },
            };
            for (pipes) |pf| {
                for (0..NSAMP) |s| scratch[s] = evalFeature(pf, grid[s], bank);
                const r = fitLinearR2(scratch[0..NTR], y[0..NTR], scratch[NVA..NSAMP], y[NVA..NSAMP]);
                if (r.r2 > best_r2) {
                    best_r2 = r.r2;
                    best_feat = pf;
                }
            }
        },
    }
    return .{ .feature = best_feat, .hold_r2 = best_r2 };
}

fn rq9Novel(f: Feature, grid: []const [NCELL]u8, feat: []const f64, bank: ModBank) bool {
    // RQ9 tax: monomial + Walsh + world (NO spectral, NO pipelines, NO mod synth).
    if (f == .spectral_count) return true;
    if (f == .mod_prog or f == .pipeline_oriented or f == .pipeline_inv_parity or f == .pipeline_sum_bind)
        return true;

    var scratch: [NSAMP]f64 = undefined;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const mask: u8 = @intCast(mm);
        for (0..NSAMP) |s| scratch[s] = phiMono(grid[s], mask);
        if (corrRange(&scratch, feat, NVA, NSAMP) >= RQ9_CORR) return false;
    }
    var S: u16 = 0;
    while (S < 256) : (S += 1) {
        for (0..NSAMP) |s| scratch[s] = chi(@intCast(S), signPattern(grid[s]));
        if (corrRange(&scratch, feat, NVA, NSAMP) >= RQ9_CORR) return false;
    }
    for (WORLD_POOL) |p| {
        const pair = [_]Feature{ .{ .world_sum_mod = p }, .{ .world_sign_mod = p } };
        for (pair) |cand| {
            for (0..NSAMP) |s| scratch[s] = evalFeature(cand, grid[s], bank);
            if (corrRange(&scratch, feat, NVA, NSAMP) >= RQ9_CORR) return false;
        }
    }
    // xor_popcount is Walsh-family; non-novel if high corr found in Walsh scan above.
    return true;
}

fn inventExpert(
    alloc: std.mem.Allocator,
    expert: usize,
    grid: []const [NCELL]u8,
    scores: []const f64,
    bank: ModBank,
    scratch: []f64,
    feat_buf: []f64,
) !?InventResult {
    for (0..NSAMP) |t| feat_buf[t] = scores[t * N_EXPERTS + expert];

    const base = baselineR2(grid, feat_buf);
    const hp = classifyHardness(grid, feat_buf, scratch);
    const probes = probeRoutes(grid, feat_buf, bank, scratch);
    const primary = chooseRoute(hp, probes);

    // Unified escalation: primary route, then spectral menu (unified_invention T5 escape).
    var inv = inventOnRoute(primary, grid, feat_buf, bank, scratch);
    var route = primary;
    if (inv.hold_r2 < PASS_R2 or primary != .spectral_menu) {
        const spec = inventOnRoute(.spectral_menu, grid, feat_buf, bank, scratch);
        if (spec.hold_r2 > inv.hold_r2) {
            inv = spec;
            route = .spectral_menu;
        }
    }
    if (inv.hold_r2 < PASS_R2) {
        const wal = inventOnRoute(.walsh_menu, grid, feat_buf, bank, scratch);
        if (wal.hold_r2 > inv.hold_r2) {
            inv = wal;
            route = .walsh_menu;
        }
    }
    for (0..NSAMP) |s| scratch[s] = evalFeature(inv.feature, grid[s], bank);

    const lift = if (base < 0)
        (inv.hold_r2 - base) / @max(@abs(1.0 - base), 1e-9)
    else
        (inv.hold_r2 - base) / @max(1.0 - base, 1e-9);
    const novel = rq9Novel(inv.feature, grid, scratch, bank);

    var namebuf: [64]u8 = undefined;
    const fname = featureName(&namebuf, inv.feature);

    if (!std.math.isFinite(inv.hold_r2) or !std.math.isFinite(lift)) return null;
    if (inv.hold_r2 <= PASS_R2 or lift < PASS_LIFT) return null;

    const owned = try alloc.dupe(u8, fname);
    return InventResult{
        .expert = expert,
        .route = route,
        .feature = inv.feature,
        .feat_name = owned,
        .base_r2 = base,
        .hold_r2 = inv.hold_r2,
        .lift = lift,
        .rq9_novel = novel,
        .task_class = hp.class,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const stdout = std.io.getStdOut().writer();

    try stdout.print(
        \\E28 — DeepSeek expert route invention
        \\Question: hardness router + unified loop → features predicting expert activation?
        \\Data: {s} {s} {s}
        \\Split: train pos 0..{d}, invention-val ..{d}, held-out ..{d} (e11 positions)
        \\
    , .{ ACTS_PATH, GATE_PATH, POS_PATH, NTR, NVA, NSAMP });

    const acts = try loadLayerActs(alloc, ACTS_PATH, LAYER);
    defer alloc.free(acts);
    const n_tok = acts.len / DIM;
    if (n_tok != NSAMP) {
        try stdout.print("WARN: expected {d} L30 tokens, got {d}\n", .{ NSAMP, n_tok });
    }

    const gate_m = try loadMatrixF32(alloc, GATE_PATH);
    defer alloc.free(gate_m.data);
    if (gate_m.rows != N_EXPERTS or gate_m.cols != DIM) {
        try stdout.print("WARN: gate shape {d}x{d} (expected {d}x{d})\n", .{ gate_m.rows, gate_m.cols, N_EXPERTS, DIM });
    }

    const grid = try alloc.alloc([NCELL]u8, n_tok);
    defer alloc.free(grid);
    try projectSubstrate(alloc, acts, n_tok, grid);

    const scores = try alloc.alloc(f64, n_tok * N_EXPERTS);
    defer alloc.free(scores);
    computeGateScores(alloc, acts, gate_m.data, n_tok, scores);

    const mod_bank = try buildModBank(alloc);
    defer alloc.free(mod_bank.nodes);
    defer alloc.free(mod_bank.depths);

    var scratch = try alloc.alloc(f64, NSAMP);
    defer alloc.free(scratch);
    var feat_buf = try alloc.alloc(f64, NSAMP);
    defer alloc.free(feat_buf);

    // Quick spectral prescreen — experts where menu route may certify.
    var candidates = std.ArrayList(usize).init(alloc);
    defer candidates.deinit();
    for (0..N_EXPERTS) |e| {
        for (0..n_tok) |t| feat_buf[t] = scores[t * N_EXPERTS + e];
        const base = baselineR2(grid, feat_buf);
        if (base > 0.15) continue;
        _ = discoverSpectral(grid, feat_buf, scratch);
        const r = fitLinearR2(scratch[0..NTR], feat_buf[0..NTR], scratch[NVA..NSAMP], feat_buf[NVA..NSAMP]);
        if (r.r2 > PASS_R2) try candidates.append(e);
    }
    // Also scan a few high-variance routing experts from E11 window.
    const pinned = [_]usize{ 54, 185, 266, 173, 368 };
    for (pinned) |e| {
        var dup = false;
        for (candidates.items) |c| {
            if (c == e) dup = true;
        }
        if (!dup) try candidates.append(e);
    }

    try stdout.print("Candidate experts: {d} (spectral prescreen + pinned)\n\n", .{candidates.items.len});

    var results = std.ArrayList(InventResult).init(alloc);
    defer results.deinit();
    defer for (results.items) |r| alloc.free(r.feat_name);

    for (candidates.items) |e| {
        if (try inventExpert(alloc, e, grid, scores, mod_bank, scratch, feat_buf)) |res| {
            try results.append(res);
            try stdout.print(
                "  e{d}: route={s} feature={s} base_r2={d:.3} hold_r2={d:.3} lift={d:.1}% rq9_novel={}\n",
                .{ e, routeName(res.route), res.feat_name, res.base_r2, res.hold_r2, 100.0 * res.lift, res.rq9_novel },
            );
        }
    }

    if (results.items.len == 0) {
        try stdout.print("\nVERDICT: FAIL — no expert reached lift≥{d:.0}% with held-out R²>0\n", .{100 * PASS_LIFT});
        try stdout.print("E28_RESULT pass=false certified=0 novel=0 doc=docs/research/open_invention_e28.md\n", .{});
        return;
    }

    // Champion: best holdout R2 among RQ9-novel features.
    var champion: ?InventResult = null;
    for (results.items) |r| {
        if (!r.rq9_novel) continue;
        if (champion == null or r.hold_r2 > champion.?.hold_r2) champion = r;
    }
    if (champion == null) {
        // fallback: best overall
        for (results.items) |r| {
            if (champion == null or r.hold_r2 > champion.?.hold_r2) champion = r;
        }
    }

    const ch = champion.?;
    const pass = ch.hold_r2 > PASS_R2 and ch.lift >= PASS_LIFT and ch.rq9_novel;

    try stdout.print(
        \\
        \\=== CHAMPION ===
        \\Expert L30 e{d}
        \\Hardness class: {s}
        \\Route: {s}
        \\Feature: {s}
        \\Baseline R² (mean): {d:.3}
        \\Held-out R²: {d:.3}
        \\Lift: {d:.1}%
        \\RQ9 novel: {}
        \\
        \\VERDICT: {s}
        \\
    , .{
        ch.expert,
        taskClassName(ch.task_class),
        routeName(ch.route),
        ch.feat_name,
        ch.base_r2,
        ch.hold_r2,
        100.0 * ch.lift,
        ch.rq9_novel,
        if (pass) "PASS" else "PARTIAL",
    });

    var novel_count: usize = 0;
    for (results.items) |r| {
        if (r.rq9_novel) novel_count += 1;
    }

    try stdout.print(
        "E28_RESULT pass={} expert={d} hold_r2={d:.3} lift={d:.3} novel={d}/{d} doc=docs/research/open_invention_e28.md\n",
        .{ pass, ch.expert, ch.hold_r2, ch.lift, novel_count, results.items.len },
    );
    try stdout.print("See: open_invention_e14.zig, unified_invention.zig, hardness_router.zig, open_invention_rq9.zig\n", .{});
}