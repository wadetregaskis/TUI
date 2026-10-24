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
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-PASTE-n — needs your decision.**
- **B-PASTE-n — shipped the safe option.** Says what the fuller version would
  be, and its price.
- **C-PASTE-n — declined.** With the reason.

There is no A or C entry.

## B. Shipped the safe option

### B-PASTE-1. A paste of any size arrives whole

*Rewritten 2026-10-12 by lane PASTE2, when the owner asked for pastes of any
size. Until then this entry was "A paste past 16 MiB arrives as its first
16 MiB".*

A bracketed paste is one `KeyEvent.Key.paste` event whatever its length,
nothing between its markers is read as a key, and nothing in it is dropped:
there is no size limit. `Terminal.maxPasteBytes`, and the code that kept a
paste's start past it, are gone.

**Where the limit came from** (`git log -S maxPasteBytes`):

- 64 KiB, b3d563040 (2026-02-14), the commit that added bracketed paste:
  "Safety limit to prevent infinite buffering on malformed input." The paste
  was read there by a loop that held the run loop, a millisecond's sleep at
  a time, until the end marker came; the limit bounded what it buffered,
  not how long it waited.
- 1 MiB, 893381180 (2026-05-28), when paste mode became a state of the
  parser: "Anything beyond this is treated as a misbehaving terminal and
  discarded so it can't pin memory forever." It was then the one way out of
  paste mode besides the end marker. The same commit had paste mode count no
  quiet passes, as "the maxPasteBytes guard handles the pathological case";
  it handled only a paste that kept coming, and one whose marker was lost
  and that then went quiet stayed open for good.
- 8a51ca1f7 (2026-08-01) gave a lost end marker its own way out, the stall
  timeout below: "Paste mode had exactly two exits: the `ESC[201~` end
  marker, or one mebibyte of content. Nothing else."
- 16 MiB, 76fd454a2 (2026-10-11, lane PASTE): twice the 8 MiB paste that
  quit Stress. Past it the paste stayed open and arrived as its first
  16 MiB.

**What the 16 MiB still protected against: the memory one paste takes, and
nothing else.** A paste whose end marker is lost ends at the stall timeout,
holding only what came before the pause. The scan for the marker has been
linear since 2026-09-04 (it resumes where it stopped). And nothing writes the
app's standard input but the terminal, which sends between the markers what
the user pasted: a paste is as long as the clipboard the user chose, which
the terminal already holds. So the limit capped the parser's memory by
refusing the user's paste, and the memory it saved is the memory that
delivering the paste takes.

**What a paste of N bytes costs inside TUIkit**, before the app has it:

- The input buffer grows by half whenever it is full, so it ends at most
  1.5 N, and while it grows its old storage and its new one are both alive.
  The copying stays linear: the growth moved 2.7 N bytes in all for 64 MiB.
