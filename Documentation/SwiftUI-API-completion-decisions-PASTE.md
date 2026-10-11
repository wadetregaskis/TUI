# Completing the SwiftUI API: decisions from lane PASTE

*Lane PASTE, 2026-10-11, fixed the input parser's give-ups. An 8 MiB
bracketed paste of plain text made Stress exit: past its 1 MiB limit the
parser dropped what it had buffered and left paste mode, so every later byte
of the same paste was read as a key, and the first `q` quit (found by the
coordinator while sizing an input benchmark). A terminal reply or a CSI
longer than the 4 KiB the parser waits for had the same flaw on a smaller
scale: the first 4 KiB was dropped and the rest typed out. Pasted text and
terminal replies are now never keys, however long they run. (A paste the
terminal pauses in for about a second is still ended at the pause, as
before: B-PASTE-1.)*

*The format is that of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-PASTE-n — needs your decision.**
- **B-PASTE-n — shipped the safe option.** Says what the fuller version would
  be, and its price.
- **C-PASTE-n — declined.** With the reason.

There is no A or C entry.

## B. Shipped the safe option

### B-PASTE-1. A paste past 16 MiB arrives as its first 16 MiB

A bracketed paste is one `KeyEvent.Key.paste` event whatever its length, and
nothing between its markers is read as a key. The limit on what is delivered
went from 1 MiB to 16 MiB (`Terminal.maxPasteBytes`). Past it, the paste
stays open to its end marker, or to the stall timeout, as before; the app is
given the first 16 MiB, cut back to a whole Unicode scalar so that it stays
UTF-8, and the rest is dropped as it arrives. A character of several scalars
that straddles the cut (a flag, a letter and its combining accent) keeps only
the scalars before it.

**The stall timeout is the one way the rest of a paste is still read as
keys**, and this lane leaves it as it was. A terminal that stops sending in
the middle of a paste for 40 passes of the run loop
(`stalledPasteStaleFrames`: a second at the loop's 25 ms input poll,
two-thirds of one while an animation runs at 60 frames a second) has the
paste ended there and delivered, and what it sends after the pause is read
as typing. The timeout exists for a paste whose end marker is lost, which
would otherwise keep the keyboard for good, and nothing tells that from a
paste that has only paused until the pause is over. The fuller version
would time the pause on the clock rather than in passes of the loop, so that
an animation cannot shorten it. Its price: the parser counts passes and
reads no clock today, and the tests that drive it pass by pass would each
need a clock of their own.

**Why 16 MiB.** The paste that quit Stress was 8 MiB of prose, and pasting a
multi-megabyte log into a `TextEditor` is plausible, so the limit has to sit
well above that: 16 MiB is twice the measured case. What it costs, from the
code (not measured):

- Within the limit, the input buffer grows by half each time it is full, so
  it holds up to about 1.5 times the paste. At the end marker the content is
  copied once into an array and decoded once into a `String`. A 16 MiB paste
  peaks near 56 MiB (24 + 16 + 16), the 8 MiB one near 28 MiB. Once it is
  delivered the buffer goes back to its 12 KiB baseline and the array is
  freed. The `String` is the app's.
- Past the limit, the kept 16 MiB is copied out of the buffer once, and the
  buffer shrinks to its baseline at the same moment, so the rest streams
  through 12 KiB however long it runs: about 40 MiB at that moment, 32 MiB at
  delivery.

Then the app holds the text, and what that costs is larger than anything
above. From the code, not measured:

- `TextEditor` keeps its text as lines of `Character`s (`EditorLayout`), and
  a `Character` is 16 bytes: 256 MiB for 16 MiB of ASCII, held for as long
  as the text is shown. Its insert (`TextEditorHandler`) splits the paste
  into the same shape first, so a paste of many lines peaks near 300 MiB
  (those lines, the paste and its copy with line breaks normalised, and the
  lines joined back into the text), and a paste of one line near twice that,
  because the line it goes into is copied. This is the largest cost the
  raise from 1 MiB opens up, and it is on the common path: UTF-8 text.
  (Review round 2; the first version of this list left it out.)
- Its undo keeps up to 50 texts from before an edit (`TextUndoHistory`),
  each the whole document. Once a 16 MiB paste is in, each later edit adds
  16 MiB, up to 800 MiB, and each joins every line back into one string, so
  every key typed walks the document. `TextField` keeps the same history
  (`pushUndoState` records the whole text), so the same 800 MiB applies to a
  field.
- Its insert shifts the lines after the caret once for each line it
  inserts, so a paste of many lines into the middle of a long document
  costs the product of the two.
- Drawing it wraps every line at the editor's width (`EditorLayout` keeps
  the wrappings of this frame and the last), a cost of its own, not
  estimated here.
- A `TextField` walks its whole text on every frame it draws, with an array
  of cell widths as long as the text (128 MiB at 16 MiB of ASCII). A
  vertical one (`axis: .vertical`) also builds an array of the text's
  `Character`s from scratch on every measure and render and on caret keys
  (`verticalSource`, `softWrapLayout`): 256 MiB and a grapheme walk of the
  whole text, several times a frame.

