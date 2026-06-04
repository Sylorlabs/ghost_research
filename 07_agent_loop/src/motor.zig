const std = @import("std");
const prover = @import("native_prover");

pub const MotorEngine = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) MotorEngine {
        return .{ .allocator = allocator };
    }

    /// Lift fulfills the machine's 'EMIT_FUNCTION' and 'LIFT_GATE' directives.
    /// It translates a single AIG node into a valid Zig expression string.
    pub fn lift(self: *MotorEngine, aig: prover.Aig, root_id: prover.NodeId) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        errdefer buf.deinit();
        const w = buf.writer();

        try w.writeAll("pub fn synthesized_logic(x: u64, y: u64) u64 {\n");
        
        // 1. MAP_VARIABLE: Simple register allocation
        // For the PoC, we only emit a single expression for the root node.
        try w.writeAll("    return ");
        try self.emitNode(aig, root_id, w);
        try w.writeAll(";\n}\n");

        return buf.toOwnedSlice();
    }

    fn emitNode(self: *MotorEngine, aig: prover.Aig, id: prover.NodeId, w: anytype) !void {
        if (id == 0) { try w.writeAll("0"); return; }
        if (id == 1) { try w.writeAll("0xFFFFFFFFFFFFFFFF"); return; }
        
        const idx = id >> 1;
        const inv = (id & 1) != 0;
        
        if (inv) try w.writeAll("~(");

        const node = aig.nodes.items[idx];
        if (node.left == 0 and node.right == 0) {
            // Input node: map to x or y
            if (idx % 2 == 0) try w.writeAll("x") else try w.writeAll("y");
        } else {
            try w.writeAll("(");
            try self.emitNode(aig, node.left, w);
            try w.writeAll(" & ");
            try self.emitNode(aig, node.right, w);
            try w.writeAll(")");
        }

        if (inv) try w.writeAll(")");
    }
};