- The string is made straight from the buffer's storage
  (`String(validating:as:)`), so it is the one copy of the paste: N for
  UTF-8, up to 2 N for a paste that is not UTF-8 and is read as Latin-1.
  Until 2026-10-12 the bytes were copied into an array first, a third copy
  alive with the other two. Not on macOS 14, which lacks
  `String(validating:as:)`: there the decoder is still Foundation's
  `String(bytes:encoding:)`, which is not inlinable, so macOS 14's own runs,
  and its source (the Swift overlay's `NSStringAPI.swift`) copies the bytes
  into an array before decoding them. So on macOS 14 the third copy is
  alive while the decode runs, as before (recalled from that source, not
  measured: these tests run on macOS 15 and later; review round 1 of lane
  PASTE2, which found the first version of this list claiming one copy
  there too).
- Once the paste is delivered the buffer goes back to its 12 KiB baseline,
  and the string is the app's.

Measured with a probe of the buffer and the decode (session notes,
PASTE2/probe; macOS 15, Xcode's Swift 6.2.4, `-O`): the peak of the
process's footprint over what it was before the paste, as a multiple of N.
8 MiB 2.46, 16 MiB 2.81, 32 MiB 2.58, 64 MiB 2.56 (3.56 with the array
copy), 128 MiB 2.12. The spread is where N falls among the buffer's sizes,
plus about 12 MiB of freed storage the allocator keeps. Delivering raises the
peak by N over what the open paste held, 2 N with the copy, which
`LargePasteTests` pins at 16 MiB.

And in the app (session notes, PASTE2/pty_paste_check.py: release Stress in
a PTY, one 64 MiB bracketed paste of prose): Stress went on running and its
screen did not change. Its footprint peaked at 171.5 MiB from 4.4 MiB
before, 2.6 times the paste, and was 19.8 MiB once the paste had gone;
`ps` put its resident size at 340 MiB at the peak and still after, the
resident size keeping freed storage until the kernel wants it back. The
paste took about ten seconds to go quiet (9.8 s). The same 64 MiB written
the same way to `cat` through a PTY took 6.6 s (PASTE2/probe/pty_writer_speed.py,
while a test suite ran), so the PTY and the writer set most of that pace,
and the parser, reading 4 KiB a pass of the run loop (`Terminal.readChunk`),
at most the rest. All measurements, not benchmarks.

On a 32-bit platform (WebAssembly's) a paste past about 1.4 GiB can still
end the process, and one of 2 GiB must (from the code, not run: the suite
does not run there). The buffer's growth rule now stops at `Int.max` rather
than overflowing, which trapped at about 1.4 GiB, but that only moves the
trap: the growth then asks for 2 GiB, and that storage and the string made
from the paste need well over 3 GiB of the 4 GiB a 32-bit process
addresses, beside the app's own memory. An allocation that cannot be made
traps, the buffer's sums of its size and a read's (`tail + needed`)
overflow once its storage nears `Int.max`, and no `String` there holds
2 GiB. The first version of this entry said the address space was the limit
there, as if the paste were then refused rather than fatal (review round 1
of lane PASTE2). Not trapping would take a size past which a 32-bit
platform cuts or refuses a paste, the limit this lane removed; it is not
done, as no terminal paste of a gibibyte into a WebAssembly app is known.

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

Then the app holds the text, and what that costs is larger than anything
above. From the code, not measured:

- `TextEditor` keeps its text as lines of `Character`s (`EditorLayout`), and
  a `Character` is 16 bytes: 256 MiB for 16 MiB of ASCII, held for as long
  as the text is shown. Its insert (`TextEditorHandler`) splits the paste
  into the same shape first, so a paste of many lines peaks near 300 MiB
  (those lines, the paste and its copy with line breaks normalised, and the
  lines joined back into the text), and a paste of one line near twice that,
  because the line it goes into is copied. This is the largest cost that
  lifting the limit opens up, and it is on the common path: UTF-8 text.
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

Until lane PASTE neither control was handed more than 1 MiB of paste in one
event: whatever came after that was typed into it, a key at a time. Lane
PASTE handed over up to 16 MiB, and since 2026-10-12 a paste of any size
arrives whole. The same costs apply to any document that size an app puts in
an editor; a paste is one way to make one. A measurement is owed: a 16 MiB
paste into a focused `TextField`, and into a `TextEditor` above a long
document with a few keys typed after it, in a release build. A `TextEditor`
that kept its text as UTF-8, and its undo as edits rather than copies, would
remove most of it; that is a redesign of the editor, outside these lanes.

**Why one event, not several.** Each chunk would be a paste of its own.
`onPasteCommand(of:validator:perform:)` and `pasteDestination` would run once
per chunk, each with part of the text. `TextField` and `TextEditor` record
one undo step per key event that changes their text (`TextEditorHandler`'s
`undoHistory.record`), so Ctrl-Z would take back only the last chunk, and the
history would keep every intermediate text, quadratic in the number of
chunks. A chunk boundary can also fall between a character and its combining
marks.

**The fuller version** is in the controls, not the parser: the editor
redesign above, so that what a large paste costs once it arrives is
proportionate to it too.

### B-PASTE-2. The rest of an over-long sequence is skipped, until its end or a pause

A CSI, OSC, DCS, APC, PM or SOS longer than the parser waits for is still
given up on at that limit, but its rest is now skipped rather than typed: to
its final byte (a CSI), to `BEL` or `ST` (the string families), or to an
`ESC` that starts a new sequence, which then parses. That is the rule each
walk already applies to a sequence a new `ESC` cuts short. The limit was
4 KiB for every family (`Terminal.maxReplyBytes`) until 2026-10-12, and is
now 16 KiB for a CSI and 64 KiB for the string families (below).

**The limits, family by family** (lane PASTE2, 2026-10-12). The owner found
4 KiB "unnecessarily tight", and asked whether any reply is unbounded by
nature, as an OSC 52 answer might be. Past the limit nothing is typed, so
the limit decides how much of a sequence is held before the rest is skipped,
and with it whether a CSI that long is read (a key) or dropped. Every reply
TUIkit asks for or is sent, and the longest each runs to:

| Reply | Why it comes | Longest |
|---|---|---|
| DA1, `CSI ? … c` | the identity and keyboard questions | 37 bytes, xterm's; iTerm2's 33 |
| DA2, `CSI > … c` | the identity question | about 15 bytes |
| XTVERSION, `DCS > \| … ST` | the identity question | the terminal's name and version: tens of bytes |
| the fence, `CSI 0 n` | every startup question ends with `CSI 5 n` | 4 bytes |
| DECRPM, `CSI ? 2027 ; Ps $ y` | the grapheme-clustering question | about 15 bytes |
| the kitty keyboard flags, `CSI ? flags u` | the keyboard negotiation | about 8 bytes |
| the cell size, `CSI 4 ; h ; w t` | `CSI 14 t` | about 15 bytes |
| colours, `OSC 4`, `10`, `11 ; rgb:…` | the colour questions, and sent unasked when the theme changes | about 25 bytes each |
| the appearance, `CSI ? 997 ; Ps n` | sent unasked while mode 2031 is on | 10 bytes |
| graphics, `APC G …;OK` or an error in words | each image transmitted, unless it says `q=2` | about 100 bytes: Warp's error is sixty characters, iTerm2's some eighty |
| a key with its text, `CSI … ; … ; text u` | the kitty keyboard protocol, `reportAssociatedText` | 8 bytes a character typed |
| focus, mouse, paste markers | the modes TUIkit turns on | under 20 bytes |
| a clipboard answer, `OSC 52 ; c ; base64 ST` | nothing TUIkit sends | unbounded |

TUIkit sends no DA3, no cursor-position report (`CSI 6 n`), no OSC 12 and no
DCS question (XTGETTCAP, DECRQSS: Apple Terminal prints a DCS rather than
parse it, `Documentation/Terminals/Terminal compatibility survey.md`).

- **A CSI: 16 KiB** (`Terminal.maxControlSequenceBytes`). The longest that
  legitimately arrives is a key: a kitty report carrying the text its key
  typed, at most eight bytes a character (a code point of up to seven digits
  and its `:`), so 16 KiB holds one that typed some two thousand characters.
  How much an input method commits through one key was not measured; a
  report longer than the limit is lost, not typed. Every CSI reply asked
  for is under 40 bytes.
- **An OSC, DCS, APC, PM or SOS: 64 KiB**
  (`Terminal.maxStringSequenceBytes`), over six hundred times the longest
  reply asked for. Only the colour answers are read; any other string
  sequence is swallowed whole within the limit and skipped past it, which
  comes to the same for the app.
- **OSC 52 is the one reply unbounded by nature**: the base64 of whatever
  the clipboard holds. TUIkit asks for none. It reads the clipboard through
  the platform's tools (`SystemClipboard`), and a terminal's own paste comes
  bracketed (B-PASTE-1). So an OSC 52 answer here answers another program's
  question, and the limit and its skip suit it: it is dropped either way,
  and held only up to 64 KiB. `OverlongSequenceTests` skips one of a
  mebibyte whole. Were TUIkit to read the clipboard by OSC 52 (a paste over
  ssh, say, where the platform's tools read the far machine's clipboard),
  that answer would have to be read as a paste is, whole, with no limit.

What the higher limits cost: memory while a sequence is held, at most 64 KiB
(the input buffer stays at its 12 KiB baseline, three reads, and grows past
it only for a sequence longer than a read, giving the room back once it is
parsed); and the walk. Each pass of the run loop walked a sequence still
arriving from its start, so one arriving a byte a read cost its length
squared over two: tolerable under 4 KiB, not at 64. The walks now resume
where the last stopped, while the buffer's front has not moved (since
2026-10-12). Except behind a meta prefix, `ESC ESC [ …`: the prefix is taken
off for the walk and put back, which moves the front, so that walk starts
over every pass, and one arriving a byte a read still costs its length
squared over two, some 134 million byte checks at 16 KiB, at most 16 K a
pass. Only the Escape key pressed straight before a sequence puts a prefix
there, and every sequence TUIkit expects is under a hundred bytes but a key
report carrying a long text. Resuming there too would take the prefix's
offset carried through every walk; not done (review round 1 of lane PASTE2
found the first version of this paragraph claiming every walk resumes).
And the colour answers the parser keeps (`noteVolunteeredColorReply`) are
not copied out when longer than all it keeps (4 KiB): an OSC 52 answer to
another program would have been copied whole, to be dropped.

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

A string sequence shorter than a read whose end is lost is not the same,
though the first version of this entry said it was (review round 2). Bytes
typed after one join it too, but its wait counts only the passes on which nothing
arrives, and never starts again, so typing cannot make it longer: after
eight quiet passes in all it is dropped with what joined it, and a held
key's later repeats arrive. A lone `ESC` that joined a string sequence is
dropped with it, so there the Escape is lost rather than late.

The skip's wait starts again for the rule this lane is about: the rest of a
reply is not typed. Counted as within the limit, a reply past the limit that
arrives with pauses adding up to eight quiet passes (a slow link, under
ssh; not measured) would see its skip end part way, and its rest typed out.
Starting again costs only when a reply past its limit loses its end, which has
not been observed on any terminal, and then only for as long as the typing
lasts.

The same holds within the limit for a sequence longer than a read (4 KiB,
`Terminal.readChunk`): each read that adds to it starts its wait again
(`restartWaitOfLongSequence()`), and only a shorter one counts every quiet
pass in all, as above. Until the limits went up (2026-10-12) the skip took
over at 4 KiB, a read, so this is the wait every sequence that long had
before. Review round 1 of lane PASTE2 found the higher limits had left the
sequences between a read and the limit with the wait that never starts
again: a 32 KiB
clipboard answer arriving in 4 KiB pieces with a quiet pass between them
was dropped at the eighth pause and its last piece typed out, base64, `BEL`
(Ctrl-G) and all; a kitty key report of 5 to 16 KiB the same, its digits and
`u`. Typing cannot make a sequence a read long before its wait drops it:
it adds about a byte a pass, and would need a key on every pass for over a
minute.

An `ESC` in front of the sequence is the Escape key: no terminal puts a
meta prefix on a reply, and no key is known to run to the limit (a key
report would need some two thousand characters from one key; above). It is delivered first, and
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
measured on any terminal): a reply longer than its limit whose end is lost.
