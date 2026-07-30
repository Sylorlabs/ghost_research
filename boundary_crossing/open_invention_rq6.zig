//! open_invention_rq6.zig — RESEARCH Q6: E8 scale — 200-command terminal grind + 50 held-out phrasings.
//!
//! Scales E8 (terminal-invented predicates, forge+logistic readout, live verify) to terminal_grind_big
//! corpus size. Expands the safe whitelist; grounds 200 training commands; trains perceptron+logistic
//! with uniform vs surprise-weighted updates; measures certified predict rate on 50 novel phrasings.
//!
//! Pass bar: ≥80% certified predict (live shell). RQ6 predicts outcome class; E18 (open_invention_e18.zig)
//! extends the same grind to NL→command synthesis with ≥60% certified argv match on 100 held-out phrasings.
//!
//! References: open_invention_e8.zig, open_invention_e18.zig, terminal_grind_big.zig
//!
//! Run: zig build open-invention-rq6 --release=fast
//!      zig build open-invention-rq6 --release=fast -- --sim

const std = @import("std");

const NC = 5;
const cname = [_][]const u8{ "FAIL", "EMPTY", "NUMBER", "LISTING", "TEXT" };
const TRAIN_TARGET: usize = 200;
const HELD_TARGET: usize = 50;
const FAST_MS: u32 = 50;
const EPOCHS: usize = 900;

// ── expanded safe whitelist: read-only probes only (no writes, network, or user input) ──
const SAFE_PREFIXES = [_][]const u8{
    "test",  "ls",     "echo",  "false", "true",  "pwd",    "wc",      "head",   "grep",
    "cat",   "find",   "date",  "whoami", "sort",  "uniq",   "tr",      "cut",    "dirname",
    "basename", "readlink", "stat", "expr", "seq", "printf", "id", "uname",
};

fn isSafeCmd(cmd: []const u8) bool {
    for (SAFE_PREFIXES) |pfx| {
        if (std.mem.startsWith(u8, cmd, pfx)) return true;
    }
    return false;
}

const RunSig = struct {
    exit_ok: bool,
    time_ms: u32,
    out_len: u32,
    err_len: u32,
    outcome: u8,

    fn timingTag(self: RunSig) []const u8 {
        if (!self.exit_ok) return "fail";
        return if (self.time_ms < FAST_MS) "fast" else "slow";
    }
};

const Obs = struct { nl: []const u8, cmd: []const u8, sig: RunSig };

fn classifyOutput(out: []const u8) u8 {
    const trimmed = std.mem.trim(u8, out, " \t\r\n");
    if (trimmed.len == 0) return 1; // EMPTY
    var alldig = true;
    for (trimmed) |ch| if (ch < '0' or ch > '9') {
        alldig = false;
        break;
    };
    if (alldig) return 2; // NUMBER
    if (std.mem.indexOfScalar(u8, trimmed, '\n') != null) return 3; // LISTING
    return 4; // TEXT
}

fn runLive(a: std.mem.Allocator, cmd: []const u8) !RunSig {
    const t0 = std.time.nanoTimestamp();
    const res = std.process.Child.run(.{
        .allocator = a,
        .argv = &.{ "sh", "-c", cmd },
        .max_output_bytes = 1 << 20,
    }) catch {
        const t1 = std.time.nanoTimestamp();
        return .{
            .exit_ok = false,
            .time_ms = @intCast(@max(0, @divTrunc(t1 - t0, std.time.ns_per_ms))),
            .out_len = 0,
            .err_len = 0,
            .outcome = 0,
        };
    };
    defer a.free(res.stdout);
    defer a.free(res.stderr);
    const t1 = std.time.nanoTimestamp();
    const ok = switch (res.term) {
        .Exited => |c| c == 0,
        else => false,
    };
    const oc: u8 = if (!ok) 0 else classifyOutput(res.stdout);
    return .{
        .exit_ok = ok,
        .time_ms = @intCast(@max(0, @divTrunc(t1 - t0, std.time.ns_per_ms))),
        .out_len = @intCast(res.stdout.len),
        .err_len = @intCast(res.stderr.len),
        .outcome = oc,
    };
}

