# Highlighting a large source in TextEditor: design (G3, A-ATTRED-1)

*The deeper design the owner asked for on 2026-11-17, when he ruled that the per-line styler proposed under
A-ATTRED-1 in [An attributed TextEditor: design (G3)](<An attributed TextEditor - design (G3).md>) is too limited,
because a line's styling can depend on the lines above it (a string or a comment opened earlier). It surveys how
real editors highlight large documents, then proposes how TUI should. Written 2026-11-17 against `main` at
2b23a75b5. Nothing here is built. The costs come from a standalone probe on this machine (macOS 15.8.3, Xcode's
Swift 6.2.4, `-O`; see "For a future reader"). Ids: A-ATTRED-5 to 7 (for the owner), B-ATTRED-8 to 15 (decided
here).*

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

### A-ATTRED-6. What TUI ships

- **(a) No lexers.** Apps write their own. **Price:** none; tuitree writes a JSON and an XML lexer itself.
- **(b) ★ JSON(C) and XML lexers in an opt-in module,** à la carte, so an app that does not import it pays
  nothing. XML covers XML property lists. **Price:** H5, 1½ days, and a module to keep.
- **(c) A TextMate grammar interpreter,** loading `.tmLanguage.json` files. **Price:** 5 days or more. Oniguruma's
  regex semantics differ from `Regex` and `NSRegularExpression`, and the result would be a regex lexer at about
  0.3 MB a second.

★ (b): the two formats the driver needs, written as byte lexers (7 ms for 3.2 MB), and a worked example of the
protocol for any app's own lexer. **Default:** (a).

### A-ATTRED-7. Where the catch-up runs

- **(a) ★ On the main actor, in slices between frames** (B-ATTRED-12), as VS Code did until 1.81, and as
  CodeMirror and Neovim do. **Price:** in H2. A lexer needs no snapshot and no locks, and a key waits at most one
  slice.
- **(b) Off the main actor,** on a snapshot of the text, with results stamped by edit and dropped when stale, as
  VS Code's worker does. **Price:** H7, 1½ days, and the races it brings. It keeps a slow lexer's catch-up from
  taking any main-actor time, which matters only for regex-speed lexers on multi-MB files.

★ (a): with the catch-up capped at a screen past the viewport, the main actor's share is small, and the protocol
already requires `Sendable`, so (b) can come later without an API change. **Default:** (a).

## For a future reader

- **The probe** (not kept in the repository, per this folder's habit): a Swift file that builds a pretty-printed
  JSON of 3.2 MB (119,774 lines, seven lines a record), lexes it with a byte-level JSONC lexer (key, string,
  number, keyword, punctuation, comment, error; a one-byte state, inside a block comment or not), and times a full
  pass with states only, a full pass keeping tokens, a 60-line screenful, a key that converges at once, `/*`
  inserted in the middle until convergence, and the document joined into one line. Built with `xcrun swiftc -O`
  and run twice. A lane can rebuild it in an hour.
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
