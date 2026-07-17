# Round AJ / AJ3 — Experience compounding under a frozen substrate

**Verdict: COMPOUNDING POSITIVE (foundation tier only).** An earned causal
record from a first raw-interaction regime makes a causally distinct second
discovery cheaper and reliable in a pre-registered withheld regime. The record
contains a polarity relation, evidence total, and provenance—not a world ID,
answer trace, target, action table, or score. The second discovery is a phase
relation in a separate interaction law.

## Question and pre-registration

Can retained *experience*, rather than retained answers, compound? Before the
run, the evaluator fixes 48 hidden cohorts. Each has a first raw regime with a
latent polarity and a withheld second regime with separately sampled period and
phase. Private evaluation uses contacts never used during discovery. The
organism sees only finite raw interaction consequences while probing; the
evaluator measures held-out material after the interaction budget is spent.

The frozen substrate supplies only bounded raw transport, generic reversible
variation/execution, accounting, append-only provenance, and sealed world
generation/evaluation, as declared in the Round AJ master. It contains no
target score during a run, task menu, decoder, answer trace, or candidate
library.

## Mechanisms and causal separation

The first mechanism is an earned signed-polarity relation. It is validated on
ten evaluator-private first-regime contacts. The second mechanism is a phase
relation that selects raw actions in the withheld period/phase regime. A
polarity relation cannot itself select the withheld phase; it instead removes
one causal orientation, allowing the same finite perturbation budget to find
phase. This is the required separate causal role.

## Controls

Every policy gets the same *maximum* 12-contact second-regime budget; the
compounded mechanism spends only the causal contacts required to resolve phase,
so its lower charged cost is itself recorded rather than hidden. The CSV records fresh start, preceding-cohort replay,
shuffled provenance, a raw first-world answer trace, a retained first-world
response table, fixed generic polarity, and literal first-record ablation.
Those answer-shaped controls have no transferable relation and cannot solve the
second regime. Replay and shuffled records usually carry the wrong polarity;
fixed-generalist has no causal evidence. A valid result requires the compounded
policy to beat every one on held-out second-regime material, transfer its first
record privately, and commit both roles.

## Result and limit

The source emits a deterministic `COMPOUNDING_POSITIVE` only if the strict
comparisons pass. This is a meaningful foundation result under the explicitly
frozen substrate: causal experience, not cached answers, makes a second
discovery possible under the finite budget. It is **not** a claim of open-ended
autonomy, self-chosen experiments, arbitrary representation invention, or
hostile process containment. The uniform synthetic raw medium and finite
perturbation schedule remain trusted substrate assumptions; later waves must
test broader private world families and independent audits.

## Reproduce

```bash
mkdir -p /tmp/zig-aj3-cache /tmp/zig-aj3-global
zig build-exe sparse_poly_discovery/experience_compounding_round_aj.zig \
  -femit-bin=/tmp/experience-compounding-aj3 \
  --cache-dir /tmp/zig-aj3-cache --global-cache-dir /tmp/zig-aj3-global
/tmp/experience-compounding-aj3 selftest
/tmp/experience-compounding-aj3 run results/experience_compounding_round_aj.csv
```

Expected:

```text
round_aj_aj3 selftest PASS verdict=COMPOUNDING_POSITIVE deterministic=true answer_scrubbed=true distinct_roles=true
```

## Artifacts

- `sparse_poly_discovery/experience_compounding_round_aj.zig`
- `results/experience_compounding_round_aj.csv`
- `docs/research/experience_compounding_round_aj.md`
