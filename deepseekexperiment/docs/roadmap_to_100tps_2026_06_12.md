# Roadmap to 100 tps — the surrogate-engine program

**Date:** 2026-06-12. Target: Micah wants 100 tps (the "+ surrogate attention"
ceiling). Honest framing: expert surrogates alone reach ~11 tps (below the 20
goal); clearing 20 and heading to 100 REQUIRES surrogating attention too.

## The two MAC ceilings (from two_floors_reconciliation)

| tier | what's surrogated | compute ceiling (MAC) |
|---|---|---|
| 0 | nothing (full XNOR) | 3.4 tps |
| 1 | routed experts | ~11 tps (attention now 96% of compute) |
| 2 | routed experts + attention | ~100 tps |

## Honest real-tps caveats (MAC ceilings overstate)

- **RAM bandwidth:** per-token surrogate reads ~180MB (6 routed ×58 ×0.43MB +
  shared + attention) at ~40GB/s = ~4.5ms = ~220 tps ceiling. Not binding —
  good, leaves compute as the limit.
- **Kernel efficiency / projection overhead / int8-vs-XNOR rates** pull MAC
  ceilings down maybe 2-3x. Realistic: tier-1 ~6-10 tps, tier-2 ~25-50 tps.
- **Warm-up cost:** stream real experts once per session to fit surrogates
  (amortized over the session length).
- **20 tps is reachable only in tier-2** (attention surrogated). 100 tps is the
  optimistic tier-2 ceiling; ~30-50 tps is the honest tier-2 expectation.

## The hard part of tier-2: attention resists naive projection

Experts surrogate cleanly (E18b: 0.93 at rank 84) because they're a plain
input->output map. Attention is harder:
- The big cost is q_b (1536 -> 128 heads x 512 = 65536). Its output feeds
  per-head rope + softmax + scores — you can't low-rank the head dimension
  arbitrarily without breaking attention.
- Surrogation must project the INPUT (residual, ~84-dim on one context) and
  possibly the per-head structure, not the 65536 output blindly.
- Open question (untested): how sensitive is attention OUTPUT to projecting its
  input to rank r? This is the attention analogue of E18b and must be measured
  before tier-2 is credible.

## Experiment sequence (disciplined: prove each tier before building the next)

1. **[RUNNING] Expert surrogate fidelity vs warm-up (E19c).** Does held-out
   per-expert cosine reach ~0.85 at ~384 warm-up tokens? GATE for everything.
   - GO -> step 2. STOP -> add nonlinear correction core (sibling sparse_poly)
     before proceeding.
2. **End-to-end surrogate perplexity (E20).** The REAL proof: warm up on N
   tokens, fit surrogates for all active experts, run the FULL model with
   surrogates swapped in, measure perplexity vs reference on held-out tokens.
   Per-expert cosine 0.85 is necessary; low end-to-end PPL is sufficient.
   - This needs: full 61-layer warm-up activation capture + a surrogate-expert
     path in ppl_stack. Real engine work; the first true validation.
3. **Attention surrogate feasibility (E21).** Capture post-attn_norm inputs;
   measure attention-output cosine vs input-projection rank (E18b for
   attention). Decides if tier-2 (the 20-100 tps tier) is real.
4. **Tier-2 end-to-end + real tps.** Surrogate experts + attention, measure
   actual tps and PPL on this hardware. The number that answers "did we hit it."

## Why this is the spine now

The two-floors analysis proved every conventional path dead-ends at ~3 tps.
Surrogates are the only retraining-free escape. Tier-1 (proving now) gets the
working set into RAM and the compute off the disk. Tier-2 (attention) is the
reach for 20-100 tps. Each tier is gated on a measured fidelity number, not a
hope. We do NOT build tier-2 until tier-1's gate (running) says GO.