fn simSig(cmd: []const u8) RunSig {
    const failish = std.mem.indexOf(u8, cmd, "zzz") != null or
        std.mem.indexOf(u8, cmd, "no_dir") != null or
        std.mem.eql(u8, cmd, "false") or
        std.mem.indexOf(u8, cmd, "bogus") != null;
    if (failish) return .{ .exit_ok = false, .time_ms = 3, .out_len = 0, .err_len = 1, .outcome = 0 };
    if (std.mem.indexOf(u8, cmd, "wc -l") != null or std.mem.indexOf(u8, cmd, "| wc -l") != null)
        return .{ .exit_ok = true, .time_ms = 80, .out_len = 2, .err_len = 0, .outcome = 2 };
    if (std.mem.startsWith(u8, cmd, "ls -1") or std.mem.startsWith(u8, cmd, "ls *.zig"))
        return .{ .exit_ok = true, .time_ms = 40, .out_len = 64, .err_len = 0, .outcome = 3 };
    if (std.mem.startsWith(u8, cmd, "test -f") or std.mem.startsWith(u8, cmd, "grep -q"))
        return .{ .exit_ok = true, .time_ms = 5, .out_len = 0, .err_len = 0, .outcome = 1 };
    if (std.mem.startsWith(u8, cmd, "echo") or std.mem.eql(u8, cmd, "pwd") or std.mem.startsWith(u8, cmd, "head"))
        return .{ .exit_ok = true, .time_ms = 5, .out_len = 12, .err_len = 0, .outcome = 4 };
    if (std.mem.startsWith(u8, cmd, "stat") or std.mem.startsWith(u8, cmd, "readlink"))
        return .{ .exit_ok = true, .time_ms = 8, .out_len = 24, .err_len = 0, .outcome = 4 };
    return .{ .exit_ok = true, .time_ms = 6, .out_len = 4, .err_len = 0, .outcome = 4 };
}

// ═══════════════════════════════════════════════════════════════════════════
// Primitive execution sensors + invented predicates (E8 pattern)
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

const Pred = struct { a: Atom, b: ?Atom = null, neg: bool = false };

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
        var buf = [_]u64{0} ** 64;
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
// Forge NL tokens → compound features (terminal_grind / E8 bigram pattern)
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

fn logitsFrom(w: []const f32, ix: []usize) [NC]f32 {
    var logits = [_]f32{0} ** NC;
    for (ix) |x| {
        for (0..NC) |c| logits[c] += w[x * NC + c];
    }
    return logits;
}

fn argmaxLogits(logits: [NC]f32) usize {
    var pred: usize = 0;
    for (0..NC) |c| {
        if (logits[c] > logits[pred]) pred = c;
    }
    return pred;
}

fn softmaxProb(logits: [NC]f32, class: usize) f32 {
    var exps = [_]f32{0} ** NC;
    var sum: f32 = 0;
    for (0..NC) |c| {
        exps[c] = @exp(logits[c]);
        sum += exps[c];
    }
    return if (sum > 0) exps[class] / sum else 1.0 / @as(f32, @floatFromInt(NC));
}

const SigilEMA = struct {
    avg: f64 = 0,
    dev: f64 = 1,
    n: u32 = 0,

    fn update(self: *SigilEMA, score: f32) void {
        const s = @as(f64, score);
        self.n += 1;
        const alpha: f64 = if (self.n < 8) 0.35 else 0.12;
        const delta = s - self.avg;
        self.avg += alpha * delta;
        self.dev = (1.0 - alpha) * self.dev + alpha * @abs(delta);
        if (self.dev < 1e-4) self.dev = 1e-4;
    }
};

