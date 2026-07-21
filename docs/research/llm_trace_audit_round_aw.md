# LLM trace audit of AW/AV claims

**Role:** read-only audit. It does not solve sealed tasks or supply answers.

## Verdict

**Correct scalar outputs are not causal evidence by themselves.** AV has narrow
evidence that a real native-Zag program read source and repaired its comment
handling. AW's apparent 4/4 was a confirmed coincidence because its evaluator
accepted only a token and integer. Output hashes prove execution, not that the
tool measured the requested property.

## Concrete trace classifications

| # | Trace / claim | Classification | Evidence |
|---|---|---|---|
| 1 | AV raw scanner, training output 26, rejected | **Causal evidence present for the wrong measurement** | The program literally counts each `pub fn ` byte sequence ([source:2-15](../../sparse_poly_discovery/round_av_raw_scanner.zag#L2-L15)); its receipt is 26/incorrect ([CSV:2](../../results/real_local_inventor_trial_round_av_zag.csv#L2)). It read/counts bytes, but not non-comment declarations. |
| 2 | AV repaired scanner, training output 10, accepted | **Causal evidence present, narrow** | The code explicitly enters/exits line comments before counting ([source:10-21](../../sparse_poly_discovery/round_av_comment_scanner.zag#L10-L21)); receipt says no answer literal and correct ([CSV:3](../../results/real_local_inventor_trial_round_av_zag.csv#L3)). The prior failure reduces one-shot guessing risk. No per-location witness exists. |
| 3 | AV repaired scanner, held-out output 3 | **Causal evidence present, narrow** | Same repaired binary transfers to a separate copied artifact, no answer visible to worker, no answer literal ([CSV:4](../../results/real_local_inventor_trial_round_av_zag.csv#L4)); Bubblewrap mounts only analyzer/corpus/runtime ([launcher:9-21](../../scripts/run_round_av_zag.sh#L9-L21)). |
| 4 | AV fixed comment scanner, held-out output 3 | **Causal evidence present; no learned advantage** | Fixed policy uses the same repaired binary and ties ([CSV:5](../../results/real_local_inventor_trial_round_av_zag.csv#L5)). This proves scanner operation, not invention advantage. |
| 5 | AV fixed raw scanner, held-out output 3 | **Coincidence risk** | A scanner proven wrong on train still gets a correct held-out scalar ([CSV:2](../../results/real_local_inventor_trial_round_av_zag.csv#L2), [CSV:6](../../results/real_local_inventor_trial_round_av_zag.csv#L6)). Exact warning: correct number can come from wrong tool. |
| 6 | AW1 answer-free method memory | **Causal evidence present for firewall only** | It stores general lessons and explicitly excludes task IDs, expected outputs, paths, hashes, source, and scores ([AW1:16-28](../../sparse_poly_discovery/method_memory_firewall_round_aw.zig#L16-L28), [41-50](../../sparse_poly_discovery/method_memory_firewall_round_aw.zig#L41-L50)). It proves no new-task measurement. |
| 7 | AW2 sealed staging boundary | **Causal evidence present for staging only** | Expected values remain evaluator-side while candidate gets payload/contract/token ([AW2:61-86](../../sparse_poly_discovery/sealed_multitask_corpus_round_aw.zig#L61-L86)); hostile path/answer/score requests reject ([AW2:90-95](../../sparse_poly_discovery/sealed_multitask_corpus_round_aw.zig#L90-L95)). Actual separate mounting remains an operational requirement. |
| 8 | AW3 candidate receipts | **Insufficient** | Receipts have hashes but say `scored=false` and `evaluator_score_absent` ([AW3 CSV:2-5](../../results/zag_toolforge_competitor_round_aw.csv#L2-L5)); runner likewise emits no score ([AW3:99-125](../../sparse_poly_discovery/zag_toolforge_competitor_round_aw.zig#L99-L125)). |
| 9 | AW3 repair after mismatch | **Insufficient / supplied-rule risk** | Candidate switches to comment scanner on `mismatch`, while fixed/broad are already given it ([AW3:62-71](../../sparse_poly_discovery/zag_toolforge_competitor_round_aw.zig#L62-L71)). That is supplied behavior, not autonomous diagnosis. |
| 10 | AW2 source-structure scalar claim | **Coincidence risk** | Contract asks for non-comment declarations ([AW2:14-19](../../sparse_poly_discovery/sealed_multitask_corpus_round_aw.zig#L14-L19)), but claim parser accepts only token plus unsigned number and evaluator checks only equality ([AW2:97-118](../../sparse_poly_discovery/sealed_multitask_corpus_round_aw.zig#L97-L118)). |
| 11 | AW2 CSV-integrity scalar claim | **Coincidence risk** | Contract requires malformed CSV-width parsing ([AW2:16](../../sparse_poly_discovery/sealed_multitask_corpus_round_aw.zig#L16)), but same scalar-only evaluator accepts it ([AW2:97-118](../../sparse_poly_discovery/sealed_multitask_corpus_round_aw.zig#L97-L118)). A declaration scanner cannot prove CSV parsing by matching a number. |
| 12 | AW2 performance-proxy scalar claim | **Coincidence risk** | Task requires sleep-within-loop analysis ([AW2:17](../../sparse_poly_discovery/sealed_multitask_corpus_round_aw.zig#L17)); evaluator asks for no sleep/loop locations ([AW2:97-118](../../sparse_poly_discovery/sealed_multitask_corpus_round_aw.zig#L97-L118)). |
| 13 | AW2 behavior-property scalar claim | **Coincidence risk** | Task requires `MissingArg` branches ([AW2:18](../../sparse_poly_discovery/sealed_multitask_corpus_round_aw.zig#L18)); evaluator checks only scalar equality ([AW2:97-118](../../sparse_poly_discovery/sealed_multitask_corpus_round_aw.zig#L97-L118)). |
| 14 | AW integration apparent 4/4 | **Coincidence confirmed; invalid** | The integration record identifies `3, 0, 1, 1` and says it did not run the other three analyses; all policies tied ([integration:5-16](round_aw_integration_attempt.md#L5-L16)). |

## Required trace/witness gate

Use a precommitted typed envelope, not a bare number:

```text
CLAIM-V1 <task-token> <task-kind> <tool-source-hash> <payload-hash>
WITNESS <task-specific records>
SUMMARY <derived-count>
```

The evaluator must derive `SUMMARY` from the witness and sealed payload, reject
wrong task kinds, duplicate/out-of-range offsets, byte-mismatched constructs,
and invalid source/payload hashes. It must require:

- source task: declaration offsets/lines plus evidence each is outside comments;
- CSV task: malformed row indices plus observed/header field counts;
- performance task: sleep offsets plus enclosing loop spans;
- behavior task: `MissingArg` offsets plus branch spans.

Run counterfactual mutations after sealing: changing a witnessed construct must
change the tool's witness/count; changing unrelated bytes must not. Use at least
one held-out recoding. Candidate never sees witness acceptance until all claims
are submitted. An LLM critic may propose attacks on a finished trace, but the
deterministic evaluator validates the witness.

## Recommendation

Do not rerun AW with better prose or an LLM as judge. Implement the typed
witness gate, then rerun the same families under equal budgets. The current
single source scanner should pass only source structure and fail the other
families honestly; those failures are the real starting point for tool forging.
