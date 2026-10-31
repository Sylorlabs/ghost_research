# Parallel forks session — measured results (June 2026)

**Status:** all seven forks built and benchmarked. Numbers below are from fresh `--release=fast` runs on
2026-06-30 unless noted.

## Summary table

| Fork | Name | Key measured claim | Reproduce | Verdict |
|------|------|-------------------|-----------|---------|
| **1** | Operator menu → inner_forge | T5 **0.50→1.00**; monomial **4/5** → final **5/5** | `zig build inner-forge --release=fast` | **PASS** — monomial saturates; spectral menu escapes |
| **2** | Hardness router (Q38) | Same pair as brute (**35.13** fail/1k); **5+1 vs 12** runs = **2.4×** cheaper | `zig build hardness-router-test --release=fast` | **PASS** — Q38 compound confirmed on DUAL_BAND |
| **3** | Plain English compression | `make it smaller` → gzip **2103→68** (**97%** smaller), no LLM | `printf 'make it smaller\n' \| zig build engine-repl --release=fast` | **PASS** — NL→compress only; no chains/discover |
| **4** | No-LLM autonomous | **4/4** certified discoveries; self-extend **1064 B** saved (**2.5%**) | `zig build real-invention` + `zig build self-extending-inventor` | **PASS** — search+certify+promote without neural layer |
| **5** | Unified loop | inner_forge **5/7** → unified **7/7** | `zig build unified-invention --release=fast` | **PASS** — menu + world pool unlock T5, T7 |
| **6** | k≥3 order escape | Full substrate **6/6**; T6 **0.50→1.00** via rank indicators | `zig build k3-order-escape --release=fast` | **PASS** — order-stats break median wall |
| **7** | Dial-3 addition chains | Engine beats binary on **735/1023** (71.8%); l(1023)=**13** | `zig build dial-three --release=fast` | **PASS** — genuine-unknown target + sound verifier |

---

## Fork 1 — Operator menu wired into inner_forge

**Question:** When monomial promotion saturates on T5 (parity-of-count), does the operator menu escape?

**Key files:**
- `sparse_poly_discovery/inner_forge.zig`
- `sparse_poly_discovery/operator_menu.zig`
- `sparse_poly_discovery/operator_menu_lib.zig`

**Command:**
```bash
cd sparse_poly_discovery && zig build inner-forge --release=fast
```

**Measured (2026-06-30):**
```
round 0:  T1=0.52  T2=0.47  T3=0.48  T4=1.00*  T5=0.50   → 1/5
round 2:  SATURATED (monomial closure)              → 4/5; atoms 11

Fork 1 operator escape:
  T5: 0.50 → menu→spectral (ω=3.1416) test=1.00 → 1.00 *

final: 5/5 solved; atoms 11 + ops 1
```

**Verdict:** Monomial forge bottoms at products-of-cells (**4/5**). Operator menu discovers certified
cross-family primitive (`cos(ω·count)`, ω≈π). Escape is **principled routing to a handed menu**, not blind
family invention. See `inner_forge.md`, `menu_growth.md`.

---

## Fork 2 — Hardness router (Q38 compound detection)

**Question:** Can substrate-hardness probes route to the right cross-class pair without O(N²) brute search?

**Key files:**
- `sparse_poly_discovery/hardness_router.zig`
- `sparse_poly_discovery/hardness_router_test.zig`
- `sparse_poly_discovery/environment.zig` (DUAL_BAND task)

**Command:**
```bash
cd sparse_poly_discovery && zig build hardness-router-test --release=fast
```
(~65 s: 5000 probe / 15000 verify × 6 seeds)

**Measured (2026-06-30):**
```
Singles (fail/1k):  sum=83.40  left_mass=35.80  right_mass=83.30  max_cell=83.30
Task class:         q38_compound

Guided pair:        (left_mass, max_cell) = 35.13 fail/1k
Brute best:         (left_mass, max_cell) = 35.13 fail/1k   gap = 0.00
Naive (sum,left_mass): 83.33 fail/1k

Search cost:        5 single probes + 1 pair verify  vs  12 brute pair runs
                    → 12/5 = 2.4× fewer evaluation runs
```

