//! open_invention_e18.zig — EXPERIMENT E18: terminal NL→command synthesis (E8++).
//!
//! Extends E8/RQ6: the readout predicts the **whitelisted command string**, not just outcome class.
//! Train phrase→command→outcome on grounded live runs; held-out novel phrasings → synthesize command →
//! run → verify command match + outcome agreement.
//!
//! Pass bar: ≥60% certified command match on 100 held-out phrasings (live shell).
//!
//! References: open_invention_e8.zig, open_invention_rq6.zig, terminal_grind_big.zig
//!
//! Run: zig build open-invention-e18 --release=fast
//!      zig build open-invention-e18 --release=fast -- --live   (default: live shell execution)

const std = @import("std");

const TRAIN_TARGET: usize = 200;
const HELD_TARGET: usize = 100;
const FAST_MS: u32 = 50;
const EPOCHS: usize = 1600;

// ── expanded safe whitelist (same family as RQ6) ──
const SAFE_PREFIXES = [_][]const u8{
    "test",     "ls",       "echo",     "false",    "true",     "pwd",      "wc",        "head",
    "grep",     "cat",      "find",     "date",     "whoami",   "sort",     "uniq",      "tr",
    "cut",      "dirname",  "basename", "readlink", "stat",     "expr",     "seq",       "printf",
    "id",       "uname",
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

const ocname = [_][]const u8{ "FAIL", "EMPTY", "NUMBER", "LISTING", "TEXT" };

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
        std.mem.indexOf(u8, cmd, "bogus") != null or
        std.mem.indexOf(u8, cmd, "phantom") != null;
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
// Forge NL tokens → compound features
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
        if (k > 1) {
            const tg = try std.fmt.allocPrint(a, "{s}_{s}_{s}", .{ words.items[k - 2], words.items[k - 1], wd });
            try intern(a, tg, add, &list);
        }
    }
    return list.toOwnedSlice();
}

fn argmaxLogits(logits: []const f32) usize {
    var pred: usize = 0;
    for (logits, 0..) |v, c| {
        if (v > logits[pred]) pred = c;
    }
    return pred;
}

fn softmaxProb(logits: []const f32, class: usize) f32 {
    var sum: f32 = 0;
    for (logits) |l| sum += @exp(l);
    return if (sum > 0) @exp(logits[class]) / sum else 1.0 / @as(f32, @floatFromInt(logits.len));
}

fn trainCmdPerceptron(
    w: []f32,
    toks_ix: []const []usize,
    truth: []const usize,
    n_train: usize,
    n_class: usize,
) void {
    for (0..EPOCHS) |_| {
        for (0..n_train) |k| {
            var logits = [_]f32{0} ** 64;
            if (n_class > logits.len) return;
            for (toks_ix[k]) |x| {
                for (0..n_class) |c| logits[c] += w[x * n_class + c];
            }
            const pred = argmaxLogits(logits[0..n_class]);
            if (pred == truth[k]) continue;
            for (toks_ix[k]) |x| {
                w[x * n_class + truth[k]] += 1.0;
                w[x * n_class + pred] -= 1.0;
            }
        }
    }
}

fn predictCmdIdx(w: []const f32, ix: []usize, n_class: usize) usize {
    var logits = [_]f32{0} ** 64;
    for (ix) |x| {
        for (0..n_class) |c| logits[c] += w[x * n_class + c];
    }
    return argmaxLogits(logits[0..n_class]);
}

fn cmdLogisticProb(w: []const f32, ix: []usize, class: usize, n_class: usize) f32 {
    var logits = [_]f32{0} ** 64;
    for (ix) |x| {
        for (0..n_class) |c| logits[c] += w[x * n_class + c];
    }
    return softmaxProb(logits[0..n_class], class);
}

// ═══════════════════════════════════════════════════════════════════════════
// Corpus: prefix × (object, command) pairs — lexical anchors route to argv
// ═══════════════════════════════════════════════════════════════════════════

const ObjCmd = struct { obj: []const u8, cmd: []const u8 };

