//! compression_invent.zig — shared reversible-filter compression invention core.
//! Used by open_invention_e9.zig (cross-script) and open_invention_e23.zig (same-family).

const std = @import("std");

pub const CORPUS_DIRS = [_][]const u8{
    "../corpus/",
    "corpus/",
    "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/",
};

pub const CHUNK: usize = 32 * 1024;
pub const TRAIN_BYTE_CAP: usize = 2 * 1024 * 1024;
pub const HELD_MAX_CHUNKS: usize = 24;

pub const Gene = struct { op: u8 = 0, param: u8 = 0 };
pub const Prog = struct { genes: [MAXLEN]Gene = [_]Gene{.{}} ** MAXLEN, len: usize = 0 };
pub const Macro = struct { genes: [MAXLEN]Gene = [_]Gene{.{}} ** MAXLEN, len: usize = 0 };
pub const ChunkView = struct { off: usize, len: usize };

pub const MAXLEN: usize = 8;

pub const Budget = struct {
    train_restarts: usize = 8,
    train_steps: usize = 18,
    held_restarts: usize = 4,
    held_steps: usize = 10,
    train_vote_chunks: usize = 16,
    max_lib: usize = 16,
    min_votes: usize = 2,
};

pub const PassCriteria = struct {
    min_lib_macros: usize = 1,
    min_cross_pct: f64 = 0.0, // (no_promo - self_ext) / no_promo * 100
    require_lib_nonempty: bool = true,
};

pub const ExperimentSpec = struct {
    title: []const u8,
    objective_lines: []const []const u8,
    train_candidates: []const []const u8,
    held_candidates: []const []const u8,
    budget: Budget = .{},
    pass: PassCriteria = .{},
    result_tag: []const u8,
    result_doc: []const u8,
    train_seed: u64 = 0xE900B009,
    use_vote_library: bool = true,
    use_stream_library: bool = false,
    include_pair_candidates: bool = false,
    held_label: []const u8 = "held-out",
};

var prng: u64 = 0x9E3779B97F4A7C15;

pub fn reseed(s: u64) void {
    prng = s | 1;
}

fn rnd() u64 {
    prng ^= prng << 13;
    prng ^= prng >> 7;
    prng ^= prng << 17;
    return prng;
}

fn rndN(n: usize) usize {
    return @intCast(rnd() % @as(u64, n));
}

pub fn mtfFwd(buf: []u8) void {
    var tbl: [256]u8 = undefined;
    for (0..256) |i| tbl[i] = @intCast(i);
    for (buf) |*b| {
        const v = b.*;
        var r: u8 = 0;
        while (tbl[r] != v) r += 1;
        b.* = r;
        var j: usize = r;
        while (j > 0) : (j -= 1) tbl[j] = tbl[j - 1];
        tbl[0] = v;
    }
}

pub fn mtfInv(buf: []u8) void {
    var tbl: [256]u8 = undefined;
    for (0..256) |i| tbl[i] = @intCast(i);
    for (buf) |*b| {
        const r = b.*;
        const v = tbl[r];
        b.* = v;
        var j: usize = r;
        while (j > 0) : (j -= 1) tbl[j] = tbl[j - 1];
        tbl[0] = v;
    }
}

pub fn opFwd(buf: []u8, g: Gene, sc: []u8) void {
    const n = buf.len;
    switch (g.op) {
        1 => {
            const d: usize = g.param;
            var i: usize = 0;
            while (i < n) : (i += 1) sc[i] = buf[i] -% (if (i >= d) buf[i - d] else 0);
            @memcpy(buf, sc[0..n]);
        },
        2 => {
            const d: usize = g.param;
            var i: usize = 0;
            while (i < n) : (i += 1) sc[i] = buf[i] ^ (if (i >= d) buf[i - d] else 0);
            @memcpy(buf, sc[0..n]);
        },
        3 => {
            var i: usize = 0;
            while (i < n) : (i += 1) buf[i] = buf[i] +% g.param;
        },
        4 => {
            const s: usize = @max(2, @as(usize, g.param));
            var pos: usize = 0;
            var r: usize = 0;
            while (r < s) : (r += 1) {
                var i: usize = r;
                while (i < n) : (i += s) {
                    sc[pos] = buf[i];
                    pos += 1;
                }
            }
            @memcpy(buf, sc[0..n]);
        },
        5 => mtfFwd(buf),
        else => {},
    }
}

