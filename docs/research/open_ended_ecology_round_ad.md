# Round AD / AD2 — open-ended challenge ecology

**Verdict: VALID NEGATIVE.** The bounded raw-state ecology obtains a real,
costed held-out resource gain, but it does not demonstrate an open-ended,
organism-owned challenge ecology. The host chooses the cell-array substrate,
the scan/rewrite candidate language, resource-consequence physics, seeded world
distribution, and trial cadence. Those choices are a hidden curriculum even
though no named task, answer trace, semantic port, score feature, task menu,
or operator menu is presented to the organism.

## Question and boundary

Can organisms generate their own experiments, constructions, and escalating
challenges from raw interaction consequences and a finite ledger, retaining
causal constructions in sealed evaluator-private worlds? The only intended
exterior is deterministic low-level transport, finite resource accounting,
sandbox/provenance, and sealed fresh worlds. This experiment treats every
organism-level convenience as hostile: no LLM, text/token prediction,
embeddings, neural or neuro-symbolic machinery, solution traces, target
function, named novelty/reward statistic, component map, candidate table,
operator menu, or preloaded experience is used.

The result is deliberately judged against the stronger condition: the
organism must author its own construction language and interaction medium. It
does not, so the result remains negative regardless of its numerical gain.

## Instrument

Thirty-two cohorts begin with 48 mutable raw cells. Sealed worlds expose only
the aggregate resource consequence of raw state/world collisions. For 28
charged rounds, a host loop scans a state and writes a full candidate state;
ordinary-world resource comparisons decide whether it remains. Nineteen fresh,
evaluator-private worlds decide final commit/rollback. All 10,752 ordinary
resource observations are charged. There is no exposed target or answer to
memorize.

This is still a bounded simulation. The evaluator's seeded transition field
and the host's scan/rewrite routine are concrete, human-authored structures;
they are reported as failure conditions rather than concealed as physics.

## Results

| Policy | Charged work | Old resource | Fresh resource | Transfers | Internal commits |
|---|---:|---:|---:|---:|---:|
| ecology | 10,752 | 34,163 | **35,322** | 15 / 32 | 451 |
| equal-cost random rewrites | 10,752 | 34,163 | 34,942 | 15 / 32 | 431 |
| equal-cost replay | 10,752 | 34,163 | 34,984 | 15 / 32 | 423 |
| static / causal ablation | 0 | 34,163 | 34,163 | 0 / 32 | 0 |
| fixed challenge | 10,752 | 34,163 | 34,945 | 18 / 32 | 32 |
| copied world (answer-memory attack) | 10,752 | 34,163 | 35,262 | 17 / 32 | 32 |
| false lineage evidence | 10,752 | 34,163 | 34,163 | 0 / 32 | 434 |
| value recoding | 10,752 | 34,163 | 34,772 | 14 / 32 | 435 |

The main policy earns +1,159 fresh resource over its ablated old state, +380
over random and +338 over replay at equal charged work. It creates 451 changed
states across the population. Causal ablation returns exactly to 34,163;
reversed lineage evidence yields zero final transfers and 32 fresh rollbacks.
These are bounded causal facts, not an autonomy conclusion.

## Hostile findings

- **Bloat is not rejected:** the bloat policy is behaviorally identical to the
  ecology, showing that the experiment has no organism-owned size/complexity
  economics.
- **Lineage is not causal enough:** shuffled lineage is identical to the main
  result. The ledger records history, but the construction does not use it as
  an independently reconstructible causal object.
- **Evaluator leakage is not independently tested:** the denied-leak row is
  identical because access is a host property, not a discovered defense.
- **Re-encoding does not reconstruct function:** value recoding changes fresh
  resource, commits, and lineage. Address relocation and the implemented
  segmentation permutation happen to preserve the host scan relation, which
  is weaker than reconstruction after the medium itself changes.
- **Copied worlds nearly match the ecology:** 35,262 versus 35,322 shows that
  the held-out distribution is too close to its seeded training distribution
  to establish open-ended novelty.

## Remaining human residue

The human-owned layer is load-bearing: raw cells are fixed objects; the host
chooses their extent and read/write grouping; it creates every full-state
candidate; it defines the private-world generator and the resource collision;
and it determines when comparisons occur. Thus, this test has no named task
API but still contains a hidden task family and proposal grammar. The organism
adapts inside a constructed ecology; it does not construct the ecology's own
physics or its challenge language.

AD2 therefore does not release AD4. A later test must make executable extent,
proposal construction, experimentation schedule, and interaction encoding
organism-created competitors inside a lower-level medium, then prove retained
function after independent address, value, segmentation, and instruction
identity changes. It must also use genuinely independent withheld worlds, not
minor resampling of a single seeded generator.

## Reproduce

```bash
mkdir -p /tmp/zig-cache-ad2 /tmp/zig-global-ad2
zig build-exe sparse_poly_discovery/open_ended_ecology_round_ad.zig \
  -femit-bin=/tmp/open_ended_ecology_round_ad \
  --cache-dir /tmp/zig-cache-ad2 --global-cache-dir /tmp/zig-global-ad2
/tmp/open_ended_ecology_round_ad selftest
/tmp/open_ended_ecology_round_ad run results/open_ended_ecology_round_ad.csv
```

Expected self-test:

```text
round_ad_ad2 selftest PASS verdict=VALID_NEGATIVE deterministic=true bounded_ecology=true open_ended=false
```

Artifacts:

- `sparse_poly_discovery/open_ended_ecology_round_ad.zig`
- `results/open_ended_ecology_round_ad.csv`
- `docs/research/open_ended_ecology_round_ad.md`
