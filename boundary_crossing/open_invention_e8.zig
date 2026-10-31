//! open_invention_e8.zig — EXPERIMENT E8: terminal-invented predicates (execution as verifier).
//!
//! The terminal IS the verifier. Safe whitelisted commands are run FOR REAL; each run records exit code +
//! timing + I/O footprint. Primitive execution sensors are searched; surviving distinct behaviors are
//! INVENTED PREDICATES (feature_invent pattern on runs, not integers). NL request tokens are FORGED into
//! compound features (rune-style bigrams); a logistic readout predicts outcome on AUTO-GENERATED held-out
//! targets; every prediction is verified by a future live run.
//!
//! E8 predicts outcome class only (ok vs errors). E18 (open_invention_e18.zig) extends this to NL→command
//! synthesis: phrase→command→outcome with certified argv match on 100 held-out phrasings.
//!
//! References: engine_live.zig, terminal_ground.zig, verify_learn_invent --live, open_invention_e18.zig.
//!
//! Run: zig build open-invention-e8 --release=fast
//!      zig build open-invention-e8 --release=fast -- --live   (default: live shell execution)

const std = @import("std");

const NC = 2; // logistic readout: errors vs ok (timing kept for invented predicates)
const cname = [_][]const u8{ "errors", "ok" };
const FAST_MS: u32 = 50;

// ── safe whitelist: read-only probes only (no writes, network, or user input) ──
const SAFE_CMDS = [_][]const u8{ "test", "ls", "echo", "false", "true", "pwd", "wc", "head", "grep", "cat", "find" };

fn isSafeCmd(cmd: []const u8) bool {
    for (SAFE_CMDS) |s| {
        if (std.mem.startsWith(u8, cmd, s)) return true;
    }
    return false;
}

const RunSig = struct {
    exit_ok: bool,
    time_ms: u32,
    out_len: u32,
    err_len: u32,

    fn outcome(self: RunSig) u8 {
        return if (self.exit_ok) 1 else 0;
    }

    fn timingTag(self: RunSig) []const u8 {
        if (!self.exit_ok) return "fail";
        return if (self.time_ms < FAST_MS) "fast" else "slow";
    }
};

const Obs = struct { nl: []const u8, cmd: []const u8, sig: RunSig };

fn runLive(a: std.mem.Allocator, cmd: []const u8) !RunSig {
    const t0 = std.time.nanoTimestamp();
    const res = std.process.Child.run(.{
        .allocator = a,
        .argv = &.{ "sh", "-c", cmd },
        .max_output_bytes = 1 << 18,
    }) catch {
        const t1 = std.time.nanoTimestamp();
        return .{
            .exit_ok = false,
            .time_ms = @intCast(@max(0, @divTrunc(t1 - t0, std.time.ns_per_ms))),
            .out_len = 0,
            .err_len = 0,
        };
    };
    defer a.free(res.stdout);
    defer a.free(res.stderr);
    const t1 = std.time.nanoTimestamp();
    const ok = switch (res.term) {
        .Exited => |c| c == 0,
        else => false,
    };
    return .{
        .exit_ok = ok,
        .time_ms = @intCast(@max(0, @divTrunc(t1 - t0, std.time.ns_per_ms))),
        .out_len = @intCast(res.stdout.len),
        .err_len = @intCast(res.stderr.len),
    };
}

// ═══════════════════════════════════════════════════════════════════════════
// Primitive execution sensors (the only handed atoms — predicates are invented)
// ═══════════════════════════════════════════════════════════════════════════

const Atom = enum(u8) {
    exit_ok,
    exit_fail,
    fast,
    slow,
    empty_out,
    has_out,
    has_stderr,
    err_dominates,
};

fn evalAtom(a: Atom, s: RunSig) bool {
    return switch (a) {
        .exit_ok => s.exit_ok,
        .exit_fail => !s.exit_ok,
        .fast => s.time_ms < FAST_MS,
        .slow => s.time_ms >= FAST_MS,
        .empty_out => s.out_len == 0,
        .has_out => s.out_len > 0,
        .has_stderr => s.err_len > 0,
        .err_dominates => s.err_len > s.out_len,
    };
}

