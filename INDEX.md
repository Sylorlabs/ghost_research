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

**2026-07-10c round: all round-b successor problems resolved** (see
`docs/research/research_round_2026_07_10c.md`, 6/6): conjunction wall CROSSED by
a stepping-stone curriculum (frontier reach 0→6/9, mechanism descriptors fail);
evidence lenses SATURATE battery-C 33/33 by exact GF(2) identification (the
(1/3)^k wall was an estimator artifact); C09/D08 reach gap closed by a
comparison-aggregate family (+11 flips, 0 regressions; D08 was a selection bug,
C09 proven family-level by Bayes ceilings); greedyFit scale fix *strengthened*
the Tier 8 effect to 0/24-vs-22/24 and exposed B3's silent leak; the 0.95
matcher was falsified (4.2% false-equals) and replaced by an exact protocol
that is correct AND cheaper; the assembled engine coheres (every battery's best
simultaneously) and is the new production default.

**2026-07-11 round (Round E): the arc's law quantified + both levers mapped**
(see `docs/research/research_round_2026_07_11.md`, 6/6): E5 — reach ≈
representable ? aim-decides : 0 (representability a threshold gate R²=0.65, aim a
phase boundary above it, diversity a proxy for representability); E1 —
representability grows by hand (+2 targets) with a three-part boundary
(family-unlocked / unreachable core ORDER2 / the RUN1 certifier-boundary); E3 —
the machine CAN auto-discover a missing mechanism with a structural prior smaller
than a hand curriculum (0/9→6/9 where blind bulk fails); E2 — aim automates
(router 92%); E4 — aim buys efficiency not ceiling (LABS N=61 plateau); E6 — the
85/86 headline survives the coevo matcher audit. **Five-round arc closed
(32 experiments): machine invention is gated by representability, steered by aim;
the missing generator is machine-findable but only with a small structural prior.**

**2026-07-11b round (Round F): representability expansion compounds, full
autonomy remains open** (see `docs/research/research_round_2026_07_11b.md`,
6/6): F2 machine-discovers ORDER2's missing comparison family (1.000, four
seeds, zero regressions); F4 shows promoted mechanisms compound through 5/10
cheap compositions and priors transfer 9/10 vs 2/10 cold; F5's assembled loop
coheres at 58/73 vs hand 59/73, with smart generation supplying reach and the
router saving 32.2% evaluations; F3 catches a 33% novelty-gate false-rejection
rate. The headline F1 selector is invalid/inconclusive, so F6's measured result
remains 66.7% machine-supplied insight and 85–90% remains projected.

**2026-07-11c round (Round G): live, with the instrument repaired and the
current selector negatively resolved** (see
`docs/research/research_round_2026_07_11c.md`, 4/5 settled): G1's frozen
multi-feature COVER novelty decision repairs F3's battery (7/9→9/9; novel
false rejections 2/6→0/6, no remix admits); G2 supplies a valid 20/20,
leakage-clean production-derived prior corpus; G3 is a **valid negative**
(six-descriptor 1-NN 0/4 held-out vs fixed 1/4); G4 is a constrained positive
(grammar/parameter prior invention 1.000 on three seeds plus holdout).
**G5 is correctly blocked, not missing:** an end-to-end autonomous routing
claim cannot use G3's known-failing selector.

**2026-07-12 round (Round H): settled constrained direct proposal, not general
autonomy** (see `docs/research/research_round_2026_07_12.md`): H5 moves v6
novelty certification into a live loop (4/4 correct vs legacy 2/4); H3/H6
reliably propose and v6-promote 2/3 held-out directed variants, producing an
assembly score of 3/4 vs hand 4/4 and fixed/cold 1/4. H1 is a valid negative
(richer static descriptors still 1/4 holdout), so H2 is not run. H4 narrows
the positive to a human-supplied singleton regime: equal-budget blind directed
search exact-hits 56–69%, and a representable two-cell partition fails the
singleton admission signal. The next frontier is search-response representations
that can license both singleton and multi-cell directed structures.

