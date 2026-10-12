"""Tests for verify-products.sh's product list check, with a stand-in for `swift`: no toolchain, no build.

`python3 -m unittest discover -s Tools/ProductSmoke -p 'test_*.py'`
"""

import json
import os
import pathlib
import stat
import subprocess
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
SCRIPT = HERE / "verify-products.sh"
APPS = sorted(path.name.removeprefix("Uses") for path in (HERE / "Sources").iterdir() if path.name.startswith("Uses"))


class ProductListTests(unittest.TestCase):
    def run_script(self, products):
        """Runs the script with a `swift` whose `package describe` declares these library products."""
        with tempfile.TemporaryDirectory() as directory:
            swift = pathlib.Path(directory) / "swift"
            describe = {"products": [{"name": name, "type": {"library": ["automatic"]}} for name in products]}
            swift.write_text(
                "#!/bin/sh\n"
                '[ "$1 $2" = "package describe" ] || { echo "unexpected: $*" >&2; exit 3; }\n'
                f"cat <<'JSON'\n{json.dumps(describe)}\nJSON\n"
            )
            swift.chmod(swift.stat().st_mode | stat.S_IXUSR)
            return subprocess.run(
                ["bash", str(SCRIPT)], env={**os.environ, "SWIFT": str(swift)}, capture_output=True, text=True,
                timeout=60,
            )

    def test_a_product_without_an_app_fails_and_says_what_to_add(self):
        result = self.run_script(APPS + ["TUIkitBogus"])
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("product without an app: TUIkitBogus", result.stderr)
        self.assertIn("Give each product an app, Tools/ProductSmoke/Sources/Uses<Product>/main.swift", result.stderr)

    def test_an_app_without_a_product_fails_and_names_it(self):
        result = self.run_script([app for app in APPS if app != "TUIkitGrid"])
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("app without a product: TUIkitGrid", result.stderr)
        self.assertIn("Give each product an app", result.stderr)


if __name__ == "__main__":
    unittest.main()
