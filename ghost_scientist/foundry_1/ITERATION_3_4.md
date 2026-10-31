# Foundry-3.4 rejected reduced-ISAMORE route

The obvious shortcut to control four has been investigated and rejected.

Five additional core files at the pinned ISAMORE commit were identified through
their exact Git blob identities: `lib.rs`, `main.rs`, `runner.rs`,
`egg_lang.rs`, and `experiment.rs`. This is identity evidence, not a local
source checkout; the full bytes and recursive submodule commit identities are
not frozen locally.

Targeted inspection of the exact runner shows the defining coupling:

1. `run` performs pruning;
2. it invokes Babble-backed library selection;
3. it forms a Pareto frontier over area and cycles;
4. it records learned-library reuse, speedup, and per-function effects.

A reduced build that removes Babble-backed discovery or hardware-aware scoring
would no longer reproduce ISAMORE. Running Babble or Enumo alone would merely
repeat controls already counted. A locally invented mock or replayed output is
therefore forbidden.

The evidence-backed result is
`ISAMORE_REDUCED_ROUTE_REJECTED`. Source-faithful external-control conformance
remains `3/4`. Since this route cannot progress without recoverable recursive
source, the next independently actionable remediation targets `P2`:
heterogeneous candidate reuse breadth.

**Verdict:** `FOUNDRY_V6_NOT_READY`
