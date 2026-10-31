# Swarm EXP-17 (E40 / RQ40) — does one measure predict escape gap across 5 witnesses?

**Date:** 2026-07-05  
**Status:** measured — **NO common predictor**; SAC-error works in mixer domain only; Fourier degree works for readout witnesses only.

## Question

Across the five closure-principle witnesses, is the **escape gap** (how far the
out-of-closure generator moves performance past the in-closure ceiling) predicted
by a single cross-domain measure — e.g. **algebraic degree** the generator adds, or
**SAC / BRank** rank of the escaped program?

Sources: `closure_escape_mixer`, `mb_mass` eval, `parity`, wcore `budget_scan`,
meta-engine ceiling docs (`monotone_parallel.md`, `successor_loop_research.md`).

## Protocol

1. For each witness, record **ceiling** (best in-closure), **escape** (with generator),
   and **escape gap** on the witness's native metric.
2. Assign **generator degree** (ANF / Walsh / structural) and **diffusion rank**
   (SAC-error or BRank where defined).
3. Normalize gaps to a common **fraction-of-ceiling-closed** scale where possible.
4. Compute Pearson **R²** for degree→gap and SAC→gap; report qualitative verdict.

**Normalized escape fraction** (when an ideal endpoint exists):

\[
f_{\mathrm{esc}} = \frac{\mathrm{perf}_{\mathrm{escape}} - \mathrm{perf}_{\mathrm{ceil}}}{\mathrm{perf}_{\mathrm{ideal}} - \mathrm{perf}_{\mathrm{ceil}}}
\]

Higher = more of the way from ceiling to ideal. For error metrics, invert so
"lower error = higher perf."

---

## Witness table (collected numbers)

| # | Witness | Closed substrate | Ceiling (in-closure) | Escape (generator) | Native gap | Generator | Δ degree† | SAC / rank at ceiling |
|---|---------|------------------|----------------------|--------------------|------------|-----------|-----------|------------------------|
| 1 | **Mixers** | GF(2)-affine + ADD | SAC-error **0.1269** (MUL-free hill-climb mean); theorem pin **0.500** (pure XOR/shift) | SAC-error **0.0213** (MUL-enabled mean) | **6.0×** SAC reduction (0.127→0.021); **23.5×** vs pure-affine best (0.5→0.021) | **MUL** | 1 → **≤64** (ANF) | SAC **0.127**; BRank **FAIL** (all mul-free champions) |
| 2 | **Control** | XOR/bundle VSA readout | Band fail/1k **33.62** (best XOR agent, CP3 pure); readout acc **0.51** (perceptron, chance) | **11.02** fail/1k (`mb_mass` SUM); readout acc **1.00** (sum-threshold) | **3.05×** fail-rate reduction; **∞×** on readout (0.51→1.00) | **SUM** (integer aggregate) | Walsh deg **16** / non-Fourier‡ | Readout ≡ chance (**0.50** err) |
| 3 | **Parity** | Linear in bits | Test acc **0.505** (k=2, 20k train) | **1.000** (MLP or +product monomial) | **0.495** acc lift; **99%** of ideal closed | **xᵢ·xⱼ** product | 1 → **2** (ANF) | Linear ceiling **0.50** (theorem) |
| 4 | **Meta-engine** | Fixed Tier-0 meta-opcodes | Holdout **44.30** (0x1111 chain ceiling, multi-seed) | Holdout **47.16** (F00D monotone+CALL_META, gen 4) | **+2.86** fitness (+6.5% relative) | **CALL_META** composition axis | **0** (search architecture, not an op) | Composite fitness ~**47.9** in-closure; no SAC/BRank |
| 5 | **Invention** | Fixed opcode VM | **0/9** irreducible at DMAX=8 (0xD00D); **1/9** false flag at depth 4 | **1/1** hand `distinct-count` survives depth 8 sanity | Search gap **0**; human gap **∞** (structural) | **distinct-count** atom | **structural** (global cardinality) | N/A (behavioural, not statistical) |

† Degree: ANF over GF(2) where applicable; Walsh–Hadamard degree for Boolean readouts
(`boolean_fourier.md`); "structural" when the generator is not a polynomial.

