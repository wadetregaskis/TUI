# The owner's decisions of 2026-11-08

*The owner's answers to the questions page of 2026-11-08 (sixteen questions) and the rulings he added through the
day, each with the reason or words he gave where they were recorded, and where it went. It continues
[the decisions of 2026-10-27 to 2026-11-07](<The owner's decisions, 2026-10-27 to 2026-11-07.md>). What is still open
is in [Open owner decisions](<../../Open owner decisions.md>). Ids: the page's own (NOTIF-KEYS … SCENE-ATTACH); none
heads an entry.*

## In short

The page asked about the night's work: notifications, the sheets' keyboard stops, faint text on Warp, a truer ASCII
mode, colour blindness, geometric arrow keys, the small APIs, strict memory safety, the last sleeps in tests, the
SwiftUI probes, two documentation consolidations and scene attach. The owner kept what was built where it was asked
whether to keep it, widened three proposals (a direct route for desktop notifications, toasts layered per
presentation, geometric arrows tried app-wide), asked for two things to be tried only if they cost nothing
(injectable clocks, an intrinsically safe `ValueHashPlans`), and declined two (a CI job for the probes, scene
attach). Through the day he added rulings on a settings scene and its key, persistence per terminal session, the
View menu's accessibility toggles and the Swift minimum.

## How it unfolded

The page went out in the morning; the answers came back by id, several with a direction of their own. Each ruling
that changed behaviour became a lane, run one at a time and landed after the gate the same day: NOTIF2, SMALL,
SMALL2, PERSIST, GEOMETRY and GEOMETRY2, ASCII-TRUE and ASCII2, and this documentation lane; CLOCKS, SAFE and
VIEW-SETTINGS were queued or running at the day's end. A study of raising the Swift minimum to 6.4 ran beside them
and reported "keep 6.2".

## Where it stands

Done: the notification rulings, FAINT, CVD's audit and the system setting, the `_printChanges` fix, GEOMETRY as an
experiment behind a variable, ASCII-TRUE behind a variable, the persistence rulings, PROBES and DOCS. Queued or
running at the day's end: the settings scene and its F2 key (VIEW-SETTINGS), CLOCKS, SAFE-EXCEPTION and SAFE-LINUX.
Owed to the owner: GEOMETRY's report on what keeping both arrow models costs against one, and an opinion, place by
place, on whether persisted state belongs to the app's host or to the person's client.

## For a future reader

- **"Only if it costs nothing" is a condition, not a preference.** CLOCKS and SAFE-EXCEPTION were approved on
  conditions (no SwiftUI API break, no uglier API, no performance cost); if a condition fails, the answer is the
  standing default, not a trade-off to argue.
- **Tried behind a variable means not yet decided.** ASCII-TRUE (`TUI_PLAIN_TEXT=transliterate`) and GEOMETRY
  (`TUI_ARROW_FOCUS=geometric`) are experiments; their defaults are the old behaviour until the owner rules again.
- **The settings rulings replace a menu-bar assumption:** TUI never forces a menu bar, so view settings need a key
  of their own (F2) as well as a menu item where a menu bar exists.

## The record

### The page's sixteen questions

The decisions in the record's words; the owner's own where quoted.

| Id | Decision | Why, as recorded | Where it went |
|---|---|---|---|
| NOTIF-KEYS | Keep F6 to reach a toast's buttons and Escape to dismiss the focused toast. | As built. | `c3f502c2a` (the design note records it) |
| NOTIF-LOOK | Lead a toast with an emoji (ℹ️ ✅ ⚠️ ❌), not the plain glyphs `i ✓ ! ✗`; keep `.plain` the default style and the automatic Close button. | Two cells is fine; compensate for terminals that mis-advance. | `92290133d` |
| NOTIF-OS | Build the direct route too (`osascript` on macOS, `notify-send` on Linux), with a variable to turn it off, used only when TUI is confident the client is on this host (`SessionLocality`). | None recorded. The page: the direct route reaches every terminal, OSC 9 only Ghostty and iTerm2. | `ccb336773`, `29c783807`, `34a33e908` |
| NOTIF-MODAL | Each notification chooses over or under modals. One associated with a window or presentation goes under its sheets; one with none goes over. A toast covered by a dialog has its timer paused. | "Different cases deserve different behaviour, configurable per notification." | `330aa4176`, `7ea41dd3b`, `cf73b887c` |
| SHEET-CALLS | Keep all three details: a sheet with no controls opens on Resize, a centred sheet grows two cells per press, no grips where the corner has no border cell. | As built. | The [sheets story](<../Presentation and windows/Sheets - sizes, detents, live sheets and the page behind.md>) |
| FAINT | (a): faint everywhere, plus italic only where faint is known not to show (Warp with a light background). | None recorded; the per-terminal rule is kept in the compatibility survey. | `f7991e51a`; the prompt too, `941b8979a` |
| ASCII-TRUE | Build it and try it, behind a variable (or on a branch) until proven. Later the same day: keep improving it, removing limitations and fixing flaws. | Not yet proven. | `b54476e08`, `e4e3e97e0`, `6891e4840`; `TUI_PLAIN_TEXT=transliterate` |
| CVD | (1), the audit only, plus reading the system's "differentiate without colour" when TUI is confident it runs locally. Later: the no-colour cues are opt-in. | None recorded. The page: OS filters and terminals already adapt colours, so re-mapping risks a double transform. | `4690a9b4a` |
| GEOMETRY | Try it, configurable app-wide (a variable for now), and report what keeping both models costs against one. Later: geometric arrows do not wrap, and must reach controls off screen or not drawn last frame, scrolling as needed (a big grid in a small scroll view). | None recorded. | `856338c8e`, `4826c0b55`, `875a1e5ca`, `f31a2f2c1`; `TUI_ARROW_FOCUS=geometric` |
| API-CALLS | Keep all three (the name `onScrollWheel`, the one main-actor static, what `_printChanges` names), but `_printChanges` must never claim an environment or `@Observable` change "unchanged". | None recorded. Probed on macOS 15: SwiftUI prints `\Model.count changed.` for an observed read and `_name changed.` for `@State` and `@Environment`. | `d52c3e217`, `b51e5d48c`, `caf48f698` |
| SAFE-EXCEPTION | Try an intrinsically safe `ValueHashPlans` with no performance cost; failing that, keep it as the one exception. | None recorded. | Lane SAFE, queued |
| SAFE-LINUX | Look for a more elegant way than a helper; a helper only if there is none. | The owner dislikes "a silly helper just to fix a warning". | Partly `4c3ef63d1` (tests format without printf); lane SAFE, queued |
| SLEEPS | Injectable clocks for the last twelve real-time tests, if that breaks no SwiftUI API, makes no API uglier and costs no performance. | None recorded. | Lane CLOCKS, queued |
| PROBES | No CI job; a "when to rerun" note in `Tools/SwiftUIProbes/README.md` instead. | "These only need to be run very occasionally, when a new OS or maybe Xcode version becomes available. I don't think that merits inclusion in CI." | The probes' README, [When to rerun](<../../../Tools/SwiftUIProbes/README.md#when-to-rerun>) |
| DOCS | Both consolidations: the review batches as stories, and the answered tables out of the open-decisions page. | None recorded beyond "both". | [Reviews and audits](<../Reviews and audits/README.md>); the 2026-10-26 to 2026-11-02 answers now in this folder's records |
| SCENE-ATTACH | Don't build it; keep the notes as a design brief. | None recorded. The page's recommendation: the reasoning that declined multi-client, three to four weeks and a permanent per-scene cost. | [Future options: Scene attach](<../../Future options.md#scene-attach>) |

### Later the same day

| Subject | Decision | Why, as recorded | Where it went |
|---|---|---|---|
| Swift minimum | Asked for a study of raising the minimum to Swift 6.4 (wider `Span` use, performance); after it reported, the minimum stays 6.2. | None recorded. | Branch `study/swift64-min` |
| View menu toggles | Every app's default View menu gets toggles for the view and accessibility options (no-colour cues, Reduce Motion, breathing …), overriding the defaults and the variables for the run, not persisted. | None recorded. | `4388419a9`, `1f6e8504b` |
| Menu bar | Never force a menu bar, so view settings need another way in. | Not universal in TUIs. | The settings key, below |
| Settings key | F2, plus ⌃, where it arrives, at the framework's last layer, so an app's own F2 wins; Shift-F1 stays the tooltips key (B-HELP-2). | "F-keys together, from the beginning." | Lane VIEW-SETTINGS |
| Settings design | SwiftUI's `Settings` scene (with `SettingsLink`, `openSettings`, `.appSettings` and the app-menu item): the app's tabs first, then TUI's View and Accessibility tabs, both removable or replaceable by the app; no contributions from deep views. | "We shouldn't nanny them"; global settings must not depend on navigation. | Lane VIEW-SETTINGS |
| `@SceneStorage` | Per terminal session, falling back to the last saved from any session. | Supports a new terminal window per interaction. | `57f6caea5` |
| Sessions | Expire after 30 days; no cap on their number, to be addressed if it becomes a problem. | None recorded. | `6c3b7baa5` |
| File panel size | Stays in cells, clamped only to the terminal. | It sets how much is visible. | As built |
| Persistence survey | Survey every persisted state for whether it belongs to the app's host or the person's client. | The app's host isn't always the person's. | Owed: an opinion per place |
