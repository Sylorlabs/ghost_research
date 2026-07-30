//! lm_baseline.zig — LM-AGENT BASELINE for the addition-chain campaign.
//!
//! Goal: measure an LLM (Claude, via the `claude` CLI) as an addition-chain
//! generator and force every LLM output through the INDEPENDENT verifier
//! `addchain_check` — never trust the LLM's self-reported "minimal".
//!
//! For each target n in a CSV (one n per line; optional ",TYPE" suffix ignored):
//!   1. shell out to `claude -p "<prompt for n>"` (non-interactive print mode);
//!   2. extract the first JSON array of integers from the reply;
//!   3. wrap it as
//!        {"results":[{"n":N,"found":true,"length":L,"binary_len":B,"chain":[...]}]}
//!      and pipe it to `addchain_check` (built from scripts/zig/addchain_check.zig);
//!   4. parse addchain_check's stderr verdict: VALID? minimal (VERIFIED minimal vs
//!      VALID len ... minimality=UNPROVEN)? BEATS-BINARY? REFUTED?
//!   5. record and tally.
//!
//! Cost is measured in API calls (1 per target) and wall time.
//!
//! If the `claude` CLI is unavailable OR the subprocess fails (e.g. API rate
//! limit, auth error), the harness does NOT crash: it reports "LLM unavailable"
//! for that target, marks it as a non-answer, and continues. The run still
//! produces a valid summary so the harness is runnable anywhere.
//!
//! Build:
//!   zig build-exe lm_baseline.zig -O ReleaseFast
//! Run:
//!   ./lm_baseline <targets.csv> [addchain_check_bin] [claude_bin]
//!
//! Exit code: 0 always unless a usage error (bad args). "LLM unavailable" is an
//! honest negative result, not a failure.

const std = @import("std");

fn binaryLen(n: u64) usize {
    if (n <= 1) return 0;
    var k: usize = 0;
    var v = n;
    while (v > 1) : (v >>= 1) k += 1;
    // binary method: floor(log2 n) doubles + popcount(n)-1 adds
    var bits: usize = 0;
    var w = n;
    while (w > 0) : (w >>= 1) bits += @intCast(w & 1);
    return k + (bits - 1);
}

/// Pull the first balanced JSON array of integers out of arbitrary text.
fn extractJsonArray(allocator: std.mem.Allocator, text: []const u8) ![]u64 {
    const start = std.mem.indexOfScalar(u8, text, '[') orelse return error.NoArray;
    var depth: i32 = 0;
    var end: usize = 0;
    var i = start;
    while (i < text.len) : (i += 1) {
        if (text[i] == '[') depth += 1;
        if (text[i] == ']') {
            depth -= 1;
            if (depth == 0) {
                end = i + 1;
                break;
            }
        }
    }
    if (end == 0) return error.NoArray;
    const slice = text[start..end];

    var list = std.ArrayList(u64).init(allocator);
    var it = std.mem.tokenizeAny(u8, slice, "[] \t\r\n,");
    while (it.next()) |tok| {
        const v = std.fmt.parseUnsigned(u64, tok, 10) catch continue;
        try list.append(v);
    }
    if (list.items.len == 0) return error.NoArray;
    return list.toOwnedSlice();
}

fn buildPrompt(allocator: std.mem.Allocator, n: u64) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "Output a shortest addition chain for n={d} as a JSON array of integers. " ++
            "The chain must start at 1, end at {d}, and each entry must be the sum of two " ++
            "(not necessarily distinct) earlier entries, strictly increasing. " ++
            "Reply with ONLY the JSON array, no prose.",
        .{ n, n },
    );
}

