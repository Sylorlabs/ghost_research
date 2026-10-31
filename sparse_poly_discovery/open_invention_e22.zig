//! E22 — Corpus runes v2 (execution traces).
//!
//! Terminal grind 200 safe commands → record execution traces → byte-pair rune forge (rune_native
//! ladder). After monomial forge saturates on the Boolean/zoo targets, compare:
//!   A) frozen symbolic menu (spectral / Walsh / Clifford)
//!   B) rune-augmented library (menu + trace-forged rune candidates)
//!
//! Question: do rune features from terminal execution traces invent grid primitives beyond the
//! handed menu — i.e. does the substrate the traces actually describe bridge to grid geometry?
//!
//! Pass bar: ≥+0.15 lift on T5 or T7 (rune-aug vs frozen-menu held-out accuracy).
//!
//! Reuses: open_invention_e7.zig protocol, terminal_grind/terminal_grind_big patterns, rune_native ladder.
//!
//! Run: zig build open-invention-e22 --release=fast
//!      zig build open-invention-e22 --release=fast -- --sim   (simulated traces, no shell)

const std = @import("std");
const oml = @import("operator_menu_lib.zig");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
const THETA: f64 = 0.40;
const NSAMP: usize = 7000;
const NTR: usize = 3500;
const NVA: usize = 5250;
const MAXATOMS: usize = 24;
const MAXOPS: usize = 12;
const MAXDEG: usize = 4;
const COVER: f64 = 0.90;
const R2_MAX: f64 = 0.40;

const MAX_BYTES: usize = 250_000;
const MERGES: usize = 400;
const MAX_RUNES: usize = 128;
const GRID_ENC_LEN: usize = NCELL * 2;

const REPO = "/home/micah/Desktop/Sylorlabs/ghost_research";
const GRIND_TARGET: usize = 200;
const TRACE_OUT_MAX: usize = 512;
const TRACE_ERR_MAX: usize = 256;
const PASS_LIFT: f64 = 0.15;
const T5_IDX: usize = 4;
const T7_IDX: usize = 6;
const SEED: u64 = 0xE7C0FF01CEE7; // same grid zoo as E7 for direct comparison

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn popcount(m: u8) usize {
    return @popCount(m);
}

fn lowerByte(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

// ── Target zoo (same 7 as unified_invention) ─────────────────────────────────

const TargetKind = enum {
    monomial_sign,
    parity_of_count,
    oriented,
    sum_mod,
};

const TargetSpec = struct {
    name: []const u8,
    kind: TargetKind,
    mask: u8 = 0,
    modulus: usize = 0,
};

const NT: usize = 7;
const TARGETS = [_]TargetSpec{
    .{ .name = "T1 sign φ{2,5}     (deg2)", .kind = .monomial_sign, .mask = (1 << 2) | (1 << 5) },
    .{ .name = "T2 sign φ{1,3,6}    (deg3)", .kind = .monomial_sign, .mask = (1 << 1) | (1 << 3) | (1 << 6) },
    .{ .name = "T3 sign φ{0,4,5,7}  (deg4)", .kind = .monomial_sign, .mask = (1 << 0) | (1 << 4) | (1 << 5) | (1 << 7) },
    .{ .name = "T4 sign(c3−MID)     (deg1)", .kind = .monomial_sign, .mask = (1 << 3) },
    .{ .name = "T5 parity-of-count  (≠mono)", .kind = .parity_of_count },
    .{ .name = "T6 oriented v1>v0   (≠mono)", .kind = .oriented },
    .{ .name = "T7 sum(g) % 7 = 0   (world)", .kind = .sum_mod, .modulus = 7 },
};

fn phi(g: [NCELL]u8, mask: u8) f64 {
    var p: f64 = 1.0;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) != 0) p *= (@as(f64, @floatFromInt(g[i])) - MID);
    }
    return p;
}

fn signPattern(g: [NCELL]u8) u8 {
    var p: u8 = 0;
    for (0..NCELL) |i| {
        if (g[i] >= THRESH) p |= @as(u8, 1) << @intCast(i);
    }
    return p;
}

fn countGE(g: [NCELL]u8) f64 {
    var c: usize = 0;
    for (g) |v| if (v >= THRESH) {
        c += 1;
    };
    return @floatFromInt(c);
}

fn gridSum(g: [NCELL]u8) usize {
    var s: usize = 0;
    for (g) |v| s += v;
    return s;
}

fn cliffordG2(g: [NCELL]u8) f64 {
    const v0: f64 = @floatFromInt(g[0]);
    const v1: f64 = @floatFromInt(g[1]);
    return @sin(THETA * (v1 - v0));
}

fn label(g: [NCELL]u8, spec: TargetSpec) f64 {
    return switch (spec.kind) {
        .monomial_sign => if (phi(g, spec.mask) > 0) 1.0 else 0.0,
        .parity_of_count => blk: {
            var c: usize = 0;
            for (g) |v| if (v >= THRESH) {
                c += 1;
            };
            break :blk @floatFromInt(c & 1);
        },
        .oriented => if (g[1] > g[0]) 1.0 else 0.0,
        .sum_mod => if (gridSum(g) % spec.modulus == 0) 1.0 else 0.0,
    };
}

// ── Terminal grind: 200 safe commands → execution trace bytes ────────────────

const SAFE_PREFIXES = [_][]const u8{
    "test", "ls",     "echo",   "false",  "true",   "pwd",    "wc",      "head",
    "grep", "cat",    "find",   "date",   "whoami", "sort",   "uniq",    "tr",
    "cut",  "stat",   "id",     "uname",  "expr",   "printf", "readlink",
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
    stdout: []const u8,
    stderr: []const u8,
};