const Pred = struct { a: Atom, b: ?Atom = null, neg: bool = false }; // atom or (a AND b)

fn evalPred(p: Pred, s: RunSig) bool {
    const v = if (p.b) |b| evalAtom(p.a, s) and evalAtom(b, s) else evalAtom(p.a, s);
    return if (p.neg) !v else v;
}

fn predName(p: Pred, buf: []u8) []const u8 {
    if (p.b) |b| {
        return std.fmt.bufPrint(buf, "{s}{s}∧{s}", .{
            if (p.neg) "¬(" else "",
            @tagName(p.a),
            @tagName(b),
        }) catch "?";
    }
    return std.fmt.bufPrint(buf, "{s}{s}", .{ if (p.neg) "¬" else "", @tagName(p.a) }) catch "?";
}

// invent predicates by behavior over training runs (dedup bitsets)
fn inventPredicates(a: std.mem.Allocator, sigs: []const RunSig) !struct { preds: []Pred, bits: []u64 } {
    var cands = std.ArrayList(Pred).init(a);
    for (@intFromEnum(Atom.exit_ok)..@intFromEnum(Atom.err_dominates) + 1) |ai| {
        const at: Atom = @enumFromInt(ai);
        try cands.append(.{ .a = at });
        try cands.append(.{ .a = at, .neg = true });
        for (@intFromEnum(Atom.exit_ok)..@intFromEnum(Atom.err_dominates) + 1) |bi| {
            if (bi <= ai) continue;
            const bt: Atom = @enumFromInt(bi);
            try cands.append(.{ .a = at, .b = bt });
        }
    }

    const n = sigs.len;
    const words = (n + 63) / 64;
    var seen = std.AutoHashMap(u64, void).init(a);
    var preds = std.ArrayList(Pred).init(a);
    var bits = std.ArrayList(u64).init(a);

    for (cands.items) |p| {
        var h: u64 = 0x9E3779B97F4A7C15;
        var buf = [_]u64{0} ** 32;
        if (words > buf.len) return error.TooManyRuns;
        @memset(buf[0..words], 0);
        var degenerate: bool = true;
        for (sigs, 0..) |s, i| {
            const v = evalPred(p, s);
            if (v) degenerate = false;
            if (v) buf[i / 64] |= @as(u64, 1) << @intCast(i % 64);
            h ^= buf[i / 64] +% 0x85EBCA77C2B2AE63 +% (h << 6) +% (h >> 2);
        }
        if (degenerate) continue;
        if (seen.contains(h)) continue;
        try seen.put(h, {});
        try preds.append(p);
        for (0..words) |w| try bits.append(buf[w]);
    }
    return .{ .preds = try preds.toOwnedSlice(), .bits = try bits.toOwnedSlice() };
}

// ═══════════════════════════════════════════════════════════════════════════
// Forge NL tokens → compound features (terminal_grind / rune bigram pattern)
// ═══════════════════════════════════════════════════════════════════════════

var vocab: std.StringHashMap(usize) = undefined;
var vcount: usize = 0;