pub fn opInv(buf: []u8, g: Gene, sc: []u8) void {
    const n = buf.len;
    switch (g.op) {
        1 => {
            const d: usize = g.param;
            var i: usize = 0;
            while (i < n) : (i += 1) buf[i] = buf[i] +% (if (i >= d) buf[i - d] else 0);
        },
        2 => {
            const d: usize = g.param;
            var i: usize = 0;
            while (i < n) : (i += 1) buf[i] = buf[i] ^ (if (i >= d) buf[i - d] else 0);
        },
        3 => {
            var i: usize = 0;
            while (i < n) : (i += 1) buf[i] = buf[i] -% g.param;
        },
        4 => {
            const s: usize = @max(2, @as(usize, g.param));
            var pos: usize = 0;
            var r: usize = 0;
            while (r < s) : (r += 1) {
                var i: usize = r;
                while (i < n) : (i += s) {
                    sc[i] = buf[pos];
                    pos += 1;
                }
            }
            @memcpy(buf, sc[0..n]);
        },
        5 => mtfInv(buf),
        else => {},
    }
}

pub fn applyFwd(p: Prog, data: []const u8, a: std.mem.Allocator) ![]u8 {
    const buf = try a.dupe(u8, data);
    const sc = try a.alloc(u8, @max(1, data.len));
    defer a.free(sc);
    for (0..p.len) |k| opFwd(buf, p.genes[k], sc);
    return buf;
}

pub fn applyInv(p: Prog, data: []const u8, a: std.mem.Allocator) ![]u8 {
    const buf = try a.dupe(u8, data);
    const sc = try a.alloc(u8, @max(1, data.len));
    defer a.free(sc);
    var k = p.len;
    while (k > 0) {
        k -= 1;
        opInv(buf, p.genes[k], sc);
    }
    return buf;
}

pub fn gzSize(a: std.mem.Allocator, data: []const u8) usize {
    var buf = std.ArrayList(u8).init(a);
    defer buf.deinit();
    var fbs = std.io.fixedBufferStream(data);
    std.compress.gzip.compress(fbs.reader(), buf.writer(), .{ .level = .default }) catch return data.len;
    return buf.items.len;
}

pub fn reversible(p: Prog, data: []const u8, a: std.mem.Allocator) !bool {
    const f = try applyFwd(p, data, a);
    defer a.free(f);
    const b = try applyInv(p, f, a);
    defer a.free(b);
    return std.mem.eql(u8, data, b);
}

pub fn cost(p: Prog, data: []const u8, a: std.mem.Allocator) !usize {
    if (!try reversible(p, data, a)) return std.math.maxInt(usize);
    const f = try applyFwd(p, data, a);
    defer a.free(f);
    return gzSize(a, f);
}

pub fn progCompressedSize(p: Prog, data: []const u8, a: std.mem.Allocator) !usize {
    const f = try applyFwd(p, data, a);
    defer a.free(f);
    return gzSize(a, f);
}

pub fn pctSaved(base: usize, after: usize) f64 {
    if (base == 0) return 0;
    return 100.0 * (@as(f64, @floatFromInt(base)) - @as(f64, @floatFromInt(after))) / @as(f64, @floatFromInt(base));
}

pub fn isStructural(p: Prog) bool {
    for (0..p.len) |k| {
        switch (p.genes[k].op) {
            1, 2, 4, 5 => {},
            else => return false,
        }
    }
    return p.len > 0;
}

fn randGene() Gene {
    const op: u8 = @intCast(1 + rndN(5));
    const param: u8 = switch (op) {
        1, 2 => @intCast(1 + rndN(4)),
        3 => @intCast(1 + rndN(255)),
        4 => @intCast(2 + rndN(7)),
        else => 0,
    };
    return .{ .op = op, .param = param };
}

