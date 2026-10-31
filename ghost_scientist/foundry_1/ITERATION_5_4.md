# Foundry-1 iteration 5.4

The exact same metered offline build now clears `crossbeam 0.8.4` and stops at
missing `csv`. The bridge uses exact official-tag root and queue sources plus
four locally cached crate archives whose SHA-256 values match the historical
ISAMORE lock.

The provenance boundary remains explicit: the root and queue source trees are
not crates.io checksum reproductions. No ISAMORE algorithm has compiled or
executed, `P1` remains `3/4`, readiness remains `5/6`, and validation-v6 stays
sealed.
