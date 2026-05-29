# ghost_research

A collection of standalone research projects exploring automatic invention /
program synthesis in Zig. The repository was originally one monolithic build of
~128 executables sharing a single `src/`; it has been split so the top level is
**project folders**, each independently buildable, all sharing one engine
library (`core/`).

> Open `ghost_research`, pick a project folder, step in, `zig build`.

## Layout

| Folder | What it is | Build target count |
|--------|------------|-----|
| [`core/`](core/) | Shared engine library — every reusable engine/module (flame, void, flux, vsa, the invention/domain engines, the meta-engine family, oracle/compiler). Exposed as public Zig modules; the projects depend on it. | 3 dual-role exes |
| [`ghost_engines/`](ghost_engines/) | The "ghost engine" line: Ghost Core, synthesis probes, consultation probes, void/absolute/infinity/null adapters. Architecture docs live here. | 54 |
| [`01_reservoir_engines/`](01_reservoir_engines/) | Reservoir / VSA-era engine benchmarks (Flare/Flame/Flux/Fractal/Frost vs VSA baseline). | 6 |
| [`02_early_invention/`](02_early_invention/) | Early geometry / "alien" invention engines and novelty probes. | 13 |
| [`03_conceptless_chain/`](03_conceptless_chain/) | Conceptless std-only invention chain (Gen0/1/2, no VSA). | 6 |
| [`04_program_synthesis/`](04_program_synthesis/) | DomainSpec program synthesis + the Z3 verification pipeline. | 9 |
| [`05_meta_stack/`](05_meta_stack/) | The meta-engine stack — research threads 05 (meta-engine stack), 06 (mega research round) and 07 (affine-closure proof) as `docs/{05,06,07}/`. | 37 |

Each project folder contains its own `build.zig`, `build.zig.zon` (a path
dependency on `../core`), `src/` (its leaf executable sources), and `docs/`.

### Shared data & tooling (top level, not projects)

These stay at the repository root because the code references them by hardcoded
relative path and the scripts orchestrate binaries across several projects:

- `results/` — experiment outputs (CSV/logs). Engines write here relative to
  the repo root; run binaries from the repo root so the paths resolve.
- `state/` — persisted `.bin` engine state.
- `corpus/` — text corpora for the reservoir/VSA experiments.
- `scripts/` — reproducibility / falsifier harnesses. They locate binaries with
  a `bin <name>` helper that searches every `*/zig-out/bin`, so build the
  relevant projects first, then run a script from the repo root.
- `RESEARCH_INDEX.md` — the detailed chronological narrative of the seven
  research threads (read this for the *story*; per-thread docs live in each
  project's `docs/`).

## Building

There is **no top-level build**; build each project independently:

```sh
cd core && zig build               # the shared library (also builds 3 dual-role exes)
cd 04_program_synthesis && zig build   # any project; resolves ../core automatically
```

Binaries land in each project's `zig-out/bin/`. The z3-linked targets
(`verify_cli`, `verify_qflia_smoke`, `affine_closure`) require a system `libz3`
under `/usr/lib/x86_64-linux-gnu`. Requires **Zig 0.14.1**.

## How `core` works

`core/build.zig` exposes every shared source as a **public named module** and
wires them into a full mesh (each core module can `@import` any other by name —
mirroring the original engine wiring, guaranteeing one instance of each engine).
A project consumes them via:

```zig
const core = b.dependency("core", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("flame", core.module("flame"));
```

Each project offers every exe the full core module set; an import costs nothing
unless the source actually `@import`s it (Zig compiles a module only on use).

## Research narrative

See [`RESEARCH_INDEX.md`](RESEARCH_INDEX.md) for the seven threads in
chronological order, each with its findings and caveats. Every project's
`docs/` folder also carries a `DISCLAIMER.md` stating what was true when those
experiments ran versus what was later revised — **the research evolved fast and
later threads contradict earlier assumptions; check the disclaimer before
mixing results across threads.**

## Related

The sibling project [`../wcore/`](../wcore) is a separate (currently skeleton)
zero-bias invention engine; it does not depend on this repository.
