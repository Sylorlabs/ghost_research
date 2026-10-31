# Foundry-4.2 evaluator-owned arm contract

All ten required arms now have one frozen transport and accounting boundary.
This is a contract milestone, not arm integration.

The input binds an exact artifact identity, source and graph digests, identical
wall/CPU/RSS/search ceilings, the frozen three-execution schedule, and sealed
candidate, fixed-portfolio, and protocol digests. The output binds state
before and after the artifact, direct tool-use receipts, six separately
charged CPU components, three correctness receipts, alias/storage checks,
process-tree resources, provenance, and an explicit fail-closed status.

Two separately implemented strict verifiers accept the canonical A3 fixture
and reject all nine hostile mutations: unknown arm, injected field, negative
cost, inconsistent cost sum, wrong invocation count, incorrect PASS,
cross-artifact A3 state, artifact-identity mismatch, and prematurely mounted
heldout outcomes. The complete conformance path passes process-tree accounting.

The contract does not make a missing implementation real. A0 and A2 remain the
only production-integrated arms. A3 and A9 have calibration kernels but no
contract adapter. A5 and A7 are adapted external controls but not prospective
adapters. A6 and A8 remain incomplete and must fail closed.

**Verdict:** `FOUNDRY_V6_NOT_READY`  
**Prerequisites:** `4/6`  
**Required arms integrated:** `2/10`  
**P3:** incomplete
