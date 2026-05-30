//! wcore-pure — the minimal-bias variant.
//!
//! Prior = the SK-combinator basis (`S`, `K`, application) + one objective:
//! "make the total description shorter" (minimize node count). NOTHING ELSE.
//! No types, no Bool/Unit, no Sensor/Action, no numbers, no recursion
//! primitives. The library starts EMPTY of discovered abstractions.
//!
//! It is driven by a stream it does not author (and is never told the structure
//! of). By compression alone it rediscovers fundamental combinators — the
//! identity and the Church booleans — and we confirm what they are by EXECUTING
//! them on inert markers. The labels are post-hoc; the discovery is pure node
//! count. Everything is logged to logs/wcore_pure_<seed>.log.

const std = @import("std");
const sk = @import("sk.zig");
const comp = @import("sk_compress.zig");
const gen = @import("sk_gen.zig");
const learn = @import("sk_learn.zig");
const Logger = @import("logger.zig").Logger;
const Term = sk.Term;

const DEFAULT_SEED: u64 = 0xC0FFEE;
const CORPUS_N: usize = 6;
const MAX_ROUNDS: usize = 5;
const CURRICULUM_STAGES: usize = 3;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const args = try std.process.argsAlloc(a);
    const seed = if (args.len >= 2) (parseU64(args[1]) orelse DEFAULT_SEED) else DEFAULT_SEED;
    const do_learn = args.len >= 3 and std.mem.eql(u8, args[2], "learn");

    const path = try std.fmt.allocPrint(a, "logs/wcore_pure_{x}{s}.log", .{ seed, if (do_learn) "_learn" else "" });
    var log = try Logger.initPath(path);
    defer log.deinit();

    try log.print("[PURE] substrate = {{S, K, application}}; objective = minimize node count.\n", .{});
    try log.writeAll("[PURE] prior contains NO types, NO Bool/Unit, NO Sensor/Action, NO numbers. Library starts empty.\n");
    try log.print("[PURE] seed=0x{x}; log -> {s}\n\n", .{ seed, path });

    if (do_learn) {
        try runCurriculum(a, &log, seed);
    } else {
        try runStream(a, &log, "STRUCTURED", try gen.structuredCorpus(a, seed, CORPUS_N));
        try log.writeAll("\n");
        try runStream(a, &log, "NOISE", try gen.noiseCorpus(a, seed, CORPUS_N));
    }

    try log.print("\n[PURE] complete. Full log: {s}\n", .{path});
}

/// Cumulative learning: a persistent library carried across a sequence of
/// streams. Each stream first REUSES what is already known, then discovers
/// what is new — so later abstractions are built on earlier ones.
fn runCurriculum(a: std.mem.Allocator, log: *Logger, seed: u64) !void {
    var lib = std.ArrayList(*Term).init(a);
    try log.writeAll("==== CURRICULUM (persistent, growing library) ====================\n\n");

    var stage: usize = 0;
    while (stage < CURRICULUM_STAGES) : (stage += 1) {
        try log.print("---- stage {d} (library has {d} abstractions on entry) ----\n", .{ stage, lib.items.len });
        var corpus: []const *Term = try gen.curriculumStage(a, seed, stage, CORPUS_N);
        const raw_nodes = comp.totalNodes(corpus, &.{});
        try log.print("[STREAM] raw description length: {d} nodes\n", .{raw_nodes});

        // 1. REUSE: fold known abstractions into references.
        if (lib.items.len > 0) {
            const res = try learn.refactorAgainstLibrary(a, corpus, lib.items);
            corpus = res.corpus;
            if (res.reuses.len == 0) {
                try log.writeAll("[REUSE] no prior abstraction occurs in this stream.\n");
            } else {
                for (res.reuses) |ru| {
                    const kind = try comp.classify(a, ru.idx, lib.items);
                    try log.print("[REUSE] applied C{d} ({s}) {d}x\n", .{ ru.idx, comp.kindName(kind), ru.count });
                }
                try log.print("[REUSE] description length after reuse: {d} nodes\n", .{comp.totalNodes(corpus, lib.items)});
            }
        }

        // 2. DISCOVER: new abstractions from what remains (may reference prior ones).
        var round: usize = 0;
        while (round < MAX_ROUNDS) : (round += 1) {
            const ext = (try comp.bestExtraction(a, corpus)) orelse break;
            const idx = lib.items.len;
            try lib.append(ext.subterm);
            corpus = try comp.applyExtraction(a, corpus, ext.subterm, idx);
            const kind = try comp.classify(a, idx, lib.items);
            try log.print("[DISCOVER] C{d} = ", .{idx});
            try sk.write(ext.subterm, log);
            try log.print("  (occurs {d}x, saves {d}) -> {s}\n", .{ ext.occurrences, ext.saved, comp.kindName(kind) });
        }
        try log.print("[STAGE {d}] done: library now {d} abstractions.\n\n", .{ stage, lib.items.len });
    }

    try log.writeAll("==== FINAL LIBRARY (the tower it built from S and K) ====\n");
    for (lib.items, 0..) |def, i| {
        const kind = try comp.classify(a, i, lib.items);
        try log.print("  C{d} = ", .{i});
        try sk.write(def, log);
        try log.print("   [{s}]\n", .{comp.kindName(kind)});
    }
}

