#!/usr/bin/env python3
"""OSC 5522 probe: does this terminal speak kitty's clipboard protocol — the
one that copies and pastes any MIME type, not only text — and what does a
write of several types put on the system clipboard?

Run INSIDE the terminal under test. Nothing here needs TUI built.

  python3 clipboard_mime_probe.py          # support, write, list
  python3 clipboard_mime_probe.py --read   # ...and read text/plain back,
                                           #    which may ask the user first

Writes JSON to $PROBE_OUT (default ./clipboard_mime_probe.json).

1. **Support.** DECRQM for private mode 5522 (`CSI ? 5522 $ p`), DSR-fenced:
   kitty's documented test. A reply of 0 or 4, or none, is no support.
2. **Write.** text/plain, text/html, text/markdown and a 2×2 PNG in one
   transaction (`type=write`, one `wdata` per type, the empty `wdata` that
   ends it), and the terminal's verdict (`type=write:status=DONE` or an
   error). On macOS `osascript -e 'clipboard info'` then lists what the
   system pasteboard holds, which is what other applications will see.
3. **List.** A read of `.`, which lists the types on the clipboard and, per
   the specification, asks no permission.
4. **Read** (`--read` only): text/plain read back, which may show the user a
   permission prompt; waited for 20 s.

The clipboard is NOT put back: what the write leaves is what is measured.
Run it where the clipboard holds nothing that matters.
"""

import base64
import json
import os
import select
import struct
import subprocess
import sys
import termios
import time
import tty
import zlib

OUT = os.environ.get('PROBE_OUT', 'clipboard_mime_probe.json')
ESC = '\x1b'
ST = ESC + '\\'


def b64(data):
    return base64.b64encode(data if isinstance(data, bytes) else data.encode()).decode()


def png_2x2():
    """A 2×2 red PNG, built here so the probe needs no file."""
    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body) & 0xFFFFFFFF)
    raw = b''.join(b'\x00' + b'\xff\x00\x00' * 2 for _ in range(2))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 2, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


# The terminal, whatever stdout is: a wrapper may send the summary to a file.
TTY = os.open('/dev/tty', os.O_WRONLY)


def read_until(predicate, timeout):
    """Bytes from stdin until `predicate(buffer)` or `timeout` seconds."""
    buffer = b''
    deadline = time.time() + timeout
    while time.time() < deadline and not predicate(buffer):
        ready, _, _ = select.select([sys.stdin], [], [], max(0, deadline - time.time()))
        if ready:
            buffer += os.read(sys.stdin.fileno(), 65536)
    return buffer


def fenced(query, timeout=2.0):
    """`query`, then DSR 5, and every byte up to DSR's reply."""
    os.write(TTY, (query + ESC + '[5n').encode())
    return read_until(lambda b: b'\x1b[0n' in b, timeout)


def osc_replies(buffer):
    """The OSC 5522 packets in `buffer`, as (metadata, payload) strings."""
    packets = []
    for part in buffer.split(b'\x1b]5522;')[1:]:
        body = part.split(b'\x1b\\')[0].split(b'\x07')[0].decode(errors='replace')
        metadata, _, payload = body.partition(';')
        packets.append((metadata, payload))
    return packets


def decode_meta(metadata):
    out = {}
    for pair in filter(None, metadata.split(':')):
        key, _, value = pair.partition('=')
        if key in ('mime', 'name', 'pw'):
            try:
                value = base64.b64decode(value).decode()
            except Exception:
                pass
        out[key] = value
    return out


def main():
    results = {'term': os.environ.get('TERM'), 'term_program': os.environ.get('TERM_PROGRAM')}
    saved = termios.tcgetattr(sys.stdin)
    tty.setraw(sys.stdin)
    try:
        reply = fenced(ESC + '[?5522$p')
        results['decrqm_raw'] = reply.decode(errors='replace')
        mode = None
        marker = b'\x1b[?5522;'
        if marker in reply:
            mode = int(reply.split(marker)[1].split(b'$')[0])
        results['decrqm'] = mode
        results['supported'] = mode not in (None, 0, 4)

        payloads = {
            'text/plain': 'TUI probe ' + str(os.getpid()),
            'text/html': '<b>TUI</b> probe',
            'text/markdown': '**TUI** probe',
            'image/png': png_2x2(),
        }
        out = ESC + ']5522;type=write' + ST
        for mime, data in payloads.items():
            out += ESC + ']5522;type=wdata:mime=' + b64(mime) + ';' + b64(data) + ST
        out += ESC + ']5522;type=wdata' + ST
        os.write(TTY, out.encode())
        reply = read_until(lambda b: b'status=' in b, 3.0)
        results['write_replies'] = [(m, p) for m, p in osc_replies(reply)]
        results['write_status'] = [decode_meta(m).get('status') for m, _ in osc_replies(reply)]
        time.sleep(0.3)
        if sys.platform == 'darwin':
            info = subprocess.run(['osascript', '-e', 'clipboard info'], capture_output=True, text=True)
            results['pasteboard_info'] = info.stdout.strip() or info.stderr.strip()
            text = subprocess.run(['pbpaste'], capture_output=True, text=True)
            results['pbpaste'] = text.stdout

        os.write(TTY, (ESC + ']5522;type=read;' + b64('.') + ST).encode())
        reply = read_until(lambda b: b'status=DONE' in b or b'status=E' in b, 3.0)
        listed = []
        for metadata, payload in osc_replies(reply):
            meta = decode_meta(metadata)
            entry = dict(meta)
            if payload:
                try:
                    entry['payload'] = base64.b64decode(payload).decode(errors='replace')
                except Exception:
                    entry['payload_raw'] = payload
            listed.append(entry)
        results['list'] = listed

        if '--read' in sys.argv:
            os.write(TTY, (ESC + ']5522;type=read;' + b64('text/plain') + ST).encode())
            reply = read_until(lambda b: b'status=DONE' in b or b'status=E' in b, 20.0)
            read = []
            for metadata, payload in osc_replies(reply):
                entry = decode_meta(metadata)
                if payload:
                    entry['payload'] = base64.b64decode(payload).decode(errors='replace')
                read.append(entry)
            results['read_text'] = read
    finally:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, saved)
    with open(OUT, 'w') as handle:
        json.dump(results, handle, indent=2)
    print(json.dumps({k: results.get(k) for k in ('supported', 'decrqm', 'write_status', 'pasteboard_info')}, indent=2))


if __name__ == '__main__':
    main()
