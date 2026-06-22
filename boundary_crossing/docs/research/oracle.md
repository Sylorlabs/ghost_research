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

Unified sources: **WordNet** curated IS-A (proof chains) **and HAS-PART (meronyms) with inheritance** · **Webster 1913**
definitions/genus · exact **arithmetic** & string atoms · **number-theory** (prime/square/odd/divisors, **fibonacci,
divisibility, gcd**, + an identity verified over [1,4096)) · **real terminal execution** (safe, read-only whitelist) ·
**corpus-attested** possessive attributes · a **taught-fact** store you extend live. CPU, no LLM.

## Real, not hardcoded (the discipline)
The three verdicts are **not** keyword rules — they emerge from whether a real source can verify or derive an answer:
- **Refusal is emergent.** There is no list of "subjective words" that triggers a refusal. The oracle *tries every source
  and inference it has*; if none produces a verified or derivable answer, it refuses. "How will computers evolve?" refuses
  because nothing answered it — not because "evolve" is blacklisted.
- **Opinion is derived, not canned.** The identity opinion says only what it actually did ("verified for every n in
  [1,4096); beyond that it's an extrapolation, not a proof") — no hardcoded "it's Fermat's theorem" label.
- **Known is computed/looked-up, never asserted.** Every [KNOWN] traces to a source or a computation.
- **Inference is sound and shown.** "Does a car have wheels?" → *yes — car is-a motor vehicle, motor vehicle has-part
  wheel* (inherited, multi-step, derived — it was never told this directly). When curated data can't confirm, it says
  **"I don't know"** rather than asserting a false "no".

## Measured (transcript)
```
is a king a person?      → [KNOWN] yes    | WordNet | king → sovereign → ruler → person
is a dog a plant?        → [KNOWN] no     | WordNet | dog has no chain reaching plant
what is a whale?         → [KNOWN] a whale is a mammal — "Any aquatic mammal of the order Cetacea…" | Webster 1913
what's 12 times 8?       → [KNOWN] 96     | computed | exact arithmetic
is 17 prime?             → [KNOWN] yes    | computed | trial division
what does a car have?    → [KNOWN] accelerator, air bag, automobile engine, bumper, car door… | WordNet HAS-PART (+inherited)
does a car have wheels?  → [KNOWN] yes | car is-a motor vehicle, and motor vehicle has-part wheel  (derived, inherited)
does a king have a body? → [KNOWN] yes | king is-a person, and person has-part human body          (derived, inherited)
does a car have feathers? → [REFUSED] I can't confirm it — and I won't assert "no" either; I just don't know
is 144 a fibonacci number? → [KNOWN] yes | computed (5·144²±4 square test)
gcd of 48 and 36?        → [KNOWN] 12 | computed (Euclid)
does `test -f build.zig` succeed? → [KNOWN] succeeds | real execution | ran it → exit 0
does `rm -rf /tmp/x` succeed?     → [REFUSED] I won't run that — safe read-only commands only
is this poem beautiful?  → [REFUSED] emergent: neither term is in any source — nothing verified or derivable
how will computers evolve? → [REFUSED] emergent: I tried every source/inference; none answered — no fabrication
is odd-divisors always the same as square? → [OPINION] likely for all n, but only verified on a bounded range |
                              derived: checked every n in [1,4096) without exception; beyond that = extrapolation, not proof
a quokka is a marsupial  → [KNOWN] learned | taught by you
what is a quokka?        → [KNOWN] a quokka is a marsupial | taught by you
is a quokka an animal?   → [KNOWN] yes | taught + WordNet | quokka is-a marsupial; marsupial → … → animal
```

## Cross-source inference (derive what no single source holds)
Chaining relations across the curated graph yields facts no lookup contains:
```
does a car have a machine? → [KNOWN] yes
   car has-part automobile engine, and automobile engine is-a machine   (HAS-PART then IS-A — two facts, one conclusion)
does a king have a body?   → [KNOWN] yes
   king is-a person, and person has-part human body                     (IS-A then HAS-PART, inherited)
does a car have a feeling?  → [REFUSED] no chain reaches it — I just don't know  (won't fabricate either way)
```
Sound (every link is curated), and the whole derivation is shown.

## Learned question-router (routing is learned, not hand-written `if`s)
The old router was hand-written grammar (`if has("is")…`). It's now a **trained perceptron** over phrasings generated
combinatorially from word banks (unigram+bigram features, numbers normalised to `<num>`, backticks → `<cmd>`). It learns
the routing function and **generalises to unseen phrasings**: **99.3% on held-out**. It catches paraphrases the grammar
would miss entirely:
```
describe a horse        → routed: define → [KNOWN] a horse is a quadruped…   (no "what"/"define" keyword present)
tell me about whales     → routed: define → [KNOWN] a whale is a mammal…      (plural-tolerant lookup)
is 91 a prime number     → routed: number
what makes up a car      → routed: define   (imperfect — 0.7% of the time it misroutes)
```
**Robust by construction:** the learned router picks the handler to try first; if its answer isn't confident, a
deterministic cascade recovers; structural floors (e.g. an is-a question must have a copula) block any *confident-wrong*
answer on a misrouted sentence. A misroute can cost a refusal, never a falsehood. (`route <q>` shows the live prediction.)

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
  knowledge base yet** → it refuses (emergently, not by blacklist).
- **Question parsing is still grammar-based** (recognizing "is a X a Y", "does X have Y", "gcd of N and M"). The
  *knowledge and the verdicts* are real and unhardcoded; the *parser* that maps English to a query is the next thing to
  make learned (the `intent_trained.zig` perceptron is the path) rather than pattern-matched.
- **Growth so far** (real, curated/computed, no hardcoded facts): curated HAS-PART with **inherited-property inference**
  (sound multi-step derivation over the meronym + is-a graphs) and expanded number theory (fibonacci/divisibility/gcd).
  **Next:** more relations (antonyms, member/substance distinctions, holonyms), cross-source inference (combine IS-A +
  HAS-PART + definition in one derivation), a learned question-parser, and more verifiers — each one moves a slice of the
  world from *guess* to *know*, shrinking the must-guess region toward only the genuinely unknowable.