fn simSig(alloc: std.mem.Allocator, cmd: []const u8) !RunSig {
    const failish = std.mem.indexOf(u8, cmd, "zzz") != null or
        std.mem.indexOf(u8, cmd, "no_dir") != null or
        std.mem.eql(u8, cmd, "false") or
        std.mem.indexOf(u8, cmd, "bogus") != null;
    if (failish) return .{ .exit_ok = false, .time_ms = 3, .stdout = "", .stderr = "err" };
    if (std.mem.indexOf(u8, cmd, "wc -l") != null or std.mem.indexOf(u8, cmd, "| wc -l") != null)
        return .{ .exit_ok = true, .time_ms = 80, .stdout = try alloc.dupe(u8, "42"), .stderr = "" };
    if (std.mem.startsWith(u8, cmd, "ls -1") or std.mem.startsWith(u8, cmd, "ls *.zig"))
        return .{ .exit_ok = true, .time_ms = 40, .stdout = try alloc.dupe(u8, "a.zig\nb.zig\n"), .stderr = "" };
    if (std.mem.startsWith(u8, cmd, "test -f") or std.mem.startsWith(u8, cmd, "grep -q"))
        return .{ .exit_ok = true, .time_ms = 5, .stdout = "", .stderr = "" };
    if (std.mem.startsWith(u8, cmd, "echo") or std.mem.eql(u8, cmd, "pwd") or std.mem.startsWith(u8, cmd, "head"))
        return .{ .exit_ok = true, .time_ms = 5, .stdout = try alloc.dupe(u8, "hello\n"), .stderr = "" };
    if (std.mem.startsWith(u8, cmd, "stat") or std.mem.startsWith(u8, cmd, "readlink"))
        return .{ .exit_ok = true, .time_ms = 8, .stdout = try alloc.dupe(u8, "4096\n"), .stderr = "" };
    return .{ .exit_ok = true, .time_ms = 6, .stdout = try alloc.dupe(u8, "ok\n"), .stderr = "" };
}

fn runLive(alloc: std.mem.Allocator, cmd: []const u8) !RunSig {
    const t0 = std.time.nanoTimestamp();
    const res = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "sh", "-c", cmd },
        .max_output_bytes = 1 << 20,
    }) catch {
        const t1 = std.time.nanoTimestamp();
        return .{
            .exit_ok = false,
            .time_ms = @intCast(@max(0, @divTrunc(t1 - t0, std.time.ns_per_ms))),
            .stdout = "",
            .stderr = "",
        };
    };
    return .{
        .exit_ok = switch (res.term) {
            .Exited => |c| c == 0,
            else => false,
        },
        .time_ms = @intCast(@max(0, @divTrunc(std.time.nanoTimestamp() - t0, std.time.ns_per_ms))),
        .stdout = res.stdout,
        .stderr = res.stderr,
    };
}

fn appendTrace(alloc: std.mem.Allocator, buf: *std.ArrayList(u8), cmd: []const u8, sig: RunSig) !void {
    try buf.appendSlice(">");
    try buf.appendSlice(cmd);
    try buf.append('\n');
    const exit_code: u8 = if (sig.exit_ok) 0 else 1;
    try buf.writer().print("!{d}\n", .{exit_code});
    try buf.writer().print("t{d}\n", .{sig.time_ms});
    try buf.append('#');
    const out_take = @min(sig.stdout.len, TRACE_OUT_MAX);
    try buf.appendSlice(sig.stdout[0..out_take]);
    try buf.append('\n');
    try buf.append('$');
    const err_take = @min(sig.stderr.len, TRACE_ERR_MAX);
    try buf.appendSlice(sig.stderr[0..err_take]);
    try buf.append('\n');
    _ = alloc;
}

