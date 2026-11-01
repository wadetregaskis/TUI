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
- ``OverlayLayer``
- ``OverlayLevel``
- ``BodyMutationDiagnostic``
- ``RenderCache``
- ``ChildInfoProvider``
- ``ChildViewProvider``
- ``ContentRewrapping``
- ``ExplicitIDProviding``
- ``LayoutPlacing``
- ``Layoutable``
- ``LazyChildViewProvider``
- ``PrefixExtending``
- ``Renderable``
- ``SingleContentWrapper``
- ``SpacerProtocol``
- ``ZIndexProviding``
- ``AnyEquatableBox``
- ``ChildInfo``
- ``ChildView``
- ``ChildViewCollection``
- ``Placement``
- ``RetainedSubtreeIndex``
- ``ViewArray``
- ``ViewIdentity``
- ``identityKey(_:)``
- ``makeChildInfo(for:context:)``
- ``measureChild(_:proposal:context:)``
- ``measureFixedByRendering(_:proposal:context:)``
- ``renderChild(_:width:height:context:)``
- ``renderToBuffer(_:context:)``
- ``resolveChildInfos(from:context:)``
- ``resolveChildViewCollection(from:context:)``
- ``resolveChildViews(from:context:)``

### Terminal Capabilities

- ``TerminalProtocol``
- ``TerminalCapabilities``
- ``TerminalClient``
- ``TerminalQuirks``

### ANSI and Terminal Output

- ``ANSICellSpan``
- ``ANSIRowCells``
- ``OpacityRegion``
- ``SGRState``
- ``TerminalHyperlink``
- ``TerminalWidthTraits``
- ``asciiSpaces(_:)``
- ``ANSICellDiff``
- ``ANSISegment``
- ``FieldUnderContent``
- ``KittyGraphics``
- ``SystemZlib``
- ``TerminalSymbols``

### View Modifier Types

- ``EnvironmentalModifier``
- ``ShapeView``
- ``AlertPresentationModifier``
- ``BackgroundModifier``
- ``BadgeModifier``
- ``DimmedModifier``
- ``DisabledModifier``
- ``DraggableModifier``
- ``DropDestinationModifier``
- ``EnvironmentModifier``
- ``FillShapeView``
- ``FlexibleFrameView``
- ``HelpModifier``
- ``HierarchicalShapeStyleModifier``
- ``ItemProviderTableRowModifier``
- ``KeyEventModifier``
- ``ListRowSeparatorModifier``
- ``ModalPresentationModifier``
- ``MouseSupportModifier``
- ``ObjectEnvironmentModifier``
- ``OffsetView``
- ``OnHoverModifier``
- ``OnInsertTableRowModifier``
- ``OnMouseEventModifier``
- ``OnSubmitModifier``
- ``OverlayModifier``
- ``PaddingModifier``
- ``PositionView``
- ``RefreshableModifier``
- ``SelectionDisabledModifier``
- ``StrokeBorderShapeView``
- ``StrokeShapeView``
- ``StyleCascadeModifier``
- ``ThemeModifier``
- ``TintModifier``
- ``TransformEnvironmentModifier``
- ``TupleView``
- ``ConditionalView``

### Animation Internals

- ``AnimationStore``
- ``DepartureStore``
- ``PlacementStore``
- ``DrawsContentUnchanged``
- ``AnimatedColor``
- ``AnimatedRunAlpha``
- ``AnimationCycle``
- ``AnimationFrame``
- ``OpacityCycle``
- ``AnimatedBufferCycle``

### State Internals

- ``AppState``
- ``PreferenceStorage``
- ``StateBox``
- ``StateStorage``
- ``VolatileReadTracker``
- ``RenderIdentityBindable``
- ``RenderInvalidationSink``
- ``StateRegistration``

### Utilities

- ``Lock``
- ``StackGuard``
- ``AutoRepeatTimer``
- ``tuiVersion``
- ``extractBadgeValue(from:)``
- ``viewTypeCarriesBadge(_:)``
- ``RenderPass``
