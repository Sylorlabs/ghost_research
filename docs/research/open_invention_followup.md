# Open invention follow-up research (RQ1–RQ10) — June 2026

Follow-up experiments on **passing/partial** E1–E12 results. One subagent per research question.

**Reproduce:** `zig build open-invention-rqN --release=fast` in `sparse_poly_discovery/` or `boundary_crossing/` (RQ6).

---

## Summary table

| RQ | Question | Verdict | Key number |
|----|----------|---------|------------|
| **RQ1** | Blind battery **without** handed menu | **PASS** (partial) | **6/11** vs E1 **11/11**; Walsh/world still fail |
| **RQ2** | E2 XOR injection closes oracle gap? | **PASS** | **11/11** oracle-only closed via `xor_popcount(mask)` |
| **RQ3** | E3 extended periodic battery | **PASS** | **≥9/20** non-monomial via `mod(·)` synthesis |
| **RQ4** | E4 mints distinct from VM depth≤6? | **FAIL** | **100%** equivalent — not real minting |
| **RQ5** | E5 pipeline transfer to 30 new specs | **PASS** | **24/30 = 80%** |
| **RQ6** | E8 scale 200 commands + 50 phrasings | **PASS** | **100%** certified predict (uniform) |
| **RQ7** | E11 scale 100 LLM proposals | **PASS** | **9 novel** on **3 families** |
| **RQ8** | E12 hard mutators / POET curriculum | **PASS** | **44%** solve; curriculum **48** |
| **RQ9** | Equivalence tax — basis reproduces escapes? | **FAIL** | **4/6 = 67%** reproducible |
| **RQ10** | Certifier sound on random labels | **PASS** | **0/64** false promotes |

---

## Which are “one of the real ones”?

| Candidate | RQ evidence | Honest label |
|-----------|-------------|--------------|
| **Scalar synthesis (`mod`)** | RQ3 PASS, RQ1 B8 | Real discovery **inside** arithmetic closure |
| **Composed pipelines** | RQ5 80% transfer, RQ1 B11 | Real **staging** invention; RQ9: F-B reproducible |
| **LLM subordinated proposer** | RQ7 9 novel / 3 families | Real **outside generator** for features |
| **Terminal grounding** | RQ6 100% on 50 phrasings | Real **execution verifier** (narrow) |
| **POET self-play** | RQ8 curriculum 48 | Real **hard curriculum** once mutators hardened |
| **Certifier** | RQ10 0% false promote | Sound — labels are trustworthy |
| **E4 VM minting** | RQ4 100% equivalent | **Not** real — opaque relabel |
| **E1 blind pass** | RQ1 6/11 without menu | **Partial** — menu was doing half the work |
| **Most “escapes”** | RQ9 67% basis-repro | **Remix** under fixed basis |

---

## Doc index

| RQ | Doc |
|----|-----|
| RQ1 | `sparse_poly_discovery/docs/research/open_invention_rq1.md` |
| RQ2 | `sparse_poly_discovery/docs/research/open_invention_rq2.md` |
| RQ3 | `sparse_poly_discovery/docs/research/open_invention_rq3.md` |
| RQ4 | `sparse_poly_discovery/docs/research/open_invention_rq4.md` |
| RQ5 | `sparse_poly_discovery/docs/research/open_invention_rq5.md` |
| RQ6 | `boundary_crossing/docs/research/open_invention_rq6.md` |
| RQ7 | `sparse_poly_discovery/docs/research/open_invention_rq7.md` |
| RQ8 | `sparse_poly_discovery/docs/research/open_invention_rq8.md` |
| RQ9 | `sparse_poly_discovery/docs/research/open_invention_rq9.md` |
| RQ10 | `sparse_poly_discovery/docs/research/open_invention_rq10.md` |

## Documentation index (all 10 + master)

| RQ | Doc | Status |
|----|-----|--------|
| RQ1 | `sparse_poly_discovery/docs/research/open_invention_rq1.md` | ✓ |
| RQ2 | `sparse_poly_discovery/docs/research/open_invention_rq2.md` | ✓ |
| RQ3 | `sparse_poly_discovery/docs/research/open_invention_rq3.md` | ✓ |
| RQ4 | `sparse_poly_discovery/docs/research/open_invention_rq4.md` | ✓ |
| RQ5 | `sparse_poly_discovery/docs/research/open_invention_rq5.md` | ✓ |
| RQ6 | `boundary_crossing/docs/research/open_invention_rq6.md` | ✓ |
| RQ7 | `sparse_poly_discovery/docs/research/open_invention_rq7.md` | ✓ |
| RQ8 | `sparse_poly_discovery/docs/research/open_invention_rq8.md` | ✓ |
| RQ9 | `sparse_poly_discovery/docs/research/open_invention_rq9.md` | ✓ |
| RQ10 | `sparse_poly_discovery/docs/research/open_invention_rq10.md` | ✓ |
| **Master** | `docs/research/open_invention_followup.md` | ✓ |

## File index

| RQ | Source | Build step |
|----|--------|------------|
| RQ1 | `sparse_poly_discovery/open_invention_rq1.zig` | `open-invention-rq1` |
| RQ2 | `sparse_poly_discovery/open_invention_rq2.zig` | `open-invention-rq2` |
| RQ3 | `sparse_poly_discovery/open_invention_rq3.zig` | `open-invention-rq3` |
| RQ4 | `sparse_poly_discovery/open_invention_rq4.zig` | `open-invention-rq4` |
| RQ5 | `sparse_poly_discovery/open_invention_rq5.zig` | `open-invention-rq5` |
| RQ6 | `boundary_crossing/open_invention_rq6.zig` | `open-invention-rq6` |
| RQ7 | `sparse_poly_discovery/open_invention_rq7.zig` | `open-invention-rq7` |
| RQ8 | `sparse_poly_discovery/open_invention_rq8.zig` | `open-invention-rq8` |
| RQ9 | `sparse_poly_discovery/open_invention_rq9.zig` | `open-invention-rq9` |
| RQ10 | `sparse_poly_discovery/open_invention_rq10.zig` | `open-invention-rq10` |

See also: `open_invention_experiments.md` (E1–E12 master), `parallel_forks_2026.md`, `verify_learn_invent.md`.