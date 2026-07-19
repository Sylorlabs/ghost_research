# Round AM / AM5 — higher-order causal portfolio transfer

**Verdict: FOUNDATION POSITIVE, bounded synthetic evidence.** A cohort-local portfolio of anonymous intervention-to-later-response records earns **5,760** hidden material across 96 sealed cohorts and 288 hidden regime queries. It strictly beats every equal-cost control, including AM4's single-record chain, broad coverage, fixed portfolio scheduling, replay/shuffling, ablations, and an explicit wrong-mechanism route. This does not establish open-ended invention, semantic understanding, or hostile runtime containment.

## Question and sealed setup

AM4 showed that one earned causal record can choose a better next experiment. AM5 tests whether the same basic machinery can retain and route a **portfolio** when every cohort contains three independently recoded hidden regimes. The evaluator privately permutes four raw action positions within every cohort/regime, selects from four distinct causal families, and changes the raw response law. The policy receives none of the family names, permutations, targets, or evaluation values. It receives only its generic intervention-to-later-response traces.

Each arm receives exactly 45 charged contacts per cohort: 36 uniform record contacts (four actions × three probes × three regimes), three raw query observations, and six final charged contacts. Evaluation material is withheld until the final action is selected. Cohort and regime nonces are disjoint and pre-registered in the deterministic fixture.

The candidate record holds only raw action position, a three-tick response trace, evidence count, and provenance digest. It uses an earned local trace relation to find a fully evidenced record, reuses that record's raw action, and otherwise takes a generic deterministic explore action. It stores no labels, IDs, targets, decoded family semantics, scores, uncertainty, evaluator feedback, task menu, answer trace, or retained answer. It has no supplied graph, static vector, fixed temporal motif, schedule, or task router.

## Equal-cost results

All policies charge **4,320 contacts** (96 × 45). Material is post-charge, evaluator-only output.

| Policy | Contacts | Hidden material | Exact routes | Reuse authorizations |
|---|---:|---:|---:|---:|
| earned local portfolio | 4,320 | **5,760** | **288** | **288** |
| AM4 single-record chain | 4,320 | 2,880 | 0 | 255 |
| fixed generic broad coverage | 4,320 | 1,400 | 0 | 0 |
| fixed portfolio schedule | 4,320 | 1,400 | 0 | 0 |
| random | 4,320 | 1,500 | 0 | 0 |
| replay | 4,320 | 1,160 | 0 | 245 |
| shuffled history | 4,320 | 1,420 | 0 | 237 |
| blank/no relevance | 4,320 | 1,340 | 0 | 0 |
| answer-memory scrubbed | 4,320 | 1,340 | 0 | 0 |
| topology/relevance ablation | 4,320 | 1,340 | 0 | 0 |
| value ablation | 4,320 | 1,540 | 0 | 0 |
| arbitration ablation | 4,320 | 1,540 | 0 | 0 |
| explicit mechanism misrouting | 4,320 | 0 | 0 | 288 |

The portfolio routes all 288 regime-local queries. The explicit misrouting control keeps the same local evidence and authorizes the same 288 reuses, but substitutes a different record and earns zero material. The positive therefore depends on routing the relation, not simply on retaining records or reusing raw actions. The AM4 single-record arm is allowed to reuse the first regime's record; its partial 2,880 outcome shows why regime-local portfolio maintenance is required under changing recodings.

## Audit boundary

The source-visible manifest is compatible with AM3's conditional, response-only append-only provenance rule. It checks that policy records use only raw action, trace, evidence, and provenance; rejects answer/task/evaluator fields and fixed matcher/router artifacts; and declares private recoding, law shift, and nonce separation. It is a source-surface audit, not operating-system sandboxing or proof against hostile runtime leakage. This is deterministic, synthetic, bounded transfer evidence—not general intelligence or unconstrained autonomy.

## Reproduce

```bash
mkdir -p /tmp/zig-am5-cache /tmp/zig-am5-global
zig build-exe sparse_poly_discovery/higher_order_portfolio_round_am.zig \\
  -femit-bin=/tmp/higher-order-portfolio-am5 \\
  --cache-dir /tmp/zig-am5-cache --global-cache-dir /tmp/zig-am5-global
/tmp/higher-order-portfolio-am5 selftest
/tmp/higher-order-portfolio-am5 run results/higher_order_portfolio_round_am.csv
```

Expected self-test:

```text
round_am_am5 selftest PASS verdict=FOUNDATION_POSITIVE deterministic=true contacts_per_cohort=45 all_controls_strictly_beaten=true routes=288 answer_scrubbed=true manifest=conditional_only
```
