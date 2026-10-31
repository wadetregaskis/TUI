# Accessibility settings: reduce motion, transparency and contrast

*Which host settings TUI reads, from where, and what its own drawing does
with them. Ids: A-D3M-1, P5, O1-LOOSEN.*

## In short

Reduce motion, reduce transparency, differentiate without colour and increase
contrast are read as reduce motion is: the host's setting in local sessions
only, each with a `TUIKIT_*` override, and TUI's own drawing honours them
(P5, option c). Reduce motion holds still only spatial motion (A-D3M-1). The
owner kept the "certain locality" standard (O1-LOOSEN, no change, 2026-10-23).

## For a future reader

- **Reduce motion does not hold still an app's own animations** (C-FU2-1), only TUI's spatial motion.

## The record

### A-D3M-1. What else reduce motion should hold still — decided 2026-10-05

*`EnvironmentValues.accessibilityReduceMotion` (B53)*

The owner: breathing, spinners, progress bars and the like are not "motion"
here; each serves a purpose. Motion means spatial motion — unnecessary
movement in X and Y — such as view animations that move or scale a view and
a drag-and-drop preview flying back home.

**Shipped:** under reduce motion, an animated change of `.offset`,
`.position`, padding or a fixed `.frame` (and an offset in a
`visualEffect` or an `.animated` `scrollTransition`, whose colours and
opacity still animate — the scroll transition since follow-up FU3) jumps to
its end
value; a drag-and-drop preview does not travel — no lift out of its row,
no fly-back when a drop is cancelled or refused, no settling morph — and
the row is back in place at once. Transitions with motion already played
as fades. Not affected: the
focus breath, the caret's blink, spinners, progress indicators, opacity and
colour animations, symbol effects. A scroll that glides since B27-ANIMATING
(2026-10-24) jumps: a `ScrollView`'s, a `List`'s or a `Table`'s `scrollTo`,
`ScrollPosition` request or written anchor edge made inside an animation,
on either axis, and the page keys under `scrollKeyboardAnimation(_:)`. An app's own `Animatable` view, a keyframe
animator's tracks and a custom `Layout`'s data are the app's to hold still,
as in SwiftUI.

### P5. Reduce transparency, differentiate without colour and increase contrast are read as reduce motion is

*`EnvironmentValues.accessibilityReduceTransparency`,
`.accessibilityDifferentiateWithoutColor`, `.colorSchemeContrast` and their
underscored setters; ruling: (c), option (b) plus the host read.*

**Shipped.** The reduce-motion plumbing carries a set
(`AccessibilityPreferences`, a prepared refactor): the user's variables
(`TUIKIT_REDUCE_TRANSPARENCY=1`, `TUIKIT_DIFFERENTIATE_WITHOUT_COLOR=1`,
`TUIKIT_INCREASE_CONTRAST=1`, beside `TUIKIT_REDUCE_MOTION=1`) and the
host's settings, read by `HostSettingsRefresher` at launch and when the
terminal regains the focus, counted only where `SessionLocality.isLocal()`
holds. On macOS the host is `com.apple.universalaccess`'s `reduceMotion`,
`reduceTransparency`, `differentiateWithoutColor` and `increaseContrast`
(the four names are in macOS 15.8's shared cache; the three new ones were
not toggled and read here). On GNOME, `org.gnome.desktop.a11y.interface
high-contrast` is increased contrast; GNOME has no setting for the other
two. The root writes all four. TUI honours reduce transparency: every
material, and glass, is opaque, as an inactive one then was, and so unfrosted.
(Since 2026-10-26 an inactive material stays frosted, half way to opaque —
owner: flat glass in an inactive window "looks like a bug". Reduced
transparency is still opaque.)

**Judgement calls.** The three are read-only, as SwiftUI's are, with
SwiftUI's own underscored setters (`_accessibilityReduceTransparency`,
`_accessibilityDifferentiateWithoutColor`, `_colorSchemeContrast`) to write
them: that is how `.environment` reaches them in SwiftUI. No `Scene`
modifier was added for them (the ruling's option (b) names variables and
`.environment`). TUI's drawing does not change for increased contrast
(the palettes keep their floors either way) or differentiate without colour
(its own cues wait on a design, as the entry recommends): both are reported
for the app's views. `\.accessibilityVoiceOverEnabled` stays refused.

**Cost:** three more environment writes at the root a frame, and, on
macOS, three more preference reads per host reading (launch, focus in); on
GNOME one more `gsettings` run per reading.

### C-FU2-1. Reduce motion does not hold still an app's own animations

*`EnvironmentValues.accessibilityReduceMotion` (A-D3M-1)*

Reduce motion holds still the movement TUI's own modifiers make — an
animated offset, position, padding or fixed frame, a visual effect's offset, a
drag preview's lift and fly-back. An `Animatable` view of the app's own, a
keyframe animator's tracks and a custom `Layout`'s data animate as before:
TUI cannot tell which of an app's numbers are positions, and SwiftUI leaves
them to the app too, which reads `\.accessibilityReduceMotion`.
