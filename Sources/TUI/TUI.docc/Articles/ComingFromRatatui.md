# Coming from Ratatui

Map what you know from Ratatui onto TUI.

## Overview

Ratatui, the Rust library, draws in immediate mode: your loop draws every widget into a frame, reads an event, updates your app's fields and draws again. TUI keeps the idea that the screen is a function of your state, but owns the loop. You describe the screen in a view's `body`, and TUI calls it again when the state it read changes, draws only what changed, and routes each key to the control with the focus.

If `@State`, `body` or modifiers are new to you, read <doc:NewToSwiftUI> first. The Rust code on this page is for Ratatui 0.30.

## The Same App in Both

A counter that `+` increases, and a list of three fruits with one selected. In Ratatui:

```rust
use ratatui::crossterm::event::{self, Event, KeyCode, KeyEventKind};
use ratatui::layout::{Constraint, Layout};
use ratatui::style::{Style, Stylize};
use ratatui::widgets::{Block, List, ListState, Paragraph};
use ratatui::{DefaultTerminal, Frame};

const ITEMS: [&str; 3] = ["Apples", "Bananas", "Cherries"];

struct App { count: u32, list: ListState }

fn main() -> std::io::Result<()> {
    let mut app = App { count: 0, list: ListState::default().with_selected(Some(0)) };
    ratatui::run(|terminal| app.run(terminal))
}

impl App {
    fn run(&mut self, terminal: &mut DefaultTerminal) -> std::io::Result<()> {
        loop {
            terminal.draw(|frame| self.render(frame))?;
            if let Event::Key(key) = event::read()? {
                if key.kind != KeyEventKind::Press { continue; }
                match key.code {
                    KeyCode::Char('+') => self.count += 1,
                    KeyCode::Up => self.list.select_previous(),
                    KeyCode::Down => self.list.select_next(),
                    KeyCode::Char('q') => return Ok(()),
                    _ => {}
                }
            }
        }
    }

    fn render(&mut self, frame: &mut Frame) {
        let [top, mid, bottom] = Layout::vertical([
            Constraint::Length(1), Constraint::Fill(1), Constraint::Length(1),
        ]).areas(frame.area());
        frame.render_widget(Paragraph::new(format!("Count: {}", self.count)), top);
        let list = List::new(ITEMS)
            .block(Block::bordered())
            .highlight_style(Style::new().reversed())
            .highlight_symbol("> ");
        frame.render_stateful_widget(list, mid, &mut self.list);
        let i = self.list.selected().unwrap_or(0).min(ITEMS.len() - 1);
        frame.render_widget(Paragraph::new(format!("Selected: {}", ITEMS[i])), bottom);
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

There's no loop, no terminal set-up or restore, and no `ListState`: the `List` keeps its cursor and scroll position, and writes the selection to `selection`. Its rows have a border by default, and the list fills the height the two lines of text leave it, as `Fill(1)` does. The arrow keys move its cursor, and Space or Return selects the row under it. Control-Q quits.

## Concepts

| Ratatui | TUI |
|---|---|
| `loop { terminal.draw(…); event::read() }` | Nothing: TUI runs the loop. `@main struct MyApp: App` is the whole entry point |
| `ratatui::init()` and `restore()` | Done for you, including after a crash or Control-Z |
| Your `App` struct's fields | `@State` on the view that owns each value, or an `@Observable` class for shared state |
| `fn ui(frame, app)` drawing everything | `body`, which TUI calls when state it read has changed. It redraws only the cells that changed |
| `Layout::vertical([...])` | ``VStack``, ``HStack`` and ``Grid`` |
| `Constraint::Length(n)` | `.frame(height: n)` or `.frame(width: n)` |
| `Constraint::Min`, `Fill` | A view that grows, such as a `List`, or `.frame(maxWidth: .infinity)`. ``Spacer`` fills the rest |
| `Constraint::Percentage`, `Ratio` | `.containerRelativeFrame(_:count:span:spacing:alignment:)`, or ``GeometryReader`` |
| `Block::bordered().title("Fruit")` | `.border()`, or a titled ``Panel``: `Panel("Fruit") { … }` |
| `Paragraph`, `Line`, `Span`, `Style` | ``Text``, with modifiers such as `.bold()` and `.foregroundStyle(.red)`. A styled `Text` interpolated into another keeps its style: `Text("Count: \(Text("3").bold())")` |
| `List` with `ListState`, `Table` with `TableState` | ``List`` and ``Table`` with a `selection:` binding. They keep their own cursor and scroll position |
| `Tabs`, `Gauge`, `LineGauge`, `Scrollbar` | ``TabView``, ``Gauge``, ``ProgressView``, and the scroll bars ``ScrollView`` and ``List`` draw |
| `Canvas`, `Chart`, `BarChart`, `Sparkline` | ``Canvas`` for drawing. TUI has no chart widgets |
| Matching `KeyCode`s and passing keys to the widget you treat as focused | The focused control gets the keys by itself. `.onKeyPress` and `.keyboardShortcut` add your own |
| A `Widget` or `StatefulWidget` of your own | A ``View`` composed from others, or for drawing cells yourself, a view that's ``Renderable``: see <doc:CustomViews> |
| `tui-input`, `tui-textarea` | ``TextField`` and ``TextEditor``, built in |
| `TestBackend` | ``TestApp`` in the `TUITesting` product, which also presses keys and clicks: see <doc:TestingYourApp> |

## What Will Surprise You

- **You don't own the frame.** TUI decides when to call `body`, and may call it more often than you expect, or not at all when nothing it read has changed. Keep `body` quick and free of side effects, and start work from `.task` instead.
- **State must be marked.** A plain `var` in a view struct starts again every time the view is rebuilt. Keep values in `@State`.
- **Layout is a negotiation, not constraints.** A container offers each child a size, the child picks its own, and the container places it. Most views size themselves to their content, so you give sizes far less often than with `Constraint`. See <doc:LayoutSystem>.
- **Keys go to the focused control first.** A `List` with the focus takes the arrows and types to jump to a row. An `.onKeyPress` on a container is asked before the control inside it, so it can take a key back, as the `+` above does.
- **Control-C doesn't quit.** It copies the selection. Control-Q quits.
- **No inline viewport.** TUI always takes the whole screen, on the alternate screen. It has nothing like `Viewport::Inline`.
- **No Windows yet.** TUI apps run on macOS and Linux. Ratatui runs on Windows through crossterm.

## What TUI Adds

- **Focus.** Every control joins the Tab order by itself, the focused one is drawn as focused, and ``FocusState`` moves the focus from code. Ratatui leaves input to you.
- **Mouse support in every control.** Clicking, scrolling and dragging work without code of your own.
- **Interactive controls.** Text fields and editors, buttons, toggles, pickers, sliders, menus, sheets, alerts and navigation, each with its keys and its look.
- **Scrolling.** ``ScrollView`` and ``List`` scroll whatever they hold, keep the focused row in view, and draw a scroll bar.
- **SwiftUI's interface.** What you learn carries over to SwiftUI apps for Apple's platforms. See <doc:ComingFromSwiftUI>.
- **Theming, animation and localisation**, which reach every view below where you set them.

## What Ratatui Does Better

- **Total control.** You own the loop, every cell of every frame and the async runtime, with no framework state hidden from you. Ratatui fits into almost any program, and since 0.30 even into `no_std` targets.
- **Constraint layout.** Ratatui's constraint solver lays out dashboards with percentages and ratios directly.
- **Charts.** `Chart`, `BarChart` and `Sparkline` are built in. In TUI you'd draw them with ``Canvas``.
- **Inline viewports and Windows**, neither of which TUI has yet.
