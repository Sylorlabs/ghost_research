# K4 — hidden-structure holdout generator

**Verdict: positive evaluation substrate; no policy or routing result.** This
artifact creates a deterministic, post-policy-freeze hidden holdout suite for
Round K. It does not expose a feature API, fit a policy, score candidates, or
claim that a machine has chosen an appropriate grammar.

Harness: `sparse_poly_discovery/hidden_holdout_round_k.zig`. Revealed raw
manifest: `results/hidden_holdout_round_k.csv`.

## Protocol and information boundary

1. Before policy work begins, record the SHA-256 commitment printed by the
   harness for the chosen 64-bit manifest seed. The default frozen seed is
   `0x4B4B000000000001`; the resulting CSV contains the matching commitment.
2. Freeze the policy code, its feature inputs, candidate banks, and budget.
   During evaluation it receives only the `policy_*` fields plus opaque labeled
   example streams. It must not read `audit_*` fields.
3. Reveal the seed and generate the manifest. Audit fields are disclosed only
   after the policy is frozen, so target kind, mask, partition size, threshold,
   modulus, residue, permutation, and sample seed cannot become policy inputs.
4. An independent audit re-runs the deterministic generator from the revealed
   seed and compares the full manifest byte-for-byte.

The CSV explicitly separates `policy_*` from `audit_*` columns. The harness is
standalone and intentionally defines **no imported policy feature API**; any
later policy must interact through opaque examples in its own harness.

## Suite construction

The 24 held-out targets are freshly generated with a deterministic PRNG:

- directed partition targets with random masks of sizes 1, 2, 3, and 4;
- threshold, adjacency, XOR, and parity controls;
- fresh modulus/residue choices and independently shuffled eight-cell
  permutations;
- independent per-target example seeds.

Each target is checked on 1,024 generated examples. It is rejected and
regenerated unless its label rate lies in the inclusive 20--80% interval,
which rules out degenerate near-constant targets. An audit-only canonical
formula signature rejects duplicate generated formula specifications. The
permutation is recorded and applied before every target evaluation, preventing
an evaluator from relying on fixed physical cell positions.

This is intentionally a *holdout generator*, not a canned four-family corpus.
It gives K3 a later, unseen mixture of singleton through four-cell partitions
and unrelated controls. It does not establish that any candidate bank is
complete for those targets.

## Reproduce

From `sparse_poly_discovery/`:

```bash
zig build-exe hidden_holdout_round_k.zig -O ReleaseFast -femit-bin=hidden_holdout_round_k
./hidden_holdout_round_k ../results/hidden_holdout_round_k.csv 0x4B4B000000000001
./hidden_holdout_round_k /tmp/hidden_holdout_round_k.check.csv 0x4B4B000000000001
cmp ../results/hidden_holdout_round_k.csv /tmp/hidden_holdout_round_k.check.csv
```

Changing the last argument produces a new committed/revealed suite. That is
allowed only for a separately pre-committed evaluation wave; it must never be
used to select a favorable manifest after observing results.

## Result

The checked-in manifest records all 24 valid, nondegenerate, unique targets
with their audit fields and the default seed commitment. It is infrastructure
for future post-freeze evaluation only. No policy score, allocation result, or
autonomy claim follows from this artifact.
