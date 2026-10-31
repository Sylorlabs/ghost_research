# Round AM / AM4 — relevance-enabled experiment recovery

**Verdict: FOUNDATION POSITIVE, bounded synthetic evidence.** The complete
candidate chain—earned intervention topology, evidence-bound value, and a
reuse-versus-explore arbitration—selects a next generic experiment that earns
**3,600** hidden material across 120 unseen cohorts. It strictly beats every
equal-cost listed control after private recoding and a changed causal law. This
does not establish open-ended invention, semantic understanding, operating
system containment, or autonomy outside this sealed fixture.

## Question and pre-registration

AM2 showed that a response-derived dependency topology can select relevant
history after a hidden shift. AM4 asks the next operational question: can that
earned relevance be used to spend the next experiment budget better than AJ4's
fixed allocator, random/replay/shuffled history, blank state, ablations, and
strong generic coverage?

There are 120 sealed cohorts. Before evaluation, every arm spends exactly 16
raw contacts per cohort: twelve generic intervention-to-later-change contacts
to earn three anonymous records, then four contacts for its next experiment.
The evaluator's material is unavailable until all charged contacts are done.
Each cohort privately permutes record ownership and changes the raw outcome
law/recoding between experience and the held-out query. Only a dependency
*count* is conserved.

The candidate record contains only a raw generic-action position, a dependency
count observed from its own interventions, a four-contact evidence count, and
an append-only digest. It does not hold a target, label, identity, world key,
semantic decoder, answer trace, task menu, static matcher/vector, supplied
graph/motif/schedule/router, score, uncertainty, evaluator feedback, or
retained answer memory.

The chain is explicit:

1. It earns three local dependency records from uniform raw probes.
2. It selects a record whose earned topology matches the held-out response
   topology.
3. Only a fully evidenced, provenance-bearing record authorizes **reuse** of
   its raw generic action; otherwise it **explores** a generic fallback.

The policy never receives the hidden material total. Evaluation occurs only
after the final action decision.

## Equal-cost results

All rows charge **1,920 contacts** (120 × 16). `Material` is post-contact
evaluator-only material. The candidate's 120 commits are a source-visible
provenance condition (complete evidence plus nonzero digest), not evaluator
feedback.

| Policy | Contacts | Hidden material | Commits | Reuse authorizations |
|---|---:|---:|---:|---:|
| earned topology → value → arbitration | 1,920 | **3,600** | **120** | **120** |
| AJ4 fixed allocator | 1,920 | 1,380 | 0 | 0 |
| random | 1,920 | 1,290 | 0 | 0 |
| replay | 1,920 | 1,410 | 0 | 120 |
| shuffled history | 1,920 | 840 | 0 | 120 |
| blank/no relevance | 1,920 | 1,320 | 0 | 0 |
| answer-memory scrubbed | 1,920 | 1,320 | 0 | 0 |
| topology/relevance ablation | 1,920 | 1,320 | 0 | 0 |
| value authorization ablation | 1,920 | 990 | 0 | 0 |
| arbitration ablation | 1,920 | 1,230 | 0 | 0 |
| fixed generic broad coverage | 1,920 | 1,660 | 0 | 0 |

The fixed broad-coverage comparator receives the same final four-contact
budget but splits it over generic anonymous actions rather than concentrating
it via an earned relation. It is the strongest control (1,660), and the chain
still wins by 1,940. The chain also strictly beats the prior AJ4 fixed
allocator by 2,220. No control ties.

## Integrity and audit boundary

- **Answer scrub:** the answer-memory arm has no interpretable trace and falls
  to 1,320. Candidate records contain no answer material.
- **Causal use:** removing topology drops to 1,320; retaining topology while
  removing value authorization drops to 990; removing the reuse/explore rule
  drops to 1,230. The result requires the entire chain, not merely a stored
  raw action.
- **History controls:** replay (1,410) and shuffled history (840) retain the
  same amount of evidence but break cohort-local provenance/relevance.
- **World separation:** experience and evaluation use private recoding, a
  changed causal law, and distinct world nonces. The candidate uses only the
  invariant dependency count.
- **AM3 compatibility:** the declared record is response-only, append-only
  intervention-transition provenance. It is compatible with AM3's
  conditional-accept manifest rule. That is a source-surface gate, not proof
  against unobserved runtime leakage or hostile containment escape.

## Reproduce

```bash
mkdir -p /tmp/zig-am4-cache /tmp/zig-am4-global
zig build-exe sparse_poly_discovery/relevance_recovery_round_am.zig \
  -femit-bin=/tmp/relevance-recovery-am4 \
  --cache-dir /tmp/zig-am4-cache --global-cache-dir /tmp/zig-am4-global
/tmp/relevance-recovery-am4 selftest
/tmp/relevance-recovery-am4 run results/relevance_recovery_round_am.csv
```

Expected self-test output:

```text
round_am_am4 selftest PASS verdict=FOUNDATION_POSITIVE deterministic=true contacts_per_cohort=16 all_controls_strictly_beaten=true answer_scrubbed=true manifest=conditional_only
```

The complete generated ledger is
[`results/relevance_recovery_round_am.csv`](../../results/relevance_recovery_round_am.csv).
