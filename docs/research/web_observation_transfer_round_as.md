# AS5 — Bounded Public-Web Observation Transfer (Round AS)

## Verdict

**VALID NEGATIVE — two fixed public captures are insufficient evidence of learned
web transfer.** The earned opaque-frame prediction was correct, but the fixed,
broad, replay, shuffled, and answer-scrubbed structural controls made the same
prediction and were also correct. This is not a failed run: it is the correct
finding that the bounded task has a generic structural shortcut.

## Exact scope

The evaluator made exactly two unauthenticated HTTPS `GET` requests: first to
`https://api.github.com/zen`, then—only after candidate precommit—to
`https://api.github.com/`. No credentials, cookies, login, POST/PUT/PATCH/
DELETE, forms, bodies, uploads, crawling, redirects, or arbitrary URLs are
accepted. The candidate receives only quantized length/printability/line-count
fields from the initial evaluator capture. It receives no response text/body,
URL/path, status meaning, target, progress score, or answer.

The evaluator owns body bytes, status, endpoint provenance, hash, timestamp,
and final check in the CSV ledger. Cached replay copies that completed ledger
without any network request, and two replays are byte-identical.

## Test and controls

The candidate precommitted, before the second capture, that it would be
nonempty and at least 70% printable. The fresh second capture was checked only
after that commitment. Equal-cost controls use one initial opaque frame and no
body access:

| Method | Result |
|---|---|
| Earned opaque-frame method | correct |
| Fixed structural rule | correct |
| Broad structural rule | correct |
| Random control | incorrect |
| Replay / shuffled / answer-scrubbed | correct |

Because the strong fixed controls tie it, this cannot support a learned causal
or structural-transfer claim. It establishes only bounded behavior across two
fixed public captures.

## Safety and denials

The source has no candidate-controlled request API. It records and rejects the
following forbidden request classes: non-GET method, non-HTTPS/other host,
authorization, cookie, form/body, answer request, score/progress request,
third capture, and cache mismatch. The live endpoint failing yields
`INCONCLUSIVE`, never a fabricated success.

## Reproduce

```bash
zig build-exe sparse_poly_discovery/web_observation_transfer_round_as.zig -O ReleaseSafe \
  --cache-dir /tmp/zig-as5-cache --global-cache-dir /tmp/zig-as5-global -femit-bin=/tmp/as5
/tmp/as5 selftest
/tmp/as5 results/web_observation_transfer_round_as.csv
/tmp/as5 replay results/web_observation_transfer_round_as.csv /tmp/as5.replay-a.csv
/tmp/as5 replay results/web_observation_transfer_round_as.csv /tmp/as5.replay-b.csv
cmp /tmp/as5.replay-a.csv /tmp/as5.replay-b.csv
```

This is **not** web understanding, browsing, discovery, general intelligence,
or evidence of an open-ended inventor. It is a small, fixed, read-only public
capture protocol whose controls correctly prevent an overclaim.
