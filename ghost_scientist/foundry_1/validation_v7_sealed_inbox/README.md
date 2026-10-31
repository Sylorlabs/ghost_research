# Validation-v7 sealed inbox

Protocol v1 was retired before any real bundle arrived because its public raw
source-tree digest was dictionary-identifiable. Only the five filenames and
schema from `VALIDATION_V7_IDENTITY_ONLY_INTAKE_PROTOCOL_V2.json` are now
admissible. Every source identity, including source-tree identity, must use a
domain-separated commitment with a unique secret salt held only inside the
encrypted payload.

This directory accepts only the five files named by
`VALIDATION_V7_IDENTITY_ONLY_INTAKE_PROTOCOL_V1.json`.

The payload must be externally encrypted. Do not place plaintext source,
runtime files, private keys, symmetric keys, fixtures, graphs, shapes, or
expected outcomes here.
