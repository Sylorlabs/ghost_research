// Centralized test root for `zig test src/tests.zig`
// NOTE: compiler_loop.zig is excluded because it imports void.zig which requires
// the 'flame' module only available via build.zig. Test it via `zig build test`.
comptime {
    _ = @import("semantics/concept_codebook.zig");
    _ = @import("semantics/topology.zig");
    _ = @import("compiler/ast_emitter.zig");
    _ = @import("oracle/sandbox.zig");
}
