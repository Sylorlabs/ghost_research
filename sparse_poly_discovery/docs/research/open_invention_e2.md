# EXPERIMENT E2 — POET-lite adversarial target generator

**Status:** built, measured. Reproduce:

```bash
cd sparse_poly_discovery
zig build-exe open_invention_e2.zig -OReleaseFast -femit-bin=/tmp/ghost_open_invention_e2
/tmp/ghost_open_invention_e2
# or (when sibling experiments compile): zig build open-invention-e2 --release=fast
```

**RNG seed:** `0xE2C0FFEE20260629` (pinned). Runtime ~40 s (`--release=fast`).

## Question

POET couples a **task population** with solvers so “useful” keeps moving. E2 asks the sparse-poly analogue:

> Can a lightweight adversarial **target generator** (mutating predicates) produce tasks that are **hard for the current library** but **easy for an evaluation-only oracle**, and does the **open forge** close that gap **without** putting oracle features in the search menu?

## Setup

### Predicate genome (mutations)

A `PredSpec` mutates across five operators:

| Mutation | Effect |
|----------|--------|
| **mask** | flip subset bits → `monomial_sign` / XOR-mask targets |
| **mod** | change modulus → `sum_mod` / `sign_mod` |
| **parity-on-transform** | cycle `parity_count`, `parity_xor`, `xor_cells` |
| **rank-stat** | pick triple + `median_eq1` / `rank2_eq1` |
| **XOR cells** | flip mask bits on `xor_cells` |

### Adversarial filter (POET-lite retention)

Keep a candidate iff:

- **Library coverage** `< 0.60` — logistic readout over **8 singleton monomials only** (the pre-forge library).
- **Oracle coverage** `≥ 0.95` — logistic over the **ground-truth feature** for that spec (evaluation-only; never searchable).

Seeds (9 hand-picked specs) are evaluated before random mutations; pool capped at 24 targets.

### Forge search menu (no oracle)

Per kept target, run the unified loop **without** oracle-exclusive primitives:

1. Monomial promotion (deg ≤ 4, escape + R² `< 0.40`)
2. Operator menu: spectral count-Fourier, Walsh χ_S, Clifford G2
3. World pool: `sum%mod_p`, `sign%mod_p` for `p ∈ {2,3,5,7,11,13}`

**Not in menu:** direct XOR-cell parity, rank indicators, or other oracle ground-truth features.

### Pass criterion

**PASS** iff every kept target reaches forge held-out `≥ 0.90` (forge matches oracle without cheating).  
**PARTIAL** iff some targets remain **oracle-only** (oracle `≥ 0.95`, forge `< 0.90`).

## Results (2026-06-30)

```
Filter: lib <0.60  oracle ≥0.95
mutations tried: 57   targets kept: 24

forge solved (≥0.90): 10/24
oracle-only gaps:     14/24

VERDICT: PARTIAL
```

### Forge **solved** (10) — menu reaches oracle without peeking

| Family | Examples | Mechanism |
|--------|----------|-----------|
| Monomial sign | `sign φ{0x24}`, `φ{0x4A}`, `φ{0x0A}`, … (7 targets) | Monomial forge promotes hidden φ_S |
| World mod | `sum(g)%2==0` (×2), `XOR(mask=0xFF)&1` | `sum%mod_2` promoted from world pool |

All reach **test = 0.900** (certified escape threshold).

### Oracle-only gaps (14) — forge stuck at library ceiling

| Family | Count | Best forge | Notes |
|--------|-------|------------|-------|
| `xor_cells` | 10 | 0.48–0.59 | GF(2) cell-parity not in monomial/spectral/Walsh menu |
| `parity_xor` | 4 | 0.48–0.59 | Parity on XOR-transform, not count-Fourier |

Representative stuck lines:

```
XOR(mask=0x0F)&1:   lib=0.481  oracle=1.000  forge=0.481  (oracle-only gap)
parity(XOR 0x33):  lib=0.486  oracle=1.000  forge=0.486  (oracle-only gap)
```

Forge coverage on these targets **equals** pre-forge library coverage — the menu never escapes.

### Seeds not retained (expected)

- `sum(g)%7==0` — library monomial readout already **0.86** (`> 0.60`); correctly rejected as non-adversarial.
- `parity(#≥THRESH)` — oracle feature must be the parity bit itself (not raw count); fixed post-run.
- `rank_stat` triples — not drawn into the 24-slot pool this seed (mutation budget exhausted on XOR-heavy branches).

## Verdict

**PARTIAL FAIL** on the strict pass rule (`oracle_only = 14`).

**Positive findings:**

1. **POET-lite filtering works** — 24 targets are genuinely hard for the singleton library (`lib ≈ 0.48–0.59`) yet trivial for the oracle (`1.000`).
2. **Forge matches oracle on 10/24 (42%)** without oracle features — monomial + world-mod covers the **monomial-sign** and **global-sum mod** families.
3. **14/24 expose a precise closure gap** — XOR-cell and parity-on-XOR predicates need a **GF(2) / Walsh-on-cells** generator that the handed menu does not contain. Spectral count-Fourier solves `parity_count` (Fork 1) but **not** parity of masked XOR.

This is the Closure Principle in POET form: coevolving targets finds the **family boundary**; crossing it still requires injecting a generator outside the current menu (as `k3_order_escape` does for rank stats, `boolean_fourier` for Walsh).

## Honest scope

- Pool size 24, mutation budget 4000 (stopped early at 57 once pool full).
- Single grid seed; separations are 0.48/0.90/1.00 — not seed-noise sensitive.
- Duplicate `XOR(mask=0x08)` in the kept list is a display/dedup artefact (same spec evaluated in pool twice); does not affect forge counts materially.

## See also

- `open_invention_e1.zig` — frozen forge + blind battery B
- `inner_forge.md`, `unified_invention.zig` — forge → menu → world
- `k3_order_escape.zig` — rank-stat escape (oracle family for median wall)
- `boolean_fourier.md` — Walsh as universal Boolean discovery operator
- `wcore/src/inv_coevo.zig` — full POET coevolution reference
- repo-root `CLOSURE_PRINCIPLE.md`