const TargetResult = struct {
    n: u64,
    available: bool,
    parsed: bool,
    valid: bool,
    minimal: bool, // true only when verifier says "VERIFIED minimal" (proven)
    beats_binary: bool,
    length: ?usize,
    bin_length: usize,
    verdict: []const u8,
};

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len < 2) {
        std.debug.print("usage: lm_baseline <targets.csv> [addchain_check_bin] [claude_bin]\n", .{});
        std.process.exit(2);
    }

    const targets_path = args[1];
    const checker_path = if (args.len > 2) args[2] else "scripts/zig/addchain_check";
    const claude_bin = if (args.len > 3) args[3] else "claude";

    // ---- Probe LLM availability once (which claude; then a tiny canary call) ----
    const claude_exists = blk: {
        const res = std.process.Child.run(.{
            .allocator = gpa,
            .argv = &.{ "which", claude_bin },
        }) catch break :blk false;
        defer gpa.free(res.stdout);
        defer gpa.free(res.stderr);
        const ok = res.term == .Exited and res.term.Exited == 0 and res.stdout.len > 0;
        break :blk ok;
    };

    var llm_available = claude_exists;
    if (claude_exists) {
        // canary call to detect auth/rate-limit failures up front
        const canary = std.process.Child.run(.{
            .allocator = gpa,
            .argv = &.{ claude_bin, "-p", "--model", "sonnet", "Reply with exactly the word: OK" },
        });
        if (canary) |c| {
            defer gpa.free(c.stdout);
            defer gpa.free(c.stderr);
            if (c.term != .Exited or c.term.Exited != 0 or
                std.mem.indexOf(u8, c.stdout, "OK") == null)
            {
                llm_available = false;
                std.debug.print("(claude CLI present but canary call failed; treating LLM as unavailable)\n", .{});
                std.debug.print("canary stderr: {s}\n", .{c.stderr});
            }
        } else |_| {
            llm_available = false;
        }
    }
    std.debug.print("LLM available: {s}\n", .{if (llm_available) "YES" else "NO"});

    // ---- Read targets ----
    const csv = try std.fs.cwd().readFileAlloc(gpa, targets_path, 1 << 24);
    defer gpa.free(csv);
    var lines = std.mem.splitScalar(u8, csv, '\n');
    var targets = std.ArrayList(u64).init(gpa);
    defer targets.deinit();
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        // optional ",TYPE" suffix: take token before comma
        const comma = std.mem.indexOfScalar(u8, trimmed, ',');
        const numstr = if (comma) |c| trimmed[0..c] else trimmed;
        const n = std.fmt.parseUnsigned(u64, std.mem.trim(u8, numstr, " "), 10) catch continue;
        try targets.append(n);
    }
    if (targets.items.len == 0) {
        std.debug.print("no targets parsed from {s}\n", .{targets_path});
        std.process.exit(2);
    }
    std.debug.print("targets: {d}\n", .{targets.items.len});

    // ---- Per-target loop ----
    var results = std.ArrayList(TargetResult).init(gpa);
    defer results.deinit();

    var total_api_calls: u64 = 0;
    const t0 = std.time.milliTimestamp();

    for (targets.items) |n| {
        const bin = binaryLen(n);
        var r = TargetResult{
            .n = n,
            .available = llm_available,
            .parsed = false,
            .valid = false,
            .minimal = false,
            .beats_binary = false,
            .length = null,
            .bin_length = bin,
            .verdict = "n/a",
        };

        if (!llm_available) {
            r.verdict = "LLM unavailable (honest non-answer)";
            try results.append(r);
            continue;
        }

        // 1. call claude
        const prompt = try buildPrompt(gpa, n);
        defer gpa.free(prompt);
        total_api_calls += 1;
        const call = std.process.Child.run(.{
            .allocator = gpa,
            .argv = &.{ claude_bin, "-p", "--model", "sonnet", prompt },
        }) catch {
            r.available = false;
            r.verdict = "LLM subprocess failed (unavailable)";
            try results.append(r);
            continue;
        };
        defer gpa.free(call.stdout);
        defer gpa.free(call.stderr);
        if (call.term != .Exited or call.term.Exited != 0) {
            r.verdict = "LLM call errored";
            try results.append(r);
            continue;
        }

        // 2. parse array
        const chain = extractJsonArray(gpa, call.stdout) catch {
            r.verdict = "LLM output: no JSON array parsed";
            try results.append(r);
            continue;
        };
        defer gpa.free(chain);
        r.parsed = true;

        // basic structural sanity before invoking checker
        if (chain.len < 2 or chain[0] != 1 or chain[chain.len - 1] != n) {
            r.verdict = "LLM chain structurally invalid (start/end/bounds)";
            try results.append(r);
            continue;
        }
        const claimed_len = chain.len - 1;

        // 3. wrap and pipe to addchain_check
        var payload = std.ArrayList(u8).init(gpa);
        defer payload.deinit();
        try payload.writer().print(
            "{{\"results\":[{{\"n\":{d},\"found\":true,\"length\":{d},\"binary_len\":{d},\"chain\":[",
            .{ n, claimed_len, bin },
        );
        for (chain, 0..) |v, k| {
            if (k > 0) try payload.writer().writeByte(',');
            try payload.writer().print("{d}", .{v});
        }
        try payload.writer().writeAll("]}]}");

        var check = std.process.Child.init(&.{checker_path}, gpa);
        check.stdin_behavior = .Pipe;
        check.stdout_behavior = .Pipe;
        check.stderr_behavior = .Pipe;
        check.spawn() catch {
            r.verdict = "checker invocation failed";
            try results.append(r);
            continue;
        };
        _ = try check.stdin.?.writeAll(payload.items);
        check.stdin.?.close();
        const check_out = try check.stdout.?.readToEndAlloc(gpa, 1 << 20);
        const check_err = try check.stderr.?.readToEndAlloc(gpa, 1 << 20);
        _ = try check.wait();

        const out = try std.fmt.allocPrint(gpa, "{s}{s}", .{ check_out, check_err });
        defer gpa.free(out);
        defer gpa.free(check_out);
        defer gpa.free(check_err);

        // 4. interpret verdict from checker text (authoritative)
        if (std.mem.indexOf(u8, out, "REFUTED invalid") != null) {
            r.verdict = "REFUTED invalid";
        } else if (std.mem.indexOf(u8, out, "REFUTED non-minimal") != null) {
            r.verdict = "REFUTED non-minimal";
        } else if (std.mem.indexOf(u8, out, "VERIFIED minimal") != null) {
            r.valid = true;
            r.minimal = true;
            if (std.mem.indexOf(u8, out, "BEATS-BINARY") != null) r.beats_binary = true;
            r.verdict = if (r.beats_binary) "VERIFIED minimal, BEATS-BINARY" else "VERIFIED minimal, ties-binary";
        } else if (std.mem.indexOf(u8, out, "VALID len") != null) {
            r.valid = true;
            if (std.mem.indexOf(u8, out, "BEATS-BINARY") != null) r.beats_binary = true;
            r.verdict = if (r.beats_binary) "VALID, BEATS-BINARY (minimality unproven)" else "VALID, ties-binary (minimality unproven)";
        } else {
            r.verdict = "checker: unclear verdict";
        }
        r.length = claimed_len;
        try results.append(r);
    }

    const elapsed_ms = std.time.milliTimestamp() - t0;

    // ---- Summary ----
    var n_avail: u64 = 0;
    var n_parsed: u64 = 0;
    var n_valid: u64 = 0;
    var n_minimal: u64 = 0;
    var n_beats: u64 = 0;
    for (results.items) |r| {
        if (r.available) n_avail += 1;
        if (r.parsed) n_parsed += 1;
        if (r.valid) n_valid += 1;
        if (r.minimal) n_minimal += 1;
        if (r.beats_binary) n_beats += 1;
    }

    std.debug.print("\n===== LM BASELINE SUMMARY =====\n", .{});
    std.debug.print("targets            : {d}\n", .{results.items.len});
    std.debug.print("LLM available      : {s}\n", .{if (llm_available) "YES" else "NO"});
    std.debug.print("API calls made     : {d}\n", .{total_api_calls});
    std.debug.print("wall time (ms)     : {d}\n", .{elapsed_ms});
    std.debug.print("chains parsed      : {d}\n", .{n_parsed});
    std.debug.print("chains VALID       : {d}\n", .{n_valid});
    std.debug.print("chains MINIMAL(prov): {d}\n", .{n_minimal});
    std.debug.print("chains BEAT binary : {d}\n", .{n_beats});
    std.debug.print("\n----- per-target -----\n", .{});
    for (results.items) |r| {
        std.debug.print("n={d:>6} bin={d:>3} len={s:>4} :: {s}\n", .{
            r.n,
            r.bin_length,
            if (r.length) |l| std.fmt.allocPrint(gpa, "{d}", .{l}) catch "?" else "?",
            r.verdict,
        });
    }
}
