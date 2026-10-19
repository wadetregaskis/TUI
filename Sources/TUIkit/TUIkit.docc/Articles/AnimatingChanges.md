# Animating Changes

Change a value and let the picture catch up.

## Overview

```swift
withAnimation(.easeInOut(duration: 0.3)) {
    isExpanded.toggle()
}
```

The change itself is immediate. `isExpanded` is `true` the instant the closure
returns, every event handler sees `true`, and every `if` in every body sees
`true`. What lags is the *picture*: views that nominated something continuous
about themselves are drawn at values between the old and the new until the
animation ends.

That distinction is the whole model, and it is why an animation cannot break
your logic. Nothing is deferred, queued, or half-applied — only drawn late.

## What actually animates

A view animates by conforming to ``Animatable`` and naming the one continuous
thing about it:

```swift
struct Bar: View, Animatable {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    var body: some View {
        let filled = Int((Double(width) * fraction).rounded())
        Text(String(repeating: "█", count: filled))
    }
}
```

Everything else about the view — its width, its glyphs, its colour — is a
function of that one value, so the framework only has to interpolate the value
to get every frame in between.

Terminal geometry is whole cells, and ``VectorArithmetic`` is deliberately not
conformed by `Int` for that reason: the *animation* is continuous and the
*drawing* rounds. Rounding per sample instead would quantise the curve as well
as the position, and an eased move would come out linear.

Much of what you would want to animate is animatable already, so most changes
need no type of your own:

| You change | What moves |
|------------|------------|
| ``View/opacity(_:)`` | The fade |
| ``View/offset(x:y:)`` | The displacement — layout is untouched, so this is the cheapest |
| ``View/shadow(color:radius:x:y:)`` | The radius and the offset, in whole cells, and the colour |
| ``View/padding(_:_:)`` | The insets, and the layout around them |
| ``View/frame(width:height:alignment:)`` | A **fixed** width and height |
| ``View/foregroundStyle(_:)-(Color)``, ``View/background(_:)-(Color)``, ``View/border(_:style:width:)-(Color,_,_)`` | The colour |
| A **gradient** given to ``View/foregroundStyle(_:)-(S)`` or ``View/background(_:)-(S)`` | Every stop's colour, every stop's location, and the geometry's own numbers |

```swift
Text("Saved")
    .opacity(hasSaved ? 1 : 0)
    .animation(.easeInOut(duration: 0.4), value: hasSaved)
```

A `BufferModifier` of your own joins that list by conforming to ``Animatable``
and naming one property — `ModifiedView` is animatable whenever its modifier
is, so there is nothing else to learn.

A gradient animates as a handful of independent numbers rather than as one
value, which is what makes the awkward case fall out for free: growing a
two-stop ramp into a five-stop one fades the two stops that were already there
and shows the three that were not at their final colours, because a value the
animator has never seen appears rather than fades.

Three boundaries are worth knowing because they look like bugs otherwise. A
**flexible** frame (`maxWidth: .infinity`) has no number to move between, so it
snaps. `Text`'s own `foregroundStyle(_:) -> Text` overload carries the colour in
the view *value* rather than painting it, so a colour set that way changes at
once; wrap the text to fade it. And a gradient that changes KIND — a colour
becoming a ramp, a ``LinearGradient`` becoming a ``RadialGradient`` — snaps,
because the numbers on either side mean different things and interpolating a
radius toward an ordinate is not a transition.

## Saying it at the change, or at the view

``withAnimation(_:_:)`` states it where the change is made. Use it when the code
making the change is the code that knows it should be seen moving — a button's
action, a keyboard shortcut.

``View/animation(_:value:)`` states it where the change is *seen*. Use it when
the change is made somewhere with no business knowing how it will be shown — a
model update, a network result, a binding written by a control.

The two compose, and neither vetoes the other. `.animation(_:value:)` **adds**
an animation for changes to its value; it does not mask an explicit
`withAnimation`, and several of them nest happily, each governing its own value.
To refuse animation outright, say so outright:

```swift
content.transaction { $0.disablesAnimations = true }
```

A view does not animate into existence: the first render of a value is not a
change, so nothing fades in merely because it scrolled into view.

## What it costs

A terminal has no compositor and no render server. SwiftUI can hand an
interpolation to Core Animation and never re-evaluate a body; here, an
animating subtree really is walked once per frame. So the honest accounting is:

