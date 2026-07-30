//! addchain_v2.zig — addition-chain external-verification campaign v2 (2026-07-10).
//!
//! Extends the 2026-07-07 campaign (dial_three.zig --targets/--factor) with a battery of
//! stronger chain-construction methods, all emitting chains in the exact JSON schema that
//! the INDEPENDENT verifier scripts/zig/addchain_check.zig consumes. The engine NEVER
//! asserts minimality — addchain_check.zig is the sole authority (it re-proves validity
//! for every chain and minimality where its depth-16 IDDFS is feasible).
//!
//! Methods (each produces a decomposition-closed value SET; sorted ascending, that set IS
//! a valid addition chain — every element is a sum of two strictly-smaller set members):
//!   binary  : constructive MSB-first double-and-add. Length = ilog2(n)+popcount(n)-1.
//!             The fixed classical baseline.
//!   factor  : recursive factor method. l(ab) <= l(a)+l(b); primes p -> chain(p-1)+1;
//!             base case n <= 1024 solved EXACTLY by iterative-deepening DFS (memoized).
//!   window  : sliding-window (m-ary) method, k = 1..6, best k kept. Odd-digit windows,
//!             zero-run skipping, odd ladder 1,2,3,5,...,maxdigit as the dictionary.
//!   search  : bounded stochastic improver (the only non-classical method):
//!             (a) randomized backward decomposition (Bos-Coster flavored: pop largest
//!                 needed value, split by halving / subtract-largest / subtract-closest-
//!                 to-half / subtract-random over the committed+pending set),
//!             (b) randomized-width sliding windows,
//!             (c) deletion-repair local search over chain structure (remove any element
//!                 whose loss keeps every other element decomposable), applied to the
//!                 stochastic candidates AND to the classical chains.
//!   exact   : optional (--exact-max M): full IDDFS minimum for n <= M with a node budget.
//!             If the budget is exhausted the engine ABSTAINS for that target (emits
//!             found=false) rather than risk emitting a non-minimal chain in the range
//!             where addchain_check proves minimality.
//!
//! Reported lower bounds per target:
//!   lb_task = ceil(log2 n) + ceil(log2 popcount(n))   — the bound requested for this
//!             campaign. NOTE: this formula is NOT a sound lower bound (n=15: l(15)=5 but
//!             lb_task=6). Negative gaps are reported honestly, not clamped.
//!   lb_sch  = max(ceil(log2 n), ceil(log2 n + log2 popcount(n) - 2.13)) — Schönhage's
//!             theorem l(n) >= log2 n + log2 nu(n) - 2.13, a sound bound.
//!
//! Usage:
//!   addchain_v2 --targets t.csv [--csv out.csv] [--json out.json] [--restarts N]
//!               [--seed 0xHEX] [--exact-max M] [--exact-budget B]
//!
//! Build: zig build-exe addchain_v2.zig -O ReleaseFast
//! Single-threaded. CPU-only. Bounded runs.

const std = @import("std");

const MAXV: usize = 512;

fn ilog2(n: u64) usize {
    var k: usize = 0;
    var v = n;
    while (v > 1) : (v >>= 1) k += 1;
    return k;
}
fn clog2(n: u64) usize {
    if (n <= 1) return 0;
    return ilog2(n - 1) + 1;
}
fn binaryLenF(n: u64) usize {
    return ilog2(n) + @as(usize, @popCount(n)) - 1;
}

// ---------------------------------------------------------------- value sets
// A chain candidate is a SET of u64 values that is decomposition-closed: every
// element v != 1 has members a,b (a+b=v, necessarily a,b < v). Sorted ascending
// this is a valid addition chain of length (count-1). validate() is the local
// gate; the external addchain_check.zig re-proves everything independently.
const ValSet = struct {
    v: [MAXV]u64 = undefined,
    n: usize = 0,

    fn reset(self: *ValSet) void {
        self.n = 0;
    }
    fn has(self: *const ValSet, x: u64) bool {
        for (self.v[0..self.n]) |e| if (e == x) return true;
        return false;
    }
    fn add(self: *ValSet, x: u64) bool {
        if (self.has(x)) return true;
        if (self.n >= MAXV) return false;
        self.v[self.n] = x;
        self.n += 1;
        return true;
    }
    fn sortAsc(self: *ValSet) void {
        std.mem.sort(u64, self.v[0..self.n], {}, comptime std.sort.asc(u64));
    }
    fn chainLen(self: *const ValSet) usize {
        return self.n - 1;
    }
};

