// Centralized test root for `zig test src/tests.zig`
// NOTE: compiler_loop.zig is excluded because it imports void.zig which requires
// the 'flame' module only available via build.zig. Test it via `zig build test`.
comptime {
    _ = @import("ghost_codebook");
    _ = @import("ghost_topology");
    _ = @import("ghost_ast_emitter");
    _ = @import("sandbox");
}
