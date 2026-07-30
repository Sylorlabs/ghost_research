# F4 — Prior transfer and compounding

**Round:** 2026-07-11b (Round F)  
**Status:** complete  
**Question:** after E3 discovers and promotes a missing RMW-shaped mechanism, does that discovery amortize across related targets, or must the prior be supplied and generation repeated per target?

## Verdict

**Transfer is real, but it has two distinct levels.** The promoted atom compounds cheaply across targets that contain the discovered `distinct` mechanism: it solves **5/10** held-out targets by depth-≤3 composition before generation, taking only **0–4 ms each**. It does **not** directly solve either new counting-family completion (`togglecount`, `eqflag`); both require fresh prior-guided generation. The structural prior transfers more broadly than the particular atom: prior-guided search reaches **9/10**, versus **2/10** for an equal-size blind pool.

Thus auto-discovery amortizes strongly over downstream compositions, but not automatically over sibling implementations. The reusable object is partly the promoted mechanism and, more generally, the generator prior.

## Design

Phase 1 deterministically reproduces E3's COVER-fair discovery against `distinct`, yielding a four-instruction candidate behaviorally identical to `noveltyflag` and scoring 6/7 on the wall family. Phase 2 evaluates ten other targets under matched pool size (3,000), seed (`0xA70F`), certification threshold, and composition depth:

- **A — full transfer:** base library + promoted atom; COVER-fair remains available as fallback.
- **B — prior only:** base library; promoted atom withheld; fresh COVER-fair generation.
- **C — cold:** base library; no structural prior; 3,000 blind random programs.

Every target is tested for library-only composition before generation. The battery contains six compositions involving `distinct`, two already-climbable controls (`hashtbl`, `union`), and two new RMW-family siblings: reordered `togglecount` and near-transfer `eqflag`.

## Results

| Condition | Composition | Fresh discovery | Not found | Total wall time |
|---|---:|---:|---:|---:|
| A — full transfer | **5/10** | 4/10 | 1/10 | 66.4 s |
| B — prior only | 0/10 | **9/10** | 1/10 | 157.7 s |
| C — cold | 0/10 | 2/10 | **8/10** | 152.6 s |

Full transfer and prior-only have the same 9/10 ceiling at this budget; the promoted atom changes five successes from fresh searches into immediate compositions. Across the complete ten-target run this reduces measured target-evaluation time by **57.9%** (66.4 s versus 157.7 s). For the five transferred compositions alone, A takes 9 ms total versus about 79.6 s of fresh generation in B, an approximately **8,800×** measured speedup (timer resolution makes the exact ratio approximate).

The target-level result is:

| Target class | A — full transfer | B — prior only | C — cold |
|---|---|---|---|
| `dist->gxor` | composition | generated | miss |
| `gadd->dist` | composition | generated | miss |
| `dist->dist` | composition | generated | miss |
| `dist->rmw` | composition | generated | miss |
| `shift->dist` | composition | generated | miss |
| `shift->dist->gxor` | miss | miss | miss |
| `hashtbl` | generated | generated | generated |
| `union` | generated | generated | miss |
| `togglecount` | generated | generated | generated |
| `eqflag` | generated | generated | miss |

The new siblings are the boundary. Neither is solvable from base atoms plus the promoted `noveltyflag` atom, and A therefore regenerates both. COVER-fair finds both in A and B, while cold happens to find `togglecount` but misses `eqflag`. For `eqflag`, A and B select different certified programs (own-stone agreement 0.321 and 0.964 respectively), which also shows that the result is discovery rather than replay of a single pinned candidate.

## Interpretation

1. **Mechanisms compound through composition.** Once `distinct` is promoted, five downstream targets no longer pay generation cost. This is the strongest positive answer to the amortization question.
2. **Atoms do not stand in for families.** Sharing load/store/read-modify-write structure is insufficient for direct compositional transfer to a reordered or operator-changed sibling.
3. **Priors transfer across siblings.** The same COVER-fair prior solves nine targets without the promoted atom, while blind generation solves only two. The prior is a reusable family-level asset even where the atom is not.
4. **There remains a depth/representation boundary.** `shift->dist->gxor` fails identically in all conditions; promotion removes search cost but does not raise this run's 9/10 ceiling.

## Scope and limitations

This is one deterministic seed and one 3,000-candidate budget, so success-rate uncertainty across seeds is not measured. Runtime includes target evaluation but excludes the common one-time COVER-pool construction and Phase-1 discovery. The cold arm's two successes are not contradictory to the earlier 0/9 blind headline: this battery and budget include easier controls and one randomly hit sibling; the matched result here is the relevant comparison.

## Reproduction

```sh
cd wcore
zig build-exe -O ReleaseFast src/prior_transfer.zig -femit-bin=bin/prior_transfer
./bin/prior_transfer phase1 ../results/prior_transfer_2026_07_11.csv
./bin/prior_transfer phase2 a ../results/prior_transfer_2026_07_11.csv --chunk=3000 --seed=0xA70F
./bin/prior_transfer phase2 b ../results/prior_transfer_2026_07_11.csv --chunk=3000 --seed=0xA70F
./bin/prior_transfer phase2 c ../results/prior_transfer_2026_07_11.csv --chunk=3000 --seed=0xA70F
```

Primary artifacts:

- `wcore/src/prior_transfer.zig`
- `results/prior_transfer_2026_07_11.csv`
