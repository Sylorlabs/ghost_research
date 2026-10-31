# Validation-v7 external curator handoff

Identity-intake v1 is retired and must never receive a real bundle: its raw
source-tree digest was dictionary-identifiable. Corrected v2 is frozen and
must not be changed to accommodate a bundle. An external curator supplies
exactly these files in
`validation_v7_sealed_inbox/`:

1. `public_manifest.v2.json`
2. `public_manifest.v2.sig`
3. `curator_public_key.pem`
4. `payload.v7.enc`
5. `payload.v7.sha256`

The public manifest must use the exact schema in
`arm_adapter_fixtures/VALIDATION_V7_IDENTITY_ONLY_INTAKE_PROTOCOL_V2.json`.
It exposes only salted commitments and aggregate attestations. Repository,
revision, family, semantic-domain, license, source-tree, path, architecture,
graph, shape, fixture, and expected-outcome plaintext belongs inside the
encrypted payload.

Every identity field, including source-tree identity, uses its v2
domain-separator and a unique secret salt of at least 128 bits. The encrypted
payload contains those salts and the reveal records needed to recompute every
public commitment after authorization. Keep the AES-256-GCM
key outside this repository and outside the inbox. Keep the RSA private
signing key outside this repository as well.

Canonicalize the public manifest as sorted-key compact UTF-8 JSON followed by
one LF. Sign those exact bytes using RSA-PSS with SHA-256 and a 3072-bit or
larger key. The manifest fingerprint is SHA-256 over the DER
SubjectPublicKeyInfo.

The payload sidecar has exactly this form:

```text
<lowercase ciphertext sha256>  payload.v7.enc
```

with one trailing LF.

The curator must independently select four public immutable upstream
revisions, four distinct repositories, and four distinct semantic domains;
verify redistributable licenses; exclude every calibration repository; use
CPU-executable non-Transformer/non-attention workloads; and avoid candidate or
fixed-tool matching during selection.

After placement, Foundry runs:

```bash
python3 phase157_validation_v7_identity_only_intake_v2.py
```

A `COMPLETE` result proves signed transport integrity and source separation
only. It does not by itself prove independent provenance, close P2/P6,
authorize decryption, or authorize the prospective trial.
