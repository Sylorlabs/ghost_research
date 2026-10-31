# L3 — sealed evaluator substrate

**Verdict: positive evaluation infrastructure, not an autonomy result.**

Harness: `sparse_poly_discovery/sealed_evaluator_round_l.zig`. Result ledger:
`results/sealed_evaluator_round_l.csv`.

L3 separates two roles. The evaluator owns target formulas, parameters, and
seeds; it emits a small public transcript containing only an opaque target
token, an opaque input, and its label. The policy consumer accepts only that
six-column transcript and rejects fields named `formula`, `audit`, `mask`,
`threshold`, `residue`, `modulus`, or `seed`.

The deterministic evaluator contains three private target forms (directed
crossing, threshold, adjacency) and emits 36 labelled examples. The checked
ledger records a SHA-256 commitment of the transcript, byte-identical replay,
schema rejection checks, and a check that a private formula name and parameter
do not appear in the public transcript.

## Boundary and limitation

The roles are separate executable modes and can be invoked as separate
processes:

```bash
cd sparse_poly_discovery
zig build-exe sealed_evaluator_round_l.zig -O ReleaseFast -femit-bin=/tmp/sealed_l
/tmp/sealed_l evaluator /tmp/l3.public.csv
/tmp/sealed_l policy /tmp/l3.public.csv
/tmp/sealed_l selftest /tmp/l3.check.csv
cmp ../results/sealed_evaluator_round_l.csv /tmp/l3.check.csv
```

This is a **protocol-level** boundary, not OS isolation. The same Unix user
can still inspect the evaluator source or any private input unless a later
runner uses separate users/containers, filesystem ACLs, and an independently
held manifest. L3 makes that limitation explicit and must not be cited as a
sealed external evaluation service.

## Result

All deterministic replay and schema/adversarial boundary checks pass. L3 is
the substrate needed for a stronger future map-making claim; it does not give
a policy access to a hidden formula, prove a policy cannot exploit other
side-channels, or establish that a proposed grammar transfers.

## Revision: public experiment API (after L4 interface block)

L4 correctly found that opaque input/label examples alone were too narrow for
an honest map-guided expedition: a policy could neither obtain its current-menu
trace nor test a proposal. The evaluator now exposes two **policy-safe**
operations, still keyed only by opaque tokens:

- `diagnostics <csv>` publishes current-menu aggregate maxima, accuracy, and
  charged candidate count for the global, singleton, directed, and adjacency
  banks. It contains no target formula, parameters, mask, audit fields, or
  target identity.
- `query <csv> <opaque-token> <candidate-kind> <a> <b> <c>` evaluates one
  public-language candidate and returns aggregate correct count, accuracy, and
  one charged call. This is the experiment bench for a proposer; it is not an
  answer key.

`results/sealed_evaluator_api_round_l.csv` is the deterministic diagnostics
ledger and `results/sealed_evaluator_api_query_round_l.csv` is a checked public
query example. The evaluator owns all scoring and charges every diagnostic
candidate/query. The current implementation still lacks OS-level isolation and
a persistent cross-process budget authority, so any later positive must audit
both the protocol transcript and the aggregate call ledger.
