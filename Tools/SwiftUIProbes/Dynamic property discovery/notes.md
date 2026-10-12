# A-DYNP-1: why SwiftUI ignores a DynamicProperty in an optional field

2026-10-10. Owner's question: "A-DYNP-1: Is there a reason for SwiftUI's
behaviour here?" A-DYNP-1 is in
`git show fca696a35:Documentation/SwiftUI-API-completion-decisions-DYNP.md`.

Labels: **measured** = I ran it here. **established** = read from Apple's SDK
or docs, or from TUIkit source at fca696a35. **OpenSwiftUI** = read from
OpenSwiftUI, a reverse-engineered reimplementation, not Apple's code.
**hypothesis** = not verified.

## The answer

There is a mechanical reason. Nothing shows it was a chosen rule.

SwiftUI finds a view's dynamic properties from the declared type of each
stored field. A field counts only if its type conforms to `DynamicProperty`.
SwiftUI then looks inside it, again only at fields whose types conform. This
is worked out once per view type, when the view's graph node is made.

`Optional` does not conform to `DynamicProperty`, so a `Full?` field is
skipped, as these are:

- a plain struct field,
- a tuple or an array,
- an `any DynamicProperty` or `Any` field,
- an enum that does not conform,
- a `ViewModifier` stored in a view.

Evidence:

- The interfaces and docs say nothing about optionals (established).
- In OpenSwiftUI the discovery code is the conformance cast.
- Adding one line to an app, `extension Optional: @retroactive
  DynamicProperty where Wrapped: DynamicProperty {}`, makes SwiftUI treat an
  optional property exactly like a plain one (measured). That covers
  `update()`, write-back, `@Environment`, `@State`, and a value that starts
  `nil`.

So the exclusion follows from `Optional` lacking the conformance. There is no
separate rule.

Why Apple never conformed `Optional` is undocumented. One concrete obstacle
is measured. A `weak var` field's type is `Optional<T>`. Once `Optional`
conforms, SwiftUI updates a weak field of a class property in place as if it
were a strong optional. It calls `update()` with a `self` that is not the
object (0x154c042b1 / 0x14df04141, where the objects are at 0x153e12ba0 /
0x149612ba0). That is memory-unsafe. Today such a field is skipped, so it is
safe. Whether this is Apple's actual reason is a hypothesis. Others: the cost
of an enum box per optional field, or no demand.

## 1. What Apple ships (established)

SDK: Xcode 26.3, MacOSX26.2.sdk, `SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface`.

`DynamicProperty` (lines 6779-6803) is declared as follows:

```swift
public protocol DynamicProperty {
  static func _makeProperty<V>(in buffer: inout _DynamicPropertyBuffer, container: _GraphValue<V>, fieldOffset: Int, inputs: inout _GraphInputs)
  @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
  static var _propertyBehaviors: UInt32 { get }
  mutating func update()
}
extension DynamicProperty {   // defaults; bodies not in the interface (not @inlinable)
  public static func _makeProperty<V>(...)
  public mutating func update()
  public static var _propertyBehaviors: UInt32 { get }
}
```

- `_DynamicPropertyBuffer` is an opaque `public struct` (line 5859).
- **Doc comments** come from the `.swiftdoc`. Apple's online page for the
  protocol
  (`developer.apple.com/tutorials/data/documentation/swiftui/dynamicproperty.json`)
  has the same protocol text:
  - The protocol: "An interface for a stored variable that updates an
    external property of a view."
  - `update()`: SwiftUI calls it before rendering the view's body.
  - `_makeProperty`: "Creates an instance of the dynamic `View` property
    represented by `self`."
  - `_propertyBehaviors`: a raw value of `DynamicPropertyBehaviors`.
  - `_DynamicPropertyBuffer`: "Unsafe storage type for `DynamicProperty`
    instances."
  - None of these says anything about optional, nested, enum or container
    fields.
