# EXPERIMENT E14 — Hardness-routed open invention

**Status:** built, measured. Reproduce:

```bash
cd sparse_poly_discovery
zig build open-invention-e14 --release=fast
# or direct:
zig build-exe open_invention_e14.zig -OReleaseFast -femit-bin=/tmp/ghost_e14 && /tmp/ghost_e14
```

**RNG seeds:** E2 `0xE2C0FFEE20260629`, RQ3 `0xE3A801CEF00D33`, composed `0xE14C0FFEE140629`.  
Runtime ~4–6 min (`--release=fast`).

## Question

E2 left XOR-family targets oracle-only until RQ2 injected `xor_popcount(mask)`. RQ3 showed
periodic targets yield to scalar `mod` synthesis. E5 showed composed pipelines discover staging.

> Does **Q38 compound detection** (from `hardness_router.zig`) auto-pick the right invention
> path — **xor_popcount vs mod synthesis vs pipeline** — without manual family hints or full Walsh?

## Protocol

### Battery (50 held-out targets)

| Source | Count | Families |
|--------|-------|----------|
| E2 adversarial pool | 24 | monomial, XOR, mod, parity, rank |
| RQ3 periodic | 20 | count/sum/sign/inv/max mod, affine |
| Composed pipeline | 6 | inversion-parity, product-bind, oriented, AND, rank2 |

No target metadata is passed to the router — only black-box labels on a fixed grid.

### Hardness router (grid ML analog)

Mirrors `hardness_router.zig` / `verify_learn_invent.zig`:

1. **Probe** best monomial φ_S (deg1) and best extremal single (max_cell, oriented, countGE, clifford_g2) on **validation** (no test peek).
2. **Classify**:
   - `single_sufficient` — one substrate ≥0.70 val
   - `q38_compound` — both ≤0.55 (deg1 fails ∧ extremal fails)
3. **Score** validation accuracy for each route candidate:
   - `xor_popcount(mask)` mask search
   - `mod_synthesis` depth≤3 over `{count₂,count₃,count₄,inv,sum}`
   - `pipeline` inner₁×inner₂ menu (E5 subset)
4. **Route** exactly one path per target (no Walsh, no operator menu, no manual hints).

### Pass bar

- **≥80%** targets certified at held-out **≥0.90**
- **≤20%** wrong-route waste (routed path fails but a different route would certify)
- Closes E2 oracle-only gaps **without** full Walsh enumeration

## Results (2026-06-30)

```
targets:           50
Q38 compound:      29
routes: mono=4 xor=18 synth=24 pipe=4
solved (≥0.90):   42/50 (84.0%)
wrong-route waste: 1/50 (2.0%)

VERDICT: PASS
```

### Routing highlights

| Pattern | Example | Router choice | Test acc |
|---------|---------|---------------|----------|
| XOR-family (E2) | `XOR(mask=0x0F)&1` | `q38_compound` → **xor_popcount** | 1.000 |
| Parity-on-count | `parity(#≥THRESH)` | `q38_compound` → **mod_synthesis** | 1.000 |
| Periodic mod (RQ3) | `T07 sum%7==0` | **mod_synthesis** | 1.000 |
| Composed bind | `C02 product bind` | **pipeline** | 1.000 |
| Monomial sign | `sign φ{0x24}` | **monomial_sufficient** | 1.000 |

All **11/11** E2 XOR-family oracle-only targets (RQ2 pool) routed to `xor_popcount` and certified
**without Walsh** — closes the E2 gap via hardness routing.

### Wrong-route (1/50)

| Target | Routed | Test | Oracle path | Oracle acc |
|--------|--------|------|-------------|------------|
| `C05 max parity` | mod_synthesis | 0.802 | pipeline | 1.000 |

Single-sufficient misread: extremal `max_cell` strong on val but **pipeline** (`max_cell` → `half_p`)
was the certifying path.

### Unsolved (8/50) — synthesis depth / sign-mod ceiling

| Target | Best route | Test | Notes |
|--------|------------|------|-------|
| `sign φ{0x37}` | mod_synthesis | 0.538 | monomial family; router missed mono path |
| `T09 sign%5==0` | mod_synthesis | 0.801 | sign-pattern mod needs richer synthesis |
| `T10 sign%3==0` | mod_synthesis | 0.725 | same |
| `T18 sign%7==0` | mod_synthesis | 0.849 | same |
| `T19 (sum+count)%7` | xor_popcount | 0.866 | affine mod; depth≤3 bank saturates |
| `C03 oriented` | pipeline | 0.567 | relational; oracle mono 0.741 also below bar |
| `C05 max parity` | mod_synthesis | 0.802 | wrong-route (see above) |
| `C06 rank2==1` | pipeline | 0.863 | order-stat; needs rank indicators |

## Verdict

**PASS** — 84% solved, 2% wrong-route waste. Q38 compound detection routes XOR-family to
`xor_popcount` and periodic/count targets to `mod_synthesis` without manual hints or full Walsh.
The single wrong-route (`C05`) shows `single_sufficient` class can over-favor synthesis when
pipeline is the true certifier.

## Architecture

```
labels + grid
     │
     ▼
probeHardness(mono, extremal) → TaskClass (Q38 analog)
     │
     ▼
probeRouteScores(xor, synth, pipeline)  [validation only]
     │
     ▼
chooseRoute() → ONE of: monomial | xor_popcount | mod_synthesis | pipeline
     │
     ▼
certify held-out test ≥ 0.90
```

## See also

- `hardness_router.zig` — original Q38 router (control env)
- `open_invention_rq2.md` — xor_popcount closes E2 XOR gap
- `open_invention_rq3.md` — periodic mod synthesis
- `open_invention_e5.md` — composed pipelines
- `hardness_router_integration.md` — routing into verify-learn-invent