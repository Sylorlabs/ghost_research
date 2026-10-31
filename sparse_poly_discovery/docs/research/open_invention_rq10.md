# RESEARCH Q10 — Certifier soundness on random-label targets

**Status:** measured (2026-06-30). **Verdict: PASS — certifier sound on noise**

## Question

Does the monomial forge certifier (escape ≥0.90 held-out **and** irreducible R²<0.40) **false-promote**
on targets with no learnable structure? If the certifier fires on random or shuffled labels, downstream
open-invention results cannot be trusted.

## Protocol

| Phase | Labels | Expectation |
|-------|--------|-------------|
| **A — random** | 64 independent Bernoulli(0.5) label vectors on a fixed grid | **0** certified promotions (any promote = false promote) |
| **B — shuffled** | inner_forge zoo T1–T5 labels permuted across samples (structure destroyed) | **0** certified promotions |
| **C — control** | Structured zoo T1–T5 (real monomial / parity targets) | True promotes on solvable monomial signs |

**Substrate:** centered monomials φ_S; base atom set = 8 singletons (deg 1); promote deg 1–4 subsets.

**Certifier (per inner_forge / E1):**

- **Escape:** held-out test acc ≥0.90 after adding φ_S, while current library <0.90
- **Irreducible:** held-out R² of reconstructing φ_S from current atoms <0.40

**Forge:** up to 8 rounds per target; discover best validation φ_S, certify, promote or stop.

**Seeds:** grid `0xF0235A11CE0FF1CE`, random labels `0xA10BA771E10A0001`, shuffle `0xA10BA771E10A0002`  
**Splits:** train/val/test = 3500/1750/1750  
**PASS bar:** false-promote rate **<5%** on random labels (Phase A)

## Reproduce

```bash
cd sparse_poly_discovery && zig build open-invention-rq10 --release=fast
```

(~50 s, `--release=fast`)

## Phase A — pure random labels (64 targets)

```
targets false-promoted:  0/64  (0.0%)
total certified promotes: 0
solved w/o promote:       0
```

No random-label target crossed the escape+irreducibility gate. Chance-level coverage (~0.50) throughout.

## Phase B — shuffled real-target labels (5 zoo targets)

| Target | Outcome | certs | final cov |
|--------|---------|-------|-----------|
| T1 sign φ{2,5} | ok | 0 | 0.482 |
| T2 sign φ{1,3,6} | ok | 0 | 0.486 |
| T3 sign φ{0,4,5,7} | ok | 0 | 0.501 |
| T4 sign(c3−MID) | ok | 0 | 0.505 |
| T5 parity-of-count | ok | 0 | 0.505 |

```
targets false-promoted:  0/5  (0.0%)
```

Shuffling preserves label marginals but removes grid correlation; certifier correctly refuses all escapes.

## Phase C — structured zoo (positive control)

| Target | Outcome | certs | final cov |
|--------|---------|-------|-----------|
| T1 sign φ{2,5} | SOLVED | 1 | 1.000 |
| T2 sign φ{1,3,6} | SOLVED | 1 | 1.000 |
| T3 sign φ{0,4,5,7} | SOLVED | 1 | 0.999 |
| T4 sign(c3−MID) | SOLVED (base-covered) | 0 | 1.000 |
| T5 parity-of-count | unsolved | 0 | 0.505 |

```
targets promoted:  3/5  (60%)
```

Certifier is **not vacuous**: monomial-sign targets T1–T3 certify and promote; T4 already solved by singletons;
T5 (non-monomial parity) stays at chance without operator menu — matches `inner_forge.md`.

## Summary

| Cohort | false-promote count | rate | verdict |
|--------|---------------------|------|---------|
| **Random labels** | **0/64** | **0.0%** | **PASS** (<5%) |
| Shuffled labels | 0/5 | 0.0% | sound |
| Structured control | 3/5 promoted | — | non-vacuous |

```
RQ10_RESULT random_false=0/64 rate=0.0000 shuffled_false=0/5 pass=true
```

## Verdict: **PASS — certifier sound on noise labels**

1. **Zero false promotes** across 64 independent random-label targets — well under the 5% pass bar.
2. **Shuffled zoo labels** also produce zero promotions; destroying structure is enough to silence the certifier.
3. **Control is live:** structured monomial targets still certify (3 promotions, 4/5 solved), so the instrument
   rejects noise without becoming universally negative.

The escape≥0.90 + R²<0.40 gate does not appear to hallucinate primitives on label noise at this sample budget.

## Honest caveats

- Test uses the **monomial forge only** (no spectral/Walsh operator menu). Operator-menu certification on noise
  is a separate soundness check (see E1 false-promote on frozen-menu hits).
- 64 random targets at 7000 samples each — a <5% bar allows ≤3 false promotes; observing 0 is consistent with
  but does not prove zero probability; extend `NRANDOM` for tighter confidence.
- Logistic epochs reduced slightly (80 held-out / 50 discovery) vs full `inner_forge` (150/70) for runtime;
  separations on noise are ~0.50 so this is not load-bearing.

## See

`inner_forge.zig`, `open_invention_e1.zig` (certifier definition), `open_invention_e10.md` (novelty↔usefulness),
`instrument_audit.md` (wcore behavioral matching).

## Files

| File | Role |
|------|------|
| `sparse_poly_discovery/open_invention_rq10.zig` | RQ10 harness |
| `sparse_poly_discovery/docs/research/open_invention_rq10.md` | This doc |
| Build step | `zig build open-invention-rq10` |