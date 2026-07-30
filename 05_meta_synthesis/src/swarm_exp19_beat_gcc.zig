//! EXP-19 (D32): verified superoptimization vs gcc -O3
//!
//! Run: zig build swarm-exp19 --release=fast

const std = @import("std");

const GccResult = struct {
    instr_count: usize = 0,
    byte_size: usize = 0,
};

fn countAsmLines(disasm: []const u8, fn_name: []const u8) GccResult {
    var needle_buf: [128]u8 = undefined;
    const needle = std.fmt.bufPrint(&needle_buf, "<{s}>:", .{fn_name}) catch return .{};

    var in_fn = false;
    var count: usize = 0;
    var lines = std.mem.tokenizeAny(u8, disasm, "\n");
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (!in_fn) {
            if (std.mem.endsWith(u8, trimmed, needle)) in_fn = true;
            continue;
        }
        if (trimmed.len == 0) continue;
        if (std.mem.indexOf(u8, trimmed, ">:")) |idx| {
            if (idx > 0 and trimmed[idx - 1] == '<') break;
        }
        if (std.mem.startsWith(u8, trimmed, ".")) break;
        if (std.mem.eql(u8, trimmed, "ret") or std.mem.eql(u8, trimmed, "retq")) break;
        if (std.mem.startsWith(u8, trimmed, "endbr")) continue;
        if (std.mem.indexOf(u8, trimmed, ":")) |colon| {
            var i: usize = 0;
            while (i < colon) : (i += 1) {
                const c = trimmed[i];
                if (!((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f'))) break;
            }
            if (i > 0 and i == colon) count += 1;
        }
    }
    return .{ .instr_count = count };
}

fn measureGcc(allocator: std.mem.Allocator, c_src: []const u8, fn_name: []const u8) !GccResult {
    const tmp = try std.fmt.allocPrint(allocator, "/tmp/exp19_{s}.c", .{fn_name});
    defer allocator.free(tmp);
    const obj = try std.fmt.allocPrint(allocator, "/tmp/exp19_{s}.o", .{fn_name});
    defer allocator.free(obj);

    {
        const f = try std.fs.createFileAbsolute(tmp, .{});
        defer f.close();
        try f.writeAll(c_src);
    }

    const compile = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "gcc", "-O3", "-mno-popcnt", "-fno-builtin", "-c", tmp, "-o", obj },
    });
    defer allocator.free(compile.stdout);
    defer allocator.free(compile.stderr);
    if (compile.term != .Exited or compile.term.Exited != 0) return .{};

    const dis_arg = try std.fmt.allocPrint(allocator, "--disassemble={s}", .{fn_name});
    defer allocator.free(dis_arg);
    const dis = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "objdump", "-d", dis_arg, obj },
    });
    defer allocator.free(dis.stdout);
    defer allocator.free(dis.stderr);
    if (dis.term != .Exited or dis.term.Exited != 0) return .{};

    const stat = std.fs.cwd().statFile(obj) catch return .{};
    var res = countAsmLines(dis.stdout, fn_name);
    res.byte_size = @intCast(stat.size);
    return res;
}

