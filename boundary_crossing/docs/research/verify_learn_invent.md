# VERIFY-LEARN-INVENT — learn from certification, not next-token guessing

**Status:** built, measured (2026-06-30). Reproduce:
```
cd boundary_crossing && zig build verify-learn-invent --release=fast
```
Interactive REPL: `zig build verify-learn-invent --release=fast -- --repl`  
Live terminal grounding: `zig build verify-learn-invent --release=fast -- --live`

## The thesis

Transformers minimize `-log P(next_token | context)` — pure guess, no ground truth at inference.  
This engine: **hypothesis → execute → VERIFIER → update ONLY on certified outcomes.**

Three coupled loops:
1. **VERIFY-LEARN routing** — perceptron trained on verifier labels (CERTIFIED/SURPRISE/FAILED), not corpus next-token prediction.
2. **INVENT** — real certifiers: addition chains (dial-3), gzip compression, hardness-routed / unified discovery.
3. **EXPLORE UNKNOWN** — hidden targets; substrate probe decides escalation path.

---

## Unified invention integration

`discover_feature` now calls the **full** `sparse_poly_discovery/unified_invention.zig` loop
(monomial forge → operator menu → world pool), not a spectral-only probe.

### Architecture

```
English "discover the hidden feature"
        │
        ▼
┌───────────────────────────────────────────────────────────────────┐
│  verify_learn_invent.zig                                          │
│  ┌─────────────┐   ┌─────────────────────────────────────────┐  │
│  │ intent      │   │ discover_feature backend                  │  │
│  │ perceptron  │──▶│ unified.runSingleTarget(parity_of_count)  │  │
│  └─────────────┘   │   Phase 1: monomial forge (saturate?)     │  │
│                    │   Phase 2: operator menu (spectral/Walsh/ │  │
│                    │            Clifford) — certifier: escape    │  │
│                    │            ≥0.90 held-out AND R²<0.40      │  │
│                    │   Phase 3: world pool (sum/sign % mod_p)    │  │
│                    └──────────────────┬──────────────────────────┘  │
│                                       │ @import("unified_invention")│
└───────────────────────────────────────┼───────────────────────────┘
                                        ▼
                    ┌───────────────────────────────────────┐
                    │ sparse_poly_discovery/                │
                    │   unified_invention.zig               │
                    │   runFullBenchmark() — 7 targets    │
                    │   runSingleTarget()  — 1 target       │
                    └───────────────────────────────────────┘

Phase 2  (parity certified domain): local hardness router — probe mono≈0.5 → menu
Phase 2b (routing battery):          Q38 hardness-router analog (3 hidden targets)
Phase 2c (unified benchmark):      runFullBenchmark(seed=0xF0235A11CE0FF1CE)
```

### Integration approach

**Option (a) chosen:** `build.zig` module import — cleanest compile-time link, no subprocess parsing.

```zig
// boundary_crossing/build.zig
const unified_invention_mod = b.addModule("unified_invention", .{
    .root_source_file = b.path("../sparse_poly_discovery/unified_invention.zig"),
});
e.root_module.addImport("unified_invention", unified_invention_mod);
```

Exported API added to `unified_invention.zig`:
- `runFullBenchmark(alloc, out, seed, verbose) !BenchmarkSummary`
- `runSingleTarget(alloc, out, spec, seed, verbose) !{ solved, cov, source }`

### Measured numbers (ReleaseFast, 2026-06-29)

| Phase | Metric | Result |
|-------|--------|--------|
| **Phase 2** (hardness-routed parity) | route / acc | `operator_menu` / **1.000** CERTIFIED |
| **Phase 2c** (unified 7-target) | inner_forge alone | **5/7** solved |
| **Phase 2c** (unified 7-target) | unified loop | **7/7** solved |
| **Phase 2c** | beyond monomial-only | **2** targets unlocked |
| **Phase 3** `discover_feature` | unified backend | parity **1.000** via operator menu |
| **Phase 3** | English invention | **4/4** certified/surprise |

Per-target unified coverage (Phase 2c):

| Target | Coverage | Source |
|--------|----------|--------|
| T1 sign φ{2,5} (deg2) | 1.000 | forge |
| T2 sign φ{1,3,6} (deg3) | 1.000 | forge |
| T3 sign φ{0,4,5,7} (deg4) | 1.000 | forge |
| T4 sign(c3−MID) (deg1) | 1.000 | base |
| T5 parity-of-count | 1.000 | **menu** ← inner_forge cannot |
| T6 oriented v1>v0 | 1.000 | base |
| T7 sum(g) % 7 = 0 | 1.000 | **world** ← inner_forge cannot |

Certifier: escape ≥0.90 held-out accuracy from below 0.90 **AND** irreducible R²<0.40 on the promoted feature.

### Honest limits

1. **No NL→TargetSpec parser** — English routes via trained perceptron to `discover_feature`, which defaults to
   `parity_of_count`; the 7-target benchmark uses structured `{kind, mask?, modulus?}` specs, not loose prose.
