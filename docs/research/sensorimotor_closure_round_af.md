# Round AF / AF2 — endogenous sensorimotor closure

**Verdict: VALID NEGATIVE.** The mutable closure record produces a small,
costed fresh-resource improvement inside this local simulator: **57,365 →
58,073**. Removing it returns exactly to baseline. That is not evidence that
the organism formed its own criterion. The equally expressive fixed-closure
control reaches **58,165**, and the host code still determines the supposedly
raw intervention, its consequence sites, their grouping, the relation between
them, record alignment, agreement, and acceptance. The experiment therefore
rejects its own autonomy claim.

## Question

Can a mutable organism discover which raw changes are consequences of its own
raw perturbations, form a criterion over that closure, and use it for
survival in sealed fresh worlds after private rewiring and relabeling—without a
semantic port, action menu, state grouping, target, score, comparison,
decoder, VM, candidate generator, or curriculum supplied by a host?

No LLM, text/token prediction, embeddings, neural model, neuro-symbolic
component, answer trace, or oracle appears in the experiment. The intended
exterior is a deterministic uniform raw transport and finite resource ledger.
This report explicitly identifies where the implementation exceeds that
exterior, rather than counting an apparently strong number as autonomy.

## Protocol

Each of 24 cohorts starts as a 128-byte raw field. Uniform local transport
updates every raw address from its neighbors. The active condition maintains a
20-byte closure record for 20 epochs and makes two charged training
measurements of 10 trial calls per epoch; then it is evaluated on 30 sealed
fresh trials. Active paths therefore charge 11,040 calls
(24 × 20 × 2 × 10 plus 24 × 30 fresh calls); inactive paths charge only the
1,440 fresh calls. Fresh trials are never used for acceptance.

The critical invalidating layer is visible in source:

- `hostClosure` selects a raw XOR perturbation's address and magnitude,
  selects outcome positions and their grouping/time separation, and encodes an
  XOR-difference relation into 20 ordered bytes.
- `hostResource` declares record bytes to be predictions, aligns them with the
  host closure, uses Hamming agreement, and converts it to resource.
- The scalar `fresh > old` is a host-provided candidate comparison and
  acceptance criterion.

Those are not bare enforcement physics. They are exactly a sensorimotor probe
grammar and a supplied meaning for "closure." Thus the record merely fills
values in a human-built language.

Controls are equal active-cost raw mutation, replay, static matter, an
equally expressive fixed closure, shuffled lineage, inverted/false lineage,
and equal-cost copied/bloated records. Attacks privately relocate addresses,
recode values, resegment groups, permute instruction identity, and destroy
boundaries. Two independent CSV writes must be byte-identical.

## Results

| Condition | Charged work | Old resource | Fresh resource | Difference | Fresh commits |
|---|---:|---:|---:|---:|---:|
| mutable closure record | 11,040 | 57,365 | **58,073** | +708 | 12 / 24 |
| criterion ablation | 1,440 | 57,365 | 57,365 | 0 | 0 / 24 |
| equal-cost raw random | 11,040 | 57,365 | 58,037 | +672 | 8 / 24 |
| equal-cost replay | 11,040 | 57,365 | 57,365 | 0 | 0 / 24 |
| static raw field | 1,440 | 57,365 | 57,365 | 0 | 0 / 24 |
| equally expressive fixed closure | 11,040 | 57,365 | **58,165** | **+800** | 11 / 24 |
| shuffled causal lineage | 11,040 | 57,365 | 58,039 | +674 | 9 / 24 |
| copied/bloated closure | 11,040 | 57,365 | 58,049 | +684 | 13 / 24 |
| false/inverted lineage | 11,040 | 57,365 | 57,365 | 0 | 0 / 24 |

The ordinary record has a 708 resource gain and exact ablation loss, but it
does **not** clear the specified equal-expressive control: fixed closure is
92 resource higher. Raw random is only 36 below the active record and shuffled
lineage only 34 below it. This is weak evidence even inside the supplied game,
not a strong causal discovery result. False lineage makes 73 harmful internal
updates and all 24 fresh outcomes roll back, showing that the host-selected
lineage influences the host-selected evaluator; it does not make that
relation organism-owned.

The destruction rows retain a small change under every attack, but this is
also non-evidence of reconstruction: the host remaps its own closure and
resource decoder alongside each attack. Their fresh resources are 58,035
(address relocation), 58,326 (value recoding), 58,187 (resegmentation),
58,017 (instruction destruction), 57,861 (boundary destruction), and 58,076
under combined address/value/group/instruction/boundary destruction.

## Why it fails the AF2 gate

1. **The action is supplied.** A specific XOR intervention and magnitude are
   hard-coded in `hostClosure`; the organism cannot decide what counts as its
   own perturbation.
2. **The observations are supplied.** The host chooses 20 consequence sites,
   their ordering and grouping. This is a semantic port under another name.
3. **The relation is supplied.** XOR difference and alignment define what it
   means for a consequence to belong to the perturbation.
4. **The criterion is supplied.** Hamming agreement and `fresh > old` are
   external comparison/selection semantics, not an internally earned reason.
5. **The strongest control wins.** Fixed closure outperforms the mutable
   record at equal cost. No claim survives that comparison.
6. **Private destruction is host-mediated.** The evaluator transforms the
   record and observation relation together, so persistence cannot establish
   organism-built reconstruction.

The remaining human ownership is decisive: raw transport selection, private
world family, intervention form, sample timing, observation and grouping
grammar, relation encoding, record boundary/alignment, evaluator, and
acceptance test. This experiment does not unlock AF4–AF6.

## Reproduce

```bash
mkdir -p /tmp/zig-cache-af2 /tmp/zig-global-af2
zig build-exe sparse_poly_discovery/sensorimotor_closure_round_af.zig \
  -femit-bin=/tmp/sensorimotor-closure-af2 \
  --cache-dir /tmp/zig-cache-af2 --global-cache-dir /tmp/zig-global-af2
/tmp/sensorimotor-closure-af2 selftest
/tmp/sensorimotor-closure-af2 run results/sensorimotor_closure_round_af.csv
```

Expected self-test:

```text
round_af_af2 selftest PASS verdict=VALID_NEGATIVE deterministic=true closure_gain=true organism_owned_criterion=false
```

Artifacts: `sparse_poly_discovery/sensorimotor_closure_round_af.zig`,
`results/sensorimotor_closure_round_af.csv`.
