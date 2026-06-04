const std = @import("std");
const domain_base = @import("domain_alien_hack");

pub const DOMAIN_NAME: []const u8 = "agi-final-integration";

// A Unified AGI Entity is defined as the minimal coupling of 6 modules:
// Perception(P), Cognition(C), Motor(M), Homeostasis(H), Immune(I), Curiosity(D)
pub const Module = enum(u3) { P, C, M, H, I, D };

pub const Coupling = struct {
    src: Module,
    dst: Module,
    strength: u8,
};

pub const GrandBlueprint = struct {
    couplings: [16]Coupling,
    used: u8,

    pub fn evaluateIntegrity(self: GrandBlueprint) f64 {
        // Vitality reward: Maximize cross-module recursive influence
        // while minimizing redundant bridges (MDL principle).
        var score: f64 = 0.0;
        var coverage: u64 = 0;
        
        for (self.couplings[0..self.used]) |c| {
            if (c.src != c.dst) score += @as(f64, @floatFromInt(c.strength));
            coverage |= (@as(u64, 1) << @intFromEnum(c.src)) | (@as(u64, 1) << @intFromEnum(c.dst));
        }

        // Connectivity must be fully meshed (all modules linked)
        if (@popCount(coverage) < 6) return 0.0; 
        return score / @as(f64, @floatFromInt(self.used));
    }
};

pub fn randomBlueprint(rng: *u64) GrandBlueprint {
    var b = GrandBlueprint{ .couplings = undefined, .used = 16 };
    for (0..16) |i| {
        rng.* = domain_base.smix(rng.*);
        b.couplings[i] = .{
            .src = @enumFromInt(rng.* % 6),
            .dst = @enumFromInt((rng.* >> 4) % 6),
            .strength = @intCast(rng.* % 256),
        };
    }
    return b;
}

pub fn mutate(b: GrandBlueprint, rng: *u64) GrandBlueprint {
    var q = b;
    rng.* = domain_base.smix(rng.*);
    const idx = rng.* % q.used;
    q.couplings[idx] = .{
        .src = @enumFromInt(rng.* % 6),
        .dst = @enumFromInt((rng.* >> 4) % 6),
        .strength = @intCast(rng.* % 256),
    };
    return q;
}