fn buildGrindCommands(alloc: std.mem.Allocator) ![]const []const u8 {
    var list = std.ArrayList([]const u8).init(alloc);

    const fail_pre = [_][]const u8{ "open the", "find the", "run the", "look for the", "use the", "access the", "load the", "probe the", "hunt the", "strike the" };
    const fail_obj = [_][]const u8{ "missing doc target", "failing script probe", "absent directory route", "bogus search needle", "vanished text artifact", "phantom config file" };
    const fail_cmd = [_][]const u8{
        "test -f zzz_missing_e22.xyz",
        "false",
        "ls /zzz_no_dir_e22 2>/dev/null",
        "grep -q zzznotfound_e22 " ++ REPO ++ "/README.md",
        "cat zzz_absent_e22.xyz 2>/dev/null",
    };

    const empty_pre = [_][]const u8{ "check the", "verify the", "confirm the", "make sure the", "ensure the", "is there a", "validate the", "assert the" };
    const empty_obj = [_][]const u8{ "readme on disk", "build on disk", "readme body on disk", "build script present", "readme still around" };
    const empty_cmd = [_][]const u8{
        "test -f " ++ REPO ++ "/README.md",
        "test -f " ++ REPO ++ "/sparse_poly_discovery/build.zig",
        "grep -q the " ++ REPO ++ "/README.md",
    };

    const num_pre = [_][]const u8{ "count the", "how many", "number of", "tally the", "give me the count of", "whats the total of", "report the number of", "quantify the" };
    const num_obj = [_][]const u8{ "zig sources", "research docs", "build lines", "zig modules", "markdown notes" };
    const num_cmd = [_][]const u8{
        "ls " ++ REPO ++ "/sparse_poly_discovery/*.zig | wc -l",
        "ls " ++ REPO ++ "/sparse_poly_discovery/docs/research/*.md | wc -l",
        "wc -l < " ++ REPO ++ "/sparse_poly_discovery/build.zig",
        "ls " ++ REPO ++ "/boundary_crossing/*.zig | wc -l",
    };

    const list_pre = [_][]const u8{ "list the", "show me the", "display the", "whats in the", "give me the", "enumerate the", "what are the", "catalog the" };
    const list_obj = [_][]const u8{ "zig sources", "research docs", "directory files", "boundary sources", "sparse sources" };
    const list_cmd = [_][]const u8{
        "ls -1 " ++ REPO ++ "/sparse_poly_discovery/*.zig",
        "ls -1 " ++ REPO ++ "/sparse_poly_discovery/docs/research",
        "ls -1 " ++ REPO ++ "/boundary_crossing",
    };

    const text_pre = [_][]const u8{ "print a", "echo a", "say a", "show the", "tell me the", "what is the", "utter a", "voice a" };
    const text_obj = [_][]const u8{ "hello greeting", "working directory path", "first readme line", "build first line", "project greeting", "salutation banner" };
    const text_cmd = [_][]const u8{
        "echo hello_e22_trace",
        "pwd",
        "head -1 " ++ REPO ++ "/README.md",
    };

    const meta_pre = [_][]const u8{ "inspect the", "read the", "fetch the", "report the", "describe the", "probe the", "audit the", "examine the" };
    const meta_obj = [_][]const u8{ "readme byte size", "build byte size", "readme symlink target", "readme inode status", "build inode status", "readme metadata" };
    const meta_cmd = [_][]const u8{
        "stat -c %s " ++ REPO ++ "/README.md",
        "stat -c %s " ++ REPO ++ "/sparse_poly_discovery/build.zig",
        "readlink -f " ++ REPO ++ "/README.md",
        "stat " ++ REPO ++ "/README.md",
    };

    var ci: usize = 0;
    outer: for (fail_pre) |_| for (fail_obj) |_| {
        if (list.items.len >= GRIND_TARGET) break :outer;
        try list.append(fail_cmd[ci % fail_cmd.len]);
        ci += 1;
    };
    ci = 0;
    outer: for (empty_pre) |_| for (empty_obj) |_| {
        if (list.items.len >= GRIND_TARGET) break :outer;
        try list.append(empty_cmd[ci % empty_cmd.len]);
        ci += 1;
    };
    ci = 0;
    outer: for (num_pre) |_| for (num_obj) |_| {
        if (list.items.len >= GRIND_TARGET) break :outer;
        try list.append(num_cmd[ci % num_cmd.len]);
        ci += 1;
    };
    ci = 0;
    outer: for (list_pre) |_| for (list_obj) |_| {
        if (list.items.len >= GRIND_TARGET) break :outer;
        try list.append(list_cmd[ci % list_cmd.len]);
        ci += 1;
    };
    ci = 0;
    outer: for (text_pre) |_| for (text_obj) |_| {
        if (list.items.len >= GRIND_TARGET) break :outer;
        try list.append(text_cmd[ci % text_cmd.len]);
        ci += 1;
    };
    ci = 0;
    outer: for (meta_pre) |_| for (meta_obj) |_| {
        if (list.items.len >= GRIND_TARGET) break :outer;
        try list.append(meta_cmd[ci % meta_cmd.len]);
        ci += 1;
    };

    // Pad with extra safe probes if cross-product fell short of 200.
    const extras = [_][]const u8{
        "whoami",
        "date +%s",
        "uname -s",
        "id -u",
        "expr 2 + 2",
        "printf '%d\\n' 7",
        "ls -1 " ++ REPO ++ "/corpus",
        "wc -c < " ++ REPO ++ "/README.md",
        "find " ++ REPO ++ "/sparse_poly_discovery -maxdepth 1 -name '*.zig' | wc -l",
        "grep -c zig " ++ REPO ++ "/sparse_poly_discovery/build.zig",
        "cut -c1-5 " ++ REPO ++ "/README.md",
        "sort " ++ REPO ++ "/sparse_poly_discovery/build.zig | head -3",
        "uniq " ++ REPO ++ "/sparse_poly_discovery/build.zig | head -3",
        "tr a-z A-Z <<< hello",
        "cat " ++ REPO ++ "/sparse_poly_discovery/build.zig | head -2",
        "true",
        "echo trace_pad_16",
        "echo trace_pad_17",
        "echo trace_pad_18",
        "echo trace_pad_19",
    };
    for (extras) |cmd| {
        if (list.items.len >= GRIND_TARGET) break;
        try list.append(cmd);
    }

    return try list.toOwnedSlice();
}

fn grindTraces(alloc: std.mem.Allocator, live_mode: bool) !struct { corpus: []u8, n_ran: usize, n_ok: usize } {
    const cmds = try buildGrindCommands(alloc);
    var buf = std.ArrayList(u8).init(alloc);
    var n_ok: usize = 0;
    for (cmds[0..@min(cmds.len, GRIND_TARGET)]) |cmd| {
        if (!isSafeCmd(cmd)) continue;
        const sig = if (live_mode) blk: {
            const s = try runLive(alloc, cmd);
            break :blk s;
        } else try simSig(alloc, cmd);
        if (sig.exit_ok) n_ok += 1;
        try appendTrace(alloc, &buf, cmd, sig);
    }
    return .{ .corpus = try buf.toOwnedSlice(), .n_ran = @min(cmds.len, GRIND_TARGET), .n_ok = n_ok };
}

// ── Grid byte encoding for rune matching ─────────────────────────────────────

fn gridEncode(g: [NCELL]u8, buf: *[GRID_ENC_LEN]u8) []const u8 {
    var w: usize = 0;
    for (g) |v| {
        buf[w] = '0' + v;
        w += 1;
        buf[w] = ',';
        w += 1;
    }
    return buf[0..w];
}

fn substringCount(hay: []const u8, needle: []const u8) f64 {
    if (needle.len == 0 or hay.len < needle.len) return 0;
    var c: usize = 0;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        if (std.mem.eql(u8, hay[i..][0..needle.len], needle)) c += 1;
    }
    return @floatFromInt(c);
}

// ── Corpus rune forge (byte-pair promotion ladder) ───────────────────────────

const Rune = struct {
    id: u32,
    expansion: []const u8,
    forge_count: u32,
};

