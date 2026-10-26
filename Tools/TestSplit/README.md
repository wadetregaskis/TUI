# TestSplit

The scripts that divided the framework's suite into a test target per module
(the owner's request B-TC1-1, 2026-10-12), kept as the record of how each file
was placed. They ran once, on the four test targets by area (`TUITests`,
`TUICollectionTests`, `TUIControlTests`, `TUIAppTests`) and their
`TUITestSupport`, which they name; they are not a tool to re-run as they
stand. A new test file is placed by hand, by the rule in CONTRIBUTING.md, and
`Tools/validate-test-boundaries.sh` checks its imports.

1. **`analyze.py`** reads, for every test file, the library modules it needs and
   the helpers (declarations in other test files) it uses, from a debug build
   with `--build-tests`. Two sources, unioned:
   - the compiler's index store (`.build/<triple>/debug/index/store`, read by
     **`indexstore.py`** over Xcode's `libIndexStore.dylib`): every symbol a
     file references, a type named only in a signature and a call the
     optimiser inlines included, looked up among the declarations the index
     records for each library module's and test file's own sources;
   - each test file's object file's undefined symbols (`nm`), whose mangled
     names spell the modules involved: this catches a conformance used only
     implicitly, which the index records no occurrence of.
2. **`plan.py`** folds each helper's needs into its users', and assigns each
   file to the target of the highest module that leaves it needing:
   `TUIFoundationTests`, `TUIAppTests`, one feature module's, or
   `TUIIntegrationTests`; a file with no tests to the matching support
   target. Test files sharing a helper declared in one of them go together.
3. **`move.py`** `git mv`s each file, replaces its `import TUI` with the
   modules it needs (and any a module above them doesn't re-export), drops the
   imports of modules it doesn't need, wraps a file entering a support target
   in that target's guard, and writes the targets into `Package.swift`.

From the package root, after a debug build:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 Tools/TestSplit/analyze.py --out split.json
```

```bash
python3 Tools/TestSplit/plan.py split.json --out plan.json
```

```bash
python3 Tools/TestSplit/move.py plan.json split.json
```

The first run built clean, with the same 11,561 tests as before, by name.
An earlier version that read only the object files missed what the optimiser
had inlined and what was named only as a type, and fed the compiler's errors
back into the plan a build at a time; it did not converge, and the index store
replaced it.
