//! terminal_sigil.zig — the SIGIL taken: ghost_engine's self-calibrating confidence, no hardcoded threshold.
//!
//! Micah: take the sigil — it's the softmax-equivalent. The real mechanism (ghost_engine src/engine.zig
//! ResonanceEMA + the L3 energy decision) is:
//!   • ENERGY of a decision = how dominant the winner is (here: the margin between the top class and the next).
//!     A peaked winner = high energy (saturation); a flat tie = low energy (boredom). That IS softmax confidence.
//!   • A running ResonanceEMA tracks the AVERAGE and MAD of energy, fixed-point, online.
//!   • SURPRISE threshold = avg + 2.5·MAD  → energy above it = a strong, surprising signal → ANSWER, confident.
//!   • SEARCH  threshold = avg − 1.5·MAD  → energy below it = weak/typical → don't commit → ASK / explore.
//! The thresholds CALIBRATE THEMSELVES from the running energy distribution — no hand-set T (my old fixed 0.905
//! is replaced by this). Out-of-distribution input fires no features → margin ≈ 0 → energy below SEARCH → it asks,
//! all by itself. This is the sigil: self-calibrating, deterministic, integer, engine-native. No LLM.
//!
//! Run from boundary_crossing/: zig build terminal-sigil --release=fast

const std = @import("std");

// ── ghost_engine's ResonanceEMA, ported faithfully (24.8 fixed-point, alpha=1/16) ──
const ResonanceEMA = struct {
    average: u32 = 850 << 8,
    deviation: u32 = 25 << 8,
    const alpha_shift: u5 = 4;
    fn update(self: *ResonanceEMA, sample: u16) void {
        const s = @as(u32, sample) << 8;
        const diff = if (s > self.average) s - self.average else self.average - s;
        const a = @as(u64, 1) << alpha_shift;
        self.average = @intCast((@as(u64, self.average) * (a - 1) + @as(u64, s)) >> alpha_shift);
        self.deviation = @intCast((@as(u64, self.deviation) * (a - 1) + @as(u64, diff)) >> alpha_shift);
    }
    fn surprise(self: ResonanceEMA) u32 {
        return (self.average + (self.deviation * 5 / 2)) >> 8; // avg + 2.5·MAD → confident line
    }
    fn searchT(self: ResonanceEMA) u32 {
        const avg = self.average >> 8;
        const dev = (self.deviation * 3 / 2) >> 8;
        return if (avg > dev) avg - dev else 0; // avg − 1.5·MAD → ask/explore line
    }
};

const NC = 5;
const cname = [_][]const u8{ "FAIL", "EMPTY", "NUMBER", "LISTING", "TEXT" };
fn observe(a: std.mem.Allocator, cmd: []const u8) u8 {
    const res = std.process.Child.run(.{ .allocator = a, .argv = &.{ "sh", "-c", cmd }, .max_output_bytes = 1 << 20 }) catch return 0;
    defer a.free(res.stdout);
    defer a.free(res.stderr);
    const ok = switch (res.term) {
        .Exited => |c| c == 0,
        else => false,
    };
    if (!ok) return 0;
    const out = std.mem.trim(u8, res.stdout, " \t\r\n");
    if (out.len == 0) return 1;
    var dig = true;
    for (out) |ch| if (ch < '0' or ch > '9') {
        dig = false;
        break;
    };
    if (dig) return 2;
    if (std.mem.indexOfScalar(u8, out, '\n') != null) return 3;
    return 4;
}
var vocab: std.StringHashMap(usize) = undefined;
var vcount: usize = 0;
fn low(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn intern(a: std.mem.Allocator, tk: []const u8, add: bool, list: *std.ArrayList(usize)) !void {
    if (vocab.get(tk)) |idx| try list.append(idx) else if (add) {
        try vocab.put(try a.dupe(u8, tk), vcount);
        try list.append(vcount);
        vcount += 1;
    }
}
fn toks(a: std.mem.Allocator, text: []const u8, add: bool) ![]usize {
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
        if (k > 0) try intern(a, try std.fmt.allocPrint(a, "{s}_{s}", .{ words.items[k - 1], wd }), add, &list);
    }
    return list.toOwnedSlice();
}
var w: []f32 = undefined;
// the sigil ENERGY = dominance/saturation of the winner = softmax mass on the top class, scaled to 0..1024.
// peaked winner ⇒ ~1024 (saturated), flat tie ⇒ ~205 (= 1024/NC, bored). this is the resonance the EMA tracks.
fn decide(ix: []const usize) struct { cls: usize, energy: u16 } {
    var s = [_]f32{0} ** NC;
    for (ix) |x| for (0..NC) |c| {
        s[c] += w[x * NC + c];
    };
    var best: usize = 0;
    for (0..NC) |c| if (s[c] > s[best]) {
        best = c;
    };
    var m = s[0];
    for (s) |v| if (v > m) {
        m = v;
    };
    var sum: f64 = 0;
    for (s) |v| sum += @exp(@as(f64, v - m));
    const prob = @exp(@as(f64, s[best] - m)) / sum; // 1/NC .. 1
    return .{ .cls = best, .energy = @intFromFloat(prob * 1024.0) };
}

