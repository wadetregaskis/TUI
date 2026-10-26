# Blend modes and image details (EFFECTS)

Lane EFFECTS, 2026-10-19, built inline on main 6044c51ac. Four items settled by
your earlier rulings (W5, B-D3M-3, B-D3M-4) and one owed look (B22). One
question comes back to you, A-EFFECTS-1. B33-SUBCELL, which waits on a PTY check of
its edges, follows.

## What shipped

- **W5, blend modes.** `BlendMode`, `View.blendMode(_:)`, `VisualEffect.blendMode(_:)`
  and `ShapeStyle.blendMode(_:)`, composited cell by cell as `.opacity` is,
  against macOS's arithmetic, measured first (`Tools/SwiftUIProbes/Blend modes`;
  `Opacity as composition.md` §110).
- **B-D3M-3.** A tiled image repeats at its natural size, and cap insets are
  points, where the terminal's cell size in points is known.
- **B-D3M-4.** A PDF is read again on Apple platforms, through Core Graphics, and
  the `CGColor` and `CGImage` bridges are TUI's own.
- **B22, the look owed.** The faint content levels were rendered at 16 and 256
  colours over every shipped palette; the result is in B22, and the levels
  that vanish are A-EFFECTS-1.

## Needs your decision

### A-EFFECTS-1. The faint content levels vanish at 16 colours, and the faintest at 256

*`HierarchicalShapeStyle` `.secondary` … `.quinary` under a `foregroundStyle`
(decisions B22)*

Under a `foregroundStyle`, `.secondary` to `.quinary` are that style at 0.5,
0.26, 0.1 and 0.05, composited at the cell. Rendered over each shipped
palette's page with the colour depth forced, and the ink read back out of the
emitted SGR (`FaintLevelsAuditTests`, 2026-10-19):

- **16 colours, all sixteen palettes:** `.secondary` is drawn in exactly
  `.primary`'s colour, and `.tertiary`, `.quaternary` and `.quinary` in the
  page's own colour — invisible. The nearest of sixteen colours to a faint ink
  is the page.
- **256 colours:** most levels stay apart, but `.quinary` is the page on Green,
  Red, Violet, Ocean and Solid Colors, and `.quaternary` too on Grass,
  Homebrew and Novel (eleven cells in all). Several neighbours collapse into
  one colour (`.tertiary` and `.quaternary` on Green, Red, Blue and Ocean).

The rendered contrast floor does not reach these: it floors a control's label
on its fill, not content text.

Options:

1. **Leave them.** The arithmetic is honest, and at 16 colours there is no
   colour between the ink and the page. *Price:* text an app styled
   `.tertiary` or fainter is invisible on a 16-colour terminal, and the
   faintest is on some 256-colour palettes.
2. **Floor the levels at the depth.** A level whose quantised ink is the
   page's steps toward the primary to the nearest colour that is not, at 256
   colours (a cube or grey entry); at 16, `.tertiary` and below take the
   primary's colour. *Price:* a small check per faint glyph at those depths;
   at 16 colours every level below the first is one colour, so the ordering is
   lost but nothing vanishes.
3. **At 16 colours, draw the faint levels dim (SGR 2) in the primary's
   colour**, and floor them at 256 as in 2. Every terminal TUI supports
   draws SGR 2 as a fainter ink, and TUI already uses it for a faint row
   (`Opacity as composition.md` §102). *Price:* as 2, and `.secondary` becomes
   distinct from `.primary` at 16 colours too, which it is not today.

**Recommendation:** 3. It keeps the levels visible and ordered as far as 16
colours can, with the attribute terminals already provide for exactly this,
and changes nothing at 24-bit colour.