fn validate(vs: *ValSet, n: u64) bool {
    if (vs.n < 2) return false;
    vs.sortAsc();
    if (vs.v[0] != 1) return false;
    if (vs.v[vs.n - 1] != n) return false;
    var i: usize = 1;
    while (i < vs.n) : (i += 1) {
        if (vs.v[i] == vs.v[i - 1]) return false;
        const w = vs.v[i];
        var ok = false;
        var a: usize = 0;
        outer: while (a < i) : (a += 1) {
            var b: usize = a;
            while (b < i) : (b += 1) {
                if (vs.v[a] + vs.v[b] == w) {
                    ok = true;
                    break :outer;
                }
            }
        }
        if (!ok) return false;
    }
    return true;
}

// ---------------------------------------------------------------- binary method
fn binarySet(n: u64, out: *ValSet) bool {
    out.reset();
    if (!out.add(1)) return false;
    if (n < 2) return n == 1;
    const top = ilog2(n);
    var acc: u64 = 1;
    var bit: usize = top;
    while (bit > 0) {
        bit -= 1;
        acc += acc;
        if (!out.add(acc)) return false;
        if ((n >> @intCast(bit)) & 1 == 1) {
            acc += 1;
            if (!out.add(acc)) return false;
        }
    }
    return acc == n;
}

// ---------------------------------------------------------------- exact IDDFS
// Complete iterative-deepening DFS over ascending chains (Knuth TAOCP 4.6.3 WLOG)
// with the admissible doubling prune — same shape as dial_three.zig / the external
// checker. Node-budgeted: if the budget trips at ANY depth the whole search FAILS
// (returning a deeper find after an aborted shallower depth could be non-minimal).
const EXACT_MAXLEN: usize = 40;
var ex_chain: [EXACT_MAXLEN + 1]u64 = undefined;
var ex_nodes: u64 = 0;
var ex_budget: u64 = 0;
var ex_aborted: bool = false;

fn exDfs(i: usize, len: usize, target: u64) bool {
    ex_nodes += 1;
    if (ex_nodes > ex_budget) {
        ex_aborted = true;
        return false;
    }
    if (i == len) return ex_chain[i] == target;
    const left = len - i - 1;
    var a: usize = i;
    while (true) : (a -= 1) {
        var b: usize = a;
        while (true) : (b -= 1) {
            const c = ex_chain[a] + ex_chain[b];
            if (c > ex_chain[i] and c <= target) {
                if ((@as(u128, c) << @intCast(left)) >= target) {
                    ex_chain[i + 1] = c;
                    if (exDfs(i + 1, len, target)) return true;
                    if (ex_aborted) return false;
                }
            }
            if (b == 0) break;
        }
        if (a == 0) break;
    }
    return false;
}

fn shortestExact(n: u64, budget: u64, out: *ValSet) bool {
    if (n == 1) {
        out.reset();
        return out.add(1);
    }
    ex_chain[0] = 1;
    ex_nodes = 0;
    ex_budget = budget;
    ex_aborted = false;
    var len: usize = clog2(n);
    if (len == 0) len = 1;
    while (len <= EXACT_MAXLEN) : (len += 1) {
        if (exDfs(0, len, n)) {
            out.reset();
            for (0..len + 1) |k| _ = out.add(ex_chain[k]);
            return true;
        }
        if (ex_aborted) return false;
    }
    return false;
}

// memo for small exact chains (factor-method base cases hit these repeatedly)
const SmallChain = struct { v: [48]u64, n: usize };
var memo: std.AutoHashMap(u64, SmallChain) = undefined;

