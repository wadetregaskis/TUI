# Product smoke test

One tiny app per library product of TUIkit (`Sources/Uses<Product>/main.swift`), each depending on that product
alone, importing its module and using one of its views or types. `verify-products.sh` stages the working tree as a
versioned package (`Tools/stage-versioned-package.sh`), builds every app against it as a client would, runs each,
and fails if the fixture's apps and the manifest's library products differ. CI runs it on the macOS swift.org 6.4
lane; the script's header says what it catches and what it costs.

```bash
Tools/ProductSmoke/verify-products.sh          # with $SWIFT, else swift
Tools/ProductSmoke/verify-products.sh --keep   # and keep the scratch directory
```

A new library product needs an app here: add `Sources/Uses<Product>/main.swift` and the product's name to
`Package.swift`'s `products`. The manifest reads TUIkit's URL from `TUIKIT_PRODUCT_SMOKE_URL`, which the script
sets, so the fixture is not meant to be opened on its own. It must never hold a dynamic product: Swift Build turns
the modules a dynamic product shares into dynamic libraries across the whole graph.