Before this lane neither control was handed more than 1 MiB of paste in one
event: whatever came after that was typed into it, a key at a time. The same
costs apply to any document that size an app puts in an editor; a paste is
now one way to make one. A measurement is owed: a 16 MiB paste into a
focused `TextField`, and into a `TextEditor` above a long document with a
few keys typed after it, in a release build. A `TextEditor` that kept its
text as UTF-8, and its undo as edits rather than copies, would remove most
of it; that is a redesign of the editor, outside this lane.

**Why not the other two shapes.**

- *Deliver nothing past the limit.* Throws away a paste the user meant,
  with no signal that it happened; a cut paste at least shows its start.
- *Deliver in several chunks.* Each chunk would be a paste of its own.
  `onPasteCommand(of:validator:perform:)` and `pasteDestination` would run
  once per chunk, each with part of the text. `TextField` and `TextEditor`
  record one undo step per key event that changes their text
  (`TextEditorHandler`'s `undoHistory.record`), so Ctrl-Z would take back
  only the last chunk, and the history would keep every intermediate text,
  quadratic in the number of chunks. A chunk boundary can also fall between
  a character and its combining marks.

**The fuller version** would tell the user the paste was cut, as the status
bar already says "Nothing to paste here" for three seconds. Its price: the
event would have to carry the cut (a field on `KeyEvent.Key.paste`, or a case
of its own), which touches every place that reads a paste (about ten, in
TUIkitTextInput, TUIkitFoundation and Stress), plus a status message in
the seven string tables of TUIkitStrings. Raising the limit further instead
costs memory in proportion: 2.5 to 3.5 times the limit at the peak.

### B-PASTE-2. The rest of an over-long sequence is skipped, until its end or a pause

A CSI, OSC, DCS, APC, PM or SOS longer than the 4 KiB the parser waits for
(`Terminal.maxReplyBytes`) is still given up on at 4 KiB, but its rest is
now skipped rather than typed: to its final byte (a CSI), to `BEL` or `ST`
(the string families), or to an `ESC` that starts a new sequence, which then
parses. That is the rule each walk already applies to a sequence a new
`ESC` cuts short.

The skip also ends after eight quiet passes of the run loop
(`deadSequenceStaleFrames`, about 200 ms at its 25 ms poll), the number an
unfinished sequence waits, and the run loop keeps polling until then.
Without that, a terminal that started a long reply and never finished it
would take the keyboard with it: a string sequence ends only at `BEL` or
`ESC`, so everything typed would be skipped until the user pressed Escape. A
reply's bytes arrive as a stream, so a pause that long means its end is not
coming.

What is typed before that pause goes with the skip, and typing makes the
pause longer. While a string sequence is being skipped, a typed letter
cannot be told from its payload (a clipboard answer's base64 is letters and
digits). The skip's wait starts again from each byte it consumes, so a user
who keeps typing loses the keys until a pause of about 200 ms, and a key
held down to auto-repeat loses every repeat until it is let go. A CSI's skip
ends at the first letter typed, its final byte, which goes with it, but not
at a digit, `;`, a space or Backspace. `BEL` ends a string's skip, and an
`ESC` with something behind it ends either: an arrow, a mouse report. A lone
`ESC`, the Escape key, ends a CSI's skip at once. In a string's it may be
the first byte of `ST`, so it waits for the skip's wait to run out and then
for the wait every lone `ESC` gets: the Escape arrives eleven passes after
the skip's last byte (about 275 ms), and a key typed in that time joins it
as an Option chord (Escape then `j` is Option-j).

A string sequence within the 4 KiB whose end is lost is not the same,
though the first version of this entry said it was (review round 2). Bytes
typed after one join it too, but its wait counts only the passes on which nothing
arrives, and never starts again, so typing cannot make it longer: after
eight quiet passes in all it is dropped with what joined it, and a held
key's later repeats arrive. A lone `ESC` that joined a string sequence is
dropped with it, so there the Escape is lost rather than late.

The skip's wait starts again for the rule this lane is about: the rest of a
reply is not typed. Counted as within the 4 KiB, a reply past 4 KiB that
arrives with pauses adding up to eight quiet passes (a slow link, under
ssh; not measured) would see its skip end part way, and its rest typed out.
Starting again costs only when a reply past 4 KiB loses its end, which has
not been observed on any terminal, and then only for as long as the typing
lasts.

An `ESC` in front of the sequence is the Escape key: no terminal puts a
meta prefix on a reply, and no key runs to 4 KiB. It is delivered first, and
the sequence is skipped after it. The first version of this entry had it
wrong (review round 1): the `ESC` was put on whatever was read after the
skip, or dropped with the sequence when its rest had not arrived, so an
Escape pressed just before a long reply came in was lost either way. The
same held in front of everything else that is not a key — a reply swallowed
whole, a focus or mouse report, a paste's start marker, behind which the
paste was typed out as keys — and it is now one rule for all of them
(`tryExtractMetaPrefixed()`). Review round 2 found one more: a sequence
straight after the `ESC` that a new one cuts short, or an over-long one
whose skip ends in front of the start of another, left the `ESC` to prefix
the next thing read, so `ESC ESC [1;2 ESC [A` was Option+Up. It is Escape
and Up.

**The fuller version** would skip strictly to the terminator, with no pause
rule. Its price is the wedge above, for a case nobody has observed (not
measured on any terminal): a reply longer than 4 KiB whose end is lost.
