// Centralized test root for `zig test src/tests.zig`
// NOTE: compiler_loop.zig is excluded because it imports void.zig which requires
// the 'flame' module only available via build.zig. Test it via `zig build test`.
comptime {
    _ = @import("ghost_codebook");
    _ = @import("ghost_topology");
    _ = @import("ghost_ast_emitter");
    _ = @import("sandbox");
}

const std = @import("std");
const vsa = @import("../../core/src/vsa.zig"); // Path relative to synthesis_probes/src/tests.zig

test "VSA operations: bundle, permute, bind, similarity" {
    const a = vsa.Hypervector.initRandom(1234);
    const b = vsa.Hypervector.initRandom(5678);

    // Similarity
    const sim_ab = a.similarity(b);
    try std.testing.expect(sim_ab >= -0.2 and sim_ab <= 0.2); // Orthogonal vectors
    try std.testing.expect(a.similarity(a) == 1.0);

    // Bundle
    const bundled = a.bundle(b);
    try std.testing.expect(bundled.similarity(a) > 0.0);
    try std.testing.expect(bundled.similarity(b) > 0.0);

    // Permute
    const shifted = a.permute(1);
    try std.testing.expect(shifted.similarity(a) < 0.2); // Shifted is orthogonal
}