**2026-07-12b round (Round I): settled negative for cheap response-driven
admission/allocation** (see `docs/research/research_round_2026_07_12b.md`):
I2 symmetrically recovers singleton through fresh four-cell partitions and
rejects unrelated controls, but I5 measures it as a 2,540-call train+validation
near-solve; I4 finds blind random competitive in the supplied finite grammar;
I3 is a valid negative (guided 9/15 = fixed 9/15). Crucially, I5 invalidates
I1's supposed uniform response atlas: its declared 1,524-candidate partition
probe duplicates 254 members of the actual 1,270 grammar. **No autonomous
general-prior claim survives; I6 is correctly blocked.**

**2026-07-12c round (Round J): sampler repaired, trajectory allocation still
negative** (see `docs/research/research_round_2026_07_12c.md`): J1 proves a
correct 1,270-key sampler; J2 initially separates 4/4 route families at 216
calls, but J5 narrows it to a fixed-order labelled-evaluator signature (order
sensitive and its `none` class is adjacency). J4 then fails the decisive
equal-cost test: guided trajectory allocation 10/12 vs fixed coverage 12/12
at 600 calls; J5 independently confirms it. **No autonomous allocation claim
survives; J6 is correctly blocked.**

**2026-07-12d round (Round K): adaptive allocation remains negative under a
fresh holdout** (see `docs/research/research_round_2026_07_12d.md`): K1 shows
the old fixed policy wins through broad finite coverage (a 127-call witness on
its frozen battery); K2 yields a limited, labelled-evaluator-only
permutation-invariant route representation; K4 supplies a deterministic
post-freeze 24-target hidden suite. The decisive K3 comparison is a **valid
negative** at 600 charged calls: adaptive 10/24 = fixed 10/24 = blind 10/24,
with IID 9/24. K5 independently confirms the ledger and warns that the
holdout boundary is procedural rather than process-isolated. **No autonomous
allocation claim survives; K6 is correctly blocked.**

**2026-07-12e round (Round L): a safe experiment bench works, but map-guided
family transfer does not yet** (see `docs/research/research_round_2026_07_12e.md`):
L1/L2 are controlled trace-map and blank-detection positives; L3 now supplies
opaque diagnostics and charged candidate queries without formula/mask/audit
fields. The revised L4 therefore runs an honest equal-cost expedition and
finds one exact sealed win (12/12 versus 10/12), but misses its other blank
target (10/12 versus 11/12), so the two-target transfer criterion is a **valid
negative**. L5 confirms the result and adds the hard limits: query scoring
reuses exposed labels, padding calls lack per-call rows, and the boundary is
protocol-level rather than OS-isolated. **The bench is adopted; autonomous
map expansion is not.**

**2026-07-13 round (Round M): the bounded map→split→propose→fresh-test loop
works under enforced accounting** (see
`docs/research/research_round_2026_07_13.md`): M1 replaces recorded-only
budgets with a persistent evaluator-owned 12-call ledger; M2 splits controlled
blank traces 12/12 versus 6/12 unsplit; M3 measures fresh within-region
transfer 48/48 versus cross/control 24/48; M4 derives a two-production public
grammar and reaches 48/48 fresh versus menu 24/48. The assembled M5 loop then
reaches **72/72 fresh tests versus fixed 36/72 and blind 54/72**, at exactly
29 individually logged calls per arm/target. M6 fresh-cache replay confirms
the accounting, privacy, order, and train/test controls. **This is a narrowed
controlled strict positive:** the supplied synthetic generator intentionally
aligns public trace direction with two fixed bit predicates, and evaluator
isolation remains protocol-level—so it is not open-ended autonomous
map-making.

**2026-07-14 round (Round N): removing trace-to-tool leakage removes the
closed-loop advantage** (see `docs/research/research_round_2026_07_14.md`):
N1/N2 establish an evaluator-owned, trace-decoupled substrate (router equals
family prior; exact counterfactual trace-only bound is chance); N3's controlled
failure memory ranks primitives 12/12 versus family prior 6/12 and blind 4/12.
But N4's decisive fresh evaluation is a **valid negative**: history grammar
4/8 beats fixed atoms 0/8 but ties blind composition 4/8 and transfers to only
one hidden kind. **The Round M loop was exploiting trace-to-tool alignment;
memory alone does not yet choose a tool for a genuinely fresh decoupled target.
N5/N6 are correctly blocked.**

