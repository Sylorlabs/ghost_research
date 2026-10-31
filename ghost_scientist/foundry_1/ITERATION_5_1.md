# Foundry-5.1 complete required-arm resource accounting

P3 is now complete in its stated resource-accounting sense.

A1, A6, A7, and A8 each have an authenticated `REQUIRED_UNSUPPORTED`
outcome for every one of the common 23 calibration graphs. The resulting 92
strict adapter pairs pass both base-contract verifiers. Every output has empty
tool and invocation receipts, false numerical and alias claims, unchanged
unretained empty state, and no validation outcome mounted.

One complete matrix-audit process receipt is referenced by all 92 outputs and
charged once. Its measured user-plus-system CPU is reconciled exactly across
four leading bindings, one per arm. Two batch verifiers reject 25 hostile
mutations, including unsupported-to-PASS relabeling, evidence substitution,
missing or duplicated CPU, resource multiplication, and integration inflation.
Batch assembly and hostile conformance also pass process-tree metering.

This is resource completeness, not control success. No new arm becomes
conformant or production-integrated. The matrix remains `6/10`.

Foundry prerequisites advance from `4/6` to `5/6`. P1 still lacks a fourth
independently implemented source-faithful control. The native-dedup stop also
remains active, so validation-v6 stays sealed.

**Verdict:** `FOUNDRY_V6_NOT_READY`  
**P3:** complete  
**Required arms integrated:** `6/10`
