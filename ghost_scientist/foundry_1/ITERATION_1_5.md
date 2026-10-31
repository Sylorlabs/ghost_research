# Foundry-1.5 future-tool native-admission iteration

This iteration converts the v5.1 compiler audit into a fail-closed admission
policy:

- exact pre-lowering or normalized compiler-code duplicates are rejected;
- compiler-required-unsupported and merely nonidentical cases are quarantined;
- derived-parameter construction alone is not evidence of novelty; and
- byte-identical runtime code can be reconsidered only with an independent,
  frozen receipt proving a bounded search-cost distinction.

Applied retrospectively, the policy admits no v5.1 plan into a future Foundry
library. That does not retract v5.1's optimization result. It prevents that
result from being reused as stronger native-distinction evidence than it
contains.