pub fn mutate(p: Prog, lib: []const Macro) Prog {
    var q = p;
    const use_macro = lib.len > 0 and rndN(2) == 0;
    if (use_macro) {
        const m = lib[rndN(lib.len)];
        if (q.len + m.len <= MAXLEN) {
            for (0..m.len) |k| {
                q.genes[q.len] = m.genes[k];
                q.len += 1;
            }
            return q;
        }
    }
    const c = rndN(3);
    if (c == 0 and q.len < MAXLEN) {
        q.genes[q.len] = randGene();
        q.len += 1;
    } else if (c == 1 and q.len > 0) {
        q.len -= 1;
    } else if (q.len > 0) {
        q.genes[rndN(q.len)] = randGene();
    } else {
        q.genes[0] = randGene();
        q.len = 1;
    }
    return q;
}

fn prog1(g: Gene) Prog {
    var p = Prog{};
    p.genes[0] = g;
    p.len = 1;
    return p;
}

fn consider(prog: Prog, data: []const u8, a: std.mem.Allocator, best: *Prog, best_cost: *usize) !void {
    const c = try cost(prog, data, a);
    if (c < best_cost.*) {
        best.* = prog;
        best_cost.* = c;
    }
}

pub fn exhaustiveStructural(data: []const u8, a: std.mem.Allocator) !Prog {
    var best = Prog{};
    var best_cost = try cost(best, data, a);
    var singles: [32]Gene = undefined;
    var ns: usize = 0;
    const addSingle = struct {
        fn f(g: Gene, s: *[32]Gene, n: *usize) void {
            if (n.* < s.len) {
                s[n.*] = g;
                n.* += 1;
            }
        }
    }.f;
    for (1..5) |d| {
        const g: Gene = .{ .op = 1, .param = @intCast(d) };
        try consider(prog1(g), data, a, &best, &best_cost);
        addSingle(g, &singles, &ns);
    }
    for (1..5) |d| {
        const g: Gene = .{ .op = 2, .param = @intCast(d) };
        try consider(prog1(g), data, a, &best, &best_cost);
        addSingle(g, &singles, &ns);
    }
    for (2..9) |s| {
        const g: Gene = .{ .op = 4, .param = @intCast(s) };
        try consider(prog1(g), data, a, &best, &best_cost);
        addSingle(g, &singles, &ns);
    }
    const mtf: Gene = .{ .op = 5, .param = 0 };
    try consider(prog1(mtf), data, a, &best, &best_cost);
    addSingle(mtf, &singles, &ns);
    for (0..ns) |i| for (0..ns) |j| {
        var p = Prog{};
        p.genes[0] = singles[i];
        p.genes[1] = singles[j];
        p.len = 2;
        try consider(p, data, a, &best, &best_cost);
    };
    return best;
}

pub fn search(data: []const u8, a: std.mem.Allocator, lib: []const Macro, restarts: usize, steps: usize) !Prog {
    var best = try exhaustiveStructural(data, a);
    var best_cost = try cost(best, data, a);
    for (0..restarts) |_| {
        var cur = mutate(Prog{}, lib);
        var cur_cost = cost(cur, data, a) catch std.math.maxInt(usize);
        for (0..steps) |_| {
            const cand = mutate(cur, lib);
            const cc = cost(cand, data, a) catch std.math.maxInt(usize);
            if (cc <= cur_cost) {
                cur = cand;
                cur_cost = cc;
            }
            if (cur_cost < best_cost) {
                best = cur;
                best_cost = cur_cost;
            }
        }
    }
    return best;
}

pub fn macroEq(m: Macro, p: Prog) bool {
    if (m.len != p.len) return false;
    for (0..p.len) |k| if (m.genes[k].op != p.genes[k].op or m.genes[k].param != p.genes[k].param) return false;
    return true;
}

pub fn printProg(o: anytype, p: Prog) void {
    if (p.len == 0) {
        o.print("identity", .{}) catch {};
        return;
    }
    for (0..p.len) |k| {
        if (k > 0) o.print("→", .{}) catch {};
        const g = p.genes[k];
        switch (g.op) {
            1 => o.print("delta{d}", .{g.param}) catch {},
            2 => o.print("xor{d}", .{g.param}) catch {},
            3 => o.print("add{d}", .{g.param}) catch {},
            4 => o.print("stride{d}", .{g.param}) catch {},
            5 => o.print("mtf", .{}) catch {},
            else => {},
        }
    }
}

