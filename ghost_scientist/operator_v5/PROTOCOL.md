# Ghost Scientist Operator v5 prospective protocol

## Research question

Can a frozen, architecture-neutral constructor emit complete typed tensor
programs—including reusable derived parameters—and conditionally select them
on post-freeze graph artifacts more cheaply than stock compilation, a strong
fixed portfolio, replay memory, static compute selection, and scoped genuine
equality saturation?

This is not a test of an LLM or a Transformer architecture.  The small
attention slice is a source/control family only.  The protocol makes no
autonomous-primitive, algorithm-novelty, production, GPU, or
architecture-superiority claim.

## What is constructed

A candidate output is not a strategy id.  It contains:

1. a complete compile-time parameter-construction SSA program; and
2. a complete runtime tensor SSA program.

The evaluator owns strict schema validation, whole-program type/shape/storage
inference, deterministic tensor materialization, output layout contracts,
numerical replay, compiler execution, timing, and memory accounting.

The frozen language covers dense and sparse matrix algebra, broadcast
elementwise operations, reductions, normalization, layout changes,
convolution, activation/fusion, periodic stencils, sparse graph message
passing, state-space projection graphs, and reusable dense parameter
composition.

Rewrite forms and primitive semantics are supplied by the protocol.  Operator
v5 constructs and conditionally reuses whole programs; it does not invent new
primitive opcodes or establish autonomous tool-grammar invention.

## Provenance and corpus truth

Private provenance records bind each public artifact to:

- the installed source symbol, path, and SHA-256;
- the exact public artifact digest;
- a full `torch.export` FX graph text/digest when supported; and
- an honest translation scope.

Mamba and BERT controls bind to installed Hugging Face source.  CNN/layout
graphs bind to installed PyTorch functional source.  Graph, normalization,
diffusion, and dense scientific kernels are evaluator-authored typed
translations of standard operator motifs, not full third-party models.
Sparse CSR currently executes under TorchInductor but is `UNSUPPORTED` by
`torch.export`; it is never relabeled as an export pass.

All tensors use deterministic random/evaluator weights.  No pretrained-model
quality and no GPU execution is measured.

## Completed pre-freeze phases

- Development: 21 artifacts, seven structural families, 45 plan outcomes.
- Validation/calibration: 21 artifacts, seven families, 45 outcomes.
- Confirmation: 21 untouched artifacts, seven families, 45 outcomes.
- Boundary stress: 16 artifacts, eight families, 32 outcomes, including a
  reference-only BERT QKV control.

Every outcome used a fresh process, empty TorchInductor cache, one CPU thread,
seven timing repetitions, and deterministic inputs/parameters.  All 167
pre-freeze plan measurements compiled and passed the absolute numerical bound.
Every unfavorable rewrite remains in the ledgers.

The final grammar is deliberately restricted.  Per-structure fixed plan
choices are learned from development/calibration outcomes.  Conditional
branches may inspect only the exact typed-shape predicate
`association_right_cheaper`; noisy proxy sizes and reuse counts cannot branch.

## Frozen controls

- `stock_reference`: the original typed program under TorchInductor.
- `fixed_first_rewrite`: the first evaluator rewrite, with reference fallback.
- `fixed_compute`: minimum static operator/node count.
- `fixed_signature_portfolio` / `no_probe_fixed_portfolio`: strongest single
  calibrated plan per structural signature, with no conditional features.
- `replay_memory`: nearest calibrated artifact within a structural signature,
  using predeclared log-scaled typed features.
- `equality_saturation` / `no_memory_egraph`: a real hash-consed union-find
  e-graph, congruence rebuild, fixed-point associative/commutative saturation,
  and FLOP extraction on supported dense/sparse matrix chains; reference
  fallback elsewhere.
- `random`: deterministic artifact-id-seeded legal plan.
- `autotuning_exhaustive`: best measured legal plan; an oracle, not a
  deployable candidate.

Overlapping controls are reported under each name but never counted as
independent evidence.

## Post-freeze heldout policy

Only after freeze creation and verification, generate 24 artifacts (three per
family) from state-space, sparse graph, CNN, periodic diffusion, explicit
normalization, layout MLP, dense scientific matrix-chain, and BERT attention
control sources.

Generation seed:
`0x67686f73745f6f70657261746f725f76355f68656c646f75745f3031`.

The policy requires:

- unseen opaque ids, seeds, and shapes;
- bounded shapes inside the predeclared language;
- dense-chain and sparse-chain cases on both sides of the exact association
  cost predicate;
- reuse counts spanning `100`, `10_000`, and `100_000`;
- three sparse CSR export negatives retained as negatives;
- at least 18 successful full Torch Export receipts; and
- no heldout artifact, outcome, or plan directory before the freeze record.

The candidate sees one opaque artifact and the frozen grammar inside the
contained process.  It cannot see provenance, other artifacts, outcomes,
PyTorch, evaluator code, control code, clocks, network sockets, or process
creation.

## Measurement and containment

Each legal plan is compiled and measured in a fresh process/cache with 11
timing repetitions.  The joint score is the equal-weight geometric mean of
within-artifact ratios for:

- construction plus compilation time;
- median CPU latency;
- construction/compile plus declared-reuse amortized latency; and
- process peak RSS.

Numerical validity and output layout are hard constraints, not soft score
terms.  Maximum eager and compiled absolute error must be at most `1e-5`.

The integrated runner first builds and probes the default-deny seccomp filter,
then seals all contained candidate plans before measuring any heldout
outcomes.  `fork`, `socket`, `unshare`, `kill`, and `clock_gettime` must return
`EPERM`.  User/PID/IPC/UTS/cgroup and mount isolation are required.
The current host prevents bubblewrap from initializing a separate network
namespace through netlink; network denial is therefore provided and tested by
seccomp, and network-namespace isolation is explicitly unavailable rather than
claimed.

## Predeclared heldout PASS gate

The prospective verdict is PASS only when all conditions hold:

1. Exactly 24 artifacts and 24 contained candidate receipts complete.
2. All selected plans are exact evaluator constructions and all numerical/type/
   layout contracts pass.
3. The hostile containment probe passes.
4. At least 18 artifacts have successful Torch Export provenance receipts.
5. The candidate selects at least four `(structural signature, plan index)`
   forms.
6. At least six selected plans construct derived parameters across at least two
   families.
7. At least four derived-parameter selections across at least two families
   beat their original program in declared-reuse amortized total cost.
8. Candidate joint score beats stock, compute-fixed, and scoped e-graph, and is
   no worse than replay memory.
9. Candidate joint score improves by at least 1% over the strong fixed-signature
   portfolio.
10. Candidate regret versus exhaustive autotuning is at most 3%.
11. Candidate loses to stock on at most two artifacts, with no loss above 10%.

Random and exhaustive outcomes are mandatory reports but random is not a gate
and exhaustive is an oracle upper bound.

Any failed gate produces a preserved FAIL verdict.  Passing would support only
this claim: a frozen typed constructor conditionally built and reused
multi-operator CPU tensor programs more cheaply on this provenance-bounded
heldout.  It would not prove autonomous primitive invention, general science,
portable compiler superiority, production safety, or GPU performance.

