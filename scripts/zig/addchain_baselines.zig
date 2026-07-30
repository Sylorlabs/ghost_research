//! Baseline battery for addition-chain targets. Pure Zig, no Python.
//!
//! For each target n in the CSV it measures:
//!   - FIXED HEURISTIC (binary method): length = ilog2(n)+popcount(n)-1, 0 evals.
//!   - RANDOM SEARCH: generate N random valid chains (random step = sum of two
//!     random earlier entries), keep the shortest valid one; report best length
//!     and eval count (N).
//!   - ENGINE (from a precomputed engine JSON): the engine's length (if found).
//!
//! Output: a comparison table + aggregate win counts + eval totals.
//! The engine JSON is produced by dial_three --targets <csv> --json <out>.
//!
//! Run: zig build-exe addchain_baselines.zig -O ReleaseFast
//!      ./addchain_baselines <targets.csv> <engine.json> [random_samples]

const std = @import("std");

fn ilog2(n: u64) usize {
    var k: usize = 0;
    var v = n;
    while (v > 1) : (v >>= 1) k += 1;
    return k;
}
fn binaryLen(n: u64) usize {
    return ilog2(n) + @as(usize, @popCount(n)) - 1;
}

// random valid chain: start [1]; each step pick two random earlier indices and
// add them if the sum is > last and <= n. Stop when we hit n or max_steps.
fn randomChainLen(rnd: std.Random, n: u64, max_steps: usize) ?usize {
    var c: [128]u64 = undefined;
    c[0] = 1;
    var len: usize = 0;
    var steps: usize = 0;
    while (steps < max_steps) : (steps += 1) {
        if (len > 0 and c[len] == n) return len;
        const a = rnd.int(u64) % (len + 1);
        const b = rnd.int(u64) % (len + 1);
        const s = c[a] + c[b];
        if (s > c[len] and s <= n) {
            len += 1;
            if (len >= c.len) break;
            c[len] = s;
        }
    }
    if (len > 0 and c[len] == n) return len;
    return null;
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);
    if (args.len < 3) {
        std.debug.print("usage: addchain_baselines <targets.csv> <engine.json> [random_samples]\n", .{});
        return;
    }
    const targets_path = args[1];
    const engine_json = args[2];
    const n_random: u64 = if (args.len > 3) try std.fmt.parseUnsigned(u64, args[3], 10) else 200000;

    // parse engine JSON -> map n -> length
    const ej = try std.fs.cwd().readFileAlloc(gpa, engine_json, 1 << 26);
    defer gpa.free(ej);
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, ej, .{});
    const root = parsed.value;
    var eng_len = std.StringHashMap(usize).init(gpa);
    defer eng_len.deinit();
    if (root.object.get("results")) |res| {
        for (res.array.items) |it| {
            const n = it.object.get("n").?.integer;
            const found = it.object.get("found").?.bool;
            if (found) {
                const l = @as(usize, @intCast(it.object.get("length").?.integer));
                try eng_len.put(try std.fmt.allocPrint(gpa, "{d}", .{n}), l);
            }
        }
    }

    // parse targets
    const tc = try std.fs.cwd().readFileAlloc(gpa, targets_path, 1 << 26);
    defer gpa.free(tc);

    var rnd = std.Random.DefaultPrng.init(0xC0FFEE);
    const r = rnd.random();

    var bin_wins: usize = 0;
    var eng_wins: usize = 0;
    var rand_wins: usize = 0;
    var total: usize = 0;
    var rand_evals_total: u64 = 0;

    var it = std.mem.tokenizeScalar(u8, tc, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r\t");
        if (trimmed.len == 0) continue;
        var f = std.mem.tokenizeScalar(u8, trimmed, ',');
        const n_str = std.mem.trim(u8, f.next() orelse "", " \r\t");
        const n = std.fmt.parseUnsigned(u64, n_str, 10) catch continue;
        const bl = binaryLen(n);

        // engine
        const key = try std.fmt.allocPrint(gpa, "{d}", .{n});
        const eng = eng_len.get(key) orelse null;
        gpa.free(key);

        // random search
        var best_rand: ?usize = null;
        var s: u64 = 0;
        while (s < n_random) : (s += 1) {
            if (randomChainLen(r, n, 200)) |rl| {
                if (best_rand == null or rl < best_rand.?) best_rand = rl;
            }
        }
        rand_evals_total += n_random;

        total += 1;
        if (eng != null and eng.? < bl) eng_wins += 1;
        if (best_rand != null and best_rand.? < bl) rand_wins += 1;
        if (eng != null and eng.? <= bl) bin_wins += 1; // binary is an upper bound (never "lost")

        std.debug.print("n={d}: binary={d} engine={d} random={d}\n", .{
            n,                        bl,
            if (eng) |e| e else 9999, if (best_rand) |x| x else 9999,
        });
    }

    std.debug.print("\n=== BASELINE SUMMARY ({} targets, random_samples={d}) ===\n", .{ total, n_random });
    std.debug.print("  engine beats binary (strictly shorter): {d}/{d}\n", .{ eng_wins, total });
    std.debug.print("  random search beats binary:             {d}/{d}\n", .{ rand_wins, total });
    std.debug.print("  total random evals: {d}\n", .{rand_evals_total});
    std.debug.print("  (binary method is an upper bound: it is never 'lost'; engine/random win only by being shorter)\n", .{});
}
