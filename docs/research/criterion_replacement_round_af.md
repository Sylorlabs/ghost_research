# Round AF / AF3 — Criterion replacement and evaluator-private transfer

**Verdict: VALID NEGATIVE.** In a deterministic opaque raw-interaction fixture,
two mutable trace-dependent relation tapes are constructed, tested against later
raw consequences, and the old tape is retired when its successor wins. The
selected successor improves evaluator-private resource and the improvement
disappears under ablation. This is evidence-dependent bounded replacement, not
organism-owned criterion formation.

## Question

Can an organism create two internal causal relations from its own intervention
records, distinguish them through consequences, retire the weaker initially
useful relation, and transfer that replacement to a fresh private regime without
answer memory? The strict AF standard additionally forbids a supplied relation
language, observation/action semantics, candidate generator, comparison rule,
component boundary, decoder, VM, or hidden target.

## Fixture and safeguards

Each of 32 cohorts encounters an opaque, deterministic byte-consequence field.
Its only writable matter is a 16-bit raw tape. The constructed policy records
nine signed consequences per byte, creates an old relation in regime zero and a
successor relation in the fresh regime, probes each relation for seven charged
interactions, and commits only a strictly better successor. Evaluation happens
in a later private regime. All raw interactions, construction, probes and
testing are charged.

The implementation explicitly includes random, preceding-cohort replay, static,
shuffled-history, false-lineage, evaluator-answer-memory (invalid ceiling),
bootstrap-retained, ablation, and an equal-expressive fixed-criterion control.
It deterministically regenerates a combined identity-destruction fixture
(address/value/boundary recoding) and writes identical CSVs on replay.

## Result

Run the source below for exact machine numbers. The required relationship is
verified by its selftest: the constructed policy improves over its old relation,
random, replay and static controls; it retires at least one old relation; and
ablation is exactly old-resource. The equal-expressive fixed criterion ties the
constructed policy exactly, which is dispositive against the ownership claim.

The alleged re-encoding recovery is also not sufficient evidence: it uses the
same source-level relation builder and decoder after a test fixture changes
identities. No answer data is carried by the constructed policy; the
answer-memory row is deliberately invalid and exists only as a ceiling audit.

## Why it is negative

The host decides that sixteen byte atoms exist, that accumulating signed
consequences and thresholding them forms a relation, what each tape bit means,
how a tape becomes an action, which seven probes compare alternatives, how
their consequences add, and when a replacement commits or rolls back. Those
are precisely criterion construction, choice, retirement and operational
semantics. The organism writes values into that supplied language.

The exact fixed-control tie proves the observed gain requires no internally
created criterion language. It cannot release AF4–AF6.

## Reproduce

```bash
mkdir -p /tmp/zig-af3-cache /tmp/zig-af3-global
zig build-exe sparse_poly_discovery/criterion_replacement_round_af.zig \
  -femit-bin=/tmp/criterion-replacement-af3 \
  --cache-dir /tmp/zig-af3-cache --global-cache-dir /tmp/zig-af3-global
/tmp/criterion-replacement-af3 selftest
/tmp/criterion-replacement-af3 run results/criterion_replacement_round_af.csv
```

Expected:

```text
round_af_af3 selftest PASS verdict=VALID_NEGATIVE deterministic=true replacement=true organism_owned=false
```

## Artifacts

- `sparse_poly_discovery/criterion_replacement_round_af.zig`
- `results/criterion_replacement_round_af.csv`
- `docs/research/criterion_replacement_round_af.md`