fn exactChain(n: u64, budget: u64, out: *ValSet) bool {
    if (memo.get(n)) |sc| {
        out.reset();
        for (sc.v[0..sc.n]) |x| _ = out.add(x);
        return true;
    }
    if (!shortestExact(n, budget, out)) return false;
    if (out.n <= 48) {
        var sc: SmallChain = undefined;
        for (out.v[0..out.n], 0..) |x, i| sc.v[i] = x;
        sc.n = out.n;
        memo.put(n, sc) catch {};
    }
    return true;
}

// ---------------------------------------------------------------- factor method
const FACTOR_EXACT_MAX: u64 = 1024;
const FACTOR_EXACT_BUDGET: u64 = 500_000_000;

fn smallestFactor(n: u64) u64 {
    if (n % 2 == 0) return 2;
    var d: u64 = 3;
    while (d * d <= n) : (d += 2) {
        if (n % d == 0) return d;
    }
    return n;
}

// Recursive factor method producing a decomposition-closed set:
//   n <= 1024          -> exact minimal chain (memoized IDDFS)
//   n prime            -> set(n-1) U {n}          (n = (n-1) + 1)
//   n = p*m composite  -> set(p) U { p*x : x in set(m) }
// Scaled witnesses: x = a+b in set(m) => p*x = p*a + p*b, both present; p*1 = p
// comes from set(p). Union of closed sets is closed.
fn factorRec(n: u64, out: *ValSet, depth: usize) bool {
    if (depth > 128) return false;
    if (n == 0) return false;
    if (n == 1) return out.add(1);
    if (n <= FACTOR_EXACT_MAX) {
        var tmp = ValSet{};
        if (!exactChain(n, FACTOR_EXACT_BUDGET, &tmp)) return false;
        for (tmp.v[0..tmp.n]) |x| if (!out.add(x)) return false;
        return true;
    }
    const p = smallestFactor(n);
    if (p == n) {
        if (!factorRec(n - 1, out, depth + 1)) return false;
        return out.add(n);
    }
    const m = n / p;
    if (!factorRec(p, out, depth + 1)) return false;
    var vm = ValSet{};
    if (!factorRec(m, &vm, depth + 1)) return false;
    for (vm.v[0..vm.n]) |x| if (!out.add(p * x)) return false;
    return true;
}

// ---------------------------------------------------------------- window method
// Sliding-window / m-ary: decompose n into odd digits d_i * 2^{e_i} (windows of
// width <= k, always ending on a set bit so digits are odd), dictionary = odd
// ladder 1,2,3,5,...,maxdigit, then MSB-first shift-and-add over the digits.
// rnd != null randomizes the per-window width in [1, k] (stochastic variant).
fn windowCore(n: u64, kmax: usize, rnd: ?std.Random, out: *ValSet) bool {
    out.reset();
    if (n < 2) return false;
    if (!out.add(1)) return false;
    var digs: [64]u64 = undefined;
    var exps: [64]usize = undefined;
    var nw: usize = 0;
    var i: i64 = @intCast(ilog2(n));
    while (i >= 0) {
        if ((n >> @intCast(i)) & 1 == 0) {
            i -= 1;
            continue;
        }
        const k: usize = if (rnd) |r| r.intRangeAtMost(usize, 1, kmax) else kmax;
        var j: i64 = i - @as(i64, @intCast(k)) + 1;
        if (j < 0) j = 0;
        while ((n >> @intCast(j)) & 1 == 0) j += 1;
        const width: usize = @intCast(i - j + 1);
        const d: u64 = (n >> @intCast(j)) & ((@as(u64, 1) << @intCast(width)) - 1);
        if (nw >= 64) return false;
        digs[nw] = d;
        exps[nw] = @intCast(j);
        nw += 1;
        i = j - 1;
    }
    if (nw == 0) return false;
    var maxd: u64 = 0;
    for (digs[0..nw]) |d| {
        if (d > maxd) maxd = d;
    }
    if (maxd >= 3) {
        if (!out.add(2)) return false;
        var vv: u64 = 3;
        while (vv <= maxd) : (vv += 2) if (!out.add(vv)) return false;
    }
    var acc: u64 = digs[0];
    if (!out.add(acc)) return false;
    var w: usize = 1;
    while (w <= nw) : (w += 1) {
        const next_exp: usize = if (w < nw) exps[w] else 0;
        var t: usize = exps[w - 1] - next_exp;
        while (t > 0) : (t -= 1) {
            acc += acc;
            if (!out.add(acc)) return false;
        }
        if (w < nw) {
            acc += digs[w];
            if (!out.add(acc)) return false;
        }
    }
    return acc == n;
}