| Animation | Cost |
|-----------|------|
| A finite one (``Animation/easeInOut``, a spring, `repeatCount`) | One render pass per frame at 30 Hz, **for its duration**: every second tick of 1/60 s, the instants the framework's other 2-tick animations draw at too. A quarter-second ease is about eight passes, then nothing. |
| ``Animation/repeatForever(autoreverses:)`` on ``View/opacity(_:)`` | The cycle is pre-rendered once and replayed by the run loop — **no render passes at all** while it runs. |
| `repeatForever` on anything else | One render pass per frame, for as long as the view is on screen. |

The middle row is the one to understand, because it generalises. A never-ending
animation is a *decoration*, and a decoration that costs a render pass twenty
times a second, forever, is the pathology ``AnimatedCellRun`` exists to remove.
Where the animated value only ever **re-styles a buffer the content already
produced** — which is exactly what `.opacity` does — the framework computes
every point of the cycle up front and hands the run loop the finished frames.
Nothing re-renders; the loop splices frames over the picture already on screen.

For `.opacity` that computation happens at the COMPOSITE rather than at the
view, because a phase cannot be coloured until what is behind the layer is
known. The saving is the same: the content is rendered once, and the cycle
costs one re-colouring of its finished lines per phase.

Where the value changes what is *drawn* rather than how it is coloured, that
shortcut is not available: rendering a subtree once per phase would multiply
every one of its side effects — focus registration, hit-test regions,
`onAppear`, preference writes — by the length of the cycle.

So for a decoration that is not a re-colouring, reach for the lower-level route
in <doc:AnimatingYourOwnView>, which lets a view hand the loop its own finished
frames. `withAnimation` is for *changes*; that is for *decorations*.

## Updating on a schedule

Not everything that changes over time is a change to *state*. A clock is not
animating: it is showing a different value each minute, and the view that shows
it wants to be re-rendered when the minute turns. That is ``TimelineView``:

```swift
TimelineView(.everyMinute) { context in
    Text(context.date, style: .time)
}
```

The date the content receives is the schedule's **entry**, not the instant of
the render. With ``TimelineSchedule/everyMinute`` it is the top of the current
minute however late in that minute the frame lands, so a clock never shows a
time that disagrees with the boundary it was drawn for. And it is one entry for
the whole frame: the schedule is resolved against the frame's own date, read
once when the frame begins, so the pass that lays the content out and the pass
that draws it never land either side of a boundary — a timer is not measured
for "9s" and drawn as "10s".

The cost model is the one this article keeps coming back to. A timeline is not a
poll: each frame it declares exactly one wake — the next entry — and the run
loop sleeps until then. A clock ticking once a minute renders once a minute, and
a schedule with nothing left to show (an exhausted
``TimelineSchedule/explicit(_:)``, a paused ``TimelineSchedule/animation``)
declares no wake at all, so the screen goes fully idle.

``TimelineSchedule/animation`` is the exception that proves it: asking for the
app's frame rate really does mean a render pass per frame, and it belongs to the
same "decoration" bucket as `repeatForever` above. If what varies is how the
content is *coloured* rather than what it *says*, the lower-level route in
<doc:AnimatingYourOwnView> is cheaper by the width of the render pass.

## Coming and going

`View.transition(_:)` says how a view arrives when it is inserted and how it
leaves when it is removed:

```swift
if showDetail {
    Detail().transition(.move(edge: .top).combined(with: .opacity))
}
```

``AnyTransition/opacity``, ``AnyTransition/move(edge:)``,
``AnyTransition/slide``, ``AnyTransition/push(from:)``,
``AnyTransition/offset(x:y:)``, ``AnyTransition/scale(scale:anchor:)`` and
``AnyTransition/identity`` compose with ``AnyTransition/combined(with:)`` and
``AnyTransition/asymmetric(insertion:removal:)``. Each is also a ``Transition``
type of its own — ``OpacityTransition``, ``MoveTransition`` and the rest — and
`.transition(_:)` takes either spelling. A transition runs when the change that
caused it was animated, or when it names an animation of its own with
``AnyTransition/animation(_:)`` — that one plays with no `withAnimation` at all,
as SwiftUI's does. Otherwise it stays instant, so leaving one on a view that
also appears for other reasons — a page opening, a list rebuilding — is safe.
Each half of an `asymmetric` transition runs under its own animation where it
names one,
``AnyTransition/animation(_:)`` with `nil` makes a transition come and go at
once inside any `withAnimation`, and the animation written nearest the view
wins.

A view with no `.transition` that comes or goes under an animated change fades,
as SwiftUI's does: the default is ``AnyTransition/opacity``. That is an `if`'s
view, the branch an `if`/`else` takes and the one it leaves, a `switch`'s case
and a `ForEach`'s row — fading in where it lands and out where it was. In a lazy
stack, a `Grid`, a `List` and a `Table` a branch, a case and a row still change
at once; an `if`'s view fades there too.

