//! terminal_grind_big.zig — the BIGGER grind: hundreds of real commands, combinatorial phrasings,
//! uni+bigram structure, large held-out → a STABLE number for grounded command-language. No LLM, no text corpus.
//!
//! Run from boundary_crossing/: zig build terminal-grind-big --release=fast

const std = @import("std");

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
    var alldig = true;
    for (out) |ch| if (ch < '0' or ch > '9') {
        alldig = false;
        break;
    };
    if (alldig) return 2;
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

const Bank = struct { pre: []const []const u8, obj: []const []const u8, cmd: []const []const u8 };
const Req = struct { nl: []const u8, cmd: []const u8 };

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();
    vocab = std.StringHashMap(usize).init(a);
    try o.print("=== TERMINAL GRIND (BIG) — hundreds of real commands, stable number. No LLM, no text corpus ===\n\n", .{});

    const banks = [NC]Bank{
        .{ .pre = &.{}, .obj = &.{}, .cmd = &.{} }, // FAIL handled below (index 0)
        .{ .pre = &.{}, .obj = &.{}, .cmd = &.{} }, // EMPTY (1)
        .{ // NUMBER (2)
            .pre = &.{ "count the", "how many", "number of", "tally the", "give me the count of", "whats the total of", "report the number of" },
            .obj = &.{ "zig files", "sources", "research docs", "modules", "source files" },
            .cmd = &.{ "ls *.zig | wc -l", "ls docs/research/*.md | wc -l", "wc -l < build.zig" },
        },
        .{ // LISTING (3)
            .pre = &.{ "list the", "show me the", "display the", "whats in the", "give me the", "enumerate the", "what are the" },
            .obj = &.{ "zig files", "sources", "research docs", "directory", "files here" },
            .cmd = &.{ "ls -1 *.zig", "ls -1 docs/research", "ls -1" },
        },
        .{ // TEXT (4)
            .pre = &.{ "print a", "echo a", "say a", "show the", "tell me the", "what is the", "give me a" },
            .obj = &.{ "greeting", "message", "path", "working directory", "first readme line", "hello" },
            .cmd = &.{ "echo hello there", "pwd", "head -1 README.md" },
        },
    };
    const failpre = [_][]const u8{ "open the", "find the", "run the", "look for the", "use the", "access the", "load the" };
    const failobj = [_][]const u8{ "missing file", "nonexistent script", "fake readme", "absent command", "broken path", "bogus target" };
    const failcmd = [_][]const u8{ "test -f zzz_missing.xyz", "false", "ls /zzz_no_dir 2>/dev/null", "grep -q zzznotfound README.md", "cat zzz_absent.xyz 2>/dev/null" };
    const emptypre = [_][]const u8{ "check the", "verify the", "confirm the", "make sure the", "ensure the", "is there a" };
    const emptyobj = [_][]const u8{ "readme", "build file", "readme is present", "build is here", "readme around" };
    const emptycmd = [_][]const u8{ "test -f README.md", "test -f build.zig", "grep -q the README.md" };

    var reqs = std.ArrayList(Req).init(a);
    var ci: usize = 0;
    // FAIL
    for (failpre) |p| for (failobj) |ob| {
        try reqs.append(.{ .nl = try std.fmt.allocPrint(a, "{s} {s}", .{ p, ob }), .cmd = failcmd[ci % failcmd.len] });
        ci += 1;
    };
    // EMPTY
    ci = 0;
    for (emptypre) |p| for (emptyobj) |ob| {
        try reqs.append(.{ .nl = try std.fmt.allocPrint(a, "{s} {s}", .{ p, ob }), .cmd = emptycmd[ci % emptycmd.len] });
        ci += 1;
    };
    // NUMBER, LISTING, TEXT
    for ([_]usize{ 2, 3, 4 }) |cls| {
        ci = 0;
        for (banks[cls].pre) |p| for (banks[cls].obj) |ob| {
            try reqs.append(.{ .nl = try std.fmt.allocPrint(a, "{s} {s}", .{ p, ob }), .cmd = banks[cls].cmd[ci % banks[cls].cmd.len] });
            ci += 1;
        };
    }
    const total = reqs.items.len;
    var truth = try a.alloc(u8, total);
    var dist = [_]usize{0} ** NC;
    for (reqs.items, 0..) |r, k| {
        truth[k] = observe(a, r.cmd);
        dist[truth[k]] += 1;
    }
    try o.print("[grind] ran {d} real commands. observed outcome distribution: ", .{total});
    for (0..NC) |c| try o.print("{s}={d} ", .{ cname[c], dist[c] });
    try o.print("\n\n", .{});

    // shuffle, 75/25 split
    var prng: u64 = 0xA17C0FFE;
    var order = try a.alloc(usize, total);
    for (0..total) |i| order[i] = i;
    var n = total;
    while (n > 1) {
        n -= 1;
        prng ^= prng << 13;
        prng ^= prng >> 7;
        prng ^= prng << 17;
        const j = prng % (n + 1);
        const t = order[n];
        order[n] = order[j];
        order[j] = t;
    }
    const split = total * 3 / 4;
    var tix = try a.alloc([]usize, total);
    for (0..split) |k| tix[order[k]] = try toks(a, reqs.items[order[k]].nl, true);
    for (split..total) |k| tix[order[k]] = try toks(a, reqs.items[order[k]].nl, false);
    const w = try a.alloc(f32, vcount * NC);
    @memset(w, 0);
    for (0..500) |_| for (0..split) |k| {
        const idx = order[k];
        var s = [_]f32{0} ** NC;
        for (tix[idx]) |x| for (0..NC) |c| {
            s[c] += w[x * NC + c];
        };
        var p: usize = 0;
        for (0..NC) |c| if (s[c] > s[p]) {
            p = c;
        };
        if (p != truth[idx]) for (tix[idx]) |x| {
            w[x * NC + truth[idx]] += 1;
            w[x * NC + p] -= 1;
        };
    };

    // held-out: predict outcome KIND, RUN to verify
    var correct: usize = 0;
    var per_tot = [_]usize{0} ** NC;
    var per_ok = [_]usize{0} ** NC;
    for (split..total) |k| {
        const idx = order[k];
        var s = [_]f32{0} ** NC;
        for (tix[idx]) |x| for (0..NC) |c| {
            s[c] += w[x * NC + c];
        };
        var p: usize = 0;
        for (0..NC) |c| if (s[c] > s[p]) {
            p = c;
        };
        const real = observe(a, reqs.items[idx].cmd);
        per_tot[real] += 1;
        if (p == real) {
            correct += 1;
            per_ok[real] += 1;
        }
    }
    const held = total - split;
    try o.print("════════════════════ THE STABLE NUMBER ════════════════════\n", .{});
    try o.print(">>> held-out, verified against the REAL terminal: {d}/{d} = {d:.1}% <<<\n", .{ correct, held, 100.0 * @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(held)) });
    try o.print("    ({d}-command corpus, {d} uni+bigram features, no text corpus, no LLM)\n", .{ total, vcount });
    try o.print("    per outcome kind:  ", .{});
    for (0..NC) |c| if (per_tot[c] > 0) try o.print("{s} {d}/{d}  ", .{ cname[c], per_ok[c], per_tot[c] });
    try o.print("\n", .{});
}
