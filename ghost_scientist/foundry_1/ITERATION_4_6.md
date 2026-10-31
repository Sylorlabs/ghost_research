# Foundry-4.6 shared-resource contract integration

A3 and A9 are now production-integrated calibration arms.

The additive batch overlay leaves the frozen v1 arm contract unchanged. Each
of 46 artifact input/output pairs passes both the primary and independent v1
verifiers. The overlay binds all 23 outputs from one arm to one canonical,
hash-identified process-tree receipt, so accounting charges that receipt once
rather than multiplying it by 23.

Two independently implemented batch verifiers reject nine hostile mutations:
changed receipt identity or body, a missing binding, a duplicate artifact, a
changed output digest, a changed resource projection, a 23x resource
multiplier, an unauthorized prospective claim, and an unknown field.

Both batch assembly paths and the hostile conformance gate pass process-tree
metering. Integrated truth therefore advances from A0/A2 (`2/10`) to
A0/A2/A3/A9 (`4/10`).

This remains calibration integration. P1 is incomplete, P3 is incomplete, and
validation-v6 remains unread and unexecuted.

**Verdict:** `FOUNDRY_V6_NOT_READY`  
**Required arms integrated:** `4/10`  
**Prospective authorization:** false
