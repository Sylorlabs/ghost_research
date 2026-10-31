# Foundry-3.9 no-library and per-instance control kernels

Two required controls now execute on the 23-graph calibration corpus from an
empty state for every graph:

- A3 discovers only locally recurring positive-MDL tools and discards them
  after the graph;
- A9 greedily spends search directly on each graph and retains no library.

Both use the same typed path/body enumerator as A2 and enumerate the same 581
paths. Because they cannot retain a global body table, they reconstruct 388
per-graph groups versus A2's 339 globally deduplicated groups. The resulting
49-unit rediscovery overhead is preserved rather than normalized away.

Under identical search construction counts and process-tree ceilings, A3
covers 126 unique calibration nodes while A9 covers 226. Both runs terminate
naturally, charge CPU, sample process-group RSS, and reap their groups. The
result demonstrates working negative-control mechanics and reveals that a
strong per-instance search can cover substantially more of calibration than
the no-library MDL rule.

These kernels are calibration-only. They are not yet sealed behind the
prospective arm interface, so A3/A9 production integration and P3 remain
incomplete. Validation-v6 remains sealed.

**Verdict:** `FOUNDRY_V6_NOT_READY`