// ------------------------------------------------- stochastic backward search
// Randomized backward decomposition (Bos-Coster flavored): keep a pending pool,
// pop the LARGEST needed value v, commit it, and split it into a+b chosen at
// random among: halving (v even), subtract the largest known value < v, subtract
// the value closest to v/2, subtract a random known value. Every committed value
// gets exactly one recorded split, so the committed set is decomposition-closed
// and |set|-1 is the chain length. Random restarts explore the space.
fn stochBackward(n: u64, rnd: std.Random, out: *ValSet) bool {
    out.reset();
    if (!out.add(1)) return false;
    var pend: [MAXV]u64 = undefined;
    var np: usize = 0;
    pend[0] = n;
    np = 1;
    var guard: usize = 0;
    while (np > 0) {
        guard += 1;
        if (guard > 2048) return false;
        var mi: usize = 0;
        for (pend[0..np], 0..) |x, ii| {
            if (x > pend[mi]) mi = ii;
        }
        const v = pend[mi];
        pend[mi] = pend[np - 1];
        np -= 1;
        if (out.has(v)) continue;
        if (!out.add(v)) return false;
        if (out.n > 96) return false; // hopeless attempt, abandon early
        if (v == 1) continue;
        var a: u64 = undefined;
        var b: u64 = undefined;
        if (v == 2) {
            a = 1;
            b = 1;
        } else {
            const roll = rnd.intRangeLessThan(u32, 0, 100);
            if (v % 2 == 0 and roll < 55) {
                a = v / 2;
                b = v / 2;
            } else {
                var g: u64 = 1;
                const strat = rnd.intRangeLessThan(u32, 0, 100);
                if (strat < 45) {
                    // subtract-largest (maximal reuse of known values)
                    for (out.v[0..out.n]) |x| {
                        if (x < v and x > g) g = x;
                    }
                    for (pend[0..np]) |x| {
                        if (x < v and x > g) g = x;
                    }
                } else if (strat < 75) {
                    // subtract the known value closest to v/2 (near-halving)
                    const half = v / 2;
                    var bestd: u64 = std.math.maxInt(u64);
                    for (out.v[0..out.n]) |x| {
                        if (x >= v) continue;
                        const d = if (x > half) x - half else half - x;
                        if (d < bestd) {
                            bestd = d;
                            g = x;
                        }
                    }
                    for (pend[0..np]) |x| {
                        if (x >= v) continue;
                        const d = if (x > half) x - half else half - x;
                        if (d < bestd) {
                            bestd = d;
                            g = x;
                        }
                    }
                } else {
                    // subtract a random known value
                    var cand: [2 * MAXV]u64 = undefined;
                    var nc: usize = 0;
                    for (out.v[0..out.n]) |x| {
                        if (x < v) {
                            cand[nc] = x;
                            nc += 1;
                        }
                    }
                    for (pend[0..np]) |x| {
                        if (x < v) {
                            cand[nc] = x;
                            nc += 1;
                        }
                    }
                    if (nc > 0) g = cand[rnd.intRangeLessThan(usize, 0, nc)];
                }
                a = v - g;
                b = g;
            }
        }
        if (a < b) {
            const t = a;
            a = b;
            b = t;
        }
        const two = [2]u64{ a, b };
        for (two) |x| {
            if (x == 0) return false;
            if (out.has(x)) continue;
            var inp = false;
            for (pend[0..np]) |y| {
                if (y == x) {
                    inp = true;
                    break;
                }
            }
            if (!inp) {
                if (np >= MAXV) return false;
                pend[np] = x;
                np += 1;
            }
        }
    }
    return out.has(n);
}

