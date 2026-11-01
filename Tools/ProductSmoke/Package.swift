// swift-tools-version: 6.2

// The product smoke test's fixture: one tiny app per library product of TUI, each depending on that product
// alone, importing its module (and what the docs say to import beside it) and using one of its views or types.
// TUI is resolved by VERSION from a staged copy of the tree under test, as a client resolves it;
// Tools/ProductSmoke/verify-products.sh stages it, sets TUI_PRODUCT_SMOKE_URL, builds every app and runs each.
// An app named `Uses<Product>` is the product's.
//
// No dynamic product here, ever: Swift Build turns modules shared with a dynamic product into dynamic libraries
// across the whole package graph, which would change what every app here links.

import PackageDescription

let url = Context.environment["TUI_PRODUCT_SMOKE_URL"] ?? "file:///run-Tools/ProductSmoke/verify-products.sh"

/// Every library product of TUI. verify-products.sh fails if this and the package's own list differ.
let products = [
    "TUI", "TUIApp", "TUIFoundation", "TUIBitmaps", "TUIChrome", "TUIColorPicker", "TUICommands",
    "TUICurveEditors", "TUIEffects", "TUIFilePanels", "TUIForms", "TUIGrid", "TUILists",
    "TUIMenus", "TUINavigation", "TUINumericControls", "TUIPickers", "TUIPresentation", "TUIScenes",
    "TUISearch",
    "TUITabImages", "TUIFilePanelImages", "TUITables", "TUITabs", "TUITesting", "TUITextInput", "TUICore", "TUIStyling", "TUIView", "TUIImage",
    "TUIEnvironmentDocs", "TUIAppKit", "TUIFilePanelsAppKit", "TUIMacros",
]

let package = Package(
    name: "TUIProductSmoke",
    platforms: [.macOS(.v15)],
    dependencies: [.package(url: url, exact: "1.0.0")],
    targets: products.map { product in
        .executableTarget(
            name: "Uses" + product,
            dependencies: [.product(name: product, package: "TUI")],
            // As strict as a client can be: a member is visible only in a file that imports its module.
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        )
    }
)
