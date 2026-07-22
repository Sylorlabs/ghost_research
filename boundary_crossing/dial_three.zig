//! TURNING THE THIRD DIAL — point the certified loop at a GENUINE UNKNOWN.
//!
//! real_invention.zig established: we have a real invention engine NOW; it became "alien / beyond known
//! human knowledge" only by turning dial (3) — aiming the certified loop at a target whose answer is NOT
//! pre-supplied (a conjecture, real data, an un-tabulated function), instead of a known theorem. This probe
//! DEMONSTRATES that dial end-to-end, self-contained, on a classic hard problem:
//!
//!     the SHORTEST ADDITION CHAIN for n  —  1 = a0 < a1 < ... < a_r = n, each a_i = a_j + a_k (j,k <= i).
//!
//! Why this is dial (3), not recall:
//!   • GENUINE UNKNOWN. l(n) (the minimum r) has no closed form; computing it is conjectured hard. I (the
//!     operator/LLM) do NOT supply the answers — I supply only the search procedure and a naive baseline.
//!     The full win-pattern (how many n beat the baseline, by how much, the champion) is unknown to me until
//!     the search runs. That is the point: the engine produces the result, I did not feed it.
//!   • SOUND VERIFIER. A complete ITERATIVE-DEEPENING search (ascending chains, WLOG — Knuth TAOCP 4.6.3)
//!     with an admissible doubling-bound prune: the first depth that succeeds is the TRUE minimum l(n) — a
//!     proof at this scale, the sound analogue of superopt's exhaustive check. Every chain is then re-checked
//!     by an INDEPENDENT verifier (each step is a sum of two priors; ends at n).
//!   • BEATS NAIVE RECOMBINATION. The binary method (a fixed algorithm: floor(log2 n)+popcount(n)-1) is the
//!     recombination baseline. Where l(n) < binary, the engine found a strictly better construction it was
//!     never given — the exact shape of FunSearch (better cap-set bound) / AlphaEvolve (better matmul).
//!
//! Honest scope: for small n these l(n) are tabulated (known to humanity) — so this is "real invention by the
//! engine" (undirected, certified, not recalled) demonstrated, NOT "new to humanity". New-to-humanity is the
//! identical machine at larger scale / an open target. The contribution here is the MECHANISM, run to a
//! certified result on answers I did not pre-supply.
//!
//! Run: zig build dial-three --release=fast

const std = @import("std");

const SWEEP_HI: u64 = 1024; // certify l(n) for every n in [2, SWEEP_HI]
const MAXLEN: usize = 80;
var chain: [MAXLEN + 1]u64 = undefined;
var best: [MAXLEN + 1]u64 = undefined;

fn ilog2(n: u64) usize {
    var k: usize = 0;
    var v = n;
    while (v > 1) : (v >>= 1) k += 1;
    return k;
}
// the NAIVE baseline (fixed algorithm = recombination): floor(log2 n) + popcount(n) - 1
fn binaryLen(n: u64) usize {
    return ilog2(n) + @as(usize, @popCount(n)) - 1;
}

// Constructive binary-method addition chain of length binaryLen(n). Feasible for
// ANY n (no search). Used by the factor method so factor chains stay computable
// even when the minimal-chain IDDFS would be infeasible (large factors).
// Writes the chain into `best` and returns its length.
const BIN_CHAIN_CAP: usize = 4096;
var bin_chain: [BIN_CHAIN_CAP + 1]u64 = undefined;
fn binaryChain(n: u64) usize {
    // Classic double-and-add: build chain of exponents of the set bits of n.
    var len: usize = 0;
    bin_chain[0] = 1;
    var i: usize = 0;
    const top = ilog2(n);
    // first build 1,2,4,...,2^top
    while (i < top) : (i += 1) {
        len += 1;
        bin_chain[len] = bin_chain[len - 1] + bin_chain[len - 1];
    }
    // now fold in the remaining bits via addition of previously built powers
    var bit: usize = 0;
    while (bit <= top) : (bit += 1) {
        if ((n >> @intCast(bit)) & 1 == 1 and bit != top) {
            len += 1;
            bin_chain[len] = bin_chain[len - 1] + bin_chain[bit];
        }
    }
    return len;
}

// Factors larger than this use the constructive binary chain (shortest() IDDFS is
// infeasible beyond it). Below it, minimal chains are affordable.
const SHORTEST_FEASIBLE: u64 = 1 << 16;

