const std = @import("std");
const domain_base = @import("domain_alien_hack");

pub const DOMAIN_NAME: []const u8 = "graph-associative-memory-max";

pub const MaxNodes = 16;
pub const StateRegs = 4; // 256-bit state

pub const Op = enum(u4) {
    ADD = 0,
    XOR = 1,
    AND = 2,
    OR  = 3,
    ROTL = 4,
    SHL_XOR = 5,
    SELECT = 6, // Gating: res = if (v1 is even) v2 else v3 (Approx. Softmax/Sigmoid)
};

pub const Node = struct {
    op: Op,
    src1: u5, // 0-3: state regs, 4: input, 5-20: node results
    src2: u5,
    src3: u5, // Only used for SELECT
    imm: u6,
};

pub const GraphSystem = struct {
    nodes: [MaxNodes]Node,
    used: u8,

    pub fn step(self: GraphSystem, h: *[StateRegs]u64, x: u64) void {
        var values = [_]u64{0} ** (MaxNodes + StateRegs + 1);
        for (0..StateRegs) |i| values[i] = h[i];
        values[StateRegs] = x;

        var i: usize = 0;
        while (i < self.used) : (i += 1) {
            const node = self.nodes[i];
            const v1 = values[node.src1];
            const v2 = values[node.src2];
            const v3 = values[node.src3];
            
            const result: u64 = switch (node.op) {
                .ADD => v1 +% v2,
                .XOR => v1 ^ v2,
                .AND => v1 & v2,
                .OR  => v1 | v2,
                .ROTL => std.math.rotl(u64, v1, node.imm),
                .SHL_XOR => v1 ^ (v1 << node.imm),
                .SELECT => if (v1 % 2 == 0) v2 else v3,
            };
            values[i + StateRegs + 1] = result;
        }
        
        // Final values map back to state
        for (0..StateRegs) |k| {
            h[k] = values[self.used + k]; // Use last nodes as new state
        }
    }

    pub fn executeSymbolic(self: GraphSystem) [64]domain_base.Dependency {
        // Truncated symbolic trace for speed: tracks how much input x influences state registers
        // To be used in the fitness function to prevent 'Dead Information'
        var node_deps = [_]u64{0} ** (MaxNodes + StateRegs + 1);
        for (0..StateRegs) |k| node_deps[k] = 0; // Previous state influence ignored for this metric
        node_deps[StateRegs] = std.math.maxInt(u64); // Current input X is the source of influence

        var i: usize = 0;
        while (i < self.used) : (i += 1) {
            const node = self.nodes[i];
            node_deps[i + StateRegs + 1] = node_deps[node.src1] | node_deps[node.src2] | node_deps[node.src3];
        }
        
        var total_influence: [64]domain_base.Dependency = undefined;
        // Mock matrix for the search gradient
        for (&total_influence) |*d| {
            d.x = node_deps[MaxNodes + StateRegs];
            d.y = 0;
        }
        return total_influence;
    }
};

pub fn randomNode(rng: *u64, used_so_far: u8) Node {
    const max_src = used_so_far + StateRegs + 1;
    rng.* = domain_base.smix(rng.*);
    const op: Op = @enumFromInt(rng.* % 7);
    rng.* = domain_base.smix(rng.*);
    const s1: u5 = @intCast(rng.* % max_src);
    rng.* = domain_base.smix(rng.*);
    const s2: u5 = @intCast(rng.* % max_src);
    rng.* = domain_base.smix(rng.*);
    const s3: u5 = @intCast(rng.* % max_src);
    rng.* = domain_base.smix(rng.*);
    const imm: u6 = @intCast(rng.* % 64);
    return .{ .op = op, .src1 = s1, .src2 = s2, .src3 = s3, .imm = imm };
}

pub fn randomSystem(rng: *u64, len: u8) GraphSystem {
    var p = GraphSystem{ .nodes = undefined, .used = len };
    var i: u8 = 0;
    while (i < len) : (i += 1) {
        p.nodes[i] = randomNode(rng, i);
    }
    return p;
}

pub fn mutate(p: GraphSystem, rng: *u64) GraphSystem {
    var q = p;
    rng.* = domain_base.smix(rng.*);
    const draw = rng.* % 16;
    if (draw < 4 and q.used > 4) {
        q.used -= 1;
    } else if (draw < 8 and q.used < MaxNodes) {
        q.nodes[q.used] = randomNode(rng, q.used);
        q.used += 1;
    } else {
        const idx = @as(u8, @intCast(rng.* % q.used));
        q.nodes[idx] = randomNode(rng, idx);
    }
    return q;
}
