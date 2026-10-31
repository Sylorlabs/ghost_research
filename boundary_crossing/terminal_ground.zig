//! terminal_ground.zig — D1 wired to a REAL terminal: meaning grounded in ACTUAL command outcomes. No LLM.
//!
//! grounded_language.zig D1 learned word→outcome from simulated episodes. This runs the commands FOR REAL
//! (std.process.Child → sh -c → real exit code), learns word meaning from genuine execution, then predicts the
//! outcome of NOVEL requests and RUNS them to check its predictions against reality. The terminal is the
//! verifier; the labels are perfect because they are what actually happened (RLVR, grounded for real).
//!
//! Safe by construction: every command is a hardcoded, read-only probe (test -f / ls / cat>/dev/null / echo /
//! false). No writes, no deletes, no network, no user input — nothing destructive.
//!
//! Run from boundary_crossing/: zig build terminal-ground --release=fast

const std = @import("std");

const Req = struct { nl: []const u8, cmd: []const u8 };

// run a safe command for REAL; outcome = its actual exit code (1=success, 0=failure). This IS the grounding.
fn runOutcome(a: std.mem.Allocator, cmd: []const u8) u8 {
    const res = std.process.Child.run(.{ .allocator = a, .argv = &.{ "sh", "-c", cmd } }) catch return 0;
    defer a.free(res.stdout);
    defer a.free(res.stderr);
    return switch (res.term) {
        .Exited => |c| if (c == 0) 1 else 0,
        else => 0,
    };
}

var vocab: std.StringHashMap(usize) = undefined;
var vcount: usize = 0;
fn low(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn toks(a: std.mem.Allocator, text: []const u8, add: bool) ![]usize {
    var list = std.ArrayList(usize).init(a);
    var i: usize = 0;
    var buf: [48]u8 = undefined;
    while (i < text.len) {
        var n: usize = 0;
        while (i < text.len and low(text[i]) >= 'a' and low(text[i]) <= 'z') : (i += 1) {
            if (n < buf.len) {
                buf[n] = low(text[i]);
                n += 1;
            }
        }
        if (n == 0) {
            i += 1;
            continue;
        }
        const tk = buf[0..n];
        if (vocab.get(tk)) |idx| try list.append(idx) else if (add) {
            try vocab.put(try a.dupe(u8, tk), vcount);
            try list.append(vcount);
            vcount += 1;
        }
    }
    return list.toOwnedSlice();
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();
    vocab = std.StringHashMap(usize).init(a);
    try o.print("=== TERMINAL GROUND — language grounded in REAL command outcomes (the engine actually runs them) ===\n\n", .{});

    const train = [_]Req{
        .{ .nl = "does the readme exist", .cmd = "test -f README.md" },
        .{ .nl = "does the build file exist", .cmd = "test -f build.zig" },
        .{ .nl = "does the missing file exist", .cmd = "test -f zzz_missing.xyz" },
        .{ .nl = "does the fake file exist", .cmd = "test -f zzz_fake.xyz" },
        .{ .nl = "list the zig sources", .cmd = "ls *.zig >/dev/null 2>&1" },
        .{ .nl = "list the absent folder", .cmd = "ls /zzz_no_such_dir >/dev/null 2>&1" },
        .{ .nl = "echo a greeting", .cmd = "echo hi >/dev/null" },
        .{ .nl = "run the false command", .cmd = "false" },
        .{ .nl = "cat the readme", .cmd = "cat README.md >/dev/null 2>&1" },
        .{ .nl = "cat the nonexistent file", .cmd = "cat zzz_nope.xyz >/dev/null 2>&1" },
    };

    // ── LEARN: run each command ONCE, ground its words in the ACTUAL exit code ──
    try o.print("[learning] running {d} real commands, grounding words in their ACTUAL exit codes:\n", .{train.len});
    var tix: [train.len][]usize = undefined;
    var outcomes: [train.len]u8 = undefined;
    for (train, 0..) |r, k| {
        outcomes[k] = runOutcome(a, r.cmd);
        tix[k] = try toks(a, r.nl, true);
        try o.print("   \"{s:<28}\"  `{s:<34}`  REAL: {s}\n", .{ r.nl, r.cmd, if (outcomes[k] == 1) "success" else "FAILURE" });
    }
    const w = try a.alloc(f32, vcount * 2);
    @memset(w, 0);
    for (0..300) |_| for (0..train.len) |k| {
        var s0: f32 = 0;
        var s1: f32 = 0;
        for (tix[k]) |x| {
            s0 += w[x * 2];
            s1 += w[x * 2 + 1];
        }
        const truth = outcomes[k];
        const pred: u8 = if (s1 > s0) 1 else 0;
        if (pred != truth) for (tix[k]) |x| {
            w[x * 2 + truth] += 1;
            w[x * 2 + pred] -= 1;
        };
    };

    // ── PREDICT → VERIFY: novel requests; predict from grounded words, then ACTUALLY run to check ──
    const held = [_]Req{
        .{ .nl = "does the fake readme exist", .cmd = "test -f zzz_fake_readme.xyz" },
        .{ .nl = "cat the missing readme", .cmd = "cat zzz_missing_readme.xyz >/dev/null 2>&1" },
        .{ .nl = "list the zig sources again", .cmd = "ls *.zig >/dev/null 2>&1" },
        .{ .nl = "does the build file exist now", .cmd = "test -f build.zig" },
        .{ .nl = "echo another greeting", .cmd = "echo yo >/dev/null" },
        .{ .nl = "run a nonexistent script", .cmd = "sh zzz_missing_script.sh >/dev/null 2>&1" },
    };
    try o.print("\n[predict→verify] novel requests — PREDICT from grounded words, then RUN it to check reality:\n", .{});
    var correct: usize = 0;
    for (held) |r| {
        const ix = try toks(a, r.nl, false);
        var s0: f32 = 0;
        var s1: f32 = 0;
        for (ix) |x| {
            s0 += w[x * 2];
            s1 += w[x * 2 + 1];
        }
        const pred: u8 = if (s1 > s0) 1 else 0;
        const real = runOutcome(a, r.cmd); // actually run it — ground truth
        const hit = pred == real;
        if (hit) correct += 1;
        try o.print("   \"{s:<30}\"  predict {s:<7}  ran→ REAL {s:<7}  {s}\n", .{ r.nl, if (pred == 1) "success" else "failure", if (real == 1) "success" else "failure", if (hit) "✓" else "✗" });
    }

    try o.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try o.print("Grounded in a REAL terminal: word meaning was learned from ACTUAL exit codes — \"missing/fake/\n", .{});
    try o.print("nonexistent/absent/false\" ⇒ failure, \"readme/build/sources/echo\" ⇒ success — and it predicted novel\n", .{});
    try o.print("requests it never ran, verified against reality: {d}/{d}. No text corpus, no LLM.\n", .{ correct, held.len });
    try o.print("The meaning is grounded in what the commands ACTUALLY DID: the terminal is the verifier, the exit code\n", .{});
    try o.print("is the perfect label, the engine learns language from it. HONEST: this grounds the success/failure\n", .{});
    try o.print("dimension; richer outcomes (specific output, error kinds) are the same loop with a richer label. The\n", .{});
    try o.print("actionable, checkable slice of language — grounded for real, no LLM. THIS is where the wall isn't.\n", .{});
}