fn surpriseWeight(sig: *SigilEMA, logits: [NC]f32, truth: u8, pred: usize) f32 {
    const true_logit = logits[truth];
    sig.update(true_logit);
    const z = (sig.avg - @as(f64, true_logit)) / (sig.dev + 1e-6);
    var w: f32 = @floatCast(@max(0.4, @min(3.5, 1.0 + 0.75 * z)));
    if (pred != truth) {
        const p_true = softmaxProb(logits, truth);
        w *= 1.0 + 1.5 * (1.0 - p_true); // RLVR: violations on low-margin examples learn hardest
        w = @min(w, 4.0);
    }
    return w;
}

fn trainPerceptron(
    w: []f32,
    toks_ix: []const []usize,
    truth: []const u8,
    n_train: usize,
    surprise_mode: bool,
) void {
    var sig = SigilEMA{};
    for (0..EPOCHS) |_| {
        for (0..n_train) |k| {
            const logits = logitsFrom(w, toks_ix[k]);
            const pred = argmaxLogits(logits);
            if (pred == truth[k]) continue;
            const weight: f32 = if (surprise_mode)
                surpriseWeight(&sig, logits, truth[k], pred)
            else
                1.0;
            for (toks_ix[k]) |x| {
                w[x * NC + truth[k]] += weight;
                w[x * NC + pred] -= weight;
            }
        }
    }
}

fn predictClass(w: []const f32, ix: []usize) usize {
    return argmaxLogits(logitsFrom(w, ix));
}

fn logisticProb(w: []const f32, ix: []usize, class: usize) f32 {
    return softmaxProb(logitsFrom(w, ix), class);
}

// ═══════════════════════════════════════════════════════════════════════════
// Corpus banks — 200 train + 50 held-out novel phrasings (combinatorial grind)
// ═══════════════════════════════════════════════════════════════════════════

const Bank = struct { pre: []const []const u8, obj: []const []const u8, cmd: []const []const u8 };

