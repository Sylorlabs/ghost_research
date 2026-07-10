# BitForge Research — Master Index

Everything tried in this repository, in order, with honest verdicts. The research
evolved quickly; later threads directly contradict earlier assumptions. Always check
a project's `docs/DISCLAIMER.md` before mixing results across projects.

---

## The Unifying Result

The deepest result in this repository, arrived at independently across five domains:

> **Closure Principle.** A search or learning process confined to a *closed*
> primitive set cannot produce a function outside the algebraic closure of that set.
> Grinding harder within the closure — more iterations, more tiers, better
> optimisation — cannot escape it. The only escape is to inject a generator outside
> the closure.

Two corollaries, both proven/measured:
- **Ceiling corollary.** If the target lies outside the closure, performance plateaus
  at a bound set by the closure regardless of optimisation effort.
- **Escape corollary.** Adding one out-of-closure generator collapses the plateau.

See [`CLOSURE_PRINCIPLE.md`](CLOSURE_PRINCIPLE.md) for the five witnesses with
runnable before/after experiments and reproduction commands.

---

## North star — Tier 8 is the goal

Invention research in this repo targets **Tier 8**: invention of the **conditions for
invention** (instruments, certifiers, reality checks, framework revision when the loop
only produces remix). Tier 2–3 production (`invention-engine`, 11/11 blind battery) is
scaffolding, not the finish line.

| Doc | What it is |
|-----|------------|
| [`docs/research/tier8_mega_plan.md`](docs/research/tier8_mega_plan.md) | **Giant mega plan** — 7 phases, 35 agents + 12 forks, sub-agent swarm |
| [`docs/research/tier8_swarm_master.md`](docs/research/tier8_swarm_master.md) | Living agent verdict table (updated per wave) |

---

## Directory Map

```
ghost_research/
├── core/                  Shared Zig library — all synthesis modules (Linear, State, Flux, VSA, meta-engines, adapters)
├── synthesis_probes/      Primary synthesis line: consultation probes, adapter modules
├── 01_baseline_engines/   VSA/Linear baseline benchmarks
├── 02_heuristic_search/   Geometry-mapped heuristic search (abandoned)
├── 03_standard_synthesis/ VSA-free recursive synthesis chain
├── 04_verified_synthesis/ DomainSpec + Z3 formal verification pipeline
├── 05_meta_synthesis/     Hierarchical meta-program synthesis (Tier 0–3+), affine-closure proof
├── 06_invention_search/   Heuristic invention + law synthesis on top of the meta-engine
├── 07_agent_loop/         Agent body scaffold: perception/cognition/homeostasis/motor subsystems
├── 08_blueprint_synth/    Mutation hill-climber over a custom blueprint domain
├── 09_distillation_probe/ Synthesis probe: distillation/AST-reduction plan generation
├── 10_motor_synth/        Mutation hill-climber over a motor-plan domain
├── 11_gateway_probe/      Thin compiler gateway / logic-kernel verification probe
├── 12_adversarial_loop/   Snapshot manager + adversarial tester loop
├── 13_causal_synth/       Causal predictor (AIG) synthesis via native prover
├── 14_novelty_probe/      Novelty-pressure / concept-divergence probe
├── 15_architecture_synth/ Grand-blueprint mutation hill-climber (200k iters)
├── 16_agent_loop_live/    Full agent loop: perception + cognition + homeostasis + motor bridge
├── 17_self_model_probe/   Subjectivity model + value-alignment gate probe
├── 18_stability_synth/    Stability-evaluated plan synthesizer (200k iters)
├── sparse_poly_discovery/           Closure-principle control agent: VSA readout ceiling + order-statistics research
├── wcore/                 Zero-bias invention engine: atom-forge, irreducibility certifier, open-atom-set
├── results/               Experiment outputs (CSV/logs) — written relative to repo root
├── state/                 Persisted engine state (.bin files)
├── corpus/                Text corpora for reservoir/VSA experiments
└── scripts/               Reproducibility harnesses (locate binaries across projects)
```

---

