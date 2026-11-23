# Text Input and Forms

Ask for text, lay out a form, check what people type, and move the keyboard from field to field.

## Overview

You'll start with one text field, then build it up into a small sign-up form that checks its answers before it lets you continue.

```swift
struct Greeting: View {
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading) {
            TextField("Your name", text: $name)
            Text("Hello, \(name)!")
        }
    }
}
```

The first control on a screen takes the keyboard by itself, so you can type straight away. The field updates `name` with every key press. While it's empty, it shows its title as a hint.

While a field has the keyboard, it takes every letter you type. Control-Q still quits. Press Tab to move to the next control, and Shift-Tab to move back. A click works too.

## Text fields

To show a hint that's different from the title, give the field a prompt:

```swift
TextField("Email", text: $email, prompt: Text("you@example.com"))
```

For a value that isn't text, such as a number, give the field a value and a format. It writes the value back when you press Return or leave the field. If what you typed can't be read as a value, the field goes back to the last good one.

```swift
TextField("Quantity", value: $quantity, format: .number)
```

To let a field grow as its text wraps, make it vertical. Return still submits it. Control-O adds a new line, as does Option-Return where the terminal sends Option.

```swift
TextField("Notes", text: $notes, axis: .vertical)
    .lineLimit(2...5)       // two rows to start, five at most
```

The usual editing keys work: the arrows, Home and End, Shift with an arrow to select, Control-V to paste, and Control-Z to undo. Control-U erases the field. ``TextField`` lists them all.

A field you're typing in also takes text dragged onto it from a `draggable(_:)` view: the text goes in where you let go, as a copy, selected, and Control-Z takes it back out. As in SwiftUI, a field you aren't typing in takes no drop. A ``TextEditor`` takes one whether you're typing in it or not, and leaves the focus where it was. A drag carried from the keyboard (<doc:DragAndDrop>) goes in at the caret.

## Doing something on Return

Add `onSubmit` to run code when someone presses Return in a field:

```swift
TextField("Add an item", text: $newItem)
    .onSubmit { addItem() }
```

Written on a view that contains several fields, it runs for Return in any of them:

```swift
VStack {
    TextField("Name", text: $name)
    TextField("Email", text: $email)
}
.onSubmit { save() }
```

A field with no `onSubmit` lets Return carry on to a button marked `.keyboardShortcut(.defaultAction)`. That's what you want in a dialog.

## Passwords

A ``SecureField`` works like a text field, but draws `●` in place of each character. You can paste into one, and you can't copy or cut from it.

```swift
SecureField("Password", text: $password)
```

## Several lines of text

A ``TextEditor`` is for longer text. It takes up the space you give it, wraps long lines, and scrolls by itself; in a vertical ``ScrollView``, which gives it no height, it is as tall as its text and the scroll view scrolls it, keeping the caret in sight. Return starts a new line, and Tab moves to the next control.

```swift
TextEditor(text: $notes)
    .frame(height: 6)
```

Since Return starts a new line there, a ``TextEditor`` doesn't take part in `onSubmit`.

### Marking ranges of the text

A ``TextEditorMark`` is a range of an editor's text drawn in attributes of its own: a parse error's curly underline, a diagnostic, a search result. ``View/textEditorMarks(_:in:)`` gives marks to the editors in a view, with the text their ranges were found in. They are drawn over the text and never written into it, so the bound value stays as the person typed it.

```swift
struct ConfigEditor: View {
    @State private var source = ""

    var body: some View {
        TextEditor(text: $source)
            .textEditorMarks(problems(in: source).map { range in
                var error = AttributeContainer()
                error.underlineStyle = Text.LineStyle(pattern: .curly, color: .red)
                return TextEditorMark(range, attributes: error)
            }, in: source)
    }
}
```

The text you state the marks with may be a few keys behind the editor's, as it is when a parse runs on a task of its own and finishes after more has been typed. The editor carries the marks through its own edits since: text typed before a mark moves it, text typed inside it grows it, text typed at either of its ends stays outside it, and a mark whose text was deleted goes. Marks of a text the editor doesn't know, such as one from before an undo, aren't drawn until you state them again. Marks are drawn over any attributes and highlighting the text has, and under the selection and the find bar's matches; of two that overlap, the later is drawn on top. For an editor over an `AttributedString`, the ranges are of its characters as a `String`, `String(value.characters)`. SwiftUI has no marks; they are TUI's own.

Highlighting a language's syntax, from tree-sitter or a language server, comes through a seam that is SPI for now: `@_spi(TextEditorHighlighting) import TUITextInput`. It is documented in its doc comments, and may change in any release until it is made public.

An editor over an `AttributedString` that is a stored property of an `@Observable` model pays for a comparison on every key. The macro's setter compares the new value with the old with `==`, to notify no one of an equal write, and `AttributedString`'s `==` reads them a character at a time up to the edit. In a long document that is most of a key's time: 98.7% of it, typing into a 3.2 MB one. The attributed `TextEditor(text:selection:)` shows how a model can write that one property's accessors itself, without the comparison.

## Building a form

A ``Form`` lines its rows up for you. A ``LabeledContent`` gives a control a label in the form's left-hand column, or shows a label and a fixed value. A ``Section`` groups rows under a heading.

```swift
struct SignUp: View {
    @State private var name = ""
    @State private var password = ""
    @State private var wantsNews = true

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Name") {
                    TextField("", text: $name)
                }
                LabeledContent("Password") {
                    SecureField("", text: $password)
                }
                LabeledContent("Plan", value: "Free")
            }
            Section("Options") {
                Toggle("Send me news", isOn: $wantsNews)
                Button("Create account") {}
            }
        }
    }
}
```

