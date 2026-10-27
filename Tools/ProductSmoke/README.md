# Product smoke test

One tiny app per library product of TUI (`Sources/Uses<Product>/main.swift`), each depending on that product
alone, importing its module (and what the docs say to import beside it) and using one of its views or types.
`verify-products.sh` stages the working tree as a versioned package (`Tools/stage-versioned-package.sh`), builds
every app against it as a client would, runs each, and fails if the fixture's apps and the manifest's library
products differ. CI runs it on the macOS swift.org 6.4
lane; the script's header says what it catches and what it costs.

```bash
Tools/ProductSmoke/verify-products.sh          # with $SWIFT, else swift
Tools/ProductSmoke/verify-products.sh --keep   # and keep the scratch directory
```

`test_verify_products.py` tests the script's product list check with a stand-in for `swift`
(`python3 -m unittest discover -s Tools/ProductSmoke -p 'test_*.py'`; no build).

A new library product needs an app here: add `Sources/Uses<Product>/main.swift` and the product's name to
`Package.swift`'s `products`. The manifest reads TUI's URL from `TUI_PRODUCT_SMOKE_URL`, which the script
sets, so the fixture is not meant to be opened on its own. It must never hold a dynamic product: Swift Build turns
the modules a dynamic product shares into dynamic libraries across the whole graph.
