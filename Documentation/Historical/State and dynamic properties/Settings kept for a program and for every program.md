# Settings kept for a program and for every program (2026-11-10)

TUI's own settings — the palette, the border style, the control style and the eight checks of the View menu and the
settings panel — are saved: for the program they were changed in, and, where the person asks, for every TUI program
they run. This note records the owner's request, the rulings that shaped it, and why the parts are as they are.

## In short

Seven layers decide each setting, highest first: a change made this run in the View menu or the settings panel; a
`TUI_*` variable set for this launch; the program's code; the person's settings for this program; their settings for
all TUI programs; the computer's setting; TUI's default. A change made this run is also saved for the program, so the
next run starts from it, now at the fourth layer. The all-programs settings live in one hand-editable JSON file,
`defaults.json`, in TUI's own folder; the program's in its existing settings store under `TUISettings.` keys. The panel
edits both: a "set here" box beside each setting says whether this level sets it, an unticked setting is drawn faint
with the value it inherits, changing a value ticks it, and unticking gives it back.

## The problem

Until now TUI's choices lasted for the run ("for now let's not persist them", owner, 2026-11-08). A person who needs
Reduce Motion, or reads keys better spelled out, had to choose it again in every program at every launch, or export a
`TUI_*` variable, which only some of the settings have and which says nothing about the palette.

## How it unfolded

