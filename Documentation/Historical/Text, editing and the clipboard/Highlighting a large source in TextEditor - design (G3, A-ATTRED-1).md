# Highlighting a large source in TextEditor: design (G3, A-ATTRED-1)

*The deeper design the owner asked for on 2026-11-17, when he ruled that the per-line styler proposed under
A-ATTRED-1 in [An attributed TextEditor: design (G3)](<An attributed TextEditor - design (G3).md>) is too limited,
because a line's styling can depend on the lines above it (a string or a comment opened earlier). It surveys how
real editors highlight large documents, then proposes how TUI should. Written 2026-11-17 against `main` at
2b23a75b5. Nothing here is built. The costs come from a standalone probe on this machine (macOS 15.8.3, Xcode's
Swift 6.2.4, `-O`; see "For a future reader"). Ids: A-ATTRED-5 to 7 (for the owner), B-ATTRED-8 to 15 (decided
here). The owner ruled on A-ATTRED-5 to 7 on 2026-11-18; §8 explores the rulings (B-ATTRED-19 to 26, and
A-ATTRED-10 to 12 for the owner, who ruled on all three on 2026-11-19). His final word on 12 replaced the lexers
with tree-sitter, outside TUI; §8.6 re-plans TUI's side for it (B-ATTRED-27 to 30 decided there, A-ATTRED-15 and
16 for the owner), with a fourth probe of tree-sitter itself.*

## In short

Editors solved this long ago, in two ways. In the first, a lexer walks each line from the state the line before
ended in, keeps each line's end state, re-lexes from an edit until a line's end state comes out as it was, and
styles the visible lines first. TextMate grammars in VS Code, Sublime, Kate, Vim and CodeMirror's stream
languages work this way. In the second, an incremental parser keeps a tree and reuses its unchanged parts after an
edit (tree-sitter in Neovim, Nova, Zed and VS Code's experiment; Lezer in CodeMirror 6). Both kinds style the text
apart from the text itself: they never write the colours into the document. NSLayoutManager's temporary
attributes, TextKit 2's rendering attributes and CodeMirror's decorations all work that way.

**Recommended (A-ATTRED-5 (b)):** a TUI-specific highlighter for `TextEditor`, kept apart from the text, so the
bound `String` or `AttributedString` is never rewritten. An app supplies a **line lexer**: a function from one
line's bytes and the state the line above ended in, to the line's tokens and its own end state. The editor keeps
an interned end state for every line (4 bytes a line), re-lexes from an edit until the state converges, styles the
visible lines first, and catches up in time slices off the key's path. It goes no further than a screen past the
viewport, so an edit that changes everything below it never costs the document. The engine sits behind a public
seam (edits in, changed lines out, work under a deadline, runs for the lines drawn) that is shaped like
tree-sitter's API, so an app can plug in a tree-sitter or language-server styler through the same modifier.
Marks, such as tuitree's parse error, are ranges stated with the text they were computed from, and the editor
carries them through its own edits. TUI ships JSON and XML lexers in an opt-in module (A-ATTRED-6).

On tuitree's 3.2 MB JSON, a byte lexer handles the whole document in 7 ms, a screenful in 3 µs, and an edit that
opens a comment in the middle (60,000 lines to re-lex) in 2.5 ms. So a key stays at today's 2.6 ms, and a slow
lexer only ever costs the lines drawn. About 7 lane-days, after SwiftUI's API (A-ATTRED-2).

**2026-11-18:** the owner's rulings (explore the public seam and a worker; no lexers in TUI) are explored in §8.
The seam becomes a push model behind `@_spi` first, the catch-up moves to a worker while the lines on screen are
still lexed in the frame, and the lexers go to a package of their own: about 6¼ lane-days in TUI.

**2026-11-19, final (A-ATTRED-12):** no lexers anywhere. Highlighting comes from tree-sitter (SwiftTreeSitter and
grammar packages such as TreeSitterJSON and TreeSitterXML), through a thin adapter on the seam that lives in
tuitree or an optional package, never in TUI. §8.6 re-plans TUI's side. TUI still owns the layer, the seam (off the
main actor, versioned, the viewport first), marks and the guards. The line-lexer engine (a state per line, the
frontier, convergence, the screen lexed in the frame, the catch-up slices) existed to run hand-written lexers, so
§8.6 proposes dropping it with the public line-lexer protocol (A-ATTRED-15): **about 4 lane-days in TUI, against
6¼**. Measured here, tree-sitter parses a 3.2 MB JSON in 240 ms and re-parses after a key in 0.4 ms at 100 KB, 4.5
ms at 1 MB and 16–17 ms at 3.2 MB, all on the styler's task, off the main actor. Its pieces add about 0.36 MB to a
stripped app (JSON and XML) and 3 to 4 s to a clean release build. The adapter is about 2½ days in tuitree
(A-ATTRED-16).

## 1. How editors do it

| Editor | Unit, and the state carried across lines | After an edit | The viewport and the rest | Long lines, large files |
|---|---|---|---|---|
| **VS Code** (TextMate grammars) | A line; the grammar's rule stack at its end | Re-tokenizes from the edited line "until an equal end state is encountered" [1] | Idle-time slices on the UI thread, yielding every 1–2 ms [3]; a viewport ahead of the tokenized lines is coloured from a *guessed* state (the lines of smaller indentation above it), not cached [3]; in a web worker, rolled out from 1.81 and on by default today [4][5] | `editor.maxTokenizationLineLength` 20,000; tokenization off past 20 MB or 300,000 lines [5] |
| **VS Code** (tree-sitter, experimental since 1.97 [2]) | A tree | Incremental parse | | |
| **Sublime Text** | A line; the context stack (push, pop, set, embed) | Re-highlights from the edit; a `branch_point` costs "reprocessing an entire branch upon each change" [6] | | Regexes see one line; a `fail` rewinds at most 128 lines [6] |
| **Kate** (KSyntaxHighlighting) | A line; `State` (the context stack), `operator==` comparable; `highlightLine(text, state) -> State` [7] | Re-highlights until the state matches | | `lineEndContext`, `#stay`, `#pop` decide the next line's context [8] |
| **Vim** (`:syntax`) | A line; the syntax region stack | Re-parses below the change | To start drawing mid-file it must *synchronize*: from the start, by C comments, a fixed number of lines back, or a sync pattern searched for backwards (`minlines`, `maxlines`) [9] | `synmaxcol`, `redrawtime` |
| **Neovim** (tree-sitter) | A tree, and child trees for injected languages | `LanguageTree:parse(range)` | Asynchronous since 0.11, in 3 ms segments on the main loop; injections queried only in the range asked for [10][11] | Parse times out after `redrawtime` [10] |
| **tree-sitter** itself | A tree | `ts_tree_edit` with the edit's bytes and points, then a reparse with the old tree, which shares its unchanged structure [12]; `ts_tree_get_changed_ranges` says where the tree changed [13] | A parse can be cancelled by a progress callback and resumes where it stopped [13]; included ranges for embedded languages [12] | |
| **CodeMirror 6** (Lezer) | A tree; small nodes packed 8 bytes each [14] | Reuses fragments of the old tree past the changes (`TreeFragment.applyChanges`, gaps under 128 characters ignored) [15] | 20 ms of parsing in the transaction, then idle slices of at least 25 ms; at most 3 s per 30 s; stops 100,000 characters past the viewport [16]; only the visible ranges are highlighted [17] | Stream (line-state) languages restart from a fresh state at the viewport when the parse is 100,000 characters behind, and come back to the gap later; a line is lexed only to its 10,000th character [18] |
| **Nova** | tree-sitter since Nova 10 | | | Lines over 10,000 characters highlighted only with tree-sitter grammars (10.1) [19] |
| **AppKit, TextKit 1** | | | `NSLayoutManager.addTemporaryAttributes`: used "only for onscreen drawing", not stored with the text; only attributes that leave layout alone (colours, underlines); how spelling marks are drawn [20] | |
| **TextKit 2** | | | `NSTextLayoutManager.setRenderingAttributes(_:for:)` and a `renderingAttributesValidator` called for the fragments laid out [21] | |
| **Neon** (Swift, on TextKit) | Any token provider; three layered phases (a fast pattern pass, then tree-sitter, then LSP semantic tokens) | Minimal invalidation, buffered and merged | Lazy, visible set first; synchronous and asynchronous providers behind one interface, "flicker-free styling on keystrokes" [22] | |
| **BBEdit** | Compiled modules, and codeless (now "declarative") language modules [23] | Not documented | | |

Xcode's source editor documents nothing of how it highlights, so it is left out rather than guessed at.

What they agree on:

1. **State at a line's end, and convergence.** Every line-based highlighter keeps the state each line ended in.
   That state is the context stack in Kate and Sublime, and the rule stack in TextMate. Re-lexing stops at the first
   line whose end state is unchanged. A typed character almost never changes its line's end state, so a key costs
   one line.
2. **The viewport first, and the rest later or never.** Highlighting is computed for what is drawn. The catch-up
   runs in small slices on the UI thread (VS Code until 1.81, CodeMirror, Neovim), and in a worker more recently
   (VS Code). CodeMirror stops a fixed distance past the viewport rather than finishing the document.
3. **A guess when the viewport is far ahead.** VS Code uses the indentation chain above. Vim uses a sync pattern.
   CodeMirror starts afresh at the viewport. The guess is drawn, then replaced once the real state arrives.
4. **Limits.** A line past 10,000 or 20,000 characters is not lexed. A file past 20 MB is not highlighted at all.
5. **Styles apart from the text.** Colours from highlighting are never stored in the document (temporary
   attributes, rendering attributes, decorations). Diagnostics are another layer on top (LSP's diagnostics carry
   the document version they were computed for [24]).
6. **Compact tokens.** VS Code holds a token in two 32-bit numbers, with its colours and font style packed into the
   second [1]. Lezer holds a node in 8 bytes.
7. **Trees for structure, lines for speed.** A tree knows what a line-state lexer cannot: a missing brace's true
   extent, or nested languages. It costs a parser per language, usually C (tree-sitter) or a generated grammar
   (Lezer). Lezer's author built his own parser because tree-sitter is C, and the line-state tokenizers of
   CodeMirror 5 only approximate structure [14].

## 2. What SwiftUI has

Nothing that styles a `TextEditor` without changing its text. The macOS 26.2 SDK's SwiftUI and SwiftUICore
interfaces have `textEditorStyle(_:)`, the formatting definitions and `textInputFormattingControlVisibility`, and
no highlighting or rendering-attribute API. `TextRenderer` (which TUI has) draws `Text` views only: the SDK's
`textRenderer(_:)` documentation speaks of text views. `AttributedTextFormattingDefinition` constrains the stored
attributes. Its documentation suggests a semantic custom attribute that a constraint turns into a colour, but the
attribute still lives in the `AttributedString`, which is what costs O(n) a key (B-ATTRED-4). So the API below is
TUI-specific and under its own names. None of them shadows a SwiftUI declaration, and a SwiftUI port of an app
drops the modifiers and keeps its plain or attributed editor.

## 3. The design

```
 bound text (String or AttributedString)   untouched by highlighting
   │ the editor's own edits (EDITOR-SPLICE's Edit: lines replaced, lines inserted)
   ▼
 EditorLayout ──► highlighter engine ──► runs for the lines drawn ──► styledRow (B-ATTRED-5)
                   │  end state per line (interned)                    ▲
                   │  frontier: the first line whose start is stale    │ marks over highlighting,
                   │  slices between frames, up to the viewport + 1    │ find and selection over both
                   ▼
                 the app's lexer (or any styler behind the seam)
```