pub fn tryLoadCorpus(a: std.mem.Allocator, name: []const u8) !?[]u8 {
    for (CORPUS_DIRS) |dir| {
        const path = try std.fs.path.join(a, &.{ dir, name });
        const f = std.fs.cwd().openFile(path, .{}) catch continue;
        defer f.close();
        return try f.readToEndAlloc(a, 64 * 1024 * 1024);
    }
    return null;
}

pub fn chunkIndices(a: std.mem.Allocator, data_len: usize, byte_cap: ?usize, max_chunks: ?usize) ![]ChunkView {
    const limit = std.math.divCeil(usize, data_len, CHUNK) catch unreachable;
    var list = try std.ArrayList(ChunkView).initCapacity(a, limit);
    var off: usize = 0;
    while (off < data_len and list.items.len < (max_chunks orelse limit)) {
        const len = @min(CHUNK, data_len - off);
        try list.append(.{ .off = off, .len = len });
        off += len;
        if (byte_cap) |c| {
            if (off >= c) break;
        }
    }
    const out = try a.alloc(ChunkView, list.items.len);
    @memcpy(out, list.items);
    return out;
}

const VoteEntry = struct { prog: Prog, votes: usize };

fn geneKey(g: Gene) u16 {
    return (@as(u16, g.op) << 8) | g.param;
}

fn progKey(p: Prog) u32 {
    var k: u32 = @intCast(p.len);
    for (0..p.len) |i| k = k *% 31 +% geneKey(p.genes[i]);
    return k;
}

pub fn candidateProgs(a: std.mem.Allocator, include_pairs: bool) ![]Prog {
    var singles: [32]Gene = undefined;
    var ns: usize = 0;
    inline for (.{ 1, 2, 3, 4 }) |d| {
        singles[ns] = .{ .op = 1, .param = @intCast(d) };
        ns += 1;
    }
    inline for (.{ 1, 2, 3, 4 }) |d| {
        singles[ns] = .{ .op = 2, .param = @intCast(d) };
        ns += 1;
    }
    inline for (.{ 2, 3, 4, 5, 6, 7, 8 }) |s| {
        singles[ns] = .{ .op = 4, .param = @intCast(s) };
        ns += 1;
    }
    singles[ns] = .{ .op = 5, .param = 0 };
    ns += 1;
    const pair_count = if (include_pairs) ns * ns else 0;
    var list = try std.ArrayList(Prog).initCapacity(a, ns + pair_count);
    for (0..ns) |i| try list.append(prog1(singles[i]));
    if (include_pairs) {
        for (0..ns) |i| for (0..ns) |j| {
            var p = Prog{};
            p.genes[0] = singles[i];
            p.genes[1] = singles[j];
            p.len = 2;
            try list.append(p);
        };
    }
    return list.toOwnedSlice();
}

pub fn sampleViews(all: []const ChunkView, a: std.mem.Allocator, max_n: usize) ![]ChunkView {
    const n = @min(max_n, all.len);
    const out = try a.alloc(ChunkView, n);
    if (all.len <= max_n) {
        @memcpy(out, all);
        return out;
    }
    const step = @max(1, all.len / max_n);
    var j: usize = 0;
    var i: usize = 0;
    while (i < all.len and j < n) : (i += step) {
        out[j] = all[i];
        j += 1;
    }
    return out[0..j];
}

pub fn buildLibraryByVote(
    data: []const u8,
    views: []const ChunkView,
    candidates: []const Prog,
    a: std.mem.Allocator,
    min_votes: usize,
    max_lib: usize,
) !std.ArrayList(Macro) {
    var votes = std.AutoHashMap(u32, VoteEntry).init(a);
    for (views) |cv| {
        const slice = data[cv.off .. cv.off + cv.len];
        const base = gzSize(a, slice);
        for (candidates) |p| {
            if (!isStructural(p)) continue;
            const c = cost(p, slice, a) catch continue;
            if (c < base) {
                const k = progKey(p);
                const e = try votes.getOrPut(k);
                if (!e.found_existing) e.value_ptr.* = .{ .prog = p, .votes = 0 };
                e.value_ptr.votes += 1;
            }
        }
    }
    var ranked = std.ArrayList(VoteEntry).init(a);
    var it = votes.iterator();
    while (it.next()) |e| {
        if (e.value_ptr.votes >= min_votes) try ranked.append(e.value_ptr.*);
    }
    std.mem.sort(VoteEntry, ranked.items, {}, struct {
        fn less(_: void, a_entry: VoteEntry, b_entry: VoteEntry) bool {
            return a_entry.votes > b_entry.votes;
        }
    }.less);
    var lib = std.ArrayList(Macro).init(a);
    for (ranked.items, 0..) |ent, i| {
        if (i >= max_lib) break;
        var mac = Macro{ .len = ent.prog.len };
        for (0..ent.prog.len) |k| mac.genes[k] = ent.prog.genes[k];
        try lib.append(mac);
    }
    return lib;
}

