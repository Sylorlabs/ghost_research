const std = @import("std");
const domain_base = @import("domain_alien_hack");

pub const DOMAIN_NAME: []const u8 = "agi-whole-body-plan";

/// THE MACHINE'S BODY SUBSYSTEMS:
pub const Subsystem = enum(u4) {
    PERCEPTION = 0, // High-bandwidth data ingestion (Corpus)
    COGNITION  = 1, // Structural Tracing & AIG reduction
    MOTOR      = 2, // Synthesis & Code Emission (Zig output)
    HOMEOSTASIS = 3, // Meta-Heuristic self-tuning (Alien Laws)
};

pub const ConnectionOp = enum(u4) {
    BRIDGE = 0,   // Pass information directly
    GATED  = 1,   // Selective filter
    FEEDBACK = 2, // Recursive loop
    PRESSURE = 3, // Apply MDL compression constraint
};

pub const NerveNode = struct {
    op: ConnectionOp,
    src: Subsystem,
    dst: Subsystem,
    strength: u8,
};

pub const AGIBody = struct {
    nerves: [16]NerveNode,
    used: u8,

    /// Evaluates the 'Vitality' of the body plan.
    /// A high-vitality plan has zero information dead-ends and 
    /// a perfectly balanced recursive feedback loop.
    pub fn evaluateVitality(self: AGIBody) f64 {
        var influence = [_]f64{ 1.0, 1.0, 1.0, 1.0 }; // Start with balanced potential
        
        var i: usize = 0;
        while (i < self.used) : (i += 1) {
            const n = self.nerves[i];
            const weight = @as(f64, @floatFromInt(n.strength)) / 255.0;
            
            switch (n.op) {
                .BRIDGE => {
                    influence[@intFromEnum(n.dst)] += influence[@intFromEnum(n.src)] * weight;
                },
                .GATED => {
                    influence[@intFromEnum(n.dst)] += (influence[@intFromEnum(n.src)] * weight) * 0.5;
                },
                .FEEDBACK => {
                    // Recursive loops multiply vitality but increase instability
                    influence[@intFromEnum(n.dst)] *= (1.0 + weight);
                },
                .PRESSURE => {
                    // Compression reduces raw size but increases density
                    influence[@intFromEnum(n.dst)] = @log(@max(1.1, influence[@intFromEnum(n.dst)])) * weight;
                },
            }
        }

        // The goal is 'Global System Stability':
        // All subsystems must be active, and no single system can dominate (implosion).
        var min_inf = influence[0];
        var max_inf = influence[0];
        var sum_inf: f64 = 0;
        for (influence) |inf| {
            if (inf < min_inf) min_inf = inf;
            if (inf > max_inf) max_inf = inf;
            sum_inf += inf;
        }

        const balance = min_inf / max_inf;
        return sum_inf * balance;
    }
};

pub fn randomBody(rng: *u64, len: u8) AGIBody {
    var body = AGIBody{ .nerves = undefined, .used = len };
    for (0..len) |i| {
        rng.* = domain_base.smix(rng.*);
        body.nerves[i] = .{
            .op = @enumFromInt(rng.* % 4),
            .src = @enumFromInt((rng.* >> 8) % 4),
            .dst = @enumFromInt((rng.* >> 16) % 4),
            .strength = @intCast((rng.* >> 24) % 256),
        };
    }
    return body;
}

pub fn mutate(body: AGIBody, rng: *u64) AGIBody {
    var q = body;
    rng.* = domain_base.smix(rng.*);
    const idx = rng.* % q.used;
    rng.* = domain_base.smix(rng.*);
    q.nerves[idx] = .{
        .op = @enumFromInt(rng.* % 4),
        .src = @enumFromInt((rng.* >> 8) % 4),
        .dst = @enumFromInt((rng.* >> 16) % 4),
        .strength = @intCast((rng.* >> 24) % 256),
    };
    return q;
}
