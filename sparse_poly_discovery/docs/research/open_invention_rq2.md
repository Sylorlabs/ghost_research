# RESEARCH Q2 — E2 XOR gap closure (`xor_popcount(mask)`)

**Status:** built, measured. Reproduce:

```bash
cd sparse_poly_discovery
zig build open-invention-rq2 --release=fast
# or direct:
zig build-exe open_invention_rq2.zig -OReleaseFast -femit-bin=/tmp/ghost_rq2 && /tmp/ghost_rq2
```

**RNG seed:** `0xE2C0FFEE20260629` (same as E2). Runtime ~3–5 min (`--release=fast`).

## Question

E2 left **14/24** targets oracle-only (documented run) because the handed forge menu lacks a
GF(2) XOR-cell readout. Walsh χ_S is sufficient but heavy (full 256-coefficient search).

> Does a **minimal** injected primitive — `xor_popcount(mask)` with mask search only — close every
> oracle-only XOR-family gap without adding the full Walsh menu?

## Primitive

```zig
xor_popcount(mask, grid) = (XOR_{i∈mask} g[i]) & 1   // LSB parity of masked cell XOR
```

**Search:** enumerate masks `1..255`, pick best validation logistic accuracy, promote on escape
(held-out test ≥0.90, library <0.90). Escape-only cert for this outer-shell generator (standard
R² irreducibility gate blocks GF(2) lifts).

**NOT in search:** Walsh enumeration, spectral peak, Clifford.

## Setup

- **Pool:** E2 adversarial filter (24 targets, lib<0.60, oracle≥0.95).
- **BEFORE:** `runForgeOnTarget` — E2 menu unchanged.
- **AFTER:** same menu + `tryXorPopcount` round.

## Results (2026-06-30)

```
targets kept:              24
BEFORE forge solved:       13/24
BEFORE oracle-only gaps:   11
closed by xor_popcount:    11/11
XOR-family oracle-only:    11 (closed 11)

VERDICT: PASS
```

### Before / after (oracle-only rows)

| Target | BEFORE | AFTER | |
|--------|--------|-------|---|
| `XOR(mask=0x0F)&1` | 0.481 | 0.900 | CLOSED |
| `parity(XOR 0x33)` | 0.486 | 0.900 | CLOSED |
| `XOR(mask=0x80)&1` | 0.593 | 0.900 | CLOSED |
| `XOR(mask=0xC0)&1` | 0.505 | 0.900 | CLOSED |
| `XOR(mask=0x20)&1` | 0.577 | 0.900 | CLOSED |
| `XOR(mask=0x3B)&1` | 0.487 | 0.900 | CLOSED |
| `parity(XOR 0x73)` | 0.490 | 0.900 | CLOSED |
| `XOR(mask=0x08)&1` | 0.561 | 0.900 | CLOSED (×2 in pool) |
| `parity(XOR 0x02)` | 0.586 | 0.900 | CLOSED |
| `XOR(mask=0x0B)&1` | 0.505 | 0.900 | CLOSED |

Already forge-solved before injection (unchanged): monomial signs (7), `parity_count` (5× spectral),
`sum(g)%2` (2× world pool).

### Note on E2 doc count (14 vs 11)

E2’s archived run reported **14** oracle-only gaps when `parity_count` remained library-saturated.
This seed’s forge now solves `parity_count` via spectral count-Fourier, leaving **11** oracle-only
targets — all `xor_cells` / `parity_xor`. RQ2 closes **11/11** = **100%** of the residual gap.

## Verdict

**PASS** — minimal `xor_popcount(mask)` injection closes every oracle-only adversarial target on
this seed. The closure is **narrow but real**: one mask-parameterized GF(2) readout replaces the
need for full Walsh on XOR-family predicates.

## Implementation bug found (fixed)

Initial readout used `@popCount(xor_sum) & 1` instead of `(xor_sum) & 1`. For multi-bit cell
values these differ (e.g. XOR sum 4 → LSB 0 but popcount parity 1). Correct LSB matches E2
`xor_cells` labels exactly (`7000/7000` agreement on mask 0x0F).

## See also

- `open_invention_e2.zig` — adversarial pool + `runForgeOnTargetWithXorPopcount`
- `open_invention_rq2.zig` — before/after harness
- `open_invention_e2.md` — original PARTIAL verdict
- `boolean_fourier.md` — full Walsh alternative
- `docs/research/open_invention_experiments.md` — E2 gap fork recommendation