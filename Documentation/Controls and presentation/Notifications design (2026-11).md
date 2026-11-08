# Notifications: design (2026-11)

The owner's decisions of 2026-11-07 on toasts, and what TUI does for each.
Background: the SwiftTUI comparison's §37 (`Documentation/Historical/SwiftTUI
comparison, 2026-11/Answers, features.md`). SwiftUI has no toast, so nothing
here has a SwiftUI signature to match; the API follows SwiftUI's conventions
(`LocalizedStringKey` literals, `@ViewBuilder` content, `ButtonRole`).

## What stays

`NotificationService` stays imperative and process-wide (`NotificationService.current`,
granted in A-APPSTATE-2): a post comes from a button action, a task or a
callback, none of which has a view to hang a binding on, and a toast outlives
the screen that posted it. The owner judged this approach better than a
binding-driven `.toast(isPresented:)`; it needed expanding, not replacing.

## 1. No manual host step

**Chosen:** the scene hosts notifications. `WindowGroup` (and so `Window`)
wraps its content in the host, inside the window chrome, so toasts sit in the
content area between the bars, over any sheet or alert, and are drawn once
whatever the app does. `.notificationHost(width:)` is gone (pre-1.0: no shim);
a package-level `notificationHost()` remains for tests that render a view
without a scene.

**Considered:** keeping `.notificationHost` as an optional override for a
screen-scoped host, with the scene's host skipping what an inner host drew.
That needs an upward "already drawn" signal each frame and goes wrong for a
window held behind another (drawn too, then discarded). Nobody uses a
screen-scoped host; placement, the reason to keep it, is now per post (4).

## 2. Semantic styles

**Chosen:** `NotificationStyle`: `.plain` (the old look), `.info`, `.success`,
`.warning`, `.error`. Each styled toast takes its border and glyph colour from
the palette's semantic colour (`info`, `success`, `warning`, `error`) and
leads with a glyph, so the meaning never rests on colour alone: ℹ️, ✅, ⚠️,
❌ — emoji, two cells wide (the owner's ruling, decision 2 below). The first
build used one-cell `i ✓ ! ✗`, for fear of terminals that draw `ℹ` and `⚠`
two cells; the writer already makes up a cell a host advances short, and the
four were measured on four hosts (*Terminal compatibility survey*,
"Notification glyphs").

**Considered:** a `NotificationStyle` protocol, as `ButtonStyle`. Kept to a
closed set for now; arbitrary content (3) covers the rest.

## 3. Arbitrary view content

**Chosen:** `post(style:duration:placement:actions:content:)` with a
`@ViewBuilder` closure. The closure is `@MainActor @Sendable`, stored, and
called each frame the toast draws, so the service stays `Sendable` (no view is
kept across threads) and the content is live: it may read state that changes.

## 4. Channels and placement

**Chosen:** a channel is a placement. `NotificationPlacement` has six:
`topLeading`, `top`, `topTrailing`, `bottomLeading`, `bottom`,
`bottomTrailing`. Each post may name one; otherwise the service's
`defaultPlacement` (`topTrailing`, as before). Each placement stacks its own
toasts, newest nearest the edge, so an app can use several at once.
`dismissAll(at:)` clears one channel. Toasts are 40 cells wide (the service's
`width`, which an app may change), narrower on a narrow terminal.

**Considered:** named channel objects carrying placement and width. Two
channels at one placement would overlap, so the placement is the channel; a
name adds a type and nothing an app can do.

## 5. Duration, persistent included

**Chosen:** `duration: TimeInterval?`, default 3 s; `nil` stays until
dismissed. A persistent toast with no actions gets a Close button, so the
keyboard can always dismiss it (6). A toast whose button has the focus does
not expire while it does.

The animation task now asks for a frame only when an opacity will change or a
toast appears or goes; before, it asked every quarter second while any toast
was up, which a persistent toast would have made a render loop that never idles.

## 6. Buttons and actions, from the keyboard

**Chosen:** `actions: [NotificationAction]`, each a title, an optional
`ButtonRole` and a `@MainActor @Sendable` closure; choosing one runs it and
dismisses the toast. They draw as buttons on the toast's last row.

Focus reaches them by **F6**, the key browsers and Windows use to move between
a page and its notification bar: F6 moves the focus to the newest toast with a
button, again to the next older one, and past the oldest back where it was.
Escape dismisses the toast holding the focus. Tab reaches the toasts too,
after the page, as it reaches the toolbars: their buttons are one passive focus
section, which never takes the keyboard by itself. The status bar shows
"F6 notification" while a toast has a button, and "⎋ dismiss" while one has
the focus. A click works too, but there is always the key. Over a sheet, an
alert or a dialog, see 9: a toast above presentations keeps its buttons live
and F6 reaches them; one below is inert, as the toolbars are.

**Considered:** a Ctrl chord (⌃N and the like collide with text editing and
with app commands) and putting the buttons in the page's own Tab ring (a toast
would join and leave the ring under the user's feet).

## 7. Programmatic dismissal

**Chosen:** every `post` returns a `NotificationID` (`@discardableResult`).
`dismiss(_:)` fades that toast out at once; `dismissAll()` and
`dismissAll(at:)` fade out every toast or one placement's. Dismissing a toast
that has gone does nothing.

## 8. OS-level notifications

What each route can do, from the survey and the routes' own documentation
(2026-11-07; rows marked "not checked" are from memory of their docs):

| Route | Where | Title + body | Actions / response | Needs |
|---|---|---|---|---|
| `OSC 9 ; text` (iTerm2) | iTerm2, Ghostty, kitty (legacy), per the survey; WezTerm documents it (not checked) | body only | none: one-way | the terminal to post it; tmux drops it (measured) |
| `OSC 777 ; notify ; title ; body` (urxvt) | Ghostty (its reference); foot, WezTerm, urxvt document it (not checked) | yes | none | as above |
| `OSC 99` (kitty) | kitty | yes, with id, urgency, icon | kitty can report activation back (`a=report`) | kitty, which TUI does not model yet |
| `osascript -e 'display notification …'` | macOS, same machine | yes | none; attributed to Script Editor | not over ssh |
| `UNUserNotificationCenter` | macOS, same machine | yes | actions and replies | an app bundle with a bundle id; a command-line tool has none |
| `notify-send` / D-Bus `org.freedesktop.Notifications` | Linux desktops, same machine | yes | actions over D-Bus (`ActionInvoked`) | a session bus; not over ssh |

**Chosen (built):** the terminal route, as an option on any text post:
`desktop: NotificationDesktopDelivery` — `.never` (the default), `.whenInactive`
(only while the terminal's window does not have the focus, mode 1004) or
`.always`. It sends `OSC 9` through the path `requestAttention(_:)` already
uses, to the hosts documented to post one (Ghostty, iTerm2;
`TUI_NOTIFICATIONS` overrides), and sends nothing elsewhere: unlike
`requestAttention`, it never falls back to the bell, because the toast is
already on screen. It is one-way.

**Chosen (built 2026-11-08, decision 4):** a direct-OS route behind the same
option, `SystemNotifier` (TUIApp), the app's run loop's only: `osascript`'s
`display notification` on macOS, `notify-send` on a Linux desktop (a session
bus and a display), each only where `SessionLocality.isLocal()` finds positive
evidence the person is at this machine — no ssh variables, no remote-session
daemon or session keeper among the process's parents, and in tmux every
attached client local. **How it combines with the terminal route:** per
message, the terminal (`OSC 9`) where it posts notifications, else the OS, else
nothing — never both. The terminal goes first because its notification is its
own (its icon; a click raises its window), where `osascript`'s names Script
Editor and a click opens that. `TUI_SYSTEM_NOTIFICATIONS=0` turns the route
off; `1` uses it where TUI cannot tell (zellij, GNU screen at the desk).
`TUI_NOTIFICATIONS=0` turns the terminal route off, so the OS route then
carries toasts, where it is on. The locality test (which can ask tmux for its
clients) and the launch run on a utility queue; the helper's standard streams
are the null device; the message is an argument of its own after `--` — the
AppleScript reads it from `argv`, so nothing in it is ever AppleScript source —
with its control characters dropped, and `notify-send`'s body has its markup
characters escaped. `UNUserNotificationCenter` stays out: it needs a bundle.
Neither helper reports a click back, so the route is one-way, as the terminal's
is.

## 9. Toasts and what is presented over the window

The owner (2026-11-08): "different cases might deserve different behaviour.
Would it make sense for it to be configurable, on a per-notification basis, as
to whether it is always available (even when modal dialogs are visible) or
not? Maybe if it's associated with a specific window (or similar) it should go
under any sheets on that window, while without an association it goes over?
And can we make any notifications that are shown 'under' a dialog
(inaccessible while the dialog is open) extend their duration?"

**Chosen:** `layer: NotificationLayer?` on every post — `.abovePresentations`
or `.belowPresentations` — and a default from whose the post is:

- **Unassociated** — a post through `NotificationService.current` — goes
  **above**: news about the app, whatever is up.
- **A window's** — a post through `@Environment(\.notificationService)` in a
  window's views — goes **below** the sheets, alerts and dialogs presented over
  that window. The window hands its views the service stamped with its serial
  (`ScenePresenter`, `owned(byWindow:)`); a window held behind another does
  not draw it, and its timer waits until that window comes to the front.
- **A presentation's** — a post from inside a sheet or an alert, whose content
  gets the service stamped with the presentation's focus section
  (`owned(byPresentation:)`) — is on top of that presentation while it is the
  one holding the keyboard, and under anything presented over it.

The association rides the environment rather than a parameter because that is
how SwiftUI scopes things to a window or a presentation (`dismiss`,
`openWindow`), and it keeps the API at one enum and one parameter. A post with
no view to read an environment from — a task, a callback — keeps `current`'s
meaning, over everything, which is what such news usually wants.

**Covered** means a `.belowPresentations` toast while a sheet, an alert, a
dialog, a popover or an open menu other than its own presentation holds the
keyboard (`FocusManager.presentedSection(beneath:)`), or one posted for a
window not in front. A covered toast is drawn at the page's level
(`OverlayLevel.popover`, z −0.5: under every presented surface, whose veil dims
it), its buttons inert, and its clock stopped
(`NotificationEntry.covered(atNanos:)`): a toast with three seconds left still
has three when the sheet closes. A dismissed toast is never covered — it is
going. A focused toast still does not fade (5).

**Over a presentation**, an uncovered toast's buttons are live in the toasts'
focus section, which is marked modal while a presentation is up: Tab stays
among the buttons, the window's bars stay inert, and the sheet's presenter
leaves the focus with them (`activatePresentedSection(id:)` does not take back
a modal section activated over its own). F6 hears through the presentation's
input grab (`KeyEventDispatcher.insertHandler(at:sectionID:hearsThroughGrab:_:)`),
but not while a menu is open. Escape is the presentation's unless a toast's
button has the focus; then it dismisses the toast and the focus goes back to
the sheet.

**Considered:** association by an explicit parameter (`post(…, for: window)`),
which needs a window handle TUI does not expose; drawing a presentation's
toast between that presentation and the next one up, which the compositor's
level-then-z order cannot express without a level per presentation — covered
and drawn under them all is what the person can act on anyway; and popovers
handing out a presentation-owned service, which TUIFoundation (below the
service's module) cannot do: a post from inside a popover is the window's.

## API sketch

```swift
@discardableResult
func post(_ messageKey: LocalizedStringKey, style: NotificationStyle = .plain,
          duration: TimeInterval? = 3.0, placement: NotificationPlacement? = nil,
          layer: NotificationLayer? = nil, actions: [NotificationAction] = [],
          desktop: NotificationDesktopDelivery = .never) -> NotificationID