## Research Threads — Chronological

### Thread 01 — Baseline Engines
**Folder:** `01_baseline_engines/`  
**Status:** Reference  
**What it is:** Linear/State/Flux/VSA benchmarks establishing the baseline. The VSA
"semantic" framing turned out non-load-bearing; gains are structural/linear.

| Source | Purpose |
|--------|---------|
| `ingestion_scale.zig` | Scale test for text ingestion throughput |
| `persistence_check.zig` | Manifold persistence (mmap) verification |
| `semantic_structure_probe.zig` | Structural probe of VSA encoding |
| `trained_semantic_bench.zig` | VSA training benchmark |
| `train_hypervectors.zig` | Hypervector training harness |
| `understanding_bench.zig` | Baseline understanding benchmark |

**Key result:** VSA hypervector coefficients are random-seeded; the "semantic
grounding" claim does not hold. Performance gains are attributable to structural
diversity, not concept binding.

---

### Thread 02 — Heuristic Search
**Folder:** `02_heuristic_search/`  
**Status:** Abandoned  
**What it is:** Geometry-mapped search and novelty-pressure probes. Superseded
by direct symbolic synthesis (DomainSpec in Thread 04).

| Source | Purpose |
|--------|---------|
| `engine_genesis.zig` | Local geometry-to-Zig compiler |
| `alien_breakthrough_inventor.zig` | Strongest heuristic engine from genesis search |
| `novelty_invention.zig` | Novelty-pressure local-only probe |
| `phase_lattice_inventor.zig` | Phase-lattice searcher |
| `search_strategy_meta.zig` | Search strategy meta-domain harness |

**Key result:** Geometric descriptors are insufficient for verifiable code generation.
Novelty-pressure search without a verifier produces plausible-looking but non-provable
output.

---

### Thread 03 — Standard Logic Synthesis
**Folder:** `03_standard_synthesis/`  
**Status:** Historical  
**What it is:** VSA-free recursive synthesis chain that established the recursive
generator pattern later formalized as DomainSpec.

| Source | Purpose |
|--------|---------|
| `conceptless_inventor.zig` | Gen0 — VSA-free synthesis probe |
| `recursive_conceptless_inventor*.zig` | v1–v4 recursive improvements |
| `synthesized_conceptless_breakthrough.zig` | Breakthrough from this chain |

**Key result:** Removing VSA scaffolding did not degrade synthesis quality — confirmed
that VSA was not the source of any benchmark improvement.

---

### Thread 04 — Formal Program Synthesis (DomainSpec)
**Folder:** `04_verified_synthesis/`  
**Status:** Milestone  
**What it is:** The DomainSpec comptime-generic architecture paired with the Z3
formal verification pipeline. First formally verified synthesis results.

| Source | Purpose |
|--------|---------|
| `program_synthesis_inventor.zig` | First u64 mixer synthesis — finds 5-instruction mixers beating splitMix64 |
| `program_synthesis_bootstrap*.zig` | Bootstrap chain (v1/v2) |
| `program_synthesis_v3.zig` | v3 synthesis |
| `reachability_tester.zig` | Gen1 quality + compositional reachability gates |
| `sorting_inventor.zig` | Sort-net N=8 cross-validation |
| `verify_cli.zig` | Z3 verification CLI |
| `verify_qflia_smoke.zig` | QFLIA smoke test |

**Key results:**
- First Z3-verified mixer synthesis (5-instruction programs, all 64-bit inputs).
- CEGIS loop independently rediscovered `x & (x - 1)` in 3 generations.
- Reachability gates 20/20 — DomainSpec architecture confirmed.

---

### Thread 05 — Hierarchical Meta-Synthesis
**Folder:** `05_meta_synthesis/`  
**Status:** Active / Primary research  
**What it is:** The full multi-tier meta-program synthesis stack (Tier 0–3+), plus
the affine-closure formal proof and the 44–47 fitness ceiling experiments.

#### Tier structure

