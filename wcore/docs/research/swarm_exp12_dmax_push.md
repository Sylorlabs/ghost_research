# EXP-12 (B10): DMAX push — do irreducible survivors appear at depth ≥10?

**Status:** built, measured — negative result, no surprises.  
**Reproduce:**
```bash
cd wcore && zig build -Doptimize=ReleaseFast
./zig-out/bin/wcore-invent budgetscan <seed> [dmax]
# batch: bash logs/exp12/run_all.sh   # DMAX 9–12 × 4 seeds
```
Raw logs: `wcore/logs/exp12/dmax{9,10,11,12}_0x{seed}.log`  
Summary TSV: `wcore/logs/exp12/summary.tsv`

## Question (RQ #10 continuation)

`budget_scan.md` showed **0 survivors at DMAX=8** across four seeds, dissolving the
lone 0xD00D depth-4 "irreducible" (it reduces at depth 5). EXP-12 asks: does
survivorship stay **0** as exhaustive reduction depth grows to 9, 10, 11, 12 — or
does any deep solver resist reduction (candidate genuine atom relative to the fixed
five-stage atom set)?

## Protocol

1. **Instrument:** `budgetScan` in `src/inv_main.zig` — builds the §24 coevolution
   ladder, then calls `coevo.reducible(prog, DMAX, seed)` for each deep solver
   (depth ≥ 2). `reducible()` exhaustively enumerates every composition of the five
   fixed atoms (`gxor`, `gadd`, `pkxor`, `pkadd`, `shift`) up to depth DMAX.

2. **Seeds:** 0xD00D, 0xBEEF, 0x1111, 0xFACE (same quartet as `budget_scan.md`).

3. **DMAX sweep:** 9, 10, 11, 12 (16 runs total).

4. **Sanity kill-test:** hand-built `distinct-count` must remain irreducible.
   - DMAX=9: sanity runs at full depth 9.
   - DMAX≥10: sanity capped at depth 8 (proven non-vacuous in `budget_scan.md`;
     exhaustive sanity at scan-DMAX would cost ~5^DMAX per seed without strengthening
     the claim).

5. **Code change:** optional third CLI arg `budgetscan <seed> [dmax]` (default 8).

## Results

### Survivor count per DMAX (aggregate over 4 seeds)

| DMAX | Deep solvers (total) | Survivors | Max min-reduction depth |
|------|---------------------|-----------|-------------------------|
| 9    | 29                  | **0**     | 5 (0xD00D only)         |
| 10   | 29                  | **0**     | 5                       |
| 11   | 29                  | **0**     | 5                       |
| 12   | 29                  | **0**     | 5                       |

For reference, DMAX=8 (prior run): **0 survivors** across the same four seeds.

### Per-seed detail (identical across DMAX 9–12)

| Seed   | Deep | Survivors | Max reduction depth | Histogram (min depth → count) |
|--------|------|-----------|---------------------|-------------------------------|
| 0xD00D | 9    | 0         | 5                   | 2→3, 3→3, 4→2, 5→1           |
| 0xBEEF | 8    | 0         | 3                   | 2→7, 3→1                      |
| 0x1111 | 7    | 0         | 3                   | 2→6, 3→1                      |
| 0xFACE | 5    | 0         | 3                   | 2→4, 3→1                      |

No histogram row changed between DMAX=8 and DMAX=12. Raising the budget past the
deepest known composition (depth 5 on 0xD00D) produces **no new information** — every
solver was already fully reduced well inside the DMAX=8 envelope.

### Sanity

All 16 runs: `distinct-count` **IRREDUCIBLE** at sanity depth (9 for DMAX=9; 8 for
DMAX≥10). Instrument non-vacuous throughout.

## Surprise at D≥10?

**None.** Specifically:

- **No new survivors** at any DMAX ≥ 10.
- **No verdict flips** — a solver irreducible at DMAX=8 would have been reported; none
  exist. Histograms are byte-stable from DMAX=8 through 12.
- **No deeper compositions discovered** — max min-reduction depth remains 5 (0xD00D)
  and 3 (other seeds). The depth-5 composition found at DMAX=8 is the hardest case;
  DMAX 9–12 add search budget with nothing left to find.
- **Runtime only** scales (~45 s/seed at DMAX=12 vs ~30 s at DMAX=9 on this machine);
  scientific output is flat.

## What this answers

- **RQ #10 closed for fixed atoms:** survivorship is **0** and **stable** from
  DMAX=8 through 12. The 0xD00D anomaly does not reappear at higher budgets.
- **Claim C strengthened again:** not merely "holds at depth 4" or "holds at DMAX=8"
  but "holds under continued budget scaling with no late surprises." Every deep solver
  the open-ended search produced is an exact composition of the five stage atoms; the
  deepest required composition is depth 5.
- **"Irreducible" = budget artifact, demonstrated by scaling:** novelty flags are
  exactly as deep as the reduction search. Pushing DMAX from 8→12 changes nothing
  because the true minimum depths (≤5) were already inside budget.

## Tie to atom-forge (`inv_atomforge.zig`)

On a **fixed** atom set, exhaustive `reducible()` can only certify composition — never
invention. `inv_atomforge.zig` is the designed escape hatch: `reducibleLib()` tests
against a **growing** program library so each invented atom must beat everything
invented so far. EXP-12 confirms the fixed-set negative result is not a shallow-budget
artifact; the standing frontier for genuine invention remains the open-ended atom set,
not deeper composition search.

## Honest status

Negative result to a genuinely open question — the good kind. The knob (DMAX 9–12) was
unexplored; the outcome was fixed by exhaustive computation. No irreducible survivors.
The closure principle holds all the way up to depth 12 on this substrate.