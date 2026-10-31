# Round AD / AD1 — interpreter birth and bootstrap retirement

**Verdict: VALID NEGATIVE.** A raw mutable 64-cell field can be selected into
macro-configurations that earn a small sealed fresh-resource gain, and accepted
late configurations replace the initially advanced bootstrap state. This does
not establish an organism-created interpreter. The experiment's macro
recognizer fixes four-cell boundaries, four instruction meanings, and the
private-world comparison. It is a human-installed executable language hidden
inside the evaluator, so state replacement is not interpreter replacement.

## Question and limit

Can a uniformly mutable causal medium construct an executable higher-level
interpreter, use it to improve resource consequences, and then replace or
retire a bootstrap without supplied opcode meanings, genome boundaries,
candidate menu, target function, intermediate reward, or answer trace?

The exterior used here is intentionally minimal: a deterministic identical
neighbour transport update, finite charged work, sealed evaluator worlds, and
resource accounting. There is no LLM, text/token prediction, embeddings,
neural or neuro-symbolic component, preloaded solution, named task, component
map, semantic port, or oracle available to the organism. The oracle row is an
unavailable evaluator ceiling only.

This experiment is designed to reject a tempting but false answer. A host
function (`hostMacroEffect`) reads every raw field in fixed groups of four and
assigns operations from two low bits. It is included specifically to see
whether an apparent constructed interpreter remains after hostile change. It
does not.

## Protocol

Twenty independent cohorts start from unverified random 64-cell matter. Each
round makes a raw matter candidate by uniform transport plus a deterministic
matter perturbation; both incumbent and candidate consume nine ordinary
evaluator worlds. The frozen winner is then evaluated in 21 sealed fresh
worlds. Every ordinary comparison is charged (5,760 total calls per active
policy); fresh evaluation governs commit or rollback. Late accepted states are
counted as bootstrap retirements, but have no special privilege.

The equal-cost controls are raw/random matter, replay, a fixed expressive host
language, static bootstrap, shuffled lineage, false lineage, and construction
ablation. Attacks independently relocate addresses, recode values, resegment
the host instruction fetch, permute instruction identity, and permute macro
boundaries. Two canonical runs must produce byte-identical CSV.

## Results

| Policy | Charged work | Old resource | Fresh committed resource | Difference | Retired bootstrap / cohorts |
|---|---:|---:|---:|---:|---:|
| selected macro configurations | 5,760 | 26,767 | **27,197** | **+430** | 6 / 20 |
| construction ablated / static bootstrap | 0 | 26,767 | 26,767 | 0 | 0 / 20 |
| equal-cost raw random matter | 5,760 | 26,767 | 27,030 | +263 | 7 / 20 |
| equal-cost bootstrap replay | 5,760 | 26,767 | 27,047 | +280 | 9 / 20 |
| fixed expressive host language | 5,760 | 26,767 | 26,963 | +196 | 9 / 20 |
| shuffled lineage | 5,760 | 26,767 | **27,197** | +430 | 6 / 20 |
| false lineage | 5,760 | 26,767 | 26,767 | 0 | 12 / 20 |
| relocated addresses | 5,760 | 26,767 | 27,197 | +430 | 6 / 20 |
| value recoding | 5,760 | 27,009 | 27,249 | +240 | 9 / 20 |
| instruction resegmentation | 5,760 | 26,815 | 27,155 | +340 | 6 / 20 |
| instruction permutation | 5,760 | 26,800 | 26,984 | +184 | 8 / 20 |
| boundary permutation | 5,760 | 26,967 | 27,170 | +203 | 10 / 20 |

The bounded causal signal is genuine inside the supplied recognizer: the main
condition is +430 over old, +167 over raw random, +150 over replay, and +234
over the fixed-language control. Forty-three proposals are accepted; 11 fresh
winners commit and nine roll back. Ablation returns exactly to the old 26,767.
False lineage accepts 54 internally harmful candidates but all 20 fresh-world
outcomes roll back, returning exactly to old resource.

## Why it fails the ownership gate

Three observations defeat the stronger claim.

1. **The interpreter is host-defined.** `hostMacroEffect` imposes a four-cell
   instruction boundary, an opcode decode, and four execution meanings. The
   organism never creates, selects among, replaces, or retires these meanings.
2. **The world has hidden semantic geometry.** The evaluator creates the
   private disturbances and defines their comparison to macro effects. It is a
   supplied harvest task, even though the population cannot inspect an answer
   trace or target value.
3. **Lineage and hostile reconstruction do not establish independent
   construction.** Shuffling lineage gives the exact same resource as the main
   condition (27,197), showing the claimed causal construction history does no
   work. Re-segmentation and instruction/boundary permutation yield different
   scores and no internally built alternate decoder reconstructs the original
   macro function.

Consequently, six late accepted raw states may replace the bootstrap *state*,
but no result replaces the bootstrap *interpreter*. The experiment is a valid
negative even though its costed, ablatable bounded gain is real.

## Remaining human-owned layer

The human-owned layer is explicit and substantial: the neighbour transport
equation; the 4-cell macro grouping; opcode interpretation; macro invocation
schedule; private disturbance generator; and resource comparison. The first
two are claimed exterior physics only provisionally; the latter four are
organism-level semantics and make this architecture ineligible for AD4.

An admissible positive would need raw configurations to construct several
alternative executable transducers, demonstrate that an alternative is used
for a fresh gain, retire the original recognizer itself, and recover equivalent
function after an evaluator-defined independent change of instruction identity
and boundary structure. It cannot merely place new bytes into this decoder.

## Reproduce

```bash
mkdir -p /tmp/zig-cache-ad1 /tmp/zig-global-ad1
zig build-exe sparse_poly_discovery/interpreter_birth_round_ad.zig \
  -femit-bin=/tmp/interpreter_birth_round_ad \
  --cache-dir /tmp/zig-cache-ad1 --global-cache-dir /tmp/zig-global-ad1
/tmp/interpreter_birth_round_ad selftest
/tmp/interpreter_birth_round_ad run results/interpreter_birth_round_ad.csv
```

Expected self-test output:

```text
round_ad_ad1 selftest PASS verdict=VALID_NEGATIVE deterministic=true bounded_macro_gain=true organism_owned_interpreter=false
```

Artifacts:

- `sparse_poly_discovery/interpreter_birth_round_ad.zig`
- `results/interpreter_birth_round_ad.csv`
- `docs/research/interpreter_birth_round_ad.md`
