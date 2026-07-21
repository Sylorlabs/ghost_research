# AX1 — Typed witness evaluator

**Status:** COMPLETE — protocol component only; it is not an inventor result.

AX1 replaces AW's unsafe `CLAIM <token> <number>` contract. A candidate now
must submit one precommitted, canonical envelope:

```text
WITNESS_V1 <task-token> <task-kind> <tool-source-hash> <payload-hash> <derived-summary> <task-specific-witness>
```

The evaluator reconstructs the canonical witness from sealed payload bytes and
rejects scalar-only claims, malformed envelopes, wrong task kinds/tokens,
zero tool hashes, mismatched payload hashes, wrong summaries, duplicate or
out-of-range witness offsets, and any witness that does not exactly match the
recomputed one. Exact matching is deliberately strict: malformed duplicate or
out-of-range offsets cannot equal the canonical reconstruction.

Supported AW2 families are declaration offsets outside line comments; CSV
header-width plus malformed row/field witnesses; sleep offset plus enclosing
`while` span witnesses; and `MissingArg` return offset plus line span
witnesses. The self-test includes relevant counterfactual mutation (a new
declaration changes the witness) and unrelated-byte mutation (trailing newline
does not).

## Reproduce

```bash
zig run sparse_poly_discovery/typed_witness_evaluator_round_ax.zig -- selftest
zig run sparse_poly_discovery/typed_witness_evaluator_round_ax.zig -- replay
```

Expected: `typed_kinds=4 scalar_claims_rejected=true ... replay=deterministic`.

## Limit

This verifies structural claims, not semantic bug discovery or tool quality.
The evaluator must remain outside the candidate sandbox and must bind its
payload hash to the exact staged bytes for a real sealed run.
