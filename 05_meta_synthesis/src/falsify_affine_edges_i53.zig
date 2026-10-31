//! I53 attack (c) — statement precision of the Tier-A affine/GF(2) theorem
//! (05_meta_synthesis/docs/07/affine_closure_tierA_2026_05_28.md), by
//! brute-force enumeration at small widths. Standalone; ports no repo code.
//!
//! Checked claims:
//!  T1 "two distinct affine maps over GF(2)^n differ on >= 2^(n-1) inputs"
//!     (used to argue W2's 1e6-sample check has failure prob 2^-1e6)
//!     -> exhaustive over ALL pairs of affine maps at n=3; sampled at n=4.
//!  T2 "P affine is completely determined by its values on the 65-point
//!     affine basis {0, e_0..e_63}" (W2b, called 'the load-bearing all-inputs
//!     proof') -> TRUE among affine maps, but W2b alone accepts NON-affine
//!     impostors: enumerate ALL 16.7M functions GF(2)^3->GF(2)^3 and count
//!     functions that pass the basis check without being affine. Also build
//!     an explicit width-64 impostor that passes all 65 points.
//!  T3 "an affine recurrence x_{n+1} = M x_n + c satisfies a GF(2) linear
//!     recurrence of order <= 64 (Cayley-Hamilton)" -> exhaustive
//!     Berlekamp-Massey at n=1..3, sampled at n=4..8. Edge case: c != 0.
//!
//! Build: zig build-exe -O ReleaseFast src/falsify_affine_edges_i53.zig
//! Run:   single thread, < 1 min.

const std = @import("std");

// ---------------------------------------------------------------- GF(2) ----

// y = M x + c at width n<=8: M given as n row-masks, x as bits of a u8.
fn affApply2(n: u4, rows: []const u8, c: u8, x: u8) u8 {
    var y: u8 = 0;
    for (0..n) |j| {
        const p: u8 = @popCount(rows[j] & x) & 1;
        y |= (p << @intCast(j));
    }
    return y ^ c;
}

// Berlekamp-Massey over GF(2): minimal LFSR length of bit sequence s.
fn berlekampMassey(alloc: std.mem.Allocator, s: []const u1) !usize {
    const n = s.len;
    var C = try alloc.alloc(u1, n + 1);
    defer alloc.free(C);
    var B = try alloc.alloc(u1, n + 1);
    defer alloc.free(B);
    const T = try alloc.alloc(u1, n + 1);
    defer alloc.free(T);
    @memset(C, 0);
    @memset(B, 0);
    C[0] = 1;
    B[0] = 1;
    var L: usize = 0;
    var m: usize = 1;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        // discrepancy
        var d: u1 = s[i];
        var j: usize = 1;
        while (j <= L) : (j += 1) {
            d ^= C[j] & s[i - j];
        }
        if (d == 0) {
            m += 1;
        } else if (2 * L <= i) {
            @memcpy(T, C);
            var k: usize = 0;
            while (k + m <= n) : (k += 1) {
                C[k + m] ^= B[k];
            }
            L = i + 1 - L;
            @memcpy(B, T);
            m = 1;
        } else {
            var k: usize = 0;
            while (k + m <= n) : (k += 1) {
                C[k + m] ^= B[k];
            }
            m += 1;
        }
    }
    return L;
}

