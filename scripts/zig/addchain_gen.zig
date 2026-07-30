//! Generate addition-chain TARGETS from /dev/urandom so they postdate the build
//! and cannot be hardcoded in any engine source. Output: CSV, one n per line.
//!
//! Three kinds, clearly separable in the output:
//!   SMALL    : random n in [2, 1024]            (in OEIS A003313 range -> rediscovery control)
//!   LARGE    : random 256-bit n                 (not tabulated -> genuine unknown; engine abstains)
//!   COMPOSITE: product of two ~20-bit primes    (40-bit n; factor structure, binary method suboptimal,
//!              factor-chain feasible because each prime factor is small)
//!
//! Pollard-Rho factorization is used so composites can be LARGE (>=40-bit) while the
//! engine's factor method stays feasible: l(n) <= l(p)+l(q), and l(p) for a 20-bit prime
//! is a short chain (~20 steps). We do NOT precompute or know l(n); the engine supplies it.
//!
//! Run: zig build-exe addchain_gen.zig -O ReleaseFast
//!      ./addchain_gen <count_small> <count_large> <count_composite> <out.csv>

const std = @import("std");

fn readU64(rand: *std.fs.File) !u64 {
    var buf: [8]u8 = undefined;
    _ = try rand.readAll(&buf);
    return @bitCast(buf);
}

// ---- modular arithmetic (safe for u64 with overflow guard) ----
fn mulMod(a: u64, b: u64, m: u64) u64 {
    // a,b < m; use u128 to avoid overflow
    return @intCast((@as(u128, a) * b) % m);
}

fn addMod(a: u64, b: u64, m: u64) u64 {
    const s = @as(u128, a) + b;
    return @intCast(if (s >= m) s - m else s);
}

fn powMod(base: u64, exp: u64, m: u64) u64 {
    var result: u64 = 1 % m;
    var b = base % m;
    var e = exp;
    while (e > 0) : (e >>= 1) {
        if (e & 1 == 1) result = mulMod(result, b, m);
        b = mulMod(b, b, m);
    }
    return result;
}

// Miller-Rabin deterministic for u64 (bases from Jim Sinclair).
fn isPrime(n: u64) bool {
    if (n < 2) return false;
    if (n % 2 == 0) return n == 2;
    if (n % 3 == 0) return n == 3;
    if (n % 5 == 0) return n == 5;
    var d = n - 1;
    var r: u64 = 0;
    while (d % 2 == 0) {
        d /= 2;
        r += 1;
    }
    const bases = [_]u64{ 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37 };
    for (bases) |a| {
        if (a % n == 0) continue;
        var x = powMod(a, d, n);
        if (x == 1 or x == n - 1) continue;
        var cont = false;
        var i: u64 = 0;
        while (i < r - 1) : (i += 1) {
            x = mulMod(x, x, n);
            if (x == n - 1) {
                cont = true;
                break;
            }
        }
        if (cont) continue;
        return false;
    }
    return true;
}

// Pollard-Rho factorization. Returns a non-trivial factor of n (n composite).
fn pollardRho(n: u64) u64 {
    var rng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    const rnd = rng.random();
    var x = rnd.int(u64) % (n - 2) + 2;
    var y = x;
    const c = rnd.int(u64) % (n - 1) + 1;
    var d: u64 = 1;
    while (d == 1) {
        x = addMod(mulMod(x, x, n), c % n, n);
        y = addMod(mulMod(y, y, n), c % n, n);
        y = addMod(mulMod(y, y, n), c % n, n);
        const diff = if (x > y) x - y else y - x;
        // gcd via Euclid
        var a = diff;
        var b = n;
        while (b != 0) {
            const t = b;
            b = a % b;
            a = t;
        }
        d = a;
    }
    if (d == n) {
        // rare failure; retry with different c
        return pollardRhoRetry(n, c + 1);
    }
    return d;
}

