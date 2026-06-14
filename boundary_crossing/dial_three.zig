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
const MAXLEN: usize = 40;
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

pub fn main() !void {
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
