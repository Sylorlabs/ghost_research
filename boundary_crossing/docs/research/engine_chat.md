# Conversational engine — chat, not calculator (ghost_engine ideas, no LLM)

**Status:** built, measured. Reproduce:
```
printf 'hey\ni want to shrink some data\ncold\nwhy\ndo it again but live\nwhat did you just do\nbe aggressive\nmake it smaller cold\nthanks\n' \
  | zig build engine-chat --release=fast
```
Interactive: `zig build engine-chat --release=fast`.

## The problem (from testing engine_repl)

The strict-calculator REPL bounced every non-arithmetic line off the same wall: "hey can you help me", "what did
you just do", "why stride4" — all got `I can't measure that`. No memory, no reasoning, no clarifying questions,
the identical canned line every time. It computed; it didn't converse.

## Ideas stolen from ghost_engine (the real, non-theatrical ones)

ghost_engine's conversational feel comes from **structured state + explicit labels + ranked memory, not
language-wrapping** — its own honest conclusion, matching this repo's anti-theater rule. The reusable parts:

| ghost_engine source | mechanism | adapted here |
|---|---|---|
| `conversation_session.zig` | session history + `last_result` + `current_intent` | memory of the last result → "what did you do" / "do it again" work |
| `epistemic_renderer.zig` | epistemic labels (Draft/Verified) | every result tagged `reversible=yes` (certified) vs out-of-scope |
| `sigil_runtime.zig` `applyMoodName` | mood = parameter swap | "be aggressive" → more search restarts + bolder phrasing |
| `triad.zig` rank ladder | runes = ranked pattern memory | reused primitives earn a rank: "reused a trick that's worked 2×" |
| `response_engine.zig` modes | surface the effort, don't hide it | the "why" answer narrates the real search trajectory |

## What changed (all grounded in real state — no faked language)

- **Social / meta intents** — greet, thanks, help, capabilities, recall, repeat, why — handled from STATE, so
  human sentences no longer bounce off "I can't measure that".
- **Memory** — it remembers the last `(objective, filter, sizes, first-win)`, so *"what did you just do"* and
  *"do it again but live"* (flipping the constraint) work.
- **Reasoning narration** — *"why"* reports the **actual** search trajectory it recorded (first improvement +
  final), not invented prose: "first win was delta2 (1171 bytes) … landed on stride4→delta2 at 68."
- **Clarifying question** — an unstated constraint makes it **ask** ("ship cold, or keep it live?") and resolve
  the answer on the next turn, instead of silently guessing.
- **Ranked primitive memory** — reused inventions earn a rank it refers back to.
- **Mood** — "be aggressive" swaps search effort (12 → 40 restarts) and phrasing; "be calm" reverts.
- **Response variety** — a few phrasings per reply type, so it isn't robotic.

## The honest line

Every spoken sentence is still a **template filled with real measurements and real state** — there is no language
generation, no tokens, no LLM. The conversational *feel* is bought with memory, narration of what the search
genuinely did, clarifying questions, and ranked memory — exactly the ghost_engine recipe (structured state, not
theatrical wrapping). It converses **about** real invention; it doesn't fake being a mind. The depth is still in
the certified search; the chat layer just makes going back and forth with it natural.

Next directions (brainstorm): persist the session/library to disk across runs (true long-term memory);
add the time/memory *measurements* so "make it faster" acts; let "why" replay the full trajectory; a richer
intent set; let it propose its own next move ("want me to also try it live?").

See: `engine_repl.md`, `intent_recognizer.md`, `self_extending_inventor.md`, `../README.md`.
