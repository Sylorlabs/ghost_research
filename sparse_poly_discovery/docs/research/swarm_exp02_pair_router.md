# EXP-2: Pair-selection hardness router

**Status:** built, measured, **PASS**.  
**Reproduce:** `cd sparse_poly_discovery && zig build pair-hardness-router-test --release=fast` (~6 s).

## Question

Can substrate-hardness probes route to the right **cell pair** for degree-2 predicates without
O(N²) brute pair logistic search — the menu-growth analog of Fork 2 (`hardness_router.zig` on
DUAL_BAND)?

## Substrate (from `menu_growth.zig`)

- `NCELL=8` → **28** unordered pairs
- Pair inner: `φ(i,j) = [c_i, c_j, c_i·c_j]`, linear readout
- Fixed menu joint degree-2 over 6 inners fails on hidden pair **(2,5)** (~0.55 test acc)
- Targets: hidden-pair predicate + **5** random `sign((c_i−mid)(c_j−mid))` degree-2 labels

## Router design (`pair_hardness_router.zig`)

Mirrors Q38 compound detection from `hardness_router.zig`:

| Class | Analog | Probe |
|-------|--------|-------|
| `cell_solo` | deg1 | centered single cell `c_k − mid` (8 logistic fits) |
| `focal_pair` | extremal / menu-pinned | pair (0,1) with `φ` features |
| `menu_joint` | fixed closure | 6 menu inners + squares (12-dim) |

**Classify:** `pair_compound` when menu ≤ 0.55 ∧ focal ≤ 0.55 ∧ best cell ≤ 0.55.

**Propose (no brute pair fits):** rank all 28 pairs by cheap validation correlation
`|corr((c_i−mid)(c_j−mid), Y)|`, then **one** full pair verify fit on the top pair.

**Brute baseline:** 28 full pair logistic fits, select by validation acc.

## Measured results (2026-07-06, `--release=fast`)

```
Target              | class          | guided pair | brute pair | val acc (guided/brute)
--------------------+----------------+-------------+------------+-----------------------
hidden_pair(2,5)    | unknown        | (2,5)       | (2,5)      | 1.000 / 1.000
deg2(1,4)           | pair_compound  | (1,4)       | (1,4)      | 1.000 / 1.000
deg2(0,6)           | unknown        | (0,6)       | (0,6)      | 1.000 / 1.000
deg2(3,7)           | unknown        | (3,7)       | (3,7)      | 1.000 / 1.000
deg2(2,6)           | pair_compound  | (2,6)       | (2,6)      | 1.000 / 1.000
deg2(4,5)           | pair_compound  | (4,5)       | (4,5)      | 1.000 / 1.000

Pair identity match (guided == brute):  6/6  (100%)
Val-acc match (guided ≥ brute − 0.01):  6/6  (100%)
Mean val acc: guided=1.000  brute=1.000
```

## Cost

| Method | Expensive ops (logistic fits) | Cheap ops |
|--------|------------------------------|-----------|
| **Guided** | 8 cell + 1 menu + 1 focal + **1 pair verify** = **11** | 28 correlations |
| **Brute** | **28** pair fits | — |

**Cost ratio (brute / guided pair-fits): 2.5×** (28 / 11).

Guided avoids 17 of 28 full pair evaluations while matching brute pair identity and validation
accuracy on all six targets.

## Verdict

**PASS** — guided pair routing matches brute on hidden-pair predicate and all five random degree-2
targets. Probes correctly detect menu/focal saturation; correlation ranking on the degree-2 product
feature substitutes for exhaustive pair logistic search on this family.

## Honest limits

- **Correlation ranking is family-specific.** It works because every target is exactly
  `sign((c_i−mid)(c_j−mid))`; the ranking statistic matches the generating feature. Anchor-based
  O(N) partner scan **failed** (0/6) on the same battery — reported in development, not shipped.
- **Q38 classification is partial:** 3/6 targets labeled `pair_compound`; 3/6 `unknown` because
  menu val acc sits at 0.57–0.59 (just above the 0.55 saturate threshold). Routing still succeeds
  because proposal uses correlation, not class label.
- **28 cheap correlations are still O(N²)** in pair count (but not O(N²) *expensive* fits). For
  NCELL=8 this is negligible (~6 s total); scaling would need a sparser partner filter.
- Single grid seed (`0x9E3B1D0FA5172C44`); separations are clean (1.000 vs ~0.50) so seed noise is
  not load-bearing.

## Files

| File | Role |
|------|------|
| `pair_hardness_router.zig` | Pair-selection router + brute baseline |
| `pair_hardness_router_test.zig` | EXP-2 benchmark harness |
| `menu_growth.zig` | Substrate + hidden-pair predicate reference |
| `hardness_router.zig` | Control-domain Q38 router (Fork 2) |

## See also

- `menu_growth.md` — certified pair discovery that motivated this routing test
- `parallel_forks_2026.md` — Fork 2 control-domain hardness router (2.4× cheaper)
- `hardness_router_integration.md` — inline grid routing in verify-learn-invent