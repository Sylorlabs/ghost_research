const std = @import("std");
const domain_base = @import("domain_alien_hack");

pub const DOMAIN_NAME: []const u8 = "agi-self-observation-logic";

pub const Op = enum(u4) {
    INGEST_SELF = 0,    // Point Perception at ./src
    IDENTIFY_LOGIC = 1, // Pattern match AST nodes
    SCORE_EFFICIENCY = 2, // Measure AIG node density of self
    REPLACE_SYMBOLS = 3, // Target code for Motor rewriting
};

pub const Node = struct {
    op: Op,
    target: u8,
    priority: u8,
};

pub const ObservationPlan = struct {
    nodes: [8]Node,
    used: u8,

    pub fn evaluate(self: ObservationPlan) f64 {
        var coverage: u64 = 0;
        for (self.nodes[0..self.used]) |n| {
            coverage |= (@as(u64, 1) << @intFromEnum(n.op));
        }
        return @as(f64, @floatFromInt(@popCount(coverage))) * 25.0;
    }
};

pub fn randomPlan(rng: *u64) ObservationPlan {
    var p = ObservationPlan{ .nodes = undefined, .used = 8 };
    for (0..8) |i| {
        rng.* = domain_base.smix(rng.*);
        p.nodes[i] = .{
            .op = @enumFromInt(rng.* % 4),
            .target = @intCast((rng.* >> 8) % 16),
            .priority = @intCast((rng.* >> 16) % 256),
        };
    }
    return p;
}

pub fn mutate(p: ObservationPlan, rng: *u64) ObservationPlan {
    var q = p;
    rng.* = domain_base.smix(rng.*);
    const idx = rng.* % q.used;
    rng.* = domain_base.smix(rng.*);
    q.nodes[idx] = .{
        .op = @enumFromInt(rng.* % 4),
        .target = @intCast((rng.* >> 8) % 16),
        .priority = @intCast((rng.* >> 16) % 256),
    };
    return q;
}
