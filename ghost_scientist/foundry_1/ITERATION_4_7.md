# Foundry-4.7 A1 IR compatibility falsification

A1 cannot be production-integrated by a direct wrapper.

The frozen Operator-v5.1 constructor is real, but it operates on its own
strict typed whole-program IR. Two independent source analyses agree that the
runtime evaluator supports 22 operations. Against the complete 23-graph
calibration surface, only 9 of 41 observed ATen targets are direct exact
mappings.

Those mappings cover 143 of 337 calls. Another 114 calls need argument- or
adjacency-sensitive composite proofs, and 80 calls are unsupported by the
frozen IR. Four graphs are wholly direct, but none has the exact runtime
histogram of a non-reference frozen A1 constructor pattern.

The compatibility negative and all 23 graph records pass process-tree
metering. A1 therefore remains `COMPATIBILITY_AUDITED_NOT_ADAPTED`; integrated
truth stays `4/10`. The required next implementation is an evaluator-owned
ATen-to-Operator-v5 typed lowering bridge with explicit unsupported outcomes,
not a generic reference-execution wrapper.

No validation-v6 source, graph, runtime, or outcome was accessed.

**Verdict:** `FOUNDRY_V6_NOT_READY`  
**A1 direct adapter:** rejected  
**Required arms integrated:** `4/10`