**2026-07-14b round (Round O): active information acquisition restores a
bounded decoupled-loop advantage** (see
`docs/research/research_round_2026_07_14b.md`): O1/O3 establish that base
trace remains at prior while a charged aggregate probe supplies conditional
information without formula/ID leakage; O2 learns probe choice (12/12 versus
fixed/blind 9/12 and no-probe 6/12); O4 commits a grammar before fresh score
and reaches 16/16 versus controls 8/16. The new three-cohort O5 active loop
then reaches **24/24 fresh versus fixed/blind/no-probe 12/24** at four
persistent calls per arm/target. O6 independently confirms the accounting and
commitment ordering. **This is a controlled strict positive, narrowed because
published per-token post-commit scores are protocol-sealed rather than
score-private; probe/history/grammar/evaluator remain supplied.**

**2026-07-14c round (Round P): answer-free experience can forge a bounded
measurement and operation** (see
`docs/research/research_round_2026_07_14c.md`): P1/P3 establish a
score-private, no-answer-join protocol (identity/family/fresh-answer attacks
at chance); P2's canonical causal notebook improves permitted calibration
choice 12/12 versus blind 2/12. From generic supplied Boolean/count atoms,
P4 composes a count-then-compare measurement (12/12 versus parity 6/12) and
P5 composes a reusable operation with aggregate fresh success **24/24 across
three hidden kinds**, versus raw/fixed 0/24 and blind 8/24. P6 confirms all
claims under fresh-cache replay, 288 equal-cost actions, aggregate-only
closure, and answer-recovery attacks. **This is an audited bounded toolmaker,
not an open-world inventor:** substrate, causal classes, evaluator, and
protocol-only isolation remain supplied.

**2026-07-14d round (Round Q): a bounded provenance-safe material expedition
works** (see `docs/research/research_round_2026_07_14d.md`): Q1 supplies a
typed content-addressed approved material registry; Q2 scouts answer-free
residuals 12/12 versus prior/blind 4/12; Q3 admits only 2/11 qualified
materials. Q4 forges a count+relation material (24/24 versus components/fixed
0/24 and blind 8/24), and the full Q5 expedition repeats **24/24 across three
fresh cohorts** versus fixed/prior 0/24 and blind 8/24 at equal six-call cost.
Q6 confirms 675-row provenance/accounting/answer-boundary replay. **This is a
controlled approved-fixture expedition, not literal external-world material
discovery:** no live corpus/web/world adapter is yet used and isolation remains
protocol-level.

**2026-07-14e round (Round R): foundations landed; real-world architecture is
still gated** (see `docs/research/research_round_2026_07_14e.md`): R1's
evaluator service passes protocol denial/replay checks (6 sealed sessions,
aggregate-only closure) but is not hostile same-user isolation; R2 autonomously
discovers and governs local public documents with provenance/quarantine but
truthfully reports no live network adapter; R3's answer-free structured
refinery wins **12/12** against raw/prior **4/12**, but uses labelled fixture
receipts. **These are reproducible limited foundations, not completion of the
outside-world inventor:** atom expansion, messy-world transfer, and
architecture certification are blocked until real read-only acquisition and a
separately protected evaluator are installed.

**2026-07-15 round (Round S): real-world architecture closure launched** (see
`docs/research/research_round_2026_07_15.md`): this is the direct repair of
Round R's two missing prerequisites—self-managed live public-source acquisition
and evaluator isolation that holds beyond a same-user protocol boundary. S1–S3
run in parallel; any atom expansion, messy-world transfer, or architecture
completion claim remains gated on real captures, answer-free principle learning,
and an enforceably protected evaluator.

**2026-07-15b round (Round T): grounded representation birth launched** (see
`docs/research/research_round_2026_07_15b.md`): a separate local research
track for non-language invention. It starts from raw causal dynamics rather
than LLM text, fixed symbols, or a supplied tool grammar, and uses Ghost
Engine's VSA-free Rune/Sigil evidence lineage and exact verifier discipline
read-only. Its first gate is narrow but real: a mechanism must emerge, predict,
and transfer on fresh sealed worlds beyond fixed/random/replay/named-feature
controls before heredity or open-endedness is claimed.

