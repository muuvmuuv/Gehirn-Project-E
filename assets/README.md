# Assets

This file is for anyone looking for an image, a recording, an icon or a font in the repository, or about to add, move or remake one. It lists every one of them, wherever it lives: what it shows, where it is used, how it is made and under which license. A commit that adds, moves or remakes an asset changes its row here.

`assets/` holds the brand's masters and the screenshots and recordings the docs show. Files a consumer reads from a fixed place stay there: the website's icons and clips in `website/`, the one folder Vercel deploys, and the icons and fonts the bridge builds in with `$embed_file`. `just assets` runs [build.py](build.py), which makes every file whose row says so from the SVG masters; [docs/brand.md](../docs/brand.md#rebuilding-them) gives its numbers and how the masters are drawn.

Everything here is gehirn's own work under the [EUPL 1.2](../LICENSE), except the fonts, which keep the SIL Open Font License 1.1 with its text beside each in `bridge/fonts`. Type outlined into the lockups and set on the social card or in a frame of the bridge comes from those fonts; the OFL does not reach a document made with a font, so those files are EUPL too. Nothing comes from khara or the show: no frame, no audio, no logo and no Matisse typeface ([decisions](../docs/decisions.md#project)).

## Brand

| File | Shows | Used by | Made by | License |
| --- | --- | --- | --- | --- |
| [assets/brand/mark.svg](brand/mark.svg) | The mark, ring and contacts in ink and deep orange, or paper and orange in a dark scheme | docs/brand.md; the source of every icon and of website/favicon.svg | Master, drawn on the 16 unit grid of docs/brand.md and shrunk with svgo | EUPL 1.2 |
| [assets/brand/mark-mono.svg](brand/mark-mono.svg) | The mark in one `currentColor` path | Print, stamps and embossing (docs/brand.md) | Master, as mark.svg | EUPL 1.2 |
| [assets/brand/lockup-dark.svg](brand/lockup-dark.svg) | The mark, GEHIRN, ゲヒルン E計画 and the cable on a dark ground | README.md's `<picture>` in a dark scheme, docs/brand.md, the source of social.png | Master, its type outlined with fontTools from Barlow Condensed Black and the full Zen Old Mincho Black by docs/brand.md's numbers, then svgo | EUPL 1.2 |
| [assets/brand/lockup-light.svg](brand/lockup-light.svg) | The lockup on a light ground | README.md's `<picture>` in a light scheme, docs/brand.md | Master, as lockup-dark.svg | EUPL 1.2 |
| [assets/brand/social.png](brand/social.png) | The 1280 by 640 link preview card: the fan project line, the lockup and the README's first sentence between hazard bands | GitHub's social preview, uploaded by hand under Settings, General | `just assets`, from lockup-dark.svg, the sentence under README.md's title and `fan_line` in bridge/draw.v | EUPL 1.2 |

## Screenshots and recordings

| File | Shows | Used by | Made by | License |
| --- | --- | --- | --- | --- |
| [assets/media/magi.gif](media/magi.gif) | MAGI on hosted models refusing the release 1/3 with a person within reach, then passing it 3/3, 800 by 447 | README.md's top | The GIF of one `just lineup=magi demo-record` take on 2026-10-05, MAGI on gpt-oss-20b, Jev and llama-3.1-8b-instruct judging the mock's scripted core, cut again from that take's MP4 with scripts/record.sh's GIF filter, without its first 0.33 s, which still showed the goto's verdict | EUPL 1.2 |
| [assets/media/bridge.png](media/bridge.png) | The whole bridge, 1280 by 800, as that take's 否決 lands with the human 1.04 m from the body, the mark's contacts lit with the votes | docs/bridge.md's top; website/bridge.png is its copy | A frame the same take saved, as RGB | EUPL 1.2 |
| [assets/media/bridge/magi-refused.png](media/bridge/magi-refused.png) | The MAGI block during a refused release, 決議 否決 1/3 | bridge/README.md's top | A frame saved as bridge/README.md's Recording frames does, scaled to 1280 by 800 and cropped with ffmpeg around its box in the Layout table | EUPL 1.2 |
| [assets/media/bridge/magi-deliberating.png](media/bridge/magi-deliberating.png) | The MAGI block deliberating on a goto as a 可決 lands | bridge/README.md, 審議中 and a landing ballot | As magi-refused.png | EUPL 1.2 |
| [assets/media/bridge/emergency.png](media/bridge/emergency.png) | The EMERGENCY overlay as the cable is cut, an 800 by 360 cut from the window's middle | bridge/README.md, EMERGENCY | A frame saved as magi-refused.png's, scaled to 1280 by 800 and cut to 800 by 360 from the middle with ffmpeg | EUPL 1.2 |
| [assets/media/bridge/limit-internal.png](media/bridge/limit-internal.png) | The 活動限界 panel on internal power at 4:55 | bridge/README.md, Seven segment timer | As magi-refused.png | EUPL 1.2 |
| [assets/media/bridge/scene.png](media/bridge/scene.png) | The radar: the body at beacon B1, a human within 2 m, an obstacle and the trail | bridge/README.md, Radar | As magi-refused.png, with the ffmpeg line in Recording frames | EUPL 1.2 |
| [assets/media/bridge/harmonics.png](media/bridge/harmonics.png) | The harmonics panel at 57.8% sync with the dummy plug in the seat | bridge/README.md, Harmonics | As magi-refused.png | EUPL 1.2 |

## Website

Each of these sits where `website/index.html` or the manifest names it.

| File | Shows | Used by | Made by | License |
| --- | --- | --- | --- | --- |
| [website/favicon.svg](../website/favicon.svg) | The mark, following the viewer's scheme | index.html's SVG favicon | `just assets`, a copy of mark.svg | EUPL 1.2 |
| [website/favicon.ico](../website/favicon.ico) | The mark on an ink tile at 16, 32 and 48 px, as PNG entries | index.html's fallback icon, browsers without SVG favicons | `just assets` | EUPL 1.2 |
| [website/favicon-96x96.png](../website/favicon-96x96.png) | The mark on an ink tile, 96 px | index.html's PNG favicon, search results | `just assets` | EUPL 1.2 |
| [website/apple-touch-icon.png](../website/apple-touch-icon.png) | The mark on opaque ink, 180 px | index.html's touch icon on iOS | `just assets` | EUPL 1.2 |
| [website/icon-192.png](../website/icon-192.png) | The mark on an ink tile, 192 px | site.webmanifest | `just assets` | EUPL 1.2 |
| [website/icon-512.png](../website/icon-512.png) | The mark on an ink tile, 512 px | site.webmanifest | `just assets` | EUPL 1.2 |
| [website/icon-maskable-512.png](../website/icon-maskable-512.png) | The mark inside the central 80% circle on a square ink tile, 512 px | site.webmanifest, as the maskable icon Android crops | `just assets` | EUPL 1.2 |
| [website/site.webmanifest](../website/site.webmanifest) | The web app manifest: the name, the three icons, the theme and background colors | index.html | Written by hand | EUPL 1.2 |
| [website/bridge.png](../website/bridge.png) | The bridge refusing the release, as assets/media/bridge.png | index.html's annotated frame | A copy of assets/media/bridge.png: `cp assets/media/bridge.png website/bridge.png` | EUPL 1.2 |
| [website/media/boot.mp4](../website/media/boot.mp4) | The demo's first 8 s, from the boot screen to MAGI passing the goto 3/3 | index.html, Watch it run | A bridge built as scripts/record.sh builds it flew scripts/scenes/demo.sh by hand with every frame kept, stopped after 16 s; its frames encoded as record.sh encodes them, libx264 at crf 20, 1280 by 800, no audio | EUPL 1.2 |
| [website/media/boot.png](../website/media/boot.png) | The boot screen with its five lines | boot.mp4's poster | A frame of the same take, 1280 by 800, cut to 256 colors | EUPL 1.2 |
| [website/media/ep13-iruel.mp4](../website/media/ep13-iruel.mp4) | Episode 13's MAGI hack as a scene, 31 s | index.html, Watch it run | `just scene=ep13-iruel demo-record`, unchanged | EUPL 1.2 |
| [website/media/ep13-iruel.png](../website/media/ep13-iruel.png) | The 3/3 verdict with the armor's refusal of self_destruct | ep13-iruel.mp4's poster | A frame of the same take, 1280 by 800, cut to 256 colors | EUPL 1.2 |

## Bridge embeds

`bridge/icon.v` builds these into `gehirn-bridge`, and `bridge/icon_test.v` finds the mark's contacts on them.

| File | Shows | Used by | Made by | License |
| --- | --- | --- | --- | --- |
| [bridge/icons/icon-32.png](../bridge/icons/icon-32.png) | The mark on an ink tile, 32 px | The bridge's window icon in a Linux title bar and task bar | `just assets` | EUPL 1.2 |
| [bridge/icons/icon-128.png](../bridge/icons/icon-128.png) | The mark on an ink plate with a macOS icon's margins, 128 px | The bridge's Dock icon, whose contacts show the live vote | `just assets` | EUPL 1.2 |

## Fonts

`bridge/main.v` builds these into `gehirn-bridge`; [bridge/fonts/README.md](../bridge/fonts/README.md) gives their sources and how to cut the subset again.

| File | Shows | Used by | Made by | License |
| --- | --- | --- | --- | --- |
| [bridge/fonts/BarlowCondensed-SemiBold.ttf](../bridge/fonts/BarlowCondensed-SemiBold.ttf) | Barlow Condensed SemiBold, the bridge's base face for Latin | The bridge; build.py sets the social card's sentence in it | google/fonts `ofl/barlowcondensed`, unmodified | OFL 1.1, `bridge/fonts/OFL-BarlowCondensed.txt` |
| [bridge/fonts/BarlowCondensed-Black.ttf](../bridge/fonts/BarlowCondensed-Black.ttf) | Barlow Condensed Black | The bridge; GEHIRN in the lockups and the social card's fan project line | google/fonts `ofl/barlowcondensed`, unmodified | OFL 1.1, `bridge/fonts/OFL-BarlowCondensed.txt` |
| [bridge/fonts/ZenOldMincho-Black-subset.ttf](../bridge/fonts/ZenOldMincho-Black-subset.ttf) | Zen Old Mincho Black cut to printable ASCII and the Japanese the bridge draws | The bridge's Japanese, such as 可決 | google/fonts `ofl/zenoldmincho`, subset with pyftsubset as bridge/fonts/README.md shows | OFL 1.1, `bridge/fonts/OFL-ZenOldMincho.txt` |
| [bridge/fonts/DSEG7Classic-BoldItalic.ttf](../bridge/fonts/DSEG7Classic-BoldItalic.ttf) | DSEG7 Classic, a seven segment face | The umbilical's clock on the bridge | keshikan/DSEG release v0.46, unmodified, since DSEG reserves its name | OFL 1.1, `bridge/fonts/OFL-DSEG.txt` |
