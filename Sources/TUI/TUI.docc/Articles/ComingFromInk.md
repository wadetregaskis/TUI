# Coming from Ink

Map what you know from Ink and React onto TUI.

## Overview

Ink brings React to the terminal, and TUI brings SwiftUI, so they're close relatives. Both describe the screen as a tree of components built from state, re-run that description when the state changes, and work out what to redraw. Most of what you know carries over. The differences are in the language, in how layout works, and in what's built in.

If `@State`, `body` or modifiers are new to you, read <doc:NewToSwiftUI> first. The JavaScript on this page is for Ink 8.

## The Same App in Both

A counter that `+` increases, and a list of three fruits with one selected. In Ink:

```jsx
import React, {useState} from 'react';
import {render, Box, Text, useInput, useApp} from 'ink';

const items = ['Apples', 'Bananas', 'Cherries'];

function App() {
	const {exit} = useApp();
	const [count, setCount] = useState(0);
	const [index, setIndex] = useState(0);

	useInput((input, key) => {
		if (input === '+') setCount(c => c + 1);
		else if (key.upArrow) setIndex(i => Math.max(0, i - 1));
		else if (key.downArrow) setIndex(i => Math.min(items.length - 1, i + 1));
		else if (input === 'q') exit();
	});

	return (
		<Box flexDirection="column">
			<Text>Count: {count}</Text>
			{items.map((item, i) => (
				<Text key={item} color={i === index ? 'green' : undefined}>
					{i === index ? '> ' : '  '}{item}
				</Text>
			))}
			<Text>Selected: {items[index]}</Text>
		</Box>
	);
}

render(<App />);
```

In TUI:

```swift
import TUI

@main
struct FruitApp: App {
    var body: some Scene {
        WindowGroup { FruitView() }
    }
}

struct FruitView: View {
    @State private var count = 0
    @State private var selection: String? = "Apples"
    private let fruit = ["Apples", "Bananas", "Cherries"]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Count: \(count)")
            List(fruit, id: \.self, selection: $selection) { name in
                Text(name)
            }
            Text("Selected: \(selection ?? "none")")
        }
        .onKeyPress("+") {
            count += 1
            return .handled
        }
    }
}
```

`useState` becomes `@State`, and `setCount(c => c + 1)` becomes `count += 1`: you assign to the state directly, and TUI notices. The `List` replaces the hand-drawn rows and the arrow-key handling. Its arrow keys move a cursor, and Space or Return selects the row under it. Control-Q quits.

## Concepts

| Ink and React | TUI |
|---|---|
| A function component returning JSX | A struct that conforms to ``View``, with a `body` |
| Props | The struct's `let` properties. Swift writes the initialiser for you: `Greeting(name: "Ada")` |
| `children` | A `@ViewBuilder` closure property: see <doc:CustomViews> |
| `useState` | `@State private var count = 0`, changed by assigning to it |
| Passing `value` and `setValue` to a child | A `@Binding`, passed as `$value` |
| `useReducer`, or a store | An `@Observable` class with methods that change it |
| `createContext` and `useContext` | `.environment(object)` and `@Environment(Store.self)`, or an environment value of your own: see <doc:StateManagement> |
| `useEffect(fn, [dep])` | `.task(id: dep) { … }`, which runs async code, restarts when `dep` changes and is cancelled when the view goes away. Also `.onAppear`, `.onDisappear` and `.onChange(of:)` |
| `<Box flexDirection="column">`, `"row"` | ``VStack``, ``HStack`` |
| `gap`, `padding`, `borderStyle` | `spacing:`, `.padding()`, `.border()` |
| `flexGrow={1}` | ``Spacer``, or `.frame(maxWidth: .infinity)` |
| `<Text color="green" bold>` | `Text("…").foregroundStyle(.green).bold()` |
| `{items.map(item => <Row key={item.id} />)}` | `ForEach(items) { item in Row(item: item) }`, with items that are `Identifiable`, or `id: \.self` |
| `{cond && <X />}` | `if cond { X() }` |
| `useInput` | `.onKeyPress`, which hears keys only while the focus is on its view or inside it |
| `useFocus`, `useFocusManager` | Built in: Tab moves the focus between controls. `.focusable()` and ``FocusState`` for the rest |
| `useApp().exit()` | `dismiss()` from `@Environment(\.dismiss)` |
| `ink-text-input`, `ink-select-input`, `ink-spinner` | ``TextField``, ``Picker`` or ``List``, ``Spinner``, all built in |
| `ink-testing-library` | ``TestApp`` in the `TUITesting` product: see <doc:TestingYourApp> |
| `render(<App />)` | `@main struct MyApp: App` |

## What Will Surprise You

- **No rules of hooks.** Property wrappers such as `@State` are declared once, as properties of the struct, so there's no call order to keep, and they can't go inside an `if`. TUI keeps their storage outside the struct, so `body` never sees stale state.
- **Keys follow the focus.** Every active `useInput` hears every key. In TUI, keys go to the control with the focus, and an `.onKeyPress` runs only while the focus is on its view or inside it. A focused `List` takes the arrows and types to jump to a row, and a `TextField` takes letters. An `.onKeyPress` on a container is asked before the control inside it, so it can take a key back, as the `+` above does.
- **Layout isn't flexbox.** A container offers each child a size, the child picks its own, and the container places it. There's no `flexShrink` or `flexBasis`. Most views size themselves to their content: see <doc:LayoutSystem>.
- **The app takes the whole screen.** Ink draws inline, below your shell prompt, by default. TUI always uses the alternate screen and has nothing like `<Static>`, so it isn't the tool for a build log or a progress line in a command's output.
- **Control-C doesn't quit.** It copies the selection. Control-Q quits.
- **No Windows yet.** TUI apps run on macOS and Linux.

## What TUI Adds

- **Mouse support in every control.** Ink has no mouse support of its own. In TUI clicking, scrolling and dragging work without code of your own.
- **Scrolling.** ``ScrollView`` and ``List`` scroll whatever they hold and keep the focused row in view.
- **Controls with their keys built in**: text fields and editors, tables, outlines, tab views, menus, sheets, alerts and pickers, all taking part in the focus.
- **A native binary**, with no Node.js to install on the machine that runs it.
- **SwiftUI's interface.** What you learn carries over to SwiftUI apps for Apple's platforms. See <doc:ComingFromSwiftUI>.

## What Ink Does Better

- **It's React.** Components, hooks, JSX and the npm ecosystem carry over unchanged, and so does what your team already knows.
- **Inline output.** Ink draws in the normal scrollback, and `<Static>` keeps finished lines above a live area, which is what most command-line tools want.
- **A quicker edit-and-run loop.** Swift compiles before every run; Ink starts as soon as Node can load it.
