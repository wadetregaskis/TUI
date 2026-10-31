# Working with Images

Show a picture from a file or the web, size it, and choose how it looks in terminals that draw it in text.

## Overview

You'll start with a picture on the screen, then learn how to size it and how to show one that takes time to load. At the end, you can see how to change its look.

```swift
struct Photo: View {
    var body: some View {
        Image(.file("photo.png"))
            .resizable()
            .scaledToFit()
            .frame(width: 40, height: 20)
    }
}
```

Those three modifiers are all most pictures need: `.resizable()` lets the picture change size, `.scaledToFit()` keeps its shape, and `.frame` says how many cells it can use.

A relative path starts from the folder you ran the app in. If the picture can't be loaded, you'll see a line of text starting with `Error:` where it should be.

There are two other places a picture can come from:

```swift
// From the web. It's downloaded while the app keeps running.
Image(.url("https://example.com/photo.png"))

// From your package's resources.
// In Package.swift: resources: [.process("Resources")]
Image("logo", bundle: .module)
```

PNG, JPEG, GIF and BMP files work everywhere. On a Mac, so does anything else the system can read, such as HEIC and TIFF.

## Real pixels and text characters

Every terminal is a grid of character cells, so there are two ways to show a picture in one:

- **Real pixels.** Terminals with the Kitty graphics protocol, such as Ghostty and iTerm2, draw the picture itself, as sharp as your screen allows.
- **Text characters.** Everywhere else, including Apple's Terminal, Warp and tmux, TUI draws the picture in coloured block characters. Each cell shows two pixels of colour, one above the other, so it's blocky but easy to recognise.

You don't need to do anything to choose. TUI asks the terminal when your app starts, and uses the best it can. The picture takes up the same cells either way, so your layout doesn't change. To see the text version in a terminal that has real pixels, run your app with `TUI_GRAPHICS=0`.

Some designs use the blocky look on purpose. To keep it everywhere, turn off real pixels for that part of your app:

```swift
Image(.file("logo.png"))
    .resizable()
    .scaledToFit()
    .terminalGraphics(false)
```

## Choosing a size

Sizes are in cells, and a cell is about twice as tall as it is wide. So a square takes up about twice as many columns as rows.

| You write | What happens |
|---|---|
| `.resizable().scaledToFit()` | Fits inside the frame and keeps its shape, leaving space around it if the shapes differ |
| `.resizable().scaledToFill()` | Fills the frame and keeps its shape, cutting off what doesn't fit |
| `.resizable()` | Stretches to fill the frame exactly |
| Nothing | Takes its natural size where TUI knows how big a cell is, and otherwise fits the space it's offered |

Write `.resizable().scaledToFit()` with a frame unless you have a reason not to, because it looks the same in every terminal. A picture with no `.resizable()` can come out a very different size from one terminal to the next, and a frame smaller than the picture cuts it off instead of shrinking it.

To let a picture use all the width it can, write only the frame's limit:

```swift
Image(.file("photo.png"))
    .resizable()
    .scaledToFit()
    .frame(maxWidth: .infinity)
```

## Pictures that take time to load

A small file loads straight away, on the frame that first draws it. A larger file, or a URL, loads in the background. Meanwhile your app keeps running, and the image shows a spinner in its frame.

You can change what it shows while loading:

```swift
Image(.url("https://example.com/photo.png"))
    .resizable()
    .scaledToFit()
    .frame(width: 40, height: 20)
    .imagePlaceholder("Loading the photo…")
```

To show views of your own while it loads, or if it fails, use ``AsyncImage``, as in SwiftUI:

```swift
struct Avatar: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .failure:
                Text("No picture")
            default:
                Spinner()
            }
        }
        .frame(width: 20, height: 10)
    }
}
```

Downloads give up after 30 seconds. Use `.imageURLTimeout(10)` to change that, and `.imageMaxPixelCount(4_000_000)` to refuse pictures that are too big.

### The cache

Your app keeps recently loaded pictures in memory, so a picture that comes back into view draws at once. An edited file is noticed and read again. You don't have to set anything up.

The cache holds 64 MiB of decoded pictures, and drops the ones used least recently once it's full. For a photo browser, you may want more. The person running the app can set `TUI_IMAGE_CACHE_SIZE=256M`, or you can give your views a cache of your own:

```swift
@main
struct Viewer: App {
    let imageCache = URLImageCache(byteLimit: 256 << 20)

    var body: some Scene {
        WindowGroup {
            Text("Your views here")
                .urlImageCache(imageCache)
        }
    }
}
```

Make the cache somewhere that lasts, as here, and not inside a `body`, which would make a new, empty one each time.

## Advanced: changing how a picture is drawn

These settings apply to a view and everything inside it. You don't need any of them to get a good picture, and the defaults are the most faithful.

### Glyph sets

``View/imageCharacterSet(_:)`` chooses which characters draw the text version of a picture. It makes no difference where real pixels are drawn, so add `.terminalGraphics(false)` if the look matters everywhere.

| Character set | Look |
|---|---|
| `.blocks(.fine)` | Half blocks, two pixels to a cell. The default |
| `.blocks(.solid)` | One colour per cell. Coarser, but never shows gaps between rows, which some fonts do |
| `.blocks(.braille)` | Braille dots, the most detail for line art and text |
| `.blocks(.coarse)` | Shade characters that show tone even with no colour |
| `.ascii` | Letters and punctuation, for the classic look |
| `.unicode` | A wider range of symbols |
| `.customRamp(" .:-=+*#%@")` | Your own characters, from least ink to most |

``View/imageShapeAware(_:)`` picks each character for the shape of what's in its cell, instead of just how bright the cell is, so edges come out cleaner:

```swift
Image(.file("logo.png"))
    .resizable()
    .scaledToFit()
    .imageCharacterSet(.ascii)
    .imageShapeAware()
    .terminalGraphics(false)
```

### Colours and palettes

``View/imageColorMode(_:)`` chooses the colours, in both real pixels and text:

| Colour mode | Look |
|---|---|
| `.trueColor` | Full colour. The default |
| `.ansi256`, `.ansi16` | Limited to the terminal's standard colours, for a retro look |
| `.grayscale` | Shades of grey |
| `.mono` | Two colours: the view's foreground and background styles |
| `.palette(ASCIIPalette([.red, .white, .blue]))` | Only the colours you list |

`ASCIIPalette.shades(8)` gives you eight shades of grey, and `ASCIIPalette.spread(32)` gives you colours spread evenly. ``ASCIIPalette`` can also choose colours to suit each picture.

### Dithering

Reducing a picture to a few colours leaves flat bands. ``View/imageDithering(_:)`` mixes neighbouring colours to hide them. It has no effect at full colour, where there's nothing to hide:

```swift
Image(.file("photo.png"))
    .resizable()
    .scaledToFit()
    .imageColorMode(.ansi16)
    .imageDithering(.floydSteinberg)
```

### Changing the picture itself

These change the picture before anything is drawn, in both real pixels and text:

- ``View/imageToneCurve(_:)`` remaps tones. `.imageToneCurve(.inverted)` makes a negative.
- ``View/imageAdjustments(_:)`` sets exposure, black point, highlights and contrast.
- ``View/imagePosterization(levels:)`` limits each colour channel to a few levels.
- ``View/imageEdgeContrast(_:)`` sharpens local detail. Around `0.6` is a visible lift.

## See Also

- <doc:TerminalSupport>
- ``Image``
- ``AsyncImage``
- ``URLImageCache``
