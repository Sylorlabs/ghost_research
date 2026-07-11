# Smart generation — can a GUIDED generator find the stone blind bulk couldn't? (round 2026-07-11 headline)
> **Belongs to: Round 2026-07-11 · experiment E3 of 6 (smart generation for auto-discovery)** — [round index](../../../docs/research/research_round_2026_07_11.md).

**Status:** built, measured. Reproduce (standalone, single-threaded, ≤2 cores):
```bash
cd wcore && zig build-exe -O ReleaseFast src/smart_gen.zig -femit-bin=bin/smart_gen
./bin/smart_gen selftest
./bin/smart_gen run grad         ../results/smart_gen_2026_07_11.csv 0xA70F 0x5EED2
./bin/smart_gen run prior_weak   ../results/smart_gen_2026_07_11.csv 0xA70F 0x5EED2
./bin/smart_gen run prior_strong ../results/smart_gen_2026_07_11.csv 0xA70F 0x5EED2
./bin/smart_gen run cover        ../results/smart_gen_2026_07_11.csv 0xA70F --rounds=5   # fair L3 base
./bin/smart_gen run cover        ../results/smart_gen_2026_07_11.csv 0x5EED2 --rounds=5  # 2nd seed
./bin/smart_gen run cover        ../results/smart_gen_2026_07_11.csv 0xA70F --rounds=5 --l3=uniform  # ablation
```
Each `run` invocation finished well under the 15-minute-per-run cap (grad 9m33s/2 seeds,
prior_strong 6m40s/2 seeds, prior_weak ~6m/2 seeds, cover-fair 6m0s and 5m42s/seed,
cover-uniform 12m46s/1 seed).

## The pivot from D5 (`auto_curriculum.md`)

D5 proved that **blind bulk generation cannot auto-discover the decomposition** for the
distinct-count conjunction wall: 54,432 mechanism-blind candidate-behaviours (pure-random
+ archive-prefixes, up to 1000 random/round) produced **zero** payoff and **zero** frontier
lift over control (F 0/9, both seeds). Crucially, D5 localised the failure precisely to
**GENERATION, not DETECTION**: its positive control showed the certify+payoff apparatus
recognises the real hand stones on contact (S1 `membership` → payoff 0/7, necessary-but-
insufficient; S2 `noveltyflag` → payoff 6/7, sufficient). The needle exists and the detector
works; blind sampling just never lands on it.

E3 asks the successor question: **can a SMART (guided) generator cross where blind bulk
failed?** It reuses D5's certify+payoff detection apparatus **verbatim** (every ported
function is byte-for-byte unchanged; the selftest re-derives S1 payoff 0/7 and S2 payoff 6/7
through it from scratch) and varies **only the generator**.

## The four guided generators (only the candidate SOURCE differs; detector is D5's)

