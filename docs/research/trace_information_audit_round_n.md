# N2 — independent trace-information audit

**Verdict: PASS — decoupled counterfactual corpus has zero trace-only family information.** This is an information-boundary test, not a solver result.

Harness: `sparse_poly_discovery/trace_information_audit_round_n.zig`.
Ledger: `results/trace_information_audit_round_n.csv`.

## Method

The audit builds 24 deterministic public diagnostic signatures: four aggregate
bank maxima (`global`, `singleton`, `directed`, `adjacency`). Each signature is
emitted twice, once for each evaluator-only winning family (`bit_zero`,
`bit_one`). Twelve paired signatures are train and twelve are held out. Thus
for every held-out public trace `x`, the corpus has both `(x, bit_zero)` and
`(x, bit_one)`.

This construction gives an exact upper bound: every deterministic function
`f(public_trace)` is right once and wrong once per held-out pair, hence exactly
12/24. It is stronger than a claim that a particular classifier happened not
to learn the shortcut.

The finite frozen attacker suite is reported anyway: family-prior, global-vs-
directed, total-score cutoff, first-field cutoff, and nearest-centroid. Each is
replayed under all 24 permutations of the four public fields. Public tokens
are output-only; an explicitly illegal token-parity attack is measured so a
future API change cannot silently turn tokens into a shortcut.

## Result

| Test | Held-out accuracy | Requirement |
|---|---:|---|
| Any deterministic trace-only function (exact bound) | **12/24** | at family prior |
| Frozen simple classifiers, worst of 24 field permutations | **12/24** | at family prior |
| Illegal token-parity attack | reported in ledger | no systematic ID signal; token is not policy input |

The harness fails with `ValidTraceLeakageFailure` if a trace classifier exceeds
12/24. It separately fails if the deliberately illegal token-ID attack exceeds
the preregistered 15/24 systematic-leakage threshold.

## Attacks and limits

- **Token rename / row order:** policy classifiers receive `Trace` only, and
  their result is replayed under all field presentations; tokens are output.
- **Target-ID attack:** token parity is tested explicitly and never passed to a
  classifier. A future target-ID API path must be treated as leakage.
- **Permutation:** every one of 24 public-field permutations is scored.
- **Duplicate attack:** duplicates are intentional counterfactual witnesses;
  deduplication yields 12 ambiguous keys, not 24 independent wins.

The corpus is an *audit fixture*, deliberately stronger and more artificial
than a natural decoupled generator. It proves the public trace alone contains
no family bit here. It does **not** prove that a policy can solve such targets,
that labels are safe, or that a more realistic benchmark has no indirect
shortcut. N1 must supply the fresh benchmark; N5 must use it with a sealed
evaluator and a separate red-team audit.

## Reproduce

```bash
rm -rf /tmp/zig-n2-cache /tmp/zig-n2-global /tmp/trace_information_audit_round_n
zig build-exe sparse_poly_discovery/trace_information_audit_round_n.zig -O ReleaseFast \
  --cache-dir /tmp/zig-n2-cache --global-cache-dir /tmp/zig-n2-global \
  -femit-bin=/tmp/trace_information_audit_round_n
/tmp/trace_information_audit_round_n results/trace_information_audit_round_n.csv
/tmp/trace_information_audit_round_n selftest > /tmp/trace_information_audit_round_n.selftest.csv
cmp results/trace_information_audit_round_n.csv /tmp/trace_information_audit_round_n.selftest.csv
```
