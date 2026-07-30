# Phase B (#3) — certified menu-growth breaks the Frontier-24 ceiling, then relocates the wall

**Status:** built, measured. Reproduce: `cd sparse_poly_discovery && zig build menu-growth --release=fast` (~4 s).

## What it does

Frontier 24 (`structure_discovery.md`) ended on a meta-ceiling: a degree-2 relation on a *hidden* pair
(2,5) that the fixed (inner ⊗ outer) menu could not route (best 0.591), because the menu's relational
inner is pinned to the focal pair (0,1). This probe makes the menu **growable** by one parameter — which
pair — and runs a certified forge loop:

1. **Discover.** Growable family: a pair-relation inner `φ(i,j) = [c_i, c_j, c_i·c_j]` for every pair,
   read by a linear outer. Search all 28 pairs; select by **validation** accuracy.
2. **Certify.** *(escape)* the chosen pair solves the target on held-out **test** where the fixed menu
   sat at chance; *(irreducibility, wcore's `reducible` lifted from opcode programs to inner transforms)*
   the new cross-term `c_i·c_j` is not reconstructible from the menu's full degree-2 readout (6 inners +
   their squares, including `sum²`) — held-out R² low — with a kill-test (append the cross-term → R²→1)
   proving the certifier is non-vacuous.
3. **Promote.** Add the certified pair to the menu → the target is solved.

## Results

```
TARGET 1 — hidden pair (2,5)   [Frontier-24 menu ceiling: 0.591]
  fixed menu (joint degree-2 over 6 inners)   test 0.556   (chance 0.501)
  DISCOVER best pair = (2,5)                  val 1.000   test 1.000
  CERTIFY escape         PASS   (1.000 ≥ 0.90, menu 0.556 < 0.70)
  CERTIFY irreducible    PASS   (menu°2 reconstructs c2·c5: held-out R² = 0.261 < 0.40;
                                 behavioral: menu 0.556 ≈ chance; kill-test R² = 1.000 → non-vacuous)
  PROMOTE                       ceiling 0.591 → 1.000   CEILING BROKEN ✓

TARGET 2 — hidden triple (1,3,6)   [the pair-family's OWN ceiling]
  fixed menu                                  test 0.520   (chance 0.513)
  best PAIR (the grown family) = (3,5)        test 0.501   → CEILING: no pair reaches it
  a TRIPLE-relation inner                     test 1.000   → the NEXT family escapes
```

## Verdict

**POSITIVE, and bounded exactly as predicted.** The forge discovered the right pair blind, certified it
(escape + irreducible, with a non-vacuous kill-test), promoted it, and broke Frontier-24's 0.591 ceiling
to 1.000. A growable menu escapes the *specific* ceiling a fixed menu could not — the first certified
menu-growth in the project.

**And the escape relocates the wall.** Target 2 shows the pair-family that just escaped has its *own*
bottom: no single pair reaches the hidden triple (best 0.501), while a triple-relation inner nails it
(1.000). The ceiling moved one rung — operator (F24) → which-pair (escaped here) → which-arity (new
bottom). Each growable family is itself a closure with a bottom. This is the unified ceiling
(`inventable_substrate_design.md`) made concrete: growth escapes a *named* ceiling; it does not repeal
the law.

## Honest caveats

- **Escape = certified selection over a fixed combinatorial family**, not unbounded invention. The family
  `{φ(i,j)}` is 28 fixed entries; "growth" is choosing one. It escapes the F24 ceiling and relocates the
  wall to triple-arity — which is the point — but it is selection-with-certification, not the minting of a
  primitive outside the substrate.
- **Irreducibility is partial, not absolute.** The menu's degree-2 readout reconstructs R² = 0.261 of
  `c2·c5` (via `sum²`, which contains `c2·c5` as 1 of 28 cross-terms) — so the cross-term is ~26%
  reducible, ~74% not. The certificate combines this with the behavioral fact (menu at chance on the
  target) and the non-vacuous kill-test (R² = 1.000 once the term is added). It is a real, but
  *relative*, irreducibility — irreducible to *this* menu, exactly as wcore's test is relative to its
  current atom set.
- Single seed; the separations are clean (0.5/1.0) so seed noise is not load-bearing, but the
  pair-search's overfitting behaviour under noisier targets is untested here.

## What it sets up — Phase C

Phase B fixed the *arity* (pairs). The wall relocated to triples, and a triple-family would relocate it
again. Phase C removes the fixed arity: an **open inner-transform forge** over a small grid→scalar VM
(cell-select, threshold, compare, product, sum/parity-reduce), promoting any certified-irreducible
program, and asks the decisive question — does iterated promotion **saturate** (cover the VM's expressive
closure and bottom out, as wcore's atom-forge did over its opcode VM) or **grow**? The unified ceiling
predicts saturation; Phase C measures it in this substrate and tests the one objective wcore did not run
in this form (algebraic-irreducibility-driven promotion).

See: `structure_discovery.md` (the ceiling broken here), `inventable_substrate_design.md` (the plan),
`antisymmetric_relational.md` (the relational inner), `wcore/docs/research/alien_novelty_limit.md`
(the terminal purist answer), repo-root `CLOSURE_PRINCIPLE.md`.
