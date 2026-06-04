# BitForge

A Zig research laboratory for **automated program synthesis**, **formal verification**,
and **algebraic invention**. The central question: what are the mathematical limits of
automated invention, and how do you escape them?

**→ Start here: [`INDEX.md`](INDEX.md)** — full project map, measured results, and
reproduce commands for every key experiment.

---

## The Unifying Result

Every research thread in this repository independently ran into the same wall:

> **Closure Principle.** A search confined to a closed primitive set cannot produce a
> function outside the algebraic closure of that set. Optimising harder within the
> closure — more iterations, more tiers, better search — cannot escape it. The only
> escape is to inject a generator outside the closure.

Five independent witnesses with runnable before/after experiments:
- **Mixers** — GF(2)-affine programs provably plateau at SAC-error 0.5; ADD/MUL escapes it.
- **wcore atom-forge** — fixed opcode VM: 85/86 behaviours reducible at depth 4; 0 survive deeper budget.
- **asi_attempt control** — XOR/bundle VSA readout of band predicate: 0.51 (chance); SUM feature escapes to 11.02.
- **Meta-engine ceiling** — reproducible 44–47 fitness ceiling; monotone+parallel finally broke it to 47.49.
- **k-sparse parity** — linear model at chance for k≥2 (theorem); nonlinearity escapes it.

See [`CLOSURE_PRINCIPLE.md`](CLOSURE_PRINCIPLE.md) for the full cross-thread synthesis
and reproduction commands.

---

## Repository Layout

```
ghost_research/
├── core/                   Shared Zig library — all synthesis engines and adapters
├── synthesis_probes/       Primary synthesis line: consultation probes and adapter modules
│
├── 01_baseline_engines/    VSA/Linear baseline benchmarks
├── 02_heuristic_search/    Geometry-mapped heuristic search (abandoned)
├── 03_standard_synthesis/  VSA-free recursive synthesis chain
├── 04_verified_synthesis/  DomainSpec + Z3 formal verification pipeline
├── 05_meta_synthesis/      Hierarchical meta-program synthesis (Tier 0–4), affine-closure proof
├── 06_invention_search/    Heuristic invention + law synthesis on the meta-engine
├── 07_agent_loop/          Agent body scaffold: perception / cognition / homeostasis / motor
├── 08_blueprint_synth/     Mutation hill-climber over a blueprint domain
├── 09_distillation_probe/  Distillation / AST-reduction plan synthesis probe
├── 10_motor_synth/         Motor-plan hill-climber probe
├── 11_gateway_probe/       Compiler gateway / logic-kernel verification scaffold
├── 12_adversarial_loop/    Snapshot manager + adversarial tester loop
├── 13_causal_synth/        Causal predictor (AIG) synthesis via native prover
├── 14_novelty_probe/       Novelty-pressure / concept-divergence probe
├── 15_architecture_synth/  Architecture blueprint hill-climber
├── 16_agent_loop_live/     Full agent loop: subsystem stack in a live loop
├── 17_self_model_probe/    Subjectivity model + value-alignment gate probe
├── 18_stability_synth/     Stability-scored plan synthesizer
│
├── asi_attempt/            Primary research: Closure Principle control agent + order-statistics invention bridge
├── wcore/                  Primary research: zero-bias invention engine, irreducibility certifier, open-atom-set loop
│
├── results/                Experiment outputs (CSV / logs) — run binaries from repo root
├── state/                  Persisted engine state (.bin)
├── corpus/                 Text corpora for VSA experiments
└── scripts/                Reproducibility harnesses
```

Projects 01–05 are the core synthesis research line. Projects 06–18 are applied probes
and scaffolds built on that machinery. `asi_attempt` and `wcore` are the active primary
research lines on the Closure Principle and algebraic invention.

---

## Building

There is no top-level build. Each project builds independently against the shared `core/`:

```sh
cd core && zig build                      # shared library (build first)
cd 04_verified_synthesis && zig build     # any project resolves ../core automatically
cd asi_attempt && zig build eval          # run the control agent eval
```

Binaries land in each project's `zig-out/bin/`. Always run binaries from the **repo
root** so `results/` paths resolve correctly.

**Requirements:** Zig 0.14.1. The Z3-linked targets (`verify_cli`, `affine_closure`)
require `libz3` at `/usr/lib/x86_64-linux-gnu`.

---

## Key Results

| Result | Value | Where |
|--------|-------|-------|
| Best Tier-1 meta-engine holdout | **44.30** (seed 0x1111) | `05_meta_synthesis/docs/05/` |
| Ceiling escape (monotone + parallel + QD) | **47.49** | `docs/05/recursive_engine_phase_abc.md` |
| Affine closure proof (MUL-free ceiling) | SAC-error = 0.5 exactly (theorem) | `05_meta_synthesis/docs/07/` |
| Closure escape (mixer) | 0.5 → 0.13 (ADD) → 0.02 (MUL) | `05_meta_synthesis/src/closure_escape_mixer.zig` |
| VSA band readout ceiling | 0.51 (chance), proved | `asi_attempt/docs/research/` |
| Out-of-closure escape (SUM feature) | **11.02** fail/1k vs 162 baseline | `asi_attempt` |
| Invention bridge: diagnose + forge + promote | 6/6 correct class inference; beyond-ladder target captured | `asi_attempt/order_statistics.zig` |
| wcore: fixed atom set cannot invent | 0/86 behaviours irreducible at depth ≥5 | `wcore/inv_atomforge.zig` |
| CEGIS rediscovery of `x & (x-1)` | 3 generations, formally verified | `04_verified_synthesis` |

---

## Documentation Map

| File | Purpose |
|------|---------|
| [`INDEX.md`](INDEX.md) | **Master reference** — full project detail, source tables, open questions status, reproduce commands |
| [`CLOSURE_PRINCIPLE.md`](CLOSURE_PRINCIPLE.md) | Cross-thread synthesis of the unifying result, with five witnesses |
| [`RESEARCH_QUESTIONS.md`](RESEARCH_QUESTIONS.md) | Full open-question inventory with honesty flags (🟢 unknown / 🟡 quantifies / 🔴 confirms) |
| [`RESEARCH_INDEX.md`](RESEARCH_INDEX.md) | Chronological narrative of the seven synthesis threads |
| `<project>/docs/DISCLAIMER.md` | Per-project: what was true then vs what was later revised |

---

## Active Research Frontiers

1. **Open-atom-set promotion loop** (`wcore`, RQ A1–A9) — the only regime where
   "yes it can invent" is a possible answer; each promoted atom enlarges the closure
   for the next round.

2. **Clifford geometric-product binding** — predicted by both the Closure Principle
   (XOR/bundle parity-collapses the grid; a typed invertible bind is the out-of-closure
   generator) and external AIT theory to be the next concrete escape.

3. **Generator-family discovery by gradient** (`asi_attempt`, RQ C23) — the
   `forge + promote` loop works when the primitive family is supplied; the unsolved case
   is discovering the family structure itself without being told what to search over.

4. **Falsification hunts** (RQ I53–I56) — try hard to break the Closure Principle;
   the most valuable possible outcome is finding a counterexample.