fn pollardRhoRetry(n: u64, c: u64) u64 {
    var x: u64 = 2;
    var y: u64 = 2;
    var d: u64 = 1;
    const cc = c % (n - 1) + 1;
    while (d == 1) {
        x = addMod(mulMod(x, x, n), cc % n, n);
        y = addMod(mulMod(y, y, n), cc % n, n);
        y = addMod(mulMod(y, y, n), cc % n, n);
        const diff = if (x > y) x - y else y - x;
        var a = diff;
        var b = n;
        while (b != 0) {
            const t = b;
            b = a % b;
            a = t;
        }
        d = a;
    }
    if (d == n) return 1; // give up
    return d;
}

// Full factorization to a list of prime factors (with multiplicity).
fn factorize(n: u64, out: *std.ArrayList(u64)) !void {
    if (n <= 1) return;
    if (isPrime(n)) {
        try out.append(n);
        return;
    }
    const f = pollardRho(n);
    if (f == 1 or f == n) {
        // fallback: trial division
        var m = n;
        var d: u64 = 2;
        while (d * d <= m) : (d += 1) {
            while (m % d == 0) {
                try out.append(d);
                m /= d;
            }
        }
        if (m > 1) try out.append(m);
        return;
    }
    try factorize(f, out);
    try factorize(n / f, out);
}

fn randomPrimeBits(rand: *std.fs.File, bits: usize) !u64 {
    var attempt: u32 = 0;
    while (attempt < 2_000_000) : (attempt += 1) {
        var buf: [8]u8 = undefined;
        _ = try rand.readAll(&buf);
        var v: u64 = 0;
        for (buf) |b| v = (v << 8) | b;
        const mask: u64 = if (bits >= 64) std.math.maxInt(u64) else (@as(u64, 1) << @intCast(bits)) - 1;
        v &= mask;
        v |= 1;
        v |= (@as(u64, 1) << @intCast(bits - 1));
        if (v < 3) continue;
        if (isPrime(v)) return v;
    }
    return 0;
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    const n_small: usize = if (args.len > 1) try std.fmt.parseUnsigned(usize, args[1], 10) else 20;
    const n_large: usize = if (args.len > 2) try std.fmt.parseUnsigned(usize, args[2], 10) else 5;
    const n_comp: usize = if (args.len > 3) try std.fmt.parseUnsigned(usize, args[3], 10) else 5;
    const out_path = if (args.len > 4) args[4] else "results/addchain_targets.csv";

    var rand = try std.fs.cwd().openFile("/dev/urandom", .{});
    defer rand.close();
    const out = try std.fs.cwd().createFile(out_path, .{});
    defer out.close();
    const w = out.writer();

    var i: usize = 0;
    while (i < n_small) : (i += 1) {
        const v = (try readU64(&rand)) % 1023 + 2;
        try w.print("{d},SMALL\n", .{v});
    }
    i = 0;
    while (i < n_large) : (i += 1) {
        var buf: [32]u8 = undefined;
        _ = try rand.readAll(&buf);
        var v: u256 = 0;
        for (buf) |b| v = (v << 8) | b;
        if (v < 2) v = 2;
        try w.print("{d},LARGE\n", .{v});
    }
    i = 0;
    while (i < n_comp) : (i += 1) {
        // product of two ~20-bit primes -> 40-bit composite, factor-chain feasible
        const p = try randomPrimeBits(&rand, 20);
        const q = try randomPrimeBits(&rand, 20);
        if (p == 0 or q == 0) {
            var buf: [16]u8 = undefined;
            _ = try rand.readAll(&buf);
            var v: u128 = 0;
            for (buf) |b| v = (v << 8) | b;
            if (v < 2) v = 2;
            try w.print("{d},COMPOSITE\n", .{v});
        } else {
            try w.print("{d},COMPOSITE\n", .{p * q});
        }
    }

    std.debug.print("wrote {} small, {} large, {} composite targets to {s}\n", .{ n_small, n_large, n_comp, out_path });
    _ = factorize; // keep available for future fact-reports
}
