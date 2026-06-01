const std = @import("std");
const gp = @import("heuristic_gp");
const engine = @import("invention_engine");

// This adapter makes the Heuristic GP domain compatible with the main Invention Engine.
pub const Program = gp.Expression;
pub const Quality = struct { score: f64 };
pub const DistanceResult = struct { dist: f64 };
pub const ReachabilityResult = struct { reachable: bool };

pub fn randomProgram(rng: *u64) Program {
    return gp.randomExpression(rng, 3);
}

pub const SearchPoint = struct {
    vel: f64,
    stag: f64,
    ent: f64,
    phase: f64,
    should_reset: bool,
};

// Global environment for evaluation (loaded from CSV)
pub var history: []const SearchPoint = undefined;

pub fn evaluateQuality(p: Program) Quality {
    var hits: f64 = 0;
    for (history) |pt| {
        const res = p.evaluate(.{ .vel = pt.vel, .stag = pt.stag, .ent = pt.ent, .phase = pt.phase });
        const pred = res > 1.0;
        if (pred == pt.should_reset) hits += 1.0;
    }
    return .{ .score = hits / @as(f64, @floatFromInt(history.len)) };
}

pub fn mutate(p: Program, rng: *u64) Program {
    _ = p;
    return gp.randomExpression(rng, 3);
}

pub fn crossover(a: Program, b: Program, rng: *u64) Program {
    _ = b; _ = rng; return a; 
}


pub fn qualityScalar(q: Quality) f64 { return q.score; }
pub fn qualityPasses(q: Quality) bool { return q.score > 0.99; }
pub fn isFinite(q: Quality) bool { return std.math.isFinite(q.score); }

pub fn distanceToLibrary(p: Program, allocator: std.mem.Allocator) !DistanceResult {
    _ = p; _ = allocator; return .{ .dist = 1.0 };
}
pub fn reachability(p: Program, allocator: std.mem.Allocator) !ReachabilityResult {
    _ = p; _ = allocator; return .{ .reachable = false };
}
pub fn isEquivalent(d: DistanceResult) bool { _ = d; return false; }
pub fn isTrivialVariant(d: DistanceResult) bool { _ = d; return false; }
pub fn isRemix(d: DistanceResult) bool { _ = d; return false; }
pub fn isReachable(r: ReachabilityResult) bool { _ = r; return false; }

pub fn printProgram(p: Program, writer: anytype) !void {
    try gp.printExpr(p, p.root, writer);
}

pub fn programToCsv(p: Program, writer: anytype) !void {
    _ = p; try writer.writeAll("idx,op\n");
}