| arm | generator | the "insight" it encodes |
|-----|-----------|--------------------------|
| **GRAD** | hill-climb on an INTERMEDIATE-behaviour objective — `0.6·hasRMWShape + 0.4·memSensitivity` (structural read-then-write-same-address shape + a history-sensitivity probe), NOT raw payoff (D5's flat surface) — 40 chains × 40 accept-if-≥ steps, whole climb path fed to the detector | "reward maintaining per-symbol state / a sub-conjunction" (a climbable surface where payoff has none) |
| **PRIOR_WEAK** | the substrate's own `alien.Params.mem_bias=0.5` proposer (load/store MORE LIKELY per instruction) — the lever D5 deliberately left unused | "memory ops matter" as a per-instruction probability |
| **PRIOR_STRONG** | `forceRMW`: one load + one later store to the SAME address register injected into every candidate; everything else random | the literal membership signature (read-then-write same cell) — the smallest STRUCTURAL prior |
| **COVER** | exhaustive systematic enumeration of every distinct-BEHAVIOUR small program (length 1,2,3), deduped by FULL-machine-state fingerprint, over a reduced alphabet (4 registers, 2 immediates, all 19 ops) | "small programs use few registers/constants; test every distinct short behaviour once" |

All four still run through the identical certify (depth-3 novelty AND depth-4 gate) +
payoff (real depth-≤3 reachability vs the unsolved wall family) + promote-or-fallback loop
as D5, so frontier reach is directly comparable to D5's 0/9 and the hand-curriculum's 6/9.

## Instrument fidelity (`selftest`, all as expected)

```
baseline WALL reachability (base atoms only) = 0/7            (expect 0)
membership(S1):  certifiable=yes  payoff=0/7                  (necessary, insufficient — matches round c/D5)
noveltyflag(S2): certifiable=yes  payoff=6/7                  (the sufficient stone — matches round c/D5)
genuineness(noveltyflag): agree_s1=0.000  agree_s2=1.000      (behavioural complements, as measured before)
hasRMWShape(membershipProg)=true   hasRMWShape(alienXorScan)=false
memSensitivity: noveltyflag=0.027  xorscan=0.000  constant-zero-prog=0.000
forceRMW always yields hasRMWShape: PASS (200/200)
COVER distinct behaviours by length (exhaustive L1,L2; L3 from 1000-program base): L1=208  L2=22345  L3=104935
COVER pool composition by step length: len1=208  len2=22345  len3=3604
COVER (fair) pool contains an OUT_R-equivalent of noveltyflag: YES (2 such programs)
```

Two honest wrinkles found while building the COVER instrument (documented, not asserted —
the same spirit as D5's own stepPrefix caveat):

1. **`load` from fresh-zero memory is behaviourally a no-op.** Memory starts all-zero, so at
   short lengths a `load` reads 0 always and is indistinguishable from a constant-zero
   instruction — a behaviour-dedup keyed on observed state collapses `load` into the no-op
   class before its latent capability (reading a value a *later* instruction stores) is ever
   exercised. This is D5's "mechanism doesn't route to output until its last instruction"
   wrinkle, one level deeper. **Fix:** the state fingerprint probes additional variants with
   the memory bank PRE-SEEDED nonzero, so a real `load` diverges from a no-op immediately.
2. **The coverage explosion is real and is itself the central COVER finding.** L1 and L2 are
   small (208 and 22,345 distinct behaviours — enumerated EXHAUSTIVELY). Extending all 22,345
   L2 programs to L3 is ~217M candidate fingerprints and **does not finish inside the 15-min
   cap** (measured: killed at 10m+ with no output). So the L3 expansion base is capped at 1000
   L2 programs.

## Result — the headline table

Frontier reach (F, of the 9 frontier targets) after the promotion rounds, vs the two
reference points D5 established:

| arm | F reach /9 | E reach /9 | stone discovered? | seeds |
|-----|-----------|-----------|-------------------|-------|
| D5 **blind bulk** (reference) | **0** | 4–5 | none (0 in 54,432) | both |
| hand-curriculum (reference, `conjunction_wall.md`) | **6** | 4 | hand-designed S1→S2 | both |
| **GRAD** (hill-climb intermediate objective) | **0** | 5 | none | both |
| **PRIOR_WEAK** (`mem_bias=0.5`) | **0** | 5 | none | both |
| **PRIOR_STRONG** (forced load;store signature) | **0** | 4–5 | none | both |
| **COVER — fair** (exhaustive + RMW-shaped L3 inclusion) | **6** | 4–5 | **len-4 noveltyflag-equiv, round 1** | **both** |
| **COVER — uniform** (exhaustive, no structural prior) | **0** | 4 | none | 0xA70F |

Every arm reports many depth-3 survivors (`n_d3` in the hundreds–thousands per round), but
`n_payoff_pos = 0` in every round of every FAILING arm — verified against the raw CSV
(`awk -F, 'NR>1 && $6>0'` returns only the two COVER-fair round-1 rows). The failing arms
degenerate to D5's control mechanism exactly (F 0/9, same E-transfer trajectory), the built-in
falsifiability check.

### The one that crosses: COVER-fair

Round 1, **both seeds**, auto-discovered this stone (printed verbatim by the run):
```
setup: r2=1;
step:  r3=mem[r0];  mem[r0]=r2;  r3=a_xor(r2,r3);
```
- **payoff 6/7**, `agree_s1=0.000`, `agree_s2=1.000` → it is the *sufficient* stone
  (behaviourally identical to `noveltyflag` on OUT_R), NOT the insufficient `membership`.
- **F jumps 0/9 → 6/9 in a single round** — the exact same jump, to the exact same 6 wall
  targets (distinct, dist→gxor, gadd→dist, dist→dist, dist→rmw, shift→dist), as round c's
  hand-designed curriculum. The 7th wall member (shift→dist→gxor) is a depth-4 composition
  outside the depth-≤3 reach, unreached by the hand-curriculum too.

**Genuineness (verified, not asserted):**
- Discovered by exhaustive enumeration over the reduced alphabet — the hand stones
  (`membershipProg`/`noveltyFlagProg`) are verification-only and are NEVER seen by the
  generator, certifier, or payoff test.
- **Structurally distinct from the hand stones**: it allocates the constant-flag to `r2`
  where the hand `noveltyFlagProg` uses `r6`, and its xor is `xor(r2,r3)` vs the hand
  `xor(r3,r6)` — an independent register allocation that is behaviourally equivalent (xor
  commutes). This is the strongest possible evidence it was rediscovered, not injected.
- **Clean at depth 4**: retro-reduction audit reports `prefix_d4=holds` on the discovered
  atom and `leaks=0/5` across all promoted atoms, both seeds — it is genuinely irreducible
  relative to the base library at the +1-depth gate, not a disguised composition.

## Why the failing arms fail, and why COVER-fair succeeds — the precise diagnosis

The result is **not** "smart generation also fails" (that is true only of gradient and
prior-sampling) and **not** "smart generation trivially works." It is sharper:

1. **GRAD fails** because the intermediate objective, while climbable (its `hasRMWShape`
   term does give a step up), tops out at "has the read-then-write shape and carries state"
   — a plateau shared by an enormous set of programs, almost none of which route the flag to
   OUT_R the way the sufficient stone does. The climb reaches the shape but not the specific
   3-instruction output wiring; there is no gradient from "has RMW shape" to "IS noveltyflag."

2. **PRIOR_WEAK / PRIOR_STRONG fail** even though PRIOR_STRONG forces the *exact* load;store
   membership signature into every candidate. Injecting the signature into **random** programs
   (12 registers, 13 immediates, random surrounding instructions and output routing) leaves
   the completion — the third instruction that turns membership into noveltyflag, wired to
   OUT_R with the right constant — a needle in the full-width random space. A signature-shaped
   *sampling bias* is not enough; the surrounding structure is still random.

3. **COVER-fair succeeds** because it does the one thing sampling cannot: over a **reduced
   alphabet** (4 registers, 2 immediates) it **exhaustively** tests every distinct third-
   instruction behaviour on top of the load;store lineage, deduped by full machine state —
   so the xor that completes the stone is enumerated **by construction**, exactly once, and
   handed to the (correct) detector. Exhaustiveness over a small alphabet converts "needle"
   into "guaranteed hit."

4. **But COVER-fair needs the RMW-shape prior — coverage alone (COVER-uniform) fails 0/9.**
   This is the load-bearing honest caveat. The L3 level (length-3 programs) is where the
   *sufficient* stone lives, and even over the reduced alphabet its distinct-behaviour count
   is >10^5 — too large to enumerate fully in budget, so only 1000 of the 22,345 exhaustive-L2
   programs are expanded to L3. **COVER-fair** includes every RMW-shaped L2 program (the
   load;store-same-address lineage) in that 1000 first; **COVER-uniform** takes a uniform
   random 1000 and gets F 0/9 — the specific load;store prefix the stone extends is not in the
   sample. So the smallest prior that actually works is **exhaustive behaviour-deduped coverage
   over a reduced alphabet PLUS a mechanism-shaped inclusion for the level where the sufficient
   stone lives.** Neither ingredient suffices alone: coverage-without-prior = 0/9 (uniform),
   prior-without-coverage = 0/9 (PRIOR_STRONG).

### The generation-hardness diagnosis (what makes this problem hard)

The distinct-count stepping stone is hard to *generate* — not to *detect* (D5) and not to
*represent* (the reduced alphabet expresses it) — for three compounding reasons:

- **No gradient (round b) and no partial payoff (D5):** the sufficient stone only pays off
  once all three instructions are present AND the flag is routed to OUT_R; every proper
  approximation scores 0, so hill-climbing and residual-climbing both plateau.
- **The completion is a needle in a wide random space:** even given the load;store signature
  (PRIOR_STRONG), the specific OUT_R-wiring third instruction is one point among the full
  register×immediate×op product with random padding — sampling misses it at 54k+ draws.
- **Exhaustive coverage is tractable only to length 2:** distinct behaviours explode
  208 → 22,345 → >10^5, so the length-3 level (where the sufficient stone lives) cannot be
  fully enumerated in budget. Closing the last gap requires steering the length-3 expansion
  to the mechanism lineage — i.e. a mechanism-shaped prior.

**The bound this places on machine auto-discovery:** the human insight is *partially*
dispensable — COVER rediscovered the noveltyflag mechanism from scratch, no hand stone, with
a different register allocation. But it is not *fully* dispensable: crossing required
(a) a generic small-alphabet restriction and (b) a mechanism-signature structural inclusion
at the one intractable level. Blind bulk (D5), gradient, and signature-*sampling* all fall
short; only exhaustive coverage *steered by the mechanism signature* crosses. The scarce
ingredient is not compute or quantity but a **structural prior precise enough to make the
sufficient-stone level exhaustively searchable** — the smallest such prior found here is the
read-then-write-same-address signature, applied as a coverage inclusion rather than a
sampling bias.

## Honest limitations

- **COVER's reduced alphabet (4 regs, 2 imms) is itself a mild prior.** It encodes "small
  programs use few registers/constants," which is generic but not nothing; the full 12-reg /
  13-imm alphabet is not exhaustively coverable at length 3 in any tractable budget.
- **The L3 base cap (1000 of 22,345) is a compute concession**, and the RMW-shape inclusion
  inside it is exactly the prior under test — COVER-uniform is the honest ablation showing the
  inclusion is load-bearing (0/9 without it). A larger budget that exhausted L3 uniformly is
  untested and could in principle find the stone without the shape inclusion; the finding is
  bounded to the ~15-min single-machine regime this arc uses throughout.
- **COVER's payoff is seed-independent by construction** (the payoff/reachability check uses
  the fixed RSEED; the enumeration is deterministic), so 1 seed settles the COVER-uniform
  question and COVER-fair was confirmed identical on both seeds. The archive-prefix half of
  every pool still varies by seed, shared with all arms.
- **cover-fair was run at `--rounds=5` (not 8)** to fit the cap given its ~2-min rounds; 5
  rounds is ample — the stone is found in round 1 and 5 rounds fully cover the enumerated pool.
  Gate-polish budget in the ctrl-equivalent fallback was trimmed once more from D5
  (POLISH 4→3 chains, 3000→2000 neigh/greedy) since this file runs four arms; the discovery
  path never touches gate-polish, and every arm's fallback reproduces D5's F 0/9 control.
- **Behaviour matching is 0.95 agreement on 8×28 streams** (same statistical caveat as every
  file in this arc), and the full-machine-state dedup is *finer* than that payoff equivalence,
  so the pool over-represents behaviours per payoff-class (which helps coverage).
- 2 seeds, one substrate, one battery (18 targets ported verbatim), one depth budget
  (payoff ≤3, gate ≤4) — the same bars every arm in this arc uses, for comparability.

## Verdict

**Smart generation CAN cross where blind bulk failed — but only exhaustive behaviour-deduped
coverage does, and only when a mechanism-shaped structural prior makes the sufficient-stone
level searchable.** Gradient (0/9), memory-bias sampling (0/9), and even forced-signature
sampling (0/9) all fail exactly like D5's blind bulk. Exhaustive coverage over a reduced
alphabet, with the read-then-write signature steering the one intractable level, crosses
0/9 → 6/9 on both seeds — matching the hand-designed curriculum — and rediscovers the
noveltyflag mechanism from scratch (genuine, structurally distinct from the hand stone, clean
at depth 4). The precise bound: machine auto-discovery here needs neither the hand-written
stone nor more compute, but it does need the mechanism's structural signature as a search
prior — the smallest working prior is the load;store-same-address shape, applied as a coverage
inclusion. That prior is a strictly smaller "insight" than the hand curriculum (which supplied
the *finished* S1→S2 programs), so the frontier moves — but it does not vanish.

## Files
- `wcore/src/smart_gen.zig` — the experiment (`selftest` / `run <grad|cover|prior_weak|prior_strong> <csv> [seeds] [--rounds=N] [--l3=uniform|fair]`)
- `results/smart_gen_2026_07_11.csv` — every round of every arm (generator × seed), plus the `cover_uniform` ablation
