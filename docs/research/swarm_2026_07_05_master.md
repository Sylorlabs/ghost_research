# Swarm research session — master report (2026-07-05)

**North star:** [**Tier 8 is the goal**](tier8_mega_plan.md) — invention of conditions for invention (instruments, framework revision, reality anchoring). This report covers the Tier 2–3 swarm wave that precedes it.

**Status:** 27 primary experiments + 8 forks; goal-session additions below (2026-07-06).
**Repo:** `/home/micah/Desktop/Sylorlabs/ghost_research`

One subagent per open research question from the 2026-07-05 experiment queue. Fork agents ran on PASS/FAIL hits that opened new questions.

---

## Executive summary

| Category | PASS | FAIL / bounded | Forks |
|----------|------|----------------|-------|
| Instrument trust (G48–G49, I54–I55) | 4/4 after G48 fix | — | G48 AND/SHL fixed |
| Menu / routing / invention | 8/8 | — | RQ1++ 11/11, triple+quad arity |
| Control agent | 3/5 | EXP-8 planning marginal | — |
| wcore atoms | 4/4 | EXP-12: 0 survivors D≤12 | — |
| Theory / landscape | 3/3 | EXP-17 no unified predictor | — |
| Verified synthesis | 3/3 | — | — |
| Sample complexity | 2/2 | — | — |

**Strongest new results:**
1. **RQ1++ staged escalation: 11/11** blind battery without pre-listed spectral menu (`swarm_fork_rq1_escalation.md`)
2. **Pair hardness router: 6/6 match brute, 2.5× cheaper** (`swarm_exp02_pair_router.md`)
3. **Triple + quad arity growth: ceilings broken, wall relocates** (`swarm_fork_triple_arity.md`)
4. **function_hardness → routing priors: 19/19 = 100%** (`swarm_exp18_routing_priors.md`)
5. **G48/G49 instrument fixes: toAig PASS, Z3 cross-audit 99/99**

**Honest failures (valuable):**
- mb_mass does **not** beat tuned thermostat (0.00 vs 11.02) — escape ≠ solve (`swarm_exp10_thermostat.md`)
- Planning barely beats greedy band control (EXP-8 FAIL)
- No single algebraic-degree predictor across 5 witnesses (EXP-17)
- E4-G00 mint genuinely novel but **0** downstream lift (`swarm_fork_e4_g00_mint.md`)

---

## Primary experiments

| ID | Question | Verdict | Key number | Doc |
|----|----------|---------|------------|-----|
| **G48** | `toAig` faithful? | **PASS** (after fix) | 0 mismatches (was 34,302) | `swarm_g48_toaig_audit.md` |
| **G49** | Native prover vs Z3 | **PASS** | 99/99 agree | `swarm_g49_z3_cross_audit.md` |
| **I54–I55** | `behaviorMatches` stress | **PASS** | 0 verdict flips 32→4096 | `swarm_i54_i55_behavior_matches.md` |
| **EXP-1** | Menu-growth hidden pair | **PASS** | 0.591→1.000 | `swarm_exp01_menu_growth.md` |
| **EXP-2** | Pair hardness router | **PASS** | 6/6, 2.5× cheaper | `swarm_exp02_pair_router.md` |
| **EXP-3** | Clifford relational | **KEEP niche** | oriented 1.000 vs product 0.583 | `swarm_exp03_clifford_relational.md` |
| **EXP-4** | RQ1 gap (no menu) | **6/11** | 5 saturated | `swarm_exp04_rq1_gap.md` |
| **EXP-5** | RQ9 taxonomy | **83% repro** v2 | E4-G00 genuinely novel | `swarm_exp05_rq9_taxonomy.md` |
| **EXP-6** | Learned guide | **PASS** | 7/7, 1.45× certify | `swarm_exp06_learned_guide.md` |
| **EXP-7** | Verify-learn gen | **PASS** | 5/10 iters=0 warm | `swarm_exp07_verify_learn_gen.md` |
| **EXP-8** | Planning vs greedy | **FAIL** | H=3: 10.92 vs 11.02 | `swarm_exp08_planning.md` |
| **EXP-9** | Two-feature band | **PASS** | 35.40 vs 39.02 single | `swarm_exp09_two_feature.md` |
| **EXP-10** | Thermostat tune (I56) | **CONFIRMED** | hand 0.00, mb_mass 11.02 | `swarm_exp10_thermostat.md` |
| **EXP-11** | Multi-objective | **PARTIAL** | learners on Pareto, not both axes | `swarm_exp11_multi_objective.md` |
| **EXP-12** | DMAX 10–12 push | **PASS** (null result) | 0 survivors @ D≤12 | `swarm_exp12_dmax_push.md` |
| **EXP-13** | Atom minimization | **PASS** | 13→11 atoms | `swarm_exp13_atom_minimize.md` |
| **EXP-14** | Invented-on-invented | **PASS** | 764 late-flip, 437 IoI | `swarm_exp14_invented_on_invented.md` |
| **EXP-15** | Synergy atoms | **PASS** | 2 pairs (AND,SUB), (OR,MUL) | `swarm_exp15_synergy_atoms.md` |
| **EXP-16** | Escape counterexamples | **Principle survives** | 4 naive-corollary fails | `swarm_exp16_escape_counterexamples.md` |
| **EXP-17** | Degree predictor | **NO unified R²** | R²≈0.12 | `swarm_exp17_degree_predictor.md` |
| **EXP-18** | Hardness routing | **PASS** | 19/19 routes | `swarm_exp18_routing_priors.md` |
| **EXP-19** | Beat gcc -O3 | **PASS** | 3/3 bit-hacks | `swarm_exp19_beat_gcc.md` |
| **EXP-20** | Weird bit-hacks | **PARTIAL** | 3/9 certified, 1 novel | `swarm_exp20_weird_hacks.md` |
| **EXP-21** | Non-MUL ops | **PASS** | MUM matches MUL SAC | `swarm_exp21_non_mul_ops.md` |
| **EXP-22** | Parity phase boundary | **PASS** | k=2→4 sample cliff mapped | `swarm_exp22_parity_phase.md` |
| **EXP-23** | Sample curve F43 | **PASS** | 10 detect / 1000 recover | `swarm_exp23_sample_curve.md` |

