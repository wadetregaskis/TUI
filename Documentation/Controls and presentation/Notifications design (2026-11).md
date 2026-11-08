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
leads with a glyph, so the meaning never rests on colour alone: `i`, `✓`, `!`,
`✗`. One-cell, non-emoji glyphs: `ℹ` and `⚠` have emoji presentations that
some terminals draw two cells wide (see the emoji-chrome survey notes).

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
the focus. A click works too, but there is always the key. While a modal holds
the keyboard, toasts still draw but their buttons are inert, as the toolbars'
are.

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

**Proposed (not built):** a direct-OS route behind the same option, used only
when TUI can be sure the app runs on the user's machine: no `SSH_CONNECTION`,
`SSH_CLIENT` or `SSH_TTY`, and not inside tmux or screen attached from
elsewhere. On macOS `osascript` works unbundled but carries no actions and
names Script Editor as the sender; `UNUserNotificationCenter` needs a bundle,
which a SwiftPM executable lacks. On Linux, D-Bus is the route with actions,
which would need a D-Bus client (no Foundation API) or a `notify-send`
subprocess (no actions back). Launching processes from a library is a policy
question, hence the owner's call below.

## API sketch

```swift
@discardableResult
func post(_ messageKey: LocalizedStringKey, style: NotificationStyle = .plain,
          duration: TimeInterval? = 3.0, placement: NotificationPlacement? = nil,
          actions: [NotificationAction] = [], desktop: NotificationDesktopDelivery = .never) -> NotificationID
// …and the same taking a StringProtocol (displayed as written), and:
@discardableResult
func post<Content: View>(style: NotificationStyle = .plain, duration: TimeInterval? = 3.0,
                         placement: NotificationPlacement? = nil, actions: [NotificationAction] = [],
                         @ViewBuilder content: @escaping @MainActor @Sendable () -> Content) -> NotificationID
func dismiss(_ id: NotificationID)
func dismissAll()
func dismissAll(at placement: NotificationPlacement)
var defaultPlacement: NotificationPlacement { get set }
var width: Int { get set }

NotificationAction("Undo") { undo() }
NotificationAction("Delete", role: .destructive) { … }
```

## Decisions to confirm

1. **F6** as the key that reaches a toast's buttons, and Escape dismissing the
   focused toast. Alternatives: a configurable key on the service.
2. **Glyphs** `i ✓ ! ✗`, and **`.plain`** as the default style (the old look).
3. **Close** as the button a persistent, action-less toast gets (TUI's
   existing "Close" string, translated already).
4. **The direct-OS route**: build it (spawning `osascript` / `notify-send`
   from the library, same machine only), or leave OS notifications to the
   terminal route.
5. **Toasts over a modal** draw but their buttons are inert until it closes.