fn tryPromote(lib: *std.ArrayList(Macro), p: Prog, max_lib: usize) !void {
    if (!isStructural(p) or p.len == 0) return;
    if (lib.items.len >= max_lib) return;
    for (lib.items) |m| {
        var mp = Prog{ .len = m.len };
        for (0..m.len) |k| mp.genes[k] = m.genes[k];
        if (macroEq(m, p)) return;
    }
    var mac = Macro{ .len = p.len };
    for (0..p.len) |k| mac.genes[k] = p.genes[k];
    try lib.append(mac);
}

/// Stream self-extension: promote structural search winners chunk-by-chunk (E23).
pub fn buildLibrarySelfExtending(
    data: []const u8,
    views: []const ChunkView,
    a: std.mem.Allocator,
    budget: Budget,
    seed_base: u64,
) !std.ArrayList(Macro) {
    var lib = std.ArrayList(Macro).init(a);
    for (views, 0..) |cv, ci| {
        const slice = data[cv.off .. cv.off + cv.len];
        const base = gzSize(a, slice);
        reseed(seed_base ^ @as(u64, @intCast(ci)) *% 0xD1B54A32D192ED03);

        const ex = try exhaustiveStructural(slice, a);
        const ex_cost = try progCompressedSize(ex, slice, a);
        if (ex_cost < base) try tryPromote(&lib, ex, budget.max_lib);

        const best = try search(slice, a, lib.items, budget.train_restarts, budget.train_steps);
        const best_cost = try progCompressedSize(best, slice, a);
        if (best_cost < base) try tryPromote(&lib, best, budget.max_lib);
    }
    return lib;
}

pub fn evalHeldOutPair(
    data: []const u8,
    views: []const ChunkView,
    a: std.mem.Allocator,
    lib: []const Macro,
    seed_base: u64,
    budget: Budget,
) !struct { base: usize, no_promo: usize, self_ext: usize } {
    var base: usize = 0;
    var no_promo: usize = 0;
    var self_ext: usize = 0;
    const empty = [_]Macro{};
    for (views, 0..) |cv, ci| {
        const slice = data[cv.off .. cv.off + cv.len];
        base += gzSize(a, slice);
        reseed(seed_base ^ @as(u64, @intCast(ci)) *% 0xD1B54A32D192ED03);
        const best_np = try search(slice, a, empty[0..], budget.held_restarts, budget.held_steps);
        no_promo += try progCompressedSize(best_np, slice, a);
        const best_se = try search(slice, a, lib, budget.held_restarts, budget.held_steps);
        self_ext += try progCompressedSize(best_se, slice, a);
    }
    return .{ .base = base, .no_promo = no_promo, .self_ext = self_ext };
}

