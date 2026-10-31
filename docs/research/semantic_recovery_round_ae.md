# Round AE / AE3 — semantic destruction and recovery

**Verdict: VALID NEGATIVE.** A mutable causal-record tape is rebuilt after the
private evaluator simultaneously destroys location, value, segmentation,
instruction, and boundary identity. The rebuilt tape restores fresh-world
resource, is charged, is necessary by ablation, and false evidence rolls it
back. It is nevertheless transport through a supplied byte relation, not
organism-owned operational semantics.

## Question and isolation

Twenty cohorts begin with opaque raw matter and no retained record tape. They
receive only aggregate resource consequences from nine calibration
interactions. Before fresh evaluation, the evaluator privately applies either
one identity destruction or the combined wholesale transformation: relocation,
value recoding, resegmentation, instruction permutation, and boundary
destruction. The cohort must rebuild a tape from its earned causal history,
then freezes it before 23 independent fresh worlds. It sees no answer values,
target name, task family, external builder, task menu, or intermediate score.

Every calibration interaction is charged. A cohort commits only if sealed
fresh resource improves; otherwise it rolls back. No LLM, text model,
embedding, neural system, solution trace, or named curriculum is present.

## Results

| Wholesale policy | Charged calls | Old fresh resource | Committed fresh resource | Commits |
|---|---:|---:|---:|---:|
| recovered causal-record tape | 57,600 | 71,596 | **89,950** | 20/20 |
| fixed decoder, equal cost | 57,600 | 71,596 | **89,950 (tie)** | 20/20 |
| equal expressive fixed language | 57,600 | 71,596 | **89,950 (tie)** | 20/20 |
| copied bytes / static | 0 | 71,596 | 71,596 | 0/20 |
| random raw records | 0 | 71,596 | 74,402 | 13/20 |
| prior-cohort replay | 0 | 71,596 | 74,793 | 13/20 |
| shuffled causal evidence | 57,600 | 71,596 | 72,677 | 11/20 |
| false causal evidence | 57,600 | 71,596 | 71,596 after rollback | 0/20 |
| evaluator-private oracle | 0 | 71,596 | 147,128 ceiling only | 20/20 |

The executable CSV contains exact totals for native, each single destruction,
and the combined wholesale case. `selftest` emits it twice and requires
byte-identical replay; it also requires recovery to beat random and baseline,
tie both equally costly host-language controls, lose its advantage under
ablation, and roll every false-evidence cohort back.

## Why this is a valid negative

The apparent semantic record is a byte array. The host defines the operation
that combines a representation byte, a record byte, and a private value mask.
It also supplies byte atoms, the array boundary, bit-flip proposal grammar,
search order, and transaction geometry. The recovered tape can move behavior
across destroyed identities, but it cannot change what execution *means*.

The fixed-decoder and equal-language controls tie exactly, which is decisive:
the result is not a newly selected or constructed operational semantics. It is
an optimized instance of the already supplied one. This experiment therefore
does not release AE4–AE6.

## Reproduce

```bash
mkdir -p /tmp/zig-ae3-cache /tmp/zig-ae3-global
zig build-exe sparse_poly_discovery/semantic_recovery_round_ae.zig \
  -femit-bin=/tmp/semantic-recovery-ae3 \
  --cache-dir /tmp/zig-ae3-cache --global-cache-dir /tmp/zig-ae3-global
/tmp/semantic-recovery-ae3 selftest
/tmp/semantic-recovery-ae3 run results/semantic_recovery_round_ae.csv
```

Expected line:

```text
round_ae_ae3 selftest PASS verdict=VALID_NEGATIVE deterministic=true recovery=true organism_owned=false
```

Residual human-owned scaffold: the fixed `execute` relation (a decoder and
semantic algebra), byte atoms, fixed record-array boundary, bit-flip proposal
operator and order, plus commit/rollback geometry. The exterior evaluator is
also necessarily responsible for isolation, resource accounting, and private
fresh-world evaluation; those enforcement roles are not claimed as organism
ownership.
