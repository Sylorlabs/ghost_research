# Experiment E21 — E4 escape VM post-RQ4

**Status:** built, measured. Reproduce:

```bash
cd sparse_poly_discovery && zig build open-invention-e21 --release=fast
```

(~3–5 min mint seed `0xE4CE11ED0FF1CE42`, oracle grids `0xE21BA51E04EEDFA`)

## Question

RQ4 showed E4 minting is **opaque relabeling inside depth≤6 VM** (100% equivalent).
After expanding the minting substrate with **mod synthesis**, **xor_popcount**, and **pipeline**
generators, can minting produce programs **NOT** equivalent to depth≤8 base VM?

## Protocol

| Stage | Setting |
|---|---|
| Minting | E4 protocol: escape≥0.90, R²<0.40, certify+promote |
| Generator unlock | Round 1: `mod` · Round 2: `xor_popcount` · Round 3: `pipeline` |
| Battery | 42 targets: 15 VM-hard + 12 mod + 10 xor + 5 pipeline |
| Oracle | RQ4-style exhaustive match in depth≤8 base VM on 10k grids, ε=1e-6 |
| Pass bar | **≥1/10** promotions fail depth≤8 equivalence |

Base VM (oracle closure): `cell`, `thresh`, `compare(>)`, `mul`, `add`, `sum`, `parity`, `min`, `max`, `rank_k`.

Expanded minting generators (not in base VM):

- **mod_synth** — scalar depth≤3 over `{count₂,count₃,count₄,inv,sum}` with `mod(·,k)` (RQ3)
- **xor_popcount** — `xor_popcount(mask)` GF(2) readout (RQ2 / E2)
- **pipeline** — composed `inner₁→inner₂` scalar feature (E5)

## Results (2026-06-30 run)

```
Battery: 42 targets (15 VM-hard + 12 mod + 10 xor + 5 pipeline)

Minting (10 promotions before oracle):
  round 0 (VM only):     G12 ((c0+c1)*(c4*parity))           gen=vm
  round 1 (+mod):        G15 mod(count₃,3), G21 mod(inv,3)  gen=mod_synth
  round 2 (+xor):        G27–G34 xor_popcount masks         gen=xor_popcount (7×)

Oracle pool: 8193 programs (depth≤8)

equivalence oracle (10k grids):
  #01 G12 vm expr           → EQUIVALENT (witness depth 3, max|Δ|=0)
  #02 G15 mod(count₃,3)     → ESCAPES depth≤8 VM
  #03 G21 mod(inv,3)        → ESCAPES depth≤8 VM
  #04–#10 xor_popcount      → ESCAPES depth≤8 VM (7/7)

VM-equivalent:     1/10 = 10.0%
Escape depth≤8:    9/10 = 90.0%
Pass bar (≥1/10):  PASS
```

### Generator breakdown

| Generator | Promoted | Escape depth≤8 |
|---|---|---|
| vm | 1 | 0 |
| mod_synth | 2 | 2 |
| xor_popcount | 7 | 7 |
| pipeline | 0 | 0 |

Pipeline unlocked at round 3 but minting stopped at 10 promotions (all from rounds 0–2).

## Verdict

**PASS** — **9/10** promotions escape depth≤8 VM equivalence after generator expansion.

RQ4's negative result (100% VM-equivalent at depth≤6) is **reversed** once mod and xor_popcount
generators enter the minting search space. The single VM-only promotion (`(c0+c1)*(c4*parity)`) remains
VM-equivalent at depth 3 — consistent with RQ4 relabeling inside the closure.

**Interpretation:** Minting **can** produce functions outside the base VM closure when the synthesizer
is given outside generators matched to target shape. It still does not invent new mathematics from
nothing — mod/xor/pipeline are **injected outer-shell generators**, not discovered from void.

## Relation to other experiments

- **E4** — menu minting helps solve rate (0%→90% on VM-hard targets)
- **RQ4** — VM-only minting is 100% equivalent at depth≤6 → not real invention
- **RQ2** — xor_popcount closes E2 XOR gap
- **RQ3** — mod synthesis closes periodic targets
- **E5** — pipeline solves composed families blind
- **E21** — expanding E4 with RQ2/RQ3/E5 generators yields **VM-inequivalent** minted programs at depth≤8

## Honest caveats

- Oracle pool is deduped and capped (8192 programs at depth≤8); witness search is exhaustive within pool.
- Only **1** VM-hard promotion in the 10-promotion window; most escapes come from mod/xor targets once generators unlock.
- Pipeline generator was unlocked but not exercised before the 10-promotion stop.

## See

`open_invention_e21.zig`, `open_invention_e4.zig`, `open_invention_rq4.zig`, `open_invention_rq2.md`, `open_invention_rq3.md`, `open_invention_e5.md`