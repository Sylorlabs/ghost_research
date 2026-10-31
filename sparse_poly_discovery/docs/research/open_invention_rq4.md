# RESEARCH Q4 — E4 equivalence oracle

**Status:** built, measured. Reproduce:

```bash
cd sparse_poly_discovery && zig build open-invention-rq4 --release=fast
```

(~5 s, mint seed `0xE4CE11ED0FF1CE42`, oracle grids `0x0BAC1E04EEDFACE4`)

## Question

E4 certifies and promotes synthesized VM programs as opaque menu primitives. **Are those
minted programs genuinely distinct from the VM closure**, or just relabeled compositions
already expressible at depth≤6?

**Oracle:** for each E4-promoted program, search the depth≤6 VM expression pool for any
program whose outputs match on **10 000** random grids within **ε = 1e-6**.

**Pass bar for "real minting":** **<50%** of promotions VM-equivalent (majority must be
genuinely outside depth≤6).

## Protocol

| Stage | Setting |
|---|---|
| Minting | E4 protocol unchanged: depth≤5 synthesis, escape≥0.90, R²<0.40, 20 hard targets |
| Oracle VM | Same substrate: `cell`, `thresh`, `compare(>)`, `mul`, `add`, `sum`, `parity`, `min`, `max`, `rank_k` |
| Oracle search | Depth≤6 pool (8192 unique after 256-grid dedup), quick-filter 24 grids → full 10k verify |
| Tolerance | ε = 1e-6 on scalar outputs |

## Results (2026-06-29 run)

```
E4 minting: 2 promoted programs, library 8 → 10

equivalence oracle (10k grids):
  G00: (sum*parity)              depth 2 → EQUIVALENT (witness: sum*parity, max|Δ|=0)
  G06: ((c0+c0)*(rank_6>rank_5)) depth 3 → EQUIVALENT (witness: same tree, max|Δ|=0)

VM-equivalent:     2/2 = 100.0%
Genuinely distinct: 0/2 =   0.0%
Pass bar (<50%):   FAIL
```

### Minted program list

| Target | Program | E4 family tag | Mint depth | Oracle verdict |
|---|---|---|---|---|
| G00 | `(sum*parity)` | `composed_known` | 2 | VM-equivalent |
| G06 | `((c0+c0)*(rank_6>rank_5))` | `genuinely_new`* | 3 | VM-equivalent |

\* E4 behavioral tag `genuinely_new` means "no simple 1–2 leaf template match" — **not**
outside the VM closure.

## Verdict

**FAIL — not real minting.** **100%** of E4 promotions are functionally recoverable from
depth≤6 VM on 10k held-out grids. Certified minting adds **opaque menu entries** inside a
fixed compositional substrate; it does **not** import new generators (no cos, Walsh, monomial
forge, or world-pool extensions).

This formalizes the structural caveat in `open_invention_e4.md`: promotions are selection +
certification over a **closed VM**, not algebraic invention.

## Relation to other RQs

- **E4** — shows minting *helps* (0% → 90% solve rate with 2 promotions).
- **RQ4** — shows minting does *not* escape the VM closure (100% equivalent).
- **RQ9** — asks whether a richer basis (monomial + Walsh + world + VM) reproduces escapes;
  RQ4 isolates the VM-only sub-question.

## Honest caveats

- Oracle pool is **deduped and capped** (8192 programs); witness search is exhaustive within
  that pool, not over the full infinite syntax tree.
- **ε = 1e-6** on float outputs; all matched witnesses had **exact** (0) disagreement on
  integer-valued VM semantics.
- Only **2** promotions on this seed — but both are the structurally interesting cases from E4
  (`composed_known` and behavioral `genuinely_new`).

## See

`open_invention_rq4.zig`, `open_invention_e4.zig`, `open_invention_e4.md`, `open_invention_rq9.zig`