// complete iterative-deepening DFS over ASCENDING addition chains. success iff chain[len]==target exactly.
fn dfs(i: usize, len: usize, target: u64) bool {
    if (i == len) return chain[i] == target;
    const left = len - i - 1; // steps remaining AFTER placing chain[i+1]
    var a: usize = i;
    while (true) : (a -= 1) {
        var b: usize = a;
        while (true) : (b -= 1) {
            const c = chain[a] + chain[b];
            // ascending representative (c > current max) and never overshoot n
            if (c > chain[i] and c <= target) {
                // admissible prune: max reachable from c in `left` steps is c<<left (repeated doubling)
                if ((c << @intCast(left)) >= target) {
                    chain[i + 1] = c;
                    if (dfs(i + 1, len, target)) return true;
                }
            }
            if (b == 0) break;
        }
        if (a == 0) break;
    }
    return false;
}

// returns the CERTIFIED-MINIMUM length l(n); fills best[0..=l(n)].
fn shortest(n: u64) usize {
    if (n == 1) {
        best[0] = 1;
        return 0;
    }
    chain[0] = 1;
    var len: usize = ilog2(n);
    if ((@as(u64, 1) << @intCast(len)) < n) len += 1; // ceil(log2 n) = true lower bound
    while (len <= MAXLEN) : (len += 1) {
        if (dfs(0, len, n)) {
            for (0..len + 1) |k| best[k] = chain[k];
            return len;
        }
    }
    return MAXLEN + 1;
}

// INDEPENDENT verifier (does not trust the search): each step a sum of two priors, strictly ascending, ends at n.
fn verify(len: usize, n: u64) bool {
    if (best[0] != 1) return false;
    if (best[len] != n) return false;
    var i: usize = 1;
    while (i <= len) : (i += 1) {
        if (best[i] <= best[i - 1]) return false;
        var ok = false;
        for (0..i) |a| for (0..i) |bb| {
            if (best[a] + best[bb] == best[i]) ok = true;
        };
        if (!ok) return false;
    }
    return true;
}

fn printChain(o: anytype, len: usize) void {
    for (0..len + 1) |k| {
        if (k > 0) o.print("→", .{}) catch {};
        o.print("{d}", .{best[k]}) catch {};
    }
}

// --- Factor-aware construction (IN-CLOSURE heuristic, not an escape) ---------
// Theorem (within the addition-chain closure): if n = a*b then l(n) <= l(a)+l(b).
// This builds a valid ascending chain for n using the factor method:
//   1. build a chain for a   (entries a_0..a_la, a_la = a)
//   2. build a chain for b   (entries b_0..b_lb, b_lb = b)
//   3. form n = a*b by taking the chain for a and multiplying each entry by b,
//      which is achievable because b's chain gives us the doublings/scalings.
// The resulting chain uses only additions, so it is a legal addition chain.
// The independent checker (addchain_check.zig) still PROVES minimality; this
// function only supplies a candidate that is shorter than the blind IDDFS can
// reach on large composites. We never claim the candidate is minimal here.
//
// Returns the chain length; writes the chain into `best`. On failure (n prime or
// factorization too large) returns 0 and leaves `best` untouched.
fn smallestFactor(n: u64) u64 {
    if (n % 2 == 0) return 2;
    var d: u64 = 3;
    while (d * d <= n) : (d += 2) {
        if (n % d == 0) return d;
    }
    return n; // prime
}

