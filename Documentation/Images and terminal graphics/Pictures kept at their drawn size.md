# Pictures kept at their drawn size

The owner's ruling of 2026-11-09 (PERF-N4, option (b)): a picture from a file
is kept at the size it is drawn, and decoded straight to that size where the
decoder can, so neither what is held nor the decode's peak is the full
picture. This records what was built and why each choice is what it is.

## The problem

The Example's Tab Views page draws each bundled mascot four cells wide in a
tab's label. Each was decoded whole — 480 × 569 to 1,024 × 1,024 pixels, about
2.1 MB each at four bytes a pixel — and kept whole in the app's image cache, to
draw sixteen half-block pixels. Eleven of the page's 26 MB footprint was
those five pictures.

## What is kept

A file's picture is decoded at a **power-of-two fraction** of its size: the
largest that still leaves every pixel its drawing reads
(`PlatformImageLoader.reduction(of:covering:)`). What a drawing reads is the
cells the whole picture covers — its natural box (which a small space then
cuts), or the box it is fitted or filled to — times what each cell reads:

- **Glyphs**: the converter's own sample grid, `ASCIIConverter.samplesPerCell`
  — 1 × 2 for half blocks, 2 × 4 for braille, 5 × 10 for shape matching, each
  times the supersampling factor where it applies. The converter scales every
  picture to exactly this grid before it reads it, so a picture with at least
  as many pixels has all the detail the glyphs can show. Taken from the
  converter rather than written down a second time, so a new character set
  cannot be drawn from too few.
- **Terminal graphics** (Kitty, iTerm2, Sixel), where the terminal may be sent
  the picture: the cell's size in the terminal's pixels
  (`imageCellPixels`), where that is more than the glyph grid. **The same
  rule applies**, because it is the same situation: the transmission already
  resamples the picture to the pixel box it is placed in
  (`_ImageCore.pixelSize(of:fitting:)`, never more than the picture has), so
  pixels past the box were decoded, held, and thrown away on the way out. A
  picture sized to its pixel box sends exactly what it sent before. The one
  thing it gives up is the headroom the growth path used (a box growing is
  sent once at twice its size): with the picture held at between one and two
  times the box, a growth sends what it holds and the next frame decodes the
  picture at its new size.

Never reduced: an image drawn in slices (`resizable(capInsets:)`), whose caps
are cut in its own pixels; a URL's picture (downloaded bytes, a different
path, and not what the ruling was about); an image that came decoded; and a
playing animation's frames, which `FramePlan` already sizes.

### Why a power of two

- JPEG decodes natively at a half, a quarter and an eighth of its size, from
  its own coefficients, so ImageIO's thumbnail is cheapest at exactly those.
- stb_image cannot decode smaller at all; its picture is averaged down by
  whole blocks (`RGBAImage.boxReduced(by:)`, alpha-weighted).
- A box growing or shrinking a cell at a time — a window dragged, a zoom —
  decodes again only when it crosses a power of two, not on every frame. What
  is kept is at most twice what is needed on each axis.

It is a relative knob, as the owner prefers (`.downsampled(by:)`), but not a
public one: nothing asked for one, and the rule has no setting a person would
want to change.

## How it is decoded

- **Apple platforms**: `CGImageSourceCreateThumbnailAtIndex` with
  `ThumbnailMaxPixelSize` the longest side over the reduction,
  `FromImageAlways` (an embedded EXIF thumbnail is a different crop and
  quality) and `WithTransform` (EXIF orientation, as the whole decode turns
  it). A JPEG is decoded at the reduced size from its coefficients; another
  format may be inflated whole inside the call (not measured separately), but
  what comes back, and is kept, is the reduced picture.
- **stb_image** (Linux, Windows, WebAssembly): decoded whole, then averaged
  down. Only what is kept is smaller; the peak is what it was.
- **PDF**: rasterised at the reduced size directly.

The pixel limit (`imageMaxPixelCount`) is the picture's own size, not the
reduced copy's: whether a picture is too large does not depend on how small it
is drawn.

## Layout does not move

A picture is laid out at its own size, as before, so a reduction can change
which pixels a cell is drawn from but never the cells. The size comes from the
file's **header** (`PlatformImageLoader.pictureSize(atPath:maxPixelCount:)`:
ImageIO's properties, the same image of a multi-image file the decode picks,
turned by its orientation; `stbi_info_from_memory` elsewhere), read once per
version of the file and kept with the view (`FileDecodeState`). A measure
therefore decodes nothing any more: it used to decode a small file whole to
learn its size, and that whole decode is what the cache then kept. The render
decodes the picture for the box the measure answered.

The phase carries both sizes: `CachedPicture.width/height` is the picture's,
its `reduction` the pixels', and a picture the cache does not keep is
`ImageLoadingPhase.reduced` (pixels, size, reduction). The render lays the
pixels out as the picture (`canvas`, the parameter a playing picture's
scaled-down frames already used).

## Decoding again

Each frame works out the reduction its box needs. Where the pixels held were
decoded at another (`reloadAtNewSize`), the picture is loaded at the new one:
from the cache, or on this frame for a small file, or in a task for a larger
one while the view draws what it holds, scaled. Both ways: a box grown past
what is held needs more pixels, and one shrunk well inside it keeps fewer.

The cache keys each reduction separately (`cacheKey(forFile:reducedBy:)`:
the file's key, then `#1/4` for a quarter), so a picture drawn at two sizes is
kept at both and a box moving back and forth finds its pixels there. A view
appearing for a picture another view drew at another size draws that one on
its first frame and loads its own after, so a picture shown elsewhere still
never flashes its placeholder.

## Output

Glyph output shifts slightly where a picture is now reduced: the converter
used to resample the whole picture with a bilinear 2 × 2 point read, which
aliases on a heavy downscale, and now resamples a copy the decoder has
already filtered down. The owner accepted the shift. No golden snapshot
draws a file picture small enough to be reduced, so none changed.

## Measured

`Tools/Profiling/drive.py --answer-fence`, release Example, 160 × 50, three
interleaved runs each, before and after (the commit that made the change
quotes every run):

| Scenario | Peak RSS | Footprint | CPU |
|---|---|---|---|
| `tabviews` | 75–78 → 45–46 MB | 25–27 → 16–18 MB | flat (0.33 s) |
| `images` | 89–92 → 54–57 MB | 35–38 → 25–29 MB | ≈ +2%, within the runs' spread |
| `tabviews`, cache 0 | 75–77 → 45–46 MB | 25–27 → 17–18 MB | flat |
| `images`, cache 0 | 92–98 → 53–56 MB | 24–28 → 23–28 MB | flat |

The Images page draws its pictures large, so what it keeps barely changes;
its peak still falls by a third, because no picture is decoded whole any more
to be measured. Stress, which `ab_bench.py` drives, draws no picture from a
file, so these interleaved runs are the A/B.