pub fn runExperiment(spec: ExperimentSpec) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();

    try o.print("=== {s} ===\n\n", .{spec.title});
    for (spec.objective_lines) |line| try o.print("{s}\n", .{line});
    try o.print("\n", .{});

    var train_name: ?[]const u8 = null;
    var train_data: ?[]u8 = null;
    for (spec.train_candidates) |nm| {
        if (try tryLoadCorpus(a, nm)) |d| {
            train_name = nm;
            train_data = d;
            break;
        }
    }
    if (train_data == null or train_name == null) {
        try o.print("FAIL: could not load train corpus from corpus/\n", .{});
        try o.print("{s} pass=false bytes_saved=0 doc={s}\n", .{ spec.result_tag, spec.result_doc });
        return;
    }

    const train = train_data.?;
    const train_cap = @min(TRAIN_BYTE_CAP, train.len);
    const train_views = try chunkIndices(a, train.len, train_cap, null);
    const vote_views = try sampleViews(train_views, a, spec.budget.train_vote_chunks);
    const candidates = try candidateProgs(a, spec.include_pair_candidates);

    try o.print("TRAIN corpus: {s} ({d} bytes, {d} chunks × {d}KB, cap {d}MB)\n", .{
        train_name.?, train.len, train_views.len, CHUNK / 1024, TRAIN_BYTE_CAP / (1024 * 1024),
    });
    try o.print("budget: train {d}×{d} search; {s} {d}×{d}; candidates {d}; max {d} macros\n", .{
        spec.budget.train_restarts,
        spec.budget.train_steps,
        spec.held_label,
        spec.budget.held_restarts,
        spec.budget.held_steps,
        candidates.len,
        spec.budget.max_lib,
    });
    if (spec.use_stream_library) try o.print("train library: stream self-extension (promote per-chunk winners)\n", .{});
    if (spec.use_vote_library) try o.print("train library: vote grid (min {d} chunk wins)\n", .{spec.budget.min_votes});
    try o.print("\n", .{});

    var lib = std.ArrayList(Macro).init(a);
    if (spec.use_vote_library) {
        try o.print("[train — vote structural winners across chunks]\n", .{});
        lib = try buildLibraryByVote(train, vote_views, candidates, a, spec.budget.min_votes, spec.budget.max_lib);
    }
    if (spec.use_stream_library) {
        try o.print("[train — stream self-extension across chunks]\n", .{});
        const stream_lib = try buildLibrarySelfExtending(train, vote_views, a, spec.budget, spec.train_seed);
        for (stream_lib.items) |m| {
            var p = Prog{ .len = m.len };
            for (0..m.len) |k| p.genes[k] = m.genes[k];
            try tryPromote(&lib, p, spec.budget.max_lib);
        }
    }

    var train_base: usize = 0;
    var train_inv: usize = 0;
    for (vote_views, 0..) |cv, ci| {
        const slice = train[cv.off .. cv.off + cv.len];
        train_base += gzSize(a, slice);
        reseed(spec.train_seed ^ @as(u64, @intCast(ci)) *% 0xD1B54A32D192ED03);
        const best = try search(slice, a, lib.items, spec.budget.train_restarts, spec.budget.train_steps);
        train_inv += try progCompressedSize(best, slice, a);
    }
    try o.print("  train raw gzip {d} → invented {d} ({d:.3}% smaller)\n", .{
        train_base, train_inv, pctSaved(train_base, train_inv),
    });
    try o.print("  library after train: {d} macro(s)\n", .{lib.items.len});
    for (lib.items, 0..) |m, i| {
        var p = Prog{ .len = m.len };
        for (0..m.len) |k| p.genes[k] = m.genes[k];
        try o.print("    macro {d}: ", .{i});
        printProg(o, p);
        try o.print("\n", .{});
    }
    try o.print("\n", .{});

    var held_base: usize = 0;
    var held_no: usize = 0;
    var held_ext: usize = 0;
    var held_chunks: usize = 0;
    var held_files: usize = 0;

    try o.print("[{s} — base gzip vs no-promotion vs self-extend (frozen train library)]\n", .{spec.held_label});
    try o.print("(eval capped at {d} chunks/file for stability)\n", .{HELD_MAX_CHUNKS});
    for (spec.held_candidates) |nm| {
        const data_opt = try tryLoadCorpus(a, nm);
        if (data_opt == null) {
            try o.print("  {s}: (not found, skipped)\n", .{nm});
            continue;
        }
        const data = data_opt.?;
        const full_chunks = std.math.divCeil(usize, data.len, CHUNK) catch 1;
        const views = try chunkIndices(a, data.len, null, HELD_MAX_CHUNKS);
        held_files += 1;
        const seed = spec.train_seed +% 1 ^ std.hash.Wyhash.hash(0, nm);

        const pair = try evalHeldOutPair(data, views, a, lib.items, seed, spec.budget);

        held_base += pair.base;
        held_no += pair.no_promo;
        held_ext += pair.self_ext;
        held_chunks += views.len;

        try o.print("  {s} ({d} bytes, {d}/{d} chunks evaluated)\n", .{ nm, data.len, views.len, full_chunks });
        try o.print("    base gzip     {d}\n", .{pair.base});
        try o.print("    no-promotion  {d}  ({d:.3}% vs base)\n", .{ pair.no_promo, pctSaved(pair.base, pair.no_promo) });
        try o.print("    self-extend   {d}  ({d:.3}% vs base, library={d})\n", .{
            pair.self_ext, pctSaved(pair.base, pair.self_ext), lib.items.len,
        });
        const cross = @as(isize, @intCast(pair.no_promo)) - @as(isize, @intCast(pair.self_ext));
        try o.print("    transfer delta (no-promo − self-extend): {d} bytes ({d:.3}%) {s}\n\n", .{
            cross,
            if (pair.no_promo > 0) pctSaved(pair.no_promo, pair.self_ext) else 0,
            if (cross > 0) "◄ library helped" else if (cross < 0) "◄ library hurt" else "◄ tie",
        });
    }

    if (held_files == 0) {
        try o.print("FAIL: no held-out files found\n", .{});
        try o.print("{s} pass=false bytes_saved=0 doc={s}\n", .{ spec.result_tag, spec.result_doc });
        return;
    }

    const bytes_saved: isize = @as(isize, @intCast(held_no)) - @as(isize, @intCast(held_ext));
    const cross_pct: f64 = if (held_no > 0) pctSaved(held_no, held_ext) else 0;
    const lib_ok = if (spec.pass.require_lib_nonempty) lib.items.len >= spec.pass.min_lib_macros else true;
    const pass = lib_ok and cross_pct > spec.pass.min_cross_pct and bytes_saved > 0;

    try o.print("════════════════════ VERDICT ════════════════════\n", .{});
    try o.print("{s} ({d} files, {d} chunks):\n", .{ spec.held_label, held_files, held_chunks });
    try o.print("  base gzip (identity)  {d}\n", .{held_base});
    try o.print("  no-promotion search   {d}  ({d:.3}% vs base)\n", .{ held_no, pctSaved(held_base, held_no) });
    try o.print("  self-extend (train)   {d}  ({d:.3}% vs base)\n", .{ held_ext, pctSaved(held_base, held_ext) });
    try o.print("\ntrain library: {d} macro(s)\n", .{lib.items.len});
    try o.print("bytes saved on {s} (no-promo − self-extend): {d}\n", .{ spec.held_label, bytes_saved });
    try o.print("cross-corpus transfer: {d:.3}% (pass bar >{d:.1}%, library>{d})\n", .{
        cross_pct, spec.pass.min_cross_pct, spec.pass.min_lib_macros,
    });
    try o.print("PASS/FAIL: {s}\n", .{if (pass) "PASS" else "FAIL"});

    if (pass) {
        try o.print("\nMacros from {s} transferred to structurally similar {s}: {d} bytes ({d:.3}%) at equal search budget.\n", .{
            train_name.?, spec.held_label, bytes_saved, cross_pct,
        });
    } else if (lib.items.len < spec.pass.min_lib_macros) {
        try o.print("\nHonest FAIL: train library {d} < {d} required — no structural macro beat gzip enough to promote.\n", .{
            lib.items.len, spec.pass.min_lib_macros,
        });
        if (bytes_saved > 0) try o.print("(Held-out delta {d} bytes is search stochasticity without a real library.)\n", .{bytes_saved});
    } else if (cross_pct <= spec.pass.min_cross_pct) {
        try o.print("\nHonest FAIL: library present but transfer {d:.3}% ≤ {d:.1}% bar — macros did not generalize.\n", .{
            cross_pct, spec.pass.min_cross_pct,
        });
    }

    try o.print("\nSee: {s}, self_extending_inventor.md, autonomous_inventor.md\n", .{spec.result_doc});
    try o.print("{s} pass={s} bytes_saved={d} library={d} transfer_pct={d:.3} doc={s}\n", .{
        spec.result_tag,
        if (pass) "true" else "false",
        bytes_saved,
        lib.items.len,
        cross_pct,
        spec.result_doc,
    });
}