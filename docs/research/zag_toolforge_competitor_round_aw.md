# AW3 — Native Zag tool-forge competitor

**Status: INTEGRATION READY, UNSCORED.** This runner is candidate-side
infrastructure for the first serious multi-task milestone. It does not contain
a task corpus, expected output, score, evaluator, or success claim.

## What it actually does

An evaluator-owned manifest supplies only a task ID, two read-only artifact
paths, and an opaque prior receipt such as `raw_token_mismatch`. The receipt is
rejected if it contains answer-shaped fields (`answer`, `expected`, `score`,
`target`, `correct`, or `output=`). The candidate records three competing
frontier hypotheses, precommits each action/source hash before the worker runs,
and generates native **Zag** scratch analyzers. Its supplied candidate policy
uses a raw scanner first and chooses a comment-aware repair only after the
opaque mismatch receipt. This is explicitly a supplied rule/baseline, not a
claim of autonomous invention.

The Bubblewrap worker receives exactly one compiled analyzer and one read-only
artifact. It has no network, evaluator mount, expected output, score, writable
corpus, or inherited environment. The runner records only output hashes in its
ledger; it never interprets them as correct. A separate evaluator must seal and
score claims after the run.

Seven policies run under the same per-task budget: candidate, fixed, broad,
random, replay, no-memory, and no-repair. Every policy gets exactly two Zag
compilations and three sandbox worker actions: training, training, held-out.
This follows AU3's equal-budget discipline. No score is emitted, so this alone
cannot generate a positive result.

## Manifest contract

One CSV row per task, no header:

```text
task_id,train_artifact_path,heldout_artifact_path,opaque_prior_receipt
```

The evaluator must keep expected results, target predicates, scores, and final
verdicts outside this runner and outside every worker mount. The candidate sees
only the receipt hash and its own raw worker outputs.

## Fresh verification

```sh
zig build-exe sparse_poly_discovery/zag_toolforge_competitor_round_aw.zig -O ReleaseSafe -femit-bin=/tmp/aw3
/tmp/aw3 selftest
# With an evaluator-supplied sealed manifest:
/tmp/aw3 run /path/to/evaluator-owned-manifest.csv results/zag_toolforge_competitor_round_aw.csv
```

`selftest` uses two tracked local Zig files only as unscored smoke-test input,
emits two ledgers, and requires byte-identical replay. It fails if a scored
positive is emitted. It requires `bwrap` and the native compiler at
`/home/micah/Desktop/Sylorlabs/zag/zag-poc/znc`; override the latter with
`ZAG_COMPILER`.

## Limits

This does not yet meet the milestone. The candidate's repair rule and tool
family are supplied; it is not arbitrary program invention. The manifest is
not a sealed evaluator corpus. A real AW integration must connect AW1 method
principles and an AU1-style independent evaluator, provide several unrelated
sealed tasks, derive correctness from evaluator receipts, compare all seven
policies at equal budget, and then survive an adversarial reduction audit.