// …and the same taking a StringProtocol (displayed as written), and:
@discardableResult
func post<Content: View>(style: NotificationStyle = .plain, duration: TimeInterval? = 3.0,
                         placement: NotificationPlacement? = nil, layer: NotificationLayer? = nil,
                         actions: [NotificationAction] = [],
                         @ViewBuilder content: @escaping @MainActor @Sendable () -> Content) -> NotificationID
func dismiss(_ id: NotificationID)
func dismissAll()
func dismissAll(at placement: NotificationPlacement)
var defaultPlacement: NotificationPlacement { get set }
var width: Int { get set }

NotificationAction("Undo") { undo() }
NotificationAction("Delete", role: .destructive) { … }
```

## Decisions

1. **Decided 2026-11-08: F6** as the key that reaches a toast's buttons, and
   Escape dismissing the focused toast; the owner answered "Keep" (no reason
   recorded). A configurable key on the service was the alternative.
2. **Decided 2026-11-08: emoji glyphs**, ℹ️ ✅ ⚠️ ❌. The owner: "it's fine
   that they're two cells wide, isn't it? We can compensate for terminal
   clients which mess up the cursor." Built in the forms that are emoji
   everywhere (U+FE0F after ℹ and ⚠; ✅ and ❌ are emoji by default), claimed
   two cells, and measured: iTerm2 and Apple Terminal advance ℹ️ and ⚠️ one
   cell, as their models predict, and the writer makes up the other. An emoji
   ignores SGR, so the style's colour is the border's and the shape carries the
   meaning. Drawn on every host, as the alert presets' marks are, rather than
   gated on `supportsEmojiChrome`, which is about the monochrome VS-15 squares.
   ❌ for an error rather than the alert's 🛑: a failure reported, not a stop.
   A terminal that shows only ASCII gets `! i ok X` (`PlainTerminalText`).
   **`.plain`** as the default style (the old look) and the Close button (3)
   were on the same question, and the owner changed only the glyphs: both
   stand.
3. **Decided 2026-11-08 (stands, see 2): Close** as the button a persistent,
   action-less toast gets (TUI's existing "Close" string, translated already).
4. **Decided 2026-11-08: build the direct-OS route** too — `osascript` on
   macOS, `notify-send` on Linux — "ONLY when confident the person is at this
   machine": `SessionLocality`, conservative, any doubt means not local, and
   `TUI_SYSTEM_NOTIFICATIONS` (named after `TUI_NOTIFICATIONS`) disables it.
   Decided here: the terminal route first, the OS route only where the
   terminal posts none, so a notification never arrives twice (§8).
5. **Decided 2026-11-08: per notification, above or below presentations**
   (9), the owner's question quoted there. Default by association: none
   (`current`) above; a window's or a presentation's below what is presented
   over it. A covered toast's timer waits while it is covered; F6 reaches an
   uncovered toast over a sheet, and Escape stays the sheet's unless the toast
   has the focus.

## Known gaps

- In a `TUITesting` `TestApp`, whose frames run on a clock of their own from
  zero, a toast's age is measured on the machine's clock, so it never gets past
  the first instant of its fade-in and draws blank (its buttons still work). It
  was so before this work too. Measuring the age on the frame clock from the
  first frame that draws a toast would fix it; not done here.
- A toast's live content is redrawn only when something asks for a frame: a
  `TimelineView` inside it does (the Example's download does that).
