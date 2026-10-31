const std = @import("std");
const prover = @import("native_prover");

pub const DOMAIN_NAME: []const u8 = "popcount-superoptimizer";

pub const MaxNodes = 8; // Try to find a very short sequence

pub const Op = enum(u4) {
    XOR = 0,
    SHR = 1,
    AND = 2,
    ROTL = 3,
    SHL = 4,
};

pub const Node = struct {
    op: Op,
    src1: u4, 
    src2: u4 = 0,
    imm: u6,
};

pub const GraphProgram = struct {
    nodes: [MaxNodes]Node,
    used: u8,

    pub fn execute(self: GraphProgram, x: u64) u64 {
        var values = [_]u64{0} ** (MaxNodes + 1);
        values[0] = x;
        var i: usize = 0;
        while (i < self.used) : (i += 1) {
            const n = self.nodes[i];
            const v1 = values[n.src1];
            values[i + 1] = switch (n.op) {
                .XOR => v1 ^ (v1 >> n.imm),
                .SHR => v1 >> n.imm,
                .AND => v1 & (@as(u64, 1) << n.imm),
                .ROTL => std.math.rotl(u64, v1, n.imm),
                .SHL => v1 << n.imm,
            };
        }
        return values[self.used];
    }

    pub fn toAig(self: GraphProgram, aig: *prover.Aig, input_bv: prover.BitVector) !prover.NodeId {
        var bvs = [_]prover.BitVector{undefined} ** (MaxNodes + 1);
        bvs[0] = input_bv;

        var i: usize = 0;
        while (i < self.used) : (i += 1) {
            const n = self.nodes[i];
            const v1 = bvs[n.src1];
            bvs[i + 1] = switch (n.op) {
                .XOR => try v1.xorBv(aig, v1.shrBv(aig, n.imm)),
                .SHR => v1.shrBv(aig, n.imm),
                .AND => try v1.andBv(aig, prover.BitVector.initConstant(aig, @as(u64, 1) << n.imm)),
                .ROTL => v1.rotlBv(aig, n.imm),
                .SHL => v1.shlBv(aig, n.imm),
            };
        }
        return bvs[self.used].bits[0];
    }
};

pub fn randomProgram(rng: *u64, len: u8) GraphProgram {
    var p = GraphProgram{ .nodes = undefined, .used = len };
    var i: u8 = 0;
    while (i < len) : (i += 1) {
        p.nodes[i] = randomNode(rng, i);
    }
    return p;
}

pub fn mutate(p: GraphProgram, rng: *u64) GraphProgram {
    var q = p;
    const smix = @import("domain_alien_hack").smix;
    rng.* = smix(rng.*);
    const draw = rng.* % 16;
    
    if (draw < 4 and q.used > 1) {
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

fn randomNode(rng: *u64, used_so_far: u8) Node {
    const smix = @import("domain_alien_hack").smix;
    rng.* = smix(rng.*);
    const op: Op = @enumFromInt(rng.* % 5);
    rng.* = smix(rng.*);
    const s1: u4 = @intCast(rng.* % (used_so_far + 1));
    rng.* = smix(rng.*);
    const imm: u6 = @intCast(rng.* % 64);
    return .{ .op = op, .src1 = s1, .imm = imm };
}