fn forgeRunes(alloc: std.mem.Allocator, raw: []const u8) !struct { runes: []Rune, n_forged: usize } {
    const n0 = @min(raw.len, MAX_BYTES);
    var seq = try alloc.alloc(u32, n0);
    for (0..n0) |i| seq[i] = lowerByte(raw[i]);

    var bytetab: [256]u8 = undefined;
    for (0..256) |i| bytetab[i] = @intCast(i);
    var vocab = std.ArrayList([]const u8).init(alloc);
    for (0..256) |i| try vocab.append(bytetab[i .. i + 1]);

    const Merge = struct { id: u32, count: u32 };
    var order = std.ArrayList(Merge).init(alloc);
    var pairs = std.AutoHashMap(u64, u32).init(alloc);
    var len: usize = n0;

    var m: usize = 0;
    while (m < MERGES) : (m += 1) {
        pairs.clearRetainingCapacity();
        var i: usize = 0;
        while (i + 1 < len) : (i += 1) {
            const key = (@as(u64, seq[i]) << 32) | @as(u64, seq[i + 1]);
            const e = try pairs.getOrPut(key);
            if (!e.found_existing) e.value_ptr.* = 0;
            e.value_ptr.* += 1;
        }
        var best_key: u64 = 0;
        var best_c: u32 = 1;
        var it = pairs.iterator();
        while (it.next()) |e| {
            if (e.value_ptr.* > best_c) {
                best_c = e.value_ptr.*;
                best_key = e.key_ptr.*;
            }
        }
        if (best_c < 2) break;

        const av: u32 = @intCast(best_key >> 32);
        const bv: u32 = @intCast(best_key & 0xffffffff);
        const newid: u32 = @intCast(vocab.items.len);
        const exp = try std.mem.concat(alloc, u8, &.{ vocab.items[av], vocab.items[bv] });
        try vocab.append(exp);
        try order.append(.{ .id = newid, .count = best_c });

        var w: usize = 0;
        var r: usize = 0;
        while (r < len) {
            if (r + 1 < len and seq[r] == av and seq[r + 1] == bv) {
                seq[w] = newid;
                w += 1;
                r += 2;
            } else {
                seq[w] = seq[r];
                w += 1;
                r += 1;
            }
        }
        len = w;
    }

    const take = @min(order.items.len, MAX_RUNES);
    const runes = try alloc.alloc(Rune, take);
    for (0..take) |i| {
        const mg = order.items[i];
        runes[i] = .{
            .id = mg.id,
            .expansion = vocab.items[mg.id],
            .forge_count = mg.count,
        };
    }
    return .{ .runes = runes, .n_forged = order.items.len };
}

fn evalRune(rune: Rune, g: [NCELL]u8, enc_buf: *[GRID_ENC_LEN]u8) f64 {
    const enc = gridEncode(g, enc_buf);
    return substringCount(enc, rune.expansion);
}

// ── Feature library: monomials + symbolic ops + runes ──────────────────────────

const OpKind = enum { spectral, walsh, clifford, rune };

const PromotedOp = struct {
    kind: OpKind,
    omega: f64 = 0,
    walsh_s: u8 = 0,
    rune_idx: usize = 0,

    pub fn eval(self: PromotedOp, g: [NCELL]u8, enc_buf: *[GRID_ENC_LEN]u8, runes: []const Rune) f64 {
        return switch (self.kind) {
            .spectral => @cos(self.omega * countGE(g)),
            .walsh => oml.chi(self.walsh_s, signPattern(g)),
            .clifford => cliffordG2(g),
            .rune => evalRune(runes[self.rune_idx], g, enc_buf),
        };
    }
};

fn buildFeat(
    X: [][]f64,
    grid: []const [NCELL]u8,
    masks: []const u8,
    ops: []const PromotedOp,
    runes: []const Rune,
    enc_bufs: [][GRID_ENC_LEN]u8,
) void {
    const nm = masks.len;
    const k = nm + ops.len;
    for (0..NSAMP) |s| {
        for (0..nm) |c| X[s][c] = phi(grid[s], masks[c]);
        for (0..ops.len) |c| X[s][nm + c] = ops[c].eval(grid[s], &enc_bufs[s], runes);
    }
    for (0..k) |c| {
        var mu: f64 = 0;
        for (0..NTR) |s| mu += X[s][c];
        mu /= @floatFromInt(NTR);
        var sd: f64 = 0;
        for (0..NTR) |s| sd += (X[s][c] - mu) * (X[s][c] - mu);
        sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
        for (0..NSAMP) |s| X[s][c] = (X[s][c] - mu) / sd;
    }
}

fn fitLogit(X: []const []f64, Y: []const f64, dim: usize, epochs: usize, lr: f64, w: []f64) void {
    @memset(w[0 .. dim + 1], 0);
    for (0..epochs) |_| for (0..NTR) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        const e = sigmoid(z) - Y[s];
        for (0..dim) |j| w[j] -= lr * e * X[s][j];
        w[dim] -= lr * e;
    };
}

fn accLogit(X: []const []f64, Y: []const f64, w: []const f64, dim: usize, from: usize, hi: usize) f64 {
    var c: usize = 0;
    for (from..hi) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        if ((z >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(hi - from));
}

fn reconR2(X: []const []f64, t: []const f64, dim: usize, w: []f64) f64 {
    @memset(w[0 .. dim + 1], 0);
    for (0..400) |_| for (0..NTR) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        const e = z - t[s];
        for (0..dim) |j| w[j] -= 0.01 * e * X[s][j];
        w[dim] -= 0.01 * e;
    };
    var mu: f64 = 0;
    for (NVA..NSAMP) |s| mu += t[s];
    mu /= @floatFromInt(NSAMP - NVA);
    var ssr: f64 = 0;
    var sst: f64 = 0;
    for (NVA..NSAMP) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        ssr += (t[s] - z) * (t[s] - z);
        sst += (t[s] - mu) * (t[s] - mu);
    }
    return 1.0 - ssr / @max(1e-9, sst);
}

