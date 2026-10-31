# Foundry-4.0 external production-demand horizon

Foundry now has a pinned, independently observed production-demand reference
instead of an internally generated invocation count. The selected Alibaba
GenAI trace contains 26,823 Stable Diffusion serving requests across 86
nonempty anonymized base-model identities.

The estimator was frozen before the successful aggregation: count `SUCCEED`
rows for every nonempty model identity, retain zero-success identities, and
take the nearest-rank lower quartile. The first execution failed because the
intake used documentation-level field names instead of the CSV's actual
`gmt_create` and `predict_status` names. That failure is preserved. A
source-documented schema-only amendment changed no population, filter, or
quantile rule.

The corrected result is `N*=3`. A second immutable-blob fetch and independently
written CSV parser reproduced all 12 exact relations: row and status counts,
model populations, seven successful-request order statistics, and `N*`.

At `N=3`, the pre-frozen calibration cost equation gives 4,862 abstract units
for the candidate versus 7,848 for the strong fixed portfolio. The candidate
remains cheaper even at `N=1` under that equation. This is a useful
falsification result: the external horizon is small, but not so small that the
candidate's calibration construction cost erases its search-accounting
advantage.

This is not a held-out win. Exact trace bytes are pinned by immutable Git blob
but are not locally frozen for offline replay, and Stable Diffusion per-model
demand has not been prospectively mapped to Foundry per-artifact reuse.
Calibration accounting is not wall time, dollars, or runtime novelty. P2
therefore remains false and validation-v6 remains sealed.

**Verdict:** `FOUNDRY_V6_NOT_READY`