// ----------------------------------------------- deletion-repair local search
// Local search over chain STRUCTURE: an interior element may be deleted iff every
// other element remains decomposable within the reduced set. Repeats (random
// scan order) until a fixed point. Never increases length; validity preserved by
// construction and re-proven by validate() + the external checker.
fn removableIdx(vs: *const ValSet, idx: usize) bool {
    var i: usize = 1;
    while (i < vs.n) : (i += 1) {
        if (i == idx) continue;
        const w = vs.v[i];
        var ok = false;
        var a: usize = 0;
        outer: while (a < i) : (a += 1) {
            if (a == idx) continue;
            var b: usize = a;
            while (b < i) : (b += 1) {
                if (b == idx) continue;
                if (vs.v[a] + vs.v[b] == w) {
                    ok = true;
                    break :outer;
                }
            }
        }
        if (!ok) return false;
    }
    return true;
}

fn deletionRepair(vs: *ValSet, rnd: std.Random) void {
    vs.sortAsc();
    var improved = true;
    while (improved and vs.n > 2) {
        improved = false;
        var order: [MAXV]usize = undefined;
        const m = vs.n - 2; // interior indices 1..n-2 (never 1, never n)
        for (0..m) |t| order[t] = t + 1;
        rnd.shuffle(usize, order[0..m]);
        for (order[0..m]) |idx| {
            if (removableIdx(vs, idx)) {
                var t: usize = idx;
                while (t + 1 < vs.n) : (t += 1) vs.v[t] = vs.v[t + 1];
                vs.n -= 1;
                improved = true;
                break;
            }
        }
    }
}

