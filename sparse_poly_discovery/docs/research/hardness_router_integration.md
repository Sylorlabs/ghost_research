# Hardness Router Integration into VERIFY-LEARN-INVENT

**Status:** integrated and measured (June 2026).  
**Reproduce:** `cd boundary_crossing && zig build verify-learn-invent --release=fast`

## What was wired

`sparse_poly_discovery/hardness_router.zig` classifies control tasks by substrate hardness
(deg1 fails ∧ extremal fails ∧ cross-class pair succeeds — the Q38 compound pattern). That
logic is now replicated **inline** in `boundary_crossing/verify_learn_invent.zig` for grid
predicate discovery, without importing `environment.zig` / `agent.zig`.

English intents `discover_feature` / `explore unknown pattern` now:

1. **Probe** monomial (deg1) and extremal singles (max_cell, oriented, countGE, clifford_g2).
2. **Classify** task hardness:
   - `single_sufficient` — one substrate class clears ≥0.70 held-out.
   - `q38_compound` — both classes saturate near chance (≤0.55) → compound escape needed.
3. **Route** through an escalation ladder (mirrors `unified_invention.zig`):
   - `monomial_sufficient` — deg1 certifies at ≥0.90.
   - `operator_menu` — mono saturated → spectral / Walsh / Clifford.
   - `pair_compound` — Q38 compound, menu failed → cross-class pair (φ_S + extremal).
   - `world_pool` — mod_p divisibility on grid sum / sign pattern.

`unified_invention.zig` is linked as a module for the 7-target benchmark and as a fallback
certifier; the **routing decision** is made by the local hardness probe.

## Thresholds (grid domain)

| Constant | Value | Role |
|----------|-------|------|
| `MONO_SATURATE` | 0.55 | Monomial forge near chance → escalate to operator menu |
| `SINGLE_SUFFICIENT` | 0.70 | One substrate class alone is informative |
| `CERT_THRESHOLD` | 0.90 | Held-out certifier (matches operator_menu / unified_invention) |

Analog to `hardness_router.zig` Q38 thresholds (`Q38_FAIL_SINGLE=25/1k`, `Q38_SUCC_PAIR=50/1k`)
but expressed in held-out accuracy because the grid ML certifier uses logistic held-out acc, not
RL fail-rate per 1k steps.

## Measured routing decisions (Phase 2b, June 2026 run)

```
parity-of-count: mono=0.531 ext=0.500 class=q38_compound → route=operator_menu acc=1.000 CERTIFIED
sum(g)%7:        mono=0.849 ext=0.849 class=single_sufficient → route=world_pool   acc=1.000 CERTIFIED
sign φ{c3}:      mono=1.000 ext=0.615 class=single_sufficient → route=monomial_sufficient acc=1.000 CERTIFIED
```

Interpretation:

- **Parity** — monomial closure saturates (~0.53); Q38 compound; operator menu finds
  `spectral(cos(ω·count))` with ω≈π (same escape as `unified_invention` T5).
- **sum_mod world target** — monomial is misleadingly strong (0.85) but below cert; menu does
  not certify; world pool promotes `sum%mod_7` (same as `unified_invention` T7).
- **deg1 monomial** — router stops at forge; no menu/world needed.

## Unified invention cross-check (Phase 2c)

```
inner_forge alone: 5/7 solved
unified loop:      7/7 solved
unlocks beyond monomial: T5 parity-of-count [menu], T7 sum(g)%7 [world]
```

The inline hardness router and the full unified loop agree on which phase solves the hard targets.

## Architecture sketch

```
English "discover / explore"
        │
        ▼
  intent router (perceptron + verify-learn)
        │
        ▼
  probeHardness(mono, extremal)
        │
        ├─ mono acc ≥ 0.90 ──────────────► monomial_sufficient
        ├─ mono ≤ 0.55 ──► operator_menu ─► certified?
        ├─ q38_compound ──► pair_compound ► certified?
        └─ else ──────────► world_pool ───► certified?
        │
        ▼
  verifier label → verify-learn weight update
```

## Files

| File | Role |
|------|------|
| `sparse_poly_discovery/hardness_router.zig` | Original Q38 router (dual-band control env) |
| `sparse_poly_discovery/unified_invention.zig` | forge → menu → world certifier (7 targets) |
| `boundary_crossing/verify_learn_invent.zig` | English front-end + inline hardness routing |
| `boundary_crossing/docs/research/verify_learn_invent.md` | End-to-end benchmark documentation |

## Honest limits

- Grid routing uses held-out logistic acc, not RL fail-rate; thresholds are calibrated to match
  `unified_invention`, not `hardness_router` step counts.
- Pair route is probed on Q38 compound tasks only; current measured suite certifies via menu or
  world before pair is needed.
- NL → target kind (parity vs sum_mod vs monomial) is not parsed from English yet; discover
  intents default to hidden parity with routing driven by probes, not target metadata.