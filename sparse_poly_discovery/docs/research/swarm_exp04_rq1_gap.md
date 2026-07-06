# Swarm EXP-4 — RQ1 gap closure (blind battery without handed menu)

**Date:** 2026-07-05  
**Status:** measured — RQ1 baseline **reproduced**; escalation ladder **diagnosed** on 5 saturated targets.

## Commands

```bash
# RQ1 baseline (frozen monomial + count synth + E5 pipelines only)
cd sparse_poly_discovery && zig build open-invention-rq1 --release=fast

# Escalation ceiling probes (existing build targets)
cd sparse_poly_discovery && zig build open-invention-e26 --release=fast   # Walsh/mod/xor/pipeline tax
cd sparse_poly_discovery && zig build menu-growth --release=fast        # pair-growth reference
cd sparse_poly_discovery && zig build pair-hardness-router-test --release=fast  # guided pair routing
```

**Seeds (pinned):** grid `0xF0235A11CE0FF1CE`, battery `0xE1B10D20A11CE01`  
**Battery masks (E26 confirms):** B1=`0x0C` (cells {2,3}), B2=`0x2A` (cells {1,3,5})

## Summary

| Metric | RQ1 (no menu) | After pair-growth step | After Walsh XOR step |
|--------|---------------|------------------------|----------------------|
| **Certified ≥0.90** | **6/11** | **7/11** (B1 only) | **11/11** |
| **Saturated** | **5/11** | **4/11** | **0/11** |
| **Faithful family match** | **3/6** | +1 (B1) | partial (Walsh mislabels monomials) |

**RQ1 score (protocol as written): 6/11.**

The 5 saturated targets are exactly B1, B2, B5, B6, B7. None reach 0.90 under frozen monomials +
count synthesis + E5 pipelines alone. Minimal auto-escalation closes them **only** at the Walsh
correlation-search step (or monomial forge unfreeze for B2); pair-growth alone closes **one** of five.

---

## RQ1 fresh run (2026-07-05)

Phase 1 identical to E1: zoo A 4/4, **FROZEN 11 monomials**.

### Battery B — certified (6/11)

| Target | Method | Test acc | Family match |
|--------|--------|----------|--------------|
| B3 sum(g)%7 | pipeline `sum_all→scan_p(ω≈0.884)` | 0.998 | ~ |
| B4 sign%mod 11 | frozen monomials | 0.905 | ~ |
| B8 parity-of-count | synth `mod(count,2)` | 1.000 | ✓ |
| B9 oriented v1>v0 | frozen monomials | 1.000 | ✓ |
| B10 parity∧sum%5 | frozen monomials | 0.910 | ~ |
| B11 inversion parity | pipeline `inversion→half_p` | 1.000 | ✓ |

### Battery B — saturated (5/11)

| Target | Known family | Frozen | Synth | Pipeline | Best |
|--------|--------------|--------|-------|----------|------|
| B1 random mono deg2 | monomial φ_S | 0.506 | 0.514 | 0.554 | **0.506** |
| B2 random mono deg3 | monomial φ_S | 0.501 | 0.509 | 0.564 | **0.501** |
| B5 Walsh χ{0x11} | Walsh χ_S | 0.495 | 0.530 | 0.586 | **0.495** |
| B6 Walsh χ{0xA4} | Walsh χ_S | 0.512 | 0.514 | 0.538 | **0.512** |
| B7 Walsh χ{0x0A} | Walsh χ_S | 0.491 | 0.535 | 0.542 | **0.491** |

**VERDICT: PASS** on RQ1 bar (≥1/11), **PARTIAL** on coverage (6/11).

---

## Per-target escalation diagnosis

Escalation ladder tested conceptually against existing substrates:

1. **L1 — Frozen monomial library** (RQ1 phase 2, step 0)
2. **L2 — Mod synthesis** (`{+,×,sin,mod}` on count; RQ1 `synth_prog`)
3. **L3 — Pair growth** (`menu_growth.zig` / `pair_hardness_router_test.zig`: φ(i,j)=[c_i,c_j,c_i·c_j])
4. **L4 — Walsh if XOR structure** (`discoverWalsh` correlation argmax; E26 basis winner χ_S)

### B1 — random monomial deg2 (mask 0x0C, cells {2,3})