---

## Fork experiments (triggered by hits)

| Fork | Trigger | Verdict | Key number | Doc |
|------|---------|---------|------------|-----|
| **G48-fix** | G48 FAIL | **PASS** | 0 mismatches | `swarm_g48_toaig_audit.md` |
| **RQ1++** | EXP-4 6/11 | **PASS** | **11/11** | `swarm_fork_rq1_escalation.md` |
| **E4-G00** | EXP-5 novel survivor | **KEEP** | ~0.46 held-out, 0 lift | `swarm_fork_e4_g00_mint.md` |
| **Triple-arity** | EXP-1 pair ceiling | **PASS** | triple 1.000, quad next | `swarm_fork_triple_arity.md` |
| **Quad-arity** | Triple fork | **PASS** | quad 1.000, quint next | `swarm_fork_quad_arity.md` |
| **Quint-arity** | Quad fork | **PASS** | quint 1.000, CEILING BROKEN | `swarm_fork_quint_arity.md` |
| **RQ1++ production** | Unified loop wire-in | **PASS** | 7/7 unified + pair/Walsh stages | `unified_invention.zig` |
| **Invention engine** | Production entrypoint | **PASS** | **11/11** blind B, growable menu, 372 battery evals | `invention_engine.zig` |
| **Baseline compare** | Invention vs 4 baselines | **PASS** | 11/7/3/2/2 solved; 372 vs 2320/6160 evals (battery-only) | `invention_baseline_compare.zig` |
| **E26 tax v2** | Equivalence remix | **PARTIAL** | 17/20 repro, 3 novel | `open_invention_e26.md` |

---

## Goal session verification (2026-07-06)

| Gate | Command | Result |
|------|---------|--------|
| **Invention engine ×2** | `zig build invention-engine --release=fast` | **11/11** both runs, 372 battery evals, growable menu path |
| RQ1++ blind battery ×2 | `zig build open-invention-rq1 --release=fast` | **11/11** both runs |
| Baseline harness | `zig build invention-baseline-compare --release=fast` | invention **11/11**, beats all 4 baselines on solve rate **and** eval count, PASS |
| Quint menu growth ×2 | `zig build menu-growth --release=fast` | Target 7 **1.000**, CEILING BROKEN ✓ |
| Unified production ×2 | `zig build unified-invention --release=fast` | **7/7** solved |
| Learned guide | `zig build learned-guide-test --release=fast` | 7/7, **1.45×** certify |
| E26 equivalence tax | `zig build open-invention-e26 --release=fast` | 17/20 repro, 3 genuinely novel |

Scratch logs: `/tmp/grok-goal-f34e4448a3af/implementer/`

---

## Reproduce key new harnesses

```bash
# Instruments
cd 04_verified_synthesis && zig build z3_cross_audit  # or standalone per swarm_g49 doc
cd 05_meta_synthesis && zig build toaig_audit         # if build step added

# sparse_poly — routing & invention (production entrypoint first)
cd sparse_poly_discovery && zig build invention-engine --release=fast      # 11/11 blind B, growable menu
cd sparse_poly_discovery && zig build invention-baseline-compare --release=fast
cd sparse_poly_discovery && zig build pair-hardness-router-test --release=fast
cd sparse_poly_discovery && zig build open-invention-rq1 --release=fast   # RQ1++ 11/11
cd sparse_poly_discovery && zig build learned-guide-test --release=fast
cd sparse_poly_discovery && zig build menu-growth --release=fast

# boundary_crossing
cd boundary_crossing && zig build swarm-exp07 --release=fast

# wcore
cd wcore && zig build run-invent -- exp14
cd wcore && zig build run-invent -- atomminimize
cd wcore && zig build run-invent -- matchstress 0xD00D

# function_hardness + synthesis
cd function_hardness && zig build export-top --release=fast
cd 05_meta_synthesis && zig build swarm-exp19 swarm-exp20 swarm-exp21 --release=fast
```

---

## Open forks (next session)

1. **Swarm runtime dispatcher** — `swarm_fork_dispatch.zig` for fork-on-PASS agent loops (docs-only today)
2. **E26 equivalence tax** — 85% reproducible; genuine novelty rate still low
3. **Learned guide → verify_learn_invent REPL** — interactive English→certified loop (7/7 certify path exists)

---

## File index (all swarm docs)

| Path |
|------|
| `docs/research/swarm_2026_07_05_master.md` (this file) |
| `docs/research/swarm_g48_toaig_audit.md` |
| `docs/research/swarm_g49_z3_cross_audit.md` |
| `docs/research/swarm_exp16_escape_counterexamples.md` |
| `docs/research/swarm_exp17_degree_predictor.md` |
| `sparse_poly_discovery/docs/research/swarm_exp01..23, swarm_fork_*` |
| `boundary_crossing/docs/research/swarm_exp06, swarm_exp07` |
| `wcore/docs/research/swarm_exp13..15, swarm_i54_i55` |
| `function_hardness/docs/research/swarm_exp18_routing_priors.md` |
| `05_meta_synthesis/docs/research/swarm_exp19..21` |

See per-doc files for measured tables, caveats, and reproduction commands.