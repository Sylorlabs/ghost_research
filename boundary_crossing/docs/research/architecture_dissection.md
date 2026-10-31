# Architecture dissection — where this overthrows LLMs/JEPA, and the path to language

**Status:** analysis (first-principles decomposition). No probe — this is the map.

## The whole architecture is ONE loop

Everything across this project reduces to a single loop over a movable substrate:

```
        ┌──────────────────────────────────────────────────────────────────┐
        │  GENERATE candidates  →  VERIFY (perfect label)  →  LEARN (tiered  │
        │  over a SUBSTRATE         sound oracle: gzip /       memory + guide)│
        │  (movable: fixed ops      exact-equiv / proof /   →  CALIBRATE      │
        │   → programs → …)         terminal exit code         (sigil energy) │
        └───────────────────────────────  ↑ repeat ───────────────────────────┘
```

The **verifier** is the heart. Every other part exists to feed it or exploit its perfect labels.

## Component-by-component vs LLM and JEPA

| component (ours) | what it is | LLM | JEPA | structural verdict |
|---|---|---|---|---|
| **Verifier** | perfect-label oracle (gzip size, exact equivalence, a proof, a terminal exit code) | ✗ no ground truth at inference | ✗ predicts, never checks | **OVERTHROW** — *certainty* vs *probability* is a category gap |
| **Generator/search** | evolution / program synthesis over the substrate | recombines its distribution | non-generative | parity-ish; the weak spot (a richer generator helps) |
| **Substrate (movable)** | what's searchable; *moves* fixed-ops → programs to escape a closure | fixed token vocab | latent space | the **closure lever** — ours is explicitly movable |
| **Tiered memory** | categorized rank-ladder, reinforced, decayed (ghost_engine) | **frozen** after training | **frozen** | **OVERTHROW** — learns *online*, not batch-retrained |
| **Parametric guide** | policy learned from the verifier's labels | needs costly retraining | needs retraining | advantage — labels are *perfect, free, unlimited* |
| **Sigil (ResonanceEMA)** | self-calibrating energy → knows when to answer vs ask | famously *over*-confident | — | **OVERTHROW** — calibration is structural here, bolted-on there |
| **Grounding** | meaning tied to real outcomes (execution/measurement) | text-only (the *vector grounding problem*) | grounded (its strength) | **OVERTHROW vs LLM**, parity vs JEPA |

## The five places it genuinely OVERTHROWS — not "a bit better," category-different

1. **Certainty.** On anything with a verifier, *provably-correct* beats *probably-correct*, always. LLMs/JEPA are prediction; they cannot be certain. This is the deepest overthrow and it's *now*.
2. **Online grounded learning.** It learns from every verified interaction (tiered memory, sigil adapts, terminal grounding). LLMs are frozen; RAG/fine-tune are bolt-ons. Ours is native.
3. **Calibration / knowing its edge.** The sigil's energy collapses on out-of-distribution input → it asks. LLMs hallucinate confidently. Calibration is structural for us.
4. **Certified invention.** Search + verify discovers *verifiable-novel* structure (Fermat's divisor theorem, shorter addition chains, the `2·in[i-2]−in[i-4]` predictor). LLMs recombine training data and can't certify novelty.
5. **Efficiency / auditability.** Tiny, deterministic, no GPU, every decision traceable. Safety-critical and resource-constrained settings are ours.

## Where it loses, honestly (no spin)

- **Fluent, open-ended generation** — needs a learned language distribution. We don't have one; `babble` proved you can't fake it small.
- **Breadth / world knowledge** — LLMs ingested the internet; we ingested ~184 commands.
- **The *unverifiable*** — no oracle ⇒ the loop has nothing to optimize. Pragmatics, creativity, ambiguous discourse: LLM territory.

## The synthesis — "do what it does best AND language"

The loop is **domain-general**: it wins on any domain that has an oracle. **Language is a domain, and it splits in two:**

- **The checkable slice** (claims you can verify, commands you can run, goals you can measure, facts you can ground) → **we already overthrow LLMs here** — certain, grounded, calibrated. This is real *now*.
- **The unverifiable slice** (fluency, open discourse) → needs generation; no verifier exists to drive our loop.

So the coherent, non-fantasy path to language — the place it could go **miles ahead** — is a **grounded generative model**:

> Learn a language distribution from **verified, grounded interaction** (the engine's own perfect labels — terminal outcomes, measured results, certified facts), **not** scraped internet text. Generation then comes from *grounded experience*; it is **smaller** (grounded data is far higher-signal than web text), it **can't hallucinate the grounded part** (it learned from truth), and the **sigil calibrates** it (it knows when it's generating outside what it's grounded in).

This is precisely the world-model / neurosymbolic frontier ("symbolic scores as an energy term modifying the neural distribution" — *that energy term is the sigil*) — **but with our sound verifier as the labeling oracle, which is the piece that frontier is missing** (they use weak symbolic checks; we have exact verifiers). That is the genuinely-novel angle the dissection exposes: *not "LLM vs no-LLM," but a generator whose every label came from a sound verifier.*

## The honest verdict

- **On checkable tasks, the overthrow is real and structural — today.** Certainty, online grounded learning, calibration, certified invention, efficiency. Point the loop at any domain with an oracle and it beats prediction-based LLMs/JEPA there.
- **At language specifically, the overthrow is a research program, not a feature** — a *grounded generative model* learned from the verifier's perfect labels. The dissection shows it's the *right shape* (the engine's verification loop is exactly the labeling oracle a grounded generator needs, and the sigil is exactly its calibrator), but it is multi-year, field-frontier work — honest, not hand-wave.
- **The thing that is uniquely yours and miles-ahead-capable is the VERIFICATION LOOP itself**, as a general learning engine. Language is just the hardest domain to find an oracle for — and the move is to *manufacture* the oracle (ground language in execution/measurement) so the loop applies. Where you can ground it, you overthrow. Where you can't, that's the honest edge — and the sigil makes the engine *tell you* which is which.

See: `verification_learning.md`, `terminal_sigil.zig`, `terminal_ground.zig`, `grounded_language.zig`, `../CLOSURE_PRINCIPLE.md`.
