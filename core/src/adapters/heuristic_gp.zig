const std = @import("std");

pub const DOMAIN_NAME: []const u8 = "heuristic-genetic-programming";

pub const NodeType = enum(u4) {
    // Terminals (Variables from search physics)
    VELOCITY = 0,
    STAGNATION = 1,
    ENTROPY = 2,
    CONSTANT = 3,
    PHASE = 10, // Normalized progress (0.0 to 1.0)
    // Operations
    ADD = 4,
    SUB = 5,
    MUL = 6,
    DIV = 7,
    GT  = 8,
    LOG = 9,
};

pub const Node = struct {
    op: NodeType,
    left: u8 = 0,  // Index of left child (0 if terminal)
    right: u8 = 0, // Index of right child
    val: f64 = 0,  // Constant value if op == CONSTANT
};

pub const Inputs = struct { vel: f64, stag: f64, ent: f64, phase: f64 };

pub const Expression = struct {
    nodes: [32]Node,
    used: u8,
    root: u8,

    pub fn evaluate(self: Expression, inputs: Inputs) f64 {
        return self.evalNode(self.root, inputs);
    }

    fn evalNode(self: Expression, idx: u8, in: Inputs) f64 {
        const n = self.nodes[idx];
        return switch (n.op) {
            .VELOCITY => in.vel,
            .STAGNATION => in.stag,
            .ENTROPY => in.ent,
            .PHASE => in.phase,
            .CONSTANT => n.val,
            .ADD => self.evalNode(n.left, in) + self.evalNode(n.right, in),
            .SUB => self.evalNode(n.left, in) - self.evalNode(n.right, in),
            .MUL => self.evalNode(n.left, in) * self.evalNode(n.right, in),
            .DIV => {
                const b = self.evalNode(n.right, in);
                return if (@abs(b) < 0.000001) 1.0 else self.evalNode(n.left, in) / b;
            },
            .GT => if (self.evalNode(n.left, in) > self.evalNode(n.right, in)) 1.0 else 0.0,
            .LOG => @as(f64, @log(@max(0.000001, @abs(self.evalNode(n.left, in))))),
        };
    }
};

pub fn randomExpression(rng: *u64, depth: u8) Expression {
    var expr = Expression{ .nodes = undefined, .used = 0, .root = 0 };
    expr.root = buildRandomTree(&expr, rng, depth);
    return expr;
}

fn buildRandomTree(expr: *Expression, rng: *u64, depth: u8) u8 {
    const idx = expr.used;
    expr.used += 1;
    
    if (depth == 0 or (nextRand(rng) % 10 < 3)) {
        // Terminal
        const terminals = [_]NodeType{ .VELOCITY, .STAGNATION, .ENTROPY, .CONSTANT, .PHASE };
        const t_op = terminals[nextRand(rng) % terminals.len];
        expr.nodes[idx] = .{ .op = t_op, .val = @as(f64, @floatFromInt(nextRand(rng) % 100)) / 10.0 };
    } else {
        // Operation
        const op: NodeType = @enumFromInt(4 + (nextRand(rng) % 6));
        const l = buildRandomTree(expr, rng, depth - 1);
        const r = buildRandomTree(expr, rng, depth - 1);
        expr.nodes[idx] = .{ .op = op, .left = l, .right = r };
    }
    return idx;
}

fn smix(x: u64) u64 {
    var z = x +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

fn nextRand(rng: *u64) u64 {
    rng.* = smix(rng.*);
    return rng.*;
}

pub fn printExpr(expr: Expression, idx: u8, writer: anytype) !void {
    const n = expr.nodes[idx];
    switch (n.op) {
        .VELOCITY => try writer.writeAll("VEL"),
        .STAGNATION => try writer.writeAll("STAG"),
        .ENTROPY => try writer.writeAll("ENT"),
        .PHASE => try writer.writeAll("PHASE"),
        .CONSTANT => try writer.print("{d:.2}", .{n.val}),
        else => {
            try writer.writeAll("(");
            try printExpr(expr, n.left, writer);
            try writer.print(" {s} ", .{@tagName(n.op)});
            try printExpr(expr, n.right, writer);
            try writer.writeAll(")");
        },
    }
}