**2026-07-15b update (Round T): representation birth has not been earned**
(see `docs/research/research_round_2026_07_15b.md`): T1's raw mutable field
beats fixed/random/replay controls (0/184 held-out errors versus 110/22/110),
but that gain follows from a human-installed shared response-surface topology,
so it is a **valid negative** rather than a concealed success. T2 establishes a
bounded 48-scratch/22-committed challenge ecology; T3's eight anti-cheat checks
pass but correctly blocks a fixture with no raw-causal lineage. **The actual
frontier is representation/topology birth itself, not more search within a
supplied substrate.**

**2026-07-15c round (Round U): the growing apprentice launched** (see
`docs/research/research_round_2026_07_15c.md`): U1 lets executable topology,
memory, timing, and mutation structure grow; U2 starts Rune experience empty
and requires independent prediction/intervention/transfer evidence for
promotion, with contradiction-driven demotion and retirement; U3 grows fresh
worlds using machinery structurally independent of the learner. Heredity and
accumulation remain gated on transfer beyond fixed/random/replay/equal-size and
task-aligned controls. **Growth means earned capability per cost, not more
bytes or a permanently expanding static memory.**

**2026-07-15c update (Round U): growth machinery works, representation growth
does not yet** (see `docs/research/research_round_2026_07_15c.md`): U1's grown
body scores 1110/2304 fresh errors, beating random 1154 and fixed/replay 1192,
but losing to equal-size static 1098 and the supplied emulator 0; it is also
encoding-sensitive, so the result is a **valid negative** for reusable
representation birth. U2 establishes empty-start earned/reversible Rune memory
with 8/8 attacks passing; U3 establishes a controlled 41/48 committed growing-
world ecology. **Heredity remains blocked: experience and worlds can grow, but
the organism has not yet earned its own invariant perceptual/action structure.**

**2026-07-15d round (Round V): the mutant organism launched** (see
`docs/research/research_round_2026_07_15d.md`): V1 places all organism-owned
code, data, topology, scheduling, development, and mutation operators in a
mutable VM; V2 lets organisms recruit and compose raw observation/action ports;
V3 tests separate lifetime adaptation and generational evolution against an
independent growing-world ecology. The sandbox, evaluator, resource meter, and
provenance remain immutable universe physics. **Inheritance must be earned by
frozen causal transfer, not birth fitness, copied trajectories, or body size.**

**2026-07-15d update (Round V): the mutant can change itself but does not yet
ground itself** (see `docs/research/research_round_2026_07_15d.md`): V1 reaches
all organism fields and 64/64 tape cells and its encoded mutator changes
descendant distributions, yet its narrow transfer edge is encoding-sensitive.
V2 exposes the main failure: perfect matched-wiring behavior (0/1536) becomes
3777/9216 errors after shifts, including 1343 under actuator remapping—it
learned addresses, not consequences. V3 provides a controlled 12-generation
two-timescale ecology without adaptive reproductive selection. **The next
frontier is active causal port grounding and reconstruction after rewiring;
mutation breadth alone is not intelligence.**

**2026-07-15e round (Round W): sense genesis launched** (see
`docs/research/research_round_2026_07_15e.md`): W1 grows receptors/effectors
over evaluator-owned raw fields instead of assigning semantic ports; W2 removes
human tasks, curricula, novelty scores, and prediction rewards in favor of
immutable energy/damage/persistence/reproduction physics; W3 tests whether
organisms reconstruct functional body/world maps after unseen organ rewiring.
**The organism may mutate every structure and preference it owns, but it may
not rewrite the universe's resource ledger, evaluator, provenance, or sandbox.**

**2026-07-15e update (Round W): causal information is present, autonomous sense
genesis is not** (see `docs/research/research_round_2026_07_15e.md`): W1
reconstructs shifted organs at 24/3072 errors, far beyond address/random/replay
controls, but its grounding protocol is human-installed. W2's mutable
development loses to fixed probing (1275 vs 1300 viable ticks; 2/24 vs 7/24
recoveries) and no policy sustains reproduction. W3's consequence procedure
beats address/no-probe but loses random/equal-static probing (514 vs 492/478
errors). **The next frontier is mutation and selection of the experiment-making
process itself: probes, alignment, comparison, and scheduling—not merely senses
and actions.**

