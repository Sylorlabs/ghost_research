const std = @import("std");

// The real tests live in tests.zig (run: `zig build unit-test`) and the
// reproducible control benchmark is the eval harness (`zig build eval`). This
// binary is kept only because build.zig's `run` step points at it.
pub fn main() !void {
    std.debug.print(
        \\ghost_harness is a stub.
        \\  zig build unit-test   - VSA / agent unit tests (tests.zig)
        \\  zig build eval        - control benchmark (eval.zig)
        \\
    , .{});
}