| Tier | Type | Searches over | Produces |
|------|------|---------------|---------|
| 0 | MetaProgram | u64 mixer programs | A mixer with fitness score |
| 1 | MMP | Search algorithms | A MetaProgram discoverer |
| 2 | MMMP | Search-algorithm discoverers | An MMP discoverer |
| 3+ | MMMM / QD | Quality-diversity over Tier-2 | Extended search |

#### Key results (measured, reproducible)

| Result | Value | File |
|--------|-------|------|
| Tier-1 CALL_META win rate | 3/4 seeds STRICT_DOMINATION | `docs/05/tier1_meta_engine.md` |
| Best Tier-1 holdout (seed 0x1111) | **44.30** | `docs/05/tier1_meta_engine.md` |
| Hand-coded baseline | 32.55 | same |
| Bigger budget (200 iters) | **REFUTED** — all 4 seeds worse | `docs/05/invention_engine_v2.md` |
| Monotone-retry + parallel ceiling escape | **47.16** | `docs/05/monotone_parallel.md` |
| Engine-3 + constrained init + QD | **47.23** → **47.49** | `docs/05/recursive_engine_phase_abc_2026_05_21.md` |
| Engine-4 (MMMM) best probe | 38.44 | same |
| Affine closure proof | GF(2)-affine = SAC 0.5 exactly (theorem) | `docs/07/affine_closure_tierA.md` |
| Closure escape (mixer) | 0.5 → 0.13 (ADD) → 0.02 (MUL) | `src/closure_escape_mixer.zig` |

#### Key sources (selected)

| Source | Purpose |
|--------|---------|
| `meta_engine_runner.zig` | Tier-0 single run |
| `meta_meta_chain_runner.zig` | Tier-1 chain (multi-gen, anchor-protected) |
| `mmm_chain_runner.zig` | Tier-2 chain runner |
| `champion_holdout_validation.zig` | 64-seed holdout validator |
| `closure_escape_mixer.zig` | **Closure escape demo: affine ceiling → MUL escape** |
| `affine_closure.zig` | Formal GF(2) affine-closure proof harness |
| `alien_hack_cegis.zig` | Automated CEGIS invention |
| `mmmm_qd_probe.zig` | Tier-4 quality-diversity probe |

---

### Thread 06 — Invention Search
**Folder:** `06_invention_search/` *(formerly `06_self_evolution`)*  
**Status:** Research layer on top of Thread 05  
**What it is:** Heuristic invention and law synthesis. Adds adversarial search, body-plan
search, and recursive reflection on top of the meta-engine stack.

| Source | Purpose |
|--------|---------|
| `heuristic_invention.zig` | Heuristic invention loop |
| `actual_meta_invention.zig` | Meta-invention with domain generality |
| `law_synthesizer.zig` | Law synthesis probe |
| `adversarial_gauntlet.zig` | Adversarial stress-test harness |
| `agi_blueprint_search.zig` | Blueprint search probe |
| `recursive_reflection_search.zig` | Recursive reflection search |
| `combat_benchmark.zig` | Multi-engine combat benchmark |
| `generality_tournament.zig` | Generality tournament |

**Key result:** Confirmed that engine generalisation depends on whether the target
behaviour is in the primitive closure — the earliest in-repo witness to the Closure
Principle.

---

### Threads 07–18 — Applied / Probe Projects

These projects explore specific application directions using the synthesis machinery
from Threads 01–06. Most are single-source probes or mutation hill-climbers.

