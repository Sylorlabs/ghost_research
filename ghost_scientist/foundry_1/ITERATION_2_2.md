# Foundry-2.2 evidence-constrained polymorphic result

Ghost repaired the specific type-abstraction failure from iteration 2.1, but
did not cross the heterogeneous-reuse boundary.

Before forging, a new four-family validation corpus, its runtime, the
polymorphic inference rule, evaluator, fixed portfolio, native audit, resource
limits, and pass gates were hash-frozen. The forge could inspect calibration
evidence but not validation-v4. It used zero LLM calls and zero manual type
widenings.

The inference rule generalized a tensor signature only when calibration
observed the ATen target at the same argument, keyword, or output position. A
boundary input reused at multiple positions had to satisfy the intersection of
those observations. This produced five generalized input constraints and no
unsupported output generalizations.

## Prospective result

All three tools replayed exactly, with zero numerical error, on the fresh dense
PyHealth graph-convolution family. Causal removal eliminated all three matches,
and the independent parser rejected six hostile mutations, including an
unobserved signature.

This moves semantic transfer from `0` to `3`, and proves that evidence-derived
layout polymorphism—not hand editing—fixed the sparse-to-dense mismatch.

It is still a valid negative:

- candidate matches appeared in only one of four families;
- candidate benefit was `7`, below the fixed portfolio's `14`;
- candidate cost was `110`, below the fixed portfolio's `235`, but that is not
  a cheaper equivalent result because benefit was lower; and
- the candidate failed both the two-family breadth gate and the
  candidate-benefit-at-least-fixed gate.

Native compilation completed for all three candidate and stock-decomposition
arms. Each pair produced identical normalized TorchInductor code, and every
tool was already an exact stock ATen decomposition. All three were rejected as
runtime inventions and zero were admitted.

The forge, evaluator, and native audit all passed process-tree accounting.

## Scientific consequence

The narrow layout-overfit diagnosis was correct, but fixing it exposed the next
limit: the calibration library contains several variants of one semantic motif
rather than a heterogeneous portfolio. Running more graph-convolution
validation would inflate counts without testing broader discovery.

The next phase therefore closes the independent-control prerequisite. It must
execute pinned public control systems against paper-derived conformance
fixtures, under the same resource meter, without substituting a locally
invented approximation. Only then should a diversity-seeking forge receive
another newly reserved prospective corpus.

**Verdict:** `FOUNDRY_V6_NOT_READY`