That draws this:

```
 Account
    Name ▐                                     ▌
Password ▐                                     ▌
    Plan Free

 Options
         ■ Send me news
         ▐ Create account ▌
```

The fields have an empty title because the `LabeledContent` names them. A toggle and a button carry their own labels, so they don't need one. A `TextField`, `SecureField`, `Picker`, `Slider`, `Stepper` or `DatePicker` written directly in a form puts its own title in the label column, so `TextField("Name", text: $name)` draws the same row as the `LabeledContent` above. As in SwiftUI, a field's title is then not also its hint: only a prompt shows in the empty field.

For the look of a grouped settings screen, with a border around each section, add `.formStyle(.grouped)`. A grouped form is a scroll view, as SwiftUI's is: it fills the space it's given, and when its sections are taller than that, the wheel and Page Up and Page Down scroll it, and Tab scrolls the control it moves to into view. In a vertical `ScrollView` a grouped form is as tall as its sections instead, and the scroll view around it scrolls it. The default columns form doesn't scroll, as SwiftUI's doesn't, so put a tall one in a `ScrollView`.

## Checking what people type

There's nothing special to learn here. Work out whether the input is good from your state, and use the answer in the view:

```swift
struct SignUp: View {
    @State private var name = ""
    @State private var password = ""

    private var nameIsValid: Bool { name.count >= 2 }
    private var passwordIsValid: Bool { password.count >= 8 }

    var body: some View {
        Form {
            LabeledContent("Name") {
                TextField("", text: $name)
            }
            if !name.isEmpty && !nameIsValid {
                Text("A name needs at least two letters.")
                    .foregroundStyle(.palette.error)
            }
            LabeledContent("Password") {
                SecureField("", text: $password)
            }
            Button("Create account") { createAccount() }
                .disabled(!nameIsValid || !passwordIsValid)
        }
    }

    private func createAccount() {}
}
```

The message appears as soon as there's something to complain about, and goes when it's fixed. A disabled button can't be clicked, and Tab passes over it.

To stop some characters from going in at all, clean up the value as it changes:

```swift
TextField("Zip code", text: $zip)
    .onChange(of: zip) { _, new in
        zip = String(new.filter(\.isNumber).prefix(5))
    }
```

## Moving the keyboard with @FocusState

``FocusState`` lets your code read and set which control has the keyboard. Make a type that names your fields, and attach each field to it with `focused(_:equals:)`. Setting the state moves the keyboard there.

This form starts in the name field, moves on when you press Return, and takes you back to whatever is wrong when you try to continue:

```swift
struct SignUp: View {
    enum Field: Hashable {
        case name, password
    }

    @State private var name = ""
    @State private var password = ""
    @State private var problem = ""
    @FocusState private var focus: Field?

    var body: some View {
        Form {
            LabeledContent("Name") {
                TextField("", text: $name)
                    .focused($focus, equals: .name)
            }
            LabeledContent("Password") {
                SecureField("", text: $password)
                    .focused($focus, equals: .password)
            }
            Button("Create account", action: submit)
            Text(problem).foregroundStyle(.palette.error)
        }
        .onSubmit {
            if focus == .name { focus = .password } else { submit() }
        }
        .defaultFocus($focus, .name)
    }

    private func submit() {
        if name.isEmpty {
            problem = "Please enter your name."
            focus = .name
        } else if password.count < 8 {
            problem = "Passwords need at least 8 characters."
            focus = .password
        } else {
            problem = ""
        }
    }
}
```

A single field can use a `Bool` instead: `@FocusState private var isEditing: Bool` and `.focused($isEditing)`.

Something always has the keyboard in a terminal app, so a screen needs no `.defaultFocus` unless you want it to start somewhere other than the first control. <doc:FocusSystem> goes further.

## Advanced

**Field styles.** ``View/textFieldStyle(_:)`` changes how the fields in a view are drawn: `.plain`, `.roundedBorder` or `.squareBorder`.

**Suggestions.** ``View/textInputSuggestions(_:)`` adds a menu of values, while still allowing free text. It opens when you press Down.

```swift
TextField("City", text: $city)
    .textInputSuggestions {
        ForEach(cities, id: \.self) { Text($0) }
    }
```

**Stopping `onSubmit` at a field.** Inside a form that saves on Return, `.submitScope()` on one field keeps its Return from reaching the form's `onSubmit`.

**The selection.** `TextField(_:text:selection:)` and `TextEditor(text:selection:)` take a binding to the selected text, which your code can read and set. `onEditingChanged(_:)` on a field tells you when editing starts and stops.

**Changing the text under a selection.** When your code changes the text a field or an editor is bound to, the selection moves through the change as an `NSTextView`'s does: text added or removed before it shifts it, a change after it leaves it, and a change that touches it leaves a caret at the end of the text put in. So a log you append lines to keeps the user's selection, lines put in above it carry it down, and a document loaded in place of another leaves a caret at its end. The change is found by comparing the old text with the new from both ends, so a new text that starts or ends like the old one is taken as an edit of the middle. If you set the selection in the same update, yours is used. This keeps more of the selection than SwiftUI does: its `TextEditor(text:)` puts the caret at the end on any change, and with a `selection:` binding it keeps the selection's numbers, which traps if they no longer fit (a deliberate deviation, by the owner's ruling of 2026-11-22).

## See Also

- <doc:KeyboardShortcuts>
- <doc:FocusSystem>
- <doc:Presentation>