### B-ATTRED-8. Highlighting is a layer over the text, never written into it

The editor holds the highlighter's results beside its layout and draws them as rendering attributes are drawn.
The binding's value is never touched, so the editor's own write is still read back by storage identity
(EDITOR-SPLICE), and SwiftUI's `AttributedString` API keeps its meaning for an app that uses it. On the attributed
editor, a highlight attribute wins over the stored one for drawing only. The order is the selection's colours, then
the find bar's tint, then marks, then highlighting, then the stored attributes, then the editor's style. Each layer
replaces only the attributes it sets.

### B-ATTRED-9. The unit is a line and its end state, and the state must be Hashable

The line lexer, sketched here (the names are for lane H0 to settle):

```swift
/// TUI-specific. Styles a TextEditor's lines for drawing without changing its text.
public protocol TextEditorLexer: Sendable {
    /// What a line's end decides about the next line: a comment or string still open, the context stack.
    associatedtype State: Hashable & Sendable
    /// What the lexer calls a token: an app's enum, mapped to attributes once per value.
    associatedtype Token: Hashable & Sendable

    var initialState: State { get }

    /// Lexes one line (its UTF-8, without the line break) from the state the line above ended in,
    /// appending each token where it starts, and returns the state this line ends in.
    func lex(_ line: Substring.UTF8View, from state: State, into tokens: inout TextEditorTokens<Token>) -> State

    /// A state to start `line` from without the lines above, when the editor must draw far ahead of the
    /// lines lexed (Vim's sync, VS Code's guess). `nil`, the default, starts from `initialState`.
    func resynchronizationState(for line: Substring.UTF8View) -> State?
}
```

and the modifier:

```swift
TextEditor(text: $source)
    .textEditorHighlighting(JSONLexer()) { token in       // (Token) -> AttributeContainer, once per token
        switch token {
        case .key: AttributeContainer().foregroundColor(.cyan)
        case .string: AttributeContainer().foregroundColor(.green)
        case .comment: AttributeContainer().foregroundColor(.secondary)
        ...
        }
    }
```

A line's bytes are a view of the text's own UTF-8 (`EditorLayout.lineStarts` are byte offsets already), so the
lexer copies nothing. `Span<UInt8>` would be the better parameter, but it needs a runtime that has `String`'s
span, which macOS 15 lacks; lane H0 settles this. Tokens are appended with UTF-8 offsets, and the row maps them to
characters as it walks the line it draws. An offset inside a character styles the whole character, and offsets
that go backwards or past the line are clamped, never trusted.

The state is the line's only memory, so a construct that spans lines lives in it: an XML comment, a JSON5 or
JSONC block comment, a heredoc. A lexer that needs structure (bracket depth for a parse error) can put it in the
state. Convergence then stops only where the structure agrees again. That is correct, and it is what the
lexer asked for (see §5).

### B-ATTRED-10. Token styles are AttributeContainers, interned once per token