**2026-07-15f round (Round X): experiment birth launched** (see
`docs/research/research_round_2026_07_15f.md`): X1 puts probe construction,
scheduling, normalization, comparison, stopping, and mutation behavior inside
raw mutable organism bytes; X2 removes supplied temporal alignment and metrics;
X3 selects experiment-makers only through descendants' later resource physics,
not grounding, novelty, prediction, or human-usefulness scores. **The experiment
procedure must earn itself through downstream transfer just as senses, actions,
and Runes must earn themselves.**

**2026-07-15f update (Round X): experiment bytes matter, but selection cannot
yet build the experimenter** (see
`docs/research/research_round_2026_07_15f.md`): X1 makes all procedure and
mutator fields reachable but remains 96/192 through development and loses
strong random/static controls. X2's narrow temporal gain relies on supplied
comparison/lag structure and collapses under recoding. X3's evolved lineage
beats weak and ablation controls but loses a fixed experimenter (1786 vs 1964
viable ticks; 9/32 vs 12/32 reproductive worlds). **The next frontier is
organism-internal developmental credit from delayed resource consequences—not
more mutation breadth or another human intermediate objective.**

**2026-07-15g round (Round Y): earned developmental credit launched** (see
`docs/research/research_round_2026_07_15g.md`): Y1 mutates internal structural
responsibility residues; Y2 lets organisms purchase paired sibling developments
that differ by self-selected edits; Y3 earns Rune fragments only through
repeated add/remove/recombine downstream resource counterfactuals. No grounding,
prediction, novelty, or correctness score is exposed. **A structural change
earns preservation only when its later causal resource contribution replicates
and transfers.**

**2026-07-15g update (Round Y): delayed credit works only inside supplied
responsibility units** (see `docs/research/research_round_2026_07_15g.md`): Y1
beats its controls (16/32 reproductive worlds) but receives the originating
action slot; Y2's causal edit ablation is real but its paired method loses
random/fixed controls and receives eight edit addresses; Y3 finds the exact
best causal fragment mask, yet humans supplied two-byte boundaries and signed
add/remove deltas. **The frontier is responsibility-unit birth: the organism
must invent what counts as a change, event, fragment, and causal comparison—not
only learn credit inside our partitions.**

**2026-07-15h round (Round Z): the causal mine launched** (see
`docs/research/research_round_2026_07_15h.md`): Z1 records content-addressed
mutation→activity→action→world→resource lineage while keeping causality
intervention-earned; Z2 measures and searches executable materials with costs,
transfer, brittleness, uncertainty, contradictions, and preserved negatives;
Z3 converts failure evidence into answer-free capability requests and lets an
autonomous forge search/compose/mutate implementations. **Self-improvement is
not assumed: Z4 may run only after these foundations pass, and must show a
sealed before/after gain plus rollback and causal ablation.**

**2026-07-15h update (Round Z): the X-ray and mine work; the request forge does
not self-improve** (see `docs/research/research_round_2026_07_15h.md`): Z1
establishes byte-replayable causal lineage with exact cost conservation and 11
attacks passing. Z2's opaque material mine reaches resource 1445 versus 1299
for the strongest ordinary control, predicts held-out property signs 11/12,
and prevents 12 repeated failures. Z3's guided forge loses request-free search
(2034 vs 2094 viable ticks), and removing its forged structure improves to
2055. **Self-improvement remains gated: reliable evidence storage is now
available, but failure evidence has not yet generated useful synthesis
direction.**

**2026-07-15i round (Round AA): the fully autonomous improvement loop
launched** (see `docs/research/research_round_2026_07_15i.md`): AA1 makes the
organism construct its own uncertainty-reducing experiments from Z1/Z2 evidence;
AA2 keeps material search, synthesis, abstention, installation, and ablation
inside the organism; AA3 requires the organism to identify its own causal
bottleneck and prepares equal-start old/new evaluation. **There is no external
builder or implementation request. Humans may only approve genuinely new
authority; every achievable improvement step must be performed internally.**

