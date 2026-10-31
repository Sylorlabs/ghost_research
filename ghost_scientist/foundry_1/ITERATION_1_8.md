# Foundry-1.8 external application and reachability iteration

The external intake was frozen before execution at
`pytorch/examples@acc295dc7b90714f1bf47f06004fc19a7fe235c4`.
It contains no Transformer or attention workload.

Four upstream application families executed:

1. MNIST image classification;
2. variational autoencoding;
3. recurrent time-series prediction; and
4. image super-resolution.

All four produced non-empty operator-level runtime traces and complete
`torch.export` graphs. Together they yielded 429 recorded operator invocations.
The model definitions are upstream-authored; the small input shapes are
harness-selected. These are real execution traces, not deployment demand logs.

## Reachability result

An adapter compared the necessary source-operation multisets of all four frozen
tools against all four exported application graphs. Across 16 pairs, zero were
coarsely reachable. Because multiset coverage is only a necessary condition,
zero coverage is sufficient to reject exact reachability; positive coverage
would not have been sufficient to accept it.

This is a useful negative:

- the external corpus and trace pipeline now exist;
- the applications are genuinely heterogeneous;
- the frozen tensor tools do not apply to them; and
- therefore this corpus cannot support a causal tool-reuse trial.

## Remediation

This intake is now calibration-only. The next phase must either:

- construct ATen-domain tools from these external graphs and reserve a new
  upstream application set; or
- freeze a new external intake, before execution, whose semantics overlap the
  already frozen tools.

Relabeling zero reachability as a `P2` pass is forbidden.

**Verdict:** `FOUNDRY_V6_NOT_READY`
