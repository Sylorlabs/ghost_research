# Ghost Scientist Tensor v4 heldout result

## Verdict

`GHOST_TENSOR_TRIAL_V4_PASS`

The frozen conditional constructor crossed the predeclared restricted
boundary: on 24 post-freeze BART/Llama-derived computation-graph artifacts, it
beat both the original TorchInductor graph and the strongest fixed portfolio
in aggregate CPU latency without changing typed or numerical semantics.

This is a result about a restricted same-input projection language. It is not
evidence that Transformers are an efficient target architecture.

## Prospective evidence

- Pre-heldout freeze: 50 records, SHA-256
  `f7bca79a078555ba07e5b8f8a5792f720687dc8a1738aed61d52dc8bed35588c`.
- Heldout corpus: 24 artifacts generated after freeze, 12 BART and 12 Llama;
  manifest SHA-256
  `5d423d9229c541f4f54250eb97457a80e097a4b96efe8e7548c9eb1d6644dcd7`.
- Candidate replay: byte-identical 24/24.
- Independent verification: PASS 24/24; maximum verifier forward-error-bound
  ratio `0.011741`, and maximum compiled absolute error `4.7684e-7`.
- Containment: outer default-deny probe 5/5, final default-deny probe 6/6,
  distinct network namespace, read-only candidate-visible runtime with only
  one artifact and the grammar bound in.
- Genuine fixed e-graph: all five legal partitions saturated into one e-class
  to a fixpoint on every artifact.

The artifacts come from actual locally installed module source and
`torch.export` FX graphs. PyTorch FX is the graph representation surface and
`torch.compile(..., backend="inductor", fullgraph=True)` is the measured
compiler surface ([FX documentation](https://docs.pytorch.org/docs/stable/fx.html),
[`torch.compile` documentation](https://docs.pytorch.org/docs/stable/generated/torch.compile)).
The model instances are randomly initialized and evaluator weights are
deterministic, so this is not pretrained-model performance.

## Control results

| Method | Latency sum (us) | Compile sum (ms) | Logical GEMMs | Max peak RSS (KB) |
|---|---:|---:|---:|---:|
| Learned conditional candidate | 3589.753 | 65375.283 | 30 | 1320396 |
| Fixed equality saturation / no-probe / replay | 3603.001 | 53097.833 | 24 | 1320396 |
| Original compiler / no-memory | 4012.068 | 65991.125 | 72 | 1318080 |
| Deterministic random | 3824.264 | 65883.381 | 49 | 1320396 |
| Exhaustive five-plan oracle | 3557.447 | 65458.493 | 34 | 1320396 |

The candidate improved aggregate latency by:

- `0.3677%` over the best fixed portfolio, the genuine e-graph.
- `10.5261%` over the original three-projection TorchInductor graph.

It selected pack-all on 21 artifacts and separate projections on three tiny
artifacts. Against the best fixed plan artifact-by-artifact it recorded 2 wins,
21 ties, and 1 loss. It matched the exhaustive-selected plan on 17/24 and had
`0.9081%` aggregate regret versus that oracle.

The result is specifically a conditional correction to static kernel-count
extraction: always packing uses fewer logical GEMMs, but it is not always the
lowest-latency choice on tiny graphs. Equality-saturation baselines are
motivated by tensor-graph work such as
[TENSAT](https://arxiv.org/abs/2101.01332), while the development outcome
learner follows the broader semantic-rule-inference direction represented by
[Ruler](https://arxiv.org/abs/2108.10436). No algorithm-novelty claim is made.

## Negative results and limits

- Compile cost is worse than the fixed e-graph: `65.375 s` versus `53.098 s`
  summed over fresh processes/caches.
- Compile-plus-1,000-call cost is also worse: `68.965 s` versus `56.701 s`.
  Therefore this run does not show cheaper short-lived end-to-end deployment.
- Candidate max process peak RSS is not lower than the e-graph and is about
  2.3 MB above the original control's maximum. Process RSS includes PyTorch and
  compiler state; analytic live tensor bytes are equal across plans.
- TorchInductor's generated-kernel counter is zero for packed external GEMMs;
  it must not be interpreted as zero physical kernels. Logical operator counts
  are the portable structural measure.
- The heldout advantage is small and comes from three conditional artifacts.
  A post-hoc within-run bootstrap over their 11 timing blocks put the aggregate
  fixed-minus-candidate delta at `13.010 us` median with a
  `[7.765, 18.269] us` 95% interval and 99.937% positive resamples. This is a
  diagnostic, not part of the frozen gate or an independent-machine result.
- The tool language and legal fuse/split primitive were supplied. The machine
  generated the conditional decision structure and selected its leaves from
  real compiler outcomes; it did not invent a new tensor primitive or an AI
  architecture.
- The artifacts preserve real source/FX structure but not production inputs,
  pretrained weights, full-model execution, GPU execution, or diverse
  hardware. No claim extends to those surfaces.

## What this answers from the prior boundary audit

1. **Autonomous grammar:** partially crossed. The constructor generated and
   froze a conditional tool-selection grammar from outcomes; the typed
   primitive language remained evaluator-supplied.
2. **Supplied forms versus inventions:** not inflated. Five partitions are a
   complete supplied search space, not five inventions. The new artifact is
   the learned reusable conditional policy.
3. **Heldout fixed-portfolio boundary:** crossed within this restricted real
   implementation-derived graph setting by `0.3677%` aggregate latency.
4. **Synthetic learning to construction:** crossed for empirical outcome
   learning, not causal learning. The learned tree directly constructed typed
   packed/separate executable plans.
5. **Reuse and reachability:** the same frozen policy transferred across 24
   BART/Llama artifacts and reached an aggregate runtime result unavailable to
   either predeclared fixed choice. It did not beat the fixed e-graph on
   compile-plus-1,000-call cost.
6. **Integrated protocol:** crossed as a research protocol—freeze, extraction,
   containment, independent verification, real e-graph, exhaustive/random/
   replay/no-memory/no-probe controls, compiler measurements, and negative
   preservation run together. It is not yet a production compiler protocol.
