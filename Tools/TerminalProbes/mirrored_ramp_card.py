# A track's fill starting within a cell (B33-SUBCELL): the ramp glyph covering the
# cell's empty left part, in the track's colour, over the fill's, beside the plain
# ramp (fill on the left) TUI already draws. Double-width rows (DECDWL) to read
# the edges; 256 colours, since Apple Terminal paints no 24-bit colour.
# Run from a `.command` file outside ~/Documents; it holds the window 90 s.
import sys, time
ramp = ["▏", "▎", "▍", "▌", "▋", "▊", "▉"]
TRACK = "\x1b[38;5;21m\x1b[48;5;21m"
FILL = "\x1b[38;5;160m\x1b[48;5;160m"
def mirrored(u):
    # ramp glyph covering u/8 from the left, in the track's colour, over the fill's
    return f"\x1b[38;5;21m\x1b[48;5;160m{ramp[u-1]}"
out = ["\x1b[2J\x1b[H"]
out.append("B33-SUBCELL card: track blue, fill red; each row: track, edge cell (u/8 empty), fill x3, then the plain ramp for comparison\r\n")
for u in range(1, 8):
    row = TRACK + "  " + mirrored(u) + FILL + "███" + "\x1b[0m" + "   " + "\x1b[38;5;160m\x1b[48;5;21m" + ramp[u-1] + TRACK + "  " + "\x1b[0m" + f"  u={u}"
    out.append("\x1b#6" + row + "\r\n")
sys.stdout.write("".join(out)); sys.stdout.flush()
time.sleep(90)
