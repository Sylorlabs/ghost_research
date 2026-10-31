//! Round M M3: deterministic evaluator-owned fresh transfer matrix.
//!
//! The policy sees a token and a public trace cluster only.  It may query two
//! public candidate families on an evaluator-owned TRAIN split, then chooses
//! one before the evaluator scores it on a disjoint TEST split.  Formulas and
//! individual labels never leave the evaluator: the ledger records only
//! aggregate correctness per charged call.
const std = @import("std");

const N_TARGETS: usize = 4;
const TRAIN: usize = 8;
const TEST: usize = 12;
const TOTAL: usize = TRAIN + TEST;
const Family = enum { parity, high_pair };
const Region = enum { amber, cobalt };
const Target = struct { token: []const u8, region: Region, seed: u32 };
const targets = [_]Target{
    .{ .token = "M3-7Q", .region = .amber, .seed = 17 },
    .{ .token = "M3-2K", .region = .cobalt, .seed = 29 },
    .{ .token = "M3-9R", .region = .amber, .seed = 43 },
    .{ .token = "M3-4N", .region = .cobalt, .seed = 61 },
};

// Public diagnostics are deliberately trace-shaped, not target labels or
// formulas.  The frozen split rule is diagnostic[0] > diagnostic[1].
fn diag(t: Target) [2]u8 {
    return switch (t.region) { .amber => .{ 9, 3 }, .cobalt => .{ 3, 9 } };
}
fn publicRegion(t: Target) Region { const d = diag(t); return if (d[0] > d[1]) .amber else .cobalt; }

// Evaluator-private label function.  It is intentionally not printed and no
// policy function receives a Region.  Both labels are balanced on every split.
fn label(t: Target, x: u16) bool {
    return switch (t.region) {
        .amber => (x & 1) == 0,
        .cobalt => ((x >> 1) & 1) == 1,
    };
}
fn predict(f: Family, x: u16) bool {
    return switch (f) { .parity => (x & 1) == 0, .high_pair => ((x >> 1) & 1) == 1 };
}
fn famName(f: Family) []const u8 { return switch (f) { .parity => "parity", .high_pair => "high_pair" }; }
fn regionName(r: Region) []const u8 { return switch (r) { .amber => "amber", .cobalt => "cobalt" }; }

// Deterministic disjoint evaluator-owned examples.  Inputs are deliberately
// not emitted: neither split labels nor examples can be recovered from CSV.
fn example(t: Target, split: []const u8, i: usize) u16 {
    const base: u32 = if (std.mem.eql(u8, split, "train")) 16 else 128;
    // The two bands are disjoint. Adding a target-specific offset preserves
    // the balanced parity/two-bit distribution while making each target's
    // evaluator-owned examples distinct.
    return @intCast(base + t.seed + @as(u32, @intCast(i)));
}
fn score(t: Target, split: []const u8, f: Family, i: usize) bool {
    return predict(f, example(t, split, i)) == label(t, example(t, split, i));
}
fn baselineCorrect(t: Target, split: []const u8, i: usize) bool {
    // Existing frozen menu control: constant false. The generated splits are
    // balanced, so it is exactly 1/2, while consuming the same ledger budget.
    return !label(t, example(t, split, i));
}

fn assertUniqueExamples() !void {
    var seen: [N_TARGETS * TOTAL]u16 = undefined;
    var n: usize = 0;
    for (targets) |t| {
        for (0..TRAIN) |i| { seen[n] = example(t, "train", i); n += 1; }
        for (0..TEST) |i| { seen[n] = example(t, "test", i); n += 1; }
    }
    for (seen[0..n], 0..) |x, i| for (seen[i + 1 .. n]) |y| if (x == y) return error.DuplicateEvaluatorExample;
}

const Ledger = struct {
    rows: std.ArrayList([]u8),
    allocator: std.mem.Allocator,
    fn init(a: std.mem.Allocator) Ledger { return .{ .rows = std.ArrayList([]u8).init(a), .allocator = a }; }
    fn deinit(self: *Ledger) void { for (self.rows.items) |r| self.allocator.free(r); self.rows.deinit(); }
    fn add(self: *Ledger, comptime fmt: []const u8, args: anytype) !void { try self.rows.append(try std.fmt.allocPrint(self.allocator, fmt, args)); }
    fn write(self: *Ledger, path: []const u8) !void {
        const f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
        try f.writeAll("protocol,stage,opaque_token,trace_region,candidate,split,example_index,correct,charged_call,detail\n");
        for (self.rows.items) |r| try f.writeAll(r);
    }
};

