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

Then the app holds the text: a `TextEditor` inserts it and keeps the text
from before for its undo. Rendering a 16 MiB document is a cost of its own,
unmeasured here. From the code, not measured: a `TextField` walks its whole
text on every frame it draws, with an array of cell widths as long as the
text (128 MiB at 16 MiB of ASCII); and `TextEditor`'s insert shifts the lines
after the caret once for each line it inserts, so a paste of many lines into
the middle of a long document costs the product of the two. Before this lane
neither was handed more than 1 MiB of paste: whatever came after that was
typed into it, a key at a time. A measurement is owed: a 16 MiB paste into a
focused `TextField`, and into a `TextEditor` above a long document, in a
release build.

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

The skip also ends after the wait an unfinished sequence gets
(`deadSequenceStaleFrames`, eight quiet frames, about 200 ms), and the run
loop keeps polling until then. Without that, a terminal that started a long
reply and never finished it would take the keyboard with it: a string
sequence ends only at `BEL` or `ESC`, so everything typed would be skipped
until the user pressed Escape. A reply's bytes arrive as a stream, so a pause
that long means its end is not coming.

An `ESC` in front of the sequence is the Escape key: no terminal puts a
meta prefix on a reply, and no key runs to 4 KiB. It is delivered first, and
the sequence is skipped after it. The first version of this entry had it
wrong (review round 1): the `ESC` was put on whatever was read after the
skip, or dropped with the sequence when its rest had not arrived, so an
Escape pressed just before a long reply came in was lost either way. The
same held in front of everything else that is not a key — a reply swallowed
whole, a focus or mouse report, a paste's start marker, behind which the
paste was typed out as keys — and it is now one rule for all of them
(`tryExtractMetaPrefixed()`).

**The fuller version** would skip strictly to the terminator, with no pause
rule. Its price is the wedge above, for a case nobody has observed (not
measured on any terminal): a reply longer than 4 KiB whose end is lost.