‡ SUM is ℤ-linear (degree 1 over integers) but **outside** the XOR/parity readout
closure — equivalent to needing a full-support or non-Boolean feature.

### Source citations

| Witness | Primary doc / command |
|---------|----------------------|
| Mixers | `05_meta_synthesis/docs/07/closure_escape_mixer.md` — `closure_escape_mixer` |
| Control | `sparse_poly_discovery/docs/research/closure_escape_control.md` — `zig build eval` `[BAND]` |
| Parity | `sparse_poly_discovery/docs/research/parity_closure.md` — `zig build parity` |
| Meta-engine | `05_meta_synthesis/docs/05/monotone_parallel.md`, `successor_loop_research.md` |
| Invention | `wcore/docs/research/budget_scan.md`, `claim_c_breadth.md` |

---

## Normalized escape fractions

| Witness | \(f_{\mathrm{esc}}\) (primary metric) | Notes |
|---------|--------------------------------------|-------|
| Mixers (MUL, vs MUL-free ceiling) | **0.83** | (0.127−0.021)/0.127 toward SAC ideal 0 |
| Mixers (MUL, vs pure-affine theorem) | **0.96** | (0.500−0.021)/0.500 |
| Mixers (ADD only, vs pure-affine) | **0.75** | (0.500−0.127)/0.500 — partial escape |
| Control (fail/1k) | **0.67** | (33.62−11.02)/33.62 toward 0 fail |
| Control (readout accuracy) | **1.00** | (1.00−0.51)/(1.00−0.50) |
| Parity k=2 | **0.99** | (1.00−0.505)/(1.00−0.50) |
| Meta-engine holdout | **0.50**§ | (47.16−44.30)/(50.0−44.30) assuming composite ideal ≈50 |
| Invention (search) | **0.00** | 0 survivors — no escape within VM closure |

§ Meta-engine ideal is approximate; using 50 (observed in-closure composite
plateau from `invention_chain.md` ~47.9) gives \(f_{\mathrm{esc}} \approx 0.50\).

---

## Correlation analysis

### A. Algebraic degree (Δdeg) vs normalized escape fraction

| Witness | Δdeg | \(f_{\mathrm{esc}}\) |
|---------|------|------------------------|
| Mixers ADD (partial) | 2 | 0.75 |
| Parity k=2 | 2 | 0.99 |
| Control SUM | 16‡ | 0.67–1.00 |
| Mixers MUL | 64 | 0.83–0.96 |
| Meta-engine CALL_META | 0 | 0.50 |
| Invention (search) | — | 0.00 |

Pearson **r ≈ 0.35**, **R² ≈ 0.12** (n=5 numeric witnesses; invention excluded).

**Parity (Δdeg=2) closes 99% of the gap; MUL (Δdeg=64) closes 83%.** Higher
degree does **not** monotonically predict larger escape. The two Δdeg=2 points
split 0.75 vs 0.99 — same degree, different gaps.

### B. SAC-error (or chance-equivalent) at ceiling vs escape gap

Restrict to witnesses where SAC / chance is the ceiling statistic:

| Witness | SAC_err_ceiling | SAC_err_escape | ΔSAC |
|---------|-----------------|----------------|------|
| Mixers (pure affine) | 0.500 | 0.021 | 0.479 |
| Mixers (MUL-free) | 0.127 | 0.021 | 0.106 |
| Control readout | 0.500 | 0.000 | 0.500 |
| Parity (linear) | 0.500 | 0.000 | 0.500 |

Within this subset, ΔSAC correlates with **mixer** gaps but is **degenerate** for
control and parity (both pin at 0.50 by theorem, both escape to 0.00) while
native performance gaps differ (3× vs ∞×). **R² = 1.0** on the four points only
because ceiling SAC is always 0.5 — tautological, not predictive across domains.

### C. BRank

All mul-free mixer champions: **BRank FAIL** at PractRand tiers
(`affine_closure_tierA`, full-run logs). MUL-enabled programs pass lower SAC-error
but BRank was not re-measured in `closure_escape_mixer`. BRank does not apply to
control, parity, meta-engine, or invention witnesses. **Not a cross-domain predictor.**