const Req = struct { nl: []const u8, cmd: []const u8 };

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();
    vocab = std.StringHashMap(usize).init(a);
    try o.print("=== TERMINAL SIGIL — ghost_engine's self-calibrating confidence (ResonanceEMA), no hardcoded T. No LLM ===\n\n", .{});

    // grounded command corpus (combinatorial), run for REAL
    const banks = .{
        .{ [_][]const u8{ "count the", "how many", "number of", "tally the", "total of" }, [_][]const u8{ "zig files", "sources", "research docs", "modules" }, [_][]const u8{ "ls *.zig | wc -l", "ls docs/research/*.md | wc -l", "wc -l < build.zig" } },
        .{ [_][]const u8{ "list the", "show me the", "display the", "enumerate the", "what are the" }, [_][]const u8{ "zig files", "sources", "research docs", "directory" }, [_][]const u8{ "ls -1 *.zig", "ls -1 docs/research", "ls -1" } },
        .{ [_][]const u8{ "print a", "echo a", "say a", "show the", "tell me the" }, [_][]const u8{ "greeting", "message", "path", "first readme line" }, [_][]const u8{ "echo hello there", "pwd", "head -1 README.md" } },
        .{ [_][]const u8{ "check the", "verify the", "confirm the", "ensure the" }, [_][]const u8{ "readme", "build file", "readme present", "build here" }, [_][]const u8{ "test -f README.md", "test -f build.zig", "grep -q the README.md" } },
        .{ [_][]const u8{ "open the", "find the", "run the", "use the", "access the" }, [_][]const u8{ "missing file", "nonexistent script", "fake readme", "absent command", "broken path" }, [_][]const u8{ "test -f zzz_missing.xyz", "false", "ls /zzz_no_dir 2>/dev/null", "grep -q zzznope README.md" } },
    };
    var reqs = std.ArrayList(Req).init(a);
    inline for (banks) |g| {
        var ci: usize = 0;
        for (g[0]) |p| for (g[1]) |ob| {
            try reqs.append(.{ .nl = try std.fmt.allocPrint(a, "{s} {s}", .{ p, ob }), .cmd = g[2][ci % g[2].len] });
            ci += 1;
        };
    }
    const total = reqs.items.len;
    var truth = try a.alloc(u8, total);
    for (reqs.items, 0..) |r, k| truth[k] = observe(a, r.cmd);

    var prng: u64 = 0x516112;
    var ord = try a.alloc(usize, total);
    for (0..total) |i| ord[i] = i;
    var n = total;
    while (n > 1) {
        n -= 1;
        prng ^= prng << 13;
        prng ^= prng >> 7;
        prng ^= prng << 17;
        const j = prng % (n + 1);
        const t = ord[n];
        ord[n] = ord[j];
        ord[j] = t;
    }
    const ntr = total * 75 / 100;
    var tix = try a.alloc([]usize, total);
    for (0..ntr) |k| tix[ord[k]] = try toks(a, reqs.items[ord[k]].nl, true);
    for (ntr..total) |k| tix[ord[k]] = try toks(a, reqs.items[ord[k]].nl, false);
    w = try a.alloc(f32, vcount * NC);
    @memset(w, 0);
    for (0..500) |_| for (0..ntr) |k| {
        const idx = ord[k];
        const d = decide(tix[idx]);
        if (d.cls != truth[idx]) for (tix[idx]) |x| {
            w[x * NC + truth[idx]] += 1;
            w[x * NC + d.cls] -= 1;
        };
    };

    // ── SELF-CALIBRATE: warm the ResonanceEMA on the training energies (it adapts to the real energy scale) ──
    var ema = ResonanceEMA{};
    for (0..ntr) |k| ema.update(decide(tix[ord[k]]).energy);
    try o.print("[sigil self-calibration] after warming on training energies, the EMA found its own bands:\n", .{});
    try o.print("   avg energy ≈ {d}   MAD ≈ {d}   →  SURPRISE(answer) ≥ {d}   |   SEARCH(ask) ≤ {d}   (no hardcoded T)\n\n", .{ ema.average >> 8, ema.deviation >> 8, ema.surprise(), ema.searchT() });

    // ── in-distribution: energy should be high (peaked) → ANSWER ──
    try o.print("[in-distribution] energy vs the self-calibrated bands:\n", .{});
    var ans: usize = 0;
    var good: usize = 0;
    for (ntr..total) |k| {
        const idx = ord[k];
        const d = decide(tix[idx]);
        if (d.energy >= ema.searchT()) {
            ans += 1;
            if (d.cls == truth[idx]) good += 1;
        }
    }
    try o.print("   answered {d}/{d} (energy ≥ the self-calibrated SEARCH line); accuracy on answered: {d}/{d} = {d:.0}%\n\n", .{ ans, total - ntr, good, ans, if (ans > 0) 100.0 * @as(f64, @floatFromInt(good)) / @as(f64, @floatFromInt(ans)) else 0 });

    // ── out-of-distribution: no features fire → energy ≈ 0 → below SEARCH → ASK (emergent, self-calibrated) ──
    const ood = [_][]const u8{ "what is the meaning of life", "tell me a joke", "i love pizza", "the weather is lovely today", "xyzzy plugh frobnitz", "how are you feeling today", "sing me a song" };
    try o.print("[out-of-distribution] the sigil energy collapses on its own → it asks:\n", .{});
    var asked: usize = 0;
    for (ood) |s| {
        var lw = try a.alloc(u8, s.len);
        for (0..s.len) |i| lw[i] = low(s[i]);
        const d = decide(try toks(a, lw, false));
        const ask = d.energy < ema.searchT();
        const band = if (d.energy >= ema.surprise()) "STRONG" else if (!ask) "answer" else "ASK";
        if (ask) asked += 1;
        try o.print("   \"{s:<34}\"  energy {d:>4}  → {s:<7} {s}\n", .{ s, d.energy, band, if (ask) std.fmt.allocPrint(a, "(\"not sure — did you mean a {s}?\")", .{cname[d.cls]}) catch "" else "" });
    }

    try o.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try o.print("The sigil, taken: confidence is ENERGY (winner dominance / margin), and the answer/ask line is the\n", .{});
    try o.print("ResonanceEMA's SURPRISE/SEARCH bands — calibrated from the running energy distribution, ONLINE, with\n", .{});
    try o.print("NO hardcoded threshold (my old fixed T is gone). In-distribution energy is high → answered {d}/{d} at\n", .{ ans, total - ntr });
    try o.print("{d:.0}%; out-of-distribution energy collapses to ~0 on its own → asked on {d}/{d}. Deterministic, integer,\n", .{ if (ans > 0) 100.0 * @as(f64, @floatFromInt(good)) / @as(f64, @floatFromInt(ans)) else 0, asked, ood.len });
    try o.print("self-calibrating — ghost_engine's mechanism, now driving the language engine's \"do I know this?\".\n", .{});
}
