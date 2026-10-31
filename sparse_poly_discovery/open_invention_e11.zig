//! EXPERIMENT E11 — LLM as proposer, engine as sole judge.
//!
//! The LLM (the model that authored e11_proposals.json) proposes diverse grid features as JSON
//! structs {name, formula_kind, params}. This harness is the honest certifier: logistic readout,
//! held-out test accuracy ≥0.90 required. Targets: parity-of-count, hidden pair (2,5), sum(g)%7.
//!
//! Novelty gate: accepted features are checked for equivalence to Walsh χ_S, spectral cos(ω·count),
//! or centered monomial φ_mask families (|ρ|≥0.995 on held-out samples).
//!
//! Run: zig build open-invention-e11 --release=fast
//!      zig build open-invention-e11 --release=fast -- e11_proposals.json

const std = @import("std");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
const NSAMP: usize = 7000;
const NTR: usize = 3500;
const NVA: usize = 5250;
const DOM: usize = 1 << NCELL;
const CERT: f64 = 0.90;
const EQUIV: f64 = 0.995;

const Target = enum { parity, hidden_pair, sum_mod };
const target_name = [_][]const u8{ "parity", "hidden_pair", "sum_mod" };

pub const FormulaKind = enum {
    monomial,
    walsh,
    spectral_count,
    count_parity,
    hidden_xor,
    sum_mod_indicator,
    median_centered,
    variance_sin,
    gcd_masked,
    xor_popcount,
    max_min_diff,
    sum_sq_mod,
    lcm_masked_mod,
    cell_diff_oriented,
    product_mod,
    harmonic_mean,
    cell_values_xor_parity,
    sign_pattern_int_mod,
    abs_diff_pair,
};

pub const Params = struct {
    subset: u8 = 0,
    mask: u8 = 0,
    omega: f64 = 0,
    modulus: usize = 2,
    i: usize = 0,
    j: usize = 1,
    scale: f64 = 1.0,
    value: u8 = 1,
};

pub const Proposal = struct {
    name: []const u8,
    formula_kind: FormulaKind,
    params: Params,
};

const Family = enum { walsh, spectral, monomial, novel, @"unknown" };
const family_name = [_][]const u8{ "walsh", "spectral", "monomial", "novel", "unknown" };

const Result = struct {
    proposal: Proposal,
    target: Target,
    val_acc: f64,
    tst_acc: f64,
    certified: bool,
    family: Family,
};

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
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

fn countGE(g: [NCELL]u8) f64 {
    var c: usize = 0;
    for (g) |v| if (v >= THRESH) {
        c += 1;
    };
    return @floatFromInt(c);
}

fn gridSum(g: [NCELL]u8) usize {
    var s: usize = 0;
    for (g) |v| s += v;
    return s;
}

fn phiMono(g: [NCELL]u8, mask: u8) f64 {
    var p: f64 = 1.0;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) != 0) p *= (@as(f64, @floatFromInt(g[i])) - MID);
    }
    return p;
}

fn gcd2(a: usize, b: usize) usize {
    var x = a;
    var y = b;
    while (y != 0) {
        const t = y;
        y = x % y;
        x = t;
    }
    return x;
}

fn gcdMasked(g: [NCELL]u8, mask: u8) usize {
    var g0: usize = 0;
    var started = false;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) == 0) continue;
        const v: usize = g[i];
        if (!started) {
            g0 = v;
            started = true;
        } else g0 = gcd2(g0, v);
    }
    return if (started) g0 else 1;
}

fn lcmMasked(g: [NCELL]u8, mask: u8) usize {
    var l: usize = 1;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) == 0) continue;
        const v: usize = @max(1, g[i]);
        l = (l * v) / gcd2(l, v);
    }
    return l;
}

fn medianU8(g: [NCELL]u8) f64 {
    var s = g;
    std.sort.pdq(u8, &s, {}, std.sort.asc(u8));
    return (@as(f64, @floatFromInt(s[NCELL / 2 - 1])) + @as(f64, @floatFromInt(s[NCELL / 2]))) / 2.0;
}

