# AA1 — Autonomous uncertainty experiments

**Verdict: VALID NEGATIVE.** The opaque organism policy covered all twelve
material units and reduced the evaluator-private competing-particle set to one,
but it did **not** improve downstream resource preservation. Its held-out
resource loss was **3,446**, worse than random (**3,326**), fixed (**3,223**),
replay (**3,191**), cheapest/frequency (**3,195**), and the private ceiling
(**3,149**). More importantly, the VM supplied the interpretation of the four
experiment bytes (unit, operation, temporal displacement, cost) and the
particle-retirement comparison. Therefore this is neither autonomous
experiment birth nor evidence for self-improvement.

Artifacts:

- `sparse_poly_discovery/autonomous_uncertainty_round_aa.zig`
- `results/autonomous_uncertainty_round_aa.csv`

## Boundary and upstream evidence

The harness validates the canonical Z1 and Z2 public contracts before running:
Z1's content-addressed intervention lineage and Z2's opaque material mine plus
negative-evidence receipt. It never parses or copies an evaluator-private
response map, transfer mask, correct experiment, or target-to-material join.

There is no LLM, token/text model, embedding, neural or neuro-symbolic path,
named task feature, semantic port, supplied solution Rune, external builder,
fixed capability request, or intermediate correctness/grounding/novelty score.
The program operates on opaque content digests, mutable bytes, charged receipts,
and later resource loss.

The experimental universe still installs significant structure. Twelve opaque
material units, four experiment-byte positions, sixteen competing response
particles, and a receipt disagreement threshold are fixture physics. That is
the decisive limitation, not a footnote.

## Experiment

An organism-owned four-byte program mutates for 24 charged experiments. The
bytes select an opaque unit and transform its operation, temporal displacement,
and execution cost. Receipts update organism-local evidence. Competing opaque
response particles retire only when their predictions conflict with charged
receipts. The policy sees no private particle identity or correct next action.

After the program freezes, 32 fresh worlds generate ordinary resource damage.
All policies pay the same 24-experiment / 96-byte headline budget; executed
cost is also accumulated in resource loss. The trace digest makes the selected
lineage replayable without publishing the private response physics.

## Results

| Policy | Remaining uncertainty | Resource loss | Units covered |
|---|---:|---:|---:|
| organism | 1 | 3,446 | 12 |
| random / causal ablation | 1 | 3,326 | 9 |
| fixed | 1 | 3,223 | 1 |
| replay | 1 | **3,191** | 1 |
| cheapest | 1 | 3,195 | 1 |
| frequency | 1 | 3,195 | 1 |
| address | 1 | 3,295 | 12 |
| byte-name surrogate | 1 | 3,307 | 6 |
| shuffled correspondence | 1 | 3,272 | 7 |
| false evidence | 0 | 3,274 | 12 |
| reversible recoding | 1 | 3,362 | 12 |
| private multi-seed ceiling | 1 | **3,149** | 12 |

The primary acceptance gate fails: the organism does not beat strong controls
on later resource loss. The uncertainty count is also demonstrably inadequate:
nearly every policy collapses it to one, while their future losses differ
substantially; false evidence collapses it to zero without becoming useful.
Thus the installed retirement axis measures consistency with the supplied
particle geometry, not useful causal understanding.

Raw recoding does not preserve the organism row exactly (3,446 to 3,362), so no
encoding-invariant experiment policy was born. Shuffling and false evidence
change the trace and downstream outcome, but do not create a clean causal
advantage. Removing the organism policy reproduces random exactly, confirming
the policy changes behavior while also confirming that its change is harmful.

## Hostile controls

The canonical ledger records fail-closed surfaces for hidden question grammar,
evaluator read/rewrite, observer influence, answer transcripts, duplicate
evidence, post-test selection, omitted cost, bloat, post-freeze edits,
nondeterminism, and LLM/text/embedding use. Two complete runs are byte-identical.
These establish instrument hygiene, not a positive intelligence result.

## Conclusion

AA1 supplies a useful diagnosis: exhaustive coverage and rapid collapse of a
human-shaped uncertainty set do not predict downstream capability. The next
attempt must let responsibility/experiment partitions compete by later resource
consequences rather than treating consistency with supplied particles as the
objective. AA2 must not treat this ledger as positive forge direction. AA4 must
remain blocked on AA1.

## Reproduction

```bash
mkdir -p /tmp/zig-aa1-cache /tmp/zig-aa1-global
zig build-exe sparse_poly_discovery/autonomous_uncertainty_round_aa.zig \
  -O ReleaseFast \
  --cache-dir /tmp/zig-aa1-cache \
  --global-cache-dir /tmp/zig-aa1-global \
  -femit-bin=/tmp/autonomous_uncertainty_round_aa
/tmp/autonomous_uncertainty_round_aa selftest
/tmp/autonomous_uncertainty_round_aa run results/autonomous_uncertainty_round_aa.csv
```
