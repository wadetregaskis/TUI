# Terminals: how it came to be

One story per subject: what TUI adopted from Ghostty, the host ledger, pointer shapes, grapheme widths, and telling an app what its terminal can do. Measured behaviour is in [Terminal compatibility survey](<../../Terminals/Terminal compatibility survey.md>). Each story has the record of its decisions below it (see the [Historical README](../README.md) for the arrangement).

| Story | In short |
|---|---|
| [Adopting what Ghostty documents: synchronized output, autowrap, progress and attention](<Adopting what Ghostty documents - synchronized output, autowrap, progress and attention.md>) | Synchronized-output markers go to every host; autowrap is off everywhere but Apple Terminal; a terminal left non-blocking is waited on as a blocking write would be.  |
| [Grapheme widths on hosts that do not compose](<Grapheme widths on hosts that do not compose.md>) | A cluster claims what its host advances, decided by the advance alone; tmux keeps the cluster rule. **Open:** a question never answered. |
| [One owner for what the app sets on the terminal](<One owner for what the app sets on the terminal.md>) | The terminal keeps the ledger of what it was last sent; the render loop says what each frame wants, and only differences are written.  |
| [Pointer shapes](<Pointer shapes.md>) | The owner's ruling (2026-10-12): option (b), inert where unsupported. **Open:** a question never answered. |
| [Telling an app what its terminal can do](<Telling an app what its terminal can do.md>) | `\.terminalCapabilities` answers supported, unsupported or undetermined per feature, settling as replies and observations arrive: one `OptionSet` with a member per style and group constants, colour depth passed through from `ColorDepth`.  |
