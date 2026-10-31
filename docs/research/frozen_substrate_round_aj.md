# Round AJ / AJ1 — frozen-substrate contract

**Verdict:** **FOUNDATION PASS** — an explicit, reproducible non-task-specific
substrate contract is mechanically exercised and rejects every mounted semantic
or evaluator leak. This is an infrastructure pass only. It does **not** claim
an autonomous organism, an intelligence result, or hostile OS containment.

## Question

Can the project freeze the smallest honest trusted base needed to run later
foundation experiments without smuggling in a target, answer, representation,
tool menu, reward, or evaluator interaction?

The point is to end the infinite-regress test (“did it invent the laws below
it?”) without weakening the test above that line. The frozen base is declared
once and later organism mechanisms must be judged by transfer, ablation,
history/answer-memory controls, and equal-cost controls.

## Declared trusted substrate

The sole organism-facing value contains:

- sixteen untyped raw bytes;
- a finite twelve-step resource budget;
- one generic reversible raw XOR change;
- one uniform nearest-neighbour byte transport operation;
- append-only `before, operation, after` causal-digest events.

The exterior owns sealed hidden-world seeds and makes an opaque post-run
receipt only after the organism stops. Neither value is mounted on the
organism surface. The receipt has no success/correctness interpretation in
AJ1; it exists only to test evaluator placement.

The trusted substrate is allowed to be a fixed physical/computational base. It
is not claimed to be organism-owned. Later positives must be about structures
the organism builds **above** it, not about the existence of bytes, transport,
or time.

## Mechanical hostile manifest

The executable tries all eleven prohibited capability names against the only
organism-facing surface. Each receives the same false/no-data result:

| Forbidden mounted capability | Result |
|---|---|
| task target; answer trace; semantic decoder | denied |
| task/curriculum/world-family label | denied |
| candidate menu; tool library | denied |
| intermediate reward; novelty score; evaluator feedback | denied |

The CSV also establishes that generic variation round-trips exactly, two
uniform executions occur under the resource budget, and four append-only
causal events are recorded. The final digest and evaluator-private receipt are
logged only after these fixtures complete.

## Results

| Check | Observed result |
|---|---|
| Contract manifest | 4/4 required placement/surface/claim-boundary rows pass |
| Generic substrate fixtures | 3/3 pass |
| Seeded prohibited semantic/evaluator requests | 11/11 denied |
| Deterministic replay | byte-identical CSVs |
| Foundation verdict | pass |

Raw evidence: [CSV](../../results/frozen_substrate_round_aj.csv) and
[standalone Zig fixture](../../sparse_poly_discovery/frozen_substrate_round_aj.zig).

## Reproduction

```bash
zig build-exe sparse_poly_discovery/frozen_substrate_round_aj.zig \\
  -O ReleaseFast -femit-bin=/tmp/frozen_substrate_aj
/tmp/frozen_substrate_aj selftest
/tmp/frozen_substrate_aj run results/frozen_substrate_round_aj.csv
```

Observed selftest:

```text
round_aj_aj1 selftest PASS deterministic=true hostile_denials=11 generic_fixtures=3 verdict=FOUNDATION_PASS
```

## Limits and interpretation

This contract does not prove that a separately compiled hostile worker cannot
open files, import libraries, inspect memory, create sockets, or spawn
processes. It is an in-process foundation-science fixture. Round AI's actual
kernel tests found that process/syscall containment is still unresolved, so no
result here may be upgraded to full autonomy/security.

Nor does a denied named request prove arbitrary source code cannot evade the
interface; it proves the later AJ experiments have a narrow declared substrate
and a reproducible leak manifest. Any later claim must additionally survive
independent leakage and answer-memory audits.

**What AJ1 unlocks:** only the evaluation framework for AJ2/AJ3’s reusable
causal abstraction and experience-compounding tests. It does not itself
unlock self-chosen experimentation, a discovery portfolio, or any claim that
the organism invented its own physics or computation.
