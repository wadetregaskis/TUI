# Security policy

## Reporting a vulnerability

Report it privately through GitHub: on the repository's **Security** tab, choose
**Report a vulnerability**
([direct link](https://github.com/wadetregaskis/TUI/security/advisories/new)).
That opens a draft advisory only the maintainers can see, where the report can be
discussed, fixed and, once a fix has shipped, published with credit to you.

Please do not open a public issue, pull request or discussion about a
vulnerability before it is fixed. There is no security e-mail address; the
advisory form is the one channel.

A useful report says which module and commit (or release) it affects, the
terminal and operating system it was seen on, and the smallest program or input
that shows it. For an escape-sequence problem, the exact bytes matter: attach
them as a file or a hex dump rather than pasted text, which a terminal or a web
form may already have interpreted.

You should hear back within a week. TUI is maintained by one person, so a fix may
take longer than that; the advisory is where its progress is tracked.

## Supported versions

TUI has not reached 1.0. Until it does, only the `main` branch is supported:
fixes land there and are not backported to any earlier commit or tag. The
`v0.x` tags in the repository are releases of
[TUIkit](https://github.com/phranck/TUIkit), the project TUI grew from, and are
not maintained here. Which releases are supported after 1.0 will be stated here
when 1.0 ships.

## In scope

TUI runs inside a user's terminal and often displays text the app did not write.
These are the areas where a bug is a security problem rather than an ordinary
one:

- **Terminal escape injection from untrusted strings.** Content that reaches the
  terminal must not be able to drive it: move the cursor off its row, change the
  window title, write the clipboard (OSC 52), open hyperlinks the app did not
  make, send device-control or graphics sequences, or reset the terminal. TUI
  neutralises cursor-moving controls in every row it writes, sanitises window
  titles and notifications itself, and gives apps `String.sanitizedForTerminal`
  for anything a user, a file or the network supplied. A way past any of these,
  or a place where TUI shows outside content (a file name, a paste, a terminal's
  reply, image metadata) without them, is in scope.
- **File panels and documents.** The open and save panels, the file browser and
  `DocumentGroup`: following a path somewhere the user did not choose, writing
  or replacing a file other than the one chosen, a file name that injects
  escapes or misleads about which file is selected, and saves that can lose or
  corrupt a document.
- **Image decoding.** Decoding pictures (`Image`, `AsyncImage`, animated
  images) and encoding them for the terminal's graphics protocols: a crash,
  hang, unbounded memory use or out-of-bounds access driven by a crafted image,
  and graphics payloads that escape their sequence.
- **Persisted state.** `@AppStorage`, `@SceneStorage` and the other settings TUI
  saves (`UserDefaults` on macOS; `settings.json` and `UserDefaults.json` under
  the app's configuration directory elsewhere): files written where another
  user can read or replace them, and a crafted settings file that crashes the
  app or makes it act on values it should reject.

Also in scope: anything else in TUI's own code that lets input the app did not
choose to trust run code, read or write files, or reach the network.

## Out of scope

- An app that passes untrusted text to a view without sanitising it, where TUI
  documents that the app must (`String.sanitizedForTerminal`). A view that is
  documented to sanitise and does not is in scope.
- Bugs in terminal emulators themselves, unless TUI can reasonably work around
  them; please report those to the terminal's authors as well.
- The `Example` app, the tools under `Tools/`, and the benchmarks, except where
  they show a problem in the library.
- Denial of service that needs the app's own cooperation, such as a view tree
  the app builds to be enormous.
