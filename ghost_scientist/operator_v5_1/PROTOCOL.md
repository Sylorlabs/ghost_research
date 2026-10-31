# Ghost Scientist Operator v5.1 prospective protocol

## Preserved predecessor result

Operator v5 freeze
`0a1e478ae1c6e5fd096b7bb2f578a0aa924b4ffc10cbd64d55f911b4a70e93d9`
completed a valid 24-artifact prospective trial and returned
`GHOST_OPERATOR_HELDOUT_V5_FAIL`.

It passed 17/18 gates.  Candidate score was `1.00829849` versus strong fixed
`1.01814173`: a `0.967%` improvement, short of the frozen `1%` gate by
`0.033` percentage points.  Every compiler, numerical, replay, containment,
provenance, reuse, stock-loss, replay, e-graph, compute-fixed, and oracle-regret
gate passed.

The failure is immutable calibration evidence.  v5.1 does not relax, rename,
or remove any v5 PASS gate.

## Single protocol change

All v5 candidate, evaluator, IR, rewrite, e-graph, measurement, containment,
and integrated-trial code remains byte-identical and is authenticated through
the v5 freeze.

The v5.1 grammar is refit over all 103 preserved v5 artifacts.  Conditional
trees have depth at most one, at least two examples per leaf, and may inspect
only:

- `association_right_cheaper`, the exact typed-shape algebraic cost predicate;
- `input_elements`, used by the explicit-normalization signature.

The resulting new rule is:

`explicit normalization -> layer_norm primitive iff input_elements <= 20480`.

All other fixed/conditional choices retain their v5 structural meaning.
The v5 heldout is included in v5.1 calibration and can never count as v5.1
prospective evidence.

Replay memory and the strong fixed-signature portfolio are also refit on all
103 v5 artifacts, making the v5.1 controls strictly better informed than the
original controls.

## Fresh prospective corpus

Only after v5.1 freeze verification, generate 24 new artifacts, three per
family, under seed:

`0x67686f73745f6f70657261746f725f76355f315f68656c646f75745f3032`.

Families, provenance requirements, CPU-only measurement, fresh-process/cache
isolation, 11 repetitions, typed/numerical contracts, containment, and claim
limits are unchanged from v5.

The new shapes must be unseen across all 103 calibration artifacts.  The
normalization slice must include values below, near, and above 20,480 input
elements.  Dense and sparse association slices must include both values of the
exact algebraic predicate.  At least 18 Torch Export receipts are required and
sparse export negatives remain explicit.

## Unchanged PASS gate

The v5.1 verdict is PASS only if all original 18 conditions hold:

1. Exactly 24 artifacts and contained candidate receipts.
2. All candidate plans are exact evaluator constructions.
3. All typed, storage, layout, eager, and compiled numerical contracts pass at
   absolute error `<= 1e-5`.
4. Default-deny hostile containment probe passes.
5. At least 18 Torch Export provenance receipts.
6. At least four selected structural plan forms.
7. At least six derived-parameter selections across at least two families.
8. At least four amortized reuse wins across at least two families.
9. Candidate beats stock.
10. Candidate beats compute-fixed.
11. Candidate beats scoped genuine equality saturation.
12. Candidate is no worse than replay memory.
13. Candidate improves at least `1%` over the strong fixed-signature portfolio.
14. Candidate regret versus exhaustive autotuning is at most `3%`.
15. Candidate loses to stock on at most two artifacts.
16. No stock loss exceeds `10%`.
17. Candidate replay receipts cover all artifacts.
18. All 24 artifacts complete without compiler/evaluator failure.

As in v5, a PASS supports only provenance-bounded conditional construction and
reuse of typed CPU tensor programs.  It does not establish autonomous primitive
or grammar invention, algorithm novelty, production readiness, GPU speed, or
architecture superiority.

