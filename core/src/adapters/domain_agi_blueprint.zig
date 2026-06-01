const std = @import("std");
const domain_base = @import("domain_alien_hack");

pub const DOMAIN_NAME: []const u8 = "agi-topological-blueprint";

pub const MaxNodes = 24;
pub const Inputs = 8;  
pub const Internal = 16; 
pub const Outputs = 8; 

pub const Op = enum(u4) {
    MIX = 0,    
    GATE = 1,   
    RECURSE = 2, 
    COMPRESS = 3, 
};

pub const Node = struct {
    op: Op,
    src1: u8,
    src2: u8,
    src3: u8,
    imm: u6,
};

pub const AGISystem = struct {
    nodes: [MaxNodes]Node,
    used: u8,

    pub fn executeSymbolic(self: AGISystem) f64 {
        var deps = [_]u64{0} ** (Inputs + Internal + MaxNodes);
        for (0..Inputs) |i| deps[i] = (@as(u64, 1) << @as(u6, @intCast(i)));

        var i: usize = 0;
        while (i < self.used) : (i += 1) {
            const n = self.nodes[i];
            const d1 = deps[n.src1 % (Inputs + Internal + i)];
            const d2 = deps[n.src2 % (Inputs + Internal + i)];
            const d3 = deps[n.src3 % (Inputs + Internal + i)];
            deps[Inputs + Internal + i] = d1 | d2 | d3;
        }

        var total_connectivity: usize = 0;
        for (0..Outputs) |o| {
            total_connectivity += @popCount(deps[Inputs + Internal + self.used - 1 - o]);
        }
        return @as(f64, @floatFromInt(total_connectivity));
    }
};

pub fn randomSystem(rng: *u64, len: u8) AGISystem {
    var sys = AGISystem{ .nodes = undefined, .used = len };
    for (0..len, 0..) |_, i| {
        sys.nodes[i] = randomNode(rng, @intCast(i));
    }
    return sys;
}

pub fn mutate(sys: AGISystem, rng: *u64) AGISystem {
    var q = sys;
    rng.* = domain_base.smix(rng.*);
    const idx = rng.* % q.used;
    q.nodes[idx] = randomNode(rng, @intCast(idx));
    return q;
}

fn randomNode(rng: *u64, idx: u8) Node {
    rng.* = domain_base.smix(rng.*);
    const s1: u8 = @intCast(rng.* % (Inputs + Internal + idx));
    rng.* = domain_base.smix(rng.*);
    const s2: u8 = @intCast(rng.* % (Inputs + Internal + idx));
    rng.* = domain_base.smix(rng.*);
    const s3: u8 = @intCast(rng.* % (Inputs + Internal + idx));
    rng.* = domain_base.smix(rng.*);
    const imm: u6 = @intCast(rng.* % 64);
    return .{
        .op = @enumFromInt(rng.* % 4),
        .src1 = s1,
        .src2 = s2,
        .src3 = s3,
        .imm = imm,
    };
}
