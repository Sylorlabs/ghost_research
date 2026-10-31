# Foundry-5.0 A7 direct-compatibility rejection

A7 now has a complete, metered compatibility result: its direct adapter is
rejected.

The source-faithful Enumo control remains real and valid in its published
Boolean domain. That domain has five operators and explicit Boolean evaluation,
interval, variable, constant, and validation semantics. The complete framework
surface has 41 tensor operator targets across 337 calls. Exact direct overlap is
zero.

Making Enumo operate faithfully on the tensor graphs would require a new typed
operator language, tensor evaluator, shape/dtype/layout/alias model, variable
and constant policy, undefined-operation semantics, rewrite validation,
workload generator, and selection policy. Those are the scientific substance
of a new domain, not glue around an existing control. This phase froze that
boundary before graph inspection and forbade silently inventing those pieces.

The earlier pre-frozen Enumo metamorphic failure remains visible: workload
counts stayed fixed, but renaming and enumeration order changed the selected
rule set from 60 to 67 rules. The compatibility rejection and its process tree
both pass verification and accounting.

Integrated truth remains `6/10`. P1 and P3 remain incomplete, and validation-v6
remains unread and unexecuted.

**Verdict:** `FOUNDRY_V6_NOT_READY`  
**A7:** direct adapter rejected; new tensor domain required  
**Required arms integrated:** `6/10`