The style closure maps a token to an `AttributeContainer`, using the same vocabulary as the attributed editor (the
drawable half in the G3 document's §2). It is called once for each distinct token, and again only when the
environment changes (a palette, the colour depth). The result is interned to a 16-bit style index, so a run costs
a byte offset and a style index, 8 bytes in all, not the 250 bytes an `AttributedString` run costs. A palette
change therefore re-styles without re-lexing.

### B-ATTRED-11. The engine: a state per line, a frontier, convergence

- **States.** One `UInt32` a line indexes a table of the distinct states seen (`Hashable`, deduplicated). So a
  comparison is an integer compare, and the store is 4 bytes a line: 0.5 MB for the probe's 120,000 lines (§4). The
  store is spliced with the layout's own `Edit` (`replaced`, `replacement`), as `lineStarts` is.
- **The frontier** is the first line whose start state is not known to be right. An edit at line *k* moves it to
  *k*. Lexing line *k* from the state above gives its end state. If that equals the state stored for it, and the
  lines below were right before the edit, the frontier goes back to where it was. That is the common case, and it
  costs one line.
- **Tokens are not stored for the document.** Only the lines drawn keep their runs (B-ATTRED-2's per-line cache),
  dropped when the line or its start state changes. A line is re-lexed from its stored start state when it is drawn
  again (3 µs a screenful, §4). Keeping every line's tokens would cost about 7 MB for the probe's 821,000 tokens.

### B-ATTRED-12. The viewport first; the catch-up in slices, never past a screen beyond the viewport

- In the frame, the lines drawn are lexed **synchronously** from the nearest known state above, if the frontier
  is within a budget of them (by default 2 ms of lexing, which lane H2 sets against the `bigtext` session).
- **Further away**, the lines drawn are lexed from `resynchronizationState(for:)` of the first line drawn (or
  from `initialState`), and drawn **provisionally**. They are re-drawn when the frontier reaches them. Neither the
  cache nor the state store keeps a provisional result. That is VS Code's heuristic tokens and CodeMirror's restart
  at the viewport.
- **The catch-up** runs on the main actor between frames, in slices of about 3 ms (Neovim's segment), back to back
  while no input is waiting. It asks for a frame only when a line on screen changed its runs, so an idle editor
  draws nothing (the zero-idle-render rule). The budget is a package seam, not real time, in tests (the
  timed-wake lesson).
- **It stops one screen past the viewport.** Lines below that keep a stale frontier until they are scrolled to,
  as CodeMirror stops past its viewport. An edit that opens a comment therefore costs, at most, the lines down to
  the bottom of the screen, whatever the document's size. Going to the end of the file then costs the gap: a
  provisional screen, then the catch-up through the gap in slices.

### B-ATTRED-13. Marks are ranges stated with the text they were computed from

```swift
TextEditor(text: $source)
    .textEditorMarks(problems.map {
        TextEditorMark($0.range, attributes: AttributeContainer().underlineStyle(.init(pattern: .curly, color: .red)))
    }, in: parsedText)
```

An app's parse can lag the editor by a key or more (tuitree's takes 22 ms). So marks come with the text whose
`String.Index` ranges they are, as LSP diagnostics carry their document version. If that text is the editor's
current one (a storage-identity check, as the binding's), the ranges are used as they are. If it is a text the
editor wrote within its last few edits, the ranges are carried forward through those edits' line splices. An offset
after an edit moves with it, a range around an edit grows or shrinks, and a range wholly replaced shrinks to its
start. If it is neither, the marks are hidden until the app states them again. The editor converts a range to
character offsets once, through the layout (`TextCharacterOffsets`: a binary search of the line starts, then a walk
of one line), and then carries those offsets through its own later edits until the app writes new marks. Marks are
compared by value each frame, as the 2026-11-16 sketch had it. The find bar's matches become one more internal
source of marks, so there is one range-styling path (the code-reuse checklist).

### B-ATTRED-14. The seam: what any styler implements

The engine above sits behind a protocol a styler of any kind can implement:

```swift
/// TUI-specific. Anything that styles a TextEditor's text incrementally: TUI's line-lexer engine,
/// or an app's tree-sitter or language-server bridge.
public protocol TextEditorHighlighter: AnyObject {
    /// The text changed: where (bytes and line/column points, old and new, as tree-sitter's TSInputEdit).
    func textDidChange(_ change: TextEditorTextChange, in source: TextEditorTextSource)
    /// Runs for these lines as far as known now; a run may be provisional.
    func runs(forLines lines: Range<Int>, in source: TextEditorTextSource) -> TextEditorHighlightRuns
    /// Work toward these lines until the deadline; says which lines' runs changed and whether more is owed.
    func advance(toward lines: Range<Int>, in source: TextEditorTextSource,
                 until deadline: ContinuousClock.Instant) -> TextEditorHighlightProgress
}
```

`TextEditorTextSource` is the editor's text by lines: their count, each line's UTF-8 and its starting byte offset.
On the `String` editor a line is a slice of the text's own bytes. On the attributed editor, whose
`AttributedString` has no UTF-8 view before macOS 26, a line is built from the layout's characters when it is
asked for, at a cost proportional to the line and never to the document (a `String` of the whole value would cost
302 ms at 1.9 MB, B-ATTRED-4).

`textDidChange` corresponds to `ts_tree_edit`. `advance(…until:)` corresponds to a parse cancelled by its
progress callback, which resumes on the next call. The changed lines correspond to `ts_tree_get_changed_ranges`,
and `runs(forLines:)` to a highlight query cursor set to a byte range. So a tree-sitter bridge (SwiftTreeSitter,
or Neon's `TreeSitterClient`) is a thin adapter an app or an optional package writes. TUI does not depend on it.
`.textEditorHighlighting(_:)` takes either a `TextEditorLexer`, which TUI wraps in its engine, or a
`TextEditorHighlighter`. This is option (b) of A-ATTRED-5.

### B-ATTRED-15. Guards against a pathological text or lexer

- **A line longer than `maxLexedLineLength`** (20,000 bytes by default, as VS Code's) is drawn unstyled except
  for marks, and its end state is taken as its start state. A lexer that wants more raises the limit in the
  modifier. The byte lexer did a 3.2 MB single line in 7–9 ms, so the limit is for slow lexers.
- **A document past a size** (VS Code's 20 MB) is not refused: nothing in B-ATTRED-11 or 12 grows with the
  document beyond the 4-byte states and the slices.
- **A lexer that never converges** (its state holds a count or a position) re-lexes to the bottom of the screen on
  every key, and no further, by B-ATTRED-12. A debug-build diagnostic, once per editor, reports an edit whose
  re-lex reached the screen's bottom with every state different. The lexer's documentation says what belongs in a
  state.
- **A lexer that is slow per line** is bounded by the synchronous budget. Past it, the screen is provisional and
  then caught up in slices. Keys are never queued behind more than one slice.
- **A lexer that hangs** cannot be pre-empted on the main actor. That is documented as the lexer's contract, as
  for any view body. Moving the catch-up off the main actor (A-ATTRED-7 (b)) would keep the screen live, but would
  not end the hang.
- **Never crash:** bad offsets are clamped, and an empty or absent token list draws the line in the editor's ink.

## 4. What it costs

Measured with the probe (§"For a future reader"): a pretty-printed JSON of 3.2 MB, 119,774 lines and 821,290
tokens, lexed by a byte-level JSONC lexer whose state is one byte (inside a block comment or not). Two runs each.

| | Time | Memory |
|---|---|---|
| The whole document, end states only | 6.6–7.6 ms | 4 bytes a line in the store: 0.5 MB |
| The whole document, keeping every line's tokens | 26 ms | about 7 MB of tokens (not done, B-ATTRED-11) |
| A screenful, 60 lines, from a stored state | 3.0–3.4 µs | the drawn lines' runs, under 0.1 MB |
| A key whose line's end state is unchanged (the usual key) | one line's lexing, well under a microsecond here | none |
| `/*` typed in the middle: every line below re-lexed until the state converges (59,887 lines) | 2.4–2.6 ms; capped at the screen's bottom by B-ATTRED-12 | |
| The whole document as one 3.2 MB line | 7–9 ms | |

A regex lexer is roughly a thousand times slower. VS Code's TextMate engine took 3.9 s for the 1.18 MB
`checker.ts` in 2017 [1], about 0.3 MB a second. With such a lexer, the full pass would take 10 s of slices, and
the engine's cost to a key would stay one line (about 0.1 ms for a 30-byte line) plus, rarely, a provisional
screen. So with B-ATTRED-12 the key
stays at today's 2.6 ms whatever the lexer is, and with a byte lexer even the worst edit fits in a frame. The
probe's process peaked at 40 MB, most of it the probe's own copies of the document.

## 5. What can go wrong

| Case | What happens | Why it is acceptable |
|---|---|---|
| A jump to the end of a large file with a slow lexer | A provisional screen (guessed or initial state), recoloured as the catch-up arrives | VS Code and CodeMirror do the same; the text and marks are right at once |
| A lexer whose state records bracket depth | An unbalanced brace re-lexes to the bottom of the screen each key | That is the lexer's choice. A tree (A-ATTRED-5 (c), or a tree-sitter bridge through the seam) is the tool for structure |
| A minified 3 MB single-line JSON | Unstyled past `maxLexedLineLength`, unless raised; marks still drawn | A byte lexer can raise it at about 2.5 ms a MB |
| An app's marks computed on a text the editor no longer knows | Hidden until restated | Better than misplaced marks; a stale mark is a wrong underline |
| Two editors on one text | Each keeps its own store | As each keeps its own layout today |
| A palette change | Styles re-resolved, no re-lex | B-ATTRED-10 |

## 6. Lanes

After SwiftUI's API (A-ATTRED-2's ruling: L0–L4, L6, L7 of the G3 document), and needing only its L2 (styled
rows). One commit a step. Each lane is gated by the 6.2.4 build and the suite, and the drawing lanes by Stress
`--selfcheck`.

| Lane | What | Days | Tests and measures |
|---|---|---|---|
| **H0** | The engine, package-internal: the interned state store spliced by `EditorLayout.Edit`, the frontier and convergence, a toy lexer | 1 | `HighlightEngineTests`: one line re-lexed for a typical key; a comment opened and closed; splices at the ends |
| **H1** | Drawing: runs into `styledRow`'s accumulator, style interning (B-ATTRED-10), the drawn lines' run cache, precedence (B-ATTRED-8) | ½ | Golden rows; A/B `text-editor`, `bigtext` (expect nothing without a lexer) |
| **H2** | The viewport first, provisional lines, the catch-up slices and their budget seam, frames only for changed lines on screen (B-ATTRED-12) | 1 | Deterministic budget tests (no sleeps); an idle editor renders nothing; a `bigtext-highlighted` Stress session |
| **H3** | Marks (B-ATTRED-13): ranges with their text, carried through the editor's edits, the find bar's matches moved onto them | 1 | `TextEditorMarkTests`: a mark one and two keys stale; a mark around, inside and after an edit; an unknown text hides |
| **H4** | The public API: `TextEditorLexer`, `TextEditorTokens`, `.textEditorHighlighting`, `TextEditorMark`, `.textEditorMarks`; guards (B-ATTRED-15); DocC; CHANGELOG; the Example's Text Input page, in its seven languages | 1 | Compile corpus; the API parity baseline unchanged (no SwiftUI symbol touched) |
| **H5** | If A-ATTRED-6 is (b): JSON(C) and XML lexers (XML covers XML property lists) in an opt-in module | 1½ | Lexer tests from the JSON and XML test suites' samples; `bigtext-highlighted` A/B against `bigtext` |
| **H6** | If A-ATTRED-5 is (b): the public seam `TextEditorHighlighter` (B-ATTRED-14), with a second implementation in tests (a fake "tree" styler that reports changed ranges) | 1 | `HighlighterSeamTests` |
| **H7** | If A-ATTRED-7 is (b): the catch-up off the main actor, on a snapshot of the text, with results stamped by edit count | 1½ | Race tests through the budget seam |

**About 7 lane-days for ★ (H0–H6)**, against 2 for the per-line styler it replaces. **For tuitree, H0–H4: 4½
days** (it can bring its own lexer, or take H5's at 1½ more).

## 7. Questions for the owner

### A-ATTRED-5. The model for highlighting a large source

- **(a) A line lexer only.** The app writes `TextEditorLexer` (a line and the state above, to tokens and an end
  state), and TUI owns everything else. **Price:** H0–H4, 4½ days. A tree-based styler (tree-sitter, a language
  server's semantic tokens) has no way in, short of flattening its output into a line lexer.
- **(b) ★ A line lexer, behind a public seam a tree can use too.** As (a), and the engine's interface
  (`TextEditorHighlighter`: edits in, changed lines out, work under a deadline, runs for the lines drawn, shaped like
  tree-sitter's API) is public. So an app, or a later optional package, can bridge tree-sitter or LSP without TUI
  depending on either. **Price:** H0–H4 and H6, 5½ days; one more public protocol to keep stable.
- **(c) A parse tree in TUI.** Bundle tree-sitter's C runtime and grammars, or write an incremental parser in Swift
  as Lezer is in JavaScript. **Price:** 8 to 15 days. A C dependency for every package consumer on Windows and
  WASM, or a parser generator to maintain, and binary size for apps that never highlight.

★ (b): the line model is what most editors still ship and is enough for JSON, XML, property lists and most
languages. The seam costs a day, and it leaves room for a tree where a language needs one, without TUI owning a
parser. **Default if unanswered:** (a), since (b) adds a public protocol.

**Ruled 2026-11-18: explore (b).** Be wary of excessive complexity and of binary size, and think hard about what the
public API implies: it can bring big benefits, but what are its risks and downsides? §8.1 explores it and recommends
(b) with the seam behind `@_spi` until a second real styler exists (A-ATTRED-10).

### A-ATTRED-6. What TUI ships

- **(a) No lexers.** Apps write their own. **Price:** none; tuitree writes a JSON and an XML lexer itself.
- **(b) ★ JSON(C) and XML lexers in an opt-in module,** à la carte, so an app that does not import it pays
  nothing. XML covers XML property lists. **Price:** H5, 1½ days, and a module to keep.
- **(c) A TextMate grammar interpreter,** loading `.tmLanguage.json` files. **Price:** 5 days or more. Oniguruma's
  regex semantics differ from `Regex` and `NSRegularExpression`, and the result would be a regex lexer at about
  0.3 MB a second.

★ (b): the two formats the driver needs, written as byte lexers (7 ms for 3.2 MB), and a worked example of the
protocol for any app's own lexer. **Default:** (a).

**Ruled 2026-11-18: a variant of (a).** TUI ships no lexers. JSON, XML and others go in their own repository, so
that apps such as tuitree can use them. They do not feel core to TUI, unless a use case is being missed. §8.2 finds
none, and proposes the package's shape (A-ATTRED-12).

### A-ATTRED-7. Where the catch-up runs

- **(a) ★ On the main actor, in slices between frames** (B-ATTRED-12), as VS Code did until 1.81, and as
  CodeMirror and Neovim do. **Price:** in H2. A lexer needs no snapshot and no locks, and a key waits at most one
  slice.
- **(b) Off the main actor,** on a snapshot of the text, with results stamped by edit and dropped when stale, as
  VS Code's worker does. **Price:** H7, 1½ days, and the races it brings. It keeps a slow lexer's catch-up from
  taking any main-actor time, which matters only for regex-speed lexers on multi-MB files.

★ (a): with the catch-up capped at a screen past the viewport, the main actor's share is small, and the protocol
already requires `Sendable`, so (b) can come later without an API change. **Default:** (a).

**Ruled 2026-11-18: explore (b).** Keep the main actor free even of slices, for responsiveness and to use a second
core, and weigh that against complexity and safety. §8.3 does, and recommends (b), with the lines on screen still
lexed in the frame (B-ATTRED-23).

## 8. Rulings of 2026-11-18 and what exploring them found

The owner ruled on A-ATTRED-5 to 7 on 2026-11-18 (recorded under each in §7). This section explores the three, against
`main` at fcbdef3ee, with three new probes (§"For a future reader") on the same machine as §4 (macOS 15.8.3, Apple M4
Max virtual machine, 14 cores, Xcode's Swift 6.2.4, `-O`). New ids: B-ATTRED-19 to 26 (decided here), A-ATTRED-10
to 12 (for the owner).

**In short.**

- **A-ATTRED-7 (b) shapes A-ATTRED-5 (b),** so it comes first (§8.3 before §8.1). If the catch-up runs off the main
  actor, the seam no longer needs "work under a deadline": a styler runs in its own task and pushes results into a
  store the editor owns. So no third-party code runs while a frame draws, and a slow or hung styler can leave lines
  unstyled but cannot stall the editor. That is simpler and safer than the pull seam of B-ATTRED-14.
- **A snapshot is free.** The editor never edits its `String` in place: each edit splices a new one
  (`EditorLayout.replacing(lines:)`), and the attributed editor keeps that same `String` beside its value
  (`AttributedTextSource.string`). A snapshot is two retains (41 ns), and the next edit costs the same with one held
  (459–510 µs either way at 3.2 MB).
- **The worker costs the main actor almost nothing:** 42–83 ns to read a screen's states under the lock, 1.5 µs for
  an edit to splice them. A worker lexing beside 20 edits slowed them by 4% at most (9.23–10.75 ms alone, 9.57–9.81 ms
  together), and both finished in 61–62 ms of wall clock against about 75 ms one after the other.
- **The seam: (b), but behind `@_spi` until a second real styler exists** (A-ATTRED-10). The line lexer, which tuitree
  needs, is public. The seam's code is about 21 KB of unspecialised object code, dead-stripped where unused. What it
  costs is the promise: once public, its push model, its line-granular changes, its UTF-8 units and its isolation are
  fixed until a major release, and today no conformer outside TUI exists to prove them.
- **No lexers in TUI** (A-ATTRED-6): no use in TUI needs one (block Markdown is out of scope, owner 2026-10-27). A
  separate `TUILexers` package depends on `TUITextInput` (A-ATTRED-12). TUI's tests, Stress and the Example keep a
  small JSONC lexer of their own, because the Example cannot depend on a package that depends on TUI.
- **About 6¼ lane-days in TUI** for H0–H4, H6 and H7 (§8.5), against 7 for H0–H6 before. The lexers move to their
  own repository, about 1½ days there.

### 8.1 A-ATTRED-5 (b): the public seam

#### The API

The line lexer stays as B-ATTRED-9 has it, and is public in (a) and (b) alike. The seam is what (b) adds. Both are
sketched below, type-checked under Swift 6 with strict concurrency and strict memory safety (the second probe). The
names are for lane H4 to settle.

```swift
// Public in (a) and (b): the line lexer and its tokens.
public protocol TextEditorLexer: Sendable {
    associatedtype State: Hashable & Sendable
    associatedtype Token: Hashable & Sendable
    var initialState: State { get }
    func lex(_ line: Substring.UTF8View, from state: State, into tokens: inout TextEditorTokens<Token>) -> State
    func resynchronizationState(for line: Substring.UTF8View) -> State?          // default: nil
}
public struct TextEditorTokens<Token: Hashable & Sendable>: Sendable {
    public init()
    @inlinable public mutating func append(_ token: Token, at utf8Offset: Int)  // inlined into the lexer's module
}
extension View {
    public func textEditorHighlighting<L: TextEditorLexer>(
        _ lexer: L, style: @escaping @MainActor (L.Token) -> AttributeContainer) -> some View
}

// What (b) adds: the seam (A-ATTRED-10 asks whether `public` or `@_spi(TextEditorHighlighting) public`).
public protocol TextEditorHighlighter: Sendable {
    associatedtype Token: Hashable & Sendable
    /// Runs off the main actor for as long as the editor shows this highlighter; cancelled when it stops.
    func highlight(_ session: TextEditorHighlightSession<Token>) async
}
public final class TextEditorHighlightSession<Token: Hashable & Sendable>: Sendable {
    public func nextUpdate() async -> TextEditorHighlightUpdate?   // nil once the editor has gone
    public var visibleLines: Range<Int> { get }                   // a hint: what to do first
    @discardableResult                                            // false: stale version or bad line, kept nowhere
    public func publish(_ tokens: TextEditorTokens<Token>, forLine line: Int, of version: Int) -> Bool
    public func checkpoint() async throws                         // cancellation, and a yield (WebAssembly)
}
public struct TextEditorHighlightUpdate: Sendable {
    public var text: TextEditorText                               // the latest text only
    public var change: TextEditorTextChange?                      // every edit since the last update, as one; nil: all new
}
public struct TextEditorText: Sendable {                          // immutable: a snapshot is two retains
    public let version: Int                                       // the editor's edit count
    public let string: String
    public var lineCount: Int { get }
    public func line(_ line: Int) -> Substring.UTF8View           // without its break
    public func utf8Offset(ofLine line: Int) -> Int
}
public struct TextEditorTextChange: Sendable, Equatable {         // by whole lines, as the editor's splice is
    public var oldLines: Range<Int>, newLines: Range<Int>
    public var oldUTF8: Range<Int>, newUTF8: Range<Int>
}
extension View {
    public func textEditorHighlighter<H: TextEditorHighlighter>(
        _ highlighter: H, style: @escaping @MainActor (H.Token) -> AttributeContainer) -> some View
}
```

TUI's own engine is a `TextEditorHighlighter`: its worker is `highlight(_:)`, and publishes through the same store a
tree-sitter bridge would, so the seam is exercised by every highlighted editor, not only by a test. The one thing the
engine has that the seam lacks is the synchronous lexing of the lines on screen (B-ATTRED-23). That stays internal,
because it calls the app's pure line function in the frame, which the seam is designed never to do.

#### Decided here

- **B-ATTRED-19. A styler sees the editor's `String`, on both editors.** The snapshot is the version, the `String`
  and its line starts. B-ATTRED-14 assumed the attributed editor would build each line from its characters, because
  `AttributedString` has no UTF-8 view before macOS 26. L4 made that unnecessary: `AttributedTextSource` keeps the
  value's characters as a `String`, written by the same splice as the plain editor's. A `String` of the whole value
  would cost 410–422 ms at 3.2 MB (probe), so the value itself is never read by a styler.
- **B-ATTRED-20. The seam pushes; the editor never waits on a styler.** The store (a `Mutex` in the session) holds
  the latest text, the coalesced change not yet taken, the lines on screen and the tokens published. A frame reads
  tokens under the lock and runs no styler code. `publish` validates on the styler's thread: offsets that go
  backwards or past the line are clamped, a line out of range or a stale version is refused. It asks for a frame only
  when a line on screen changed. The store keeps tokens for the lines on screen and a screen either side, as the
  drawn lines' cache does (B-ATTRED-11), however much a styler publishes.
- **B-ATTRED-21. Changes are by whole lines, coalesced, and only the latest text is kept.** A change is what
  `EditorLayout.Edit` already has (lines replaced, lines in their place, and their bytes). Edits that arrive while a
  styler is busy fold into one change, so a slow styler holds one old text alive, never a queue of 3 MB texts. That
  is enough for tree-sitter (one `ts_tree_edit` with points at column 0, then a reparse of slightly more than the
  edit) and for an LSP client (one ranged change with the new lines' text). A value the app writes whole arrives as
  an update with no change.
- **B-ATTRED-24. Stale results.** The line engine drops a slice whose version has passed and starts again from the
  new frontier. For a styler that lags (an LSP server answers in tens of milliseconds), tokens of lines an edit kept
  move with their lines, and tokens of a line edited in place (as many lines after the edit as before) are kept as
  provisional until the styler publishes again. So a lagging styler's colours neither vanish nor flicker while
  typing.
- **B-ATTRED-25. A lexer or highlighter of the same type is the same one** across body evaluations, unless it is
  `Equatable` and unequal, as `.task(id:)` restarts only on a new id. Otherwise every body evaluation would restart
  highlighting.
- **B-ATTRED-26. Units.** Lines split at LF, CRLF and a lone CR, as `EditorLayout` splits them, numbered from 0.
  Offsets are UTF-8 bytes from the line's start. These match tree-sitter's points (rows, byte columns), except that
  tree-sitter does not count a lone CR as a line break, which a bridge maps. LSP counts lines as TUI does, and
  columns in UTF-16 unless a server agrees to UTF-8 (3.17's `positionEncoding`), which a bridge converts per line.
  The line parameter is `Substring.UTF8View`: `Span` would be better, but `String`'s span needs macOS 26 (cost
  ledger M3, M4). Adding a `Span` requirement later is additive, with each requirement's default calling the other,
  as `Collection`'s do.

#### Risks and costs

| Concern | What it costs or risks | How the design answers it |
|---|---|---|
| **API stability** | Before 1.0, nothing. After 1.0 (policy decisions B and 7), a public protocol that apps *conform to* is harder to evolve than one they call. A minor release can add requirements only with defaults. It cannot change a requirement's signature, the protocol's isolation (`Sendable` and off the main actor), whether `highlight` is `async`, or the meaning of an update. The push model, line-granular changes, UTF-8 units and line numbering are fixed until 2.0, and so is the session's lifetime: one session per editor, cancelled when it goes | Strict first: requiring `Sendable` now can be relaxed later without breaking a conformer, never the other way. The session is a final class, so members can be added in a minor release. `@_spi` until a second conformer exists (A-ATTRED-10) |
| **What it commits TUI to** | Line-granular edits forever (finer edits can be added, coarser cannot be taken back); `version` as an edit count; a text snapshot per version (cheap only while the editor never edits its `String` in place: an in-place edit would make the first edit after a snapshot copy the text, 184–204 µs at 3.2 MB in the probe instead of 28–32 µs) | The editor builds a new `String` per edit today, and TUI needs the snapshot for its own worker whatever the seam does |
| **A slow or hung styler** | With the pull seam (B-ATTRED-14), it ran in the frame and stalled the editor | It runs only in its own task. Lines it has not styled are drawn in the editor's ink (or provisionally, B-ATTRED-24). On WebAssembly, a styler that never reaches `checkpoint()` holds the only thread, as any task can. That is documented, and cannot be defended against |
| **A buggy styler** | Offsets out of order or out of range, lines past the end, results for an old text, a flood of results | Clamped, refused, refused, and bounded to the window of B-ATTRED-20; frames requested only for lines on screen, and coalesced by the frame pacer |
| **Testability** | A third party cannot make a session (its initialiser is internal), so cannot test a bridge without an editor | When public: a driveable session in `TUITesting` (apply an edit, read what was published), about ½ day. TUI's own tests drive the engine's slice function directly, with the budget seam, and never race |
| **Documentation** | A DocC article: the lexer (a page) and the seam (a page more: the push model, the units, cancellation, `checkpoint()` on WebAssembly, B-ATTRED-25); symbol documentation; the Example's page in seven languages for the lexer | About ½ day of H4 for the seam's half |
| **SwiftUI parity** | SwiftUI has no highlighting API for `TextEditor` (§2). Both modifiers are TUI extensions under their own names, and shadow nothing (CLAUDE.md, "Extending SwiftUI's API"). If SwiftUI adds one (TextKit 2 has rendering attributes, so it could), TUI would adopt SwiftUI's spelling and deprecate its own: one deprecation cycle, ending at the next major | Distinct base names (`textEditorHighlighting`, `textEditorHighlighter`), so no overload set grows and neither can make a SwiftUI call ambiguous |
| **Binary size** | Lexer protocol and tokens: 2.3 KB of object code. The seam, with a minimal catch-up adapter: 23.7 KB (17.3 KB of `__text`), unspecialised, `-O -wmo` (probe 2). The real engine is (a)'s cost either way | An app that never highlights loses it to `DeadStripUnusedAPI`; one that does carries about 20 KB more for (b) |
| **Compile time** | The sketch's 250 lines compile in 0.29 s more than the lexer's alone (0.20 s, 0.49 s). In apps: one generic modifier per entry point, and a style closure that is a `switch` | In the noise for `TUITextInput`. No overloads, so no new type-checking at existing call sites |
| **No conformer yet** | Nobody has asked for tree-sitter or an LSP styler. A seam designed with no second user is the likeliest to be wrong (the rule of three) | Keep it `@_spi` until one is written against it; promote in a minor release, which is additive |

**The alternatives.** `package` access does not cross packages, so a seam made `package` could be used only inside
TUI, and a tree-sitter bridge would then have to live in TUI too. `@_spi(TextEditorHighlighting) public` reaches
another package that asks for it (`@_spi(TextEditorHighlighting) import TUITextInput`). The API stability policy
already leaves SPI outside the promise ("and `@_spi` (there is none)"). Two small costs: DocC leaves SPI symbols out
of the catalog, so the seam would be documented in its doc comments only; and `api_baseline.py` must skip SPI
declarations, which needs checking. Swift's own packages use SPI this way (swift-syntax, swift-nio), and SwiftUI
has its own (`@_spi(SwiftUI)`, cited in `TUIView`).

**Recommendation: (b), with the seam `@_spi` first** (A-ATTRED-10). TUI's engine is built behind the seam anyway,
because the worker of §8.3 needs the same store, so the seam costs about ½ day more, not the day H6 priced. Its
promise waits for the first real bridge.

### 8.2 A-ATTRED-6: no lexers in TUI

**Confirmed: no use in TUI needs a built-in lexer.** Checked:

- **Markdown code blocks.** TUI parses inline Markdown only (`InlineMarkdownParser` in `TUIStrings`). Block
  Markdown, code blocks included, was ruled out of TUI on 2026-10-27 (MARKDOWN-SCOPE: a separate package atop TUI).
  An inline code span has no language to highlight.
- **DocC.** DocC highlights the catalog's code itself.
- **The file dialog's preview** shows a text file's opening lines as `Text(verbatim:)`
  (`FilePanelPreview.swift`). Highlighting them would be new behaviour, not a need. Quick Look shows source as
  plain text too.
- **The terminal compatibility survey, Stress, the Example, the tests.** The survey has no highlighting. The
  others need a lexer only to exercise and show the feature.

**The separate package (A-ATTRED-12).** A `TUILexers` package, in its own repository beside TUI's:

- **Products per language, à la carte:** `TUIJSONLexer` (JSON, JSONC, JSON5's comments) and `TUIXMLLexer` (XML,
  with property lists' conventions) first. An app links only the languages it imports.
- **Each lexer** is a `TextEditorLexer` with a public `Token` enum, a one- or two-byte `State`, and a default style
  (`JSONLexer.Token.defaultStyle`, from the palette's semantic colours) that an app can replace.
- **It depends on TUI's `TUITextInput` product only,** for `TextEditorLexer` and `TextEditorTokens`. An app that
  uses it already depends on TUI. A dependency-free core, with an adapter product for TUI, would let a non-TUI
  program use the lexers too. It would cost an adapter and about ½ day more, so it waits for such a program.
- **Versions** follow TUI's major (TUILexers 1.x needs TUI 1.x), and its CI builds against TUI's `main` and latest
  release.
- **Tests:** samples from the JSON and XML test suites; a fuzz test that every token offset is in range and that
  lexing never traps; a throughput benchmark in MB/s.

**What TUI keeps.** SwiftPM refuses a dependency cycle between packages, so TUI's Example and Stress cannot use
`TUILexers`. They need a lexer to show and to measure the feature (the Example's Text Input page, Stress's
`bigtext-highlighted`). So TUI keeps one small JSONC byte lexer, about 150 lines (the probe's), in an internal target
that is not a product, as `TUIWidthCorpus` is. Tests, Stress and the Example use it, and no package consumer ever
builds it. The engine's tests use toy lexers written in the tests: a block-comment lexer for convergence, one whose
state never converges (B-ATTRED-15), and a fake tree styler for the seam (H6).

### 8.3 A-ATTRED-7 (b): the catch-up off the main actor

#### What a snapshot costs (probe 1)

A pretty-printed JSON of 3,200,067 bytes and 172,714 lines, shorter lines than §4's 119,774, lexed by the same kind
of one-byte-state JSONC lexer. Two runs each; the second ran at a load average of 7, because other lanes were
building.

| | Time |
|---|---|
| A full pass, states only, on the main actor | 3.31–3.38 ms |
| The same pass in a `@concurrent` task, awaited from the main actor | 3.52–3.69 ms |
| Starting a `@concurrent` task and awaiting its value | 41–351 µs (latency under load, not main-actor work) |
| A snapshot: the version, the `String` and its line starts (two retains) | 41–42 ns |
| The editor's own edit (a new `String` spliced from the old), no snapshot held | 459–487 µs |
| The same, with a snapshot held | 462–510 µs: the same |
| An in-place `String` insert in the middle, unique / with a snapshot held | 28–32 µs / 184–204 µs (the copy) |
| An in-place `[Int]` line-starts splice, unique / with a snapshot held | 15–18 µs / 105–109 µs |
| `AttributedString` (24,674 runs): a snapshot / an insert, unique / with a snapshot held | 292 ns / 19–21 µs / 19–21 µs (its rope copies only the path it changes) |
| A `String` of the whole `AttributedString` | 410–422 ms |
| The worker, in slices of 4,096 lines, each published under a `Mutex` / of 512 lines with a yield each | 3.28–4.69 ms (43 slices) / 5.62–6.87 ms (338) |
| The main actor reading a screen's 60 states and the frontier under that lock | 42–83 ns |
| The main actor splicing an edit into the store under that lock | 1.5 µs |
| 20 editor edits alone / while a worker made 20 full passes / those passes alone | 9.23–10.75 ms / 9.57–9.81 ms / 65.0–65.8 ms |
| Wall clock for both at once (about 75 ms one after the other) | 61.3–62.3 ms |
| `/*` typed mid-document: every line below re-lexed, without the cap | 0.89–0.90 ms |

So copy-on-write never costs the editor anything today, because nothing it snapshots is mutated in place: the
`String` and both start arrays are built afresh by each edit. If a later change made those edits in place, the
first edit after a snapshot would copy, at a tenth of a millisecond to a fifth. The worker would let go of its
snapshot at its next slice, so only edits made while it holds one would pay.

**A lead the probe turned up (not this design's business):** rebuilding a 172,714-entry start array the way
`EditorLayout.replacing(lines:)` does (a prefix, then the rest shifted through `lazy.map`) took 2.64–3.67 ms. An
in-place splice took 15–18 µs. The editor rebuilds two such arrays a key. This was measured in the probe, not in
TUI. It is worth a profile of the `bigtext` key before anyone relies on it.

#### The design

```
 main actor                                            worker (a task on the global concurrent executor)
 ─────────                                             ──────────────────────────────────────────────────
 an edit: splice the store's states, version += 1  ─┐   loop: take the latest text, change and frontier (lock)
          move the frontier, ring the doorbell      ├─►       lex from the frontier for 3 ms, unlocked, on the snapshot
 a frame: lines on screen lexed in the frame from  ─┘       publish the slice's states (lock): dropped if the version moved
          the nearest known state (B-ATTRED-23),           a line on screen changed? hop to the main actor (StateBox
          reading the store under the lock (42-83 ns)        write, as AsyncImage does): memo invalidated, frame asked
                                                            checkpoint(): cancelled? yield; up to the viewport + a screen
```

- **B-ATTRED-22. The worker is an ordinary task.** It is started through `LifecycleManager.startTask(token:priority:
  name:operation:)` with a `@concurrent` operation, `.userInitiated` (as `AsyncImage`'s load) and a name
  ("TextEditor highlighting", which macOS 15 drops: cost ledger M7). It is cancelled when the editor disappears or
  B-ATTRED-25 sees a new lexer. Snapshot renders start no tasks (`firesEffects`), so golden snapshots draw only what
  the frame lexes, and stay deterministic. It needs no change to the run loop: (a)'s slices would have needed a
  main-actor task interleaved with input, which is about as much code.
- **Slices are bounded by time, not lines** (3 ms, Neovim's segment), so a regex-speed lexer's slice is as short as a
  byte lexer's. At each slice's end the worker publishes, checks the version, and calls `checkpoint()`. An edit
  therefore wastes at most one slice of the worker's work, and never waits for it.
- **Results come back without a hitch.** They are written into the store by the worker, under the lock, a slice's
  states in one copy. The main actor merges nothing: the next frame reads them. Only when a line on screen changed
  does the worker hop to the main actor, for one `StateBox` write that invalidates the editor's memo and asks for a
  frame. That is `AsyncImage`'s pattern (`await MainActor.run { guard !Task.isCancelled … }`), so no new route to a
  frame is invented.
- **Ordering.** The version is the only clock. An edit bumps it under the lock, and a publish checks it under the same
  lock, so a slice lexed from an old text can never land on a new one. A frame request that arrives late draws the
  current state, which is harmless.
- **Interning off the main actor.** Interning each line's end state under the lock would cost a lock a line, which
  would double a full pass. The worker interns only where a line's state differs from the line above's (rare: a
  comment's start or end), and does it at publish.
- **Swift 6.2.** The lexer is a `Sendable` value, the snapshot is values, the store is a `Mutex` in a `Sendable` final
  class, and the worker is `@concurrent`, so the compiler proves the sharing. **Measured (probe 3):** an app module
  built with Swift 6.2's default main-actor isolation and Xcode 26's approachable-concurrency features
  (`InferIsolatedConformances`, `NonisolatedNonsendingByDefault`) conforms a plain `struct JSONLexer: TextEditorLexer`
  without `nonisolated` and without a diagnostic, and TUI can call it off the main actor. A lexer that touches
  main-actor state is refused at compile time ("main actor-isolated var … can not be mutated from a nonisolated
  context"). So the protocol costs an app nothing in such a module, and the compiler catches the one real mistake.
- **The lexer runs on two threads at once:** the main actor's lines on screen, and the worker's catch-up. A
  `Sendable` value with a pure `lex` (its documented contract) makes that safe. An `@unchecked Sendable` lexer with
  hidden mutable state is the app's own race.
- **Platforms.** Linux and Windows run the worker on the global executor's thread pool, and `Mutex` is in
  `Synchronization` everywhere (`AppStorage` already uses it). `TUITextInput` does not build on Windows yet, and
  nothing here adds POSIX. **WebAssembly** (wasip1) has one thread: the "worker" runs on the cooperative executor
  between the run loop's 8 ms stdin polls (WebAssembly port, `StdinArrivalNotifier`). Each 3 ms slice ends in
  `checkpoint()`, so input waits at most one slice. That is exactly (a), with the same code and no `#if`.
- **Priority inversion and memory.** The main actor waits on the lock only while the worker copies a slice's states
  (microseconds), and Darwin's `Mutex` donates priority. A snapshot held by the worker keeps one old text alive (3.2
  MB, and 1.4 MB of start array, here) until its next slice.

**B-ATTRED-23. The lines on screen are still lexed in the frame, on the main actor.** This is what the line engine
keeps from (a), and the one place app code runs in a frame. Without it, every key would draw its line with the old
tokens shifted, or unstyled, for a frame (16.7 ms or more), until the worker's answer came. So would every line a
scroll brings into view. Typing a `"` that opens a string would colour the rest of the line one frame late. VS Code
keeps a viewport tokenizer on the UI thread beside its worker (`tokenizeHeuristically` [3]). Neon makes it the point of its
synchronous providers [22]. The price is a screenful: 3.0–3.4 µs with a byte lexer (§4), and the 2 ms budget of
B-ATTRED-12 at worst. If the owner prefers no lexing at all on the main actor, the cost is that flash after each key
and each scroll. Third-party stylers behind the seam always work without the frame's help (B-ATTRED-24).

#### What (b) buys, honestly

With the cap of B-ATTRED-12, the catch-up after an edit is at most the lines down to a screen past the viewport:
microseconds with a byte lexer. So for TUI's byte lexers on today's files, (b) saves the main actor little. It
matters:

1. **After a jump** far ahead: the gap is caught up on another core (3.3–4.7 ms at 3.2 MB with a byte lexer, about
   10 s with a regex-speed one), while the main actor draws and takes keys.
2. **For slow lexers** in general: a regex lexer's slices never take main-actor time.
3. **For stylers behind the seam:** a tree-sitter parse of a large file, or an LSP round trip, is long or
   asynchronous by nature.
4. **If the cap is lifted** (A-ATTRED-11): running to the document's end becomes background work.

**The risks it brings,** and their answers: data races (the compiler proves the sharing, and version stamps stop
stale writes); nondeterministic tests (the slice function is driven directly with the budget seam, as the
timed-wake lesson wants; one stress test runs the real worker under the thread sanitizer); a second core's energy
(bounded by the cap); and a held snapshot's memory (one old text).

**Complexity against (a).** (a)'s H2 is about 150 lines (a main-actor slice task and its budget). (b) adds the
locked store and versions (about 80 lines), the worker loop and its lifecycle (about 70), and publishing with the
hop (about 50): about 200 lines more, and about 300 lines of tests (deterministic stepping, a stale slice dropped,
an edit mid-slice, cancellation, and the sanitizer run). **H2 and H7 together: 2 lane-days, against H2's 1.**

**Recommendation: (b),** with B-ATTRED-23. It costs a day more than (a). It keeps the main actor's share to the
lines it draws, uses a second core where there is one, and degrades to (a) on WebAssembly by itself. It also makes
the seam of §8.1 simpler and safer. Without the worker, the seam would have had to run third-party code in the
frame.

### 8.4 For the owner

#### A-ATTRED-10. How the seam ships

*The `TextEditorHighlighter` seam of §8.1: a tree-sitter or LSP styler plugs into the editor through it.*

- **(a) Public at once.** **Price:** about ½ day (H6) plus ½ day for a driveable session in `TUITesting`, and from 1.0
  on, the push model, line-granular changes, UTF-8 units, isolation and session lifetime are fixed until 2.0, before
  any styler has been written against them.
- **(b) ★ `@_spi(TextEditorHighlighting) public` until a second real styler exists,** then public in a minor release
  (additive). **Price:** the same ½ day. Also: `api_baseline.py` must skip SPI (to check, about ¼ day), the API
  stability policy's "there is none" line changes, and the seam is documented in doc comments only (DocC leaves SPI
  out). Users write `@_spi(TextEditorHighlighting) import TUITextInput` and accept that it may change.
- **(c) Internal (`package`).** **Price:** saves ½ day. No other package can use it, so a tree-sitter bridge would
  have to live in TUI.

★ (b): the engine is built behind the seam either way. It is the promise, not the code, that wants a user first.
**Default if unanswered:** (b), since it promises nothing.

**Ruled 2026-11-19: (b).** The seam is `@_spi(TextEditorHighlighting) public` until a second real styler exists, then
public in a minor release. H6 builds it so, with `api_baseline.py` taught to skip SPI.

#### A-ATTRED-11. How far the catch-up goes, now that it is off the main actor

- **(a) ★ As B-ATTRED-12: to a screen past the viewport.** A jump far ahead draws one provisional screen, corrected
  when the worker reaches it (3.3–4.7 ms at 3.2 MB with a byte lexer). **Price:** none.
- **(b) To the document's end after every edit that changes an end state.** No provisional screens with a byte
  lexer, and every line's state known (a minimap or an outline could use them). **Price:** a background core for
  0.9–4.7 ms per such edit with a byte lexer; with a regex-speed lexer, about 10 s, restarted by each key typed
  while a comment is open.
- **(c) To the end only for a lexer measured fast** (its last catch-up's MB/s over a threshold), else (a). **Price:**
  about ½ day, and behaviour that depends on a measurement.

★ (a): with a byte lexer the difference is one frame after a jump. (b) or (c) can come when an app wants a minimap,
without an API change. **Default:** (a).

**Ruled 2026-11-19: (a).** The catch-up runs to a screen past the viewport, as B-ATTRED-12 has it.

#### A-ATTRED-12. The lexers' package

- **(a) ★ `TUILexers`, a repository beside TUI's,** with a product per language (`TUIJSONLexer`, `TUIXMLLexer`),
  depending on `TUITextInput` (§8.2). **Price:** H5's 1½ days, moved there, and a repository for the owner to create
  (repository names are held for the owner).
- **(b) The same, with a dependency-free core** and an adapter product for TUI. **Price:** about ½ day more. Pays
  only if a program without TUI wants the lexers.
- **(c) In tuitree for now,** extracted when a second app wants them. **Price:** none now. Only tuitree has them.

★ (a): the ruling asked for a repository other apps can use, and every user named so far uses TUI. **Default:** (a)
once the owner names the repository, else (c).

**2026-11-19: (a), tentatively.** The owner leaned to (a) and asked, for (b), how much the lexers depend on TUI and how
useful they would be without it. The answer given: they are not written yet; what would touch TUI is only the
`TextEditorLexer` conformance, the token type it returns and the default palette's colours, and a lexer's state
machine itself needs nothing of TUI's. Without TUI they would be modestly useful (another terminal or GUI editor,
a formatter, a linter), since a byte lexer for JSON or XML is small. Proposed: (a), with each language's lexing in a
target that imports nothing of TUI's inside `TUILexers`, and the TUI conformance in the product beside it, so that
(b) is additive later at no cost now. Still open: the owner's final word, and the repository's name, which the owner
creates.

**Ruled 2026-11-19, final: none of (a) to (c).** TUI writes no lexers, and there is no `TUILexers` repository.
Highlighting for JSON, XML and other languages comes from tree-sitter (SwiftTreeSitter and grammar packages such as
TreeSitterJSON and TreeSitterXML), plugged in through a thin adapter on the `TextEditorHighlighter` seam. The
adapter lives in an app (tuitree) or an optional package, never in TUI. In the owner's words: "I just don't want to
invest significant time in that, especially if it's highly unoriginal work." A language server may come later
through the same seam, for code-editing apps. A-ATTRED-10 (b) (the seam `@_spi` until a second real styler
exists), A-ATTRED-11 (a) (to a screen past the viewport) and A-ATTRED-7 (work off the main actor) stand. §8.6
re-plans TUI's side.

### 8.5 The lanes, as they now stand

| Lane | Change | Days |
|---|---|---|
| H0, H1, H3 | As §6 | 1, ½, 1 |
| H2 + H7 | One lane: the viewport in the frame (B-ATTRED-23), the worker, the locked store and versions (B-ATTRED-20 to 25) | 2 |
| H4 | As §6, with the lexer public and the seam as A-ATTRED-10 rules | 1 |
| H5 | Moves to `TUILexers` (1½ days there); TUI keeps the internal JSONC lexer target (§8.2) | ¼ in TUI |
| H6 | The seam over the engine's store, its SPI or public attribute, the fake tree styler | ½ |

**About 6¼ lane-days in TUI**, against 7 before. The 11-17 plan's H0–H6 is now H0–H4, H6 and H7, with H5's lexers
in their own repository.

*Superseded on 2026-11-19 by §8.6, after A-ATTRED-12's final ruling.*

### 8.6 Tree-sitter instead of lexers: TUI's side, re-planned (2026-11-19)

Written against `main` at c05417ca8, with a fourth probe (§"For a future reader"): a throwaway package that links
SwiftTreeSitter 0.25.0, tree-sitter's C runtime 0.25.10, TreeSitterJSON 0.24.8 and TreeSitterXML 0.7.0, built and
run on the same machine as §8 (macOS 15.8.3, 14 cores, Xcode's Swift 6.2.4, `-c release`, a load average of about 7
from other lanes). New ids: B-ATTRED-27 to 30 (decided here), A-ATTRED-15 and 16 (for the owner).

#### What tree-sitter changes

The line engine of B-ATTRED-11 and 12 (an interned end state per line, the frontier, convergence, the screen lexed
in the frame, the catch-up in 3 ms slices) is how TUI would have run a *line lexer*. Tree-sitter needs none of it.
It keeps its own tree, re-parses after `ts_tree_edit` by reusing the old tree's unchanged parts [12], says where
the tree changed (`ts_tree_get_changed_ranges` [13]), and answers a highlight query for any byte range [26]. So
the whole incremental machinery is the styler's, and TUI's share shrinks to what any styler needs from an editor:

| TUI still owns | Why a tree-sitter styler cannot do it | Where |
|---|---|---|
| The layer: runs drawn over the text, never written into it; styles interned per token; precedence under marks, find and selection | Only the editor draws | B-ATTRED-8, 10; H1 |
| The seam: versioned snapshots, edits coalesced by whole lines, the styler's task started and cancelled with the editor | Only the editor sees its edits, and owns the task's lifetime | B-ATTRED-19 to 22, 25; H6′ |
| The viewport first: the lines on screen as a hint, and an update when they move | Only the editor knows what it shows | B-ATTRED-20, 27 |
| The off-main hand-off: a locked store the styler publishes into, a frame asked only when a line on screen changed, stale versions refused | The frame must never wait on a styler (A-ATTRED-7) | B-ATTRED-20, 24, 28 |
| Marks tied to the text they were computed from | An app's parse errors and the find bar's matches are not highlighting | B-ATTRED-13; H3 |
| The guards: clamped offsets, refused lines and versions, a bounded window, an over-long line drawn unstyled | A buggy or slow styler must not cost the editor | B-ATTRED-15, 20, 30 |

What goes: the state store and its interning, the frontier and convergence, `resynchronizationState`, the screen
lexed in the frame (B-ATTRED-23), the catch-up slices and their budget seam, and the guards that exist for a
non-converging or slow-per-line lexer. B-ATTRED-23 existed because a line lexer is a pure function TUI could call in
the frame. A tree-sitter parse cannot be (16–17 ms a key at 3.2 MB, below), so the line just typed is drawn with its
old tokens until the styler publishes, which B-ATTRED-24 and 28 make close to invisible.

**Does the public line-lexer protocol still earn its place?** Not on present evidence. Its users would be an app
with a hand-written lexer, and the two named so far (tuitree's JSON and XML) are now tree-sitter's. TUI's own
Example, Stress and tests need a styler to show and measure the feature, but strict JSON has nothing that spans
lines (a string cannot hold a raw line break), so a stateless line styler over the seam is exact for them. The
engine is a few hundred lines and about two days of lanes for a protocol with no user outside TUI. It can come back in a minor
release, additively, if an app asks: A-ATTRED-15.

#### What the adapter needs from the seam, checked against SwiftTreeSitter

Read from SwiftTreeSitter 0.25.0's source [25] and tree-sitter 0.25.10's `api.h` [26]:

- **Edits.** `InputEdit(startByte:oldEndByte:newEndByte:startPoint:oldEndPoint:newEndPoint:)`, applied with
  `MutableTree.edit(_:)` (or `Tree.edit(_:)`, which returns an edited copy), then `Parser.parse(tree:…)` with the
  edited tree to re-parse [25: `InputEdit.swift`, `Tree.swift`, `Parser.swift`]. B-ATTRED-21's change maps onto it
  directly: `startByte` is `oldUTF8.lowerBound`, `oldEndByte` is `oldUTF8.upperBound`, `newEndByte` is
  `newUTF8.upperBound`, and the points are (line, 0) at each end. Edits coalesced into one whole-line change are one
  wider `InputEdit`, which tree-sitter takes as it takes any edit. Measured: `edit` alone is 2–7 µs.
- **Changed ranges.** `Tree.changedRanges(from:)` (or `MutableTree.changedRanges(from:)`) over
  `ts_tree_get_changed_ranges`, returning `TSRange`s with bytes and points [25: `Tree.swift`]. tree-sitter documents
  them as where "the hierarchical structure of syntax nodes" changed [13], so the text just typed inside a token is
  not necessarily in them: the adapter adds the edit's new bytes. It maps the bytes to lines, keeps those in the
  window, and queries only those.
- **Highlight queries over a byte range.** `Query(language:data:)` from a `highlights.scm`, `query.execute(in:)` for
  a `QueryCursor`, `setByteRange(range:)`, then `nextCapture()`; each capture has `node.byteRange` and its capture
  name [25: `Query.swift`]. A match that overlaps the range is returned whole [26:
  `ts_query_cursor_set_byte_range`], so the adapter clips captures to each line, splits a capture that spans lines
  (a comment), and flattens nested captures (a pair's key is also a string) into the seam's flat runs, with a "none"
  token for the gaps. Measured: a 60-line screen's captures in 0.15 ms, whatever the document's size.
- **Points against the seam's units.** tree-sitter's points are (row, column), the column in bytes of the input's
  encoding, and a row ends only at LF [12]. With a UTF-8 parse, the column is exactly B-ATTRED-26's UTF-8 offset
  from the line's start, and the rows are TUI's lines for LF and CRLF text. They differ only for a lone CR, which
  TUI counts as a break and tree-sitter does not. SwiftTreeSitter's own comment on `InputEdit` says the points are
  optional for a client that does not use line-relative positions [25: `InputEdit.swift`], and incremental reuse
  works on bytes, so an adapter that works in bytes throughout is right even for lone-CR text.
- **Three traps in SwiftTreeSitter.** It is built for UTF-16 and `NSRange` (TextKit's units):
  1. `Parser.parse(_:)` and `parse(tree:string:)` encode the text as UTF-16, and `parse(tree:readBlock:)` defaults
     to `TSInputEncodingUTF16LE` [25: `Parser.swift`]. The adapter passes `encoding: TSInputEncodingUTF8` and a read
     block over the snapshot's UTF-8. Measured: that read block, which copies a chunk into `Data`, costs the same as
     handing tree-sitter's C API the whole buffer (within the noise, at every size below).
  2. Every `NSRange` helper (`Node.range`, `QueryCursor.setRange`, `NamedRange.range`) halves byte offsets
     [25: `Encoding+Helpers.swift`], so it is wrong for a UTF-8 parse. So is the stock text provider that query
     predicates read through (`String.predicateTextProvider` takes an `NSRange` [25: `String+TextProvider.swift`,
     `Predicate.swift`]). TreeSitterXML's highlights use `#any-of?`, so the adapter gives the cursor its own text
     provider, which reads by the point range it is also handed.
  3. Cancellation: SwiftTreeSitter offers only `Parser.timeout`, over `ts_parser_set_timeout_micros` [25:
     `Parser.swift`], which tree-sitter 0.25 marks deprecated ("will be removed in 0.26") for
     `ts_parser_parse_with_options` and its progress callback [26]. SwiftTreeSitter pins tree-sitter
     `.upToNextMinor(from: "0.25.0")` [25: `Package.swift`], while tree-sitter is at 0.27.2 (2026-11-07) [30]. An
     adapter that wants to stop a long parse when a newer version arrives calls `ts_parser_parse_with_options`
     itself (`import TreeSitter`, about 60 lines). Importing both modules makes `TSRange` ambiguous, so it is
     spelled `SwiftTreeSitter.TSRange` (a compile error in the probe).
- **The queries ship as resource bundles.** Each grammar target copies its `queries` folder as a SwiftPM resource
  [27][28], and `LanguageConfiguration(_:name:)` finds it as `TreeSitterJSON_TreeSitterJSON.bundle` under
  `Bundle.main.resourceURL` [25: `LanguageConfiguration.swift`]. A terminal tool is often installed as a lone
  binary, without its bundles, so the adapter embeds each `highlights.scm` it uses (a few lines each; MIT licensed)
  and builds its `Query` from the text.

**Decided here.**

- **B-ATTRED-27. An update comes on a scroll too.** B-ATTRED-21's updates carried edits. A styler that styles only
  the window, as the tree-sitter adapter does by query, must also hear when the lines on screen move. So
  `nextUpdate()` returns when the viewport moves, with the lines on screen in the update; the version is unchanged
  by a scroll, which is how a styler tells one from an edit.
- **B-ATTRED-28. A line edited in place keeps its tokens shifted.** B-ATTRED-24 kept an edited line's old tokens as
  provisional at their old offsets. The editor knows the edit's column and length, so it moves the offsets past the
  edit by the bytes inserted or removed. Typing inside a string then keeps the closing quote's colour where it was
  until the styler publishes (0.4 ms later at 100 KB, a frame or two at 3.2 MB). Internal; no API.
- **B-ATTRED-29. What the seam adds for a tree styler.** `TextEditorText.line(containingUTF8Offset:)` (a binary
  search of the line starts the snapshot already has), to map changed ranges and captures to lines;
  `TextEditorText.withUTF8(_:)`, the whole text's UTF-8 borrowed without a copy, for a parse through tree-sitter's C
  API; and a batch `publish(_:forLines:of:)`, so a window of 60 or 180 lines takes the lock once, not once a line.
- **B-ATTRED-30. The cap bounds styling, not parsing.** A-ATTRED-11 (a) stands, but a tree-sitter parse covers the
  document (it is cheap after an edit because the old tree is reused, not because it stops early). What the cap
  bounds is what the styler is asked for and what the store keeps: the lines on screen and a screen either side
  (B-ATTRED-20). The long-line guard of B-ATTRED-15 stays: a line past 20,000 bytes (raisable in the modifier) is
  drawn unstyled except for marks, and the session tells the styler not to style it, since a minified file's one
  line would otherwise be hundreds of thousands of tokens.

#### What it costs: probe 4

A pretty-printed JSON built as §8.3's was (an array of records of seven lines), at three sizes. Medians of 5 full
parses, 9 edits and 51 queries, two or three runs each; "C API" is the same edit through `ts_parser_parse_string_encoding`
with the whole buffer, to split SwiftTreeSitter's share from tree-sitter's.

| | 100 KB (5,464 lines) | 1 MB (53,344 lines) | 3.2 MB (168,095 lines) |
|---|---|---|---|
| A full parse | 7.3–7.8 ms | 70–76 ms | 237–241 ms |
| A letter typed in a string: `edit`, re-parse with the old tree, changed ranges | 0.41–0.42 ms | 4.3–4.7 ms | 15.5–17.3 ms |
| Of the letter's and the quote's, the re-parse / the changed ranges (C API, one run) | 0.19–0.20 / 0.19–0.20 ms | 2.2–2.7 / 2.2–2.8 ms | 7.3–9.0 / 6.7–7.2 ms |
| A `"` typed, opening a string | 0.41–0.42 ms | 4.3–4.6 ms | 16.0–17.4 ms |
| `/*` typed, opening a comment to the end (changed range: the whole document) | 0.77–0.81 ms | 7.4–7.7 ms | 24.4–26.1 ms |
| A 60-line screen's highlight captures (`setByteRange`) | 0.15 ms | 0.16 ms | 0.15 ms |

Against the byte lexer of §8.3 (a full pass in 3.3 ms at 3.2 MB, a key one line), tree-sitter is about 70 times
slower to parse, and its cost a key grows with the document: about 5 ms a megabyte on this shape (one top-level
array of 24,000 records), split evenly between the re-parse and the changed ranges. Why it grows was not
investigated, and a more nested document may do better. None of it runs on the main actor (A-ATTRED-7), so the
cost is how soon colours arrive, not how fast keys are taken: at once at 100 KB, a frame or two late at 3.2 MB,
and a quarter of a second for the first colours when a 3.2 MB file opens. The tree's memory was not measured.

Binary size: release builds (SwiftPM dead-strips), then stripped.

| Executable | Stripped | Added | `__text` |
|---|---|---|---|
| A baseline (Foundation, `Data`, one `print`) | 54,568 bytes | | |
| + SwiftTreeSitter, the runtime and TreeSitterJSON, parsing and querying | 360,360 bytes | 305,792 | 231,772 |
| + TreeSitterXML (its DTD target is linked too) | 410,056 bytes | 49,696 more | 244,640 |

Each grammar target also leaves a resource bundle beside the binary (4 KB each on disk), which an adapter that
embeds its queries does not read. Compile time, clean, each product in a fresh scratch path: the baseline in 4.5 s
of wall clock (3.0 s of CPU), with JSON 7.5 s (7.9 s), with JSON and XML 8.8 s (8.4 s) in release; in debug the
baseline 4.8 s (3.7 s) and JSON with XML 6.6 s (14.8 s). So about **0.36 MB and 3 to 4 s of a clean build**, and
nothing on an incremental build, since the dependencies do not change with the app's code. None of it reaches TUI
or an app that does not depend on the adapter.

#### Platforms

- **macOS:** built and run here (above).
- **Linux:** SwiftTreeSitter's CI runs `swift test` on `ubuntu-latest` [25: `.github/workflows/ci.yml`], which
  compiles the C runtime too, and the Swift Package Index reports 0.25.0 building on Linux with Swift 6.1 to 6.4
  [29]. The grammar packages are plain C11 (TreeSitterXML's scanner includes only `<string.h>`, `<wctype.h>` and
  tree-sitter's own headers) and are expected to build, but **this was not verified here**: the static Linux SDK
  this machine used for cross-checks is no longer installed, and this lane did not download it again.
- **Windows: unverified.** tree-sitter's own CI builds the C library for Windows on x64, x86 and arm64 with MSVC,
  through Cargo [26: `.github/workflows/build.yml`], and the runtime has `_WIN32` branches (its clock, atomics,
  allocation). Nobody that I found builds the SwiftPM targets on Windows: SwiftTreeSitter has no Windows CI, and the
  Swift Package Index does not build Windows [29]. SwiftTreeSitter uses `Data`, `NSRange`, `Bundle` and
  `FileManager`, all in swift-corelibs-foundation there. It does not matter yet: `TUITextInput` does not build on
  Windows (§8.3, "Platforms"), so no highlighted editor exists there until it is ported. Check then, on the Windows
  VM (an owner action).
- **WebAssembly:** the Swift Package Index reports Wasm builds (one of its two Swift 6.2 builds failed) [29], and
  SwiftTreeSitter keeps its `Bundle` code behind `#if !os(WASI)` [25]. Not verified here.

#### The adapter's cost (in tuitree or a package, never TUI)

| Piece | Days |
|---|---|
| Updates to the tree: change to `InputEdit`, `edit`, re-parse over the snapshot's UTF-8, changed ranges and the edit to lines in the window | ½ |
| Cancellation through `ts_parser_parse_with_options` when a newer version arrives (optional at first: B-ATTRED-21's coalescing wastes at most one parse) | ¼–½ |
| Styling the window: query a byte range, clip and split captures per line, flatten nesting, publish (B-ATTRED-29's batch) | ½ |
| A UTF-8 text provider for predicates; embedded queries; capture names to a default palette | ½ |
| Tests: the edit mapping, the flattening, a lone-CR text, and incremental against full parse over random edits | ½–¾ |

**About 2½ days**, against H5's 1½ for two hand-written lexers, and every further language then costs a dependency
and its query rather than a lexer. Dependencies: SwiftTreeSitter (BSD 3-Clause), tree-sitter (MIT) and each
grammar (MIT). The grammar packages' manifests name `ChimeHQ/SwiftTreeSitter` for their tests only; SwiftPM did not
fetch it.

#### The lanes

| Lane | What | Days | Was |
|---|---|---|---|
| **H1** | Drawing: runs into `styledRow`, styles interned per token value (B-ATTRED-10), the drawn lines' run cache, precedence (B-ATTRED-8) | ½ | ½ |
| **H6′** | The seam and its store: versioned snapshots, coalesced whole-line changes, the styler's task started and cancelled with the editor (B-ATTRED-19 to 22, 25), publishing validated into the window, frames only for lines on screen (20), provisional tokens carried and shifted (24, 28), updates on a scroll (27), B-ATTRED-29's additions, the guards (15, 30). Tests: a fake tree styler that reports changed ranges, deterministic stepping without sleeps, a stale publish refused, an edit mid-publish, cancellation, one run under the thread sanitizer | 1½ | H2 + H7 2, H6 ½ |
| **H5′** | A stateless JSON line styler over the seam, in an internal target that is not a product (as `TUIWidthCorpus` is), for the Example, Stress's `bigtext-highlighted` and tests | ¼ | ¼ (a JSONC lexer) |
| **H3** | Marks (B-ATTRED-13), with the find bar's matches moved onto them | 1 | 1 |
| **H4′** | The API: `TextEditorMark` and `.textEditorMarks` public, with DocC; the seam and `.textEditorHighlighter` under `@_spi(TextEditorHighlighting)` (A-ATTRED-10), documented in doc comments; `api_baseline.py` taught to skip SPI; the API stability policy's SPI line; CHANGELOG; the Example's Text Input page in its seven languages | ¾ | 1 |
| **H0** | Gone, with the line-lexer engine (A-ATTRED-15 (a)) | 0 | 1 |

**About 4 lane-days in TUI, against 6¼.** In order: H1, H6′, H5′, H3, H4′. With A-ATTRED-15 (b), about 6¼. The
adapter's 2½ days are tuitree's.

#### A-ATTRED-15. Whether TUI keeps a line lexer

*A-ATTRED-5 (b) made the line lexer public beside the seam. With tree-sitter as the only real styler, it has no
user outside TUI.*

- **(a) ★ Not now.** TUI builds only the seam. **Price:** none, and it saves about 2¼ days (H0's day, about a day
  of H2 and H7's screen lexed in the frame and catch-up slices, and about ¼ of the lexer's public API and
  documentation). An app with a hand-written lexer writes it against the seam and keeps its own line states. A line lexer can be added in a minor release later, on the seam, if an app asks. All highlighting is then
  behind `@_spi` until the seam is promoted (A-ATTRED-10): apps write `@_spi(TextEditorHighlighting) import
  TUITextInput`. The promotion trigger is unchanged: when tuitree's adapter has been written against the seam and
  has settled, promotion is put to the owner.
- **(b) As ruled on 2026-11-18.** The engine and the public `TextEditorLexer` beside the seam. **Price:** about 2¼
  days more (about 6¼ in all), and from 1.0 a public protocol fixed until 2.0 whose only users are TUI's Example and
  tests.

★ (a): it is the line engine, not the seam, that a lexer needed, and no lexer is coming. **Default if unanswered:**
(a), since it promises nothing and (b) stays additive.

#### A-ATTRED-16. Where the tree-sitter adapter lives

- **(a) ★ In tuitree, in a target of its own** that imports nothing else of tuitree's, so it can move out whole.
  **Price:** none beyond its 2½ days.
- **(b) An optional package now,** in a repository beside TUI's that the owner creates (repository names are held
  for the owner). **Price:** about ½ day more (the package and its CI against TUI's `main`), and while the seam is
  `@_spi` a published package breaks whenever the seam changes in a minor release, so it must pin TUI's minor.

★ (a): extract it when a second app wants it, which is also when the seam's promotion is due. **Default:** (a).

## For a future reader

- **The probe** (not kept in the repository, per this folder's habit): a Swift file that builds a pretty-printed
  JSON of 3.2 MB (119,774 lines, seven lines a record), lexes it with a byte-level JSONC lexer (key, string,
  number, keyword, punctuation, comment, error; a one-byte state, inside a block comment or not), and times a full
  pass with states only, a full pass keeping tokens, a 60-line screenful, a key that converges at once, `/*`
  inserted in the middle until convergence, and the document joined into one line. Built with `xcrun swiftc -O`
  and run twice. A lane can rebuild it in an hour.
- **The 2026-11-18 probes** (§8; in the scratchpad, not the repository). Each rebuilds in minutes from its
  description, with Xcode's toolchain (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, or the
  maintainers' `slot.py`, which sets it):
  1. *Snapshot and worker* (`probe.swift`, about 330 lines): builds the 3.2 MB JSON (records of seven lines), the
     one-byte-state JSONC lexer, the editor's splice edit, and a worker that lexes in slices and publishes each into
     a `Mutex` store stamped with a generation. Times every row of §8.3's table, as medians of 9 to 51 runs. Built
     with `xcrun swiftc -O -swift-version 6 -parse-as-library probe.swift -o probe`.
  2. *The seam sketch* (`Lexer.swift` and `Seam.swift`, about 250 lines): §8.1's declarations, with a session
     store, change coalescing and a minimal catch-up adapter. It was type-checked and compiled with `-swift-version
     6 -O -wmo -strict-memory-safety -target arm64-apple-macosx15.0 -emit-object`, and sized with `size -m`, once
     with the lexer file alone and once with both. It is not tested: `followed(by:)`'s composition of two changes,
     in particular, is for lane H6 to test.
  3. *Isolation* (`Seam.swift` declaring a `Sendable` lexer protocol and a function that calls it in a
     `@concurrent` task; `App.swift` with `struct JSONLexer: LineLexer`; `App3.swift` with a lexer that writes a
     global): the module emitted with `-emit-module`, then each app file type-checked with `-default-isolation
     MainActor -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature
     NonisolatedNonsendingByDefault`, and without them.
- **The 2026-11-19 probe** (§8.6; in the scratchpad, not the repository): a SwiftPM package (tools 6.2, macOS 15)
  depending on `tree-sitter/swift-tree-sitter` from 0.10.0 (it resolved to 0.25.0, and tree-sitter to 0.25.10),
  `tree-sitter/tree-sitter-json` exactly 0.24.8 and `tree-sitter-grammars/tree-sitter-xml` exactly 0.7.0. Four
  executables: `Base` (Foundation, `Data` of the argument, a `print`); `MinimalJSON` and `Minimal` (a UTF-8 parse
  through `parse(tree:encoding:readBlock:)` and a capture walk, for JSON, and for JSON and XML); and `Adapter`,
  about 180 lines, which builds the JSON of §8.3 at a size given as its argument, then times a full parse, a 60-line
  query by `setByteRange`, and three edits (a letter in a string, a `"`, a `/*`) as copy, `edit`, re-parse and
  changed ranges, through SwiftTreeSitter with 64 KB and 4 KB read chunks and through the C API with the whole
  buffer. Sizes: `swift build -c release --product X --scratch-path <fresh>` per product, timed with `/usr/bin/time
  -p`, then a copy stripped with `strip` and measured, and `size -m` for sections. Built with Xcode's toolchain
  (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`). A lane can rebuild it in an hour.
- **The cap on catch-up** (B-ATTRED-12) is the decision most likely to be revisited. If an app wants the whole
  document styled (a minimap, an outline drawn from tokens), the engine can run to the end in slices on request.
  It is not the default, because an edit that opens a comment would then cost the document.

## Sources

1. Alexandru Dima, "Optimizations in Syntax Highlighting", VS Code blog, 2017-02-08:
   <https://code.visualstudio.com/blogs/2017/02/08/syntax-highlighting-optimizations>
2. VS Code 1.97 release notes (tree-sitter, experimental): <https://code.visualstudio.com/updates/v1_97>
3. VS Code source, `src/vs/editor/common/model/textModelTokens.ts` (`tokenizeHeuristically`, `guessStartState`,
   `findLikelyRelevantLines`, `_backgroundTokenizeWithDeadline`):
   <https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/textModelTokens.ts>
4. VS Code 1.76 and 1.81 release notes (asynchronous tokenization in a web worker):
   <https://code.visualstudio.com/updates/v1_76>, <https://code.visualstudio.com/updates/v1_81>
5. VS Code source, `editorConfigurationSchema.ts` (`maxTokenizationLineLength` 20,000; `asyncTokenization` on) and
   `textModel.ts` (`LARGE_FILE_SIZE_THRESHOLD` 20 MB, `LARGE_FILE_LINE_COUNT_THRESHOLD` 300,000):
   <https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/config/editorConfigurationSchema.ts>,
   <https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/textModel.ts>
6. Sublime Text, "Syntax Definitions": <https://www.sublimetext.com/docs/syntax.html>
7. KSyntaxHighlighting, `abstracthighlighter.h` and `state.h`:
   <https://invent.kde.org/frameworks/syntax-highlighting/-/tree/master/src/lib>
8. Kate handbook, "Working with Syntax Highlighting":
   <https://docs.kde.org/stable_kf6/en/kate/katepart/highlight.html>
9. Vim, `syntax.txt`, "Synchronizing" (`:syn-sync`): <https://vimhelp.org/syntax.txt.html#%3Asyn-sync>
10. Neovim, `treesitter.txt` (`vim.treesitter.start`, `LanguageTree:parse()`):
    <https://neovim.io/doc/user/treesitter.html>
11. Neovim 0.11 news (asynchronous highlighting and injections): <https://neovim.io/doc/user/news-0.11.html>
12. tree-sitter, "Advanced Parsing" (editing, multi-language documents):
    <https://tree-sitter.github.io/tree-sitter/using-parsers/3-advanced-parsing.html>
13. tree-sitter, `lib/include/tree_sitter/api.h` (`ts_parser_parse_with_options` and its progress callback,
    `ts_tree_get_changed_ranges`): <https://github.com/tree-sitter/tree-sitter/blob/master/lib/include/tree_sitter/api.h>
14. Marijn Haverbeke, "Lezer": <https://marijnhaverbeke.nl/blog/lezer.html>
15. Lezer source, `@lezer/common` `parse.ts` (`TreeFragment.applyChanges`):
    <https://github.com/lezer-parser/common/blob/main/src/parse.ts>
16. CodeMirror source, `@codemirror/language` `language.ts` (the `Work` budgets) and its reference manual
    (`ParseContext`, `skipUntilInView`, `ensureSyntaxTree`): <https://github.com/codemirror/language/blob/main/src/language.ts>,
    <https://codemirror.net/docs/ref/#language>
17. CodeMirror source, `highlight.ts` (`TreeHighlighter` over `view.visibleRanges`):
    <https://github.com/codemirror/language/blob/main/src/highlight.ts>
18. CodeMirror source, `stream-parser.ts` (`MaxDistanceBeforeViewport`, `MaxLineLength`):
    <https://github.com/codemirror/language/blob/main/src/stream-parser.ts>
19. Nova 10.1 release notes: <https://nova.app/releases/10.1/>
20. Apple, `NSLayoutManager.addTemporaryAttributes(_:forCharacterRange:)`:
    <https://developer.apple.com/documentation/appkit/nslayoutmanager/addtemporaryattributes(_:forcharacterrange:)>
21. Apple, `NSTextLayoutManager.setRenderingAttributes(_:for:)` and `renderingAttributesValidator`:
    <https://developer.apple.com/documentation/appkit/nstextlayoutmanager/setrenderingattributes(_:for:)>
22. ChimeHQ, Neon: <https://github.com/ChimeHQ/Neon>
23. Bare Bones, Codeless Language Modules: <https://barebones.com/support/develop/clm.html>
24. Language Server Protocol 3.17, `textDocument/publishDiagnostics` (`version`) and semantic tokens:
    <https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/>
25. SwiftTreeSitter 0.25.0 (revision 08ef81e), read where cited: `Package.swift`, `Sources/SwiftTreeSitter/`
    `Parser.swift`, `Tree.swift`, `InputEdit.swift`, `Query.swift`, `Predicate.swift`, `String+TextProvider.swift`,
    `Encoding+Helpers.swift`, `LanguageConfiguration.swift`, `Bundle+Extensions.swift`, and
    `.github/workflows/ci.yml`: <https://github.com/tree-sitter/swift-tree-sitter/tree/0.25.0>
26. tree-sitter 0.25.10: `Package.swift`, `lib/include/tree_sitter/api.h` (`ts_parser_parse_with_options`,
    `TSParseOptions`, the deprecation of `ts_parser_set_timeout_micros`, `ts_query_cursor_set_byte_range`,
    `ts_tree_get_changed_ranges`) and `.github/workflows/build.yml` (the Windows targets):
    <https://github.com/tree-sitter/tree-sitter/tree/v0.25.10>
27. tree-sitter-json 0.24.8 (`Package.swift`, `queries/highlights.scm`, `bindings/swift`):
    <https://github.com/tree-sitter/tree-sitter-json/tree/v0.24.8>
28. tree-sitter-xml 0.7.0 (`Package.swift`, `queries/xml/highlights.scm`, `xml/src/scanner.c`):
    <https://github.com/tree-sitter-grammars/tree-sitter-xml/tree/v0.7.0>
29. Swift Package Index, swift-tree-sitter's builds (0.25.0: Linux, Android, Wasm and Apple platforms with Swift
    6.1 to 6.4; no Windows), read 2026-11-19: <https://swiftpackageindex.com/tree-sitter/swift-tree-sitter/builds>
30. tree-sitter's releases (0.27.2, 2026-11-07): <https://github.com/tree-sitter/tree-sitter/releases>