fn variance(g: [NCELL]u8) f64 {
    var mu: f64 = 0;
    for (g) |v| mu += @as(f64, @floatFromInt(v));
    mu /= @as(f64, @floatFromInt(NCELL));
    var v: f64 = 0;
    for (g) |c| {
        const d = @as(f64, @floatFromInt(c)) - mu;
        v += d * d;
    }
    return v / @as(f64, @floatFromInt(NCELL));
}

fn harmonicMean(g: [NCELL]u8) f64 {
    var inv: f64 = 0;
    for (g) |v| inv += 1.0 / @as(f64, @floatFromInt(@max(1, v)));
    return @as(f64, @floatFromInt(NCELL)) / inv;
}

pub fn label(g: [NCELL]u8, t: Target) f64 {
    return switch (t) {
        .parity => blk: {
            var c: usize = 0;
            for (g) |v| if (v >= THRESH) {
                c += 1;
            };
            break :blk if (c & 1 == 1) 1.0 else 0.0;
        },
        .hidden_pair => if ((g[2] >= THRESH) != (g[5] >= THRESH)) 1.0 else 0.0,
        .sum_mod => if (gridSum(g) % 7 == 0) 1.0 else 0.0,
    };
}

pub fn evalFeature(g: [NCELL]u8, kind: FormulaKind, p: Params) f64 {
    return switch (kind) {
        .monomial => phiMono(g, p.mask),
        .walsh => chi(p.subset, signPattern(g)),
        .spectral_count => @cos(p.omega * countGE(g)),
        .count_parity => blk: {
            var c: usize = 0;
            for (g) |v| if (v >= THRESH) {
                c += 1;
            };
            break :blk if (c & 1 == 1) 1.0 else -1.0;
        },
        .hidden_xor => if ((g[p.i] >= THRESH) != (g[p.j] >= THRESH)) 1.0 else -1.0,
        .sum_mod_indicator => if (gridSum(g) % p.modulus == 0) 1.0 else 0.0,
        .median_centered => medianU8(g) - MID,
        .variance_sin => @sin(p.scale * variance(g)),
        .gcd_masked => @as(f64, @floatFromInt(gcdMasked(g, p.mask))),
        .xor_popcount => blk: {
            const pc = @popCount(signPattern(g));
            break :blk if (pc & 1 == 1) 1.0 else -1.0;
        },
        .max_min_diff => blk: {
            var mn: u8 = VMAX;
            var mx: u8 = 0;
            for (g) |v| {
                mn = @min(mn, v);
                mx = @max(mx, v);
            }
            break :blk @as(f64, @floatFromInt(mx - mn));
        },
        .sum_sq_mod => blk: {
            var s: usize = 0;
            for (g) |v| s += v * v;
            break :blk @as(f64, @floatFromInt(s % p.modulus));
        },
        .lcm_masked_mod => @as(f64, @floatFromInt(lcmMasked(g, p.mask) % p.modulus)),
        .cell_diff_oriented => if (g[p.i] > g[p.j]) 1.0 else -1.0,
        .product_mod => blk: {
            var pr: usize = 1;
            for (0..NCELL) |i| {
                if (p.mask & (@as(u8, 1) << @intCast(i)) == 0) continue;
                pr = (pr * g[i]) % p.modulus;
            }
            break :blk @as(f64, @floatFromInt(pr));
        },
        .harmonic_mean => harmonicMean(g),
        .cell_values_xor_parity => blk: {
            var x: u8 = 0;
            for (g) |v| x ^= v;
            break :blk if (x & 1 == 1) 1.0 else -1.0;
        },
        .sign_pattern_int_mod => @as(f64, @floatFromInt(@as(usize, signPattern(g)) % p.modulus)),
        .abs_diff_pair => @as(f64, @floatFromInt(@abs(@as(i32, @intCast(g[p.i])) - @as(i32, @intCast(g[p.j]))))),
    };
}