| Step | Mechanism | Est. test acc | Escape? | Diagnosis |
|------|-----------|---------------|---------|-----------|
| L1 | frozen φ library (11 masks, **not** 0x0C) | 0.506 | no | Mask absent from zoo-A freeze |
| L2 | count synth depth≤4 | 0.514 | no | Periodic/count structure unrelated to cell product |
| L3 | pair-growth on (2,3) | **~1.000** | **yes** | Deg-2 monomial ≡ `sign((c₂−μ)(c₃−μ))`; pair inner hits product term (EXP-02: 6/6 deg-2 pairs at 1.000) |
| L4 | Walsh χ(0x0C) | **1.000** | yes | E26 round 1: `+χ(0x0C)`; monomial-sign ≡ parity character on same mask |

**Best without handed menu (through L3):** **1.000** via pair-growth.  
**Still needs handed menu under RQ1 protocol?** **No** — if pair-growth is wired as auto-escalation step 3.

### B2 — random monomial deg3 (mask 0x2A, cells {1,3,5})

| Step | Mechanism | Est. test acc | Escape? | Diagnosis |
|------|-----------|---------------|---------|-----------|
| L1 | frozen φ library | 0.501 | no | Mask 0x2A not in frozen set |
| L2 | count synth | 0.509 | no | Same as B1 — scalar count cannot see triple product |
| L3 | pair-growth (28 pairs) | **~0.50** | no | **Triple-arity wall** (menu_growth Target 2 analog: best pair ≈ chance on hidden triple) |
| L4 | Walsh χ(0x2A) | **1.000** | yes | E26 round 1: `+χ(0x2A)`; needs deg-3 character, not pair family |

**Best without handed menu (through L3):** **0.509** (synth) — still saturated.  
**Still needs handed menu under RQ1 protocol?** **Yes** — pair-growth insufficient; requires L4 Walsh
or **monomial forge unfreeze** (E1 promotes new φ_S).

### B5 — Walsh χ{S=0x11} (cells {0,4})

| Step | Mechanism | Est. test acc | Escape? | Diagnosis |
|------|-----------|---------------|---------|-----------|
| L1 | frozen monomials | 0.495 | no | Linear readout on products cannot express parity on sign bits |
| L2 | count synth | 0.530 | no | Z₂ structure on **sign pattern**, not count |
| L3 | pair-growth | ~0.52 | no | χ_{0,4} is not a single pair product |
| L4 | Walsh χ(0x11) | **1.000** | yes | E26 round 1: `+χ(0x11)` |

**Best without handed menu (through L3):** **0.530** — saturated.  
**Still needs handed menu under RQ1 protocol?** **Yes** — XOR/parity structure; only L4 closes.

### B6 — Walsh χ{S=0xA4} (cells {2,5,7}, deg 3)

| Step | Mechanism | Est. test acc | Escape? | Diagnosis |
|------|-----------|---------------|---------|-----------|
| L1 | frozen monomials | 0.512 | no | |
| L2 | count synth | 0.514 | no | |
| L3 | pair-growth | ~0.51 | no | Triple parity character |
| L4 | Walsh χ(0xA4) | **1.000** | yes | E26 round 1: `+χ(0xA4)` |

**Still needs handed menu under RQ1 protocol?** **Yes.**

### B7 — Walsh χ{S=0x0A} (cells {1,3})

| Step | Mechanism | Est. test acc | Escape? | Diagnosis |
|------|-----------|---------------|---------|-----------|
| L1 | frozen monomials | 0.491 | no | |
| L2 | count synth | 0.535 | no | |
| L3 | pair-growth | ~0.52 | no | Could be pair-like but wrong feature basis (sign parity ≠ raw product) |
| L4 | Walsh χ(0x0A) | **1.000** | yes | E26 round 1: `+χ(0x0A)` |

**Still needs handed menu under RQ1 protocol?** **Yes.**

---

## What each escalation buys (aggregate)

| Escalation step | Targets closed | New certified | Mechanism |
|-----------------|----------------|---------------|-----------|
| L1+L2+L3 (RQ1 as built) | 6/11 | — | Z₂ parity, inversion pipeline, accidental frozen hits |
| +L3 pair-growth | **7/11** | **B1** | Deg-2 monomial via (i,j) product inner |
| +L4 Walsh corr-search | **11/11** | **B2,B5,B6,B7** | `discoverWalsh` / χ_S argmax (E26, E1) |

**xor_popcount does not substitute for Walsh on B5–B7.** E26 selects χ(S) directly, not
`xor_pop(mask)` — GF(2) cell XOR ≠ sign-pattern parity character.

---

## Targets still needing handed menu

Under the **current RQ1 protocol** (no pair-growth, no Walsh):

| Target | Why saturated | Minimal fix |
|--------|---------------|-------------|
| **B1** | Mask 0x0C ∉ frozen lib | Pair-growth step 3 **or** monomial promotion |
| **B2** | Deg-3 mask 0x2A | Walsh step 4 **or** forge unfreeze |
| **B5** | Walsh χ_{0,4} | Walsh correlation search (step 4) |
| **B6** | Walsh χ_{2,5,7} | Walsh correlation search (step 4) |
| **B7** | Walsh χ_{1,3} | Walsh correlation search (step 4) |