fn runStream(a: std.mem.Allocator, log: *Logger, label: []const u8, initial: []const *Term) !void {
    try log.print("==== {s} stream =====================================\n", .{label});
    try log.writeAll("[STREAM] raw experience (verbatim SK, nothing labelled):\n");
    for (initial, 0..) |c, i| {
        try log.print("  e{d} = ", .{i});
        try sk.write(c, log);
        try log.print("   ({d} nodes)\n", .{sk.nodeCount(c)});
    }

    var lib = std.ArrayList(*Term).init(a);
    var corpus: []const *Term = initial;
    const start_nodes = comp.totalNodes(corpus, lib.items);
    try log.print("[STREAM] initial description length: {d} nodes\n", .{start_nodes});

    var round: usize = 0;
    while (round < MAX_ROUNDS) : (round += 1) {
        const ext = (try comp.bestExtraction(a, corpus)) orelse {
            try log.writeAll("[SLEEP] no abstraction reduces the description length further.\n");
            break;
        };
        const idx = lib.items.len;
        try lib.append(ext.subterm);
        corpus = try comp.applyExtraction(a, corpus, ext.subterm, idx);

        try log.print("[SLEEP] discovered C{d} = ", .{idx});
        try sk.write(ext.subterm, log);
        try log.print("  (occurs {d}x, saves {d} nodes)\n", .{ ext.occurrences, ext.saved });

        // Post-hoc: what does this combinator actually DO? (verified by execution)
        const kind = try comp.classify(a, idx, lib.items);
        try log.print("         C{d} decoded behaviourally as: {s}\n", .{ idx, comp.kindName(kind) });
        if (kind == .identity) try log.writeAll("         >> the engine reinvented the IDENTITY FUNCTION from S and K alone <<\n");
        if (kind == .church_false) try log.writeAll("         >> the engine reinvented a CHURCH BOOLEAN (false) from S and K alone <<\n");
        if (kind == .church_true) try log.writeAll("         >> the engine reinvented a CHURCH BOOLEAN (true) from S and K alone <<\n");
    }

    const end_nodes = comp.totalNodes(corpus, lib.items);
    const ratio: f64 = if (end_nodes == 0) 0 else @as(f64, @floatFromInt(start_nodes)) / @as(f64, @floatFromInt(end_nodes));
    try log.print("[RESULT] {s}: {d} abstractions discovered; {d} -> {d} nodes (compression {d:.2}x)\n", .{ label, lib.items.len, start_nodes, end_nodes, ratio });
}

fn parseU64(s: []const u8) ?u64 {
    if (std.mem.startsWith(u8, s, "0x")) return std.fmt.parseInt(u64, s[2..], 16) catch null;
    return std.fmt.parseInt(u64, s, 10) catch null;
}

test {
    _ = @import("sk.zig");
    _ = @import("sk_compress.zig");
    _ = @import("sk_gen.zig");
    _ = @import("sk_learn.zig");
}
