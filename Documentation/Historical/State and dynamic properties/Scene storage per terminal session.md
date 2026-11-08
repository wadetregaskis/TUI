# Scene storage per terminal session (2026-11-08)

`@SceneStorage` keeps each value per terminal session as well as per window, and falls back to the value last saved
from any session. This note records why, what a session is, and how the store stays bounded.

## The problem

A persistence survey (2026-11-08) found that `@SceneStorage` was app-wide durable state with no session in its key.
SwiftUI's scene storage belongs to one scene instance and is restored only to the window it came from. TUI's launch
window always wrote `scene.<key>`, so two runs of one app at once (two tabs, or two ssh clients of one account) shared
and overwrote one set of values, and "where the user was" came back for whoever launched next, from any client.

## The owner's decision

The owner, 2026-11-08:

> can we make it per-session (or similar) but if there's nothing saved for the current session then use whatever the
> last-saved setting(s) were (from any session)? That way we support a usage pattern where the user opens a new
> terminal window, in their terminal client, for each interaction. Granted there may be some weirdness in the middle
> ground — where a user sometimes closes windows but not always — but let's start with our best guess as to how it
> should work and we can refine it later as needed.

## What was built

- **Reads and writes.** A write goes to the session's copy and to the shared last-saved copy. A read takes the
  session's copy, else the last saved, else the declared default. Without a session there is only the last saved, which
  is what every run did before.
- **Keys.** The last saved keeps its old key, `scene.` + the window's namespace + the declared key (`scene.tab`,
  `scene.viewer#2.tab`). A session's copy is under `scene@` + a 16-hex-digit FNV-1a digest of the session + the same
  rest (`scene@0123456789abcdef.viewer#2.tab`). The digest has a fixed length, so a session's characters can't run into
  the key after it, and no terminal's identifiers are written into the app's preferences. FNV-1a, not `Hasher`, because
  `Hasher` is seeded per process.
- **The session** comes from what the terminal put in the process's environment (`TerminalSession.identity`, in
  TUITerminalHost). The most specific answer wins:
  1. a tmux pane (`TMUX`'s socket and server pid, and `TMUX_PANE`), then a screen window (`STY`, `WINDOW`). These come
     first because a tmux server keeps the environment of the client that started it, so the outer terminal's
     variables inside it are stale (`Documentation/Terminals/Terminal compatibility survey.md`, "Environment leakage
     does NOT work");
  2. kitty (`KITTY_WINDOW_ID` with `KITTY_PID`, since window ids restart with each kitty), Windows Terminal
     (`WT_SESSION`), Konsole (`KONSOLE_DBUS_SESSION` with its service), GNOME Terminal (`GNOME_TERMINAL_SCREEN`) and
     Alacritty (`ALACRITTY_WINDOW_ID` with its socket);
  3. WezTerm (`WEZTERM_PANE` with its socket), Warp (`WARP_TERMINAL_SESSION_UUID`), iTerm2 (`ITERM_SESSION_ID`) and
     Apple Terminal (`TERM_SESSION_ID`, which it restores with a window when it relaunches). Each of these counts only
     where `TERM_PROGRAM` names that terminal, because a terminal started from another's shell inherits the other's
     variables.

  Ghostty sets no per-window variable, so every Ghostty window is one session, as before. A plain ssh session forwards
  none of these, so it gets only the last saved.
- **Where it is decided.** The app's run loop reads the process's environment once and writes the session at the root
  of every frame (`EnvironmentValues.sceneStorageSession`). A headless run and `TestApp` set none, so a test never
  depends on the terminal it was started from.
- **Bounds.** A ledger under `scene@sessions` records each session's last write and the keys it wrote (a store can't
  list its keys). A write renews the stamp when it adds a key or the stamp is an hour old, so a slider bound to scene
  storage costs one ledger read per tick, not a ledger write. Whenever the ledger is written, sessions with no write for 30 days are dropped with their
  keys; a dropped session starts from the last saved, as a new one does. There is no cap on how many sessions a store
  keeps: the first version kept the 32 most recently written, and the owner removed the cap the same day ("let's not
  put any limit on how many sessions there can be. If it somehow becomes a problem, such as for performance, then we
  will address that as it rises").

## Store resolution

`@SceneStorage` with no store of its own now uses the store `defaultAppStorage(_:)` set above its view, as `@AppStorage`
does, before `StorageDefaults.backend`. Before this, it captured `StorageDefaults.backend` when the property was made,
so `TestApp`'s in-memory store didn't cover it, and a test using `@SceneStorage` wrote the real preferences.

## Known rough edges, for later refinement

- **The middle ground the owner named.** Someone who sometimes reuses a window gets that window's own value there,
  which may be older than the last saved from another window.
- **Ledger races.** Two processes that write the ledger at once can each lose the other's record (the JSON store
  merges per key, and the ledger is one key). The lost session's values stay but are no longer pruned with it. The cost is a
  few stale keys.
- **Stamped on write only.** A session that only reads (restores and changes nothing) ages out after 30 days and then
  starts from the last saved.
- **Inheritance by a terminal that names nothing.** kitty's variables inherited by a terminal that sets no
  `TERM_PROGRAM` of its own, or none per window, make all its windows one session.
