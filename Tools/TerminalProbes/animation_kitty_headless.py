"""Kitty's own graphics code on TUI's animation commands, with no window.

kitty cannot open a window on a VM with no OpenGL 3.3, so `animation_probe.py` cannot
draw on it. Its parser and frame compositor need no window, and answer what they can:
the reply to `a=f`, the frames a command composes to, gaps, the current frame, the
state. **Not** whether it plays: `scan_active_animations` runs in the render loop.

    /Applications/kitty.app/Contents/MacOS/kitty +runpy \
        "exec(open('Tools/TerminalProbes/animation_kitty_headless.py').read(), {})"

With `PROBE_STREAM` naming a file of a TUI app's output (`TUI_HEADLESS_STREAM`), it
parses that instead and says what became of each animated image.
"""
import base64
import os

from kitty.fast_data_types import Screen, set_send_sprite_to_gpu

WIDTH, HEIGHT = 2, 2
IMAGE_ID = 77
RED = bytes((255, 0, 0, 255))
WHITE = bytes((255, 255, 255, 255))
CLEAR = bytes((0, 0, 0, 0))


class Child:
    """What `Screen` writes replies to, and every callback it might make."""

    def __init__(self):
        self.replies = []

    def write(self, data):
        self.replies.append(bytes(data))

    def __getattr__(self, name):
        return lambda *args, **kwargs: None


child = Child()
screen = Screen(child, 24, 80, 0, 10, 20, 0, child)
set_send_sprite_to_gpu(lambda *args: 1)


def send(data):
    if isinstance(data, str):
        data = data.encode()
    buffer = screen.test_create_write_buffer()
    screen.test_commit_write_buffer(data, buffer)
    screen.test_parse_written_data()


def apc(keys, pixels=None):
    payload = ";" + base64.standard_b64encode(pixels).decode() if pixels is not None else ""
    return f"\x1b_G{keys}{payload}\x1b\\"


def describe(image_id):
    image = screen.grman.image_for_client_id(image_id)
    print(
        f"image {image_id}: {image['width']}x{image['height']}, state {image['animation_state']}, "
        f"showing frame {image['current_frame_index'] + 1}, root gap {image['root_frame_gap']}, "
        f"{len(image['extra_frames']) + 1} frames, gaps {[frame['gap'] for frame in image['extra_frames']]}")
    return image


def commands():
    """TUI's own spellings, over two frames each clear but for one block."""
    one = RED + CLEAR + CLEAR + CLEAR
    two = CLEAR + CLEAR + CLEAR + WHITE
    send(apc(f"a=t,q=2,f=32,t=d,s={WIDTH},v={HEIGHT},i={IMAGE_ID}", one))
    send(apc(f"a=a,i={IMAGE_ID},r=1,z=100,q=2"))
    send(apc(f"a=f,X=1,z=200,q=2,f=32,t=d,s={WIDTH},v={HEIGHT},i={IMAGE_ID}", two))
    print("replies to quiet commands:", child.replies)
    send(apc(f"a=f,q=0,f=32,t=d,s=2,v=2,z=40,i={IMAGE_ID}", two))
    print("reply to a frame added aloud:", b"".join(child.replies))
    send(apc(f"a=a,i={IMAGE_ID},c=2,q=2"))
    send(apc(f"a=a,i={IMAGE_ID},s=3,v=3,q=2"))
    image = describe(IMAGE_ID)
    second = list(image["extra_frames"][0]["data"])
    print("frame 2 replaced what was under it:", second == list(two), second)
    send(apc(f"a=a,i={IMAGE_ID},s=1,q=2"))
    describe(IMAGE_ID)


stream = os.environ.get("PROBE_STREAM")
if stream:
    with open(stream, "rb") as source:
        send(source.read())
    print("replies:", b"".join(child.replies))
    print("images in kitty:", screen.grman.image_count)
    for image_id in range(1, 64):
        try:
            image = describe(image_id)
        except Exception:
            continue
        for number, frame in enumerate(image["extra_frames"], start=2):
            data = frame["data"]
            stride = 4 if len(data) == 4 * image["width"] * image["height"] else 3
            row = [tuple(data[index:index + stride]) for index in range(0, stride * image["width"], stride)]
            print(f"  frame {number}, first row: {row}")
else:
    commands()