fn coverage(
    X: [][]f64,
    grid: []const [NCELL]u8,
    masks: []const u8,
    ops: []const PromotedOp,
    Y: []const f64,
    runes: []const Rune,
    enc_bufs: [][GRID_ENC_LEN]u8,
    w: []f64,
) f64 {
    buildFeat(X, grid, masks, ops, runes, enc_bufs);
    const dim = masks.len + ops.len;
    fitLogit(X, Y, dim, 150, 0.05, w);
    return accLogit(X, Y, w, dim, NVA, NSAMP);
}

// ── Monomial forge (shared substrate) ────────────────────────────────────────

fn monomialForge(
    X: [][]f64,
    grid: []const [NCELL]u8,
    atoms: []u8,
    natoms: *usize,
    ops: []const PromotedOp,
    Y: []const []f64,
    solved: []bool,
    runes: []const Rune,
    enc_bufs: [][GRID_ENC_LEN]u8,
    phiTgt: []f64,
    w: []f64,
) void {
    var round: usize = 0;
    while (round < 8) : (round += 1) {
        var promoted = false;
        for (0..NT) |t| {
            if (solved[t]) continue;
            const cov_now = coverage(X, grid, atoms[0..natoms.*], ops, Y[t], runes, enc_bufs, w);
            if (cov_now >= COVER) {
                solved[t] = true;
                continue;
            }
            var best_val: f64 = -1;
            var best_mask: u8 = 0;
            var mm: u16 = 1;
            while (mm < 256) : (mm += 1) {
                const cand: u8 = @intCast(mm);
                const d = popcount(cand);
                if (d < 1 or d > MAXDEG) continue;
                var is_atom = false;
                for (0..natoms.*) |a| if (atoms[a] == cand) {
                    is_atom = true;
                };
                if (is_atom) continue;
                for (0..NSAMP) |s| X[s][0] = phi(grid[s], cand);
                for (0..1) |c| {
                    var mu: f64 = 0;
                    for (0..NTR) |s| mu += X[s][c];
                    mu /= @floatFromInt(NTR);
                    var sd: f64 = 0;
                    for (0..NTR) |s| sd += (X[s][c] - mu) * (X[s][c] - mu);
                    sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
                    for (0..NSAMP) |s| X[s][c] = (X[s][c] - mu) / sd;
                }
                fitLogit(X, Y[t], 1, 70, 0.06, w);
                const v = accLogit(X, Y[t], w, 1, NTR, NVA);
                if (v > best_val) {
                    best_val = v;
                    best_mask = cand;
                }
            }
            const aug = natoms.*;
            atoms[aug] = best_mask;
            const cov_aug = coverage(X, grid, atoms[0 .. aug + 1], ops, Y[t], runes, enc_bufs, w);
            const escape = cov_aug >= COVER and cov_now < 0.70;
            for (0..NSAMP) |s| phiTgt[s] = phi(grid[s], best_mask);
            buildFeat(X, grid, atoms[0..natoms.*], ops, runes, enc_bufs);
            const rr = reconR2(X, phiTgt, natoms.* + ops.len, w);
            if (escape and rr < R2_MAX) {
                natoms.* += 1;
                solved[t] = true;
                promoted = true;
            }
        }
        if (!promoted) break;
    }
}

// ── Frozen symbolic menu (spectral + Walsh + Clifford) ───────────────────────

fn frozenMenuCandidate(
    grid: []const [NCELL]u8,
    Y: []const f64,
    feat_scratch: []f64,
) PromotedOp {
    const spec = oml.discoverSpectral(grid, Y, feat_scratch, NTR, NVA, NSAMP);
    const wal = oml.discoverWalsh(grid, Y, feat_scratch, NTR, NVA, NSAMP);
    for (0..NSAMP) |s| feat_scratch[s] = cliffordG2(grid[s]);
    const clf_val = oml.accLogit(feat_scratch, Y, NTR, NTR, NVA);

    const vals = [_]f64{ spec.val, wal.val, clf_val };
    var best: usize = 0;
    for (1..3) |k| {
        if (vals[k] > vals[best]) best = k;
    }
    return switch (best) {
        0 => .{ .kind = .spectral, .omega = spec.omega },
        1 => .{ .kind = .walsh, .walsh_s = wal.bestS },
        else => .{ .kind = .clifford },
    };
}

fn tryFrozenMenu(
    X: [][]f64,
    grid: []const [NCELL]u8,
    atoms: []const u8,
    ops: []PromotedOp,
    nops: *usize,
    Y: []const f64,
    runes: []const Rune,
    enc_bufs: [][GRID_ENC_LEN]u8,
    feat_scratch: []f64,
    phiTgt: []f64,
    w: []f64,
) bool {
    const cov_now = coverage(X, grid, atoms, ops[0..nops.*], Y, runes, enc_bufs, w);
    if (cov_now >= COVER) return false;

    const cand = frozenMenuCandidate(grid, Y, feat_scratch);
    for (0..nops.*) |i| {
        if (ops[i].kind == cand.kind and
            (cand.kind != .spectral or @abs(ops[i].omega - cand.omega) < 1e-4) and
            (cand.kind != .walsh or ops[i].walsh_s == cand.walsh_s))
            return false;
    }

    var trial: [MAXOPS]PromotedOp = undefined;
    @memcpy(trial[0..nops.*], ops[0..nops.*]);
    trial[nops.*] = cand;
    const cov_aug = coverage(X, grid, atoms, trial[0 .. nops.* + 1], Y, runes, enc_bufs, w);
    for (0..NSAMP) |s| phiTgt[s] = cand.eval(grid[s], &enc_bufs[s], runes);
    buildFeat(X, grid, atoms, ops[0..nops.*], runes, enc_bufs);
    const rr = reconR2(X, phiTgt, atoms.len + nops.*, w);
    const escape = cov_aug >= COVER and cov_now < COVER;
    if (escape and rr < R2_MAX) {
        ops[nops.*] = cand;
        nops.* += 1;
        return true;
    }
    return false;
}

