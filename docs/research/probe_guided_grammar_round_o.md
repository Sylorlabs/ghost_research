# O4 — probe-guided grammar commitment

**Verdict: CONTROLLED STRICT POSITIVE.** On a trace-decoupled fixture, a
policy that buys one permitted aggregate diagnostic, then commits a public
nonredundant grammar before the evaluator-owned fresh score, reaches **16/16**.
Frozen fixed, blind, family-prior, and no-probe controls each reach **8/16**.
The guided policy wins separately in both independently evaluator-owned
partitions (8/8 each), so this is not a one-partition accident.

Harness: `sparse_poly_discovery/probe_guided_grammar_round_o.zig`. Ledger:
`results/probe_guided_grammar_round_o.csv`.

## Protocol

The policy receives a public `amber`/`violet` base trace and frozen public
history of which permitted diagnostic is informative for that trace. Each test
trace has an even grammar-outcome split; a trace-only or family-prior route is
therefore 8/16. The evaluator retains the scoring relation and two hidden test
partitions. The policy cannot inspect target formulas, names, masks, labels,
or manifest data.

Every arm receives an equal four-call persistent session budget:

1. base trace observation;
2. one diagnostic slot (inert for no-probe controls);
3. a public grammar commitment, frozen before scoring;
4. evaluator-owned fresh score.

Each arm emits an explicit rejected fifth-call row. The guided grammar is
selected solely from the aggregate diagnostic reply; it is not revised after
the fresh score. The two candidate grammars are public, small, and distinct.

## Result

| Arm | Fresh exact | Cost / target |
|---|---:|---:|
| Probe-guided grammar | **16/16** | 4 calls |
| Fixed grammar | 8/16 | 4 calls |
| Blind grammar/probe | 8/16 | 4 calls |
| Family prior | 8/16 | 4 calls |
| No probe | 8/16 | 4 calls |

## Checks

- base trace has no grammar-routing advantage (balanced 8/16);
- two independent evaluator-owned partitions each show the strict win;
- frozen train/query history, separated from test scoring;
- token and test order reversal preserves the result;
- all action rows, commitments, fresh scores, and rejected over-budget calls
  are logged individually;
- public-ledger scan rejects formulas, labels, masks, manifests, and test
  labels; candidate and probe names are public only;
- fixed, blind, prior, and no-probe arms use the same charged budget.

This is still controlled: the grammar alphabet, diagnostics, history, and
evaluator API are supplied. It proves that active measurement can make an
otherwise trace-decoupled grammar commitment transfer across more than one
held-out evaluator partition; it does not prove open-ended grammar invention.

## Reproduce

```bash
rm -rf /tmp/zig-o4-cache /tmp/zig-o4-global /tmp/probe_guided_grammar_o4
zig build-exe sparse_poly_discovery/probe_guided_grammar_round_o.zig -O ReleaseFast \\
  --cache-dir /tmp/zig-o4-cache --global-cache-dir /tmp/zig-o4-global \\
  -femit-bin=/tmp/probe_guided_grammar_o4
/tmp/probe_guided_grammar_o4 run results/probe_guided_grammar_round_o.csv
/tmp/probe_guided_grammar_o4 selftest
```
