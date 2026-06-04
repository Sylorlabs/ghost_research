const std = @import("std");
const prover = @import("native_prover");
pub const MotorBridge = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MotorBridge {
        return .{ .allocator = allocator };
    }

    pub fn triggerAutonomousBuild(self: *MotorBridge, new_logic: []const u8) !void {
        // 1. Write the new kernel logic
        var kernel_file = try std.fs.cwd().createFile("src/logic_kernel.zig", .{});
        defer kernel_file.close();
        try kernel_file.writer().writeAll(new_logic);

        // 2. Trigger the Build System
        var child = std.process.Child.init(&[_][]const u8{ "zig", "build" }, self.allocator);
        const term = try child.spawnAndWait();

        if (term.Exited != 0) {
            return error.CompilationFailed;
        }
    }

    pub fn lift(self: *MotorBridge, aig: prover.Aig, root_id: prover.NodeId) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        errdefer buf.deinit();
        const w = buf.writer();

        try w.writeAll("pub fn synthesized_logic(x: u64, y: u64) u64 {\n");
        try w.writeAll("    return ");
        try self.emitNode(aig, root_id, w);
        try w.writeAll(";\n}\n");

        return buf.toOwnedSlice();
    }

    fn emitNode(self: *MotorBridge, aig: prover.Aig, id: prover.NodeId, w: anytype) !void {
        if (id == 0) { try w.writeAll("0"); return; }
        if (id == 1) { try w.writeAll("0xFFFFFFFFFFFFFFFF"); return; }

        const idx = id >> 1;
        const inv = (id & 1) != 0;

        if (inv) try w.writeAll("~(");

        const node = aig.nodes.items[idx];
        if (node.left == 0 and node.right == 0) {
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