// ── Rune menu: argmax corpus-forged rune on validation ───────────────────────

fn bestRuneCandidate(
    grid: []const [NCELL]u8,
    Y: []const f64,
    runes: []const Rune,
    enc_bufs: [][GRID_ENC_LEN]u8,
    feat_scratch: []f64,
) struct { idx: usize, val: f64, tst: f64 } {
    var best_idx: usize = 0;
    var best_val: f64 = -1;
    for (runes, 0..) |_, ri| {
        for (0..NSAMP) |s| feat_scratch[s] = evalRune(runes[ri], grid[s], &enc_bufs[s]);
        const v = oml.accLogit(feat_scratch, Y, NTR, NTR, NVA);
        if (v > best_val) {
            best_val = v;
            best_idx = ri;
        }
    }
    for (0..NSAMP) |s| feat_scratch[s] = evalRune(runes[best_idx], grid[s], &enc_bufs[s]);
    const tst = oml.accLogit(feat_scratch, Y, NTR, NVA, NSAMP);
    return .{ .idx = best_idx, .val = best_val, .tst = tst };
}

fn tryRuneEscape(
    X: [][]f64,
    grid: []const [NCELL]u8,
    atoms: []const u8,
    ops: []PromotedOp,
    nops: *usize,
    Y: []const f64,
    runes: []const Rune,
    enc_bufs: [][GRID_ENC_LEN]u8,
    feat_scratch: []f64,
    phiTgt: []f64,
    w: []f64,
) ?struct { idx: usize, tst: f64 } {
    const cov_now = coverage(X, grid, atoms, ops[0..nops.*], Y, runes, enc_bufs, w);
    if (cov_now >= COVER) return null;

    const br = bestRuneCandidate(grid, Y, runes, enc_bufs, feat_scratch);
    const cand: PromotedOp = .{ .kind = .rune, .rune_idx = br.idx };

    for (0..nops.*) |i| {
        if (ops[i].kind == .rune and ops[i].rune_idx == br.idx) return null;
    }

    var trial: [MAXOPS]PromotedOp = undefined;
    @memcpy(trial[0..nops.*], ops[0..nops.*]);
    trial[nops.*] = cand;
    const cov_aug = coverage(X, grid, atoms, trial[0 .. nops.* + 1], Y, runes, enc_bufs, w);
    for (0..NSAMP) |s| phiTgt[s] = evalRune(runes[br.idx], grid[s], &enc_bufs[s]);
    buildFeat(X, grid, atoms, ops[0..nops.*], runes, enc_bufs);
    const rr = reconR2(X, phiTgt, atoms.len + nops.*, w);
    const escape = cov_aug >= COVER and cov_now < COVER;
    if (escape and rr < R2_MAX and br.tst >= COVER) {
        ops[nops.*] = cand;
        nops.* += 1;
        return .{ .idx = br.idx, .tst = br.tst };
    }
    return null;
}

