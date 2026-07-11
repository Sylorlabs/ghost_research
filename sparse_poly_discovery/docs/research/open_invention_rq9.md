# RESEARCH Q9 — Cross-cutting equivalence tax harness

**Status:** built, measured. Reproduce:

```bash
cd sparse_poly_discovery && zig build open-invention-rq9 --release=fast
```

(~25 s, ReleaseFast)

## What this tests

Open-invention experiments (E3, E4, E5, E11) certify **escapes** — primitives or pipelines that
lift held-out accuracy from chance to ≥0.90. RQ9 asks the cross-cutting question:

> Are those escapes **genuinely outside** the repo's rich symbolic basis, or just rediscoverable
> by a fixed-budget search over monomial + Walsh + world + VM?

This is the **equivalence tax**: if most escapes reproduce on fresh held-out grids, the experiments
document **remix inside a designed closure**, not invention outside it.

## Basis (the tax collector)

| Family | Contents |
|--------|----------|
| Monomial | centered φ_S, deg 1–4 (255 masks) |
| Walsh | χ_S for all 256 sign-pattern subsets |
| World | `sum(g)%p` and `sign(g)%p` for p ∈ {2,3,5,7,11,13} |
| VM | expression trees depth ≤6 over cell/thresh/sum/parity/min/max/rank_k + add/mul/cmp_gt |

**Explicitly excluded:** spectral cos(ω·count), composed pipelines (E5 inner₁→inner₂), count
program synthesis (E3 `mod(count,2)` path).

## Escapes under test

| ID | Source | Certified escape | Target predicate |
|----|--------|------------------|------------------|
| E3-parity | E3 | `mod(count,2)` | popcount(cells ≥ thr) odd |
| E4-G00 | E4 | `sum*parity` mint | seed-pinned hard VM target G00 |
| E4-G06 | E4 | rank-compare mint | seed-pinned hard VM target G06 |
| E5-F-A | E5 | inversion→half_p | inversion_count mod 2 |
| E5-F-B | E5 | sum→bind_xy | sign((c0−mid)(c1−mid)) > 0 |
| E11 | E11 | `sum_mod7_indicator` | Σ cells ≡ 0 (mod 7) |

E4 targets regenerated from seed `0xE4CE11ED0FF1CE42` (same algorithm as `open_invention_e4.zig`);
thresholds fit on train grids only, evaluated on held-out test grids (seed `0xE957E5700002`).

## Search protocol

- **Train:** 7000 grids (seed `0xF0235A11CE0FF1CE`)
- **Held-out test:** 3500 fresh grids (seed `0xE957E5700002`)
- **Fixed budget:** greedy forward selection, ≤8 features
- **Prefilter:** top 96 candidates/round by \|corr(feature, Y)\| on train
- **Reproducible:** test accuracy ≥ 0.90 within budget

## Measured results (2026-06-30)

```
Candidates: 523 static + 8174 VM roots = 8697 total

┌────────────────────────────────┬────────┬──────────┬─────────────┬──────────────┐
│ Escape                         │ Source │ Test acc │ Reproducible│ Basis winner │
├────────────────────────────────┼────────┼──────────┼─────────────┼──────────────┤
│ E3-parity (mod count 2)        │ E3     │ 1.000    │ YES         │ χ(0xFF)      │
│ E4-G00 (sum*parity mint)       │ E4     │ 0.830    │ NO          │ (thresh+rank_3) │
│ E4-G06 (rank-compare mint)     │ E4     │ 1.000    │ YES         │ φ(0x01)      │
│ E5-F-A (inversion-parity)      │ E5     │ 0.508    │ NO          │ VM cmp tree  │
│ E5-F-B (sum-then-bind)         │ E5     │ 1.000    │ YES         │ χ(0x03)      │
│ E11 (sum_mod7_indicator)       │ E11    │ 0.936    │ YES         │ sum%mod_3*   │
└────────────────────────────────┴────────┴──────────┴─────────────┴──────────────┘

* E11 reached 0.936 with world-pool mod features (mod 3 + mod 7 family); ≥0.90 → reproducible.
```

| Metric | Value |
|--------|-------|
| Escapes tested | 6 |
| Reproducible | **4/6 (66.7%)** |
| Pass bar | <30% reproducible |
| **Verdict** | **FAIL** — escapes are mostly basis-equivalent |

## Interpretation

### Reproducible (basis already spans the escape)

1. **E3 parity → Walsh χ(0xFF).** E3's PASS used `mod(count,2)` without naming Walsh, but the
   equivalence tax shows parity is **fully reachable** from Walsh in the rich basis. E3 escape is
   a **routing discovery**, not a new family.

2. **E5-F-B → Walsh χ(0x03).** The bilinear bind label on (c0,c1) is Walsh-equivalent on the
   8-cell sign pattern. The E5 pipeline discovery is **honest composition**, but the tax classifies
   it as basis-redundant.

3. **E4-G06 → monomial φ(0x01).** The rank-compare mint target is classified by a degree-1 monomial
   on held-out grids — the minted VM tree is **behaviorally covered** by a simpler basis atom.

4. **E11 sum_mod7 → world pool.** The "novel" LLM-proposed feature is reproducible from the
   handed world pool (`sum%mod_p`), confirming E11's novelty gate was correct for Boolean families
   but the arithmetic escape lives in world — not outside the unified loop.

### Not reproducible (genuine tax survivors)

1. **E5-F-A inversion-parity (0.508).** Inversion count mod 2 is **not** reached by monomial + Walsh
   + world + VM depth≤6 within budget. The composed pipeline (`inversion→half_p`) is the only
   certified path — strongest **real invention** survivor in this harness.

2. **E4-G00 hard target (0.830).** The seed-pinned G00 predicate stays below the 0.90 bar on
   held-out grids despite val-perfect VM fits — either the minted family is genuinely outside the
   basis, or the greedy budget is insufficient (finding, not failure of tax).

## Verdict

| Criterion | Result |
|-----------|--------|
| Reproducibility rate | 66.7% |
| Pass bar (<30%) | **FAIL** |
| Real invention survivors | E5-F-A (strong), E4-G00 (partial) |
| Doc path | `sparse_poly_discovery/docs/research/open_invention_rq9.md` |

**Conclusion:** Cross-cutting equivalence tax **fails** the "<30% reproducible" bar. Most certified
open-invention escapes are **re-expressible** in monomial + Walsh + world + VM — consistent with the
Closure Principle. The exceptions (inversion-parity pipeline, some E4 hard mints) are the honest
candidates for "invention outside the named menu."

## Expanded tax v2 (E26)

`open_invention_e26.zig` extends this harness with **mod synthesis + xor_popcount + E5 pipelines**
and tests **20 escapes** from E1–E12. Measured **17/20 = 85%** reproducible (FAIL vs <40% bar).
Novel survivors: E4-G00, E2 parity(XOR 0x33), E12 rank2. See `open_invention_e26.md`.

## See also

`open_invention_rq9.zig`, `open_invention_e26.zig`, `open_invention_e3.zig`, `open_invention_e4.zig`,
`open_invention_e5.zig`, `open_invention_e11.zig`, `unified_invention.zig`,
`docs/research/open_invention_experiments.md`, `CLOSURE_PRINCIPLE.md`.