# Under the Hood

How TUI draws, and the lower-level types for custom rendering and for talking to the terminal.

## Topics

### Essentials

- <doc:Architecture>
- <doc:AppLifecycle>
- <doc:RenderCycle>
- <doc:ModuleIndex>

### Rendering

- ``FrameBuffer``
- ``RenderContext``
- ``ChildInfoProvider``
- ``ChildViewProvider``
- ``ContentRewrapping``
- ``ExplicitIDProviding``
- ``Layoutable``
- ``LazyChildViewProvider``
- ``Renderable``
- ``SingleContentWrapper``
- ``SpacerProtocol``
- ``ZIndexProviding``
- ``ChildInfo``
- ``ChildView``
- ``ChildViewCollection``
- ``ViewArray``
- ``ViewIdentity``
- ``renderToBuffer(_:context:)``

### Terminal Capabilities

- ``TerminalCapabilities``
- ``TerminalClient``
- ``TerminalQuirks``

### ANSI and Terminal Output

- ``OpacityRegion``
- ``KittyGraphics``

### View Modifier Types

- ``EnvironmentalModifier``
- ``ShapeView``
- ``FillShapeView``
- ``HierarchicalShapeStyleModifier``
- ``ItemProviderTableRowModifier``
- ``OnInsertTableRowModifier``
- ``StrokeBorderShapeView``
- ``StrokeShapeView``
- ``TupleView``
- ``ConditionalView``

### Animation Internals

- ``DrawsContentUnchanged``
- ``AnimatedColor``
- ``AnimatedRunAlpha``

### Utilities

- ``tuiVersion``
