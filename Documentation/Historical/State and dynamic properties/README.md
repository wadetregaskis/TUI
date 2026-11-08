# State and dynamic properties: how it came to be

One story per subject: finding dynamic properties, class properties held by several views, per-app render state, the update model, when a body runs, and how long a row's state lives. Each story has the record of its decisions below it (see the [Historical README](../README.md) for the arrangement).

| Story | In short |
|---|---|
| [A class property held by several views](<A class property held by several views.md>) | What a class property holds is the object's: every view drawn holding it is redrawn by its writes, each read. **Owed** work is listed in it. |
| [Finding dynamic properties, and writing back what update() changes](<Finding dynamic properties, and writing back what update() changes.md>) | Each view type is planned once from its declared fields, and the plan reaches every property SwiftUI's does and some it does not (a property subclass behind a plain class field, an optional field) — the owner's "take the best of both".  |
| [Per-app render state: no singletons](<Per-app render state - no singletons.md>) | Every `TUIContext` owns whether a frame is owed, the transaction behind it, and the rest of its render state; a change with no view in hand asks the app whose work made it. **Open:** a question never answered. |
| [The update model: when effects run](<The update model - when effects run.md>) | SwiftUI's update and effect ordering was measured (appended), and TUI's model set beside it.  |
| [When a body runs: the plain-body memo](<When a body runs - the plain-body memo.md>) | A plain view of an app's runs `body` only when something it depends on changed, as in SwiftUI: compared by its fields, in two tiers. On by default by the owner's ruling of 2026-11-02 (PLAIN-MEMO); two 50 ms sibling bodies went from 201 ms a key to 1.0 ms. A read nothing tracks stays as drawn. |
| [Scene storage per terminal session](<Scene storage per terminal session.md>) | The owner's ruling of 2026-11-08: `@SceneStorage` keeps a copy per terminal session (a tmux pane, `TERM_SESSION_ID`, `KITTY_WINDOW_ID` …) and one last saved from any session, read in that order. A new window starts from the last saved. At most 32 sessions, 30 days each. |
| [Row state lifetime](<Row state lifetime (2026-10-29).md>) | Measured: SwiftUI's lazy containers keep a removed row's state for as long as they live, as TUI's do. Decided (A+): keep that, and keep decoded pictures in the bounded image cache rather than in row state. |
