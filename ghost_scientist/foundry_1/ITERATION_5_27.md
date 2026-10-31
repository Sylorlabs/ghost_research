# Foundry readiness iteration 5.27

The initial A1 reachability result contained three directional false positives.

The initial audit correctly found six exact constructor histograms, but its
dense-matrix semantic check accepted the first multiplication as either
operand of the second. Direct inspection showed all three dense candidates
were shaped as:

```text
Adj @ (X @ W)
```

The frozen v5.1 constructor instead recognizes the left-associated form:

```text
(X @ B) @ C
```

Those are not interchangeable through the constructor's reassociation. The
initial result and readiness iteration 5.26 remain preserved as diagnostic
history.

A disclosed post-diagnostic amendment froze the exact operand direction before
the corrected run. It is explicitly not pristine preregistration. The complete
surface, enumeration, six histograms, resource limits, and validation seal did
not change.

The corrected result still enumerates 7,093 connected mapped subgraphs and six
histogram candidates. Three right-nested dense candidates are now rejected.
Three conv-to-inference-batch-normalization folds in one real calibration graph
remain valid because each convolution is exactly argument zero of its
inference batch-normalization call.

The next A1 implementation target is therefore only
`fold_conv_batch_norm`. This is still reachability rather than typed lowering,
constructor execution, numerical equivalence, conformance, or integration.
The production matrix remains `7/10`, validation-v6 stays sealed, and the
prospective trial remains unauthorized.