- **Conformers in the interfaces:**
  - SwiftUICore: `Namespace`, `EnvironmentObject`, `ObservedObject`,
    `Environment`, `Binding` (by extension), `ScaledMetric`, `_ScaledValue`,
    `StateObject`, `State`.
  - SwiftUI: `GestureState`, `SceneStorage`, `AppStorage`, `FocusState`,
    `NSApplicationDelegateAdaptor`, `FocusedValue`, `FocusedBinding`,
    `FetchRequest` (by extension), `AccessibilityFocusState`,
    `SectionedFetchRequest` (by extension), `FocusedObject`.
  - `_SwiftData_SwiftUI`: `Query`.
  - Apple's online page also lists platform-only ones: `PhysicalMetric`,
    `UIApplicationDelegateAdaptor`, `WKApplicationDelegateAdaptor`,
    `WKExtensionDelegateAdaptor`.
  - **No conformance at all, conditional or not, for `Optional`, `Array`,
    tuples, or any generic wrapper.** `Bindable` does not conform either.
- The installed framework is SwiftUI / SwiftUICore 6.5.4 (version.plist,
  macOS 15.8.1). That is the version OpenSwiftUI's `DynamicProperty.swift`
  says it is "Audited for".

## 2. How discovery works (OpenSwiftUI, reverse-engineered)

Source: github.com/OpenSwiftUIProject/OpenSwiftUI @ aefa4e6e (2026-10-09).

**Building a view's buffer.** `Sources/OpenSwiftUICore/View/CustomView.swift:28-61`.
`makeView` calls `DynamicPropertyCache.fields(of: Self.self)` and builds the
body rule's `_DynamicPropertyBuffer` from it, once per graph node. A modifier
does the same: `Modifier/CustomViewModifier.swift:121-176`.

**Finding the fields.** `Sources/OpenSwiftUICore/Data/DynamicProperty/DynamicProperty.swift:144-250`,
`DynamicPropertyCache.fields(of:)`. The result is cached per
`ObjectIdentifier(type)` (lines 196-200, 245). What it does depends on the
type's kind:

- **struct or tuple** (224-234): walks the fields. It keeps a field only if
  `fieldType as? DynamicProperty.Type` succeeds, and records its offset.
  Every other field is skipped and **not descended into**.
- **enum or optional** (204-223): a `.sum` layout. Each case's payload is
  taken as a tuple, and its elements that conform become that case's
  fields.
- **anything else**, a class included (235-236): no fields.

**Looking inside a property.** `DynamicProperty.swift:100-132`. The default
`_makeProperty` calls `makeEmbeddedProperties`. That runs `fields(of: Self)`
on the property's own type, then appends an `EmbeddedDynamicPropertyBox`,
which calls `update()` (89-97). So the inner properties come first, and
nesting happens only through types that conform.

**Applying the fields.** `DynamicPropertyBuffer.swift`:

- `addFields` (47-88): a `.product` layout calls each field's
  `_makeProperty` at `field.offset + baseOffset`. A `.sum` layout builds
  one buffer per case inside an `EnumBox`.
- `update(container:)` (138-152): each box is updated in place at its
  offset. This is the write-back.
- `EnumVTable.update` (692-717): uses `withUnsafeMutablePointerToEnumCase`
  to reach the active case's payload in place. It resets the old case's
  boxes when the case changes.

**Tests.** `Tests/OpenSwiftUICoreTests/Data/DynamicProperty/DynamicPropertyCacheTests.swift`
is disabled under OpenSwiftUI's own AttributeGraph (line 11), so I read it
as written against Apple's (hypothesis). It expects:

- `fields(of: Optional<NormalP>.self)` is `.sum` with one case, tag 0
  `"some"` (94-120). The cache handles an optional when asked; nothing asks
  unless `Optional` conforms.
- A tuple type gives no fields (149-159).
- A class gives no fields (161-180).

The measurements below agree with all of this.

