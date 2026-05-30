# BitForge

A collection of standalone research projects exploring **automated bit-vector synthesis** and **verified kernel discovery** in Zig. The repository focuses on high-performance program synthesis, leveraging SMT solvers (Z3) and statistical testing (PractRand) to discover optimal hash mixers and sorting networks.

## Core Architecture

| Folder | Name | Description |
|--------|------|-------------|
| [`core/`](core/) | **BitForge Core** | Shared engine library — reusable synthesis modules (Linear, State, Flux, VSA-Baseline). Exposed as public Zig modules. |
| [`synthesis_probes/`](synthesis_probes/) | **Synthesis Probes** | The primary synthesis line: Core synthesis, consultation probes, and adapter modules. |
| [`01_baseline_engines/`](01_baseline_engines/) | **Baselines** | Linear / VSA-era engine benchmarks (Linear/State/Flux vs VSA baseline). |
| [`02_heuristic_search/`](02_heuristic_search/) | **Heuristic Search** | Early experiments in geometry-mapped search and novelty-pressure probes. |
| [`03_standard_synthesis/`](03_standard_synthesis/) | **Standard Synth** | Direct synthesis using Zig stdlib only (Gen0/1/2, no VSA). |
| [`04_verified_synthesis/`](04_verified_synthesis/) | **Verified Synth** | DomainSpec program synthesis + the Z3 formal verification pipeline. |
| [`05_meta_synthesis/`](05_meta_synthesis/) | **Meta-Synthesis** | The hierarchical synthesis stack — research on multi-tier optimization and affine-closure proofs. |

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