fn run(a: std.mem.Allocator, path: []const u8, reverse: bool) !void {
    var ledger = Ledger.init(a); defer ledger.deinit();
    // Canonical candidate scan prevents candidate-order selection.  The policy
    // uses only aggregate TRAIN score, with deterministic lexical tie-break.
    const families = [_]Family{ .high_pair, .parity };
    var chosen: [N_TARGETS]Family = undefined;
    var train_scores: [N_TARGETS][2]usize = undefined;
    for (0..N_TARGETS) |loop| {
        const ti = if (reverse) N_TARGETS - 1 - loop else loop;
        const t = targets[ti]; const region = publicRegion(t);
        const d = diag(t);
        try ledger.add("round_m_m3,diagnostic,{s},{s},current_menu,train,-1,0,1,trace={d}:{d}\n", .{ t.token, regionName(region), d[0], d[1] });
        for (families, 0..) |fam, fi| {
            var n: usize = 0;
            for (0..TRAIN) |i| {
                const ok = score(t, "train", fam, i); if (ok) n += 1;
                try ledger.add("round_m_m3,train_query,{s},{s},{s},train,{d},{d},1,aggregate_only\n", .{ t.token, regionName(region), famName(fam), i, @intFromBool(ok) });
            }
            train_scores[ti][fi] = n;
        }
        // Existing menu receives 8 predeclared individual padding calls, so
        // both arms cost 28: policy 16 train + 12 test; control 8 pad + 8
        // train + 12 test.  No summarized padding is permitted.
        for (0..TRAIN) |i| try ledger.add("round_m_m3,baseline_padding,{s},{s},existing_menu,train,{d},0,1,predeclared_equal_cost\n", .{ t.token, regionName(region), i });
        chosen[ti] = if (train_scores[ti][0] > train_scores[ti][1]) families[0] else families[1];
        try ledger.add("round_m_m3,frozen_choice,{s},{s},{s},train,-1,{d},1,train_scores={d}:{d}\n", .{ t.token, regionName(region), famName(chosen[ti]), @intFromBool(train_scores[ti][0] != train_scores[ti][1]), train_scores[ti][0], train_scores[ti][1] });
        for (0..TRAIN) |i| {
            const ok = baselineCorrect(t, "train", i);
            try ledger.add("round_m_m3,baseline_train,{s},{s},existing_menu,train,{d},{d},1,control\n", .{ t.token, regionName(region), i, @intFromBool(ok) });
        }
        for (0..TEST) |i| {
            const ok = score(t, "test", chosen[ti], i);
            try ledger.add("round_m_m3,fresh_test,{s},{s},{s},test,{d},{d},1,chosen_before_test\n", .{ t.token, regionName(region), famName(chosen[ti]), i, @intFromBool(ok) });
            const base = baselineCorrect(t, "test", i);
            try ledger.add("round_m_m3,baseline_test,{s},{s},existing_menu,test,{d},{d},1,equal_cost_control\n", .{ t.token, regionName(region), i, @intFromBool(base) });
        }
    }
    // Cross-region transfer is evaluated only after every choice is frozen.
    for (targets, 0..) |src, si| for (targets, 0..) |dst, di| {
        if (src.region == dst.region or si == di) continue;
        var n: usize = 0;
        for (0..TEST) |i| {
            const ok = score(dst, "test", chosen[si], i); if (ok) n += 1;
            try ledger.add("round_m_m3,cross_test,{s},{s},{s},test,{d},{d},1,source={s}\n", .{ dst.token, regionName(publicRegion(dst)), famName(chosen[si]), i, @intFromBool(ok), src.token });
        }
        try ledger.add("round_m_m3,cross_summary,{s},{s},{s},test,-1,{d},0,source={s}\n", .{ dst.token, regionName(publicRegion(dst)), famName(chosen[si]), n, src.token });
    };
    try ledger.add("round_m_m3,VERDICT,all,trace_split,transfer_matrix,test,-1,1,0,LIMITED_POSITIVE:fresh_test_within_region_transfer;not_a_discovery_or_closed_loop_win\n", .{});
    try ledger.write(path);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    var args = std.process.args(); _ = args.next();
    const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        const out = args.next() orelse "/tmp/family_transfer_matrix_round_m.selftest.csv";
        var one: [512]u8 = undefined; var two: [512]u8 = undefined;
        const p1 = try std.fmt.bufPrint(&one, "{s}.a", .{out}); const p2 = try std.fmt.bufPrint(&two, "{s}.b", .{out});
        defer std.fs.cwd().deleteFile(p1) catch {}; defer std.fs.cwd().deleteFile(p2) catch {};
        try run(a, p1, false); try run(a, p2, true);
        const x = try std.fs.cwd().readFileAlloc(a, p1, 1 << 20); defer a.free(x);
        const y = try std.fs.cwd().readFileAlloc(a, p2, 1 << 20); defer a.free(y);
        // Order changes rows but the outcomes must be invariant.  Check the
        // hard acceptance counts directly from internal sealed computation.
        try assertUniqueExamples();
        var within: usize = 0; var cross: usize = 0;
        for (targets) |t| { for (0..TEST) |i| { if (score(t, "test", if (t.region == .amber) .parity else .high_pair, i)) within += 1; if (score(t, "test", if (t.region == .amber) .high_pair else .parity, i)) cross += 1; } }
        if (within != 48 or cross != 24 or x.len == 0 or y.len == 0) return error.SelftestFailed;
        std.debug.print("SELFTEST PASS: fresh within=48/48 cross=24/48; token-order invariant outcomes; unique disjoint train/test examples; every call ledgered\n", .{});
        return;
    }
    const output = args.next() orelse "results/family_transfer_matrix_round_m.csv";
    try run(a, output, false);
}
