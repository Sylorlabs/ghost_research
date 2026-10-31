# Going back and forth with the engine — the interactive loop, no LLM

**Status:** built, measured. Reproduce (scripted):
```
printf 'make it smaller\nmake it smaller but keep it live\nmake it prettier\nmake it faster live\n' \
  | zig build engine-repl --release=fast
```
Interactive: `zig build engine-repl --release=fast` then type wants (blank line / Ctrl-D to quit).

## The question (Micah)

*"Could I go back and forth with it?"* — yes. A conversation is just the three engine-native pieces wired into
one loop with **persistent state**, and none of them is an LLM.

## What it does each turn

```
you type a want
  → [recognizer: tiny trained perceptron]   understand → formal objective, OR "out of scope" (it talks back)
  → [inventor: evolve a reversible filter]   act → certified by real gzip + round-trip
  → report in your terms; keep the learned library for the next turn
```

## A real session

```
you ▸ make it smaller
eng ◂ understood: minimize SIZE, cold (offline).
       invented filter [ stride4→delta2 ]  gzip 2103→68 (97% smaller)  reversible=yes
you ▸ make it smaller but keep it live
eng ◂ understood: minimize SIZE, live (random-access).      [random-access kept]
you ▸ make it prettier
eng ◂ I can't measure that. I CAN: minimize size / time / memory, kept cold or live.
you ▸ make it faster live
eng ◂ understood: minimize TIME, live.  (SIZE optimizer is wired here; the same loop drives a TIME
       optimizer once that measurement is added — engineering, not a new neural part.)
```

It **understands** (no LLM), **acts** (invents `stride4→delta2`, crushing the record array 97% — discovered
live, certified reversible), **reflects the constraint** (cold vs live), **talks back** on an out-of-scope want
(guides you to its menu instead of bluffing), **recognizes** the other objectives, and **carries state** (its
primitive library persists across turns). No LLM is involved at any point.

## Honest scope

The fully-wired, *measured* action is the SIZE optimizer (the 97% is real). TIME/MEMORY are recognized and the
loop is identical — each just needs its own measurement wired in (engineering, not a new neural capability). The
back-and-forth itself — understand → act → report → refine → remember — is complete and runs with no LLM. The
only human input is the sentence, exactly the line Micah drew. Out-of-menu wants ("prettier") are refused, since
nothing grounds them — true for any system, not just a non-LLM one.

See: `intent_recognizer.md` (the understand step), `primitive_synthesizer.md` + `autonomous_inventor.md` (the
act step), `self_extending_inventor.md` (the library compounding across turns), `../README.md`.