fn appendCross(
    a: std.mem.Allocator,
    list: *std.ArrayList(Obs),
    pre: []const []const u8,
    obj: []const []const u8,
    cmd: []const []const u8,
    cap: usize,
) !void {
    var ci: usize = 0;
    outer: for (pre) |p| for (obj) |ob| {
        if (list.items.len >= cap) break :outer;
        const nl = try std.fmt.allocPrint(a, "{s} {s}", .{ p, ob });
        const c = cmd[ci % cmd.len];
        ci += 1;
        if (!isSafeCmd(c)) continue;
        try list.append(.{ .nl = nl, .cmd = c, .sig = undefined });
    };
}

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

    try o.print("=== RESEARCH Q6 — E8 scale: 200-command grind + 50 held-out phrasings ===\n", .{});
    try o.print("mode: {s} | expanded safe whitelist | forge+logistic | uniform vs surprise-weighted\n\n", .{
        if (live_mode) "LIVE" else "SIMULATED",
    });

    // Training banks (target 200): FAIL 40 + EMPTY 30 + NUMBER 35 + LISTING 35 + TEXT 36 + META 24
    const fail_pre = [_][]const u8{ "open the", "find the", "run the", "look for the", "use the", "access the", "load the", "probe the" };
    const fail_obj = [_][]const u8{ "missing file", "nonexistent script", "fake readme", "absent command", "broken path" };
    const fail_cmd = [_][]const u8{
        "test -f zzz_missing_rq6.xyz",
        "false",
        "ls /zzz_no_dir_rq6 2>/dev/null",
        "grep -q zzznotfound_rq6 README.md",
        "cat zzz_absent_rq6.xyz 2>/dev/null",
    };

    const empty_pre = [_][]const u8{ "check the", "verify the", "confirm the", "make sure the", "ensure the", "is there a" };
    const empty_obj = [_][]const u8{ "readme", "build file", "readme is present", "build is here", "readme around" };
    const empty_cmd = [_][]const u8{ "test -f README.md", "test -f build.zig", "grep -q the README.md" };

    const num_bank = Bank{
        .pre = &.{ "count the", "how many", "number of", "tally the", "give me the count of", "whats the total of", "report the number of" },
        .obj = &.{ "zig files", "sources", "research docs", "modules", "source files" },
        .cmd = &.{ "ls *.zig | wc -l", "ls docs/research/*.md | wc -l", "wc -l < build.zig" },
    };
    const list_bank = Bank{
        .pre = &.{ "list the", "show me the", "display the", "whats in the", "give me the", "enumerate the", "what are the" },
        .obj = &.{ "zig files", "sources", "research docs", "directory", "files here" },
        .cmd = &.{ "ls -1 *.zig", "ls -1 docs/research", "ls -1" },
    };
    const text_bank = Bank{
        .pre = &.{ "print a", "echo a", "say a", "show the", "tell me the", "what is the" },
        .obj = &.{ "greeting", "message", "path", "working directory", "first readme line", "hello" },
        .cmd = &.{ "echo hello there", "pwd", "head -1 README.md" },
    };
    const meta_bank = Bank{
        .pre = &.{ "inspect the", "read the", "fetch the", "show me the", "report the", "describe the" },
        .obj = &.{ "readme size", "build metadata", "readme link", "file status" },
        .cmd = &.{ "stat -c %s README.md", "stat -c %s build.zig", "readlink -f README.md", "stat README.md" },
    };

    var train = std.ArrayList(Obs).init(a);
    try appendCross(a, &train, &fail_pre, &fail_obj, &fail_cmd, TRAIN_TARGET);
    try appendCross(a, &train, &empty_pre, &empty_obj, &empty_cmd, TRAIN_TARGET);
    try appendCross(a, &train, num_bank.pre, num_bank.obj, num_bank.cmd, TRAIN_TARGET);
    try appendCross(a, &train, list_bank.pre, list_bank.obj, list_bank.cmd, TRAIN_TARGET);
    try appendCross(a, &train, text_bank.pre, text_bank.obj, text_bank.cmd, TRAIN_TARGET);
    try appendCross(a, &train, meta_bank.pre, meta_bank.obj, meta_bank.cmd, TRAIN_TARGET);

    // Held-out banks: novel phrasing vocabulary never used in training (50 targets)
    const held_fail_pre = [_][]const u8{ "attempt the", "reach for the", "hunt the", "seek the", "fetch the", "grab the", "pull the", "touch the", "strike the", "invoke the" };
    const held_fail_obj = [_][]const u8{ "phantom readme", "ghost script", "vanished target", "decoy artifact", "fictive module" };
    const held_fail_cmd = [_][]const u8{
        "test -f zzz_phantom_rq6.xyz",
        "false",
        "cat zzz_ghost_rq6.xyz 2>/dev/null",
        "grep -q zzz_phantom_rq6 README.md",
        "ls /zzz_phantom_dir_rq6 2>/dev/null",
    };

    const held_empty_pre = [_][]const u8{ "validate the", "assert the", "doublecheck the", "crosscheck the", "reconfirm the", "ascertain the", "establish the", "determine the", "establish whether the", "ascertain whether the" };
    const held_empty_obj = [_][]const u8{ "readme remains", "build remains", "readme still exists", "build still exists", "readme is intact" };
    const held_empty_cmd = [_][]const u8{ "test -f README.md", "test -f build.zig", "grep -q README README.md" };

    const held_num_pre = [_][]const u8{ "quantify the", "reckon the", "measure the", "compute the", "derive the", "obtain the", "summarize the", "calculate the", "determine the", "assess the" };
    const held_num_obj = [_][]const u8{ "zig modules", "markdown notes", "source tally", "doc tally", "module tally" };
    const held_num_cmd = [_][]const u8{ "ls *.zig | wc -l", "ls docs/research/*.md | wc -l", "wc -l < build.zig" };

    const held_list_pre = [_][]const u8{ "catalog the", "inventory the", "outline the", "survey the", "scan the", "browse the", "peruse the", "review the", "compile the", "index the" };
    const held_list_obj = [_][]const u8{ "zig modules", "research notes", "local files", "project files", "tree contents" };
    const held_list_cmd = [_][]const u8{ "ls -1 *.zig", "ls -1 docs/research", "ls -1" };

    const held_text_pre = [_][]const u8{ "utter a", "voice a", "broadcast a", "announce a", "recite a", "state a", "declare a", "present a", "offer a", "relay a" };
    const held_text_obj = [_][]const u8{ "salutation", "banner line", "cwd string", "readme opener", "hello phrase", "path string" };
    const held_text_cmd = [_][]const u8{ "echo hello there", "pwd", "head -1 README.md", "printf cwd:%s\\n $(pwd)" };

    var held = std.ArrayList(Obs).init(a);
    try appendCross(a, &held, &held_fail_pre, &held_fail_obj, &held_fail_cmd, HELD_TARGET);
    try appendCross(a, &held, &held_empty_pre, &held_empty_obj, &held_empty_cmd, HELD_TARGET);
    try appendCross(a, &held, &held_num_pre, &held_num_obj, &held_num_cmd, HELD_TARGET);
    try appendCross(a, &held, &held_list_pre, &held_list_obj, &held_list_cmd, HELD_TARGET);
    try appendCross(a, &held, &held_text_pre, &held_text_obj, &held_text_cmd, HELD_TARGET);

    const n_train = train.items.len;
    const n_held = held.items.len;

    try o.print("corpus: {d} training + {d} held-out novel phrasings (whitelist-checked)\n\n", .{ n_train, n_held });

    // ── Phase 1: GROUND — run every training command ──
    try o.print("[Phase 1] GROUND — {d} whitelisted training commands:\n", .{n_train});
    var dist = [_]usize{0} ** NC;
    for (train.items, 0..) |*ob, k| {
        ob.sig = if (live_mode) try runLive(a, ob.cmd) else simSig(ob.cmd);
        dist[ob.sig.outcome] += 1;
        if (k < 12 or k >= n_train - 3) {
            try o.print("   [{d:>3}] \"{s:<36}\" → {s}\n", .{ k, ob.nl, cname[ob.sig.outcome] });
        } else if (k == 12) {
            try o.print("   … ({d} more training runs)\n", .{n_train - 15});
        }
    }
    try o.print("   distribution: ", .{});
    for (0..NC) |c| try o.print("{s}={d} ", .{ cname[c], dist[c] });
    try o.print("\n\n", .{});

    var train_sigs = std.ArrayList(RunSig).init(a);
    var truth = try a.alloc(u8, n_train);
    for (train.items, 0..) |ob, k| {
        truth[k] = ob.sig.outcome;
        try train_sigs.append(ob.sig);
    }

    // ── Phase 2: INVENT predicates from execution sensors ──
    const inv = try inventPredicates(a, train_sigs.items);
    try o.print("[Phase 2] INVENT — {d} distinct execution predicates over {d} training runs\n\n", .{
        inv.preds.len, n_train,
    });

    // ── Phase 3: FORGE + train uniform vs surprise-weighted perceptron+logistic ──
    var tix = try a.alloc([]usize, n_train);
    for (train.items, 0..) |ob, k| tix[k] = try forgeToks(a, ob.nl, true);

    const w_uniform = try a.alloc(f32, vcount * NC);
    const w_surprise = try a.alloc(f32, vcount * NC);
    @memset(w_uniform, 0);
    @memset(w_surprise, 0);
    trainPerceptron(w_uniform, tix, truth, n_train, false);
    trainPerceptron(w_surprise, tix, truth, n_train, true);

    try o.print("[Phase 3] FORGE+LOGISTIC — {d} forged features | uniform vs surprise-weighted ({d} epochs)\n\n", .{
        vcount, EPOCHS,
    });

    // ── Phase 4: PREDICT→VERIFY on 50 held-out novel phrasings ──
    try o.print("[Phase 4] PREDICT→VERIFY — {d} held-out novel phrasings (never in train vocabulary banks):\n", .{n_held});

    const evalHeld = struct {
        fn f(
            label: []const u8,
            w: []const f32,
            live: bool,
            alloc: std.mem.Allocator,
            writer: anytype,
            items: []Obs,
        ) !struct { correct: usize, certified: usize, total: usize } {
            var correct: usize = 0;
            var certified: usize = 0;
            var shown: usize = 0;
            for (items) |*nv| {
                const ix = try forgeToks(alloc, nv.nl, false);
                const pred_c = predictClass(w, ix);
                const prob = logisticProb(w, ix, pred_c);
                nv.sig = if (live) try runLive(alloc, nv.cmd) else simSig(nv.cmd);
                const real_c = nv.sig.outcome;
                const hit = pred_c == real_c;
                if (hit) correct += 1;
                if (live and hit) certified += 1;
                if (shown < 8 or shown >= items.len - 2) {
                    try writer.print("   [{s}] \"{s:<34}\" predict {s} (p={d:.2}) ran→ {s} {s}{s}\n", .{
                        label,
                        nv.nl,
                        cname[pred_c],
                        prob,
                        cname[real_c],
                        if (hit) "✓" else "✗",
                        if (live and hit) " [CERTIFIED]" else if (live) "" else " [sim]",
                    });
                } else if (shown == 8) {
                    try writer.print("   … ({d} more held-out predictions)\n", .{items.len - 10});
                }
                shown += 1;
            }
            return .{ .correct = correct, .certified = certified, .total = items.len };
        }
    }.f;

    const uni = try evalHeld("uniform", w_uniform, live_mode, a, o, held.items);
    const sur = try evalHeld("surprise", w_surprise, live_mode, a, o, held.items);

    const uni_acc = 100.0 * @as(f64, @floatFromInt(uni.correct)) / @as(f64, @floatFromInt(uni.total));
    const sur_acc = 100.0 * @as(f64, @floatFromInt(sur.correct)) / @as(f64, @floatFromInt(sur.total));
    const uni_cert = if (live_mode)
        100.0 * @as(f64, @floatFromInt(uni.certified)) / @as(f64, @floatFromInt(uni.total))
    else
        0.0;
    const sur_cert = if (live_mode)
        100.0 * @as(f64, @floatFromInt(sur.certified)) / @as(f64, @floatFromInt(sur.total))
    else
        0.0;
    const delta = sur_cert - uni_cert;

    const best_cert = @max(uni_cert, sur_cert);
    const pass_bar = best_cert >= 80.0;

    try o.print("\n════════════════════ RQ6 VERDICT ════════════════════\n", .{});
    try o.print("Training grind: {d} grounded commands | invented predicates: {d} | forged features: {d}\n", .{
        n_train, inv.preds.len, vcount,
    });
    try o.print("Held-out novel phrasings: {d}\n\n", .{n_held});
    try o.print("Uniform updates     — predict accuracy: {d}/{d} = {d:.1}%", .{ uni.correct, uni.total, uni_acc });
    if (live_mode) try o.print(" | certified: {d}/{d} = {d:.1}%", .{ uni.certified, uni.total, uni_cert });
    try o.print("\n", .{});
    try o.print("Surprise-weighted   — predict accuracy: {d}/{d} = {d:.1}%", .{ sur.correct, sur.total, sur_acc });
    if (live_mode) try o.print(" | certified: {d}/{d} = {d:.1}%", .{ sur.certified, sur.total, sur_cert });
    try o.print("\n", .{});
    try o.print("Surprise − uniform certified delta: {s}{d:.1} pp\n", .{ if (delta >= 0) "+" else "", delta });
    try o.print("Pass bar (≥80% certified predict): {s} (best={d:.1}%)\n\n", .{
        if (pass_bar) "PASS" else "FAIL",
        best_cert,
    });
    try o.print("The terminal is the verifier: labels are what commands ACTUALLY DID.\n", .{});
    try o.print("E8 at grind scale: invented predicates + forged NL + live-certified predictions on unseen phrasings.\n", .{});
}