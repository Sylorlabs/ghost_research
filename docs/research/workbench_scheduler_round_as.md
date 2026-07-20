# AS3 — Checkpointed local-artifact workbench scheduler

**Verdict: FOUNDATION POSITIVE (bounded local-artifact fixture).** The scheduler uses only an evaluator-owned deterministic 96-artifact corpus; it does not read arbitrary host files or the network. Each of 192 episodes precommits a structural action before the evaluator applies it. Candidate records contain observations, probes, provenance bucket, revisions, and costs—not targets, scores, labels, or answers.

The full long run performs meaningful hash-mixed structural propagation over every artifact, bounded observation/test work, checkpoint hashing, record resume, and held-out recoded evaluation for at least ten wall-clock seconds. The self-test runs the long ledger and a second deterministic ledger and verifies byte-identical CSV output plus the checkpoint/resume path.

Result: learned provenance scored **9,648** held-out hits versus blank **8,736**, fixed broad **9,216**, random **9,165**, replay **9,216**, shuffled **8,688**, answer-scrub **8,736**, and ablation **8,736**, at the same 18,432 per-ledger tests. It is therefore a bounded foundation positive: provenance-bound structural records beat all named controls in this local corpus. The curve rises 2,304 → 4,992 → 9,648 at checkpoints 48, 96, and 192.

Limits: this is an evaluator-owned synthetic artifact snapshot, not arbitrary real repositories or web access. Wall time measures computation, not intelligence or real-world experience.