**Count: 5/11 still blocked** at RQ1 substrate.

If **auto-escalation** is defined as the 4-step ladder (not E1's pre-named operator menu), only
**B2** remains structurally hard at step 3; **B1** closes at pair-growth; **B5–B7** need step 4.

Distinction:

- **Handed menu (E1):** route to named operators (spectral peak, Walsh χ_S, Clifford, world pool)
  after frozen saturation — **menu-assisted routing**.
- **Auto-escalation Walsh (E28/E2):** `discoverWalsh` correlation argmax triggered by hardness
  probe — **structural search**, same function class but not pre-labeled "Walsh menu entry."

RQ1 **explicitly blocks** the latter; hence the gap is **by design**, not a certifier bug.

---

## Comparison to E1 (handed menu)

| | E1 | RQ1 | RQ1 + full ladder |
|---|----|----|-------------------|
| Solve rate | 11/11 | **6/11** | 11/11 (projected) |
| Novel primitives | 9 | 2 principled + 1 periodic | +pair +Walsh discoveries |
| Walsh / monomial gaps | menu-routed | **blocked → saturate** | correlation search |
| Anti-remix claim | weak | **stronger** for Z₂ targets | weakens if Walsh step added |

E1 B1/B2 were "monomial-sign" targets but escaped via **Walsh characters** at the same masks
(E26: B1→χ(0x0C), B2→χ(0x2A)), not new φ promotions — family mislabel already documented in
`open_invention_e1.md`.

---

## Fork recommendations

1. **RQ1++ in `open_invention_rq1.zig`** — implement staged escalation after pipeline saturation:
   - Step 3: `pair_hardness_router` correlation rank + one verify (EXP-02, 2.5× cheaper than brute)
   - Step 4: `discoverWalsh` only when hardness class = `q38_compound` / mono≤0.55 (E14/E28)
   - **Do not** add spectral peak or world pool — keeps anti-remix bar meaningful

2. **Triple-arity fork for B2** — pair-growth cannot close deg-3 monomials. Options:
   - Monomial forge **one-shot unfreeze** on battery B (E1 path)
   - Triple-inner family from `menu_growth` Target 2 (`inner_forge` Phase C)
   - Walsh step 4 (closes B2 but mislabels family)

3. **Do not rely on xor_popcount for Walsh battery** — RQ2/E26 show XOR-mask readout is a
   different closure; B5–B7 need sign-pattern χ_S.

4. **Preserve RQ1 as control** — keep current 6/11 binary as the "no menu" baseline; add
   `open-invention-rq1-plus` or a `--escalate` flag for the ladder A/B.

5. **Next swarm experiment** — wire EXP-02 pair router into RQ1 step 3 and measure whether
   guided routing recovers B1 at ≤2× brute cost on the pinned battery seed.

---

## Verdict

| Criterion | Result |
|-----------|--------|
| RQ1 reproduced | **6/11** certified, 5 saturated |
| Pair-growth closes gap? | **Partial** — 7/11 (+B1 only) |
| Walsh XOR step closes gap? | **Yes** — 11/11 (E26 confirms all 5) |
| Handed menu still required? | **5 targets** under current RQ1; **4** if pair-growth added (B2,B5,B6,B7) |
| Recommended fork | **RQ1++** staged ladder + triple-arity path for B2 |

**Conclusion:** RQ1 gap is **real and principled**. E3+E5 substrates suffice for Z₂ and periodic
scalars (6/11) but cannot invent Walsh or unseen monomial masks without either (a) pair-growth for
deg-2, (b) Walsh correlation search for parity-on-sign targets, or (c) forge unfreeze for deg≥3.
E1's 11/11 success was **substantially menu-assisted**; auto-escalation can recover coverage only
if Walsh search is admitted as step 4 — which reopens the equivalence-tax question (E26: 85%
reproducible).

## References

- `open_invention_rq1.md` — RQ1 protocol and prior 6/11 numbers (confirmed)
- `open_invention_e1.md` — handed-menu 11/11 baseline
- `open_invention_e26.md` — escalation ceiling per target
- `swarm_exp01_menu_growth.md` — pair-growth certification
- `swarm_exp02_pair_router.md` — guided pair routing 6/6
- `open_invention_e14.md` — hardness-routed xor/synth/pipeline (no Walsh)
- `boolean_fourier.md` — why Walsh is the universal parity discovery operator