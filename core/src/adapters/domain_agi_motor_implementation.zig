const std = @import("std");
const domain_base = @import("domain_alien_hack");

pub const DOMAIN_NAME: []const u8 = "agi-motor-implementation";

// The machine synthesizes the safest way to rewrite its own logic.
pub const RewriteOp = enum(u4) {
    ATOMIC_WRITE = 0,    // Write to a shadow file first
    SYNTAX_VERIFY = 1,   // Use 'zig build-exe' to check correctness
    ATOMIC_SWAP = 2,     // Rename shadow file over live logic
    MODULE_RELOAD = 3,   // Notify engine of logic change
};

pub const ActionNode = struct {
    op: RewriteOp,
    priority: u8,
};

pub const MotorImplementationPlan = struct {
    actions: [8]ActionNode,
    used: u8,

    pub fn evaluate(self: MotorImplementationPlan) f64 {
        // High score = maximized safety (Verify before Swap) 
        // and maximized atomicity.
        var score: f64 = 0.0;
        var has_verify = false;
        var has_swap = false;

        for (self.actions[0..self.used]) |a| {
            if (a.op == .SYNTAX_VERIFY) has_verify = true;
            if (a.op == .ATOMIC_SWAP) has_swap = true;
            score += @as(f64, @floatFromInt(a.priority));
        }

        if (has_verify and has_swap) score *= 2.0;
        return score;
    }
};

pub fn randomPlan(rng: *u64) MotorImplementationPlan {
    var p = MotorImplementationPlan{ .actions = undefined, .used = 8 };
    for (0..8) |i| {
        rng.* = domain_base.smix(rng.*);
        p.actions[i] = .{
            .op = @enumFromInt(rng.* % 4),
            .priority = @intCast(rng.* % 256),
        };
    }
    return p;
}

pub fn mutate(p: MotorImplementationPlan, rng: *u64) MotorImplementationPlan {
    var q = p;
    rng.* = domain_base.smix(rng.*);
    const idx = rng.* % q.used;
    q.actions[idx] = .{
        .op = @enumFromInt(rng.* % 4),
        .priority = @intCast(rng.* % 256),
    };
    return q;
}