A ``Transition`` of your own describes the view at each ``TransitionPhase`` with
ordinary modifiers, and what animates is each modifier's value between one phase
and the next:

```swift
struct SlideAndFade: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .offset(x: Int(phase.value) * 4)
    }
}
```

It is drawn by rendering its body at the end phase, noting every animatable
value, and rendering it again at rest with each value part-way there — the same
interpolation an animated change performs. ``Transition`` lists what differs
from SwiftUI.

The effects apply to the rendered cells rather than to layout: a view sliding
in gets its space at once and moves into it. `.scale` has no sub-cell rendering
to shrink, so it uncovers the view from its anchor a cell at a time.

The layout changes at once, as SwiftUI's does, and under the animation the
views it moves glide from where they were to where they now go: a view arriving
is drawn where it lands while the row below slides out of its way, and a view
leaving gives its room back at once and plays its removal where it was,
beneath the views gliding up over it. `View.transitionSpace(_:)` holds an
`if`'s room until its removal has played, for an app that wants the views
around to stand still.

A **removal** needs something to play it, because the view is gone from the
tree by the time anything notices. The picture the view drew on its last frame
is left behind, and what still stands where it stood draws it part-way gone:
the `nil` an `if` became, or — for the branch an `if`/`else` leaves, a
`switch`'s case or a `ForEach`'s row — the stack that placed it, which sees it
go. Put the `.transition` on the view the `if` holds — after anything that
draws, though a modifier that draws nothing of its own, such as `.onAppear` or
`.foregroundStyle`, may come after it: in a few shapes the removal fades rather
than play the transition, and `View.transition(_:)` lists them.

## Springs

``Animation/spring(duration:bounce:blendDuration:)`` is a real damped oscillator, evaluated in
closed form. `bounce: 0` is the fastest approach that does not overshoot;
positive values overshoot and oscillate; negative values are sluggish.
``Animation/smooth``, ``Animation/snappy`` and ``Animation/bouncy`` are the
usual three points on that scale. ``Spring`` is the same oscillator as a value
of its own — convert between duration and bounce and mass, stiffness and
damping, or ask where a spring is at a given time — and
``Animation/spring(_:blendDuration:)`` animates with one.

A spring approaches its target asymptotically, so it has no exact end. It is
given one where the answer stops mattering: a terminal draws whole cells and at
most 256 shades, so a residual of 0.2% cannot change anything on screen, and the
animation retires there.

## Keyframes

A ``KeyframeTimeline`` describes a value's whole path rather than a change to
it — keyframes laid end to end, each with how it gets there — and answers what
the value is at any time:

```swift
let wobble = KeyframeTimeline(initialValue: 0.0) {
    CubicKeyframe(4, duration: 0.2)
    CubicKeyframe(-2, duration: 0.2)
    SpringKeyframe(0, spring: .bouncy)
}
let offset = wobble.value(time: elapsed)
```

Every curve is SwiftUI's, sampled the same way. A timeline is a calculation,
not an animation: something has to ask it for a value at the times it draws,
such as a ``TimelineView`` on the animation schedule.

## Topics

### Animating a change

- ``withAnimation(_:_:)``
- ``View/animation(_:value:)``
- ``Binding/animation(_:)``
- ``Animation``
- ``Spring``
- ``UnitCurve``
- ``AnimationCompletionCriteria``

### Keyframes

- ``KeyframeTimeline``
- ``Keyframes``
- ``KeyframeTrack``
- ``KeyframeTrackContent``
- ``LinearKeyframe``
- ``CubicKeyframe``
- ``SpringKeyframe``
- ``MoveKeyframe``
- ``KeyframesBuilder``
- ``KeyframeTrackContentBuilder``

### Coming and going

- ``AnyTransition``
- ``Transition``
- ``TransitionPhase``
- ``TransitionProperties``
- ``PlaceholderContentView``
- ``OpacityTransition``
- ``MoveTransition``
- ``OffsetTransition``
- ``ScaleTransition``
- ``SlideTransition``
- ``PushTransition``
- ``IdentityTransition``
- ``AsymmetricTransition``

### Declaring what moves

- ``Animatable``
- ``VectorArithmetic``
- ``AnimatablePair``
- ``EmptyAnimatableData``

### Updating on a schedule

- ``TimelineView``
- ``TimelineSchedule``
- ``TimelineScheduleMode``
- ``TimelineViewDefaultContext``

### Controlling it

- ``Transaction``
- ``withTransaction(_:_:)``
- ``View/transaction(_:)``
- ``EnvironmentValues/transaction``

### Doing it by hand

- <doc:AnimatingYourOwnView>