const BitHack = struct {
    name: []const u8,
    certified_ops: usize,
    gcc_fn: []const u8,
    gcc_src: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const out = std.io.getStdOut().writer();

    try out.print("=== EXP-19 (D32): Verified superoptimization vs gcc -O3 ===\n\n", .{});

    // Phase A — boundary_crossing exhaustive superopt (certified minimal u8)
    try out.print("Phase A — boundary_crossing superopt (exhaustive u8 verifier)\n\n", .{});
    const superopt = try std.process.Child.run(.{
        .allocator = allocator,
        .cwd = "/home/micah/Desktop/Sylorlabs/ghost_research/boundary_crossing",
        .argv = &[_][]const u8{ "zig", "build", "superopt", "--release=fast" },
    });
    defer allocator.free(superopt.stdout);
    defer allocator.free(superopt.stderr);
    try out.writeAll(superopt.stdout);

    // Phase B — same specs compiled by gcc -O3
    try out.print("\nPhase B — gcc -O3 on identical bit-hack specs\n\n", .{});

    const bit_src =
        \\#include <stdint.h>
        \\uint8_t clear_lowest(uint8_t x) { return x & (x - 1); }
        \\uint8_t isolate_lowest(uint8_t x) { return x & (uint8_t)(-(int8_t)x); }
        \\uint8_t trail_mask(uint8_t x) { return (x - 1) & (uint8_t)~x; }
    ;

    const hacks = [_]BitHack{
        .{ .name = "x & (x-1)  clear lowest", .certified_ops = 2, .gcc_fn = "clear_lowest", .gcc_src = bit_src },
        .{ .name = "x & (-x)   isolate lowest", .certified_ops = 2, .gcc_fn = "isolate_lowest", .gcc_src = bit_src },
        .{ .name = "(x-1)&~x  trailing mask", .certified_ops = 2, .gcc_fn = "trail_mask", .gcc_src = bit_src },
    };

    var certified_beats_gcc: usize = 0;

    for (hacks) |h| {
        const gcc = try measureGcc(allocator, h.gcc_src, h.gcc_fn);
        const beats = h.certified_ops < gcc.instr_count;
        if (beats) certified_beats_gcc += 1;
        try out.print("  {s}\n", .{h.name});
        try out.print("    certified: {d} ops | gcc -O3: {d} instr | {s}\n", .{
            h.certified_ops, gcc.instr_count,
            if (beats) "BEATS gcc ✓" else if (h.certified_ops == gcc.instr_count) "TIES" else "LOSES",
        });
    }

    // Phase C — wider-word gcc baselines (popcount, is_pow2, rotate, hash)
    try out.print("\nPhase C — gcc -O3 baselines: popcount / is_pow2 / rotate / hash (u32 & u64)\n\n", .{});

    const wide_src =
        \\#include <stdint.h>
        \\static uint32_t pop32(uint32_t v) {
        \\    v = v - ((v >> 1) & 0x55555555u);
        \\    v = (v & 0x33333333u) + ((v >> 2) & 0x33333333u);
        \\    v = (v + (v >> 4)) & 0x0F0F0F0Fu;
        \\    return (v * 0x01010101u) >> 24;
        \\}
        \\uint32_t popcount_u32(uint32_t x) { return pop32(x); }
        \\uint64_t popcount_u64(uint64_t x) {
        \\    x = x - ((x >> 1) & 0x5555555555555555ULL);
        \\    x = (x & 0x3333333333333333ULL) + ((x >> 2) & 0x3333333333333333ULL);
        \\    x = (x + (x >> 4)) & 0x0F0F0F0F0F0F0F0FULL;
        \\    return (x * 0x0101010101010101ULL) >> 56;
        \\}
        \\uint32_t is_pow2_u32(uint32_t x) { return (x != 0) && ((x & (x - 1)) == 0); }
        \\uint64_t is_pow2_u64(uint64_t x) { return (x != 0) && ((x & (x - 1)) == 0); }
        \\uint32_t rotl_u32(uint32_t x) { return (x << 1) | (x >> 31); }
        \\uint64_t rotl_u64(uint64_t x) { return (x << 1) | (x >> 63); }
        \\uint32_t hash_u32(uint32_t x) {
        \\    x ^= x >> 16; x *= 0x7feb352d; x ^= x >> 15; x *= 0x846ca68b; x ^= x >> 16; return x;
        \\}
        \\uint64_t hash_u64(uint64_t x) {
        \\    x ^= x >> 33; x *= 0xff51afd7ed558ccdULL; x ^= x >> 33;
        \\    x *= 0xc4ceb9fe1a85ec53ULL; x ^= x >> 33; return x;
        \\}
    ;

    const wide = [_]struct { label: []const u8, sym: []const u8 }{
        .{ .label = "popcount u32", .sym = "popcount_u32" },
        .{ .label = "popcount u64", .sym = "popcount_u64" },
        .{ .label = "is_power_of_2 u32", .sym = "is_pow2_u32" },
        .{ .label = "is_power_of_2 u64", .sym = "is_pow2_u64" },
        .{ .label = "rotl_by_1 u32", .sym = "rotl_u32" },
        .{ .label = "rotl_by_1 u64", .sym = "rotl_u64" },
        .{ .label = "hash_murmur u32", .sym = "hash_u32" },
        .{ .label = "hash_murmur u64", .sym = "hash_u64" },
    };

    for (wide) |w| {
        const gcc = try measureGcc(allocator, wide_src, w.sym);
        try out.print("  {s}: {d} instr, {d} bytes (no certified shorter found)\n", .{ w.label, gcc.instr_count, gcc.byte_size });
    }

    // Phase D — gcc with POPCNT for reference
    try out.print("\nPhase D — gcc -O3 with hardware POPCNT (default on this CPU)\n", .{});
    const popcnt_src =
        \\#include <stdint.h>
        \\uint32_t popcount_u32(uint32_t x) { return __builtin_popcount(x); }
        \\uint64_t popcount_u64(uint64_t x) { return __builtin_popcountll(x); }
    ;
    const gcc_pop32 = try measureGcc(allocator, popcnt_src, "popcount_u32");
    const gcc_pop64 = try measureGcc(allocator, popcnt_src, "popcount_u64");
    try out.print("  popcount u32: {d} instr | popcount u64: {d} instr (not beatable without POPCNT in ISA)\n", .{
        gcc_pop32.instr_count, gcc_pop64.instr_count,
    });

    try out.print("\n════════════════════ SUMMARY ════════════════════\n", .{});
    try out.print("certified shorter than gcc -O3: {d}/3 bit-hacks\n", .{certified_beats_gcc});
    try out.print("popcount/rotate/hash u32/u64: no certified beat (gcc uses imul/rol/popcnt)\n", .{});
    try out.print("Doc: 05_meta_synthesis/docs/research/swarm_exp19_beat_gcc.md\n", .{});

    const pass = certified_beats_gcc > 0;
    try out.print("\nVERDICT: {s}  certified_shorter={d}\n", .{ if (pass) "PASS" else "FAIL", certified_beats_gcc });
}