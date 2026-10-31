# Round AC / AC2 — self-producing proposal ecology

**Verdict: VALID NEGATIVE.** Executable proposer programs produced and replaced
other executable proposer programs, including members of their own inherited
population, and the resulting ecology earned a small fresh-resource advantage
over equal-search controls. However, the host still defines the VM instruction
meanings, fixed genome width, parent/victim schedule, and whole-genome
replacement operation. Recursion moved the external generator into fixed VM
semantics; it did not eliminate it.

## Question

Can proposal-producing structures emit, mutate, challenge, replace, and retire
proposal-producing structures—including themselves—without a host candidate
generator or operator/tool menu? Human bootstrap begins unverified and receives
no origin privilege. Only sealed fresh resource per exactly charged work may
commit a candidate.

## Instrument

Each of 24 cohorts begins with a raw 40-byte organism tape and 16 inherited
12-byte executable proposer strings. An extant proposer executes over the raw
tape to emit every byte of a challenger proposer. The challenger then emits a
whole-tape candidate. Old and candidate tapes are compared on charged ordinary
contexts; only afterward is the frozen winner evaluated on 24 disjoint fresh
contexts. No evaluator target, correctness trace, named feature, component map,
operator menu, or solution Rune reaches the population.

The ledger records parent, victim, generation, measured effect, every proposer
execution/calibration charge, commit/rollback, and a deterministic lineage hash.
The private oracle is only an unreachable ceiling.

## Results

| Policy | Charged work | Old resource | Committed resource | Proposer replacements | Bootstrap survivors | Commit / rollback |
|---|---:|---:|---:|---:|---:|---:|
| self-producing ecology | 8,640 | 93,563 | **101,963** | 50 | 336 / 384 | 24 / 0 |
| fixed / ablated | 0 | 93,563 | 93,563 | 0 | — | 0 / 24 |
| equal-search random | 8,640 | 93,563 | 101,195 | 44 | 341 / 384 | 22 / 2 |
| equal-search bootstrap replay | 8,640 | 93,563 | 101,795 | 55 | 335 / 384 | 22 / 2 |
| shuffled proposer/victim binding | 8,640 | 93,563 | 101,315 | 45 | 340 / 384 | 24 / 0 |
| false evidence | 8,640 | 93,563 | **93,563** | 72 | 313 / 384 | 0 / 24 |
| relocated tape | 8,640 | 93,563 | 102,035 | 43 | 342 / 384 | 24 / 0 |
| value-recoded tape | 8,640 | 93,563 | 102,155 | 60 | 324 / 384 | 24 / 0 |
| resegmented instruction fetch | 8,640 | 93,563 | 101,723 | 51 | 333 / 384 | 22 / 2 |
| private oracle ceiling | 0 | 93,563 | 184,307 | 0 | — | 24 / 0 |

The bounded causal result is real. The ecology gains 8,400 fresh resource over
its old state, 768 over random, 168 over replay, and 648 over shuffled binding.
Proposer ablation returns exactly 93,563. Reversing evidence produces many
internal replacements but every harmful fresh candidate rolls back, also
returning exactly 93,563. Forty-eight inherited proposer slots are replaced in
the main ecology; human origin does not protect them.

## Why this does not pass organism ownership

The numerical win is not enough. Three scaffolds dominate the verdict:

1. The host assigns four meanings to instruction bits. The organism may rewrite
   programs but cannot invent, retire, or reinterpret that execution physics.
2. The host fixes a 12-byte proposer boundary and schedules which extant program
   emits which whole-genome challenger. That is a hidden proposal ontology.
3. Relocation and value recoding retain gains, but changing instruction
   segmentation changes the lineage, survivor set, resource total, and produces
   two rollbacks. No organism-owned reconstruction restores equivalent function.

Thus the experiment establishes a **self-producing proposal ecology inside a
human VM**, not a self-producing proposal physics. AC2 does not release AC4.
The next admissible mechanism must make instruction interpretation, executable
extent, replacement granularity, and proposer scheduling mutable competitors
with causal retirement—not immutable meanings disguised as raw computation.

## Reproduce

```bash
mkdir -p /tmp/zig-cache-ac2 /tmp/zig-global-ac2
zig build-exe sparse_poly_discovery/self_producing_proposals_round_ac.zig \
  -femit-bin=/tmp/self_producing_proposals_round_ac \
  --cache-dir /tmp/zig-cache-ac2 --global-cache-dir /tmp/zig-global-ac2
/tmp/self_producing_proposals_round_ac selftest
/tmp/self_producing_proposals_round_ac run results/self_producing_proposals_round_ac.csv
```

Expected:

```text
round_ac_ac2 selftest PASS verdict=VALID_NEGATIVE deterministic=true recursive_proposal_gain=true host_vm_owned=false
```

Artifacts:

- `sparse_poly_discovery/self_producing_proposals_round_ac.zig`
- `results/self_producing_proposals_round_ac.csv`
- `docs/research/self_producing_proposals_round_ac.md`