fn showRune(out: anytype, s: []const u8) !void {
    for (s) |c| {
        if (c == ' ') try out.print("·", .{}) else if (c < 32 or c > 126) try out.print("?", .{}) else try out.print("{c}", .{c});
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var live_mode = true;
    var argit = try std.process.argsWithAllocator(alloc);
    _ = argit.next();
    while (argit.next()) |arg| {
        if (std.mem.eql(u8, arg, "--live")) live_mode = true;
        if (std.mem.eql(u8, arg, "--sim")) live_mode = false;
    }

    try out.print("=== E22: Corpus runes v2 (execution traces) ===\n\n", .{});
    try out.print("Protocol: terminal grind {d} commands → trace bytes → rune forge → Boolean/zoo forge.\n", .{GRIND_TARGET});
    try out.print("Mode: {s} | Pass bar: ≥+{d:.2} on T5 or T7 (rune-aug vs frozen-menu).\n", .{
        if (live_mode) "LIVE" else "SIM",
        PASS_LIFT,
    });
    try out.print("Certifier: escape ≥{d:.2} held-out AND irreducible R²<{d:.2}.\n", .{ COVER, R2_MAX });
    try out.print("train/val/test {d}/{d}/{d}  seed=0x{X}\n\n", .{ NTR, NVA - NTR, NSAMP - NVA, SEED });

    try out.print("── Phase 0: terminal grind ({d} safe commands) ──\n", .{GRIND_TARGET});
    const grind = try grindTraces(alloc, live_mode);
    try out.print("  ran {d} commands ({d} exit_ok); trace corpus {d} bytes\n\n", .{
        grind.n_ran, grind.n_ok, grind.corpus.len,
    });

    const raw = grind.corpus;
    const forged = try forgeRunes(alloc, raw);
    try out.print("Rune forge: {d} promotions on {d} bytes; library top-{d} runes for menu.\n", .{
        forged.n_forged,
        @min(raw.len, MAX_BYTES),
        forged.runes.len,
    });
    try out.print("First forged runes: ", .{});
    for (forged.runes[0..@min(8, forged.runes.len)]) |r| {
        try showRune(out, r.expansion);
        try out.print(" ", .{});
    }
    try out.print("\n\n", .{});

    var prng = std.Random.DefaultPrng.init(SEED);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    };

    const enc_bufs = try alloc.alloc([GRID_ENC_LEN]u8, NSAMP);
    for (0..NSAMP) |s| _ = gridEncode(grid[s], &enc_bufs[s]);

    const Y = try alloc.alloc([]f64, NT);
    for (0..NT) |t| {
        Y[t] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Y[t][s] = label(grid[s], TARGETS[t]);
    }

    const X = try alloc.alloc([]f64, NSAMP);
    const phiTgt = try alloc.alloc(f64, NSAMP);
    const feat_scratch = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, MAXATOMS + MAXOPS);

    var w: [MAXATOMS + MAXOPS + 1]f64 = undefined;
    const empty_ops = &[_]PromotedOp{};

    // ── Phase 1: monomial forge to saturation (no ops) ──
    var atoms_base: [MAXATOMS]u8 = undefined;
    var natoms_base: usize = 0;
    for (0..NCELL) |i| {
        atoms_base[natoms_base] = @as(u8, 1) << @intCast(i);
        natoms_base += 1;
    }
    var mono_solved = [_]bool{false} ** NT;
    var mono_cov: [NT]f64 = .{0} ** NT;
    monomialForge(X, grid, &atoms_base, &natoms_base, empty_ops, Y, &mono_solved, forged.runes, enc_bufs, phiTgt, &w);
    var mono_nsolved: usize = 0;
    for (0..NT) |t| {
        mono_cov[t] = coverage(X, grid, atoms_base[0..natoms_base], empty_ops, Y[t], forged.runes, enc_bufs, &w);
        if (mono_cov[t] >= COVER) mono_nsolved += 1;
    }

    try out.print("── Phase 1: monomial forge saturation ──\n", .{});
    for (0..NT) |t| {
        try out.print("  {s}: {d:.3}{s}\n", .{ TARGETS[t].name, mono_cov[t], if (mono_cov[t] >= COVER) " *" else "" });
    }
    try out.print("  → {d}/{d} solved; atoms {d}\n\n", .{ mono_nsolved, NT, natoms_base });

    // ── Phase 2A: frozen symbolic menu only ──
    var atoms_a: [MAXATOMS]u8 = undefined;
    @memcpy(atoms_a[0..natoms_base], atoms_base[0..natoms_base]);
    const natoms_a = natoms_base;
    var ops_a: [MAXOPS]PromotedOp = undefined;
    var nops_a: usize = 0;
    var menu_cov: [NT]f64 = .{0} ** NT;
    var menu_solved = [_]bool{false} ** NT;
    for (0..NT) |t| menu_solved[t] = mono_cov[t] >= COVER;

    try out.print("── Phase 2A: frozen symbolic menu (spectral / Walsh / Clifford) ──\n", .{});
    for (0..NT) |t| {
        if (menu_solved[t]) {
            menu_cov[t] = mono_cov[t];
            continue;
        }
        const cov_before = coverage(X, grid, atoms_a[0..natoms_a], ops_a[0..nops_a], Y[t], forged.runes, enc_bufs, &w);
        if (tryFrozenMenu(X, grid, atoms_a[0..natoms_a], &ops_a, &nops_a, Y[t], forged.runes, enc_bufs, feat_scratch, phiTgt, &w)) {
            menu_cov[t] = coverage(X, grid, atoms_a[0..natoms_a], ops_a[0..nops_a], Y[t], forged.runes, enc_bufs, &w);
            menu_solved[t] = menu_cov[t] >= COVER;
            const op = ops_a[nops_a - 1];
            const tag = switch (op.kind) {
                .spectral => "spectral",
                .walsh => "walsh",
                .clifford => "clifford",
                else => "?",
            };
            try out.print("  {s}: {d:.3}→{d:.3} via {s} → PROMOTE\n", .{ TARGETS[t].name, cov_before, menu_cov[t], tag });
        } else {
            menu_cov[t] = cov_before;
            try out.print("  {s}: {d:.3} — menu did not certify\n", .{ TARGETS[t].name, cov_before });
        }
    }
    var menu_nsolved: usize = 0;
    for (0..NT) |t| {
        if (menu_cov[t] >= COVER) menu_nsolved += 1;
    }
    try out.print("  → {d}/{d} solved; atoms {d} + ops {d}\n\n", .{ menu_nsolved, NT, natoms_a, nops_a });

    // ── Phase 2B: rune-augmented library (menu + corpus runes) ──
    var atoms_b: [MAXATOMS]u8 = undefined;
    @memcpy(atoms_b[0..natoms_base], atoms_base[0..natoms_base]);
    const natoms_b = natoms_base;
    var ops_b: [MAXOPS]PromotedOp = undefined;
    var nops_b: usize = 0;
    var rune_cov: [NT]f64 = .{0} ** NT;
    var rune_solved = [_]bool{false} ** NT;
    for (0..NT) |t| rune_solved[t] = mono_cov[t] >= COVER;

    try out.print("── Phase 2B: rune-augmented library (menu + trace runes) ──\n", .{});
    for (0..NT) |t| {
        if (rune_solved[t]) {
            rune_cov[t] = mono_cov[t];
            continue;
        }
        var cov = coverage(X, grid, atoms_b[0..natoms_b], ops_b[0..nops_b], Y[t], forged.runes, enc_bufs, &w);
        const cov0 = cov;

        // first try frozen menu
        _ = tryFrozenMenu(X, grid, atoms_b[0..natoms_b], &ops_b, &nops_b, Y[t], forged.runes, enc_bufs, feat_scratch, phiTgt, &w);
        cov = coverage(X, grid, atoms_b[0..natoms_b], ops_b[0..nops_b], Y[t], forged.runes, enc_bufs, &w);

        // then try rune escape on remaining gap
        const rune_hit = tryRuneEscape(X, grid, atoms_b[0..natoms_b], &ops_b, &nops_b, Y[t], forged.runes, enc_bufs, feat_scratch, phiTgt, &w);
        cov = coverage(X, grid, atoms_b[0..natoms_b], ops_b[0..nops_b], Y[t], forged.runes, enc_bufs, &w);
        rune_cov[t] = cov;
        rune_solved[t] = cov >= COVER;

        if (rune_hit) |rh| {
            try out.print("  {s}: {d:.3}→{d:.3} via RUNE[", .{ TARGETS[t].name, cov0, cov });
            try showRune(out, forged.runes[rh.idx].expansion);
            try out.print("] test={d:.3} → PROMOTE\n", .{rh.tst});
        } else if (cov >= COVER and cov0 < COVER) {
            const op = ops_b[nops_b - 1];
            const tag = switch (op.kind) {
                .spectral => "spectral",
                .walsh => "walsh",
                .clifford => "clifford",
                else => "rune",
            };
            try out.print("  {s}: {d:.3}→{d:.3} via {s} → PROMOTE\n", .{ TARGETS[t].name, cov0, cov, tag });
        } else {
            try out.print("  {s}: {d:.3} — no certified escape (menu+rune)\n", .{ TARGETS[t].name, cov });
        }
    }
    var rune_nsolved: usize = 0;
    for (0..NT) |t| {
        if (rune_cov[t] >= COVER) rune_nsolved += 1;
    }
    try out.print("  → {d}/{d} solved; atoms {d} + ops {d}\n\n", .{ rune_nsolved, NT, natoms_b, nops_b });

    // ── Comparison table ──
    try out.print("════════════════════ LIFT TABLE ════════════════════\n", .{});
    try out.print("{s:<32} | mono | frozen-menu | rune-aug | d_menu | d_rune\n", .{"target"});
    try out.print("{s}\n", .{"--------------------------------+------+-------------+----------+---------+---------"});
    var lift_menu: usize = 0;
    var lift_rune: usize = 0;
    var lift_rune_only: usize = 0;
    for (0..NT) |t| {
        const dm = if (menu_cov[t] >= COVER and mono_cov[t] < COVER) blk: {
            lift_menu += 1;
            break :blk menu_cov[t] - mono_cov[t];
        } else 0.0;
        const dr = if (rune_cov[t] >= COVER and mono_cov[t] < COVER) blk: {
            lift_rune += 1;
            break :blk rune_cov[t] - mono_cov[t];
        } else 0.0;
        if (rune_cov[t] >= COVER and menu_cov[t] < COVER) lift_rune_only += 1;
        try out.print("{s:<32} | {d:.3}{s} | {d:.3}{s}       | {d:.3}{s}    | {d:.3}   | {d:.3}\n", .{
            TARGETS[t].name,
            mono_cov[t],
            if (mono_cov[t] >= COVER) "*" else " ",
            menu_cov[t],
            if (menu_cov[t] >= COVER) "*" else " ",
            rune_cov[t],
            if (rune_cov[t] >= COVER) "*" else " ",
            dm,
            dr,
        });
    }

    try out.print("\nmonomial saturation:     {d}/{d}\n", .{ mono_nsolved, NT });
    try out.print("frozen menu lift:        +{d} targets (→ {d}/{d})\n", .{ lift_menu, menu_nsolved, NT });
    try out.print("rune-augmented lift:     +{d} targets (→ {d}/{d})\n", .{ lift_rune, rune_nsolved, NT });
    try out.print("rune-only delta vs menu: +{d} targets menu cannot reach\n\n", .{lift_rune_only});

    const t5_menu_lift = menu_cov[T5_IDX] - mono_cov[T5_IDX];
    const t7_menu_lift = menu_cov[T7_IDX] - mono_cov[T7_IDX];
    const t5_rune_vs_menu = rune_cov[T5_IDX] - menu_cov[T5_IDX];
    const t7_rune_vs_menu = rune_cov[T7_IDX] - menu_cov[T7_IDX];
    const pass = t5_rune_vs_menu >= PASS_LIFT or t7_rune_vs_menu >= PASS_LIFT;

    try out.print("T5/T7 focus (pass bar ≥+{d:.2} rune-aug vs frozen-menu):\n", .{PASS_LIFT});
    try out.print("  T5 parity:  mono={d:.3} menu={d:.3} rune-aug={d:.3} | d_menu={d:.3} d_rune_vs_menu={d:.3}\n", .{
        mono_cov[T5_IDX], menu_cov[T5_IDX], rune_cov[T5_IDX], t5_menu_lift, t5_rune_vs_menu,
    });
    try out.print("  T7 sum%%7:  mono={d:.3} menu={d:.3} rune-aug={d:.3} | d_menu={d:.3} d_rune_vs_menu={d:.3}\n\n", .{
        mono_cov[T7_IDX], menu_cov[T7_IDX], rune_cov[T7_IDX], t7_menu_lift, t7_rune_vs_menu,
    });

    try out.print("════════════════════ VERDICT ════════════════════\n", .{});
    if (pass) {
        try out.print("PASS — trace runes add ≥+{d:.2} lift on T5 or T7 beyond frozen symbolic menu.\n", .{PASS_LIFT});
    } else if (lift_rune_only > 0) {
        try out.print("PARTIAL — trace runes help some targets but T5/T7 miss +{d:.2} bar.\n", .{PASS_LIFT});
    } else if (menu_nsolved == rune_nsolved and lift_menu > 0) {
        try out.print("FAIL — symbolic menu spans the escape; trace runes add 0 certified lift on zoo.\n", .{});
        try out.print("       Execution traces did NOT invent grid primitives the handed menu lacks.\n", .{});
    } else if (lift_menu == 0 and lift_rune == 0) {
        try out.print("FAIL — neither menu nor trace runes certified escape from monomial saturation.\n", .{});
    } else {
        try out.print("FAIL — menu and trace runes tie at {d}/{d}; no T5/T7 advantage (need ≥+{d:.2}).\n", .{ rune_nsolved, NT, PASS_LIFT });
    }

    try out.print("\nE22_RESULT pass={s} t5_lift={d:.3} t7_lift={d:.3} menu_solved={d} rune_solved={d}\n", .{
        if (pass) "true" else "false",
        t5_rune_vs_menu,
        t7_rune_vs_menu,
        menu_nsolved,
        rune_nsolved,
    });
    try out.print("See: open_invention_e22.md, open_invention_e7.md, terminal_grind_big.zig, rune_native.zig\n", .{});
}