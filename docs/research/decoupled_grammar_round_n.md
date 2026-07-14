# N4 — decoupled grammar expansion

**Verdict: VALID NEGATIVE.** On eight evaluator-owned fresh opaque targets,
the history-derived grammar solved **4/8** exactly, versus **0/8** for the
frozen existing primitive menu and **4/8** for the blind composition control.
It did not beat blind selection or transfer across both independent hidden
kinds. This is the correct result once N1's prohibition on held-out target
queries is preserved.

Harness: `sparse_poly_discovery/decoupled_grammar_round_n.zig`  
Ledger: `results/decoupled_grammar_round_n.csv`

## Protocol

The policy has four public aggregate trace fields, opaque tokens, and eight
frozen historical outcome rows. Each trace signature occurs once with each
private target kind in the fresh split, so it cannot name a winning candidate
from trace alone. The policy is not passed a target formula, kind/family label,
parameters, target ID feature, held-out result, or audit data.

From history it retains only two nonredundant public compositions whose old
results were repeatedly exact and better than their respective atoms. Training
tokens may query both public composition symbols and are then fresh-tested.
Held-out tokens cannot be queried: each arm receives exactly one evaluator-owned
fresh score. The grammar arm must freeze one composition from history; the
existing-menu arm freezes one existing atom; the blind arm alternates a
composition without using outcomes. This prevents the invalid shortcut of
asking a candidate-scoring oracle about the very held-out target being claimed
as fresh.

Training targets have a persistent nine-call budget: two query calls plus one
fresh test for each of three arms. Held-out targets have a persistent three-call
budget: one evaluator-owned fresh score per arm, with candidate queries refused
by protocol. The next action is rejected after either budget. The 106-row CSV
contains eight frozen-history rows, 96 individually charged action rows, one
verdict row, and its header.

## Result

| Equal-cost arm | Exact fresh targets | Calls per target |
|---|---:|---:|
| History-derived composition grammar | 4/8 | 1 |
| Frozen existing atom menu | 0/8 | 1 |
| Blind composition choice | **4/8** | 1 |

The frozen grammar succeeds 4/4 in one hidden kind and 0/4 in the other.
Reversing token presentation and training-candidate query order preserves all
totals. The public trace-only router remains 4/8. The core result is therefore
not a failure of accounting: under a genuinely non-diagnostic trace and no
held-out query access, this frozen history does not identify which composition
applies to a new case.

## Controls and limits

- **Fresh separation:** held-out targets do not admit query calls at all;
  fresh scores are evaluator-owned and unavailable while the arm is frozen.
- **Persistent accounting:** every query and fresh test increments the target
  state; a simulated restart cannot obtain a tenth action.
- **Order / duplicate:** reverse target presentation and candidate order in
  `selftest`; every public trace is deliberately duplicated across opposite
  private kinds.
- **Privacy scan:** `selftest` rejects private kind, formula, parameter,
  audit, or held-out-label markers in public output.
- **Important limit:** This is still a deliberately bounded synthetic world.
  The public candidate alphabet contains the two atoms and the composition
  operation is a supplied language operation. Frozen history tells the policy
  which *two composition forms deserve testing*, but cannot choose between them
  on a truly fresh target. The experiment does not show unrestricted invention
  of new operators or OS-level evaluator isolation.

## Reproduce

```bash
rm -rf /tmp/zig-n4-cache /tmp/zig-n4-global /tmp/decoupled_grammar_n4
zig build-exe sparse_poly_discovery/decoupled_grammar_round_n.zig -O ReleaseFast \
  --cache-dir /tmp/zig-n4-cache --global-cache-dir /tmp/zig-n4-global \
  -femit-bin=/tmp/decoupled_grammar_n4
/tmp/decoupled_grammar_n4 results/decoupled_grammar_round_n.csv
/tmp/decoupled_grammar_n4 selftest
```