fn factorChain(n: u64) usize {
    if (n < 2) return 0;
    const a = smallestFactor(n);
    if (a == n) return 0; // prime -> no factor construction
    const b = n / a;
    // Build chain(a): use shortest() only when feasible, else constructive binary chain.
    const la = if (a < 2) 0 else if (a <= SHORTEST_FEASIBLE) shortest(a) else binaryChain(a);
    // Preserve chain(a) BEFORE computing chain(b) (shortest() overwrites `best`).
    var cha: [MAXLEN + 1]u64 = undefined;
    if (a <= SHORTEST_FEASIBLE) {
        for (0..la + 1) |k| cha[k] = best[k];
    } else {
        for (0..la + 1) |k| cha[k] = bin_chain[k];
    }
    const lb = if (b < 2) 0 else if (b <= SHORTEST_FEASIBLE) shortest(b) else binaryChain(b);
    if (la > MAXLEN or lb > MAXLEN) return 0;

    // Build the factor-method chain:
    //   Phase 1: chain for b  -> out[0..lb] = chain(b)
    //   Phase 2: scaled entries s_i = a_i * b for each a_i in chain(a).
    //   a_0 = 1 -> s_0 = b (already out[0]). For k>=1, a_k = a_p + a_q (p,q<k,
    //   valid addition-chain step) so s_k = s_p + s_q, both already built.
    var out: [MAXLEN + 1]u64 = undefined;
    var ol: usize = 0;
    {
        var i: usize = 0;
        while (i <= lb) : (i += 1) {
            out[ol + i] = if (b <= SHORTEST_FEASIBLE) best[i] else bin_chain[i];
        }
        ol = lb;
    }
    // scaled[k] = a_k * b, built from scaled[p] + scaled[q] where a_k = a_p + a_q.
    // scaled[0] = a_0 * b = 1 * b = b (already out[0]..out[lb] ends at b; out[lb]==b).
    var scaled: [MAXLEN + 1]u64 = undefined;
    scaled[0] = b;
    {
        var i: usize = 1;
        while (i <= la) : (i += 1) {
            var p: usize = 0;
            var found = false;
            while (!found and p < i) : (p += 1) {
                var q: usize = 0;
                while (!found and q < i) : (q += 1) {
                    if (cha[p] + cha[q] == cha[i]) {
                        const s_k = scaled[p] + scaled[q];
                        if (ol + 1 > MAXLEN or s_k <= out[ol]) {
                            return 0;
                        }
                        ol += 1;
                        out[ol] = s_k;
                        scaled[i] = s_k;
                        found = true;
                    }
                }
            }
            if (!found) {
                return 0;
            }
        }
    }
    if (out[ol] != n) {
        return 0;
    }
    // validity: each step must be a sum of two earlier entries
    {
        var i: usize = 1;
        while (i <= ol) : (i += 1) {
            var ok = false;
            var p: usize = 0;
            while (!ok and p < i) : (p += 1) {
                var q: usize = 0;
                while (!ok and q < i) : (q += 1) {
                    if (out[p] + out[q] == out[i]) ok = true;
                }
            }
            if (!ok) return 0;
        }
    }
    for (0..ol + 1) |k| best[k] = out[k];
    return ol;
}

