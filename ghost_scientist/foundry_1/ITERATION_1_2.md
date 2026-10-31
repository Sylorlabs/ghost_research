# Foundry-1.2 external-corpus intake iteration

This iteration attacks the corpus half of `P2` without pretending that
installed local research artifacts are external workloads.

It inventories the official PyTorch Export DB shipped in the installed
PyTorch wheel, binds the wheel `RECORD`, license, version, every example
source, and every exported graph by SHA-256, and attempts a fresh
`torch.export.export` for every upstream-supported case.

The resulting graphs are independently authored upstream compiler-conformance
material. They improve the provenance boundary, but they are not four
application workload families and carry no independently observed invocation
trace. `P2` therefore remains incomplete.

Run:

```bash
python3 -B ghost_scientist/foundry_1/phase6_external_corpus.py
python3 -B ghost_scientist/foundry_1/recompute_iteration_1_2.py
```

