//! labs_check.zig — INDEPENDENT external verifier for LABS claims emitted by
//! boundary_crossing/labs_campaign.zig (results/labs_claims_2026_07_10.json).
//!
//! This program is the ONLY authority on the claims. It deliberately shares NO
//! code with the campaign binary: energy is recomputed from scratch with a
//! direct O(N^2) double loop (no incremental updates, no Gray code), and for
//! PROVEN claims with n <= BRUTE_MAX it re-proves optimality with its own
//! naive brute-force enumeration (full re-evaluation per candidate).
//!
//! For every claim it checks:
//!   1. seq has exactly n entries, all +1 or -1;
//!   2. recomputed E' (from scratch) == claimed E;
//!   3. recomputed F' = n^2/(2E') matches claimed F within 1e-4;
//!   4. if status == "PROVEN" and n <= BRUTE_MAX: its OWN exhaustive search
//!      over 2^(n-1) sequences (s_0=+1, negation symmetry) must find no lower
//!      energy — otherwise the optimality claim is REFUTED. For PROVEN claims
//!      with n > BRUTE_MAX it reports "optimality not independently re-proven"
//!      (an honest non-claim, not a pass).
//!   5. HEURISTIC claims get checks 1-3 only (no optimality is claimed).
//!
//! Exit code 0 = every claim verified (with any honest non-reproofs listed).
//! Exit code 1 = at least one claim REFUTED.
//! Exit code 2 = usage / parse error.
//!
//! Build: zig build-exe scripts/zig/labs_check.zig -O ReleaseFast \
//!        -femit-bin=/tmp/claude-1000/labs_check
//! Run:   /tmp/claude-1000/labs_check results/labs_claims_2026_07_10.json
//!        (or pipe the JSON on stdin)

const std = @import("std");

const BRUTE_MAX: usize = 22; // independent optimality re-proof cap (2^21 candidates, full O(n^2) energy each)
const NMAX: usize = 256;

/// direct from-scratch energy: E = sum_{k=1}^{n-1} (sum_i s_i s_{i+k})^2
fn energyScratch(seq: []const i64) i64 {
    const n = seq.len;
    var e: i64 = 0;
    var k: usize = 1;
    while (k < n) : (k += 1) {
        var c: i64 = 0;
        var i: usize = 0;
        while (i + k < n) : (i += 1) c += seq[i] * seq[i + k];
        e += c * c;
    }
    return e;
}

/// naive independent exhaustive: minimum energy over all 2^(n-1) sequences with
/// s_0 = +1 (negation symmetry). No incremental tricks — every candidate fully
/// re-evaluated, so this shares no failure mode with the campaign's Gray scan.
fn bruteOptE(n: usize) i64 {
    var s: [BRUTE_MAX]i64 = undefined;
    s[0] = 1;
    var best: i64 = std.math.maxInt(i64);
    const total: u64 = @as(u64, 1) << @intCast(n - 1);
    var mask: u64 = 0;
    while (mask < total) : (mask += 1) {
        var i: usize = 1;
        while (i < n) : (i += 1) {
            s[i] = if ((mask >> @intCast(i - 1)) & 1 == 1) -1 else 1;
        }
        const e = energyScratch(s[0..n]);
        if (e < best) best = e;
    }
    return best;
}