| # | Folder | What it actually does | Verdict |
|---|--------|-----------------------|---------|
| 07 | `07_agent_loop/` | Multi-subsystem agent body (perception/cognition/homeostasis/motor). `PerceptionEngine` ingests source files; loop drives all subsystems. | Scaffold — no closed learning loop |
| 08 | `08_blueprint_synth/` | 100k-iter mutation hill-climber over a `randomManifesto()` blueprint domain evaluated by a scalar fitness. | Probe — identical structure to meta-engine Tier-0 |
| 09 | `09_distillation_probe/` | Synthesises distillation plans (AST node count, AIG reduction factor, efficiency gain) from a domain struct. | Probe — fixed-random, no real learning |
| 10 | `10_motor_synth/` | 100k-iter hill-climber over a motor-plan domain (action cost, torque params). | Probe |
| 11 | `11_gateway_probe/` | Verifies `logic_kernel.zig` is accessible; thin compiler/gateway integration scaffold. | Skeleton |
| 12 | `12_adversarial_loop/` | Snapshot manager + adversarial tester in a 10-step simulation loop. No real learning. | Skeleton |
| 13 | `13_causal_synth/` | Evolves a causal predictor (AIG) for next-state prediction using the native prover. | Prototype |
| 14 | `14_novelty_probe/` | Maximises distance from a seeded concept library using native prover and concept memory. Novelty-pressure divergence. | Probe — the right idea; no persistence |
| 15 | `15_architecture_synth/` | 200k-iter hill-climber over a "grand unification blueprint" domain (integrity fitness). | Probe |
| 16 | `16_agent_loop_live/` | Most complete agent loop: full subsystem stack (perception → corpus, cognition, homeostasis, motor bridge, logic kernel) in an infinite loop. | Live scaffold |
| 17 | `17_self_model_probe/` | Subjectivity model (self-hash, world-model fidelity, intention vector) + value-alignment gate. 5-step reflect/rewrite simulation. | Toy probe |
| 18 | `18_stability_synth/` | 200k-iter hill-climber over a stability-scored plan domain. | Probe |

**Shared verdict on 07–18:** These are correctly characterised as probes and scaffolds.
They build correctly, print structured output, and use the shared synthesis machinery.
None of them contains a closed learning or verification loop. They are the layer the
`CLAUDE.md` warns about — real code with theatrical framing. The machinery underneath
(DomainSpec, native prover, meta-engine) is real. The "AGI" claims in their print
statements are print statements.

---

### sparse_poly_discovery — Closure-Principle Control Agent

**Folder:** `sparse_poly_discovery/`  
**Status:** Active primary research  
**What it is:** The most disciplined research project in the repo. Implements a
reward-driven control agent over a grid-cell battery simulation, using VSA encoding.
The project's purpose is to measure the Closure Principle empirically, in a controlled
setting, and build a principled invention ladder.

#### Measured results

| Experiment | Result | File |
|------------|--------|------|
| XOR/bundle VSA readout of band predicate | **0.51** (chance) — provably at ceiling | `closure_escape_control.md` |
| Linear probe over all 8192 encoding bits | **0.51** — ceiling confirmed | `probe` build target |
| Out-of-closure escape: SUM feature (`mb_mass`) | **11.02** fail/1k — 3–15× better than XOR agents | `eval` build target |
| Tuned thermostat baseline | **0.00** — mb_mass does NOT beat hand-coded | `closure_escape_control.md` |
| Unsupervised PCA recovery of SUM direction | cosine = **0.9987** (circular case) | `feature_discovery.md` |
| Non-salient hidden feature: PCA recovery | cosine = **0.000** — circular result collapses | `feature_discovery.md` |
| Order-statistics closure lattice | Median outside {poly + max + min} — proved | `order_statistics_closure.md` |
| Invention bridge: diagnose + forge + promote | 6/6 known-class targets correctly diagnosed; parity-of-count correctly flagged beyond ladder, then forged + promoted | `primitive_class_inference.md` |
| Emergent escape (synergy) | Isolated targets need generator *pairs*; greedy one-at-a-time misses them | `emergent_escape.md` |

#### The open frontier (measured, not solved)
The `forge + promote` loop works when the primitive family is handed in — `cos(ω·count)`
is chosen knowing parity is periodic. The unsolved case: discover the *family itself*,
by gradient rather than grid search, when the needed primitive structure is unknown in
advance. This is the line between a principled feature-selector and a genuine inventor.

#### Key sources

