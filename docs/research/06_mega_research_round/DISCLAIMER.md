# Disclaimer — Thread 06: Mega Research Round (2026-05-23)

**This is the most recent and most verified thread.** All 9 experiments
are complete. Start with the checkpoint doc.

## Verification status

Every claim in this thread has one or more of:
- Full 24-iteration run across 3 independent seeds (DEAD, 1111, ABCD)
- Z3 bijection check (8-bit exhaustive SMT)
- PractRand 16 MiB run (147 tests)
- Pilot gate (--iters=0 anchor/holdout check before each full run)

Anti-shortcut checklists at the bottom of each experiment doc itemize
exactly what was and was not verified.

## Null results are real null results

Exp3 (LMG + MUL-free) and Exp9 (opset discovery) produced null results.
These are documented as null results, not reframed as partial successes.
Do not skip these — they bound what the meta-engine architecture can and
cannot do.

## The one recovery note (Exp8 ABCD)

During Exp8, the ABCD seed's results directory was accidentally deleted
while the process was running. The hillclimb.csv was recovered via
`/proc/PID/fd/N` (Linux inode semantics — the file persisted in memory
while the file descriptor was open). Iter 24 was reconstructed
deterministically from the confirmed lock pattern (21 consecutive
identical rows). The recovery is documented in the Exp8 file.
`BEST_champion_mm.csv` for ABCD seed was not recoverable.

## Open questions after this round

See the "Open Questions" section at the bottom of
`mega_research_round_checkpoint_2026_05_23.md`. These are the starting
points for the next research round.
