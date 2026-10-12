# Which Module Provides It

Find the module, and the library product, that each public name of TUIkit comes from.

## Overview

An app that depends on the `TUIkit` product never needs this page: `import TUIkit` is the whole framework. An app or
a library that depends on per-module products instead (<doc:ChoosingProducts>) gets only the modules of the products
it lists, and a name from any other module is an error that names no module:

```
error: cannot find 'Table' in scope
error: value of type 'Text' has no member 'tableStyle'
```

Look the name up below: add the **Product** to your target's `dependencies:` and `import` the module of the same
name. A product brings the modules its module is built on with it, and from `TUIkitFoundation` up its module
re-exports them, so one import covers them: `TUIkitTables` gives you `List` too. `TUIkitCore`, `TUIkitStyling`,
`TUIkitView` and `TUIkitImage` re-export nothing: beside `TUIkitView` or `TUIkitImage`, import the module of each
lower name you use, which their products bring (<doc:ChoosingProducts>).

**Name** is how you would find it in the reference: a type, protocol, function or macro by itself, and a member
another module adds to a type (most often a modifier on `View`) after the type's name, as in `View.tableStyle(_:)`.
Members a module declares on its own concrete types are not listed; look up the type. Overloads share a row.
**Module** is the module that declares the name, which is also what `String(reflecting:)` and the debugger show
for a type (`TUIkitTables.Table<…>`). **Product** is the library product to depend on; for TUIkitStrings and
TUIkitTerminalHost, which have no product of their own, that is TUIkitFoundation, which re-exports both.

## The index

This copy of the page has no index. The index is generated from the symbol graphs when the documentation is built
with `Tools/BuildDocs/build-docs.sh`, which writes it here; `Tools/BuildDocs/build-docs.sh --preview` serves the
built pages. The Swift Package Index documents each module as an archive of its own, so a symbol's page there sits
under its module.
