# SwiftUI parity process: how it came to be

How the SwiftUI API work was run: the refusals review, the semantic audit, the completion work and its decisions process, Apple-only API, and the owner's decisions record. Each story has the record of its decisions below it (see the [Historical README](../README.md) for the arrangement).

| Story | In short |
|---|---|
| [Apple-only API behind canImport](<Apple-only API behind canImport.md>) | The owner, 2026-10-12: "Yes, we can use platform-specific API. I prefer not to if we have a reasonable alternative, but certainly if it's intrinsically tied to a specific platform … then that's fine." `@AppStorage`'s `store:` `UserDefaults` forms shipped behind `canImport` (2026-10-13). **Open:** a question never answered. |
| [Completing the SwiftUI API](<Completing the SwiftUI API.md>) | From 2026-10-03 the gaps (2,022) were worked in waves; every point where the call was the owner's, or where a call was made the owner might revisit, went into one decisions document, then into a decisions file per lane, each entry in three parts: A (needs a decision), B (shipped the safe option, with the fuller version priced), C (declined).  |
| [The owner's decisions, 2026-10-18 to 2026-10-25](<The owner's decisions, 2026-10-18 to 2026-10-25.md>) |  **Open:** a question never answered. |
| [The refusals re-examined (wave 17)](<The refusals re-examined (wave 17).md>) |   |
| [The semantic audit of August 2026](<The semantic audit of August 2026.md>) |   |
