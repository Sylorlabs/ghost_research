# Foundry-2.0 prospective ATen transfer result

This is the first ATen transfer/search-economics component whose source
snapshots, runtime constructors, inputs, seed, candidate digest, strong fixed
portfolio, ledger, gates, failure handling, and resource limits were all
frozen before scientific execution.

The first frozen wrapper failed at import before observing candidate outcomes.
An outcome-blind API-only remediation was separately frozen. That run then
proved the absent optional `torchvision` dependency stopped the workload list
before any model was constructed. A second separately frozen remediation
isolated workload construction, exactly as the original protocol's
`REQUIRED_UNSUPPORTED` policy intended; it did not change the candidate,
sources, shapes, seed, fixed baseline, ledger, gates, or limits.

## Prospective result

- Three of four families exported and executed.
- The Siamese family is explicit `REQUIRED_UNSUPPORTED` because `torchvision`
  is absent.
- One forged `linear -> relu` macro transferred to the recurrent image
  classifier and replayed with zero error.
- The candidate and fixed portfolios each matched once and covered two nodes.
- Candidate cost was 175 ledger units versus 235 for the larger fixed
  portfolio.
- Causal removal reduced candidate matches from one to zero.
- The process-tree resource receipt passed at about 1.39 GiB peak RSS.

The result fails the frozen minimum of two matched families and two distinct
matched tools. Equal benefit at lower search cost is promising bounded
evidence, but sparse one-family reach is not autonomous general tool reuse.

## Research consequence

More application collection alone is unlikely to solve the central problem.
The forge currently compresses recurring syntax; it does not construct new
semantic operations in response to unmet real workload demands.

The next phase should target demand-driven typed grammar extension: identify
repeated uncovered real graph fragments, construct executable semantic
candidates without an LLM, reject native/compiler duplicates, and test on a
new reserved corpus under the same fixed, causal, resource, and no-intervention
controls.

**Verdict:** `FOUNDRY_V6_NOT_READY`
