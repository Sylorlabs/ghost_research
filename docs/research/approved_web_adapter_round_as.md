# AS2 — Approved Public Web Capture Adapter (Round AS)

## Verdict

**GATE READY — bounded read-only public capture, not web understanding or open-ended web autonomy.**

The adapter made exactly two unauthenticated HTTPS `GET` requests to the fixed,
public [`api.github.com/zen`](https://api.github.com/zen) endpoint. The normal
preferred demo endpoint, `httpbin.org/get`, returned HTTP 503 during a single
manual availability check, so this fixed fallback was used. The implementation
does not follow redirects, crawl, authenticate, store cookies, submit forms,
or use any non-GET method. It stores each retrieved response only in the
evaluator-owned capture ledger as base64 plus structural provenance.

The candidate's entire precommit was structural: a fresh permitted response
will be nonempty, at least 90% printable, and one logical line. The evaluator
ran the fresh capture after the precommit and marked it **PASS**. This is a
small protocol test; it does **not** mean the candidate understood the English
sentence returned by GitHub, discovered a web fact, or was given a browser.

## What was actually tested

The live ledger is
[`results/approved_web_adapter_round_as.csv`](../../results/approved_web_adapter_round_as.csv).

| Capture | Access | Candidate-visible information | Result |
|---|---|---|---|
| First | exact public HTTPS GET | status, length, printable count, line count, digest only | cached by evaluator |
| Fresh | same exact permitted GET, after precommit | none until end-only evaluation | PASS: nonempty, printable, one line |
| Replay | no network | none; evaluator copies retained capture ledger | byte-identical |

The raw response bytes are retained as `raw_body_base64` in the evaluator
ledger so replay is an exact cached record, not a simulated network success.
The candidate protocol itself never accepts those bytes—only the bounded
structural fields are its declared observation surface.

## Denial fixtures

The local protocol self-test rejected all **8/8** hostile request fixtures:

1. `POST` instead of `GET`;
2. another host;
3. authorization field;
4. cookie field;
5. form/mutation body;
6. answer request;
7. score request;
8. progress request.

The adapter also permits exactly the one approved origin and request shape.
No redirect option is passed to curl, no credentials or cookie jar are passed,
and curl uses HTTPS-only transport with bounded connection and total time.

## Reproduction

```bash
zig build-exe sparse_poly_discovery/approved_web_adapter_round_as.zig -O ReleaseSafe \
  --cache-dir /tmp/zig-as-cache --global-cache-dir /tmp/zig-as-global \
  -femit-bin=/tmp/approved_web_as

/tmp/approved_web_as selftest
/tmp/approved_web_as results/approved_web_adapter_round_as.csv
/tmp/approved_web_as replay /tmp/approved_web_adapter_round_as.replay.csv \
  results/approved_web_adapter_round_as.csv
cmp results/approved_web_adapter_round_as.csv /tmp/approved_web_adapter_round_as.replay.csv
```

Expected self-test receipt:

```text
round_as_as2 selftest PASS protocol_denials=8 cached_replay=byte_identical candidate_body_access=false verdict=GATE_READY
```

If either live fetch fails, the ledger records `INCONCLUSIVE` and does not
substitute a local fixture or claim a web success. The cached replay command
does not fetch the network.

## Boundaries and next use

This is deliberately small: one public endpoint, two GETs, a weak structural
prediction, and a source-level request gate. It has no login, account, form,
write, crawl, API discovery, natural-language interpretation, or real-world
invention claim. It is an approved raw-material adapter suitable for a later
separate-process workbench only after that workbench preserves the same
evaluator/candidate isolation and provenance rules.
