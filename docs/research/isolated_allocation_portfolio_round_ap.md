# AP6 — separate-candidate replay of AM4 allocation and AM5 portfolio

**Verdict: FOUNDATION POSITIVE, bounded synthetic reproducibility evidence only.**

This replay keeps the synthetic world, recoding, reward calculation, nonce
sequence, and end-only score in a parent evaluator. A small candidate is
compiled separately from embedded C source for each run and receives opaque
input frames only. It returns a bounded index. The candidate source contains no
world, target, reward, score, or evaluator helper.

The local wrapper used for each run is the already documented Bubblewrap and
resource-limited wrapper. This report records a deterministic local experiment;
it does not make an open-ended autonomy or security claim.

## Equal-budget results

| Battery | Earned policy | Contacts per arm | Earned material | Strongest listed control |
|---|---:|---:|---:|---:|
| AM4 allocation | topology → value → reuse/explore | 120 × 16 = 1,920 | 3,600 | broad coverage: 1,380 |
| AM5 portfolio | local anonymous portfolio | 96 × 45 = 4,320 | 5,760 | AM4 single record: 1,620 |

AM4 also exceeds fixed AJ4 allocation (1,080), random (1,080), replay
(1,080), shuffled history (1,110), and blank, answer-scrubbed, topology,
value, and arbitration ablations (each 1,080). AM5 exceeds fixed coverage and
fixed scheduling (1,560 each), random (1,560), replay (1,320), shuffled
history (1,680), blank/answer/topology/value/arbitration ablations (1,560),
and explicit wrong-mechanism routing (0). Every arm charges the original budget.

## Reproduction

```sh
zig build-exe sparse_poly_discovery/isolated_allocation_portfolio_round_ap.zig \
  -O ReleaseSafe -lc -femit-bin=/tmp/ap6
/tmp/ap6 selftest
mkdir -p /tmp/ap6-fresh-one /tmp/ap6-fresh-two
/tmp/ap6 run /tmp/ap6-fresh-one/ledger.csv
/tmp/ap6 run /tmp/ap6-fresh-two/ledger.csv
cmp -s /tmp/ap6-fresh-one/ledger.csv /tmp/ap6-fresh-two/ledger.csv
```

The smoke test and two full independent ledgers passed byte-identically. The
published CSV is the second fresh ledger. Local-runtime assumptions remain
outside this bounded synthetic score comparison.
