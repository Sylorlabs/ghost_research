# Foundry readiness iteration 5.34

Local experimentation continued past the missing external validation bundle.
It did not access validation-v6 or validation-v7 and does not change
prospective authorization.

Phase160 replaced the old chain-only search with exhaustive connected induced
DAG enumeration over the 23 authenticated local graphs. Two independent
enumerators agreed on 375 training and 1,539 heldout connected subsets. The
machine selected 27 topology productions, including three non-chain and three
multi-output forms, then constructed nine exact tools. Those tools matched nine
heldout motifs but reached no node beyond the exact-chain and supplied-fixed
controls. This is a valid negative for exact-body grammar emergence.

Phase161 tested whether exact operator identity was hiding a more general
grammar. Typed anti-unification selected one two-node, two-output template from
five training occurrences across polynomial regression and variational
autoencoding. Both operator slots and both argument-recipe slots became holes;
the only learned typed constraint was equality of the two node-output types.
On the unchanged heldout split it bound `relu -> pad` in style transfer and
`relu -> mul` in robust graph convolution. Both instantiated bodies reproduced
byte-identically, covering three nodes outside the exact, chain, and fixed
controls. Two independent implementations agreed and rejected all 16 hostile
cases twice.

That positive is deliberately narrow. Phase162 froze and ran the missing null
control: remove only the learned type equality while preserving the selected
topology and output boundary. The candidate matched two heldout motifs and the
topology-only ablation matched the same two. The type constraint rejected zero
motifs and added `0.0` bits of heldout information. A node-count/output-boundary
ablation matched 17 motifs, while the single most frequent training topology
matched 19. The two bound operator pairs were unseen in training, but the holes
merely accepted those existing operations; they did not predict or construct
their semantics.

The scientific result is therefore:

- connected non-chain topology construction is real;
- exact learned tools did not beat the controls on heldout reachability;
- a parameterized topology transferred across families;
- its typed constraint added no heldout information beyond topology;
- no concrete reusable tool, cheaper execution, new operation semantics, or
  runtime primitive has been demonstrated.

Foundry remains `FOUNDRY_V6_NOT_READY` at `5/6` prerequisites, with all ten
arms integrated, V08 pending, no real sponsor trust root, validation-v7 bundle
`0/5`, provenance `0/13`, and no prospective execution.