## 3. Measured matrix

**What was run.** SwiftUI 6.5.4 on macOS 15.8.1, offscreen `NSHostingView`.
The probe is `op.swift`, built with Xcode's swiftc 6.2.4 and `-target
arm64-apple-macos15.0`, run with `OS_ACTIVITY_DT_MODE=YES` so SwiftUI's
runtime warnings reach stderr. Outputs: `op.out`, and `op-optconf.out` for
the `-D OPTCONF` build with the retroactive conformance.

**The property.** Every case holds the same `Full`:

- a `count` that `update()` increments,
- `@Environment(\.lineLimit) var limit`, with the view hosted under `.lineLimit(3)`,
- `@State var kept = 5`.

After the first draw, a poke writes 9 through `$kept` and bumps the view's
own `@State`.

**Legend.**

- **U**: `update()` ran.
- **W**: what it changed was written back (body reads `count=1`).
- **E**: `@Environment` resolved (body reads `limit=Optional(3)`).
- **S**: `@State` installed (body reads `kept=9` after the poke; an
  uninstalled one stays 5, because its binding is a constant).
- **—**: none of these. In every "—" case that has an `@Environment` or
  `@State` inside, SwiftUI logs "[SwiftUI] Accessing State's value outside
  of being installed on a View. This will result in a constant Binding of
  the initial value and will not update." and the matching `Environment`
  message.

**TUIkit column.** Read from fca696a35. TUIkit was not built.

| Case (field of a struct view) | SwiftUI (measured) | +Optional conformance (measured) | TUIkit fca696a35 (read) | Same? |
|---|---|---|---|---|
| B1 plain `var p: Full` | U W E S | U W E S | U W E S | yes |
| B2 `var p: Full?` (non-nil) | — | U W E S | U W E S | **no (A-DYNP-1)** |
| (v) `@State` inside `Full?` | not installed (stays 5, warning) | installed | installed | **no** |
| (vi) `Full?`, `nil` at first draw, then non-nil | — before and after | U W E S after the change | U W E S after the change (B-DYNP-2 walks the type every frame) | **no** |
| (i) `struct Holder { var p: Full }`, not conforming | — | — | — | yes |
| (ii) `struct HolderDP: DynamicProperty { var p: Full }` | U W E S | U W E S | U W E S | yes |
| (iii) `enum E { case a(Full), b }`, not conforming | — | — | — | yes |
| (iii-b) `enum EDP: DynamicProperty { case a(Full), b }` | U W E S | U W E S | U E S, **not W** | **no (W)** |
| (iv) tuple `(Full, Int)` | — | — | — | yes |
| (iv-b) array `[Full]` | — | — | — | yes |
| (vii-a) `var p: any DynamicProperty = Full(…)` | — | — | U W E S | **no (new)** |
| (vii-a2) `var p: Any = Full(…)` | — | — | U W E S | **no (new)** |
| (vii-b) generic `var t: T`, T = `Full` | U W E S | U W E S | U W E S | yes |
| (vii-c) a `ViewModifier` holding `Full`, stored in a view field, not applied | — | — | U W E S | **no (new)** |
| (vii-c2) the same modifier applied with `.modifier(m)` | the view's field: —; the modifier's own copy: U W E | same | the view's field: U W E S; the copy in `ModifiedContent`: U W E S | **no (the view field)** |
| (vii-f) a class `DynamicProperty` held strongly, with `@Environment`/`@State` inside | U only; E and S not installed (warnings) | same | U E S | **no (new: E S)** |
| case 4 (dp.out) `weak var w: Box?` | not updated | update() on a bogus `self` (weak.out) | not updated; what it holds is bound and resolved | partly |

Two more observations, not part of the question:

- **(vii-d) A `Binding` in an optional field** of a child, measured. After a
  change, both children read the new value. In the plain build the
  parent's body ran again too, though it reads only `$value`. Under the
  conformance it did not. A hypothesis: SwiftUI saw an uninstalled
  binding's read and made the parent depend on the state. Either way,
  SwiftUI skipping an optional `Binding` costs an extra body, not a stale
  value. Not compared for TUIkit.
- **Pass-through modifiers**, measured in `passmod.out`. SwiftUI 6.5.4
  neither runs a modifier's `body` nor calls `update()` on its properties
  when the body returns `content` unchanged. `content.padding(1)` does run
  both. This is unrelated to A-DYNP-1, and TUIkit's behaviour here is not
  checked. It may be worth a parity check.

### TUIkit, the code behind its column (established, fca696a35)

TUIkit finds properties from the value, not the declared type. Its walks use
`Mirror` and a dynamic cast on each child: `State.swift:668-702`
(`bindStateProperties`) and `EnvironmentProperty.swift:260-272`.
`NestedProperties.container` (`DynamicProperty.swift:77-81`) descends into
any value that `is any DynamicProperty || is any ViewModifier`.

A Swift dynamic cast from `Any` looks through `Optional` and through
existential boxes, and `Mirror` opens both. That is why TUIkit reaches the
B2, (v), (vi), (vii-a) and (vii-c) cases. A class instance's `Mirror` lists
its stored properties, so TUIkit also reaches inside (vii-f).

Plain structs, tuples, arrays and non-conforming enums fail the cast, so
TUIkit skips them, as SwiftUI does.

The write-back follows the same paths:

- `mayBeContainer` (`DynamicProperty.swift:137-148`) loads optionals,
  existentials and classes.
- `isContainerType` (153-156) accepts a `ViewModifier`.
- An enum's payload is updated on copies only (`updateDynamicProperties`'
  default arm, 292-293, and `updateCopies`/`updateCopy`, 324-341). That is
  why (iii-b) is not W.

## 4. Deliberate or incidental?

It looks incidental to a design that discovers properties by conformance and
type, with the layout fixed per view type. Nothing in the record suggests a
chosen rule against optionals.

- Nothing is documented (§1).
- SwiftUI's own cache has an `.optional` arm (OpenSwiftUI). It is reached
  only by a type that conforms, and `Optional` does not.
- A retroactive conformance makes optionals work completely (measured).
- When a property inside an unvisited field is read, SwiftUI warns at run
  time that it was read "outside of being installed on a View". It treats
  this as a programmer error, the same message as for every other unvisited
  case. It does not handle optionals specially.
- The same rule also skips existentials, stored modifiers, and a class's
  contents. None of those reads as a policy about optionals.

One thing does make a plain `Optional` conformance unsafe as SwiftUI is
built: weak fields, measured (weak.out). Whether Apple held back for that
reason is a hypothesis.

## 5. New divergences found (beyond A-DYNP-1)

**1. Existential fields, (vii-a).** For `any DynamicProperty` and `Any`
fields, SwiftUI does nothing. TUIkit binds, resolves, updates and writes
back. B-DYNP-2 already says TUIkit looks into existentials. It is not
written down as a divergence from SwiftUI.

**2. A `ViewModifier` stored in a view's field, (vii-c).** TUIkit treats it
as a property container, because its walks look into every `ViewModifier`
value: that is how `ModifiedContent`'s modifier gets its properties. SwiftUI
gives such a field nothing. When the modifier is applied, SwiftUI gives
properties only to the copy inside `ModifiedContent`.

**3. A class property's contents, (vii-f).** SwiftUI runs a class property's
`update()`, but never installs the `@State` or `@Environment` inside it.
TUIkit installs both. This also answers the open note in A-DYNP-1: a `weak`
field's contents are not installed in SwiftUI. That follows from (vii-f)
plus case 4; it was not measured directly.

**4. Enum `DynamicProperty` fields, (iii-b).** SwiftUI writes the payload
back. TUIkit runs `update()` on a copy. This is the B-DYNP-1 limitation,
which also applies to an enum property, not only to an enum view; B-DYNP-1
names only the view.

**5. Declaration-order state keys move when a value changes.** The keys are
established from reading the code; their consequence is a hypothesis, not
run. Nested `@State` takes the next index of the view's one counter, in
`Mirror` order (`State.swift:663-665, 672-700`). A `nil` optional
contributes no index.

So in `struct V: View { var p: Full?; @State var x = 0 }`, `x` is key 0
while `p` is `nil`, and key 1 once `p` holds a value. At that point
`p.kept` takes key 0. `StateStorage.storage(for:default:)`
(`StateStorage.swift:242-255`) returns an existing box of the same type
(here `x`'s value), and makes a new box when the type differs. So `x` would
lose its value and `kept` would start with `x`'s.

The same could happen with an existential field whose type changes, or an
enum view whose cases hold different numbers of `@State`. SwiftUI keys each
box by field offset, with separate per-case buffers that reset when the case
changes, so it has no such shift. This needs a TUIkit test before anyone
relies on it.

## 6. What this means for A-DYNP-1, and a recommendation

The optional case is one example of a general difference. TUIkit finds
properties from values, using casts that look through `Optional` and `any`,
and into modifiers and class instances. SwiftUI uses the declared field type
and requires a conformance.

- **(a) Keep TUIkit's behaviour.** No working SwiftUI app depends on what
  TUIkit adds: in SwiftUI those properties are inert, and SwiftUI warns at
  run time when there is `@State` or `@Environment` inside. TUIkit keeps
  paying for it:
  - the walk on every frame for a type that holds an optional (B-DYNP-2),
  - the state-key shift in §5.5 (hypothesis),
  - code that works on TUIkit and silently does nothing on SwiftUI.
- **(b) Match SwiftUI.** This is more than "one rule in two walks". To
  match all the rows above, the walks would descend only where the
  **declared** field type conforms (`RuntimeFields` already gives the type
  and offset). That removes optionals, existentials, a class's contents, and
  modifiers stored in a view. `ModifiedContent`'s own modifier must still
  be descended into, since that is how TUIkit gives a modifier its
  properties.
  - Possible benefits (hypothesis, not measured): the answer could be
    cached per type, as SwiftUI's `DynamicPropertyCache` is. That would end
    the per-frame `Mirror` walk for most types, and most of B-DYNP-2's value
    checks, except for enums.
  - Price: an app relying on TUIkit's looking through would lose it, its
    environment going back to the default. TUIkit is pre-1.0 and keeps no
    compatibility shims.

**Recommendation: (b).** Do it as the declared-type rule, in two steps:

1. Optionals and existentials, which is A-DYNP-1 proper. Add a TUIkit test
   for §5.5 first, so the step shows whether the shift was real.
2. Modifiers stored in a view, and a class's contents.

Keep the enum write-back difference as B-DYNP-1 already prices it, and
widen B-DYNP-1's text to cover enum properties.

If the owner prefers (a), §5.5 still needs that test. If the shift is real,
the fix is to key nested state by something that does not depend on the
value, such as the field's path or offset.

## Files (this folder, `Tools/SwiftUIProbes/Dynamic property discovery/`)

- The harness, `dp.swift`, and its output `dp.out` are in `../Dynamic properties/`.
- `op.swift`: the probe for this note. Build it as
  `swiftc -sdk <Xcode MacOSX.sdk> -target arm64-apple-macos15.0 op.swift -o op`,
  and the same with `-D OPTCONF -o op-optconf`. Run it as
  `OS_ACTIVITY_DT_MODE=YES ./op`.
- `op.out` and `op-optconf.out`: the output of the two builds.
- `weak.swift` and `weak.out`: the weak-field hazard under the conformance.
- `passmod.swift` and `passmod.out`: the pass-through modifier skip.
- The built probes, `op` and `op-optconf` (about 300 KB each), are not kept: build them as above.