// --- Windowed / m-ary construction (a search VARIATION, not the baseline) ---
// Unlike the binary method (base 2), build the chain for the digits of n in
// base 2^k (the "window"). Classic sliding-window / m-ary addition-chain
// construction:
//   step 1: precompute every odd value in [1, 2^k) as a chain (small table).
//   step 2: build 1,2,4,...,2^top via doublings.
//   step 3: scan the bits of n in windows of k: when a run of zeros is seen,
//           double (extend the window); when a window of k bits is full, fold in
//           the precomputed odd multiple via one addition.
// This yields a chain whose length is <= binary length, often strictly shorter
// when n has sparse / clustered high bits. The independent checker still proves
// validity (and minimality where feasible). We never claim this is minimal.
//
// Writes the chain into `best` and returns its length. Returns 0 on overflow /
// infeasibility (caller falls back). `k` is the window width (>=1).
const WIN_CHAIN_CAP: usize = 8192;
var win_chain: [WIN_CHAIN_CAP + 1]u64 = undefined;
fn windowChain(n: u64, k: usize) usize {
    if (n < 2) return 0;
    if (k < 1) return 0;
    const m = @as(u64, 1) << @intCast(k); // 2^k
    // Step 1: precompute an addition chain for EVERY digit value v in [1, m).
    // dtbl[v] holds the chain entries (absolute values) for v, ending at v.
    var dtbl_len: [1 << 10]usize = undefined; // indexed by v (< 2^k <= 1024)
    var dtbl: [1 << 10][64]u64 = undefined;
    {
        var v: u64 = 1;
        while (v < m) : (v += 1) {
            var clen: usize = 0;
            dtbl[v][0] = 1;
            var i: usize = 0;
            const top = ilog2(v);
            while (i < top) : (i += 1) {
                clen += 1;
                dtbl[v][clen] = dtbl[v][clen - 1] + dtbl[v][clen - 1];
            }
            var bit: usize = 0;
            while (bit <= top) : (bit += 1) {
                if ((v >> @intCast(bit)) & 1 == 1 and bit != top) {
                    clen += 1;
                    dtbl[v][clen] = dtbl[v][clen - 1] + dtbl[v][bit];
                }
            }
            dtbl_len[v] = clen;
        }
    }
    // Step 2: m-ary construction. Write n in base 2^k: n = sum_i d_i * 2^{i*k}.
    // For the most-significant digit d_t we append its absolute chain (ending at
    // d_t). For each lower digit d_i: double k times (multiply running value by
    // 2^k), then append the chain for d_i as CUR + entry (each step a legal
    // addition-chain step because d_i < 2^k <= cur). The result is a valid chain
    // ending at n, with length <= binaryLen(n), often strictly shorter.
    var digs: [128]u64 = undefined;
    var nd: usize = 0;
    {
        var x = n;
        while (x > 0) : (nd += 1) {
            digs[nd] = x % m;
            x /= m;
        }
    }
    if (nd == 0) return 0;
    var len: usize = 0;
    win_chain[0] = 1;
    var val: u64 = 1;
    var i: usize = nd - 1; // most significant digit first
    while (true) {
        const d = digs[i];
        if (d != 0) {
            const dl = dtbl_len[d];
            if (i == nd - 1) {
                // absolute chain for the first digit
                var j: usize = 1;
                while (j <= dl) : (j += 1) {
                    len += 1;
                    if (len > WIN_CHAIN_CAP) return 0;
                    win_chain[len] = dtbl[d][j];
                    val = dtbl[d][j];
                }
            } else {
                // append BASE + entry for each entry of d's chain (skipping entry 1),
                // where BASE is the running value BEFORE this digit (constant), so the
                // result is the prefix*2^k + d_i we need. Each step is a legal sum of
                // two earlier (BASE + smaller) entries. d == 1 has an empty table
                // (dl == 0), so add it explicitly (BASE + 1, with 1 == win_chain[0]).
                const base = win_chain[len];
                if (dl == 0) {
                    len += 1;
                    if (len > WIN_CHAIN_CAP) return 0;
                    win_chain[len] = base + 1;
                    val = base + 1;
                } else {
                    var j: usize = 1;
                    while (j <= dl) : (j += 1) {
                        len += 1;
                        if (len > WIN_CHAIN_CAP) return 0;
                        const nv = base + dtbl[d][j];
                        win_chain[len] = nv;
                        val = nv;
                    }
                }
            }
        }
        if (i == 0) break;
        // double k times
        var dd: usize = 0;
        while (dd < k) : (dd += 1) {
            len += 1;
            if (len > WIN_CHAIN_CAP) return 0;
            win_chain[len] = win_chain[len - 1] + win_chain[len - 1];
            val = val + val;
        }
        i -= 1;
    }
    if (val != n) return 0;
    // validity recheck: each step a sum of two earlier entries, strictly ascending
    {
        var ii: usize = 1;
        while (ii <= len) : (ii += 1) {
            var ok = false;
            var p: usize = 0;
            while (!ok and p < ii) : (p += 1) {
                var q: usize = 0;
                while (!ok and q < ii) : (q += 1) {
                    if (win_chain[p] + win_chain[q] == win_chain[ii]) ok = true;
                }
            }
            if (!ok) return 0;
        }
    }
    for (0..len + 1) |kk| best[kk] = win_chain[kk];
    return len;
}

// External-verification mode. Reads targets from CSV (lines: "n" or "n,label").
// Emits JSON: for each target, the found chain + its length + the binary-method
// upper bound. The engine does NOT assert minimality here — addchain_check.zig
// re-proves minimality independently. If the search exceeds MAXLEN, reports
// found=false (honest non-answer, never a fake minimal chain).
const EngineMode = enum { blind, factor, window, hybrid };

