const std = @import("std");
const domain_base = @import("domain_alien_hack");

pub const DOMAIN_NAME: []const u8 = "agi-objective-synthesis";

// The machine evolves its own "Success Metric" (the fitness function).
pub const ObjectiveNode = struct {
    op: enum(u2) { ADD, MUL, DIV, LOG },
    term: enum(u2) { VITALITY, COMPLEXITY, CONNECTIVITY, CONSTANT },
    val: f64,
};

pub const ObjectiveFunction = struct {
    nodes: [8]ObjectiveNode,
    used: u8,

    pub fn evaluate(self: ObjectiveFunction, metrics: struct { vitality: f64, complexity: f64, connectivity: f64 }) f64 {
        var score: f64 = 0.0;
        for (self.nodes[0..self.used]) |n| {
            const val = switch (n.term) {
                .VITALITY => metrics.vitality,
                .COMPLEXITY => metrics.complexity,
                .CONNECTIVITY => metrics.connectivity,
                .CONSTANT => n.val,
            };
            switch (n.op) {
                .ADD => score += val,
                .MUL => score *= val,
                .DIV => score /= @max(0.001, val),
                .LOG => score += @log(@max(0.001, val)),
            }
        }
        return score;
    }
};

pub fn randomObjective(rng: *u64) ObjectiveFunction {
    var obj = ObjectiveFunction{ .nodes = undefined, .used = 4 };
    for (0..4) |i| {
        rng.* = domain_base.smix(rng.*);
        obj.nodes[i] = .{
            .op = @enumFromInt(rng.* % 4),
            .term = @enumFromInt((rng.* >> 2) % 4),
            .val = @as(f64, @floatFromInt(rng.* % 10)) / 2.0,
        };
    }
    return obj;
}
