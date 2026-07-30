//! EXP-15 cross-check: atom-level synergy among wcore base atoms.
//! A pair {A,B} shows synergy on target T iff depth-≤3 compositions of {A,B}
//! match T but neither {A} nor {B} alone (plus composition) does.
const std = @import("std");
const alien = @import("inv_alien.zig");
const coevo = @import("inv_coevo.zig");
const forge = @import("inv_atomforge.zig");

const V: usize = alien.CANON_BASE;
const DEPTH: usize = 3;
const N_SEQ: usize = 16;
const L: usize = 28;
const SEED: u64 = 0xB17;

fn chainMatchesTarget(lib: []const alien.Program, idxs: []const usize, target: *const alien.Program) bool {
    var prng = std.Random.DefaultPrng.init(SEED);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var tgt: [256]u8 = undefined;
    var got: [256]u8 = undefined;
    var agree: usize = 0;
    var total: usize = 0;
    for (0..N_SEQ) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        alien.runStream(target, syms[0..L], tgt[0..L]);
        forge.applyChain(lib, idxs, syms[0..L], got[0..L]);
        for (0..L) |i| {
            total += 1;
            if (got[i] == tgt[i]) agree += 1;
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total)) >= coevo.MATCH_THRESHOLD;
}

fn reachable(lib: []const alien.Program, max_depth: usize, target: *const alien.Program) bool {
    const n = lib.len;
    if (n == 0) return false;
    var d: usize = 1;
    while (d <= max_depth) : (d += 1) {
        var total: usize = 1;
        for (0..d) |_| total *= n;
        var idx: usize = 0;
        while (idx < total) : (idx += 1) {
            var idxs: [8]usize = undefined;
            var x = idx;
            for (0..d) |j| {
                idxs[j] = x % n;
                x /= n;
            }
            if (chainMatchesTarget(lib, idxs[0..d], target)) return true;
        }
    }
    return false;
}

pub fn run(out: anytype) !void {
    const atoms = forge.baseAtoms();
    const labels = [_][]const u8{ "g_xor", "g_add", "pk_xor", "pk_add", "shift" };
    const tasks = [_]coevo.TaskKind{ .g_xor, .g_add, .pk_xor, .pk_add };

    try out.print("=== wcore atom-level synergy cross-check (depth≤{d}, seed=0x{X}) ===\n\n", .{ DEPTH, SEED });

    var synergy_count: usize = 0;
    for (tasks) |tk| {
        const target = coevo.refSolver(tk);
        const dedicated: usize = @intFromEnum(tk); // each task has a same-named atom
        try out.print("target {s} (excluding dedicated atom {s}):\n", .{ coevo.TaskKind.name(tk), labels[dedicated] });

        var pool: [4]usize = undefined;
        var pool_len: usize = 0;
        for (0..atoms.len) |i| {
            if (i == dedicated) continue;
            pool[pool_len] = i;
            pool_len += 1;
        }

        var single_ok = [_]bool{false} ** 5;
        for (pool[0..pool_len]) |i| {
            const sub = [_]alien.Program{atoms.slice()[i]};
            single_ok[i] = reachable(&sub, DEPTH, &target);
            try out.print("  single {s}: {s}\n", .{ labels[i], if (single_ok[i]) "REACHABLE" else "no" });
        }

        for (pool[0..pool_len], 0..) |i, a| {
            for (pool[a + 1 .. pool_len]) |j| {
                const sub = [_]alien.Program{ atoms.slice()[i], atoms.slice()[j] };
                const pair_ok = reachable(&sub, DEPTH, &target);
                if (pair_ok and !single_ok[i] and !single_ok[j]) {
                    synergy_count += 1;
                    try out.print("  SYNERGY: {s}+{s} reaches {s} (neither alone)\n", .{ labels[i], labels[j], coevo.TaskKind.name(tk) });
                }
            }
        }
        try out.print("\n", .{});
    }
    try out.print("=> {d} atom-pair synergies (dedicated atom withheld per target).\n", .{synergy_count});
}

pub fn main() !void {
    try run(std.io.getStdOut().writer());
}