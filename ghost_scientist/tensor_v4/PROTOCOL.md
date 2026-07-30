# Ghost Scientist Tensor v4 prospective protocol

## Research question

Can a development-outcome constructor produce a frozen conditional tensor
rewrite that transfers to post-freeze computation-graph artifacts and beats
the strongest predeclared fixed portfolio without changing typed semantics?

Transformer implementations are only sources of externally authored control
graphs. They are not the target architecture, and this protocol does not train
a Transformer or claim that Transformers are efficient.

## Artifact and claim scope

The extractor instantiates locally installed BERT, RoBERTa, T5, BART, and Llama
attention modules and requires `torch.export` evidence of exactly three
same-input linear projection nodes. Public artifacts retain only opaque typed
projection metadata and deterministic evaluator weights. Private audit records
bind each public artifact to the installed source file, source digest, module
class, configuration, and full FX graph digest/text.

These are real implementation-derived graph structures with random initialized
model instances and deterministic evaluator weights. They are not pretrained
model performance measurements. No GPU is used.

The restricted expression language may only partition the three projections
into packed linear groups, exact splits, head views, and transposes. Shape,
dtype, projection order, bias behavior, output arity, and last-dimension layout
must remain unchanged.

## Phases

- Development: 18 artifacts from BERT, RoBERTa, and T5. Every one of the five
  Bell partitions is measured with single-threaded CPU TorchInductor. A depth-2
  outcome tree is learned from those 90 outcomes.
- Validation: 8 artifacts spanning all five source families. Protocol repairs
  are allowed, and every failed rehearsal is retained.
- Freeze: candidate, learned grammar, evaluator, genuine e-graph, independent
  verifier, extractor, trial runner, containment sources, this protocol, and
  all development/validation evidence are SHA-256 frozen.
- Heldout: only after freeze verification, generate 24 artifacts from BART and
  Llama with seed
  `0x74656e736f725f76345f68656c645f3031`, then run the frozen trial with 11
  timing repetitions.

The contained candidate sees exactly one public artifact and the frozen
grammar. It cannot see family/provenance, other artifacts, outcomes, PyTorch,
the evaluator, verifier, controls, or clocks.

## Controls

- `strong_fixed_compiler`: original three separate projections compiled by
  TorchInductor.
- `fixed_equality_saturation`: a real union-find e-graph saturated with
  bidirectional fuse/split equalities to a fixpoint, then extracted by minimum
  logical GEMM count.
- `random`: deterministic random legal partition from the artifact digest.
- `replay`: the globally best single development plan, pack-all.
- `brute_exhaustive`: fastest measured plan among all five legal partitions.
- `no_memory`: original separate projections, with no learned development
  state.
- `no_probe`: the e-graph/static-cost plan, with no measured-outcome learner.

Some controls intentionally select the same plan. That overlap is reported,
not counted as independent evidence.

## Measurement

Every plan is measured once per artifact in a fresh process and a fresh
TorchInductor cache, using one CPU thread, full-graph static compilation, and
identical deterministic inputs and parameters. Records include compilation
time, median/MAD CPU latency, samples, logical operator/kernel counts,
TorchInductor-generated-code counters, process peak/delta RSS, analytic live
tensor bytes, multiply-add count, output contracts, and eager/compiled
numerical errors.

The independent verifier imports none of the candidate, constructor,
extractor, evaluator, or shared core. It checks exact partition structure and
NumPy float32/float64 semantics over eight cases. Numerical acceptance uses a
conservative reduction-width and dtype forward-error bound, not a
shape-independent absolute threshold.

## Predeclared heldout gate

The heldout verdict is PASS only if:

1. All 24 artifacts complete with no candidate, containment, verifier,
   compiler, or evaluator failure.
2. Candidate replay is byte-identical on all 24.
3. All typed and numerical contracts pass, with compiled float32 maximum
   absolute error at most `1e-5`.
4. The candidate selects at least two distinct plans, demonstrating a
   conditional rule rather than a renamed fixed portfolio.
5. Aggregate candidate median latency is lower than both the fixed original
   compiler and genuine equality-saturation controls.
6. Aggregate candidate median latency improves by more than 0.1% over the
   lowest-latency predeclared fixed control.
7. Both default-deny filters pass hostile probes and the candidate network
   namespace differs from the host.

Random and exhaustive results are mandatory measurements but are not verdict
gates: random can win by chance, while exhaustive is an oracle upper bound.
Compile-time and amortized reuse costs are mandatory reports but do not decide
the latency-transfer gate. Any unfavorable compile, memory, random, exhaustive,
or per-artifact result remains in the ledger and limits the claim.

No result permits a GPU-speed, pretrained-model, autonomous-primitive,
architecture-superiority, or algorithm-novelty claim.