2. **Runtime cost** — full unified benchmark (~7 targets × forge rounds × certifier) takes several minutes in
   ReleaseFast; Phase 2c dominates wall time.
3. **Shared library growth** — `runFullBenchmark` compounds features across targets (realistic invention);
   `runSingleTarget` uses a fresh library (single discover intent).
4. **Hardness router vs unified certifier** — Phase 2 local router uses held-out acc≥0.90 only; unified loop
   additionally requires escape + R² irreducibility. Both certify parity; unified is stricter on promotion.
5. **Domain scope** — grid predicates + mod_p world pool only; no text, commands, or open-world perception.
6. **AGI not claimed** — invention under formal specs with sound proofs, not general intelligence.

---

## Pure verifier-learned routing

Keyword cheats **removed** from `classify()` — routing is perceptron-only plus content-word abstention
(stopwords like `it`, `the` trigger OOS if no content tokens remain).

**Corpus:** 84 phrases (12 paraphrases × 7 intents), 80/20 train/holdout split.

| Stage | Held-out (17) | Novel (4) |
|-------|---------------|-----------|
| BEFORE (untrained weights) | 1/17 = **5.9%** | — |
| AFTER bootstrap (supervised seed) | 12/17 = **70.6%** | **4/4** |
| AFTER verify-learn session | 12/17 = **70.6%** | **4/4** |

Verify-learn session uses RLVR weights: `certified=2.0×`, `surprise=3.0×`, `failed=1.0×`, `abstain=0`.
Novel phrasings maintained at 4/4; surprise teach (`cargo test` expected ok got errors) reinforces teach intent.

**vs transformer:** wins on the verification axis (certified labels); loses on open LM generation
(see `attention_replacement.md`: gpt2-124M **1.91** vs babble **2.06** BPB on held-out text).

---

## Hardness-routed discovery

Inline Q38 analog (see `sparse_poly_discovery/docs/research/hardness_router_integration.md`):

1. Probe monomial (deg1) + extremal singles (max_cell, oriented, countGE, clifford_g2).
2. Classify: `single_sufficient` / `q38_compound` / `unknown`.
3. Escalate: `monomial_sufficient` → `operator_menu` → `pair_compound` → `world_pool`.

**Phase 2b routing battery (2026-06-30):**

| Target | mono | ext | class | route | acc |
|--------|------|-----|-------|-------|-----|
| parity-of-count | 0.531 | 0.500 | q38_compound | operator_menu | **1.000** |
| sum(g)%7 | 0.849 | 0.849 | single_sufficient | world_pool | **1.000** |
| sign φ{c3} | 1.000 | 0.615 | single_sufficient | monomial_sufficient | **1.000** |

**3/3 certified** on hidden targets without being told which operator to use.

---

## Terminal grounding

`--live` runs whitelisted commands (`zig build`, `make`, `git status`, `echo`) via `std.process.Child`.
Exit code `0` → `"ok"`; else `"errors"`. Default mode uses honest `SIM` labels with `verified=false`.

| Mode | live_ran | certified_predict | surprise |
|------|----------|-------------------|----------|
| simulated (default) | 0 | **0/3** (ABSTAIN — honest) | 1 |
| `--live` | 3 | **3/3** | 0 |

- **teach:** parse `ran <cmd> expected <X> got <Y>` OR live-run; `SURPRISE` when X≠Y.
- **predict:** `CERTIFIED` only when `TermObs.verified == true`; else `ABSTAIN`.

Pattern stolen from `engine_live.zig` / `terminal_ground.zig` — terminal exit codes ARE the verifier.

---

## Phase summary

| Phase | What | Measured |
|-------|------|----------|
| 1 | Pure perceptron routing (84 phrases) | bootstrap **70.6%** held-out; novel **4/4** |
| 2 | Hardness-routed parity discovery | operator_menu, acc=**1.000** |
| 2b | Routing battery (3 hidden targets) | **3/3** certified |
| 2c | Unified invention 7-target | **7/7** |
| 3 | English → certified invention | **4/4** |
| 4 | Verify-learn session (RLVR-weighted) | held-out **70.6%**; novel **4/4** |
| 5 | Terminal grounding | sim **0/3** predict; live **3/3** with `--live` |

## Code map

| File | Role |
|------|------|
| `boundary_crossing/verify_learn_invent.zig` | Harness: routing, invent, discover, terminal ground |
| `boundary_crossing/build.zig` | Module import `unified_invention` for verify-learn-invent target |
| `sparse_poly_discovery/unified_invention.zig` | Forge → menu → world loop; exported `runFullBenchmark` / `runSingleTarget` |

See also:
- `verification_learning.md` — verification axis vs LLM/JEPA
- `sparse_poly_discovery/docs/research/parallel_forks_2026.md` — all 7 parallel fork results
- `sparse_poly_discovery/docs/research/hardness_router_integration.md` — Q38 routing into discover
- `sparse_poly_discovery/unified_invention.zig` (Fork 5), `inner_forge.zig`, `operator_menu.zig`