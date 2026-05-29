# ghost_engines

The original "ghost engine" line: the Ghost Core probe, the synthesis-probe
family (one binary per `src/synthesis/*.zig`), the consultation probes, and the
void / absolute / infinity / null adapters. Architecture docs are in
`docs/architecture/`.

```sh
zig build      # 54 executables (incl. ghost_core, chat, ghost_search, ...)
```

Depends on `../core`. Archived stubs under `src/archived_cores/placeholders/`
and the test roots are kept as sources but are not built. See ../README.md.
