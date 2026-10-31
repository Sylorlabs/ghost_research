# Round T / T1 — Raw causal substrate

**Verdict: VALID NEGATIVE for representation birth.** The neutral mutable
micro-dynamic field produced a strong *narrow transfer signal* on its own raw
transition worlds (0/184 held-out bit errors), beating fixed field (110/184),
128 equal-budget random candidates (22/184), and replay memory (110/184).
That is not accepted as representation birth: the learner and worlds both use
the same human-installed bias, one shared 16-entry local response surface plus
two incoming wires per cell. The result demonstrates that this particular
substrate can identify its supplied structural regularity. It does **not**
demonstrate that the system made the representation itself.

## Question

Can mutable, non-linguistic micro-dynamics form a reusable executable
mechanism from raw state transitions without a named feature menu, language
model, embedding, token prediction objective, answer traces, or a fixed
domain-specific tool library?

## Local construction

`sparse_poly_discovery/raw_causal_substrate_round_t.zig` creates twelve raw
four-cell transition worlds. A state is four unlabelled bits. A transition is
made by applying one unknown 16-entry bit surface to two wired input cells for
each output cell. The mutable field searches raw bit surfaces and wire ends
against twelve observed states; four hash-partitioned states are held out.

Allowed basic machinery is explicit: state storage, deterministic mutation /
enumeration, execution, equality comparison, bit wiring, and timing-free
replay. There are no imported learning libraries and no external corpus. The
harness imports only Zig standard library support.

The field stores an executable artifact (surface bits plus wire endpoints),
not a word or named operation. It has no `count`, relation, order, XOR,
comparison, graph, compiler, or task-family feature. That absence is checked
against the released CSV. It does **not** make the field grammar-free: its
shared local-surface topology is a representation imposed by this experiment.

## Controls and result

All arms see the same 12 observed transitions per world and are evaluated on
the same 4 held-out states. The mutable arm chooses one response surface and
wires before held-out evaluation. The random arm receives 128 raw candidates;
the fixed arm is a frozen zero field; replay stores observed transitions and
emits zero bits for unseen states.

| Arm | Held-out errors / 184 raw bits | Interpretation |
|---|---:|---|
| mutable field | **0** | Found the supplied shared-surface regularity |
| fixed field | 110 | No adaptation |
| random mutation | 22 | Equal raw-candidate budget but no selection from observations |
| replay memory | 110 | Exact seen-state storage does not extrapolate |

The mutable result is reproducible and beats each control, but it fails T1's
actual acceptance criterion because the substrate's reusable form was chosen
by the human experiment author. The proper T1 verdict is therefore **VALID
NEGATIVE**, not a positive claim hidden behind good scores.

## Ghost Engine grounding

Ghost Engine was inspected read-only. T1 borrows only its VSA-free evidence
discipline:

- `src/rank.zig` provides the durable `noise → emerging → pattern → validated
  → verified` lineage idea. A mutable artifact is recorded as `PATTERN` after
  passing its fresh partition, while fixed/random/replay artifacts stay
  `NOISE`.
- `docs/ideas/SIGIL_REFERENCE.md` provides the separation between speculative
  scratch work, committed state, and snapshots. Random candidates are marked
  `scratch_only`; the selected field is `committed_after_fresh_partition`; the
  aggregate closure is a snapshot. The code does not import Ghost Engine or
  give the substrate Rune/Sigil meanings.

No Ghost Engine file was modified. Its existing inventions, menus, VSA paths,
and textual surfaces were not reused as substrate primitives.

## Reproduction

Run from repository root while putting Zig caches outside the read-only cache
location used by this environment:

```sh
zig build-exe sparse_poly_discovery/raw_causal_substrate_round_t.zig \
  --cache-dir /tmp/zig-t-cache --global-cache-dir /tmp/zig-t-global \
  -femit-bin=/tmp/raw_causal_t
/tmp/raw_causal_t selftest
/tmp/raw_causal_t results/raw_causal_substrate_round_t.csv
```

Fresh self-test result:

```text
SELFTEST PASS: deterministic raw micro-dynamic substrate; fresh partition,
fixed/random/replay controls, scratch-to-committed lineage, and explicit
non-emergence verdict hold
```

The CSV is deterministic under two fresh runs. It releases aggregate
transition errors and raw structural digests, not a prose answer key.

## What this falsifies and what remains

This falsifies the tempting claim that excellent held-out performance by a
mutable bit field automatically means it invented its own representation. It
does not. The shared response-surface assumption is sufficient to explain the
gain.

Next work must remove or competitively evolve the field topology itself, then
test on worlds whose generative structure is not selected to match a single
preinstalled form. T2 and T3 are the needed independent challenge/ecology and
anti-overfit gates; their completion is required before any heredity or
open-ended-intelligence claim.