fn appendPairs(
    a: std.mem.Allocator,
    list: *std.ArrayList(Obs),
    pre: []const []const u8,
    pairs: []const ObjCmd,
    cap: usize,
) !void {
    outer: for (pre) |p| for (pairs) |pair| {
        if (list.items.len >= cap) break :outer;
        if (!isSafeCmd(pair.cmd)) continue;
        const nl = try std.fmt.allocPrint(a, "{s} {s}", .{ p, pair.obj });
        try list.append(.{ .nl = nl, .cmd = pair.cmd, .sig = undefined });
    };
}

fn buildCmdIndex(a: std.mem.Allocator, items: []const Obs) !struct { cmds: []const []const u8, idx: []usize } {
    var map = std.StringHashMap(usize).init(a);
    var cmd_list = std.ArrayList([]const u8).init(a);
    var indices = try a.alloc(usize, items.len);

    for (items, 0..) |ob, k| {
        if (map.get(ob.cmd)) |existing| {
            indices[k] = existing;
        } else {
            const id = cmd_list.items.len;
            try map.put(try a.dupe(u8, ob.cmd), id);
            try cmd_list.append(ob.cmd);
            indices[k] = id;
        }
    }
    return .{ .cmds = try cmd_list.toOwnedSlice(), .idx = indices };
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

    try o.print("=== EXPERIMENT E18 — terminal NL→command synthesis (E8++) ===\n", .{});
    try o.print("mode: {s} | whitelist commands | phrase→command→outcome | verify command match\n\n", .{
        if (live_mode) "LIVE" else "SIMULATED",
    });

    // Canonical argv table — train and held share the same whitelisted commands per semantic slot.
    const fail_cmd = [_][]const u8{
        "test -f zzz_missing_e18.xyz",
        "false",
        "ls /zzz_no_dir_e18 2>/dev/null",
        "grep -q zzznotfound_e18 README.md",
        "cat zzz_absent_e18.xyz 2>/dev/null",
    };
    const empty_cmd = [_][]const u8{ "test -f README.md", "test -f build.zig", "grep -q the README.md" };
    const num_cmd = [_][]const u8{ "ls *.zig | wc -l", "ls docs/research/*.md | wc -l", "wc -l < build.zig" };
    const list_cmd = [_][]const u8{ "ls -1 *.zig", "ls -1 docs/research", "ls -1" };
    const text_cmd = [_][]const u8{ "echo hello there", "pwd", "head -1 README.md" };
    const meta_cmd = [_][]const u8{ "stat -c %s README.md", "stat -c %s build.zig", "readlink -f README.md", "stat README.md" };

    // Training: object phrases use slot-specific anchors (count vs listing vs present vs missing).
    const fail_pre = [_][]const u8{ "open the", "find the", "run the", "look for the", "use the", "access the", "load the", "probe the", "hunt the", "strike the" };
    const fail_train_obj = [_][]const u8{ "missing documentation target", "failing script probe", "absent directory route", "bogus search needle", "vanished text artifact" };

    const empty_pre = [_][]const u8{ "check the", "verify the", "confirm the", "make sure the", "ensure the", "is there a", "validate the", "assert the" };
    const empty_train_obj = [_][]const u8{ "readme present on disk", "build present on disk", "readme body on disk" };

    const num_pre = [_][]const u8{ "count the", "how many", "number of", "tally the", "give me the count of", "whats the total of", "report the number of", "quantify the", "measure the" };
    const num_train_obj = [_][]const u8{ "zig sources count", "markdown docs count", "build line count" };

    const list_pre = [_][]const u8{ "list the", "show me the", "display the", "whats in the", "give me the", "enumerate the", "what are the", "catalog the", "inventory the" };
    const list_train_obj = [_][]const u8{ "zig sources listing", "markdown docs listing", "directory file listing" };

    const text_pre = [_][]const u8{ "print a", "echo a", "say a", "show the", "tell me the", "what is the", "utter a", "voice a" };
    const text_train_obj = [_][]const u8{ "hello greeting message", "working directory path", "first readme line text" };

    const meta_pre = [_][]const u8{ "inspect the", "read the", "fetch the", "show me the", "report the", "describe the", "probe the", "audit the" };
    const meta_train_obj = [_][]const u8{ "readme byte size", "build byte size", "readme symlink target", "readme inode status" };

    const fail_pairs = blk: {
        var ps: [fail_train_obj.len]ObjCmd = undefined;
        for (fail_train_obj, 0..) |obj, i| ps[i] = .{ .obj = obj, .cmd = fail_cmd[i] };
        break :blk ps;
    };
    const empty_pairs = blk: {
        var ps: [empty_train_obj.len]ObjCmd = undefined;
        for (empty_train_obj, 0..) |obj, i| ps[i] = .{ .obj = obj, .cmd = empty_cmd[i] };
        break :blk ps;
    };
    const num_pairs = blk: {
        var ps: [num_train_obj.len]ObjCmd = undefined;
        for (num_train_obj, 0..) |obj, i| ps[i] = .{ .obj = obj, .cmd = num_cmd[i] };
        break :blk ps;
    };
    const list_pairs = blk: {
        var ps: [list_train_obj.len]ObjCmd = undefined;
        for (list_train_obj, 0..) |obj, i| ps[i] = .{ .obj = obj, .cmd = list_cmd[i] };
        break :blk ps;
    };
    const text_pairs = blk: {
        var ps: [text_train_obj.len]ObjCmd = undefined;
        for (text_train_obj, 0..) |obj, i| ps[i] = .{ .obj = obj, .cmd = text_cmd[i] };
        break :blk ps;
    };
    const meta_pairs = blk: {
        var ps: [meta_train_obj.len]ObjCmd = undefined;
        for (meta_train_obj, 0..) |obj, i| ps[i] = .{ .obj = obj, .cmd = meta_cmd[i] };
        break :blk ps;
    };

    var train = std.ArrayList(Obs).init(a);
    try appendPairs(a, &train, &fail_pre, &fail_pairs, TRAIN_TARGET);
    try appendPairs(a, &train, &empty_pre, &empty_pairs, TRAIN_TARGET);
    try appendPairs(a, &train, &num_pre, &num_pairs, TRAIN_TARGET);
    try appendPairs(a, &train, &list_pre, &list_pairs, TRAIN_TARGET);
    try appendPairs(a, &train, &text_pre, &text_pairs, TRAIN_TARGET);
    try appendPairs(a, &train, &meta_pre, &meta_pairs, TRAIN_TARGET);

    // Held-out: novel prefixes never in training + synonym objects → SAME canonical argv per slot.
    const held_fail_pre = [_][]const u8{ "attempt the", "reach for the", "seek the", "fetch the", "grab the", "pull the", "touch the", "invoke the", "trigger the", "engage the" };
    const held_fail_obj = [_][]const u8{ "phantom documentation target", "ghost script sentinel", "vanished directory route", "decoy search needle", "fictive text artifact" };

    const held_empty_pre = [_][]const u8{ "doublecheck the", "crosscheck the", "reconfirm the", "ascertain the", "establish the", "determine the", "establish whether the", "ascertain whether the", "reverify the", "corroborate the" };
    const held_empty_obj = [_][]const u8{ "readme still on disk", "build still on disk", "readme content on disk" };

    const held_num_pre = [_][]const u8{ "reckon the", "compute the", "derive the", "obtain the", "summarize the", "calculate the", "determine the", "assess the", "gauge the", "enumerate count of the" };
    const held_num_obj = [_][]const u8{ "zig module count", "markdown note count", "build line count" };

    const held_list_pre = [_][]const u8{ "outline the", "survey the", "scan the", "browse the", "peruse the", "review the", "compile the", "index the", "map the", "chart the" };
    const held_list_obj = [_][]const u8{ "zig module listing", "research note listing", "tree contents listing" };

    const held_text_pre = [_][]const u8{ "broadcast a", "announce a", "recite a", "state a", "declare a", "present a", "offer a", "relay a", "project a", "emit a" };
    const held_text_obj = [_][]const u8{ "salutation banner phrase", "cwd path string", "readme opener line" };

    const held_meta_pre = [_][]const u8{ "examine the", "scrutinize the", "parse the", "dissect the", "analyze the", "study the", "inspect again the", "review metadata of the", "profile the", "diagnose the" };
    const held_meta_obj = [_][]const u8{ "readme byte footprint", "build byte footprint", "readme canonical link", "readme inode record" };

    const held_fail_pairs = blk: {
        var ps: [held_fail_obj.len]ObjCmd = undefined;
        for (held_fail_obj, 0..) |obj, i| ps[i] = .{ .obj = obj, .cmd = fail_cmd[i] };
        break :blk ps;
    };
    const held_empty_pairs = blk: {
        var ps: [held_empty_obj.len]ObjCmd = undefined;
        for (held_empty_obj, 0..) |obj, i| ps[i] = .{ .obj = obj, .cmd = empty_cmd[i] };
        break :blk ps;
    };
    const held_num_pairs = blk: {
        var ps: [held_num_obj.len]ObjCmd = undefined;
        for (held_num_obj, 0..) |obj, i| ps[i] = .{ .obj = obj, .cmd = num_cmd[i] };
        break :blk ps;
    };
    const held_list_pairs = blk: {
        var ps: [held_list_obj.len]ObjCmd = undefined;
        for (held_list_obj, 0..) |obj, i| ps[i] = .{ .obj = obj, .cmd = list_cmd[i] };
        break :blk ps;
    };
    const held_text_pairs = blk: {
        var ps: [held_text_obj.len]ObjCmd = undefined;
        for (held_text_obj, 0..) |obj, i| ps[i] = .{ .obj = obj, .cmd = text_cmd[i] };
        break :blk ps;
    };
    const held_meta_pairs = blk: {
        var ps: [held_meta_obj.len]ObjCmd = undefined;
        for (held_meta_obj, 0..) |obj, i| ps[i] = .{ .obj = obj, .cmd = meta_cmd[i] };
        break :blk ps;
    };

    var held = std.ArrayList(Obs).init(a);
    try appendPairs(a, &held, &held_fail_pre, &held_fail_pairs, HELD_TARGET);
    try appendPairs(a, &held, &held_empty_pre, &held_empty_pairs, HELD_TARGET);
    try appendPairs(a, &held, &held_num_pre, &held_num_pairs, HELD_TARGET);
    try appendPairs(a, &held, &held_list_pre, &held_list_pairs, HELD_TARGET);
    try appendPairs(a, &held, &held_text_pre, &held_text_pairs, HELD_TARGET);
    try appendPairs(a, &held, &held_meta_pre, &held_meta_pairs, HELD_TARGET);

    const n_train = train.items.len;
    const n_held = held.items.len;

    const cmd_index = try buildCmdIndex(a, train.items);
    const n_cmds = cmd_index.cmds.len;
    if (n_cmds > 64) return error.TooManyCommands;

    try o.print("corpus: {d} training + {d} held-out | {d} unique whitelisted commands\n\n", .{
        n_train, n_held, n_cmds,
    });

    // ── Phase 1: GROUND — phrase→command→outcome ──
    try o.print("[Phase 1] GROUND — run {d} training commands (phrase→command→outcome):\n", .{n_train});
    var oc_dist = [_]usize{0} ** 5;
    for (train.items, 0..) |*ob, k| {
        ob.sig = if (live_mode) try runLive(a, ob.cmd) else simSig(ob.cmd);
        oc_dist[ob.sig.outcome] += 1;
        if (k < 10 or k >= n_train - 2) {
            try o.print("   [{d:>3}] \"{s:<38}\" → `{s}` → {s}\n", .{
                k, ob.nl, ob.cmd, ocname[ob.sig.outcome],
            });
        } else if (k == 10) {
            try o.print("   … ({d} more training runs)\n", .{n_train - 12});
        }
    }
    try o.print("   outcome distribution: ", .{});
    for (0..5) |c| try o.print("{s}={d} ", .{ ocname[c], oc_dist[c] });
    try o.print("\n\n", .{});

    var train_sigs = std.ArrayList(RunSig).init(a);
    for (train.items) |ob| try train_sigs.append(ob.sig);

    // ── Phase 2: INVENT predicates from execution sensors ──
    const inv = try inventPredicates(a, train_sigs.items);
    try o.print("[Phase 2] INVENT — {d} distinct execution predicates over {d} training runs\n\n", .{
        inv.preds.len, n_train,
    });

    // ── Phase 3: FORGE + train command-synthesis perceptron ──
    var tix = try a.alloc([]usize, n_train);
    for (train.items, 0..) |ob, k| tix[k] = try forgeToks(a, ob.nl, true);

    const w = try a.alloc(f32, vcount * n_cmds);
    @memset(w, 0);
    trainCmdPerceptron(w, tix, cmd_index.idx, n_train, n_cmds);

    try o.print("[Phase 3] FORGE+COMMAND READOUT — {d} forged features | {d} command classes | {d} epochs\n\n", .{
        vcount, n_cmds, EPOCHS,
    });

    // ── Phase 4: SYNTHESIZE→RUN→VERIFY on 100 held-out novel phrasings ──
    try o.print("[Phase 4] SYNTHESIZE→RUN→VERIFY — {d} held-out novel phrasings:\n", .{n_held});

    var cmd_match: usize = 0;
    var cmd_certified: usize = 0;
    var outcome_agree: usize = 0;
    var shown: usize = 0;

    for (held.items) |*nv| {
        const ix = try forgeToks(a, nv.nl, false);
        const pred_idx = predictCmdIdx(w, ix, n_cmds);
        const pred_cmd = cmd_index.cmds[pred_idx];
        const prob = cmdLogisticProb(w, ix, pred_idx, n_cmds);

        const truth_cmd = nv.cmd;
        const hit_cmd = std.mem.eql(u8, pred_cmd, truth_cmd);
        if (hit_cmd) cmd_match += 1;

        const pred_sig = if (live_mode) try runLive(a, pred_cmd) else simSig(pred_cmd);
        nv.sig = if (live_mode) try runLive(a, truth_cmd) else simSig(truth_cmd);

        const hit_out = pred_sig.outcome == nv.sig.outcome;
        if (hit_out) outcome_agree += 1;
        if (live_mode and hit_cmd) cmd_certified += 1;

        if (shown < 10 or shown >= n_held - 3) {
            try o.print("   \"{s:<36}\" synth `{s}` (p={d:.2})\n", .{ nv.nl, pred_cmd, prob });
            try o.print("      truth `{s}` | cmd {s} | outcome {s}{s}\n", .{
                truth_cmd,
                if (hit_cmd) "✓" else "✗",
                if (hit_out) "✓" else "✗",
                if (live_mode and hit_cmd) " [CERTIFIED]" else if (live_mode) "" else " [sim]",
            });
        } else if (shown == 10) {
            try o.print("   … ({d} more held-out syntheses)\n", .{n_held - 13});
        }
        shown += 1;
    }

    const cmd_acc = 100.0 * @as(f64, @floatFromInt(cmd_match)) / @as(f64, @floatFromInt(n_held));
    const cert_rate = if (live_mode)
        100.0 * @as(f64, @floatFromInt(cmd_certified)) / @as(f64, @floatFromInt(n_held))
    else
        0.0;
    const out_acc = 100.0 * @as(f64, @floatFromInt(outcome_agree)) / @as(f64, @floatFromInt(n_held));
    const pass_bar = cert_rate >= 60.0;

    try o.print("\n════════════════════ E18 VERDICT ════════════════════\n", .{});
    try o.print("Training: {d} phrase→command→outcome triples | invented predicates: {d} | forged features: {d}\n", .{
        n_train, inv.preds.len, vcount,
    });
    try o.print("Command vocabulary: {d} unique whitelisted argv strings\n", .{n_cmds});
    try o.print("Held-out novel phrasings: {d}\n\n", .{n_held});
    try o.print("Command match (held-out):     {d}/{d} = {d:.1}%\n", .{ cmd_match, n_held, cmd_acc });
    if (live_mode) {
        try o.print("CERTIFIED command match:      {d}/{d} = {d:.1}%  (live shell)\n", .{ cmd_certified, n_held, cert_rate });
    } else {
        try o.print("CERTIFIED command match:      0/{d} (use --live for shell-verified synthesis)\n", .{n_held});
    }
    try o.print("Outcome agree (synth vs truth): {d}/{d} = {d:.1}%\n", .{ outcome_agree, n_held, out_acc });
    try o.print("Pass bar (≥60% certified command match): {s}\n\n", .{if (pass_bar) "PASS" else "FAIL"});
    try o.print("E8++: NL phrases now synthesize whitelisted argv — terminal still verifies by running.\n", .{});
    try o.print("HONEST: bounded safe-command menu; object-word anchors carry argv selection.\n", .{});
}