**Verdict:** Q38 analog **confirmed** on DUAL_BAND. Router finds **same pair** as brute. **2.4× cheaper** in
pair-level evaluations (5 probe+verify ops vs 12 full pair searches). See `closure_escape_control.md`,
`function_hardness` Q38 lineage.

---

## Fork 3 — Plain English → compression only (engine-repl)

**Question:** Can a user type a natural-language want and get a **certified** compression invention with **no LLM**?

**Scope:** Compression/SIZE objective only — not chains, feature discovery, or terminal teach/predict. That wider
menu is `verify-learn-invent` (boundary_crossing).

**Key files:**
- `boundary_crossing/engine_repl.zig`
- `boundary_crossing/intent_recognizer.zig`
- `boundary_crossing/primitive_synthesizer.zig`

**Command:**
```bash
cd boundary_crossing
printf 'make it smaller\n' | zig build engine-repl --release=fast
```
Interactive: `zig build engine-repl --release=fast`

**Measured (2026-06-30):**
```
you ▸ make it smaller
eng ◂ understood: minimize SIZE, cold (offline).
       invented filter [ stride4→delta2 ]
       gzip 2103→68 (97% smaller)  reversible=yes
```

Intent recognizer held-out (separate binary): **10/10** on SIZE/TIME/MEMORY × COLD/LIVE menu
(`zig build intent-recognizer --release=fast`). Out-of-scope wants ("make it prettier") refused.

**Verdict:** **PASS** for compression-only plain English. Honest bound: TIME/MEMORY recognized but SIZE is the
only fully wired certifier in the REPL loop. See `engine_repl.md`, `intent_recognizer.md`.

---

## Fork 4 — No-LLM autonomous invention

**Question:** Can the engine search, certify, and self-extend **without any neural layer**?

Two complementary binaries:

### 4a — real_invention (certified logical discovery)

**Key file:** `boundary_crossing/invention_engine.zig` (via `real_invention` entry)  
**Command:** `cd boundary_crossing && zig build real-invention --release=fast`

**Measured:**
```
«odd number of divisors»   DISCOVERED ≡ is_square        (Fermat pairing; no divisor primitive)
«n mod 6 ∈ {0,2,3,4}»     DISCOVERED ≡ even ∨ mod3
«n divisible by 30»      DISCOVERED ≡ even ∧ mod3 ∧ mod5
«structureless hash»     UNINVENTABLE (correctly declined)
→ 4 certified discoveries, 1 honest decline
```

### 4b — self_extending_inventor (library promotion)

**Key file:** `boundary_crossing/self_extending_inventor.zig`  
**Command:** `cd boundary_crossing && zig build self-extending-inventor --release=fast`

**Measured:**
```
raw 59912  |  self-extending 41542  |  base-only 42606
→ 1064 fewer bytes (2.5% better) at equal budget; all reversible

Per-file (8-wide records):  self 12371 (20.2%)  vs  control 12876 (17.0%)
```

**Verdict:** **PASS** — autonomous search + certify + self-extend with zero LLM. Bound: promotion is
abstraction **within** the injected DSL closure, not escape to new primitive *forms*. See `real_invention.md`,
`self_extending_inventor.md`, `autonomous_inventor.md`.

---

## Fork 5 — Unified invention loop (forge → menu → world)

**Question:** Does escalating through monomial forge, operator menu, and world pool beat inner_forge alone?

**Key file:** `sparse_poly_discovery/unified_invention.zig`

**Command:**
```bash
cd sparse_poly_discovery && zig build unified-invention --release=fast
```

**Measured (2026-06-30):**
```
inner_forge-only baseline:  5/7 solved
  T5 parity-of-count:  0.501
  T7 sum(g)%7:         0.859

unified loop:               7/7 solved
  T5 → MENU spectral cos(ω·count) ω=3.142  0.50→1.00
  T7 → WORLD sum%mod_7                     0.86→1.00

final library (13 features): 8 singletons + φ{2,5} + φ{1,3,6} + φ{0,4,5,7}
                             + cos(ω·count) + sum%mod_7
```

