"""Tests for build.sh's options and where it puts things, with a stand-in for `swift`: no toolchain, no SDK, no build.

`python3 -m unittest discover -s Tools/Web -p 'test_*.py'`

The stand-in answers `sdk list`, makes a module and one resource bundle on `build`, and prints the bin path on
`--show-bin-path`, so what is checked is the script's own part: which site it picks, what it copies there, what it
removes, and that building another package leaves the copy of TUI it runs from as it found it. Each test runs the
script from a copy of `Tools/Web` in a temporary directory, so not even the real `Tools/Web/site/` is touched.
"""

import json
import os
import pathlib
import shutil
import stat
import subprocess
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
PAGE_FILES = ["index.html", "worker.js", "wasi.js", "isolation-sw.js"]

STUB = r"""#!/bin/bash
# Stands in for swift.org's `swift`: logs each call, and on `build` makes what SwiftPM would.
echo "$*" >> "$STUB_LOG"
[ "$1 $2" = "sdk list" ] && { echo swift-6.3.3-RELEASE_wasm; exit 0; }
[ "$1" = build ] || { echo "unexpected: $*" >&2; exit 3; }
shift
package=""; product=""; show=0
while [ $# -gt 0 ]; do
    case "$1" in
        --package-path) package="$2"; shift ;;
        --product) product="$2"; shift ;;
        --show-bin-path) show=1 ;;
    esac
    shift
done
bin="$package/.build/wasm32-unknown-wasip1/release"
[ "$show" = 1 ] && { echo "$bin"; exit 0; }
mkdir -p "$bin/${product}_${product}.resources"
echo "module $product" > "$bin/$product.wasm"
echo "strings" > "$bin/${product}_${product}.resources/strings.txt"
"""


def listing(directory):
    """Every file under `directory`, relative to it, with its contents."""
    return {
        str(path.relative_to(directory)): path.read_bytes()
        for path in sorted(directory.rglob("*")) if path.is_file()
    }


class BuildScriptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        base = pathlib.Path(self.temporary.name)
        # A copy of TUI, as much of it as build.sh reads.
        self.root = base / "TUI"
        web = self.root / "Tools" / "Web"
        (web / "site").mkdir(parents=True)
        for name in ["build.sh", "example_gallery.py", "glyph-probe.html"]:
            shutil.copy2(HERE / name, web / name)
        for name in PAGE_FILES:
            shutil.copy2(HERE / "site" / name, web / "site" / name)
        probes = self.root / "Tools" / "TerminalProbes" / "data"
        probes.mkdir(parents=True)
        (probes / "terminal.json").write_text("{}")
        # The Example's last build, which building an app must leave alone.
        (web / "site" / "Example.wasm").write_text("the Example")
        (web / "site" / "manifest.json").write_text(json.dumps({"wasm": "./Example.wasm"}))
        self.page = web / "site"
        self.app = base / "MyApp"
        self.app.mkdir()
        self.swift = base / "swift"
        self.swift.write_text(STUB)
        self.swift.chmod(self.swift.stat().st_mode | stat.S_IXUSR)
        self.log = base / "swift.log"

    def tearDown(self):
        self.temporary.cleanup()

    def build(self, *arguments):
        environment = {**os.environ, "TUI_WASM_SWIFT": str(self.swift), "STUB_LOG": str(self.log)}
        return subprocess.run(
            ["bash", str(self.root / "Tools" / "Web" / "build.sh"), "--no-opt", *arguments],
            env=environment, capture_output=True, text=True, timeout=60,
        )

    def assert_site(self, site, product):
        for name in PAGE_FILES:
            self.assertEqual((site / name).read_bytes(), (HERE / "site" / name).read_bytes(), name)
        self.assertEqual((site / f"{product}.wasm").read_text(), f"module {product}\n")
        manifest = json.loads((site / "manifest.json").read_text())
        self.assertEqual(manifest["wasm"], f"./{product}.wasm")
        self.assertEqual(manifest["argv0"], product)
        resource = f"{product}_{product}.resources/strings.txt"
        self.assertEqual([entry["url"] for entry in manifest["files"]], [f"./resources/{resource}"])
        self.assertTrue((site / "resources" / resource).is_file())

    def test_another_package_builds_into_its_own_build_directory_and_leaves_tui_alone(self):
        before = listing(self.root)
        result = self.build("--package-path", str(self.app), "--product", "MyApp")
        self.assertEqual(result.returncode, 0, result.stderr)
        site = self.app / ".build" / "web"
        self.assert_site(site, "MyApp")
        self.assertFalse((site / "probe-data").exists(), "the glyph probe is TUI's, not the app's")
        self.assertFalse((site / "glyph-probe.html").exists())
        self.assertEqual(listing(self.root), before, "nothing in TUI's checkout changed")
        self.assertIn(f"serve.py --site {site}", result.stdout)
        self.assertIn(f"--package-path {self.app}", self.log.read_text())

    def test_a_named_site_gets_the_build_and_the_page(self):
        site = pathlib.Path(self.temporary.name) / "public" / "play"
        result = self.build("--package-path", str(self.app), "--product", "MyApp", "--site", str(site))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_site(site, "MyApp")
        self.assertFalse((self.app / ".build" / "web").exists())

    def test_a_site_holding_something_else_is_refused_before_building(self):
        site = pathlib.Path(self.temporary.name) / "docs"
        site.mkdir()
        (site / "index.html").write_text("the app's own home page")
        result = self.build("--package-path", str(self.app), "--product", "MyApp", "--site", str(site))
        self.assertEqual(result.returncode, 2)
        self.assertIn("holds no earlier build", result.stderr)
        self.assertEqual((site / "index.html").read_text(), "the app's own home page")
        self.assertFalse(self.log.exists(), "swift never ran")

    def test_a_rebuild_elsewhere_removes_only_the_previous_build(self):
        site = pathlib.Path(self.temporary.name) / "play"
        # From a package of its own, whose build directory holds only its bundle.
        old = pathlib.Path(self.temporary.name) / "OldApp"
        old.mkdir()
        self.assertEqual(self.build("--package-path", str(old), "--product", "Old", "--site", str(site)).returncode, 0)
        (site / "other.wasm").write_text("someone else's")
        (site / "notes.txt").write_text("kept")
        result = self.build("--package-path", str(self.app), "--product", "MyApp", "--site", str(site))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_site(site, "MyApp")
        self.assertFalse((site / "Old.wasm").exists(), "the previous build's module goes")
        self.assertFalse((site / "resources" / "Old_Old.resources").exists(), "and its resources")
        self.assertEqual((site / "other.wasm").read_text(), "someone else's")
        self.assertEqual((site / "notes.txt").read_text(), "kept")

    def test_tuis_own_package_still_builds_into_tools_web_site(self):
        result = self.build("--product", "Demo")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_site(self.page, "Demo")
        self.assertFalse((self.page / "Example.wasm").exists(), "a stale module goes, as before")
        self.assertTrue((self.page / "probe-data" / "terminal.json").is_file())
        self.assertTrue((self.page / "glyph-probe.html").is_file())
        self.assertIn("serve it with: Tools/Web/serve.py\n", result.stdout)


if __name__ == "__main__":
    unittest.main()
