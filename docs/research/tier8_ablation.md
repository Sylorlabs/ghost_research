# Tier 8 ablation — is framework revision load-bearing?
> **Belongs to: Round 2026-07-10 · experiment 6 of 8 (Tier 8 ablation)** — [round index](research_round_2026_07_10.md).

**Harness:** `sparse_poly_discovery/tier8_ablation.zig` (new file; no existing file modified)
**Date:** 2026-07-10
**Verdict:** **EXISTENCE PROOF FOUND** — 4 target-solves occur only with framework revision enabled, 0 only with it disabled, at equal (actually smaller) realized eval budget.

---

## Question

The Tier 8 loop PASSed (`tier8_loop.zig`), but on its own authored setup: the same
run that triggers the v3→v4 basis revision also grades itself with v4 enabled.
Missing evidence: an ablation showing some artifact/solve is reachable **only**
with framework revision, at equal budget. Otherwise Tier 8 adds nothing over the
frozen Tier-2 loop with a strict v3 tax.

## Design

Two arms, identical seeds, identical code path, identical ladder/iteration caps.
Both arms start in the **same** state: strict tax, basis v3, reality lane off.

| Arm | Behavior |
|-----|----------|
| **ARM-OFF** | Basis frozen at v3 forever (Tier-2 loop + strict tax, no revision authority) |
| **ARM-ON** | Remix-rate trigger (T8-AG-21 semantics, adapted within-run: cumulative tax checks ≥ 5 and novel rate < 0.20) fires a witnessed closure revision (T8-AG-22 proposal + T8-AG-25 vote) → basis v4 + escape-authentic reality lane |

Batteries per (seed, arm), run as one continuous loop:

- **Battery B** (11 targets): full production engine `ie.solveBlindTarget` —
  includes the rq1 rescue lanes (mod/pipeline, pair-walsh escalation) which
  **bypass the tax gate** entirely.
- **Battery C ladder-only slice** (11 targets): `ui.solveOneTarget` only
  (no xor route, no mod escalation). Every promotion goes through
  `certify() → eqtax.gatePromoteEx`, so this is the slice where the tax gate —
  and therefore its revision — is fully load-bearing.

Seeds (3): `0xF0235A11CE0FF1CE` (production), `0xC1B10D20260706`,
`0xC2B10D20260707` (battery-C held-out replication seeds). Battery B target set
is fixed by `BATTERY_SEED 0xE1B10D20A11CE01` as in production.

Existence proof sought: a target solved in ARM-ON and never in ARM-OFF at the
same seed.

### Reproduce

```bash
cd sparse_poly_discovery
zig build-exe tier8_ablation.zig -O ReleaseFast   # zig 0.14.1
./tier8_ablation                                   # ~6.5 min, single worker thread
# CSV → results/tier8_ablation_2026_07_10.csv
```

Note: the workload runs on one spawned thread with a 512MB stack (2 threads
total incl. main) because the tax greedy fit keeps a ~32MB column store on the
stack and the default 8MB main stack segfaults under `zig build-exe`.

## Results (measured 2026-07-10)

### Per-seed

| Seed | Arm | B solve | C-ladder solve | Tax checked | Novel | Blocked | B evals | Wall |
|------|-----|---------|----------------|-------------|-------|---------|---------|------|
| 0xF0235A11CE0FF1CE | OFF | **11/11** | 0/11 | 20 | 1 | 19 | 1354 | 61.3s |
| 0xF0235A11CE0FF1CE | ON (rev@1) | **11/11** | **1/11** | 14 | 7 | 7 | 693 | 60.1s |
| 0xC1B10D20260706 | OFF | 10/11 | 0/11 | 20 | 1 | 19 | 1704 | 68.3s |
| 0xC1B10D20260706 | ON (rev@1) | **11/11** | **1/11** | 14 | 7 | 7 | 693 | 62.9s |
| 0xC2B10D20260707 | OFF | **11/11** | 0/11 | 20 | 1 | 19 | 1354 | 61.2s |
| 0xC2B10D20260707 | ON (rev@1) | **11/11** | **1/11** | 13 | 6 | 7 | 686 | 59.7s |

### Aggregate

| Metric | ARM-OFF | ARM-ON |
|--------|---------|--------|
| Battery B solves | 32/33 | **33/33** |
| Battery C ladder-only solves | 0/33 | **3/33** |
| Novel promotions | 3 | **20** |
| Remix-blocked | 57 | 21 (all 21 pre-revision; **0 post-revision**) |
| Battery B evals | 4412 | **2072** |
| Targets solved ON-only | — | **4** |
| Targets solved OFF-only | 0 | — |

The revision trigger fired after target 1 in all three ON runs (novel rate 0.0%
over 7 checks — the remix alert crosses almost immediately at v3).