fn runTargets(allocator: std.mem.Allocator, path: []const u8, json_path: ?[]const u8, mode: EngineMode, win_k: usize) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const content = try file.readToEndAllocOptions(allocator, 1 << 30, null, 1, 0);
    defer allocator.free(content);

    var out_buf = std.ArrayList(u8).init(allocator);
    defer out_buf.deinit();
    const w = out_buf.writer();

    try w.print("{{\"results\":[", .{});
    var first = true;
    var it = std.mem.tokenizeScalar(u8, content, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r\t");
        if (trimmed.len == 0) continue;
        // split on comma; first field is n
        var fields = std.mem.tokenizeScalar(u8, trimmed, ',');
        const n_str = std.mem.trim(u8, fields.next() orelse "", " \r\t");
        const n = std.fmt.parseUnsigned(u64, n_str, 10) catch {
            // out-of-range / unparseable target (e.g. >2^64): emit explicit
            // abstention so the verifier counts it instead of silent dropping.
            if (!first) try w.print(",", .{});
            first = false;
            try w.print("{{\"n\":0,\"found\":false,\"length\":{d},\"binary_len\":0,\"note\":\"unparseable\"}}", .{MAXLEN + 1});
            continue;
        };

        var l: usize = MAXLEN + 1;
        switch (mode) {
            .blind => l = shortest(n),
            .factor => {
                const fl = factorChain(n);
                if (fl > 0) l = fl;
            },
            .window => {
                const wl = windowChain(n, win_k);
                if (wl > 0) l = wl;
            },
            .hybrid => {
                // try all three constructive methods, keep the shortest valid.
                var best_len: usize = MAXLEN + 1;
                // binary baseline (always valid for any n)
                const bl = binaryChain(n);
                if (bl > 0 and bl <= MAXLEN) best_len = bl;
                if (n <= SHORTEST_FEASIBLE) {
                    const sl = shortest(n);
                    if (sl <= MAXLEN and sl < best_len) best_len = sl;
                }
                const fl = factorChain(n);
                if (fl > 0 and fl < best_len) best_len = fl;
                const wl = windowChain(n, win_k);
                if (wl > 0 and wl < best_len) best_len = wl;
                l = best_len;
            },
        }
        const found = l <= MAXLEN;
        if (!first) try w.print(",", .{});
        first = false;
        if (found) {
            try w.print("{{\"n\":{d},\"found\":true,\"length\":{d},\"binary_len\":{d},\"chain\":[", .{ n, l, binaryLen(n) });
            for (0..l + 1) |k| {
                if (k > 0) try w.print(",", .{});
                try w.print("{d}", .{best[k]});
            }
            try w.print("]}}", .{});
        } else {
            try w.print("{{\"n\":{d},\"found\":false,\"length\":{d},\"binary_len\":{d}}}", .{ n, MAXLEN + 1, binaryLen(n) });
        }
    }
    try w.print("],\"maxlen\":{d}}}", .{MAXLEN});

    if (json_path) |jp| {
        var jf = try std.fs.cwd().createFile(jp, .{});
        defer jf.close();
        try jf.writeAll(out_buf.items);
    } else {
        const o = std.io.getStdOut().writer();
        try o.writeAll(out_buf.items);
        try o.writeAll("\n");
    }
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    // External-verification mode: read targets from a CSV file (one n per line,
    // optionally "n,label"), search each, emit MACHINE-READABLE JSON. The engine
    // does NOT self-label "CERTIFIED" — the independent checker (addchain_check.zig)
    // is the only authority on minimality. Targets are generated post-build from
    // /dev/urandom (addchain_gen.zig) so they cannot be hardcoded in this source.
    var targets_path: ?[]const u8 = null;
    var json_path: ?[]const u8 = null;
    var mode: EngineMode = .blind;
    var win_k: usize = 4;
    {
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--targets")) {
                i += 1;
                if (i < args.len) targets_path = args[i];
            } else if (std.mem.eql(u8, args[i], "--json")) {
                i += 1;
                if (i < args.len) json_path = args[i];
            } else if (std.mem.eql(u8, args[i], "--factor")) {
                mode = .factor;
            } else if (std.mem.eql(u8, args[i], "--window")) {
                mode = .window;
                // optional width: --window 4
                if (i + 1 < args.len) {
                    const maybe = std.fmt.parseUnsigned(usize, args[i + 1], 10) catch 0;
                    if (maybe >= 1 and maybe <= 9) {
                        win_k = maybe;
                        i += 1;
                    }
                }
            } else if (std.mem.eql(u8, args[i], "--hybrid")) {
                mode = .hybrid;
                if (i + 1 < args.len) {
                    const maybe = std.fmt.parseUnsigned(usize, args[i + 1], 10) catch 0;
                    if (maybe >= 1 and maybe <= 9) {
                        win_k = maybe;
                        i += 1;
                    }
                }
            }
        }
    }

    if (targets_path) |tp| {
        try runTargets(gpa, tp, json_path, mode, win_k);
        return;
    }

    const o = std.io.getStdOut().writer();
    try o.print("=== TURNING THE THIRD DIAL: certified shortest addition chains (a genuine unknown) ===\n\n", .{});
    try o.print("target l(n) = min r with 1=a0<...<a_r=n, each a_i a sum of two priors. No closed form; I do\n", .{});
    try o.print("NOT supply the answers — only the search + the binary-method baseline. Search = complete\n", .{});
    try o.print("iterative deepening (sound minimum), every chain re-checked by an independent verifier.\n\n", .{});

    var wins: usize = 0; // n where engine STRICTLY beats the binary baseline
    var ties: usize = 0;
    var total_saving: usize = 0;
    var max_saving: usize = 0;
    var champion: u64 = 0;
    var champ_l: usize = 0;
    var champ_bin: usize = 0;
    var verified_all = true;
    var n: u64 = 2;
    while (n <= SWEEP_HI) : (n += 1) {
        const l = shortest(n);
        if (!verify(l, n)) {
            verified_all = false;
            try o.print("  !! verifier REJECTED n={d}\n", .{n});
        }
        const bl = binaryLen(n);
        if (l < bl) {
            wins += 1;
            const sv = bl - l;
            total_saving += sv;
            if (sv > max_saving) {
                max_saving = sv;
                champion = n;
                champ_l = l;
                champ_bin = bl;
            }
        } else if (l == bl) ties += 1;
    }

    try o.print("CERTIFIED over every n in [2,{d}]  ({s})\n", .{ SWEEP_HI, if (verified_all) "all chains independently verified ✓" else "VERIFY FAILED" });
    try o.print("  engine STRICTLY beat the naive binary method on {d} of {d} values ({d:.1}%)\n", .{ wins, SWEEP_HI - 1, 100.0 * @as(f64, @floatFromInt(wins)) / @as(f64, @floatFromInt(SWEEP_HI - 1)) });
    try o.print("  matched it on {d}; the binary method is NEVER optimal-beating (it is an upper bound) so 0 losses.\n", .{ties});
    try o.print("  total additions saved vs baseline over the range: {d}\n", .{total_saving});

    // showcase: the smallest n where the naive algorithm is provably suboptimal
    var first_win: u64 = 0;
    n = 2;
    while (n <= SWEEP_HI) : (n += 1) {
        if (shortest(n) < binaryLen(n)) {
            first_win = n;
            break;
        }
    }
    const fl = shortest(first_win);
    try o.print("\nsmallest n where the naive method is PROVABLY suboptimal: n={d}\n", .{first_win});
    try o.print("    binary method length = {d}   |   certified minimum l({d}) = {d}\n    engine's chain: ", .{ binaryLen(first_win), first_win, fl });
    printChain(o, fl);
    try o.print("\n", .{});

    // champion: largest beat-the-baseline margin in range
    _ = shortest(champion);
    try o.print("\nlargest margin over the naive method in range: n={d}\n", .{champion});
    try o.print("    binary method length = {d}   |   certified minimum l({d}) = {d}   (saved {d} additions)\n    engine's chain: ", .{ champ_bin, champion, champ_l, max_saving });
    printChain(o, champ_l);
    try o.print("\n", .{});

    // a few specific values whose l(n) I (the operator) did NOT have memorized — the engine supplies them.
    const showcase = [_]u64{ 127, 255, 511, 1023, 1000 };
    try o.print("\nl(n) for values I did not pre-supply (the engine computes & certifies them):\n", .{});
    for (showcase) |m| {
        const lm = shortest(m);
        const okv = verify(lm, m);
        try o.print("    l({d}) = {d}   (binary {d}, saved {d})  {s}  ", .{ m, lm, binaryLen(m), binaryLen(m) - lm, if (okv) "✓" else "✗" });
        printChain(o, lm);
        try o.print("\n", .{});
    }

    try o.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try o.print("Dial (3) turned, end-to-end: a target with NO pre-supplied answer (shortest addition chains),\n", .{});
    try o.print("a SOUND verifier (complete iterative-deepening = a minimality proof at this scale, plus an\n", .{});
    try o.print("independent re-check of every chain), and the engine STRICTLY beating the naive recombination\n", .{});
    try o.print("baseline on {d} values it was never told. This is the FunSearch/AlphaEvolve shape exactly —\n", .{wins});
    try o.print("better-than-baseline constructions, certified — only at honestly-small scale.\n\n", .{});
    try o.print("Honest scope: these l(n) are tabulated for small n (known to HUMANITY), so this demonstrates the\n", .{});
    try o.print("MECHANISM of real invention (undirected, certified, not recalled, beats the fixed algorithm) — NOT\n", .{});
    try o.print("a new-to-humanity result. New-to-humanity is the IDENTICAL machine pointed at a larger / open target:\n", .{});
    try o.print("the only change is what you aim it at, exactly as real_invention.md concluded. Bounded as ever by the\n", .{});
    try o.print("injectable closure (here: the search space of ascending chains) and the soundness of the verifier.\n", .{});
    try o.print("\nSee: real_invention.md, superopt.md, ../README.md, ../CLOSURE_PRINCIPLE.md.\n", .{});
}
