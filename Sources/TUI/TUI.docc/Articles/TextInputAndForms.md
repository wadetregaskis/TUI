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

A ``TextEditor`` is for longer text. It takes up the space you give it, wraps long lines, and scrolls by itself. Return starts a new line, and Tab moves to the next control.

```swift
TextEditor(text: $notes)
    .frame(height: 6)
```

Since Return starts a new line there, a ``TextEditor`` doesn't take part in `onSubmit`.

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

The fields have an empty title because the `LabeledContent` names them. A toggle and a button carry their own labels, so they don't need one. A `Picker`, `Slider`, `Stepper` or `DatePicker` written directly in a form puts its own title in the label column.

For the look of a grouped settings screen, with a border around each section, add `.formStyle(.grouped)`.

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

## See Also

- <doc:KeyboardShortcuts>
- <doc:FocusSystem>
- <doc:Presentation>