fn getF(v: std.json.Value) ?f64 {
    return switch (v) {
        .float => |x| x,
        .integer => |x| @floatFromInt(x),
        else => null,
    };
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    // read JSON from argv[1] or stdin
    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();
    _ = args.next();
    const content = blk: {
        if (args.next()) |path| {
            const f = std.fs.cwd().openFile(path, .{}) catch {
                std.debug.print("ERR: cannot open {s}\n", .{path});
                std.process.exit(2);
            };
            defer f.close();
            break :blk try f.readToEndAlloc(gpa, 1 << 26);
        }
        break :blk try std.io.getStdIn().reader().readAllAlloc(gpa, 1 << 26);
    };
    defer gpa.free(content);

    const parsed = std.json.parseFromSlice(std.json.Value, gpa, content, .{}) catch {
        std.debug.print("ERR: JSON parse failure\n", .{});
        std.process.exit(2);
    };
    const root = parsed.value;
    const claims = (if (root == .object) root.object.get("claims") else null) orelse {
        std.debug.print("ERR: no 'claims' array\n", .{});
        std.process.exit(2);
    };
    if (claims != .array) {
        std.debug.print("ERR: 'claims' is not an array\n", .{});
        std.process.exit(2);
    }

    var refuted: usize = 0;
    var verified: usize = 0;
    var non_reproven: usize = 0;

    for (claims.array.items) |item| {
        if (item != .object) {
            std.debug.print("REFUTED: claim is not an object\n", .{});
            refuted += 1;
            continue;
        }
        const obj = item.object;
        const n_val = obj.get("n") orelse {
            refuted += 1;
            std.debug.print("REFUTED: claim missing 'n'\n", .{});
            continue;
        };
        const n: usize = @intCast(n_val.integer);
        const claimed_e = obj.get("E").?.integer;
        const claimed_f = getF(obj.get("F").?) orelse {
            refuted += 1;
            std.debug.print("n={d}: REFUTED (F not numeric)\n", .{n});
            continue;
        };
        const status_str = obj.get("status").?.string;
        const seq_val = obj.get("seq").?;

        // 1. structural validity
        if (seq_val != .array or seq_val.array.items.len != n or n < 2 or n > NMAX) {
            refuted += 1;
            std.debug.print("n={d}: REFUTED (seq length/shape wrong)\n", .{n});
            continue;
        }
        var seq: [NMAX]i64 = undefined;
        var ok = true;
        for (seq_val.array.items, 0..) |sv, i| {
            if (sv != .integer or (sv.integer != 1 and sv.integer != -1)) {
                ok = false;
                break;
            }
            seq[i] = sv.integer;
        }
        if (!ok) {
            refuted += 1;
            std.debug.print("n={d}: REFUTED (seq entry not +/-1)\n", .{n});
            continue;
        }

        // 2-3. recompute E and F from scratch
        const e2 = energyScratch(seq[0..n]);
        const f2 = @as(f64, @floatFromInt(n * n)) / (2.0 * @as(f64, @floatFromInt(e2)));
        if (e2 != claimed_e) {
            refuted += 1;
            std.debug.print("n={d}: REFUTED (claimed E={d}, recomputed E={d})\n", .{ n, claimed_e, e2 });
            continue;
        }
        if (@abs(f2 - claimed_f) > 1e-4) {
            refuted += 1;
            std.debug.print("n={d}: REFUTED (claimed F={d:.6}, recomputed F={d:.6})\n", .{ n, claimed_f, f2 });
            continue;
        }

        // 4. optimality re-proof for PROVEN claims
        if (std.mem.eql(u8, status_str, "PROVEN")) {
            if (n <= BRUTE_MAX) {
                const opt = bruteOptE(n);
                if (opt < e2) {
                    refuted += 1;
                    std.debug.print("n={d}: REFUTED non-optimal (independent brute force found E={d} < claimed optimal {d})\n", .{ n, opt, e2 });
                    continue;
                }
                if (opt > e2) {
                    // impossible if E recheck passed (claimed seq itself achieves e2) -> internal inconsistency
                    refuted += 1;
                    std.debug.print("n={d}: REFUTED inconsistent (brute min {d} > verified E {d}??)\n", .{ n, opt, e2 });
                    continue;
                }
                verified += 1;
                std.debug.print("n={d}: VERIFIED E={d} F={d:.4} and OPTIMALITY independently re-proven (brute 2^{d})\n", .{ n, e2, f2, n - 1 });
            } else {
                non_reproven += 1;
                verified += 1;
                std.debug.print("n={d}: VERIFIED E={d} F={d:.4}; PROVEN claim but optimality NOT independently re-proven here (n > brute cap {d}) — honest non-claim\n", .{ n, e2, f2, BRUTE_MAX });
            }
        } else {
            verified += 1;
            std.debug.print("n={d}: VERIFIED E={d} F={d:.4} [HEURISTIC — no optimality claimed]\n", .{ n, e2, f2 });
        }
    }

    std.debug.print("\n=== summary: verified={d} refuted={d} (of which optimality-not-reproven={d}) ===\n", .{ verified, refuted, non_reproven });
    if (refuted > 0) {
        std.debug.print("VERDICT: REFUTED — at least one claim failed independent re-check\n", .{});
        std.process.exit(1);
    }
    std.debug.print("VERDICT: all claims independently re-verified (E/F from scratch; optimality re-proven where n <= {d})\n", .{BRUTE_MAX});
}
