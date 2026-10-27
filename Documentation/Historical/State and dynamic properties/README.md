# State and dynamic properties: how it came to be

One story per subject: finding dynamic properties, class properties held by several views, per-app render state, and the update model. Each story has the record of its decisions below it (see the [Historical README](../README.md) for the arrangement).

| Story | In short |
|---|---|
| [A class property held by several views](<A class property held by several views.md>) | What a class property holds is the object's: every view drawn holding it is redrawn by its writes, each read. **Owed** work is listed in it. |
| [Finding dynamic properties, and writing back what update() changes](<Finding dynamic properties, and writing back what update() changes.md>) | Each view type is planned once from its declared fields, and the plan reaches every property SwiftUI's does and some it does not (a property subclass behind a plain class field, an optional field) — the owner's "take the best of both".  |
| [Per-app render state: no singletons](<Per-app render state: no singletons.md>) | Every `TUIContext` owns whether a frame is owed, the transaction behind it, and the rest of its render state; a change with no view in hand asks the app whose work made it. **Open:** a question never answered. |
| [The update model: when effects run](<The update model: when effects run.md>) | SwiftUI's update and effect ordering was measured (appended), and TUI's model set beside it.  |
