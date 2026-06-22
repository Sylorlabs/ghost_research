# The Oracle — a KNOWING engine (knowledge vs labeled opinion vs refusal)

`oracle.zig` (`zig build-exe oracle.zig -O ReleaseFast -femit-bin=/tmp/oracle && /tmp/oracle`, or `zig build oracle`).

## Why
Predicting the next token — by counting or by a transformer — is **guessing**: no world model, no notion of truth, can't
tell a right guess from a hallucination. The project's real axis is **verification**: *know* (prove / compute / measure /
look up curated data) and **refuse** what you can't check. This is the build of that idea: **everything asserted as
knowledge is verified; guessing is allowed but quarantined** — clearly labelled opinion, *derived by reasoning over the
known facts*, never stored as knowledge.

Exploration found the knowing machinery already existed but was **un-integrated** (11+ verified probes). The oracle is the
**unification**: one queryable engine, every answer tagged by epistemic status with its provenance.

## What it is
An interactive REPL. Every answer is one of three:
- **[KNOWN]** — proved / computed / measured / curated lookup. Authoritative. Shows source + proof.
- **[OPINION]** — couldn't verify, but **derived from known facts**; labelled, non-authoritative, **quarantined** (never
  written to the knowledge store). Cites the knowns it was built from.
- **[REFUSED]** — nothing verifiable, nothing derivable. Honest "I can't verify that" (the anti-hallucination move).

Unified sources: **WordNet** curated IS-A (proof chains) · **Webster 1913** definitions/genus · exact **arithmetic** &
string atoms · **number-theory** predicates (+ an identity proved over [1,4096)) · **real terminal execution** (safe,
read-only whitelist) · **corpus-attested** possessive attributes · a **taught-fact** store you extend live. CPU, no LLM.

## Measured (transcript)
```
is a king a person?      → [KNOWN] yes    | WordNet | king → sovereign → ruler → person
is a dog a plant?        → [KNOWN] no     | WordNet | dog has no chain reaching plant
what is a whale?         → [KNOWN] a whale is a mammal — "Any aquatic mammal of the order Cetacea…" | Webster 1913
what's 12 times 8?       → [KNOWN] 96     | computed | exact arithmetic
is 17 prime?             → [KNOWN] yes    | computed | trial division
what does a king have?   → [KNOWN] palace, son, daughter, tent, ship | corpus-attested ("king's …")
does `test -f build.zig` succeed? → [KNOWN] succeeds | real execution | ran it → exit 0
does `rm -rf /tmp/x` succeed?     → [REFUSED] I won't run that — safe read-only commands only
is this poem beautiful?  → [REFUSED] that's opinion/unverifiable — I won't pass a guess off as knowledge
how will computers evolve? → [REFUSED] (same — honest, no fabrication)
is odd-divisors always the same as square? → [OPINION] likely yes (Fermat) | derived: verified for all n in
                                              [1,4096); beyond that it's a conjecture from the proven domain
a quokka is a marsupial  → [KNOWN] learned | taught by you
what is a quokka?        → [KNOWN] a quokka is a marsupial | taught by you
is a quokka an animal?   → [KNOWN] yes | taught + WordNet | quokka is-a marsupial; marsupial → … → animal
```

## The quarantine (the core discipline)
Only the **teach** path and verified lookups write to the knowledge store. **Opinions are computed on the fly and never
written** — so a guess can never later be mistaken for knowledge. The three states are visually and structurally
separate; provenance is on every line.

## Honest scope / what hasn't been built yet
- It is a **genuine oracle on its grounded domains** (taxonomy, definitions, arithmetic, number properties, real command
  outcomes, corpus-attested attributes, taught facts) and **refuses elsewhere** — not a general chatbot.
- Corpus attributes are **attested** (found in usage), weaker than proof — the provenance says so; they never get the
  hard-"proved" label.
- The **opinion-from-knowledge** layer is minimal (extrapolation beyond a verified domain; is-a composition via
  Webster-genus + WordNet chain). Broad-future / subjective opinion ("how will computers evolve") has **no verified
  knowledge base yet** → it refuses. Building those knowledge domains — and richer derivation (multi-step inference over
  the unified store, HAS-PART/meronym relations, more verifiers) — is the **next step**: grow the *knowing* region so the
  part that must be guessed shrinks to only the genuinely unknowable.