// ---------------------------------------------------------------------- main
pub fn main() !void {
    const gpa = std.heap.page_allocator;
    memo = std.AutoHashMap(u64, SmallChain).init(gpa);
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    var targets_path: ?[]const u8 = null;
    var csv_path: ?[]const u8 = null;
    var json_path: ?[]const u8 = null;
    var restarts: usize = 3000;
    var seed: u64 = 0;
    var seed_given = false;
    var exact_max: u64 = 0;
    var exact_budget: u64 = 2_000_000_000;
    {
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--targets")) {
                i += 1;
                if (i < args.len) targets_path = args[i];
            } else if (std.mem.eql(u8, args[i], "--csv")) {
                i += 1;
                if (i < args.len) csv_path = args[i];
            } else if (std.mem.eql(u8, args[i], "--json")) {
                i += 1;
                if (i < args.len) json_path = args[i];
            } else if (std.mem.eql(u8, args[i], "--restarts")) {
                i += 1;
                if (i < args.len) restarts = try std.fmt.parseUnsigned(usize, args[i], 10);
            } else if (std.mem.eql(u8, args[i], "--seed")) {
                i += 1;
                if (i < args.len) {
                    seed = try std.fmt.parseUnsigned(u64, std.mem.trimLeft(u8, args[i], "0x"), 16);
                    seed_given = true;
                }
            } else if (std.mem.eql(u8, args[i], "--exact-max")) {
                i += 1;
                if (i < args.len) exact_max = try std.fmt.parseUnsigned(u64, args[i], 10);
            } else if (std.mem.eql(u8, args[i], "--exact-budget")) {
                i += 1;
                if (i < args.len) exact_budget = try std.fmt.parseUnsigned(u64, args[i], 10);
            }
        }
    }
    const tp = targets_path orelse {
        std.debug.print("usage: addchain_v2 --targets t.csv [--csv out.csv] [--json out.json] [--restarts N] [--seed 0xHEX] [--exact-max M] [--exact-budget B]\n", .{});
        std.process.exit(2);
    };
    if (!seed_given) {
        var rf = try std.fs.cwd().openFile("/dev/urandom", .{});
        defer rf.close();
        var sb: [8]u8 = undefined;
        _ = try rf.readAll(&sb);
        seed = @bitCast(sb);
    }
    std.debug.print("addchain_v2: restarts={d} seed=0x{X} exact_max={d} exact_budget={d}\n", .{ restarts, seed, exact_max, exact_budget });
    var prng = std.Random.DefaultPrng.init(seed);
    const rnd = prng.random();

    const file = try std.fs.cwd().openFile(tp, .{});
    defer file.close();
    const content = try file.readToEndAllocOptions(gpa, 1 << 30, null, 1, 0);
    defer gpa.free(content);

    var csv_buf = std.ArrayList(u8).init(gpa);
    defer csv_buf.deinit();
    const cw = csv_buf.writer();
    try cw.print("n,label,bits,nu,lb_task,lb_sch,len_binary,len_factor,len_window,win_k,len_exact,len_search,len_best,best_method,gap_task,gap_sch,beats_binary,beats_window,search_beats_classical\n", .{});

    var json_buf = std.ArrayList(u8).init(gpa);
    defer json_buf.deinit();
    const jw = json_buf.writer();
    try jw.print("{{\"results\":[", .{});
    var first_json = true;

    // aggregates
    var cnt: usize = 0;
    var sum_bin: f64 = 0;
    var sum_fac: f64 = 0;
    var cnt_fac: usize = 0;
    var sum_win: f64 = 0;
    var sum_search: f64 = 0;
    var sum_best: f64 = 0;
    var wins_best_bin: usize = 0;
    var wins_best_win: usize = 0;
    var wins_search_classical: usize = 0;
    var gap_task_sum: i64 = 0;
    var gap_task_min: i64 = std.math.maxInt(i64);
    var gap_task_max: i64 = std.math.minInt(i64);
    var gap_sch_sum: i64 = 0;
    var gap_sch_min: i64 = std.math.maxInt(i64);
    var gap_sch_max: i64 = std.math.minInt(i64);
    var exact_attempted: usize = 0;
    var exact_ok: usize = 0;
    var abstained: usize = 0;

    const t0 = std.time.milliTimestamp();

    var it = std.mem.tokenizeScalar(u8, content, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r\t");
        if (trimmed.len == 0) continue;
        var fields = std.mem.tokenizeScalar(u8, trimmed, ',');
        const n_str = std.mem.trim(u8, fields.next() orelse "", " \r\t");
        const label = std.mem.trim(u8, fields.next() orelse "?", " \r\t");
        const n = std.fmt.parseUnsigned(u64, n_str, 10) catch {
            if (!first_json) try jw.print(",", .{});
            first_json = false;
            try jw.print("{{\"n\":0,\"found\":false,\"length\":999,\"binary_len\":0,\"note\":\"unparseable\"}}", .{});
            abstained += 1;
            continue;
        };
        if (n < 2) continue;

        const nu: usize = @popCount(n);
        const bits = ilog2(n) + 1;
        const lb_task: i64 = @intCast(clog2(n) + clog2(@as(u64, nu)));
        const lb_sch: i64 = blk: {
            const f = @log2(@as(f64, @floatFromInt(n))) + @log2(@as(f64, @floatFromInt(nu))) - 2.13;
            const c: i64 = @intFromFloat(@ceil(f));
            const trivial: i64 = @intCast(clog2(n));
            break :blk if (c > trivial) c else trivial;
        };

        // --- binary (classical baseline) ---
        var vbin = ValSet{};
        const ok_bin = binarySet(n, &vbin) and validate(&vbin, n);
        if (!ok_bin) {
            std.debug.print("FATAL: binary method failed for n={d}\n", .{n});
            std.process.exit(1);
        }
        const len_bin = vbin.chainLen();
        if (len_bin != binaryLenF(n)) {
            std.debug.print("WARN: constructive binary len {d} != formula {d} for n={d} (dedup shortened it)\n", .{ len_bin, binaryLenF(n), n });
        }

        // --- factor (classical) ---
        var vfac = ValSet{};
        var len_fac: usize = 0;
        {
            var tmp = ValSet{};
            if (factorRec(n, &tmp, 0) and validate(&tmp, n)) {
                vfac = tmp;
                len_fac = tmp.chainLen();
                cnt_fac += 1;
            }
        }

        // --- window k=1..6 (classical) ---
        var vwin = ValSet{};
        var len_win: usize = 0;
        var win_k: usize = 0;
        {
            var k: usize = 1;
            while (k <= 6) : (k += 1) {
                var vw = ValSet{};
                if (windowCore(n, k, null, &vw) and validate(&vw, n)) {
                    if (len_win == 0 or vw.chainLen() < len_win) {
                        len_win = vw.chainLen();
                        win_k = k;
                        vwin = vw;
                    }
                }
            }
        }

        var classical: usize = len_bin;
        if (len_fac > 0 and len_fac < classical) classical = len_fac;
        if (len_win > 0 and len_win < classical) classical = len_win;

        // --- exact (optional, small n only) ---
        var vex = ValSet{};
        var len_ex: usize = 0;
        var exact_wanted = false;
        if (exact_max > 0 and n <= exact_max) {
            exact_wanted = true;
            exact_attempted += 1;
            var tmp = ValSet{};
            if (exactChain(n, exact_budget, &tmp) and validate(&tmp, n)) {
                vex = tmp;
                len_ex = tmp.chainLen();
                exact_ok += 1;
            }
        }

        // --- bounded stochastic search ---
        var vsearch = ValSet{};
        var len_search: usize = 0;
        {
            var attempt = ValSet{};
            var r: usize = 0;
            while (r < restarts) : (r += 1) {
                var ok = false;
                if (r % 2 == 0) {
                    ok = stochBackward(n, rnd, &attempt);
                } else {
                    ok = windowCore(n, 6, rnd, &attempt);
                }
                if (!ok) continue;
                const cur: usize = if (len_search == 0) 100000 else len_search;
                if (r % 2 == 1 and attempt.n - 1 <= cur + 8) deletionRepair(&attempt, rnd);
                if (attempt.n - 1 < cur) {
                    if (validate(&attempt, n)) {
                        vsearch = attempt;
                        len_search = attempt.n - 1;
                    }
                }
            }
            // deletion-repair over the stochastic candidate AND the classical chains
            const cands = [_]*const ValSet{ &vbin, &vfac, &vwin, &vsearch };
            for (cands) |c| {
                if (c.n < 2) continue;
                var cp: ValSet = c.*;
                deletionRepair(&cp, rnd);
                if (validate(&cp, n)) {
                    if (len_search == 0 or cp.chainLen() < len_search) {
                        vsearch = cp;
                        len_search = cp.chainLen();
                    }
                }
            }
        }

        // --- best of all ---
        var len_best = len_bin;
        var vbest: *ValSet = &vbin;
        var best_method: []const u8 = "binary";
        if (len_fac > 0 and len_fac < len_best) {
            len_best = len_fac;
            vbest = &vfac;
            best_method = "factor";
        }
        if (len_win > 0 and len_win < len_best) {
            len_best = len_win;
            vbest = &vwin;
            best_method = "window";
        }
        if (len_search > 0 and len_search < len_best) {
            len_best = len_search;
            vbest = &vsearch;
            best_method = "search";
        }
        if (len_ex > 0 and len_ex < len_best) {
            len_best = len_ex;
            vbest = &vex;
            best_method = "exact";
        }
        // self-check: exact (when it succeeded) must never lose to a heuristic
        if (len_ex > 0 and len_best < len_ex) {
            std.debug.print("BUG: heuristic ({s}, len {d}) beat 'exact' (len {d}) for n={d} — exact search is unsound\n", .{ best_method, len_best, len_ex, n });
            std.process.exit(1);
        }

        // --- JSON emission for the independent checker ---
        // In the exact range we emit ONLY exact chains (checker proves minimality
        // there; emitting a heuristic chain that happens to be non-minimal would
        // be flagged REFUTED — and rightly so). If exact failed: abstain.
        var emit: ?*ValSet = vbest;
        if (exact_wanted and len_ex == 0) emit = null;
        if (!first_json) try jw.print(",", .{});
        first_json = false;
        if (emit) |ev| {
            try jw.print("{{\"n\":{d},\"found\":true,\"length\":{d},\"binary_len\":{d},\"chain\":[", .{ n, ev.chainLen(), binaryLenF(n) });
            for (0..ev.n) |k| {
                if (k > 0) try jw.print(",", .{});
                try jw.print("{d}", .{ev.v[k]});
            }
            try jw.print("]}}", .{});
        } else {
            abstained += 1;
            try jw.print("{{\"n\":{d},\"found\":false,\"length\":999,\"binary_len\":{d}}}", .{ n, binaryLenF(n) });
        }

        // --- CSV row ---
        const gap_task: i64 = @as(i64, @intCast(len_best)) - lb_task;
        const gap_sch: i64 = @as(i64, @intCast(len_best)) - lb_sch;
        const beats_bin: u8 = if (len_best < len_bin) 1 else 0;
        const beats_win: u8 = if (len_win > 0 and len_best < len_win) 1 else 0;
        const s_beats_c: u8 = if (len_search > 0 and len_search < classical) 1 else 0;
        try cw.print("{d},{s},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{s},{d},{d},{d},{d},{d}\n", .{
            n,        label,   bits,    nu,      lb_task, lb_sch, len_bin,
            len_fac,  len_win, win_k,   len_ex,  len_search, len_best, best_method,
            gap_task, gap_sch, beats_bin, beats_win, s_beats_c,
        });

        // --- aggregates ---
        cnt += 1;
        sum_bin += @floatFromInt(len_bin);
        if (len_fac > 0) sum_fac += @floatFromInt(len_fac);
        sum_win += @floatFromInt(len_win);
        sum_search += @floatFromInt(len_search);
        sum_best += @floatFromInt(len_best);
        if (len_best < len_bin) wins_best_bin += 1;
        if (len_win > 0 and len_best < len_win) wins_best_win += 1;
        if (len_search > 0 and len_search < classical) wins_search_classical += 1;
        gap_task_sum += gap_task;
        if (gap_task < gap_task_min) gap_task_min = gap_task;
        if (gap_task > gap_task_max) gap_task_max = gap_task;
        gap_sch_sum += gap_sch;
        if (gap_sch < gap_sch_min) gap_sch_min = gap_sch;
        if (gap_sch > gap_sch_max) gap_sch_max = gap_sch;

        std.debug.print("n={d} ({s},{d}b): bin={d} fac={d} win={d}(k{d}) search={d} exact={d} best={d}[{s}] lb_task={d} lb_sch={d}\n", .{ n, label, bits, len_bin, len_fac, len_win, win_k, len_search, len_ex, len_best, best_method, lb_task, lb_sch });
    }
    try jw.print("],\"maxlen\":{d}}}", .{MAXV - 1});

    if (csv_path) |cp| {
        var f = try std.fs.cwd().createFile(cp, .{});
        defer f.close();
        try f.writeAll(csv_buf.items);
    }
    if (json_path) |jp| {
        var f = try std.fs.cwd().createFile(jp, .{});
        defer f.close();
        try f.writeAll(json_buf.items);
    }

    const dt = std.time.milliTimestamp() - t0;
    const o = std.io.getStdOut().writer();
    const fcnt: f64 = @floatFromInt(if (cnt == 0) 1 else cnt);
    const ffac: f64 = @floatFromInt(if (cnt_fac == 0) 1 else cnt_fac);
    try o.print("=== addchain_v2 summary: targets={d} time={d}ms restarts={d} seed=0x{X} ===\n", .{ cnt, dt, restarts, seed });
    try o.print("mean lengths: binary={d:.2} factor={d:.2}(n={d}) window={d:.2} search={d:.2} best={d:.2}\n", .{ sum_bin / fcnt, sum_fac / ffac, cnt_fac, sum_win / fcnt, sum_search / fcnt, sum_best / fcnt });
    try o.print("best < binary: {d}/{d}   best < window: {d}/{d}   search < min(classical) [invention yield]: {d}/{d}\n", .{ wins_best_bin, cnt, wins_best_win, cnt, wins_search_classical, cnt });
    try o.print("gap vs lb_task (clog2 n + clog2 nu): mean={d:.2} min={d} max={d}  [NEGATIVE => that formula is NOT a sound lower bound]\n", .{ @as(f64, @floatFromInt(gap_task_sum)) / fcnt, gap_task_min, gap_task_max });
    try o.print("gap vs lb_sch (Schoenhage, sound):   mean={d:.2} min={d} max={d}\n", .{ @as(f64, @floatFromInt(gap_sch_sum)) / fcnt, gap_sch_min, gap_sch_max });
    try o.print("exact: attempted={d} succeeded={d}   json abstained={d}\n", .{ exact_attempted, exact_ok, abstained });
    try o.print("NOTE: engine asserts nothing — run scripts/zig/addchain_check on the JSON for the independent verdict.\n", .{});
}
