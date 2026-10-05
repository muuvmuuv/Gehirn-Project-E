# Brand

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="media/brand/lockup-dark.svg">
  <img alt="gehirn's mark, a ring with three square contacts, beside GEHIRN and ゲヒルン E計画, with an orange cable running from the ring under the name" src="media/brand/lockup-light.svg" width="400">
</picture>

This page is for anyone putting gehirn's mark or name on a page, a slide or a video. It says what the mark means, which colors it takes, how small it may go and which file to use.

## The mark

The mark is the entry plug's connector seen end on: a ring, the plug's shell, holding three contacts, one per MAGI unit. A connector conducts only once every contact seats, the way an irreversible goal passes only once all three units approve. The contacts sit where the bridge puts the units: BALTHASAR-2 on top, CASPER-3 below left, MELCHIOR-1 below right. The lockup adds the umbilical cable, which leaves the plug at the bottom of its ring and runs under the name.

It is drawn on a 16 unit grid. The ring runs around (8, 8) with an outer radius of 7 and an inner one of 5, and the contacts are 2 by 2 squares at (7, 4), (4, 8) and (10, 8). Every straight edge and the ring's four extremes fall on whole units, so one file stays crisp from a 16 px favicon to a 512 px icon. The contacts are square and the ring has no key notch, so the mark reads neither as an XLR socket nor as the radiation trefoil.

## Colors

| Color | Hex | Meaning |
| --- | --- | --- |
| Ink | `#040406` | The ground the mark lives on, the bridge's `ink` |
| Paper | `#ECE8E1` | The ring and the name on a dark ground, the bridge's `paper` |
| Orange | `#FF8D00` | The contacts and the cable, the bridge's `orange` |
| Deep orange | `#C25E00` | The contacts and the cable on a light ground, 4.3:1 on white where orange reaches 2.3:1 |
| Dim | `#8B8680` | ゲヒルン E計画 on a dark ground, the bridge's `dim` |
| Dim on light | `#5E5852` | ゲヒルン E計画 on a light ground |

On a light ground the ring and the name turn ink.

## Size and space

- The mark goes down to 16 px, the size of its grid. Below that the contacts merge with the ring.
- The lockup goes down to 200 px wide, where ゲヒルン E計画 stands about 10 px tall. Below that, use the mark and set the name in text.
- Keep clear space of one ring width around the ring, 2 units of the grid, and the same around the lockup.
- Scale the mark only as a whole. Do not stretch it, rotate it, round the contacts, add a notch, outline it or set the name in another face.

The name in the lockup is Barlow Condensed Black and the Japanese Zen Old Mincho Black, both under the SIL Open Font License. Barlow Condensed is in [bridge/fonts](../bridge/fonts/README.md), but the bridge holds only a subset of Zen Old Mincho that lacks ゲ, ヒ, 計 and 画, so the full face comes from google/fonts, `ofl/zenoldmincho`. The lockup's SVGs hold both as outlines, so they need no font installed.

## A fan project

gehirn is a fan project, not affiliated with khara or Gehirn Inc. The mark is original. It carries the show's three judges, the lockup adds the show's Japanese and the social card its hazard stripes, but none of them resembles an official mark: not NERV's fig leaf, not SEELE's triangle, not MAGI's three panel layout, and no Matisse, the show's typeface. It also stays clear of Gehirn Inc., a real company behind the NERV防災 app: nothing like its faceted G, its squared, rounded rectangle wordmark, or Gehirn Web Services' hexagon in a hexagon. Any surface that carries the mark also carries that line, and nothing that carries it is sold ([decisions](decisions.md#project)).

## Files

| File | Use |
| --- | --- |
| [media/brand/mark.svg](media/brand/mark.svg) | The mark; it follows the viewer's light or dark scheme |
| [media/brand/mark-mono.svg](media/brand/mark-mono.svg) | The mark in one color, `currentColor`, for print, stamps and embossing |
| [media/brand/lockup-dark.svg](media/brand/lockup-dark.svg) | The lockup on a dark ground |
| [media/brand/lockup-light.svg](media/brand/lockup-light.svg) | The lockup on a light ground |
| [media/brand/social.png](media/brand/social.png) | The 1280 by 640 card for link previews: the fan project line, the lockup and the README's first sentence on ink |
| [website/favicon.svg](../website/favicon.svg) | The website's favicon, a copy of mark.svg |
| `website/favicon.ico`, `favicon-96x96.png` | The mark on an ink tile, for browsers without SVG favicons, PDFs and search results; the icon holds 16, 32 and 48 px |
| `website/apple-touch-icon.png` | 180 px on opaque ink, since iOS fills transparency black |
| `website/icon-192.png`, `icon-512.png`, `icon-maskable-512.png` | The web app manifest's icons; the maskable one keeps the ring inside the central 80% circle that Android's masks leave |

The social preview is not read from the repository. GitHub takes it only as an upload: Settings, General, Social preview, Edit, then social.png.

### Rebuilding them

No script in the repository builds these files, since outlining the type needs fontTools, which the tools' standard library rule (CONTRIBUTING.md, Python tools 2) keeps out, so this section gives the numbers that do. mark.svg holds the ring as one path under the even-odd rule and the contacts as another, ink and deep orange, or paper and orange under `prefers-color-scheme: dark`; mark-mono.svg holds both in one `currentColor` path.

The lockup sets the mark at 4 px a unit with its grid at 0, 0, and its view box runs from 4, 4 to the cable's end. GEHIRN is outlined at 40 px with 0.1 em between advances, its ink from x 78, on the base line 36. ゲヒルン E計画 is outlined at 13 px with 0.22 em between the glyphs' ink, from x 78, on the base line 53. The cable, a 4 px stroke drawn under the mark, starts at 32, 56, drops to 60, runs at 45 degrees to 38, 66 and on to GEHIRN's right edge. svgo then shrinks the four SVGs with its default preset, multipass, at 2 decimals and with `inlineStyles` off, which would otherwise pin the light scheme's fills over the dark one's media query.

Each icon is an ink square under the mark in paper and orange, scaled into a box centered on it, and rendered with `rsvg-convert -w <size> -h <size>`; the box over 16 gives the pixels a unit:

| File | Size | Ink square, corner radius | Mark box |
| --- | --- | --- | --- |
| favicon.ico's images | 16, 32 and 48 | the size, 3/16 of it | the size |
| favicon-96x96.png | 96 | 96, 18 | 96 |
| apple-touch-icon.png | 180 | 180, 0 | 128 |
| icon-192.png | 192 | 192, 36 | 144 |
| icon-512.png | 512 | 512, 96 | 384 |
| icon-maskable-512.png | 512 | 512, 0 | 400 |

The website's PNGs are then quantized to 64 colors without dithering, except the three in favicon.ico, which holds them as they are, as PNG entries of 32 bits.

social.png is ink under a 12 px hazard band, stripes at 45 degrees as wide as the band is high, `#3D2200` on `#140B02`. The fan project line follows in Barlow Condensed Black at 34 px in paper, with 0.06 em between advances, on the base line 72 from x 96. lockup-dark.svg sits at three times its size with the ring's left edge at x 96 and its top at 128, and the README's first sentence follows in Barlow Condensed SemiBold at 38 px in paper, wrapped at 1088 px, its first base line 80 px below the lockup and each next one 48 px lower. `rsvg-convert` renders it, and it is quantized to 128 colors without dithering. The card copies that sentence, so a change to it in the README means a new card.