1. **The owner's request (evening feedback, 2026-11-10, item 9):** "Add a user-level settings system, that lets a user
   specify some or all settings (theme, accessibility options, etc - all the stuff in the View menu and default
   Settings tabs) to apply by default to all TUI-based apps." Three parts: an elegant way to edit them in the settings
   panel ("maybe an 'Edit user defaults' … button that switches to a mode which shows the user-level settings _and_
   has checkboxes added next to every setting to control whether it's included"), the precedence order, and a
   suitable place to store them.
2. **The questions page, answered the same evening** (the four rulings below, in the owner's decisions of 2026-11-08,
   2026-11-10 section).
3. **Built the same night**, design first: this note and *State Management*'s "Settings for This Program and All
   Programs".

## The rulings

| Id | Ruling |
|---|---|
| USET-SAVE | (a): a change in the View menu or TUI's settings tabs is saved for that program — the per-program layer. |
| USET-ORDER | (b), highest first: this run's change; a `TUI_*` variable; the program's code; the person's settings for this program; for all programs; the computer's setting; TUI's default. The saved settings fill in only what the code leaves unset. Every one-way rule stays (code can add an accessibility aid, never remove one); where today's behaviour orders a variable and code differently, keep it and say so. |
| USET-EDIT | (b): a button in TUI's tabs, "Settings for all programs…", enters a mode showing the all-programs settings, each with a "set here" box: unticked is not set at this level, drawn faint with the value it would inherit; changing a value ticks it; unticking gives it back. Done leaves the mode. The per-program level offers the same give-back, designed consistently. |
| USET-PLACE | (a): macOS `~/Library/Application Support/TUI/defaults.json`; elsewhere `$XDG_CONFIG_HOME/tui/defaults.json`, else `~/.config/tui/defaults.json`; Windows `%APPDATA%\TUI\defaults.json`; `TUI_CONFIG_DIR` moves it. Hand-editable JSON; a bad entry is skipped alone; unknown keys kept on rewrite. Per-program values in the app's existing store under TUI-reserved keys. |

## The design, and why

**One model for every setting.** The eleven settings were already one model (`ViewPreferenceOverrides`, the SETTINGS
lane's commit "The settings panel and the View menu offer the same settings, from one model"), with a table of each
setting's value type kept for exactly this store. Each setting has one key, used in the file, in the program's store
(prefixed `TUISettings.`), and in code: `palette`, `borderStyle`, `controlStyle`, `focusBreathing`, `spelledOutKeys`,
`focusFollowsPointer`, `arrowsFollowLayout`, `differentiateWithoutColor`, `reduceMotion`, `reduceTransparency`,
`increaseContrast`. A check is a JSON `true` or `false`; a display option is the identifier of a built-in palette,
border style or control style, the identifiers TUI already gives them.

**Where the layers meet.** The variable, the program's saved setting, the all-programs setting and the computer's
setting are resolved together at the root of each frame, where the variable and the computer's setting were already
written: the first that says anything wins, else TUI's default. The scene's own statements are applied over that root,
as before, and this run's choice last, as before. So the program's code beats both saved layers without either knowing
the other, and nothing new runs per view.

**Three places where the order is not the owner's 2-over-3, kept as they were, as the ruling asked:**

- *Focus Follows Pointer:* the program's `Scene.focusFollowsPointer(_:)` wins over `TUI_FOCUS_FOLLOWS_POINTER`, as its
  documentation has said since it was added (`code: .overrides`). Both still win over the saved settings.
- *Reduce Motion, Breathing Focus and Spell Out Keys:* the program's code can add the aid even under the variable's
  `0` (`.reduceMotion(true)` under `TUI_REDUCE_MOTION=0`), never take it away. That is the one-way rule.
- *Palette, Border Style and Control Style:* a program that states one itself (`.palette(_:)`, its own state handed to
  `DisplayCommands`) decides it outright, this run's choice included, as before: the panel disables the option and
  says why, or chooses into the program's own state, which the program keeps however it likes. TUI saves only a
  choice it holds itself (the app's palette, appearance and control style managers).

**Saved when changed, read when launched.** A change this run is both the run's choice (layer 1) and the program's
saved setting (layer 4). The next launch reads it at layer 4, beneath a variable set for that launch and the program's
code. That is what makes `TUI_REDUCE_MOTION=0 myapp` still mean "this once", whatever the person saved.

**The "set here" box, at both levels.** The same column of boxes is shown in the panel's normal mode, for this program,
and in the all-programs mode. Ticked: this level sets it, to the value shown. Unticked: it does not, and the value
shown, faint, is the one it inherits. Changing a value ticks the box; ticking it keeps the value shown at this level;
unticking gives the setting back. In the normal mode unticking forgets this run's choice too, so the value falls back to
the program's code, the variable, the all-programs setting or the computer's. One rule for both levels, so a person who
has learnt one has learnt the other; the alternative for the per-program level, a "Reset" button for the whole tab, was
coarser and has no counterpart in the owner's design for the all-programs mode.

**What an inherited value looks like.** In the all-programs mode, an unticked setting shows the computer's setting
where TUI reads one (the four accessibility settings, when the person is at the machine), else TUI's default. In the
normal mode every setting shows the value in force, faint where nothing at this program's level set it. The View menu
shows the value in force, as before, whichever layer decided it; it draws no difference between inherited and chosen
values (a menu item has a check or none, and a second kind of mark would be TUI's alone), and a choice there is this
run's choice, saved for the program, ticking its box in the panel. The panel is where a setting is given back.

**The file.** One flat JSON object, so a person can read and write it by hand:

```json
{
  "palette" : "amber",
  "reduceMotion" : true
}
```

Read at launch, and again when the terminal regains the focus, so a change made in another program shows when the
person comes back; written at once on a change, merged key by key over what is on disk at that moment (the rule
`JSONFileStorage` adopted after two instances clobbered each other's settings), with every key TUI does not know kept
as it was. An entry of the wrong type, or naming a palette that does not exist, is skipped alone. A file that is not a
JSON object at all is not read and **never rewritten**: a typo in a hand-edited file must not be lost to the next
change made in a panel. The failure is reported through `StorageDiagnostics`, as any other store's is.

**The place.** TUI's own folder beside each app's: `Application Support/TUI` on macOS, `tui` under the XDG config home
elsewhere (lower case, as XDG tools name theirs), `%APPDATA%\TUI` on Windows. Under `TUI_CONFIG_DIR` it is
`$TUI_CONFIG_DIR/TUI/defaults.json`, beside each app's folder there, so one variable isolates a test run from both. The
path code is in TUIStrings beside `appConfigDirectory()` and is written for all three platforms in one function taking
the platform as an argument, so each platform's branch is tested on any machine.

**The program's store.** `StorageDefaults.backend`, the store an `@AppStorage` that names none uses, as TUI's other
kept state (toolbar customization, file panel folders) does: `UserDefaults` on macOS, `settings.json` elsewhere, both
moved by `TUI_CONFIG_DIR`. A headless loop and a test's keep nothing unless given a store, as they read no `TUI_*`
variable and no computer setting; `TestApp` gives its in-memory one, so a test of a saved setting never touches a real
preference.

## Where it stands

Built as described. Not done, and why:

- ~~A `TUI_*` variable that can only say one thing (`TUI_BREATHING=0`, `TUI_KEY_SYMBOLS=0`, `TUI_ARROW_FOCUS=geometric`)
  cannot override a saved setting the other way for one launch.~~ Done the next day: `TUI_BREATHING=1`,
  `TUI_KEY_SYMBOLS=1` and `TUI_ARROW_FOCUS=tab` say the other way (ENV-EITHER-WAY, the owner's decisions of 2026-11-08,
  2026-11-10 section).
- The Example holds its palette and control style in its own state, so TUI does not keep them for it (the ruling's
  "code wins"). Decided the next day: TUI does not restore a choice through the bindings a program hands
  `DisplayCommands`; the Example keeps its own with `@AppStorage`, as any app keeps what it holds (EXAMPLE-KEEPS, the
  owner's decisions of 2026-11-08, 2026-11-10 section).

## For a future reader

- A new setting in the View menu or the panel is a new `ViewPreference` (or display option): give it a key, and it is
  saved, edited and inherited like the rest. Its default and, if any, its variable and its computer setting go in the
  root resolution.
- The file's keys are a published format once released: never rename one; add new keys, and keep reading old ones.
