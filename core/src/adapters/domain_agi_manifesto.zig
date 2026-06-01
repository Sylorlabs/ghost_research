const std = @import("std");

pub const DOMAIN_NAME: []const u8 = "agi-manifesto-synthesis";

pub const Module = enum(u4) {
    PERCEPTION = 0,
    COGNITION = 1,
    MOTOR = 2,
    HOMEOSTASIS = 3,
};

pub const RemixOp = enum(u4) {
    MERGE = 0,      // Combine logic
    DISTILL = 1,    // Remove redundancies
    RECURSE = 2,    // Create feedback loop
    INTERFACE = 3,  // Create explicit bridge
};

pub const Action = struct {
    op: RemixOp,
    m1: Module,
    m2: Module,
};

pub const Manifesto = struct {
    actions: [16]Action,
    used: u8,

    pub fn evaluate(self: Manifesto) f64 {
        // Vitality reward: Maximize structural connectivity while minimizing node count.
        var connectivity: f64 = 0;
        const node_count: f64 = @as(f64, @floatFromInt(self.used));
        for (self.actions[0..self.used]) |a| {
            if (a.m1 != a.m2) connectivity += 1.0;
        }
        return connectivity / @max(1.0, node_count);
    }
};

pub fn randomManifesto(rng: *u64) Manifesto {
    var m = Manifesto{ .actions = undefined, .used = 16 };
    for (0..16) |i| {
        rng.* = (rng.* *% 0x9E3779B9) +% 0x1234;
        m.actions[i] = .{
            .op = @enumFromInt(rng.* % 4),
            .m1 = @enumFromInt((rng.* >> 4) % 4),
            .m2 = @enumFromInt((rng.* >> 8) % 4),
        };
    }
    return m;
}

pub fn mutate(m: Manifesto, rng: *u64) Manifesto {
    var q = m;
    rng.* = (rng.* *% 0x9E3779B9) +% 0x1234;
    const idx = rng.* % q.used;
    q.actions[idx] = .{
        .op = @enumFromInt(rng.* % 4),
        .m1 = @enumFromInt((rng.* >> 4) % 4),
        .m2 = @enumFromInt((rng.* >> 8) % 4),
    };
    return q;
}