**2026-07-15i update (Round AA): autonomous diagnosis remains the blocker**
(see `docs/research/research_round_2026_07_15i.md`): AA1's internal experiments
lose strong controls (loss 3446 versus replay 3191), while false evidence drives
the supplied uncertainty measure to zero without capability gain. AA2 correctly
abstains with zero forge charges instead of building from invalid lineage. AA3
selects a causal bottleneck 24/24 and its candidate improves resource
30680→37640 with exact ablation, but humans supplied eight component boundaries
and no implementation was invented. **The next direction must come from
disagreement between executable causal mechanisms and ordinary resource
outcomes—not a human-shaped uncertainty number.**

**2026-07-15j round (Round AB): self-built rooms launched** (see
`docs/research/research_round_2026_07_15j.md`): AB1 begins from a uniform
mutable self and lets causal partitions split/merge/overlap/dissolve; AB2 makes
multiple organism-built executable self-models generate distinguishing
self-interventions; AB3 removes human-origin privilege and tests internally
constructed replacements for bootstrap instruments. **Every organism-owned
human scaffold is an unverified competitor, never authority; evidence may
replace and retire it.**

**2026-07-15j update (Round AB): the organism can replace scaffolds but does
not yet own its mutation ontology** (see
`docs/research/research_round_2026_07_15j.md`): AB1's variable rooms score
90416 versus ordinary 59288 but inherit “subset of cells” grammar and recover
0/32 exact causal rooms. AB2 inherits a model container/decoder and loses strong
controls. AB3 internally builds a causally real replacement (91736→148616,
ablation exactly restores old, false evidence rolls back 20/20), yet humans
still provide raw-byte edit units and the proposal generator. **The frontier is
self-generation of mutation scales, boundaries, encodings, and proposal
process—not merely choosing and replacing inside human edit geometry.**

**2026-07-15k round (Round AC): organism-owned invention physics launched**
(see `docs/research/research_round_2026_07_15k.md`): AC1 tests endogenous
creation and replacement of mutation units and scales; AC2 tests executable
proposal programs that reproduce and replace the proposal process itself; AC3
tests functional reconstruction after wholesale relocation, value recoding,
and resegmentation. **The host supplies only universe physics and sealed
accounting. Human-written organism scaffolds have no authority or permanent
status. AC4–AC6 remain gated until these foundations pass.**

**2026-07-15k update (Round AC): useful self-modification still lives inside
human transition physics** (see
`docs/research/research_round_2026_07_15k.md`): AC1's mutation words produce an
ablatable 52735 versus raw-bit 42612 gain; AC2's recursive proposers improve
93563→101963 with false-evidence rollback; AC3 relearns 91534→144574 after
combined relocation, recoding, and resegmentation. All three are valid
negatives: the host still defines interpreters, primitive interventions, VM
meanings, scheduling, genome/byte boundaries, candidate generation, and commit
geometry. **Do not add more human opcodes. The next frontier is organism-built
interpreters in a lower-level causal medium, followed by causal retirement of
the bootstrap interpreter and reconstruction after wholesale instruction and
boundary re-encoding.**

**2026-07-16 round (Round AD): open-ended organism construction launched**
(see `docs/research/research_round_2026_07_16.md`): AD1 asks mutable matter to
construct and retire a higher-level interpreter; AD2 asks organisms to create
their own escalating challenge ecology and transfer to hidden worlds; AD3 asks
them to construct a representation-to-behavior transducer and migrate through
it. **No human task menu, instruction set above raw physics, target, or answer
score may be supplied. The only fixed layer is enforcement physics; every
organism-level mechanism must earn its continued existence from consequences.**

**2026-07-16 update (Round AD): open-ended behavior remains inside a supplied
micro-language** (see `docs/research/research_round_2026_07_16.md`): AD1's
macro configuration gain is real but uses a host decoder and opcodes; AD2's
ecology beats random/replay but is bounded by fixed cells, candidate language,
world physics, and cadence; AD3 migrates 44089→54957 through combined hostile
transport, but fixed-decoder and equal-language controls tie it exactly. **All
three are valid negatives. The next admissible target is construction and
retirement of operational semantics themselves—not another configuration or
larger host language.**