---

## Reading — three regimes, not one ruler

```
  regime          | witnesses        | what predicts escape gap
  ----------------+------------------+------------------------------------------
  diffusion / SAC | mixers           | SAC-error (second-order statistic);
                  |                  | BRank for PractRand; degree bounds ANF
                  |                  | but degree alone insufficient (Tier B:
                  |                  | deg-2 ops don't beat BRank at L≤24)
  readout / Fourier | control, parity | Walsh/ANF degree of the *target predicate*
                  |                  | predicts ceiling (0.50) exactly; escape
                  |                  | needs generator of matching degree/structure
  structural      | meta-engine,     | no polynomial degree; escape = new search
                  | invention        | axis or new atom — gap is architectural
```

### What works (locally)

1. **Mixer domain:** SAC-error is the right ceiling statistic; MUL's high ANF degree
   coincides with SAC collapse — but ADD already raises degree (~2) yet plateaus at
   SAC 0.127, so **degree is necessary, not sufficient** for diffusion escape.
2. **Control + parity:** **Fourier degree / low-degree mass** (`boolean_fourier.md`)
   predicts the *ceiling* (linear at chance) but not the *magnitude* of the escape
   gap on the task metric (fail/1k vs accuracy).
3. **Invention:** Escape is **boolean** (reducible vs irreducible), not continuous —
   budget scan shows the gap is a function of **reduction depth**, not generator degree.

### What fails (cross-domain)

- **Meta-engine** escaped (+2.86 holdout) without adding a nonlinear op — monotone
  retry + CALL_META is a **search-process** generator, Δdeg = 0.
- **Invention** has a true outsider (`distinct-count`) with no ANF degree; search
  never finds it (0/86 irreducible at breadth, 0/9 at DMAX=8).
- **Same Δdeg=2** gives 75% escape (ADD carry) and 99% escape (parity product) —
  context dominates.

---

## Verdict

| Hypothesis | Result |
|------------|--------|
| One **algebraic degree** predicts escape gap across 5 witnesses? | **NO** — R² ≈ 0.12; parity beats MUL at lower degree |
| One **SAC / BRank** rank predicts escape gap across 5 witnesses? | **NO** — only defined for mixers; degenerate where defined |
| Any **common** measure? | **NO** — three incompatible regimes |

**Qualitative verdict:** The closure principle's witnesses share the *shape*
(ceiling → inject generator → escape) but **not** a single numerical predictor.
Use **SAC-error** for diffusion/mixer ceilings, **Fourier degree** for
readout/classification ceilings, and **irreducibility depth** for invention —
mixing them into one R² is a category error.

**Partial positive:** Where the ceiling is a **proved low-degree blind spot**
(parity, control band-readout, pure-affine SAC=0.5), the generator's degree
*relative to that closure class* predicts **whether** escape is possible, not
**how large** the performance gap will be on the task metric.

---

## Reproduce

```bash
# Witness 1 — mixers
cd 05_meta_synthesis && zig build -Doptimize=ReleaseFast && ./zig-out/bin/closure_escape_mixer

# Witness 2 — control (mb_mass)
cd sparse_poly_discovery && zig build eval    # [BAND] block

# Witness 3 — parity
cd sparse_poly_discovery && zig build parity

# Witness 4 — meta-engine ceiling (historical; long run)
cd 05_meta_synthesis && zig build -Doptimize=ReleaseFast
./zig-out/bin/meta_meta_chain_runner --monotone-retries=10  # see monotone_parallel.md

# Witness 5 — invention budget
cd wcore && zig build -Doptimize=ReleaseFast
./zig-out/bin/wcore-invent budgetscan 0xD00D
```

## Open

- Tier-B mixer experiment: does **forced** deg-2 generation ever beat BRank at L≤24?
  (`affine_closure_tierA` §Tier B) — would sharpen degree→diffusion within mixers only.
- Assign a principled \(f_{\mathrm{esc}}\) for invention (sample complexity of
  irreducibility at depth D?) so RQ40 can be re-asked numerically in one regime.