#!/usr/bin/env python3
"""Check that .spi.yml has Swift Package Index document every library module.

Swift Package Index (SPI) does not run build-docs.sh. It runs
`swift package generate-documentation` once per target that `.spi.yml`'s
`documentation_targets` names, and serves each archive behind a selector, the
first as the landing page. Since module split step B1 the `TUIkit` umbrella
declares nothing: an archive of it alone holds the catalog's articles and not
one symbol, so a list that names only the umbrella publishes an empty API
reference, at the URL the project template links to
(/documentation/tuikit). Each module of the API is reached only through its
own archive.

So: every module in unify_symbol_graphs.py's MODULES (the modules this
directory's unified build documents) must be listed, and the umbrella must come
first, so that the landing page, and with it the template's link, stays where
it was. A module carved out of TUIkitFoundation joins MODULES when it is carved,
and this check then asks for it in .spi.yml as well.

Reads the flow-style list (`documentation_targets: [A, B]`) only, which is
what .spi.yml uses; another spelling is reported, not guessed at.

Usage: check_spi_targets.py [path to .spi.yml]   (default: the repository's)
Exit status: 0 if every list passes, 1 otherwise.
"""

import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from unify_symbol_graphs import MODULES, UMBRELLA  # noqa: E402

KEY = re.compile(r"^[ \t]*(?:-[ \t]*)?documentation_targets[ \t]*:(.*)$", re.MULTILINE)
FLOW = re.compile(r"[ \t]*\[([^\]]*)\]")


def uncommented(text: str) -> str:
    """The text with each `#` comment removed (none of .spi.yml's values hold a `#`)."""
    return "\n".join(line.split("#", 1)[0] for line in text.splitlines())


def problems(text: str) -> list[str]:
    body = uncommented(text)
    found = []
    out = []
    for match in KEY.finditer(body):
        flow = FLOW.match(body, match.start(1))
        if not flow:
            out.append("a documentation_targets list is not in flow style ([A, B]), which this check reads")
            continue
        found.append([name.strip().strip("'\"") for name in flow.group(1).split(",") if name.strip()])
    if not found and not out:
        out.append("no documentation_targets list: Swift Package Index would document no module")
    for targets in found:
        missing = sorted(MODULES - set(targets))
        if missing:
            out.append(
                "documentation_targets lacks " + ", ".join(missing)
                + ": Swift Package Index documents each listed target on its own, and the"
                " umbrella's archive has no API of its own, so an unlisted module's API is"
                " missing from the published reference")
        if targets and targets[0] != UMBRELLA:
            out.append(
                f"documentation_targets starts with {targets[0]}, not {UMBRELLA}: the first target"
                f" is the landing page, and /documentation/{UMBRELLA.lower()} is the link the"
                " project template writes")
    return out


def main(path: pathlib.Path) -> int:
    found = problems(path.read_text())
    for problem in found:
        print(f"error: {path}: {problem}", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    if len(sys.argv) > 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    default = pathlib.Path(__file__).resolve().parents[2] / ".spi.yml"
    sys.exit(main(pathlib.Path(sys.argv[1]) if len(sys.argv) == 2 else default))
