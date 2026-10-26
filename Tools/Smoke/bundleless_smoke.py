#!/usr/bin/env python3
"""Does a TUI program run without its resource bundle — and in English?

A terminal program is often shipped as one file: copied out of `.build`, put in
a release archive, installed by a formula. TUI's translations and VERSION
are in a SwiftPM resource bundle beside the executable
(`TUI_TUIStrings.bundle`, `.resources` off Apple platforms), and SwiftPM's
generated `Bundle.module` stops the program (`fatalError`) where it finds none —
which, until TUI looked for the bundle itself, was every such program, at
launch. Unit tests cannot see this: a test runs beside its build's bundle.

So this copies Stress out of the build directory, and runs one headless session
(`--session settings --steps 2 --show`, which draws TUI's own status bar)
three ways, each under `LANGUAGE=de` and a fresh config directory:

  1. ALONE in a directory — it must exit 0 and draw TUI's words in ENGLISH:
     the German is in the bundle, and the English is compiled in;
  2. with the bundle copied BESIDE it, as an installer would — in GERMAN;
  3. through a symbolic link to (2) from another directory, as a formula links
     a program into `bin` — in GERMAN.

Runs 2 and 3 are the controls: without them a lookup that never found any
bundle would pass run 1. Run 1 asks for German so that it can tell NO bundle
from the bundle still in the build directory: SwiftPM's native build compiles
that directory's absolute path into the program, so an accessor that still read
it would draw German here — on the machine that built it, and on no other.

POSIX only, like the rest of `ci-pty-smoke.sh`; no PTY and no pyte. About a
second a run.

Usage:  bundleless_smoke.py [build-dir]     (default .build/debug)
Exit 0 if all three held, 1 otherwise.
"""
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
TRANSLATIONS = os.path.join(REPO, "Sources", "TUIStrings", "Localization", "translations")
SESSION = ["--session", "settings", "--steps", "2", "--show"]
KEY = "statusbar.quit"


def word(language):
    """TUI's word for KEY in `language`, from the source tree's table."""
    with open(os.path.join(TRANSLATIONS, f"{language}.json"), encoding="utf-8") as handle:
        return json.load(handle)[KEY]


def run(binary, scratch, name):
    """One run of the session; returns (problem or None, output)."""
    config = os.path.join(scratch, f"config-{name}")
    env = {k: v for k, v in os.environ.items() if k not in ("LANG", "LC_ALL", "LC_MESSAGES")}
    env.update({"LANGUAGE": "de", "TUIKIT_CONFIG_DIR": config, "TERM": "xterm-256color"})
    try:
        result = subprocess.run([binary, *SESSION], env=env, capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return "did not finish in 120 s", ""
    output = result.stdout + result.stderr
    if result.returncode < 0:
        return f"stopped by signal {-result.returncode}", output
    if result.returncode != 0:
        return f"exited {result.returncode}", output
    return None, output


def says(output, text):
    return re.search(rf"(?<!\w){re.escape(text)}(?!\w)", output) is not None


def main():
    build_dir = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, ".build", "debug"))
    binary = os.path.join(build_dir, "Stress")
    bundles = sorted(glob.glob(os.path.join(build_dir, "TUI_TUIStrings.*")))
    if not os.path.isfile(binary) or not bundles:
        print(f"error: {build_dir} has no Stress, or no TUI_TUIStrings bundle beside it", file=sys.stderr)
        return 1
    english, german = word("en"), word("de")
    failures = []
    with tempfile.TemporaryDirectory(prefix="tuikit-bundleless-") as scratch:
        bare = os.path.join(scratch, "bare")
        installed = os.path.join(scratch, "installed")
        linked = os.path.join(scratch, "linked")
        for directory in (bare, installed, linked):
            os.makedirs(directory)
        shutil.copy2(binary, bare)
        shutil.copy2(binary, installed)
        shutil.copytree(bundles[0], os.path.join(installed, os.path.basename(bundles[0])))
        os.symlink(os.path.join(installed, "Stress"), os.path.join(linked, "Stress"))

        cases = [
            ("alone", os.path.join(bare, "Stress"), english, german),
            ("beside its bundle", os.path.join(installed, "Stress"), german, english),
            ("linked to beside its bundle", os.path.join(linked, "Stress"), german, english),
        ]
        for name, path, wanted, unwanted in cases:
            problem, output = run(path, scratch, name.replace(" ", "-"))
            if problem is None and KEY in output:
                problem = f"drew the key {KEY!r} — no English compiled in?"
            elif problem is None and not says(output, wanted):
                problem = f"did not draw {wanted!r}"
            elif problem is None and says(output, unwanted):
                problem = f"drew {unwanted!r}, the wrong language"
            print(f"  {'FAIL' if problem else 'ok  '} {name}: " + (problem or f"drew {wanted!r}"))
            if problem:
                failures.append(name)
                for line in output.strip().splitlines()[-12:]:
                    print(f"      {line}")
    if failures:
        print(f"bundleless smoke: {len(failures)} of {len(cases)} FAILED")
        return 1
    print("bundleless smoke: Stress runs without its resource bundle, in English, and finds one beside it")
    return 0


if __name__ == "__main__":
    sys.exit(main())
