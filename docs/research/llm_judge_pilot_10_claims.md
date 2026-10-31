# LLM judge pilot — ten Ghost Research claims

**Verdict: useful as a critic and classification aid; not accepted as evaluator
authority.** This pilot used the current LLM session in two constrained modes.
Safe mode read only the public experiment reports. Full mode then checked the
corresponding source/replay evidence. No hidden task answers, live evaluator
state, or candidate score channel was supplied to the LLM.

## Ten-claim result

| Claim | Safe report-only judgment | Full evidence judgment | Final classification |
|---|---|---|---|
| AS1 local adapter | gate/infrastructure | 10 denials + replay pass | narrow protocol gate |
| AS2 web adapter | gate/infrastructure | 8 denials + cached replay | narrow protocol gate |
| AS3 scheduler | retracted | unequal long budget/generated target confirmed | retracted invalid |
| AS4 discovery | retracted | target sentinel in child frame confirmed | retracted invalid |
| AT1 knownness | gate/infrastructure | 5 classes/5 denials/replay | narrow infrastructure |
| AT2 forge | infrastructure | repair receipt/unsafe denials | tiny DSL infrastructure |
| AT3 frontier | mechanics only | replay/unreached forks | mechanics only |
| AU1 protocol | protocol gate | 6 denials/separate role processes | protocol only |
| AV real repair | operational, no advantage | native Zag repair transfers but fixed ties | operational tie |
| AW1 method memory | infrastructure | 9 lessons/7 injections/retraction block | narrow infrastructure |

The safe and full classifications agree because the reports had already been
corrected after AS6. That is not proof the LLM is reliable: before correction,
safe mode would have repeated AS3/AS4's original overclaims. Full mode matters
because the deterministic checks directly confirm the unequal budget and direct
target channel.

## What the LLM was allowed to do

- identify missing assumptions, scope mismatch, and plausible shortcut paths;
- classify a claim as infrastructure, operational, retracted, unsupported, or
  candidate success pending evidence;
- propose a deterministic follow-up audit.

## What it was not allowed to do

- see hidden answers, evaluator source/state during a live task, or scores;
- issue a final pass/fail, change a ledger, or choose a winner;
- provide candidate solution code or a task answer.

**Conclusion:** retain an LLM critic as an optional red-team input. Every one of
its concerns must become a precommitted deterministic audit; the evaluator and
receipt evidence remain the authority.