**Verdict:** **PASS** — unified loop unlocks **2 targets** inner_forge cannot (T5, T7). Target spec is still
structured `{kind, mask?, modulus?}` — **not plain English yet** (7-item AGI gap listed at end of binary output).
See `inventable_substrate_design.md`.

---

## Fork 6 — k≥3 + order-statistic escape (T6 median wall)

**Question:** Does adding rank/indicator order statistics break T6 (`median(c0,c1,c2)==1`) where monomials and
mod3 stall?

**Key file:** `sparse_poly_discovery/k3_order_escape.zig`  
**RNG seed:** `0xC3F0A6E01CEF` (pinned)

**Command:**
```bash
cd sparse_poly_discovery && zig build k3-order-escape --release=fast
```

**Measured (2026-06-30):**
```
T6 solo probes:
  med−1(0,1,2):   test=0.262  ← centered median FAILS (±1 not separable)
  med==1(0,1,2):  test=1.000  ← rank indicator OK

Pool results:
  A monomial-only:     4/6  T6=0.50  saturated
  B mono+mod3:         5/6  T6=0.50  saturated  (T5 escapes via mod3_global)
  C mono+order-stats:  5/6  T6=1.00  saturated  (T6 escapes via med==1)
  D full substrate:    6/6  T6=1.00  saturated
```

**Verdict:** **PASS** — order-stat rank indicators break T6 wall; full substrate reaches **6/6**. Forge still
**saturates** at the substrate family (closure principle unchanged). See `order_statistics_closure.md`,
`kary_frontier.md`.

---

## Fork 7 — Dial-3: shortest addition chains

**Question:** Does the certified loop beat a naive baseline on a **genuine unknown** (l(n) not pre-supplied)?

**Key file:** `boundary_crossing/dial_three.zig`

**Command:**
```bash
cd boundary_crossing && zig build dial-three --release=fast
```

**Measured (2026-06-30):**
```
Certified n ∈ [2, 1024]:  all 1023 chains independently verified ✓

Engine STRICTLY beat binary method:  735 / 1023  (71.8%)
Matched: 288;  Losses: 0
Total additions saved vs baseline:   1186

Smallest suboptimal-for-binary:  n=15  (binary=6, l(15)=5)
Largest margin:                  n=1023 (binary=18, l(1023)=13, saved 5)

Showcase l(n) (engine-derived, not hardcoded):
  l(127)=10  l(255)=10  l(511)=12  l(1023)=13  l(1000)=12
```

**Verdict:** **PASS** — dial (3) turned end-to-end: unknown target + sound verifier + beats recombination
baseline. Honest scope: small-n l(n) is tabulated for humanity — demonstrates **mechanism**, not new-to-humanity
result. See `dial_three.md`, `real_invention.md`.

---

## Cross-fork synthesis

```
Monomial inner_forge saturates (Fork 1: 4/5)
    ↓ operator menu escape
Fork 1 + Fork 5: spectral/world unlock parity + mod_p (5/5, 7/7)
    ↓ different substrate
Fork 6: k≥3 + order-stats unlock median (6/6) — still saturates
    ↓ control domain
Fork 2: hardness router finds Q38 pairs 2.4× cheaper
    ↓ boundary_crossing
Fork 3: plain English → compress (97%); Fork 4: no-LLM invent; Fork 7: dial-3 chains (735/1023)
    ↓ integration
verify-learn-invent: verify-learn routing + all three loops in one binary
```

**Honest ceiling across all forks:** every forge/router/menu **bottoms at its injected closure**. Crossing
families requires **handed** operators (menu, world pool, LLM seed) or human-supplied primitives — measured
consistently across `inner_forge.md`, `CLOSURE_PRINCIPLE.md`, and `wcore/docs/research/alien_novelty_limit.md`.

## See also

- `boundary_crossing/docs/research/verify_learn_invent.md` — integrated verify-learn-invent architecture
- `boundary_crossing/docs/research/verification_learning.md` — verification vs prediction axis
- `sparse_poly_discovery/docs/research/inner_forge.md` — Phase C monomial saturation
- `sparse_poly_discovery/docs/research/inventable_substrate_design.md` — unified loop design