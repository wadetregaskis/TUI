# Demo image

`paint_demo_image.py` paints the picture the Example's image page shows,
`Sources/Example/Resources/demo-image.jpg`: an orrery badge (a brushed-metal
disc with an engraved scale, a glowing blue field, a ringed planet) on a
starfield. It needs Pillow.

```
python3 Tools/DemoImage/paint_demo_image.py Sources/Example/Resources/demo-image.jpg
```

The picture is painted so that the repository holds nothing it may not show.
It is the same every run (seeded noise), and it keeps what the image pages and
`AdaptivePaletteTests.noEntryIsWastedOnTheDemoPicture` need from a
photograph: a near-black, speckled ground, a large grey surface with grain,
a blue ramp from navy to near-white, a warm accent, and edges at several
scales.

It replaced a third-party emblem on 2026-10-25. Measurements in
`Documentation/Images and terminal graphics/` that name `demo-image.jpg` at
1101×1080 were taken on that earlier picture, which is still in the history.
