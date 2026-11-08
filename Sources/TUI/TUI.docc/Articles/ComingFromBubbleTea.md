# Coming from Bubble Tea

Map what you know from Bubble Tea, Lip Gloss and Bubbles onto TUI.

## Overview

Bubble Tea, the Go framework, uses the Elm architecture: one model holds all the state, `Update` turns each message into a new model, and `View` renders the model. TUI uses SwiftUI's architecture instead. The screen is still a function of the state, but the state is spread over the views that own it, and an event changes it directly, in the closure that handles the event. There is no `Update`, no message type and no loop to write.

If `@State`, `body` or modifiers are new to you, read <doc:NewToSwiftUI> first. The Go code on this page is for Bubble Tea v2 and Lip Gloss v2.

## The Same App in Both

A counter that `+` increases, and a list of three fruits with one selected. In Bubble Tea:

```go
package main

import (
	"fmt"
	"os"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

var hi = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#FF5FAF"))

type model struct {
	count, cursor int
	items         []string
}

func (m model) Init() tea.Cmd { return nil }

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if msg, ok := msg.(tea.KeyPressMsg); ok {
		switch msg.String() {
		case "+":
			m.count++
		case "up":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down":
			if m.cursor < len(m.items)-1 {
				m.cursor++
			}
		case "q", "ctrl+c":
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m model) View() tea.View {
	var b strings.Builder
	fmt.Fprintf(&b, "Count: %d\n\n", m.count)
	for i, it := range m.items {
		if i == m.cursor {
			b.WriteString(hi.Render("> "+it) + "\n")
		} else {
			b.WriteString("  " + it + "\n")
		}
	}
	fmt.Fprintf(&b, "\nSelected: %s\n", m.items[m.cursor])
	return tea.NewView(b.String())
}

func main() {
	p := tea.NewProgram(model{items: []string{"Apples", "Bananas", "Cherries"}})
	if _, err := p.Run(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
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

The `List` draws the rows, the cursor and the selection, scrolls when the rows don't fit, and takes clicks. The arrow keys move its cursor, and Space or Return selects the row under it. Control-Q quits, so there's no quit key to handle.

## Concepts

| Bubble Tea | TUI |
|---|---|
| The model struct | `@State` properties on the view that owns them, or an `@Observable` class for state that views share |
| `Init() tea.Cmd` | `.task { }` or `.onAppear { }` on a view |
| `Update(msg)` and its `switch` | The closure that handles the event: `Button("Add") { count += 1 }`, `.onKeyPress`, `.onChange(of:)` |
| `tea.KeyPressMsg` | `.onKeyPress("+")` on the view, or `.keyboardShortcut` on a button. The focus decides which view hears a key |
| `tea.WindowSizeMsg` | Layout does it for you. ``GeometryReader`` gives you the size when you need it |
| `tea.Cmd`, `tea.Tick` | `.task { … }`, which runs async code and is cancelled when the view goes away. ``TimelineView`` redraws on a schedule |
| `View()` building a string | `body` returning views. TUI works out the text, the colours and what changed |
| Lip Gloss `NewStyle().Bold(true).Foreground(…)` | Modifiers: `.bold().foregroundStyle(.pink)` |
| Lip Gloss `JoinVertical`, `JoinHorizontal`, `Padding`, `Width`, `Border` | ``VStack``, ``HStack``, `.padding()`, `.frame(width:)`, `.border()` |
| Bubbles `list`, `table`, `textinput`, `textarea`, `viewport`, `spinner`, `progress` | ``List``, ``Table``, ``TextField``, ``TextEditor``, ``ScrollView``, ``Spinner``, ``ProgressView`` |
| A child model, with the parent forwarding messages to it | A child view with its own `@State`. The parent passes a `@Binding` or an `@Observable` object, and forwards nothing |
| Huh forms | ``Form`` with ``TextField``, ``Picker`` and ``Toggle`` |
| `tea.Quit` | Control-Q, or `dismiss()` from `@Environment(\.dismiss)` in your code |
| teatest | ``TestApp`` in the `TUITesting` product: see <doc:TestingYourApp> |

## What Will Surprise You

- **Nothing calls you in a loop.** TUI reads the keys, calls the closures, and draws again when state that a `body` read has changed. You never ask for a redraw.
- **State lives on views.** A plain `var` in a view struct starts again every time the view is rebuilt, which is often. Keep values in `@State`, or in an `@Observable` class held by `@State` higher up.
- **Keys go to the focused control first.** A `List` with the focus takes the arrows and types to jump to a row, and a ``TextField`` takes letters. An `.onKeyPress` on a container is asked before the control inside it, so it can take a key back, as the `+` above does. Tab moves the focus, and <doc:FocusSystem> has the rules.
- **Control-C doesn't quit.** It copies the selection, as it does in a GUI. Control-Q quits.
- **The app takes the whole screen.** TUI always draws on the alternate screen and puts the terminal back when it quits. It has no inline mode like Bubble Tea's default, so it isn't the tool for a progress line in a command's output.
- **Sizes are cells, and you rarely give them.** Stacks size themselves from their content. Use `.frame` only when you want a fixed width.
- **No Windows yet.** TUI apps run on macOS and Linux. Bubble Tea runs on Windows too.

## What TUI Adds

- **A focus system.** Every control joins the Tab order by itself, the focused one is drawn as focused, and ``FocusState`` moves the focus from code. In Bubble Tea you track which component is focused and forward keys to it yourself.
- **Mouse support in every control.** Clicks, scrolling and dragging work without code of your own.
- **Layout.** Stacks, grids, frames, alignment and scrolling containers size and place the views, and recompute when the terminal is resized.
- **More built-in controls.** Tables with sortable columns, outlines, tab views, menus, sheets, alerts, date and colour pickers, and navigation.
- **SwiftUI's interface.** What you learn carries over to SwiftUI apps for Apple's platforms, and much SwiftUI code compiles here unchanged. See <doc:ComingFromSwiftUI>.
- **Tests that drive the app.** ``TestApp`` presses keys, clicks and reads the screen in a unit test, with no terminal. See <doc:TestingYourApp>.

## What Bubble Tea Does Better

- **Every change is a message.** All input, timers and results arrive at one `Update`, so you can log, replay and unit-test the app's behaviour as plain state transitions, and side effects are explicit `tea.Cmd` values. In TUI a change happens in whichever closure handles the event, which is less code but harder to trace.
- **Inline output.** A Bubble Tea program can draw a few lines in the middle of a shell session and leave them in the scrollback.
- **Serving over SSH.** Wish serves a Bubble Tea app to anyone who connects with `ssh`, one program per session. TUI has no equivalent.
- **Windows.** Bubble Tea runs on Windows; TUI apps don't yet.
