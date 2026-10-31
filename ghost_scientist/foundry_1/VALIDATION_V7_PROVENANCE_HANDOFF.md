# Validation-v7 accountable provenance v2 handoff

This handoff starts only after the protocol freeze already recorded in
`results/validation_v7_accountable_provenance_v2_freeze.json`.

First, an experiment sponsor must be verified outside Foundry. Place only the
lowercase SHA-256 fingerprint of the sponsor key's DER SubjectPublicKeyInfo,
plus one LF, at:

`validation_v7_external_trust_root/authorized_sponsor_fingerprint.sha256`

Foundry must not generate, select, or approve that production key.

After the corrected five-file identity-intake v2 bundle exists, place exactly
these files in `validation_v7_provenance_inbox/`:

1. `sponsor_public_key.pem`
2. `trust_registry.v2.json`
3. `trust_registry.v2.sig`
4. `candidate_boundary.v2.json`
5. `candidate_boundary.v2.sig`
6. `provenance_statement.v2.json`
7. `curator_public_key.pem`
8. `curator_statement.sig`
9. `reviewer_public_key.pem`
10. `reviewer_statement.sig`
11. `external_log_public_key.pem`
12. `external_log_entry.v2.json`
13. `external_log_entry.v2.sig`

Use the exact canonical schemas, roots, purposes, statements, claim boundary,
and timestamp ordering in
`arm_adapter_fixtures/VALIDATION_V7_ACCOUNTABLE_PROVENANCE_PROTOCOL_V2.json`.
The sponsor signs the registry and candidate boundary. The curator and
reviewer sign identical statement bytes. The external log signs its entry.
All four public keys are RSA 3072-bit or larger.

Then run:

```bash
python3 phase157_validation_v7_identity_only_intake_v2.py
python3 phase159_validation_v7_accountable_provenance_v2.py
```

Even a complete result is labeled
`ACCOUNTABLE_TWO_PARTY_PROVENANCE_AND_ORDERED_COMMITMENT_ATTESTED`, never
“independence proved.” It cannot rule out off-system collusion and does not
authorize decryption, matcher release, V08, or the prospective trial.