pub fn accLogit(feat: []const f64, Y: []const f64, lo: usize, hi: usize) f64 {
    var w: [2]f64 = .{ 0.0, 0.0 };
    for (0..80) |_| for (0..NTR) |s| {
        const e = sigmoid(w[0] * feat[s] + w[1]) - Y[s];
        w[0] -= 0.1 * e * feat[s];
        w[1] -= 0.1 * e;
    };
    var c: usize = 0;
    for (lo..hi) |s| {
        if ((w[0] * feat[s] + w[1] >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(hi - lo));
}

fn pearson(a: []const f64, b: []const f64, lo: usize, hi: usize) f64 {
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
    const den = @sqrt(da * db);
    if (den < 1e-12) return 0;
    return num / den;
}

fn classifyFamily(
    grid: []const [NCELL]u8,
    feat: []const f64,
    lo: usize,
    hi: usize,
    scratch: []f64,
) Family {
    // Walsh family
    for (0..DOM) |S| {
        for (lo..hi) |s| scratch[s] = chi(@intCast(S), signPattern(grid[s]));
        if (@abs(pearson(feat, scratch, lo, hi)) >= EQUIV) return .walsh;
    }
    // Spectral family: cos/sin(ω·count)
    const NF = 120;
    var k: usize = 1;
    while (k <= NF) : (k += 1) {
        const w = std.math.pi * @as(f64, @floatFromInt(k)) / @as(f64, @floatFromInt(NF));
        for (lo..hi) |s| scratch[s] = @cos(w * countGE(grid[s]));
        if (@abs(pearson(feat, scratch, lo, hi)) >= EQUIV) return .spectral;
        for (lo..hi) |s| scratch[s] = @sin(w * countGE(grid[s]));
        if (@abs(pearson(feat, scratch, lo, hi)) >= EQUIV) return .spectral;
    }
    // Monomial family
    for (0..DOM) |m| {
        for (lo..hi) |s| scratch[s] = phiMono(grid[s], @intCast(m));
        if (@abs(pearson(feat, scratch, lo, hi)) >= EQUIV) return .monomial;
    }
    return .novel;
}

pub fn parseFormulaKind(s: []const u8) !FormulaKind {
    inline for (std.meta.fields(FormulaKind)) |f| {
        if (std.mem.eql(u8, s, f.name)) return @field(FormulaKind, f.name);
    }
    return error.UnknownFormulaKind;
}

pub fn parseParams(val: std.json.Value) Params {
    var p = Params{};
    if (val != .object) return p;
    const o = val.object;
    if (o.get("subset")) |v| {
        if (v == .integer) p.subset = @intCast(@max(0, @min(255, v.integer)));
    }
    if (o.get("mask")) |v| {
        if (v == .integer) p.mask = @intCast(@max(0, @min(255, v.integer)));
    }
    if (o.get("omega")) |v| {
        if (v == .float) p.omega = v.float;
    }
    if (o.get("modulus")) |v| {
        if (v == .integer) p.modulus = @intCast(@max(1, v.integer));
    }
    if (o.get("i")) |v| {
        if (v == .integer) p.i = @intCast(@max(0, @min(NCELL - 1, v.integer)));
    }
    if (o.get("j")) |v| {
        if (v == .integer) p.j = @intCast(@max(0, @min(NCELL - 1, v.integer)));
    }
    if (o.get("scale")) |v| {
        if (v == .float) p.scale = v.float;
    }
    if (o.get("value")) |v| {
        if (v == .integer) p.value = @intCast(@max(0, @min(VMAX, v.integer)));
    }
    return p;
}

fn loadProposals(alloc: std.mem.Allocator, path: []const u8) ![]Proposal {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const raw = try file.readToEndAlloc(alloc, 1024 * 1024);
    defer alloc.free(raw);
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.ExpectedJSONArray;
    const arr = parsed.value.array;
    var out = try alloc.alloc(Proposal, arr.items.len);
    errdefer alloc.free(out);
    for (arr.items, 0..) |item, i| {
        if (item != .object) return error.ExpectedProposalObject;
        const o = item.object;
        const name_v = o.get("name") orelse return error.MissingName;
        const kind_v = o.get("formula_kind") orelse return error.MissingFormulaKind;
        if (name_v != .string or kind_v != .string) return error.BadProposalField;
        const name = try alloc.dupe(u8, name_v.string);
        const kind = try parseFormulaKind(kind_v.string);
        const params = if (o.get("params")) |pv| parseParams(pv) else Params{};
        out[i] = .{ .name = name, .formula_kind = kind, .params = params };
    }
    return out;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    const json_path = if (args.len > 1) args[1] else "e11_proposals.json";

    const proposals = try loadProposals(alloc, json_path);
    defer {
        for (proposals) |p| alloc.free(p.name);
        alloc.free(proposals);
    }

    var prng = std.Random.DefaultPrng.init(0xE11C0DE20260629);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    defer alloc.free(grid);
    const Y = try alloc.alloc([]f64, 3);
    defer alloc.free(Y);
    for (0..3) |ti| Y[ti] = try alloc.alloc(f64, NSAMP);
    defer for (Y) |y| alloc.free(y);

    const feat = try alloc.alloc(f64, NSAMP);
    defer alloc.free(feat);
    const scratch = try alloc.alloc(f64, NSAMP);
    defer alloc.free(scratch);

    for (0..NSAMP) |s| {
        for (0..NCELL) |i| grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
        inline for (0..3) |ti| Y[ti][s] = label(grid[s], @enumFromInt(ti));
    }

    try out.print("=== EXPERIMENT E11: LLM proposer, engine sole judge ===\n\n", .{});
    try out.print("Proposals file: {s}\n", .{json_path});
    try out.print("Proposals: {d}   Cert threshold: held-out test ≥ {d:.2}\n", .{ proposals.len, CERT });
    try out.print("Targets: parity-of-count | hidden pair (2,5) | sum(g)%%7\n", .{});
    try out.print("Split: train {d} / val {d} / test {d}\n\n", .{ NTR, NVA - NTR, NSAMP - NVA });

    var results = std.ArrayList(Result).init(alloc);
    defer results.deinit();

    try out.print("──────── certification matrix ────────\n", .{});
    try out.print("proposal                  | target       | val   | test  | cert | family\n", .{});
    try out.print("--------------------------+--------------+-------+-------+------+--------\n", .{});

    for (proposals) |prop| {
        for (0..3) |ti| {
            const t: Target = @enumFromInt(ti);
            for (0..NSAMP) |s| feat[s] = evalFeature(grid[s], prop.formula_kind, prop.params);
            const val = accLogit(feat, Y[ti], NTR, NVA);
            const tst = accLogit(feat, Y[ti], NVA, NSAMP);
            const certified = tst >= CERT;
            const family: Family = if (certified) classifyFamily(grid, feat, NVA, NSAMP, scratch) else .@"unknown";
            try results.append(.{
                .proposal = prop,
                .target = t,
                .val_acc = val,
                .tst_acc = tst,
                .certified = certified,
                .family = family,
            });
            const cert_mark: []const u8 = if (certified) "✓" else " ";
            try out.print("{s:<25} | {s:<12} | {d:.3} | {d:.3} |  {s}   | {s}\n", .{
                prop.name,
                target_name[ti],
                val,
                tst,
                cert_mark,
                if (certified) family_name[@intFromEnum(family)] else "—",
            });
        }
    }

    var n_cert: usize = 0;
    var n_novel: usize = 0;
    var any_novel = false;
    for (results.items) |r| {
        if (!r.certified) continue;
        n_cert += 1;
        if (r.family == .novel) {
            n_novel += 1;
            any_novel = true;
        }
    }

    try out.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try out.print("Proposals submitted : {d}\n", .{proposals.len});
    try out.print("Certified (test≥{d:.2}): {d} proposal×target pairs\n", .{ CERT, n_cert });
    try out.print("Novel (not Walsh/spectral/monomial): {d}\n", .{n_novel});

    if (any_novel) {
        try out.print("\nNOVEL ACCEPTANCES (engine-certified, family-orthogonal):\n", .{});
        for (results.items) |r| {
            if (r.certified and r.family == .novel) {
                try out.print("  • {s} on {s} (test={d:.3})\n", .{ r.proposal.name, target_name[@intFromEnum(r.target)], r.tst_acc });
            }
        }
        try out.print("\nPASS — at least one accepted feature is genuinely outside Walsh/spectral/monomial.\n", .{});
    } else if (n_cert > 0) {
        try out.print("\nFAIL (novelty) — certified features are all Walsh/spectral/monomial renamings.\n", .{});
    } else {
        try out.print("\nFAIL — no proposal reached the certification bar.\n", .{});
    }

    try out.print("\nSee: docs/research/open_invention_e11.md, operator_menu.zig, unified_invention.zig\n", .{});
}