# Foundry-0 goal closure

**Closed:** 2026-07-30  
**Verdict:** `FOUNDRY_0_GO_NARROWED`  
**Prospective v6 trial authorized:** no

## Outcome

The broad proposal did not survive the novelty audit. Library learning,
automatic rewrite inference, reusable equality-saturation strategies,
LLM-free e-graph anti-unification, semantics-aware reusable hardware
instruction discovery, and real tensor-compiler optimization all have close
prior art.

A narrower empirical question survived:

> Can an LLM-free system induce verified typed tensor tools whose complete
> charged discovery cost is repaid by behaviorally demonstrated reuse on
> post-freeze heterogeneous real-compiler workloads against compute-matched
> controls?

The surviving contribution is the causal prospective evaluation and tool
economics, not a first-of-kind construction algorithm. A future PASS would
require direct frozen-tool reuse receipts, tool-removal interventions,
native-compiler deduplication, independent recomputation, and a net total-cost
advantage against all critical arms.

## Evidence produced

- `SOURCE_LEDGER.tsv`: 17 external primary sources and 8 local evidence
  records.
- `FOUNDRY_0_DOSSIER.md`: claim collision matrix, bounded novelty decision,
  surviving estimand, and disallowed claims.
- `FALSIFICATION_PROTOCOL.md`: 11 experimental arms, 12 validity gates, and
  12 scientific gates.
- `decision.json`: machine-readable claim and authorization boundary.
- `verify_foundry_0.py`: stdlib-only documentary integrity audit.

## Verification

Executed from the repository root on 2026-07-30:

```text
FOUNDRY_0_VERIFY_PASS sources=25 external=17 local=8 arms=11 validity_gates=12 research_gates=12
GHOST_OPERATOR_FREEZE_VERIFY_V5 PASS records=133 freeze_sha256=0a1e478ae1c6e5fd096b7bb2f578a0aa924b4ffc10cbd64d55f911b4a70e93d9
GHOST_OPERATOR_FREEZE_VERIFY_V5_1 PASS records=22 freeze_sha256=cd24e8337eb81a227057e9fe5205806e03d9f8a855f82d4d6f87752e83f38e0d
GHOST_OPERATOR_INDEPENDENT_RECOMPUTE_V5_1 PASS gates=18_of_18 candidate=1.002005 fixed=1.021641 replay=1.004062 oracle_regret=1.000677 output_sha256=5bccf8a740fc4da8f3a838e52486aae75c40a95b92b1d29afe8c1e7984599d42
```

`git diff --check` also passed.

## Authorization boundary

Foundry-0 authorizes preparation of a development pilot only after
prerequisites `P1` through `P6` have evidence. It does not authorize the
prospective v6 trial, because the external controls, independent corpus and
invocation trace, complete resource meter, independent typed-tool verifier,
native-compiler deduplication audit, and final hash-frozen protocol do not yet
exist.

This is a completed research decision, not a v6 experimental result.
