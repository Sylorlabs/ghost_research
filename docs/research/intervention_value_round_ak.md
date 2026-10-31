# Round AK / AK2 — Intervention value calibration

**Verdict: FOUNDATION POSITIVE (bounded frozen-substrate tier).** An earned,
answer-scrubbed consequence record selects one generic raw perturbation after a
current-world raw scan and beats every equal-cost strong allocation control in
pre-registered hidden transfer worlds.

## Question

Can an organism decide which raw perturbation is worth spending on from its own
causal consequences, rather than from a host-provided uncertainty, novelty, or
reward score?

## Mechanism

Training supplies only charged before/after raw-material traces. The organism
stores `direction`, `support`, and append-only provenance: whether greater or
lesser repeated raw change predicts persistence. Transfer worlds privately
relocate action addresses and recode material values. Each policy gets one
equal-cost scan of all eight raw perturbations and one final allocation. The
earned policy calculates max/min empirical consequence according to its earned
direction; it has no world identity, target, future material value, candidate
ranker, answer table, or evaluator feedback.

## Results

The wholesale-recode rows in the CSV are the decisive evaluation. The earned
policy commits in every one of 960 hidden worlds at the same 8+1 raw contacts
per world as random, replay, shuffled, fixed-value, ablated, and false-evidence
policies. It exceeds all of them in evaluator-private future material. The
oracle is reported only as an invalid sealed ceiling.

## Controls and attacks

- **Random:** equal scan and allocation cost without an earned record.
- **Replay / shuffled:** preceding or mismatched causal records; both lose.
- **Fixed-value / ablation:** always favor the greatest repeated change; exact
  removal of the earned direction reduces to that form.
- **Counterfactual false evidence:** inverting the earned direction loses.
- **Answer memory / retained answer:** a training address or response cannot
  survive private address relocation and wholesale material-value recoding.
- **World-overlap:** train and transfer domains have disjoint hashed seed
  spaces, verified exhaustively during selftest.

## Scope and limitation

This establishes a narrow reusable causal-allocation mechanism in the declared
Round AJ frozen substrate. The host still supplies uniform finite raw
perturbations, raw transport, bounded memory/time, provenance plumbing, and
post-run measurement. It does **not** establish unrestricted experiment
invention, open-ended intelligence, ownership of the physical substrate, or
hostile containment.

## Reproduce

```sh
zig build-exe sparse_poly_discovery/intervention_value_round_ak.zig -O ReleaseSafe -femit-bin=/tmp/ak2
/tmp/ak2 selftest
/tmp/ak2 run results/intervention_value_round_ak.csv
```
