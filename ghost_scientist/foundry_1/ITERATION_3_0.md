# Foundry-3.0 source-faithful Enumo Boolean control

Enumo now executes as the third independent source-faithful control.

The build stages exact upstream Enumo, Egg `v0.9.5`, and `symbol_table`
`v0.2.0` source. Forty-nine directly used files match their pinned Git blobs.
Generated build indexes and dependency substitutions are disclosed separately;
the pinned algorithm sources are not modified.

The exact Boolean learning algorithm and official test recipe produced workload
counts `93`, `348`, and `4599`. Its 60 learned directed rules derive all `43`
official expected directed rules, with zero misses. The complete build and
execution passed process-tree accounting with 12 observed processes.

This is a source-faithful core build, not the full official crate. The
bit-vector/Z3, logger, and command-line surfaces are excluded, so official
binary-artifact conformance remains `0/4`.

Source-faithful independent-control conformance is now `3/4`.

**Verdict:** `FOUNDRY_V6_NOT_READY`
