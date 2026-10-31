# Ghost Scientist Operator v5.1 goal closure

## Verdict

`GHOST_OPERATOR_HELDOUT_V5_PASS` — all 18 unchanged prospective gates passed
on the fresh v5.1 heldout.

The byte-identical integrated v5 runner retains its v5 status token; the
v5.1 wrapper verified the chained v5.1 freeze before invoking it.

Key identities:

- v5 preserved FAIL freeze:
  `0a1e478ae1c6e5fd096b7bb2f578a0aa924b4ffc10cbd64d55f911b4a70e93d9`
- v5.1 freeze:
  `cd24e8337eb81a227057e9fe5205806e03d9f8a855f82d4d6f87752e83f38e0d`
- v5.1 frozen grammar:
  `e465b9c9398288c34bbce9e2d00aaa31d16c46fd2b2282e2a5c7a86317eb53c7`
- v5.1 heldout manifest:
  `f6aa4cf7a04cc38b8af79fa1f0b5e41496798a78d0606a358cdfd78a683098d0`
- prospective verdict:
  `bcdfb1a225371a94253e67ccb124ba22b9ba4cc5ff81afd4558e80ca2bd6195e`
- independent recomputation:
  `5bccf8a740fc4da8f3a838e52486aae75c40a95b92b1d29afe8c1e7984599d42`

## Prospective results

The fresh heldout contained 24 artifacts across eight families and 48 legal
plan measurements.  Every plan compiled; every typed, storage, layout, eager,
and compiled numerical contract passed.

Maximum error across the complete grid:

- eager absolute error: `2.86102294921875e-6`
- compiled absolute error: `4.291534423828125e-6`
- frozen limit: `1e-5`

Equal-weight four-objective geometric scores:

| Method | Score |
|---|---:|
| exhaustive autotuning oracle | 1.001327 |
| frozen candidate | 1.002005 |
| replay memory | 1.004062 |
| strong fixed-signature portfolio | 1.021641 |
| compute-fixed | 1.026092 |
| first fixed rewrite | 1.076652 |
| scoped genuine equality saturation | 1.193743 |
| stock reference compiler | 1.257580 |
| deterministic random | 1.243829 |

Candidate improvements:

- `1.922%` over the strong fixed-signature portfolio;
- `0.205%` over replay memory;
- `2.347%` over compute-fixed;
- `16.062%` over scoped equality saturation;
- `20.323%` over stock reference;
- `0.0677%` regret versus exhaustive autotuning.

The candidate recorded 10 wins, 13 ties, and 1 loss versus stock.  The one
loss was `1.138%`, inside the frozen at-most-two/at-most-10% bound.

## What crossed the original boundaries

1. **Whole constructed tools, not ids.** Candidate outputs contain a complete
   compile-time parameter-construction SSA program and a complete runtime
   typed tensor program.  The evaluator rejects untyped strategy labels.
2. **Strong fixed heldout comparison.** The frozen candidate beat the strongest
   non-conditional per-signature portfolio by the predeclared `>1%` margin on a
   post-freeze corpus.
3. **Real compiler/outcome connection.** Twenty-one artifacts have full
   Torch Export receipts tied to installed source.  Three sparse CSR artifacts
   remain explicit Export `UNSUPPORTED` negatives while still compiling under
   CPU TorchInductor.
4. **Cheaper reuse.** Eight selected derived-parameter programs beat their
   originals in construction+compile+declared-reuse amortized cost across CNN,
   dense scientific, and state-space families.
5. **One production research protocol.** One frozen runner verifies the freeze,
   builds and probes containment, seals all candidate plans before outcomes,
   measures the exhaustive grid in isolated fresh-cache processes, computes all
   controls, and emits the gate verdict.
6. **Independent replay.** A stdlib-only recomputation rebuilt every
   within-artifact score, aggregate, reuse count, provenance count, stock-loss
   bound, and all 18 gates from raw ledgers and matched the prospective verdict.

## Preserved negative evidence

- v5 is permanently a 17/18-gate FAIL: its fixed-portfolio improvement was
  `0.967%`, short of `1%`.
- All stencil-convolution rewrites that lost remain in the pre-freeze and
  heldout ledgers.
- Sparse CSR Torch Export remains unsupported on all sparse artifacts.
- Several normalization and graph reassociations lost on individual shapes;
  these outcomes drove the frozen fail-closed selectors.
- The display-bound GPU was not used.
- Bubblewrap network-namespace initialization is unavailable under the host
  netlink policy.  Network access is instead explicitly denied and hostile-
  probed through default-deny seccomp (`socket=EPERM`).

## Claim boundary

The evidence supports this bounded statement:

> A frozen typed constructor conditionally built and reused complete
> multi-operator CPU tensor programs more cheaply than stock compilation,
> compute-fixed, replay, scoped equality saturation, and a strong fixed
> portfolio on this provenance-bound 24-artifact heldout.

It does **not** show autonomous primitive or rewrite-grammar invention.  The
primitive semantics and rewrite theory are supplied.  It also does not show
algorithm novelty, general autonomous science, pretrained-model improvement,
production readiness, GPU performance, or architecture superiority.

