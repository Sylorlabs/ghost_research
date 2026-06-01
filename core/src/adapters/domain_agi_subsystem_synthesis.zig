const std = @import("std");
const domain_base = @import("domain_alien_hack");

pub const DOMAIN_NAME: []const u8 = "agi-motor-synthesis";

// The machine must decide how to map AIG NodeIds to actual Zig Code Patterns.
pub const Op = enum(u4) {
    LIFT_GATE = 0,     // AIG -> AST Node
    MAP_VARIABLE = 1,  // Register allocation
    EMIT_FUNCTION = 2, // Wrap in Zig 'pub fn'
    OPTIMIZE_TAIL = 3, // Recursive cleanup
};

pub const Node = struct {
    op: Op,
    src: u8,
    imm: u6,
};

pub const MotorPlan = struct {
    nodes: [8]Node,
    used: u8,

    /// Measures the 'Expressivity' of the generated motor plan.
    pub fn evaluate(self: MotorPlan) f64 {
        var coverage: u64 = 0;
        for (self.nodes[0..self.used]) |n| {
            // A good motor plan must use all 4 ops to be 'Complete'
            coverage |= (@as(u64, 1) << @intFromEnum(n.op));
        }
        const variety = @as(f64, @floatFromInt(@popCount(coverage)));
        return variety * 25.0; // Max 100.0
    }
};

pub fn randomPlan(rng: *u64) MotorPlan {
    var p = MotorPlan{ .nodes = undefined, .used = 8 };
    for (0..8) |i| {
        rng.* = domain_base.smix(rng.*);
        p.nodes[i] = .{
            .op = @enumFromInt(rng.* % 4),
            .src = @intCast((rng.* >> 8) % 16),
            .imm = @intCast((rng.* >> 16) % 64),
        };
    }
    return p;
}

pub fn mutate(p: MotorPlan, rng: *u64) MotorPlan {
    var q = p;
    rng.* = domain_base.smix(rng.*);
    const idx = rng.* % q.used;
    rng.* = domain_base.smix(rng.*);
    q.nodes[idx] = .{
        .op = @enumFromInt(rng.* % 4),
        .src = @intCast((rng.* >> 8) % 16),
        .imm = @intCast((rng.* >> 16) % 64),
    };
    return q;
}
