# Round AJ / AJ2 — reusable causal abstraction
**Verdict: FOUNDATION POSITIVE, bounded to the declared frozen substrate.** An
organism-owned signed rank-order relation, earned from direct raw transition
history, selected the correct intervention in evaluator-private relay worlds.
It transfers through private action-address and value recoding, is causally
necessary, and beats all pre-registered controls. This is evidence for a
reusable causal abstraction; it is neither full autonomy nor a claim that the
organism invented the substrate, the raw interaction law, or hostile
containment.

## Pre-registered question

In training, each of 32 cohorts acts in 12 opaque *direct material* worlds.
An action's local material pattern is either more or less repeatable, and its
immediate persistence effect has a cohort-private sign. The organism can retain
only an append-only provenance record of raw action, repeated-versus-changed
material, and persistence change. It builds the generic structure:

```text
signed relation: rank(repeatability) -> direction of persistence change
```

The 24 transfer worlds per cohort are from a different, pre-registered
mechanism: action changes an unlabelled relay, then the relay changes material
persistence. Transfer world IDs use a distinct hash domain from all training
world IDs. Their action addresses and byte-value encodings are evaluator-private
permutations. No family name, target action, target value, answer trace,
intermediate evaluator score, candidate library, LLM, text model, embedding, or
neural component is available during a run.

All generic-probe policies spend eight raw probes per transfer world (6,144
total). The held-out evaluator measures untouched and committed material only
after the policy has acted.

## Results — private wholesale-recoding transfer

| Policy | Raw probes | Untouched | Committed | Commits |
|---|---:|---:|---:|---:|
| earned signed rank-order relation | 6,144 | 16,853 | **26,069** | **768/768** |
| fixed generic: always prefer greatest repeatability | 6,144 | 16,853 | 21,390 | 432/768 |
| relation ablated to that fixed generic | 6,144 | 16,853 | 21,390 | 432/768 |
| shuffled other-cohort history | 6,144 | 16,853 | 19,365 | 288/768 |
| random action after equal raw probes | 6,144 | 16,853 | 16,659 | 94/768 |
| replayed training action address | 6,144 | 16,853 | 16,841 | 107/768 |
| static action zero | 0 | 16,853 | 16,506 | 81/768 |
| retained training answer/address cache | 0 | 16,853 | 16,915 | 112/768 |
| false (reversed) history | 6,144 | 16,853 | 15,360 | 0/768 |
| evaluator-private oracle | 0 | 16,853 | 26,069 | 768/768 |

The same learned relation gets 26,142 in native transfer encoding and 26,069
after wholesale private address/value recoding. The small difference is only
world noise; it commits all 768 worlds in both cases. The answer-memory and
replay controls fail because they preserve addresses, while the learned object
preserves a relation that is re-instantiated from fresh raw transition traces.

## Why this counts at the foundation tier

The new mechanism is not a fixed preference for high repeatability: half the
cohorts require the reverse direction, which is why the equal-cost fixed-generic
control reaches only 432/768 commits. Removing the earned sign leaves exactly
that control. Shuffling history, reversing it, and retaining a training answer
all destroy the advantage. The transfer world uses a delayed relay rather than
the direct training mechanism, so this is not train-set optimization.

The claim is intentionally narrow. The host still supplies universal raw state
transport, bounded memory/time, generic intervention budget, causal-event
provenance transport, hidden-world generation, and external post-run resource
measurement—the trusted Round AJ substrate. Those are not claimed as
organism-owned. The source has no OS isolation claim and cannot elevate this to
full autonomy/security.

## Attacks and limits

- **Target/answer attack:** training actions and cached answers are physical
  addresses; private transfer permutations make them ineffective.
- **Representation attack:** all action addresses and material values are
  recoded in the transfer condition; only repeat-versus-change relation is used.
- **World-overlap attack:** training and transfer IDs have distinct seed
  domains, checked exhaustively in `selftest`.
- **Fixed abstraction attack:** the same raw probe budget with a fixed positive
  repeatability rule loses on the negative-polarity cohorts.
- **History attack:** shuffled and reversed causal records lose; this rules out
  a generic probe budget alone explaining the result.

## Reproduce

```bash
mkdir -p /tmp/zig-aj2-cache /tmp/zig-aj2-global
zig build-exe sparse_poly_discovery/reusable_abstraction_round_aj.zig \
  -femit-bin=/tmp/reusable-abstraction-aj2 \
  --cache-dir /tmp/zig-aj2-cache --global-cache-dir /tmp/zig-aj2-global
/tmp/reusable-abstraction-aj2 selftest
/tmp/reusable-abstraction-aj2 run results/reusable_abstraction_round_aj.csv
```

Expected:

```text
round_aj_aj2 selftest PASS verdict=FOUNDATION_POSITIVE deterministic=true transfer=true anti_answer=true relation_owned=true
```
