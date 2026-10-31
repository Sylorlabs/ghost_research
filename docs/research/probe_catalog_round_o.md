# O1 — probe catalogue and information/cost curve

**Verdict: controlled positive — declared aggregate probes route the held-out
tool above the frozen family prior without publishing formulas, target IDs,
audit data, or per-target test labels.**

Harness: `sparse_poly_discovery/probe_catalog_round_o.zig`.
Ledger: `results/probe_catalog_round_o.csv`.

## Question

Round N removed the shortcut from a passive public trace to the winning tool.
O1 asks the next narrower question: can an evaluator safely provide a
predeclared *experimental probe* whose aggregate conditional reply helps route
a tool, while retaining a sealed test split?

## Protocol

There are 12 deterministic public trace signatures, each counterfactually
paired with both hidden tools (`bit_zero`, `bit_one`). Four paired signatures
are train, four query, and four sealed test: 8 cells per split. The passive
base trace therefore has exactly one correct and one incorrect route for each
signature, so the frozen `bit_zero` family prior is 4/8 on test.

The evaluator owns the hidden tool and exposes only these declared replies:

| Probe | Public aggregate reply | Charged cost |
|---|---|---:|
| `balance` | `aggregate_high` or `aggregate_low` | 1 |
| `agreement` | `consistent` or `inconsistent` | 1 |
| `balance_then_agreement` | both declared replies | 2 |

The harness never writes formula, hidden tool, target ID, audit label, or an
individual test correctness label. Test rows say `WITHHELD`; only final arm
totals are released. Tokens are opaque and output-only. Row/token reversal,
counterfactual duplicate pairing, and a persistent session budget are tested.
Every action/probe observation has its own CSV row and its own charged cost;
a simulated restart retains spent budget and cannot consume a second session
cap.

## Result

| Routing arm | Held-out routing | Cost/target | Empirical information | Information/cost |
|---|---:|---:|---:|---:|
| Base trace / frozen family prior | 4/8 | 0 | 0.000 bits | 0.000 |
| `balance` | **8/8** | 1 | **1.000 bit** | **1.000** |
| `agreement` | **8/8** | 1 | **1.000 bit** | **1.000** |
| `balance_then_agreement` | **8/8** | 2 | **1.000 bit** | **0.500** |

At least one declared probe exceeds the 4/8 frozen prior as required. The
sequence intentionally demonstrates a catalogue fact: a second redundant
probe may add cost without adding routing information.

## Controls and limits

- **Trace decoupling:** each passive trace occurs once with each hidden tool;
  base routing is exactly prior, not merely weak.
- **Train/query/test:** only train/query rows expose route feedback. Test rows
  release aggregate arm totals after the sealed session.
- **Privacy:** output columns contain literal `WITHHELD` placeholders for
  formulas, target IDs, audit labels, and test labels. Tokens are not policy
  inputs.
- **Order/duplicates:** arm rows include token-and-row reversal; each public
  signature has an intentional counterfactual pair.
- **Persistent budget:** each arm has a 48-cost session cap; a copied/restarted
  state is refused when attempting to consume another cap.

This is a **synthetic protocol fixture**, not proof of general diagnosis. The
aggregate reply is deliberately constructed to contain one diagnostic bit. O1
shows how active information acquisition can be made explicit, costed, and
non-private; it does not show that a system discovered the probe, that the
probe would be predictive on natural targets, or that process-level sealing is
OS isolation.

## Reproduce

```bash
rm -rf /tmp/zig-o1-cache /tmp/zig-o1-global /tmp/probe_catalog_round_o
zig build-exe sparse_poly_discovery/probe_catalog_round_o.zig -O ReleaseFast \\
  --cache-dir /tmp/zig-o1-cache --global-cache-dir /tmp/zig-o1-global \\
  -femit-bin=/tmp/probe_catalog_round_o
/tmp/probe_catalog_round_o results/probe_catalog_round_o.csv
/tmp/probe_catalog_round_o selftest > /tmp/probe_catalog_round_o.selftest.csv
cmp results/probe_catalog_round_o.csv /tmp/probe_catalog_round_o.selftest.csv
```