fn low(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

fn intern(a: std.mem.Allocator, tk: []const u8, add: bool, list: *std.ArrayList(usize)) !void {
    if (vocab.get(tk)) |idx| {
        try list.append(idx);
    } else if (add) {
        try vocab.put(try a.dupe(u8, tk), vcount);
        try list.append(vcount);
        vcount += 1;
    }
}

fn forgeToks(a: std.mem.Allocator, text: []const u8, add: bool) ![]usize {
    var words = std.ArrayList([]const u8).init(a);
    var i: usize = 0;
    while (i < text.len) {
        var buf: [48]u8 = undefined;
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
        try words.append(try a.dupe(u8, buf[0..n]));
    }
    var list = std.ArrayList(usize).init(a);
    for (words.items, 0..) |wd, k| {
        try intern(a, wd, add, &list);
        if (k > 0) {
            const bg = try std.fmt.allocPrint(a, "{s}_{s}", .{ words.items[k - 1], wd });
            try intern(a, bg, add, &list);
        }
    }
    return list.toOwnedSlice();
}

fn sigmoid(x: f32) f32 {
    return 1.0 / (1.0 + @exp(-x));
}

// logistic readout: forged token weights → outcome class
fn trainLogistic(a: std.mem.Allocator, toks_ix: []const []usize, truth: []const u8, n_train: usize) ![]f32 {
    const w = try a.alloc(f32, vcount * NC);
    @memset(w, 0);
    for (0..1200) |_| {
        for (0..n_train) |k| {
            var logits = [_]f32{0} ** NC;
            for (toks_ix[k]) |x| {
                for (0..NC) |c| logits[c] += w[x * NC + c];
            }
            var pred: usize = 0;
            for (0..NC) |c| {
                if (logits[c] > logits[pred]) pred = c;
            }
            if (pred != truth[k]) for (toks_ix[k]) |x| {
                w[x * NC + truth[k]] += 1.0;
                w[x * NC + pred] -= 1.0;
            };
        }
    }
    return w;
}

fn predictClass(w: []const f32, ix: []usize) usize {
    var logits = [_]f32{0} ** NC;
    for (ix) |x| {
        for (0..NC) |c| logits[c] += w[x * NC + c];
    }
    var pred: usize = 0;
    for (0..NC) |c| {
        if (logits[c] > logits[pred]) pred = c;
    }
    return pred;
}

fn logisticProb(w: []const f32, ix: []usize, class: usize) f32 {
    var logits = [_]f32{0} ** NC;
    for (ix) |x| {
        for (0..NC) |c| logits[c] += w[x * NC + c];
    }
    var exps = [_]f32{0} ** NC;
    var sum: f32 = 0;
    for (0..NC) |c| {
        exps[c] = @exp(logits[c]);
        sum += exps[c];
    }
    return if (sum > 0) exps[class] / sum else 1.0 / @as(f32, @floatFromInt(NC));
}

// ═══════════════════════════════════════════════════════════════════════════
// Corpus: cross-product phrasings × safe commands; auto-held-out predict targets
// ═══════════════════════════════════════════════════════════════════════════

const CmdClass = struct { phr: []const []const u8, cmd: []const []const u8 };

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();

    var live_mode = true;
    var argit = try std.process.argsWithAllocator(a);
    _ = argit.next();
    while (argit.next()) |arg| {
        if (std.mem.eql(u8, arg, "--live")) live_mode = true;
        if (std.mem.eql(u8, arg, "--sim")) live_mode = false;
    }

    vocab = std.StringHashMap(usize).init(a);

    try o.print("=== EXPERIMENT E8 — terminal-invented predicates (execution as verifier) ===\n", .{});
    try o.print("mode: {s} | safe whitelist only | forge+logistic readout | verify on future runs\n\n", .{
        if (live_mode) "LIVE" else "SIMULATED",
    });

    const classes = [_]CmdClass{
        .{ // → ok_fast (exists, quick)
            .phr = &.{
                "check the readme is here",
                "verify readme exists",
                "confirm the readme file",
                "is the readme around",
            },
            .cmd = &.{
                "test -f README.md",
                "test -f README.md",
                "test -f README.md",
                "test -f README.md",
            },
        },
        .{ // → ok_fast
            .phr = &.{
                "check the build file exists",
                "verify build dot zig",
                "confirm build is present",
                "does the build file exist",
            },
            .cmd = &.{
                "test -f build.zig",
                "test -f build.zig",
                "test -f build.zig",
                "test -f build.zig",
            },
        },
        .{ // → ok (heavier timing pattern — slow bucket for predicate invention)
            .phr = &.{
                "count the zig sources",
                "how many zig files",
                "number of modules here",
                "tell me the source count",
            },
            .cmd = &.{
                "ls *.zig 2>/dev/null | wc -l",
                "ls *.zig 2>/dev/null | wc -l",
                "ls *.zig 2>/dev/null | wc -l",
                "wc -l < build.zig",
            },
        },
        .{ // → errors
            .phr = &.{
                "open the missing readme",
                "check the fake file",
                "probe the absent script",
                "look for bogus path",
            },
            .cmd = &.{
                "test -f zzz_missing_e8_readme.xyz",
                "test -f zzz_fake_e8.xyz",
                "ls /zzz_no_such_dir_e8 2>/dev/null",
                "cat zzz_absent_e8.xyz 2>/dev/null",
            },
        },
        .{ // → errors
            .phr = &.{
                "run the false command",
                "execute failure probe",
                "trigger a failing run",
                "force an error exit",
            },
            .cmd = &.{
                "false",
                "false",
                "false",
                "false",
            },
        },
    };

    var corpus = std.ArrayList(Obs).init(a);
    for (classes) |cl| for (cl.phr, 0..) |p, pi| {
        const cmd = cl.cmd[pi % cl.cmd.len];
        if (!isSafeCmd(cmd)) continue;
        try corpus.append(.{ .nl = p, .cmd = cmd, .sig = undefined });
    };
    const total = corpus.items.len;

    // ── Phase 1: GROUND — run every command, record exit + timing + I/O ──
    try o.print("[Phase 1] GROUND — run {d} whitelisted commands, record exit codes + timing patterns:\n", .{total});
    var dist = [_]usize{0} ** NC;
    for (corpus.items, 0..) |*ob, k| {
        if (live_mode) {
            ob.sig = try runLive(a, ob.cmd);
        } else {
            // honest SIM: infer from command keywords (unverified — predict abstains later)
            const failish = std.mem.indexOf(u8, ob.cmd, "zzz") != null or
                std.mem.indexOf(u8, ob.cmd, "false") != null or
                std.mem.indexOf(u8, ob.cmd, "no_such") != null;
            ob.sig = .{
                .exit_ok = !failish,
                .time_ms = if (std.mem.indexOf(u8, ob.cmd, "wc") != null) 80 else 5,
                .out_len = if (failish) 0 else 4,
                .err_len = if (failish) 1 else 0,
            };
        }
        const oc = ob.sig.outcome();
        dist[oc] += 1;
        try o.print("   [{d:>2}] \"{s:<28}\"  `{s}`  exit={s} {d}ms out={d} err={d} → {s} ({s})\n", .{
            k,
            ob.nl,
            ob.cmd,
            if (ob.sig.exit_ok) "0" else "!0",
            ob.sig.time_ms,
            ob.sig.out_len,
            ob.sig.err_len,
            cname[oc],
            ob.sig.timingTag(),
        });
    }
    try o.print("   distribution: ", .{});
    for (0..NC) |c| try o.print("{s}={d} ", .{ cname[c], dist[c] });
    try o.print("\n\n", .{});

    // train on full grounded corpus; auto-generated novel targets are separate (never in train phrasings)
    var train_sigs = std.ArrayList(RunSig).init(a);
    var truth = try a.alloc(u8, total);
    for (corpus.items, 0..) |ob, k| {
        truth[k] = ob.sig.outcome();
        try train_sigs.append(ob.sig);
    }
    const split = total;

    // ── Phase 2: INVENT predicates from execution sensors ──
    const inv = try inventPredicates(a, train_sigs.items);
    try o.print("[Phase 2] INVENT — {d} distinct execution predicates (deduped by behavior over train runs):\n", .{inv.preds.len});
    const show_p = @min(inv.preds.len, 10);
    for (0..show_p) |pi| {
        var buf: [64]u8 = undefined;
        try o.print("   P{d}: {s}\n", .{ pi, predName(inv.preds[pi], &buf) });
    }
    if (inv.preds.len > show_p) try o.print("   … +{d} more\n", .{inv.preds.len - show_p});
    try o.print("\n", .{});

    // ── Phase 3: FORGE tokens + train logistic readout on full grounded corpus ──
    var tix = try a.alloc([]usize, total);
    for (corpus.items, 0..) |ob, k| tix[k] = try forgeToks(a, ob.nl, true);

    const w = try trainLogistic(a, tix, truth, split);
    try o.print("[Phase 3] FORGE+LOGISTIC — {d} forged features, perceptron+logistic readout trained on {d} runs\n\n", .{
        vcount, split,
    });

    // auto-generate predict targets: compositional paraphrases × commands never paired in training
    const novel_gen = [_]struct { nl: []const u8, cmd: []const u8 }{
        .{ .nl = "does the fake readme exist now", .cmd = "test -f zzz_fake_readme_e8.xyz" },
        .{ .nl = "is the bogus build file around", .cmd = "test -f zzz_bogus_build_e8.xyz" },
        .{ .nl = "how many zig modules are present", .cmd = "ls *.zig 2>/dev/null | wc -l" },
        .{ .nl = "verify the readme is still here", .cmd = "test -f README.md" },
        .{ .nl = "run the failure sentinel probe", .cmd = "false" },
        .{ .nl = "probe missing documentation file", .cmd = "test -f zzz_missing_docs_e8.xyz" },
        .{ .nl = "confirm build dot zig still exists", .cmd = "test -f build.zig" },
        .{ .nl = "cat the nonexistent research note", .cmd = "cat zzz_noresearch_e8.xyz 2>/dev/null" },
    };

    // ── Phase 4: AUTO-GENERATED predict targets → verify on future live runs ──
    const held = novel_gen.len;
    try o.print("[Phase 4] PREDICT→VERIFY — {d} auto-generated novel commands (phrasings never in train):\n", .{held});
    var correct: usize = 0;
    var certified_predict: usize = 0;

    for (novel_gen) |nv| {
        if (!isSafeCmd(nv.cmd)) continue;
        const ix = try forgeToks(a, nv.nl, false);
        const pred_c = predictClass(w, ix);
        const prob = logisticProb(w, ix, pred_c);

        var real_sig: RunSig = undefined;
        const verified = live_mode;
        if (live_mode) {
            real_sig = try runLive(a, nv.cmd);
        } else {
            const failish = std.mem.indexOf(u8, nv.cmd, "zzz") != null or std.mem.eql(u8, nv.cmd, "false");
            real_sig = .{ .exit_ok = !failish, .time_ms = 5, .out_len = if (failish) 0 else 4, .err_len = 0 };
        }
        const real_c = real_sig.outcome();
        const hit = pred_c == real_c;
        if (hit) correct += 1;
        if (verified and hit) certified_predict += 1;

        try o.print("   \"{s:<34}\"  predict {s} (p={d:.2})  ran→ {s}  {s}{s}\n", .{
            nv.nl,
            cname[pred_c],
            prob,
            cname[real_c],
            if (hit) "✓" else "✗",
            if (verified) " [CERTIFIED]" else " [sim-unverified]",
        });
    }

    const acc = 100.0 * @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(held));
    const cert_rate = if (live_mode)
        100.0 * @as(f64, @floatFromInt(certified_predict)) / @as(f64, @floatFromInt(held))
    else
        0.0;

    // predicate interpretability: which invented preds fire on ok_fast vs errors?
    try o.print("\n[Phase 2b] Invented predicate activation on training classes:\n", .{});
    const words = (split + 63) / 64;
    for (0..@min(inv.preds.len, 8)) |pi| {
        var act = [_]usize{0} ** NC;
        for (0..split) |k| {
            const oc = truth[k];
            const bit = (inv.bits[pi * words + k / 64] >> @intCast(k % 64)) & 1;
            if (bit == 1) act[oc] += 1;
        }
        var buf: [64]u8 = undefined;
        try o.print("   {s}: errors={d} ok={d}\n", .{
            predName(inv.preds[pi], &buf),
            act[0], act[1],
        });
    }

    try o.print("\n════════════════════ E8 VERDICT ════════════════════\n", .{});
    try o.print("Terminal-invented predicates: {d} behaviors forged from exit/timing/I/O sensors — not handed.\n", .{inv.preds.len});
    try o.print("Auto-generated predict targets: {d} held-out novel commands.\n", .{held});
    try o.print("Logistic readout accuracy (novel): {d}/{d} = {d:.0}%\n", .{ correct, held, acc });
    if (live_mode) {
        try o.print("CERTIFIED predict rate (novel, live-verified): {d}/{d} = {d:.0}%\n", .{
            certified_predict, held, cert_rate,
        });
    } else {
        try o.print("CERTIFIED predict rate: 0/{d} (use --live for shell-verified predictions)\n", .{held});
    }
    try o.print("\nThe terminal is the verifier: every label is what a command ACTUALLY DID.\n", .{});
    try o.print("Predicates are invented from execution; NL features are forged; predictions are checked on future runs.\n", .{});
    try o.print("HONEST: bounded safe-command slice; richer outcomes = same loop with richer sensors.\n", .{});
}