| Source | Purpose |
|--------|---------|
| `order_statistics.zig` | Order-statistics closure lattice + invention bridge (diagnose/forge/promote) |
| `concentration_control.zig` | Max/extremal closure test |
| `parity_closure.zig` | Parity = degree-N, outside every poly closure |
| `basis_control.zig` | Basis-degree control ablation |
| `adaptive_feature.zig` | Adaptive feature discovery probe |
| `correlation_discover.zig` | Correlation-based feature discovery |
| `parallel_disagree.zig` | Parallel model-disagreement detection |
| `synergy.zig` | Emergent escape / synergy pair search |
| `hypervector.zig` | VSA encoding layer |
| `vm.zig` | Program VM for behaviour comparison |
| `agent.zig` | Control agent |
| `environment.zig` | Grid-cell battery simulation |
| `eval.zig` | Evaluation harness |

---

### wcore — Zero-Bias Invention Engine

**Folder:** `wcore/`  
**Status:** Active primary research (sibling project)  
**What it is:** A standalone invention engine with an irreducibility certifier, atom-forge,
and open-atom-set loop. The most formal treatment of the Closure Principle in the repo.

#### Measured results

| Claim | Status |
|-------|--------|
| Fixed atom set cannot invent: 85/86 behaviours reducible at depth 4; 1 exception reducible at depth 5; 0 survivors at deeper budget | **Confirmed** (`inv_atomforge.zig`) |
| Irreducibility certifier: 16/16 kill-tests, non-vacuous at depth 8 | **Confirmed** |
| Atom promotion (open-atom-set): first positive result on RQ A1 | **Prototyped** |

#### Key sources

| Source | Purpose |
|--------|---------|
| `inv_atomforge.zig` | Atom-forge: search for behaviours irreducible to current atom set |
| `inv_library.zig` | Atom library with promotion mechanism |
| `inv_evolve.zig` | Evolutionary search over the atom set |
| `inv_open.zig` | Open-atom-set loop (RQ A1–A9) |
| `inv_coevo.zig` | Coevolution probe |
| `checker.zig` | Irreducibility certifier |
| `evaluator.zig` | Behaviour comparison and test harness |
| `law.zig` | Law/rule representation |

---

## Core Library

**Folder:** `core/`  
**What it is:** Shared Zig module mesh. Every named module is a public dependency
available to all project `build.zig` files via `b.dependency("core", ...)`.

| Module class | Examples |
|-------------|---------|
| Engine layers | `flame`, `void`, `flux`, `fractal`, `frost`, `flare` |
| VSA substrate | `vsa`, `lore`, `manifold`, `aether` |
| Meta-engine tiers | `domain_meta_engine`, `domain_meta_meta_engine`, `domain_meta_meta_meta_engine` |
| Chain runners | `meta_meta_chain_runner`, `mmm_chain_runner` |
| Adapters | `native_prover`, `domain_agi_*` (probe adapters — see note) |
| Synthesis probes | `domain_meta_architect`, `domain_concept_memory` |

**Note on `domain_agi_*` adapters:** These are thin struct definitions (30–60 lines) that
define a domain for a specific probe in projects 08–18. They are not load-bearing inference
or learning modules. Each is documented by the project that uses it.

---

## Research Questions — Status Summary

Full list with honesty flags at [`RESEARCH_QUESTIONS.md`](RESEARCH_QUESTIONS.md).

| Section | Topic | Open / Done |
|---------|-------|-------------|
| A1–A9 | Open-atom-set promotion loop | Partially prototyped (wcore) |
| A10 *(proposed)* | Clifford binding vs XOR/bundle: does it break the VSA band ceiling? | **Not started** |
| B10–B18 | wcore engine knobs (DMAX, budget, coevolution) | Mostly open |
| C19–C28 | sparse_poly_discovery control: planning, nonlinear features, multi-objective | Partially done |
| D29–D35 | Mixer / meta-engine ceiling and superoptimization | Thread 05–07 done; D32–D34 open |
| E36–E40 | Closure principle theory | Closure Principle confirmed; decidability open |
| F41–F45 | Discovery ladder sample complexity | Partially mapped in sparse_poly_discovery |
| G46–G49 | Instrument validation | #46 done; #48–#49 open |
| H50–H52 | Scaling laws | Open |
| I53–I56 | Falsification hunts — try to break our own claims | Ongoing |
| J57–J60 | External-ingredient experiments (real code, real datasets) | Needs external data |

