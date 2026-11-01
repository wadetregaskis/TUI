# Apps and Windows

Define your app and its windows, and fill in their menu bar, toolbars and status bar.

## Topics

### Essentials

- <doc:BuildingYourFirstApp>
- <doc:ScenesAndQuitting>
- <doc:StatusBarGuide>
- <doc:TerminalSupport>
- <doc:ShippingAnApp>
- <doc:TestingYourApp>

### Apps and Scenes

- ``App``
- ``Scene``
- ``WindowGroup``
- ``ScenePhase``

### Quitting

- ``QuitBehavior``
- ``QuitConfirmation``
- ``Scene/quitConfirmation(_:)``
- ``View/quitWarning(_:isActive:)-(LocalizedStringKey,_)``
- ``View/quitWarning(_:isActive:)-(S,_)``

### Running Without a Terminal

- ``App/runWithoutTerminal(_:)``
- ``NoTerminal``
- ``renderOnce(output:content:)``
- ``RenderOnceOutput``

### Windows

- ``Window``
- ``Settings``
- ``SettingsLink``
- ``WindowVisibilityToggle``
- ``WindowInteractionBehavior``
- ``SceneBuilder``
- ``ScenePadding``
- ``PresentedWindowContent``
- ``DefaultSettingsLinkLabel``
- ``DefaultWindowVisibilityToggleLabel``
- ``TerminalProgress``

### Commands and the Menu Bar

- ``Commands``
- ``CommandsBuilder``
- ``CommandMenu``
- ``CommandGroup``
- ``CommandGroupPlacement``
- ``EmptyCommands``
- ``SidebarCommands``
- ``InspectorCommands``
- ``ToolbarCommands``
- ``TextEditingCommands``
- ``DisplayCommands``

### Toolbars

- ``CustomizableToolbarContent``
- ``ToolbarContent``
- ``ContentToolbarPlacement``
- ``DefaultToolbarItem``
- ``LabeledToolbarItemGroupContent``
- ``SpacerSizing``
- ``ToolbarContentBuilder``
- ``ToolbarCustomizationBehavior``
- ``ToolbarCustomizationOptions``
- ``ToolbarDefaultItemKind``
- ``ToolbarItem``
- ``ToolbarItemGroup``
- ``ToolbarItemPlacement``
- ``ToolbarPlacement``
- ``ToolbarRole``
- ``ToolbarSpacer``
- ``ToolbarTitleMenu``

### Status Bar

- ``StatusBar``
- ``StatusBarState``
- ``StatusBarItem``
- ``StatusBarItemProtocol``
- ``ChromeStyle``
- ``StatusBarAlignment``
- ``Shortcut``
- ``QuitShortcut``
- ``StatusBarItemBuilder``
- ``StatusBarItemOrder``
- ``StatusBarItemComposition``
- ``StatusBarKeySpelling``
- ``SystemStatusBarItem``

### Opening and Closing Things from Your Code

- ``OpenWindowAction``
- ``DismissWindowAction``
- ``DismissBehavior``
- ``OpenURLAction``
- ``OpenSettingsAction``
- ``MenuActionDismissBehavior``
- ``RefreshIndicator``
- ``RequestAttentionAction``
