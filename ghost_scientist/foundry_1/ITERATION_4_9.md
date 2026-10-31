# Foundry-4.9 A5 structural-control integration

A5 is now a production-integrated calibration structural control.

Byte-exact upstream Stitch ran over two independently encoded versions of all
23 complete calibration graphs. It learned one arity-three abstraction used
329 times and reduced its encoding cost from 452,962 to 386,504.

The independent semantics audit materially narrows that result: the abstraction
is exactly the call/sequence scaffold for calls with empty keyword dictionaries.
All 329 empty-kwargs calls are abstracted; all eight non-empty-kwargs calls are
not. It is not a new tensor primitive, a multi-operator runtime tool, or an
efficiency result.

All 23 rewrites reconstruct byte-identically after independently specified
Stitch normalization. Raw encoder bytes are intentionally unequal for all 23
because the encoder writes nullary `(dict )` applications and Stitch emits the
normalized atom `dict`. Separately, eager and exported framework graphs agree
across 69 executions with zero error. No rewritten Stitch program was executed
as a tensor runtime.

All 23 strict v1 contract pairs pass primary and independent verification. One
canonical process receipt and one global candidate-generation CPU charge are
counted once. Both batch verifiers reject 19 hostile mutations. The full path
passes process-tree metering.

Integrated truth advances from `5/10` to `6/10`. P1 and P3 remain incomplete,
and validation-v6 remains unread and unexecuted.

**Verdict:** `FOUNDRY_V6_NOT_READY`  
**A5:** production-integrated calibration structural control  
**Required arms integrated:** `6/10`
