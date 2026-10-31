# Foundry readiness iteration 5.32

An independent design audit found that validation-v7 identity-intake v1 did
not fully hide source identity. Its public, unsalted source-tree SHA-256 could
be matched against a dictionary of known public repository trees. Phase156
reproduces that failure synthetically and records that the real inbox was
empty: no external identity, source, runtime, graph, shape, or outcome was
exposed.

V1 is therefore retired for all real bundles. Corrected v2 was frozen before
its validator implementation or any external arrival. It replaces the raw
tree digest with `source_tree_commitment_sha256` and requires every identity
commitment to use a field-specific domain separator, a unique secret salt of
at least 128 bits, and canonical identity bytes. Salts remain only inside the
encrypted payload.

Two separately implemented validators accept a synthetic RSA-PSS signed v2
fixture and reject all 18 frozen hostile classes, including any v1 artifact,
raw source-tree field, weakened salted-commitment attestation, plaintext
identity, private key, duplicate commitment, malformed schema, low-entropy
ciphertext, and cryptographic mismatch. The metered real-inbox inspection
returns `VALIDATION_V7_IDENTITY_ONLY_INTAKE_V2_WAITING` at `0/5`.

Foundry remains `FOUNDRY_V6_NOT_READY`: all ten calibration arms are
integrated, but prerequisites remain `5/6`, V08 is pending, and no prospective
trial ran. The next admissible external artifact is the exact five-file v2
bundle. Self-signature still proves only key possession and byte integrity;
accountable curator identity, conflicts, and selection chronology require
separate out-of-band trust anchors and externally witnessed ordering.