**2026-07-10 round: the previous four priorities are all now done** (see
`docs/research/research_round_2026_07_10.md` for the full eight-experiment round):
A10 replicated with controls (0.508→0.976); A1–A6 measured (no fixed point,
escapes mostly unaimed, corrected held-out 3/18→4/18); G49 cross-audit 5016/5016;
I53 falsification refuted the emergent-pair block and strengthened the core
principle (u2 infinite-depth fixpoint). Plus: Tier 8 revision proven load-bearing
by ablation; tax gate settled (measurement-only); H50 closure-exhaustion law;
two externally-verified dial-3 campaigns (LABS, addchains).

**2026-07-10b round: priorities 1–3 answered same day** (see
`docs/research/research_round_2026_07_10b.md`): aimed escapes WORK but only at
selection boundaries (battery-C wall 3/33→8/33; first structured-family solves
via gate-level aiming; fitness-level aiming fails 0/9); the v5-ladder gate
breaks the admission/discrimination trade-off (51/51 remix blocked, 6/6
escapes admitted — "novel" is closure-relative); Claim-C certifier leak
bounded at 5%, front-loaded at +1 depth, closable at ~1s/candidate (new thin
axis: the 0.95 matcher, margin 0.008); Tier 8 effect size now 1/9 vs 9/9 on
battery-D; LABS N=44/50 matched best-known, no even-N skew analogue exists.

**Highest-priority open experiments (updated after round b):**
1. **The conjunction-wall class** — distinct-count (climb plateau 0.862 vs the
   0.95 bar), C09's family miss, D08's reachability gap: stepping-stone
   curricula / mechanism-level descriptors; measured target 0.862 → ≥0.95
2. **Better evidence lenses** — the aiming signal decays as (1/3)^k under the
   current lens; raise the signal to reach degree ≥5 targets
3. **Instrument fixes + falsification** — greedyFit raw-vs-z-scored scale
   mismatch (battery-D leak); attack the 0.95 statistical matcher (0.008
   kill-test margin), not depth
4. **Adopt the settled architecture** — v5-ladder at the verdict layer, +1-depth
   promotion gate in wcore, aim/taxes at selection boundaries only
5. **Records, not baselines** — LABS even-N needs new theory or B&B compute;
   Flammenkamp/Clift addchain comparisons (J57–J60); H51/H52 still open

---

## Reproduce the Core Results

```bash
# The five closure witnesses
cd sparse_poly_discovery && zig build eval         # mb_mass 11.02 beats XOR; tuned thermostat = 0.00
cd sparse_poly_discovery && zig build probe        # band readout at chance under XOR/bundle
cd 05_meta_synthesis && zig build -Doptimize=ReleaseFast && ./zig-out/bin/closure_escape_mixer
cd sparse_poly_discovery && zig build parity       # linear 0.50 → MLP 1.0

# The invention bridge
cd sparse_poly_discovery && zig build order-stats -- diagnose   # 6/6 correct class inference
cd sparse_poly_discovery && zig build order-stats -- forge       # beyond-ladder forge + promote

# Meta-engine ceiling
cd 05_meta_synthesis && zig build -Doptimize=ReleaseFast
./05_meta_synthesis/zig-out/bin/meta_meta_chain_runner --monotone-retries=10

# Formal verification
cd 04_verified_synthesis && zig build && ./zig-out/bin/verify_cli
```

---

## Conventions

- **Results go in `results/`** (relative to repo root). Run binaries from repo root.
- **Per-project docs** live in `<project>/docs/`. Each has a `DISCLAIMER.md`.
- **`RESEARCH_INDEX.md`** has the full chronological narrative of Threads 01–07.
- **`CLOSURE_PRINCIPLE.md`** is the cross-thread synthesis of the unifying result.
- **`RESEARCH_QUESTIONS.md`** is the full open-question inventory with honesty flags.
