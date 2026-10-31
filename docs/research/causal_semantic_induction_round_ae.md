# Round AE / AE1 — causal semantic induction

**Verdict: VALID NEGATIVE.** The mutable tape attains a large, costed,
ablatable prediction gain from raw transition observations: fresh resource rises
from **64,428** to **129,024**. It does not induce an organism-owned
operational semantics. The host names the 24 observation slots, aligns them to
tape addresses, and scores byte predictions. Those functions are precisely a
fixed probe grammar, decoder, and semantic comparison; the tape only fills in
values inside that supplied language.

## Question

Can mutable matter derive an executable interpretation from lower-level causal
transition traces and use it on evaluator-private trials, without a supplied
VM, opcode meanings, decoder, component/genome boundary, task family,
curriculum, target, candidate menu, semantic score, or answer trace?

The experiment uses no LLM, text/token prediction, embeddings, neural or
neuro-symbolic component, preloaded Rune, named target, or oracle selection.
Only a deterministic identical local transport, finite accounting, provenance,
sandboxing, and sealed trial calls are exterior conditions. The implementation
deliberately exposes the moment at which it exceeds those conditions, rather
than hiding it behind a positive label.

## Protocol

Twenty-four cohorts begin as independent 96-byte raw fields. A uniform local
transport law advances every address using its neighbors. In each of 18 epochs
the candidate condition writes a mutable 24-byte record from a transition
trace, compares incumbent and candidate over 12 charged observations, and is
then judged on 28 sealed fresh trials. Total ordinary charged work is 10,368
per active condition (24 × 18 × 2 × 12); fresh trials are kept outside the
selection calls. A stable causal law is evaluated repeatedly on fresh trial
instances, rather than treating a private answer string as a target.

This should be read as an adversarial test of the intended claim, not as a
model of how a free organism ought to work. `hostTrace` creates a fixed
24-position observation projection; `hostScore` reads fixed aligned positions
as predictions and computes Hamming agreement. The organism cannot change,
select, discover, retire, or reconstruct either function.

Equal-total-cost controls are raw random mutation, replay, static matter, and
an equally expressive fixed semantic writer. The attacks shuffle evidence,
invert evidence, relocate addresses, recode values, resegment trace positions,
permute instruction identity, and destroy the original boundary assignment.
All paths are deterministic; two independent CSV generations must be
byte-identical.

## Results

| Condition | Charged work | Old resource | Fresh resource | Difference | Fresh commits |
|---|---:|---:|---:|---:|---:|
| trace-record induction | 10,368 | 64,428 | **129,024** | **+64,596** | 24 / 24 |
| semantic ablation / static matter | 0 | 64,428 | 64,428 | 0 | 0 / 24 |
| equal-cost raw random | 10,368 | 64,428 | 71,960 | +7,532 | 22 / 24 |
| equal-cost replay | 10,368 | 64,428 | 64,428 | 0 | 0 / 24 |
| equally expressive fixed semantic | 10,368 | 64,428 | 71,428 | +7,000 | 23 / 24 |
| shuffled evidence | 10,368 | 64,428 | 66,864 | +2,436 | 11 / 24 |
| false/inverted evidence | 10,368 | 64,428 | 64,428 | 0 | 0 / 24 |

The signal is real inside the host-defined game: removal returns exactly to
baseline, random and the fixed writer are far below the trace-record result,
and shuffled evidence loses 62,160 resource relative to correct evidence.
False evidence makes 24 harmful internal updates and all 24 sealed fresh
outcomes roll back. Address relocation and value recoding retain 129,024,
while resegmentation changes the old baseline to 64,036 but still reaches
129,024. The same apparent success survives instruction and boundary
permutations because the host applies the matching remapping; that is evidence
of host mediation, not a semantic reconstruction by the organism.

## Why this is not semantic birth

1. **The observation language is supplied.** `hostTrace` selects 24 slots,
   their ordering, causal sampling, and evidence encoding. A trace record
   cannot decide what it observes.
2. **The execution meaning is supplied.** `hostScore` defines which tape cells
   are predictions, aligns them to trace slots, and defines agreement. It is a
   byte decoder and semantic comparison score, forbidden by the AE boundary.
3. **No bootstrap semantics is retired.** The cell record is mutable, but the
   interpreter of that record is not. There is no organism-created alternate
   interpreter that can replace `hostTrace`/`hostScore`.
4. **Fresh trials do not cure a fixed ontology.** Sealing trial calls prevents
   answer leakage; it cannot convert a host-specified observation/prediction
   partition into an earned one.

The residual human-owned layer is therefore decisive: the raw transport law,
trace projection, trace/tape boundary, address alignment, prediction decoder,
comparison function, and evaluator world generator. Only resource accounting,
sandbox/provenance, and sealed external trials plausibly belong in an exterior
in a future admissible experiment. This result does **not** unlock AE4.

## What a positive would require

The organism would need to construct multiple mutually incompatible causal
transducers from raw interaction, arrange its own observations and executable
interpretation, select one based on consequences without an externally named
comparison form, causally retire the bootstrap transducer, and retain useful
behavior after an evaluator independently destroys all old address, value,
instruction, and segmentation identities. Neither fixed tape positions nor a
host-provided prediction score may survive that audit.

## Reproduce

```bash
mkdir -p /tmp/zig-cache-ae1 /tmp/zig-global-ae1
zig build-exe sparse_poly_discovery/causal_semantic_induction_round_ae.zig \
  -femit-bin=/tmp/causal_semantic_induction_round_ae \
  --cache-dir /tmp/zig-cache-ae1 --global-cache-dir /tmp/zig-global-ae1
/tmp/causal_semantic_induction_round_ae selftest
/tmp/causal_semantic_induction_round_ae run results/causal_semantic_induction_round_ae.csv
```

Expected self-test:

```text
round_ae_ae1 selftest PASS verdict=VALID_NEGATIVE deterministic=true raw_trace_prediction_gain=true organism_owned_semantics=false
```

Artifacts: `sparse_poly_discovery/causal_semantic_induction_round_ae.zig`,
`results/causal_semantic_induction_round_ae.csv`.
