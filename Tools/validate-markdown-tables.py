#!/usr/bin/env python3
"""Fails on a Markdown table row with more cells than its table's header.

GitHub's Markdown (GFM) drops a row's extra cells without a word: "If greater, the excess is ignored"
(the spec's tables extension). So two rows run together on one line, `| a | b || c | d |`, render as
`| a | b |` and the second row is simply gone: no warning on GitHub, no failure anywhere else. Module
split step B4 lost a row of CONTRIBUTING.md's Windows status table that way, the one for the four
modules' own test targets, and a review found it by reading the source. Every later step adds a row
to that table, and agents edit the documentation's tables with scripts, so this is the check.

    python3 Tools/validate-markdown-tables.py              # every tracked .md file; exit 1 on a finding
    python3 Tools/validate-markdown-tables.py FILE ...     # these files only
    python3 Tools/validate-markdown-tables.py --self-test  # prove the check bites, on samples below

A cell boundary is a pipe that is not backslash-escaped, inside a code span too: GFM splits
`` `a | b` `` into two cells unless the pipe is written `\\|`. A row with FEWER cells is not flagged:
GFM pads it with empty cells, so nothing is lost. Fenced code blocks are skipped. A table ends at a
blank line or at a line that starts a heading, a quote or a fence; this is GFM's rule, short of
the rarer block starts (an HTML block, a thematic break), which no table here is followed by.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FENCE = re.compile(r'^ {0,3}(`{3,}|~{3,})')
DELIMITER_CELL = re.compile(r'^\s*:?-+:?\s*$')
BLOCK_START = re.compile(r'^ {0,3}(#{1,6}(\s|$)|>)')


def cells(line):
    """The cells GFM reads from a table line: split on unescaped pipes, less one leading and one trailing."""
    text = line.strip()
    parts, current, i = [], '', 0
    while i < len(text):
        if text[i] == '\\' and i + 1 < len(text):
            current += text[i:i + 2]
            i += 2
            continue
        if text[i] == '|':
            parts.append(current)
            current = ''
        else:
            current += text[i]
        i += 1
    parts.append(current)
    if text.startswith('|'):
        parts = parts[1:]
    if len(parts) > 1 and parts[-1].strip() == '' and text.endswith('|') and not text.endswith('\\|'):
        parts = parts[:-1]
    return parts


def findings(lines):
    """(line number, cells, header cells) for every table row with more cells than its header."""
    found, fence, i = [], None, 0
    while i < len(lines):
        opened = FENCE.match(lines[i])
        if opened:
            marker = opened.group(1)
            if fence is None:
                fence = marker[0] * 3
            elif marker.startswith(fence):
                fence = None
            i += 1
            continue
        if fence is None and i + 1 < len(lines) and '|' in lines[i] + lines[i + 1]:
            header, delimiter = cells(lines[i]), cells(lines[i + 1])
            if len(header) == len(delimiter) and all(DELIMITER_CELL.match(c) for c in delimiter):
                j = i + 2
                while j < len(lines) and lines[j].strip() and not BLOCK_START.match(lines[j]) \
                        and not FENCE.match(lines[j]):
                    if len(cells(lines[j])) > len(header):
                        found.append((j + 1, len(cells(lines[j])), len(header)))
                    j += 1
                i = j
                continue
        i += 1
    return found


def tracked_markdown():
    out = subprocess.run(['git', '-C', ROOT, 'ls-files', '-z', '--', '*.md'],
                         check=True, capture_output=True, text=True).stdout
    return [os.path.join(ROOT, path) for path in out.split('\0') if path]


def check(paths):
    total = 0
    for path in paths:
        with open(path, encoding='utf-8') as fh:
            lines = fh.read().split('\n')
        for line, count, header in findings(lines):
            total += 1
            print(f'{os.path.relpath(path, ROOT)}:{line}: a row of {count} cells under a header of {header}; '
                  f'GitHub drops the last {count - header} (two rows run together on one line?)')
    if total:
        print(f'{total} table row(s) lose cells on GitHub', file=sys.stderr)
    return 1 if total else 0


# (name, Markdown, the line numbers the check must report)
SAMPLES = [
    ('two rows run together, as step B4 left CONTRIBUTING.md',
     '| Step | Status |\n|---|---|\n| `A` | advisory || the tests | advisory |\n| `B` | binding |', [3]),
    ('a well-formed table', '| Step | Status |\n|---|---|\n| `A` | advisory |\n| `B` | binding |', []),
    ('no outer pipes', 'Step | Status\n--- | :---:\nA | advisory | extra', [3]),
    ('an escaped pipe in a code span is content', '| Op | Meaning |\n|---|---|\n| `a \\|\\| b` | or |', []),
    ('an unescaped pipe in a code span splits the cell', '| Op | Meaning |\n|---|---|\n| `a || b` | or |', [3]),
    ('a short row is padded, not cut', '| a | b | c |\n|---|---|---|\n| 1 |', []),
    ('a table in a fence is code', '```\n| a | b |\n|---|---|\n| 1 | 2 | 3 |\n```', []),
    ('a blank line ends the table', '| a | b |\n|---|---|\n\n| 1 | 2 | 3 |', []),
    ('a heading ends the table', '| a | b |\n|---|---|\n# x | y | z', []),
    ('a delimiter row that disagrees with its header is no table', '| a | b |\n|---|\n| 1 | 2 | 3 |', []),
]


def self_test():
    failures = 0
    for name, text, expected in SAMPLES:
        got = [line for line, _, _ in findings(text.split('\n'))]
        if got != expected:
            failures += 1
            print(f'FAIL {name}: reported lines {got}, expected {expected}')
    if failures:
        print(f'{failures} self-test failure(s)', file=sys.stderr)
        return 1
    print(f'self-test passed: {len(SAMPLES)} samples, each reported exactly where it should be')
    return 0


if __name__ == '__main__':
    args = sys.argv[1:]
    if args == ['--self-test']:
        sys.exit(self_test())
    sys.exit(check([os.path.abspath(a) for a in args] if args else tracked_markdown()))