**2026-07-16b round (Round AE): operational semantics birth launched** (see
`docs/research/research_round_2026_07_16b.md`): AE1 requires executable meaning
to be derived from raw transition traces; AE2 makes internally constructed
semantics compete and retire bootstrap meaning; AE3 tests reconstruction after
private destruction of instruction, address, value, and boundary identities.
**No host VM, decoder, probe grammar, high-level instruction meanings, target,
or semantic score may enter. A real positive must show a causal semantic the
organism itself earns, selects, needs, and can preserve after its bootstrap
identity has been destroyed.**

**2026-07-16b update (Round AE): semantic-looking behavior remains host-scored
and host-decoded** (see `docs/research/research_round_2026_07_16b.md`): AE1's
trace memory reaches 129024 from 64428 but writes inside host trace/prediction
slots; AE2 performs real commit/retirement yet fixed semantics ties at 1197;
AE3 recovers 71596→89950 after wholesale destruction but fixed decoder and
equal language tie exactly. **All three are valid negatives. The next
experiment must remove observational and comparison semantics too: organism
invention of a causal invariant in closed raw sensorimotor loops, with a fixed
equally expressive invariant as the decisive control.**

**2026-07-16c round (Round AF): endogenous criterion birth launched** (see
`docs/research/research_round_2026_07_16c.md`): AF1 asks organisms to create a
causal invariant from self-intervention traces; AF2 asks them to identify and
use a raw sensorimotor closure after rewiring; AF3 asks them to replace an old
earned criterion with a stronger one and transfer without answers. **No host
observation field, action menu, target, score, feature, comparison language,
or candidate generator is admissible. Resource survival is outside accounting;
the internal criterion must be invented, necessary, replaceable, and
reconstructible.**

**2026-07-16c update (Round AF): relation records are not self-made criteria**
(see `docs/research/research_round_2026_07_16c.md`): AF1 gains 6030→8640 but
fixed invariant ties; AF2 gains 57365→58073 but fixed closure wins 58165; AF3
replaces bootstrap relations in every cohort at 220→1833, yet fixed criterion
ties exactly. **All are valid negatives because the host still decides the
intervention/observation split, relation form, comparison and resource
acceptance. The next substrate must supply no organism-visible score or
sensor/action split: criterion-like structure must persist as a self-maintained
causal loop under raw finite-resource physics.**

**2026-07-16d round (Round AG): persistent causal loops launched** (see
`docs/research/research_round_2026_07_16d.md`): AG1 tests self-assembled,
self-restoring loops in a raw finite-resource medium; AG2 tests emergent
boundary and reproduction without a template; AG3 tests reconstruction or
evolution after private changes to interaction physics. **There is no
organism-visible reward, score, sensor/action split, relation register, or loop
grammar. The only selection is physical persistence; a real internal criterion
must be a causally necessary self-maintained constraint.**

**2026-07-16d update (Round AG): physical persistence remains template-shaped**
(see `docs/research/research_round_2026_07_16d.md`): AG1's 128-tick loop is
host-seeded/repaired and ties a fixed loop; AG2's 21807 lineage gain inherits
boundary tags, candidate/revision grammar, viability scalar and scheduler; AG3
rebuilds 566→4472 across a private physics shift but ties a fixed loop at equal
charge. **All three are valid negatives. The next medium must evolve every
particle uniformly, with no host-enumerated loop, repair, boundary, candidate,
or reproduction structure; conservation and persistence may be measured only
outside the organism after the fact.**

**Highest-priority open experiments (updated after Round Q):**
1. **Live approved-world adapter** — permit material scouting from a real,
   read-only approved corpus/simulator with content capture, provenance hash,
   quarantine, and no evaluator/test overlap.
2. **Harden score-private isolation** — move evaluator state/manifest and
   answer closure into a separately protected service/process beyond protocol.
3. **Discover the atom alphabet** — expand raw materials from causal failures
   rather than composing only the supplied fixture atoms/passports.
4. **External-family expedition transfer** — test materials/forges on task
   worlds generated independently of Q's residual/passport alignment.
5. **Records, not baselines** — LABS even-N / addchain records still require a
   representability escape, not more aim or budget.

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
