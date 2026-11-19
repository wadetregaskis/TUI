# Text, editing and the clipboard: how they came to be

One story per subject, each with the record of its decisions below it (see the
[Historical README](../README.md)). Keys and gestures are in
[Input, keys and gestures](<../Input, keys and gestures/>).

| Story | What it covers |
|---|---|
| [Copying out of a terminal: the clipboard, screen selection and session keepers](<Copying out of a terminal - the clipboard, screen selection and session keepers.md>) | OSC 52 and who takes it, tmux and screen, the screen selection (D4X, TEXTFMT). |
| [Text fields and the wrapping editor](<Text fields and the wrapping editor.md>) | Vertical fields, newlines, the wrapping editor, the find bar, Ctrl-U, selections kept to a container, rich text (B62–B65, B81, D4X, TEXT2, A42). **Owed:** TEXT2-INTERIOR, the caret lean, A42. |
| [An attributed TextEditor: design (G3)](<An attributed TextEditor - design (G3).md>) | `TextEditor` over an `AttributedString` (A42) priced against a 3.2 MB source: what a terminal draws of it, a per-line styler beside it, staged lanes (2026-11-16); the owner's rulings, and the caret's side at a run's edge and at a wrap measured on macOS (2026-11-17). A-ATTRED-8 and 9 ruled (a), 2026-11-18. |
| [Highlighting a large source in TextEditor: design (G3, A-ATTRED-1)](<Highlighting a large source in TextEditor - design (G3, A-ATTRED-1).md>) | How editors highlight large documents (TextMate, tree-sitter, Lezer, TextKit), and TUI's design: a line lexer with end states that converge, the viewport first, marks carried through edits (2026-11-17). The 2026-11-18 rulings explored: a push seam behind `@_spi` first, the catch-up on a worker with the screen still lexed in the frame (a snapshot costs 41 ns), the lexers in their own package. **For the owner:** A-ATTRED-10 to 12. |
| [Undo](Undo.md) | `UndoManager`, a text control's steps, the keys, undoable reorders (D1K, TEXT2). **Owed:** undo as edits, undo for every control. |
| [Links, Markdown and attributed text](<Links, Markdown and attributed text.md>) | Links as controls, TUI's Markdown parse beside Foundation's, titles, typography declined (B84–B88). **Open:** `^[…](attrs)`. |
| [Formatting and live text](<Formatting and live text.md>) | Typed interpolations, locale numbers, live text, the formatter forms refused (B49, B51, TEXTFMT). |
| [ASCII transliteration before layout](<ASCII transliteration before layout.md>) | `TUI_PLAIN_TEXT=transliterate`: other scripts spelled in Latin letters before layout, an experiment behind the flag (2026-11-08). |
