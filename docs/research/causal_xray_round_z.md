# Round Z Z1 — Causal X-Ray Lineage

## Verdict

**DONE — bounded instrumentation foundation.** A 12-event public DAG records
mutation → development → activation → organism probe → raw-world change →
delayed resource outcome → freeze/replay plus four independent counterfactual
branches. Its canonical digest is `e8b3b1a996edb878`; reverse reconstruction is
byte-identical. The ledger conserves exactly 36 energy, 142 bytes, and 60 ticks.

This is not intelligence, causal-unit birth, or self-improvement. The event
schema and intervention categories are human-built measurement infrastructure.

## Method

Each immutable event contains an opaque content ID, parent ID, independent world
digest, event kind, opaque payload digest, and exact energy/byte/tick charge.
The content ID commits to every field. A parent must already exist, duplicate
content is rejected, and canonical serialization sorts by ID so traversal order
cannot alter the snapshot.

The public schema deliberately has no evaluator seed, hidden map, component
score, answer, semantic feature, named port, or observer command. The observer
can receive a copied snapshot but has no mutation interface. Ghost contributes
only the read-only discipline: candidates are speculative until freeze, the
CSV is the replayable snapshot, and evidence rank is earned. No Ghost shard,
Rune value, Sigil implementation, VSA/LLM path, text model, embedding, imported
algorithm, or solution menu enters the harness.

## Causality experiment

Ordinary chronological co-activation earns confidence 0. Four distinct,
independently hashed worlds contribute bounded evidence:

| Evidence | Confidence after evidence |
|---|---:|
| removal | 20 |
| restoration | 40 |
| sibling trial | 55 |
| post-freeze transfer | 80 |
| false temporal correlation plus contradiction | 0 |

Repeating the same removal receipt 99 times still contributes only once.
Therefore provenance is automatic, while causal credit changes only through
independent interventions and contradictions.

## Hostile controls

Eleven controls fail closed: missing parent, event reordering, forged parent,
same-ID/different-payload alias, duplicate evidence, correlation presented as
causation, answer-field injection, observer influence, deleted cost, post-freeze
editing, and replay nondeterminism. Hash-alias coverage is bounded to deliberate
record forgery; this experiment does not prove mathematical collision resistance
of the 64-bit local digest. Privacy is enforced by a closed public record schema,
not by a hostile-process OS isolation claim.

## Reproduction

```bash
ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-z1 \
ZIG_LOCAL_CACHE_DIR=/tmp/zig-local-z1 \
zig run sparse_poly_discovery/causal_xray_round_z.zig -- \
  results/causal_xray_round_z.csv
```

Expected closure:

```text
SELFTEST PASS: 12-event content-addressed DAG; exact cost conservation;
canonical replay; intervention-only confidence; 11 hostile attacks fail closed.
Foundation only.
```