### The existence proofs

**C08 "parity count" — 3/3 seeds, direct mechanism.** In ARM-OFF the ladder
finds a certified escape (walsh) but the v3 tax blocks it as greedy-basis remix
— 2 tax-blocked *certified* escapes per seed — and the target saturates at
cov ≈ 0.49–0.51. In ARM-ON, post-revision v4 (family-conditioned remix basis +
escape-authentic lane) lets the same certified walsh escape promote:
cov = 1.000. This is the clean shape: OFF fails *because of* the rule that the
framework revision revises, and promoting the blocked candidate is exactly what
solves the target.

| Seed | OFF cov (blocked certs) | ON cov (via) |
|------|-------------------------|--------------|
| 0xF023… | 0.510 (2) | 1.000 (walsh) |
| 0xC1B1… | 0.487 (2) | 1.000 (walsh) |
| 0xC2B1… | 0.502 (2) | 1.000 (walsh) |

**B10 "parity AND sum%5" — 1/3 seeds (0xC1B1…), indirect and marginal.**
OFF saturates at cov 0.898 (bar 0.90) with 0 blocked certs *on that target*;
ON solves at 1.000 via unified escalation with a richer library (nlib 17 vs 12)
grown from revision-enabled promotions on earlier targets. Real separation, but
it is a library-trajectory effect and the OFF miss is by 0.002 — do not lean on
it. The load-bearing witness is C08.

### Budget honesty

Both arms run the identical ladder with identical caps; realized evals differ
because accepted promotions change trajectories. **ARM-ON used fewer battery-B
evals than ARM-OFF (2072 vs 4412)** — blocked promotions in OFF force repeated
expensive escalations. The ON advantage is not extra compute.

## Diagnosis

1. **Battery B is too easy to separate the arms** (32/33 vs 33/33): the rq1
   rescue lanes bypass the tax gate, so a v3 block is almost always rescued.
   Any ablation run only on battery B would have concluded "revision adds
   nothing."
2. **Most of battery C is too hard for both arms**: the 9 xor-family targets +
   inv-parity sit at cov ≈ 0.50 in BOTH arms — the tax-gated ladder has no xor
   primitive, and the xor route that solves them in `tier8_battery_c_engine.zig`
   bypasses the tax (hence excluded from the slice). They are uninformative for
   this ablation.
3. **The decisive band is narrow**: targets that are (a) reachable by a
   tax-gated ladder feature and (b) blocked by the v3 greedy remix basis. In
   the current batteries that band contains essentially one target — C08 — plus
   the marginal B10 carryover effect. It replicates 3/3 seeds, so the existence
   proof stands, but it is one witness, not a distribution.

### What would make the ablation decisive (battery change)

Add a "battery D" of ladder-reachable-but-v3-blockable targets: parity-of-count
variants, `sum(g)%k` threshold composites, and walsh-of-subset targets whose
solving feature is in the ladder (walsh/world_sum/pair) while correlated
mod-synth/pipeline columns push the v3 greedy basis over COVER. Alternatively,
admit `xor_popcount` as a ladder feature so the 9 xor targets move from
"unreachable in both arms" into the decidable band.

## Honest scope

- **v4's escape-authentic lane is vacuous for certified escapes.** The lane
  condition (`cov_before < COVER ≤ cov_after`) is identical to the certifier's
  escape condition, so post-revision every certified escape survives the tax
  by construction — measured: 0 post-revision blocks, novel rate 100%. The
  ablation shows this revision is load-bearing for solves (v3 remix-blocking
  was blocking real certified escapes), **not** that the revised gate retains
  any novelty discrimination among certified escapes. "Framework revision"
  here = witnessed retirement of remix-blocking for certified escapes, plus
  family-conditioned remix tests.
- The revision trigger crosses at the second target in every run; ARM-ON is
  effectively "v4 from target 2 onward." The trigger adds auditability
  (witnessed, ledgered), not a delicate decision boundary.
- One robust witness (C08) + one marginal indirect witness (B10, 1/3 seeds).
  Claim supported: *framework revision is load-bearing at this budget on this
  battery*. Claim NOT supported: revision broadly unlocks battery C (xor family
  remains 0% in both arms on the ladder slice).

## Files

- Harness: `sparse_poly_discovery/tier8_ablation.zig`
- CSV (132 rows: 3 seeds × 2 arms × 22 targets): `results/tier8_ablation_2026_07_10.csv`
- Ports/reads (unmodified): `equivalence_tax.zig`, `invention_engine.zig`,
  `unified_invention.zig`, `open_invention_tier8_battery_c.zig`,
  `closure_revision.zig`, `framework_vote.zig`, `remix_rate_monitor.zig`
