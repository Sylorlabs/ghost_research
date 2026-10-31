# Validation-v7 external sponsor trust root

The production sponsor fingerprint is intentionally absent. After this
protocol freeze, an experiment sponsor key must be verified out of band and
its lowercase DER-SPKI SHA-256 enrolled as:

`authorized_sponsor_fingerprint.sha256`

The file contains exactly 64 lowercase hexadecimal characters and one LF.
Foundry must not generate this production key or its enrollment evidence.
