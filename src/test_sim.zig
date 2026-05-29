const std = @import("std");
const vsa = @import("vsa.zig");
pub const Role_Type = vsa.Hypervector.initRandom(0x33333333);
pub const Role_Parameter = vsa.Hypervector.initRandom(0x44444444);
pub fn main() !void {
    const s = Role_Type.similarity(Role_Parameter);
    std.debug.print("Sim: {}\n", .{s});
}
