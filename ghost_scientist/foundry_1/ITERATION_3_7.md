# Foundry-3.7 failure-mechanism calibration

The prospective v5 result is immutable and has been reclassified as
calibration-only for future work. A separately metered diagnostic identifies
four failed gates and a specific mechanism:

- the machine portfolio covered two fewer unique nodes than the fixed one;
- the largest deficit was the convolutional classifier (`5` versus `9`);
- the novelty-only constraint discarded five recurring motifs that the
  machine had rediscovered because their target sequences matched fixed forms;
- two of three executable tools transferred, but the recurrent language
  workload was unreachable by both portfolios;
- excluding its one-time calibration search, candidate matching cost `114`
  versus fixed cost `244`;
- the one-time search cost would amortize by a second equal cohort, but repeated
  cohorts do not repair the coverage deficit.

The next forge is therefore not another hand-authored motif list. It must
machine-select a Pareto portfolio from all recurring typed motifs across the
now-calibration-only 23-graph corpus. Its objective must jointly score unique
coverage, repository/domain reach, definition cost, calibration search, node
visits, and edge checks. Novelty-only, all-motif, and Pareto-selected variants
must be ablated without weakening the unchanged fixed portfolio.

A new repository-disjoint validation intake must be frozen before that
portfolio is made executable.

**Verdict:** `FOUNDRY_V6_NOT_READY`
