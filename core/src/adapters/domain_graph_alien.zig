const std = @import("std");
const domain_base = @import("domain_alien_hack");

pub const MaxNodes = 10;
pub const NumInputs = 2; // x and y

pub const Op = domain_base.Op;

pub const Node = struct {
    op: Op,
    src1: u4, // 0-1: input registers, 2-11: results of previous nodes
    src2: u4,
    imm: u6,
};

pub const GraphProgram = struct {
    nodes: [MaxNodes]Node,
    used: u8,

    pub fn execute(self: GraphProgram, x: u64, y: u64) u64 {
        var values = [_]u64{0} ** (MaxNodes + 2);
        values[0] = x;
        values[1] = y;

        var i: usize = 0;
        while (i < self.used) : (i += 1) {
            const node = self.nodes[i];
            const v1 = values[node.src1];
            const v2 = values[node.src2];
            const result: u64 = switch (node.op) {
                .ADD => v1 +% v2,
                .SUB => v1 -% v2,
                .XOR => v1 ^ v2,
                .AND => v1 & v2,
                .OR  => v1 | v2,
                .SHR => v1 >> node.imm,
            };
            values[i + 2] = result;
        }
        return values[self.used + 1]; // Last node result
    }

    pub fn executeSymbolic(self: GraphProgram) [64]domain_base.Dependency {
        var deps = [_][64]domain_base.Dependency{undefined} ** (MaxNodes + 2);
        for (&deps) |*row| {
            for (row) |*d| d.* = .{ .x = 0, .y = 0 };
        }
        
        // Init inputs
        for (0..64) |b| {
            deps[0][b].x = @as(u64, 1) << @as(u6, @intCast(b));
            deps[1][b].y = @as(u64, 1) << @as(u6, @intCast(b));
        }

        var i: usize = 0;
        while (i < self.used) : (i += 1) {
            const node = self.nodes[i];
            const d1 = deps[node.src1];
            const d2 = deps[node.src2];
            var res = &deps[i + 2];

            switch (node.op) {
                .XOR, .AND, .OR => {
                    for (0..64) |b| {
                        res[b].x = d1[b].x | d2[b].x;
                        res[b].y = d1[b].y | d2[b].y;
                    }
                },
                .SHR => {
                    for (0..64) |b| {
                        if (b + node.imm < 64) {
                            res[b] = d1[b + node.imm];
                        }
                    }
                },
                .ADD, .SUB => {
                    var acc_x: u64 = 0;
                    var acc_y: u64 = 0;
                    for (0..64) |b| {
                        acc_x |= d1[b].x | d2[b].x;
                        acc_y |= d1[b].y | d2[b].y;
                        res[b].x = acc_x;
                        res[b].y = acc_y;
                    }
                },
            }
        }
        return deps[self.used + 1];
    }
};

pub fn randomNode(rng: *u64, used_so_far: u8) Node {
    const max_src = used_so_far + 2;
    const smix = domain_base.smix;
    rng.* = smix(rng.*);
    const op: Op = @enumFromInt(rng.* % 6);
    rng.* = smix(rng.*);
    const s1: u4 = @intCast(rng.* % max_src);
    rng.* = smix(rng.*);
    const s2: u4 = @intCast(rng.* % max_src);
    rng.* = smix(rng.*);
    const imm: u6 = @intCast(rng.* % 64);
    return .{ .op = op, .src1 = s1, .src2 = s2, .imm = imm };
}

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
    const smix = domain_base.smix;
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
