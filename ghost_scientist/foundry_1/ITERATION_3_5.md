# Foundry-3.5 historical diversity calibration

Every previously observed external workload suite is now explicitly
calibration-only.

The LLM-free audit attempted 20 families and exported 19. The frozen Siamese
case remained unsupported because `torchvision` is unavailable. Bounded
connected-path enumeration produced 149 typed motifs.

Eleven motifs occurred in at least three semantic families and two historical
suites:

- five target sequences duplicate the unchanged strong fixed portfolio;
- six target sequences are novel to that portfolio;
- only `aten.mm.default -> aten.add.Tensor` spans more than one repository,
  appearing across three families, three suites, and two repositories.

The complete audit passed process-tree accounting. It exposes a real
opportunity for a diversity-seeking forge, but no prospective claim is
permitted: all 19 successful graphs had already produced outcomes in earlier
phases.

The next protocol boundary is therefore strict. Four new non-Transformer
upstream applications, from repositories absent from this calibration pool,
must be source-selected and hash-frozen before typed candidate construction.
Candidate and strong-fixed outcomes may only be observed afterward.

**Verdict:** `FOUNDRY_V6_NOT_READY`
