# core — shared engine library

Every reusable source in the project: the Ghost engine modules (flame, void,
flux, vsa, vsa_decoder, aetheric, sovereign, lore, manifold, the archived
cores, semantics, compiler/ast_emitter, oracle/compiler_loop), the invention
engine and the whole `domain_*` / meta-engine family, `smt_verify`, the oracle
sandbox, and the orphan engines (frost/fractal/flare/echo/omni/aether).

`build.zig` exposes each file as a **public named Zig module** and wires them
into a full mesh, so any core module can `@import` any other by name. The
per-project builds consume these via `b.dependency("core", .{...}).module(name)`.

```sh
zig build      # builds the 3 dual-role exes: anchor_readout,
               # mul_free_challenge, sovereign_interface
```

Not a research thread — a library. See ../README.md for the overall layout.
