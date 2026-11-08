# Reviews and audits: how it came to be

Reviews of the codebase kept for what they found and what they taught. The review batches' full logs, with every
verified finding, stay in [Reviews](<../../Reviews/>); the stories here tell each one readably and link to its log. Each story has the record of its decisions below it (see the [Historical README](../README.md) for the arrangement).

| Story | In short |
|---|---|
| [The first reviews of the codebase and its tests (May 2026)](<The first reviews of the codebase and its tests (May 2026).md>) | A broad code review ("the library is in good shape", no changes applied) and a review of the test suite's gaps and redundancy. |
| [The review batch of 2026-08-20 - the Split View drag, gradients and page width](<The review batch of 2026-08-20 - the Split View drag, gradients and page width.md>) | The owner's list worked through in four passes: a drag frame from 10,620 bytes to 3,929, gradient banding fixed as a ramp, every page's width measured; twice a measurement that measured nothing. |
| [The three deep dives of 2026-09-09 - bugs, documentation and performance](<The three deep dives of 2026-09-09 - bugs, documentation and performance.md>) | Twelve-lens fan-outs with refutation: 35 defects, 64 doc inaccuracies, 23 optimisations, all drained the same day; six proposed fixes failed their refutation. |
| [The broad bug hunt of 2026-09-12](<The broad bug hunt of 2026-09-12.md>) | Fourteen finders, two refuters each: 45 findings, 43 fixed in the batch; a verifier told to refute still mostly confirms. |
| [A review of 71 commits by another author (2026-11-07)](<A review of 71 commits by another author (2026-11-07).md>) | Seven reviewers read `c13e4536d..5d300ea7c`: ten commits needed correcting, twenty-one were incomplete, fixed in `b5bc4886a`…`6675bf56a`. The faults that recurred, to check first next time; the gate now runs the ratchets. |