fn isAffineFn(n: u4, tt: []const u8) bool {
    const c = tt[0];
    const nn = @as(usize, 1) << n;
    var x: usize = 0;
    while (x < nn) : (x += 1) {
        var y: usize = 0;
        while (y < nn) : (y += 1) {
            if (tt[x ^ y] != (tt[x] ^ tt[y] ^ c)) return false;
        }
    }
    return true;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const w = std.io.getStdOut().writer();
    var prng = std.Random.DefaultPrng.init(0x1D53_2026_0710);
    const rnd = prng.random();

    try w.print("=====================================================================\n", .{});
    try w.print("I53 attack (c): affine/GF(2) theorem edge cases (brute force)\n", .{});
    try w.print("=====================================================================\n", .{});

    // ---------------- T1: minimum pairwise disagreement -------------------
    {
        try w.print("\n[T1] distinct affine maps differ on >= 2^(n-1) inputs?\n", .{});
        const n: u4 = 3;
        const nn: usize = 8;
        const n_maps: usize = 1 << (3 * 3 + 3); // 4096
        var tables = try alloc.alloc([8]u8, n_maps);
        defer alloc.free(tables);
        var mi: usize = 0;
        while (mi < n_maps) : (mi += 1) {
            const rows = [_]u8{
                @intCast(mi & 7),
                @intCast((mi >> 3) & 7),
                @intCast((mi >> 6) & 7),
            };
            const c: u8 = @intCast((mi >> 9) & 7);
            for (0..nn) |x| tables[mi][x] = affApply2(n, &rows, c, @intCast(x));
        }
        // NOTE: different (M,c) can encode the SAME map only if identical
        // truth table; we compare truth tables directly.
        var min_dis: usize = 99;
        var n_below: usize = 0;
        var checked: usize = 0;
        var a: usize = 0;
        while (a < n_maps) : (a += 1) {
            var b: usize = a + 1;
            while (b < n_maps) : (b += 1) {
                if (std.mem.eql(u8, &tables[a], &tables[b])) continue; // same map
                checked += 1;
                var dis: usize = 0;
                for (0..nn) |x| {
                    if (tables[a][x] != tables[b][x]) dis += 1;
                }
                if (dis < min_dis) min_dis = dis;
                if (dis < nn / 2) n_below += 1;
            }
        }
        try w.print("  n=3: ALL {d} distinct-map pairs: min disagreement = {d} (claim: >= {d})\n", .{ checked, min_dis, nn / 2 });
        try w.print("  pairs violating the bound: {d}   -> {s}\n", .{ n_below, if (n_below == 0) "T1 HOLDS (exhaustive)" else "T1 BROKEN" });

        // n=4 sampled
        const n4: u4 = 4;
        var min4: usize = 99;
        var viol4: usize = 0;
        var t: usize = 0;
        while (t < 2_000_000) : (t += 1) {
            var rowsA: [4]u8 = undefined;
            var rowsB: [4]u8 = undefined;
            for (0..4) |j| {
                rowsA[j] = @intCast(rnd.int(u4));
                rowsB[j] = @intCast(rnd.int(u4));
            }
            const cA: u8 = rnd.int(u4);
            const cB: u8 = rnd.int(u4);
            var dis: usize = 0;
            var same = true;
            for (0..16) |x| {
                const ya = affApply2(n4, &rowsA, cA, @intCast(x));
                const yb = affApply2(n4, &rowsB, cB, @intCast(x));
                if (ya != yb) {
                    dis += 1;
                    same = false;
                }
            }
            if (same) continue;
            if (dis < min4) min4 = dis;
            if (dis < 8) viol4 += 1;
        }
        try w.print("  n=4: 2M random pairs: min disagreement = {d} (claim >= 8), violations = {d}\n", .{ min4, viol4 });
    }

    // ---------------- T2: W2b basis check soundness ------------------------
    {
        try w.print("\n[T2] W2b: 'agreement on the affine basis proves agreement everywhere'\n", .{});
        try w.print("     - TRUE if P is affine (W1). How unsound is W2b WITHOUT W1?\n", .{});
        const n: u4 = 3;
        // reference affine map g = identity. Basis points {0, e0, e1, e2} = {0,1,2,4}.
        // enumerate all 8^8 = 16.7M functions f: GF(2)^3 -> GF(2)^3
        var passers: usize = 0;
        var affine_passers: usize = 0;
        var affine_total: usize = 0;
        var example_code: u32 = 0;
        var code: u32 = 0;
        const total: u32 = 1 << 24;
        while (code < total) : (code +%= 1) {
            var tt: [8]u8 = undefined;
            for (0..8) |x| tt[x] = @intCast((code >> @intCast(3 * x)) & 7);
            const is_aff = isAffineFn(n, &tt);
            if (is_aff) affine_total += 1;
            if (tt[0] == 0 and tt[1] == 1 and tt[2] == 2 and tt[4] == 4) {
                passers += 1;
                if (is_aff) {
                    affine_passers += 1;
                } else if (example_code == 0) {
                    example_code = code;
                }
            }
            if (code == total - 1) break;
        }
        try w.print("  n=3, all 16,777,216 functions vs g=identity:\n", .{});
        try w.print("    functions passing the 4-point basis check : {d}\n", .{passers});
        try w.print("    of those, actually affine                 : {d}\n", .{affine_passers});
        try w.print("    NON-affine impostors accepted by W2b-alone: {d}\n", .{passers - affine_passers});
        try w.print("    (affine functions total: {d} of 16.7M)\n", .{affine_total});
        var ex_tt: [8]u8 = undefined;
        for (0..8) |x| ex_tt[x] = @intCast((example_code >> @intCast(3 * x)) & 7);
        try w.print("    example impostor tt: {any} (passes basis, non-affine)\n", .{ex_tt});

        // width-64 constructive impostor vs identity: f(x) = x ^ (K * [x&3==3])
        const K: u64 = 0x94D0_49BB_1331_11EB;
        var basis_ok = true;
        // point 0
        if ((0 ^ (if ((0 & 3) == 3) K else 0)) != 0) basis_ok = false;
        var bi: u6 = 0;
        while (true) {
            const e = @as(u64, 1) << bi;
            const fe = e ^ (if ((e & 3) == 3) K else 0);
            if (fe != e) basis_ok = false;
            if (bi == 63) break;
            bi += 1;
        }
        var diff: usize = 0;
        var s: usize = 0;
        while (s < 1_000_000) : (s += 1) {
            const x = rnd.int(u64);
            const fx = x ^ (if ((x & 3) == 3) K else 0);
            if (fx != x) diff += 1;
        }
        try w.print("  width-64 impostor f(x)=x^(K*[x&3==3]) vs identity:\n", .{});
        try w.print("    passes ALL 65 basis points: {s}; differs on {d}/1e6 random inputs (~25% expected)\n", .{ if (basis_ok) "YES" else "NO", diff });
        try w.print("  => W2b is sound ONLY conditioned on W1's linear-op classification.\n", .{});
        try w.print("     The 'deterministic all-inputs proof' is W1+W2b jointly; W2b alone\n", .{});
        try w.print("     accepts ~8^(2^n - (n+1)) impostors. (The Tier-A doc DOES state the\n", .{});
        try w.print("     W1 precondition — this quantifies how load-bearing it is.)\n", .{});
    }

    // ---------------- T3: recurrence order (Cayley-Hamilton claim) ---------
    {
        try w.print("\n[T3] 'affine recurrence has GF(2) linear recurrence of order <= n' —\n", .{});
        try w.print("     the doc says 'order <= 64 (Cayley-Hamilton)'. Edge case: c != 0.\n", .{});
        // exhaustive n=1..3, all (M, c, x0), min LFSR order of every output bit
        inline for ([_]u4{ 1, 2, 3 }) |n| {
            const nn: usize = n;
            const n_m: usize = @as(usize, 1) << (n * n);
            var maxL_hom: usize = 0; // c == 0
            var maxL_aff: usize = 0; // c != 0
            var wit_m: usize = 0;
            var wit_c: u8 = 0;
            var wit_x0: u8 = 0;
            const slen: usize = 4 * (nn + 1) + 8;
            var seq: [40]u1 = undefined;
            var mi: usize = 0;
            while (mi < n_m) : (mi += 1) {
                var rows: [3]u8 = .{ 0, 0, 0 };
                for (0..nn) |j| rows[j] = @intCast((mi >> @intCast(n * j)) & ((@as(usize, 1) << n) - 1));
                var c: u8 = 0;
                while (c < (@as(u8, 1) << n)) : (c += 1) {
                    var x0: u8 = 0;
                    while (x0 < (@as(u8, 1) << n)) : (x0 += 1) {
                        for (0..nn) |bit| {
                            var x: u8 = x0;
                            for (0..slen) |t| {
                                seq[t] = @intCast((x >> @intCast(bit)) & 1);
                                x = affApply2(n, rows[0..nn], c, x);
                            }
                            const L = try berlekampMassey(alloc, seq[0..slen]);
                            if (c == 0) {
                                if (L > maxL_hom) maxL_hom = L;
                            } else {
                                if (L > maxL_aff) {
                                    maxL_aff = L;
                                    wit_m = mi;
                                    wit_c = c;
                                    wit_x0 = x0;
                                }
                            }
                        }
                        if (x0 == (@as(u8, 1) << n) - 1) break;
                    }
                    if (c == (@as(u8, 1) << n) - 1) break;
                }
            }
            try w.print("  n={d} exhaustive: max LFSR order, c=0 (linear): {d} (<= n: {s});", .{ n, maxL_hom, if (maxL_hom <= n) "OK" else "VIOLATED" });
            try w.print("  c!=0 (affine): {d} ", .{maxL_aff});
            if (maxL_aff > n) {
                try w.print("> n  -> 'order <= n' NEEDS the +1: bound is n+1 (witness M-code={d}, c={d}, x0={d})\n", .{ wit_m, wit_c, wit_x0 });
            } else {
                try w.print("(<= n)\n", .{});
            }
        }
        // sampled n=4..8
        inline for ([_]u4{ 4, 6, 8 }) |n| {
            const nn: usize = n;
            var maxL_hom: usize = 0;
            var maxL_aff: usize = 0;
            const slen: usize = 4 * (nn + 1) + 8;
            var seq: [60]u1 = undefined;
            var t: usize = 0;
            while (t < 30_000) : (t += 1) {
                var rows: [8]u8 = undefined;
                for (0..nn) |j| rows[j] = rnd.int(u8) & @as(u8, @intCast((@as(u16, 1) << n) - 1));
                const c: u8 = if (t % 2 == 0) 0 else (rnd.int(u8) & @as(u8, @intCast((@as(u16, 1) << n) - 1))) | 1;
                const x0: u8 = rnd.int(u8) & @as(u8, @intCast((@as(u16, 1) << n) - 1));
                const bit: u3 = @intCast(rnd.uintLessThan(u8, n));
                var x: u8 = x0;
                for (0..slen) |i| {
                    seq[i] = @intCast((x >> bit) & 1);
                    x = affApply2(n, rows[0..nn], c, x);
                }
                const L = try berlekampMassey(alloc, seq[0..slen]);
                if (c == 0) {
                    if (L > maxL_hom) maxL_hom = L;
                } else {
                    if (L > maxL_aff) maxL_aff = L;
                }
            }
            try w.print("  n={d} sampled (30k): max order c=0: {d} (bound n={d}); c!=0: {d} (bound n+1={d})\n", .{ n, maxL_hom, n, maxL_aff, n + 1 });
        }
        try w.print("  minimal counterexample to 'order <= n': n=1, M=[1], c=1, x0=0 ->\n", .{});
        try w.print("  stream 0,1,0,1,... needs L=2 > n=1. The Tier-A phrase 'order <= 64'\n", .{});
        try w.print("  is off by one for affine-with-offset maps (1 of the 6 champions);\n", .{});
        try w.print("  correct bound n+1=65. BRank verdict unaffected (65 << 256).\n", .{});
    }
}
