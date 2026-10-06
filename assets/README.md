# Assets

This file is for anyone looking for an image, a recording, an icon or a font in the repository, or about to add, move or remake one. It lists every one of them, wherever it lives: what it shows, where it is used, how it is made and under which license. A commit that adds, moves or remakes an asset changes its row here.

`assets/` holds the brand's masters and the screenshots and recordings the docs show. Every MP4 in the repository, here and in `website/`, is a Git LFS object ([CONTRIBUTING.md](../CONTRIBUTING.md#set-up)); Vercel fetches LFS objects for the website. Files a consumer reads from a fixed place stay there: the website's icons and clips in `website/public/`, which Vite copies into the site Vercel builds from `website/`, and the icons and fonts the bridge builds in with `$embed_file`. `just assets` runs [build.py](build.py), which makes every file whose row says so from the SVG masters; [docs/brand.md](../docs/brand.md#rebuilding-them) gives its numbers and how the masters are drawn.

Everything here is gehirn's own work under the [EUPL 1.2](../LICENSE), except the fonts, which keep the SIL Open Font License 1.1 with its text beside each in `bridge/fonts`. Type outlined into the lockups and set on the social card or in a frame of the bridge comes from those fonts; the OFL does not reach a document made with a font, so those files are EUPL too. Nothing comes from khara or the show: no frame, no audio, no logo and no Matisse typeface ([decisions](../docs/decisions.md#project)).

## Brand

| File | Shows | Used by | Made by | License |
| --- | --- | --- | --- | --- |
| [assets/brand/mark.svg](brand/mark.svg) | The mark, ring and contacts in ink and deep orange, or paper and orange in a dark scheme | docs/brand.md; the source of every icon and of website/public/favicon.svg | Master, drawn on the 16 unit grid of docs/brand.md and shrunk with svgo | EUPL 1.2 |
| [assets/brand/mark-mono.svg](brand/mark-mono.svg) | The mark in one `currentColor` path | Print, stamps and embossing (docs/brand.md) | Master, as mark.svg | EUPL 1.2 |
| [assets/brand/lockup-dark.svg](brand/lockup-dark.svg) | The mark, GEHIRN, ゲヒルン E計画 and the cable on a dark ground | README.md's `<picture>` in a dark scheme, docs/brand.md, the source of social.png | Master, its type outlined with fontTools from Barlow Condensed Black and the full Zen Old Mincho Black by docs/brand.md's numbers, then svgo | EUPL 1.2 |
| [assets/brand/lockup-light.svg](brand/lockup-light.svg) | The lockup on a light ground | README.md's `<picture>` in a light scheme, docs/brand.md | Master, as lockup-dark.svg | EUPL 1.2 |
| [assets/brand/social.png](brand/social.png) | The 1280 by 640 link preview card: the fan project line, the lockup and the README's first sentence between hazard bands | GitHub's social preview, uploaded by hand under Settings, General; website/public/social.png is the same file | `just assets`, from lockup-dark.svg, the sentence under README.md's title and `fan_line` in bridge/draw.v | EUPL 1.2 |

## Screenshots and recordings

| File | Shows | Used by | Made by | License |
| --- | --- | --- | --- | --- |
| [assets/media/magi.gif](media/magi.gif) | MAGI on hosted models refusing the release 1/3 with a person within reach, then passing it 3/3, 800 by 447 | README.md's top; the source of website/public/media/magi.mp4 | The GIF of one `just lineup=magi demo-record` take on 2026-10-05, MAGI on gpt-oss-20b, Jev and llama-3.1-8b-instruct judging the mock's scripted core, cut again from that take's MP4 with scripts/record.sh's GIF filter, without its first 0.33 s, which still showed the goto's verdict | EUPL 1.2 |
| [assets/media/bridge.png](media/bridge.png) | The whole bridge, 1280 by 800, as that take's 否決 lands with the human 1.04 m from the body, the mark's contacts lit with the votes | docs/bridge.md's top; website/public/bridge.png is its copy | A frame the same take saved, as RGB | EUPL 1.2 |
| [assets/media/bridge/magi-refused.png](media/bridge/magi-refused.png) | The MAGI block during a refused release, 決議 否決 1/3 | bridge/README.md's top | A frame of magi.gif's take on 2026-10-05, saved as bridge/README.md's Recording frames does, cropped with ffmpeg around its box in the Layout table | EUPL 1.2 |
| [assets/media/bridge/magi-deliberating.png](media/bridge/magi-deliberating.png) | The MAGI block deliberating on a goto as a 可決 lands | bridge/README.md, 審議中 and a landing ballot | As magi-refused.png | EUPL 1.2 |
| [assets/media/bridge/emergency.png](media/bridge/emergency.png) | The EMERGENCY overlay as the cable is cut, an 800 by 360 cut from the window's middle | bridge/README.md, EMERGENCY | A frame of magi-refused.png's take, cut to 800 by 360 from the middle with ffmpeg | EUPL 1.2 |
| [assets/media/bridge/limit-internal.png](media/bridge/limit-internal.png) | The 活動限界 panel on internal power at 4:53 | bridge/README.md, Seven segment timer | As magi-refused.png | EUPL 1.2 |
| [assets/media/bridge/scene.png](media/bridge/scene.png) | The radar: the body at beacon B1, a human within 2 m, an obstacle and the trail | bridge/README.md, Radar | As magi-refused.png, with the ffmpeg line in Recording frames | EUPL 1.2 |
| [assets/media/bridge/harmonics.png](media/bridge/harmonics.png) | The harmonics panel at 57.9% sync with the dummy plug in the seat | bridge/README.md, Harmonics | As magi-refused.png | EUPL 1.2 |

## Scene recordings

One take of each scene on its world, recorded with `just scene=<id> demo-record` on 2026-10-06, and `ep12-sahaquiel` on 2026-10-07; [docs/scenes.md](../docs/scenes.md#recordings) links them. Episode 13's MP4 lives only as the website's clip, [website/public/media/ep13-iruel.mp4](../website/public/media/ep13-iruel.mp4), and the website plays copies of Episodes 3, 6, 18 and 19, listed under Website, but not yet Episode 12. A copy costs no LFS storage, since Git LFS stores one object per content.

| File | Shows | Used by | Made by | License |
| --- | --- | --- | --- | --- |
| [assets/media/scenes/ep03-cable.mp4](media/scenes/ep03-cable.mp4) | Episode 3's cut cable in Tokyo-3, 69 s with the grace at 8x | docs/scenes.md, Recordings | `just scene=ep03-cable demo-record` on 2026-10-06, unchanged, a Git LFS object | EUPL 1.2 |
| [assets/media/scenes/ep06-yashima.mp4](media/scenes/ep06-yashima.mp4) | Operation Yashima on Mt. Futago, 38 s | docs/scenes.md, Recordings | `just scene=ep06-yashima demo-record` on 2026-10-06, unchanged, a Git LFS object | EUPL 1.2 |
| [assets/media/scenes/ep18-bardiel.mp4](media/scenes/ep18-bardiel.mp4) | Episode 18: Toji on a collision course, the dummy plug's goto toward him refused 0/3 by the course rule, 26 s | docs/scenes.md, Recordings | `just scene=ep18-bardiel demo-record` on 2026-10-06, unchanged, a Git LFS object | EUPL 1.2 |
| [assets/media/scenes/ep19-bench.mp4](media/scenes/ep19-bench.mp4) | Episode 19's benched dummy plug in the Geofront, 40 s | docs/scenes.md, Recordings | `just scene=ep19-bench demo-record` on 2026-10-06, unchanged, a Git LFS object | EUPL 1.2 |
| [assets/media/scenes/ep12-sahaquiel.mp4](media/scenes/ep12-sahaquiel.mp4) | Episode 12: Sahaquiel's landing zone over NERV HQ, the catch refused 0/3 on the landing fact while the armor holds a racing pilot at its rim, the release at Matsushiro and the Angel landing unopposed, 44 s | docs/scenes.md, Recordings | `just scene=ep12-sahaquiel demo-record` on 2026-10-07, unchanged, a Git LFS object | EUPL 1.2 |
| [assets/media/scenes/ep13-iruel-magi.gif](media/scenes/ep13-iruel-magi.gif) | The MAGI block of Episode 13 from the first vote on self_destruct to the last | docs/scenes.md, Recordings | The `gehirn-magi.gif` of the same take, unchanged | EUPL 1.2 |
| [assets/media/scenes/ep03-cable-magi.gif](media/scenes/ep03-cable-magi.gif) | The MAGI block of Episode 3's release after the reconnect | docs/scenes.md, Recordings | The `gehirn-magi.gif` of the same take, unchanged | EUPL 1.2 |
| [assets/media/scenes/ep06-yashima-magi.gif](media/scenes/ep06-yashima-magi.gif) | The MAGI block of Operation Yashima from the first release vote to the last | docs/scenes.md, Recordings | The `gehirn-magi.gif` of the same take, unchanged | EUPL 1.2 |
| [assets/media/scenes/ep19-bench-magi.gif](media/scenes/ep19-bench-magi.gif) | The MAGI block of Episode 19's release vote, which passes at the first try | docs/scenes.md, Recordings | The `gehirn-magi.gif` of the same take, unchanged | EUPL 1.2 |
| [assets/media/scenes/ep12-sahaquiel-magi.gif](media/scenes/ep12-sahaquiel-magi.gif) | The MAGI block of Episode 12's release vote at Matsushiro, which passes at the first try | docs/scenes.md, Recordings | The `gehirn-magi.gif` of the same take, unchanged | EUPL 1.2 |

## Website

Each of these sits in `website/public/`, which the site serves at its root, where `website/index.html`, the manifest or a page in `website/src/routes` names it.

| File | Shows | Used by | Made by | License |
| --- | --- | --- | --- | --- |
| [website/public/favicon.svg](../website/public/favicon.svg) | The mark, following the viewer's scheme | index.html's SVG favicon | `just assets`, a copy of mark.svg | EUPL 1.2 |
| [website/public/favicon.ico](../website/public/favicon.ico) | The mark on an ink tile at 16, 32 and 48 px, as PNG entries | index.html's fallback icon, browsers without SVG favicons | `just assets` | EUPL 1.2 |
| [website/public/favicon-96x96.png](../website/public/favicon-96x96.png) | The mark on an ink tile, 96 px | index.html's PNG favicon, search results | `just assets` | EUPL 1.2 |
| [website/public/apple-touch-icon.png](../website/public/apple-touch-icon.png) | The mark on opaque ink, 180 px | index.html's touch icon on iOS | `just assets` | EUPL 1.2 |
| [website/public/icon-192.png](../website/public/icon-192.png) | The mark on an ink tile, 192 px | site.webmanifest | `just assets` | EUPL 1.2 |
| [website/public/icon-512.png](../website/public/icon-512.png) | The mark on an ink tile, 512 px | site.webmanifest | `just assets` | EUPL 1.2 |
| [website/public/icon-maskable-512.png](../website/public/icon-maskable-512.png) | The mark inside the central 80% circle on a square ink tile, 512 px | site.webmanifest, as the maskable icon Android crops | `just assets` | EUPL 1.2 |
| [website/public/site.webmanifest](../website/public/site.webmanifest) | The web app manifest: the name, the three icons, the theme and background colors | index.html | Written by hand | EUPL 1.2 |
| [website/public/social.png](../website/public/social.png) | The link preview card, as assets/brand/social.png | index.html's `og:image`, the card X and other sites show for a link to the website | `just assets`, which writes the card to both | EUPL 1.2 |
| [website/public/bridge.png](../website/public/bridge.png) | The bridge refusing the release, as assets/media/bridge.png | The landing page's Reading the bridge and the guide's annotated frame, website/src/routes/bridge.tsx | A copy of assets/media/bridge.png: `cp assets/media/bridge.png website/public/bridge.png` | EUPL 1.2 |
| [website/public/media/magi.mp4](../website/public/media/magi.mp4) | MAGI on hosted models refusing the release 1/3 with a person within reach, then passing it 3/3, 800 by 448, 12.7 s | The landing page's opening | assets/media/magi.gif as H.264 with a row of ink below it for an even height: `ffmpeg -i assets/media/magi.gif -vf "pad=800:448:0:0:color=0x040406" -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -movflags +faststart -an website/public/media/magi.mp4`, 320 KB against the GIF's 836 KB | EUPL 1.2 |
| [website/public/media/magi.png](../website/public/media/magi.png) | The refusal, 否決 1/3 | magi.mp4's poster | The GIF's frame at 3 s, cut to 256 colors with ffmpeg's palettegen and paletteuse | EUPL 1.2 |
| [website/public/media/boot.mp4](../website/public/media/boot.mp4) | The demo's first 8 s, from the boot screen to MAGI passing the goto 3/3 | The bridge guide, Watch it run | The frames of one `just demo-record` take on the mock on 2026-10-05, linked aside while it ran since scripts/record.sh removes them, from the first one the bridge drew, encoded as record.sh encodes its MP4: libx264 at crf 20, 1280 by 800, no audio | EUPL 1.2 |
| [website/public/media/boot.png](../website/public/media/boot.png) | The boot screen with its five lines | boot.mp4's poster | A frame of the same take, 1280 by 800, cut to 256 colors | EUPL 1.2 |
| [website/public/media/ep13-iruel.mp4](../website/public/media/ep13-iruel.mp4) | Episode 13's MAGI hack as a scene in NERV HQ's MAGI room, its world `worlds/ep13-iruel.json`, 32 s | The bridge guide, Watch it run; the landing page's scenes | `just scene=ep13-iruel demo-record` on 2026-10-06, unchanged | EUPL 1.2 |
| [website/public/media/ep13-iruel.png](../website/public/media/ep13-iruel.png) | The 3/3 verdict with the armor's refusal of self_destruct, the MAGI room on the radar | ep13-iruel.mp4's poster | The take's last frame, 1280 by 800, cut to 256 colors with ffmpeg's palettegen and paletteuse | EUPL 1.2 |
| [website/public/media/ep03-cable.mp4](../website/public/media/ep03-cable.mp4), [ep06-yashima.mp4](../website/public/media/ep06-yashima.mp4), [ep18-bardiel.mp4](../website/public/media/ep18-bardiel.mp4), [ep19-bench.mp4](../website/public/media/ep19-bench.mp4) | The other four scenes, as under Scene recordings | The landing page's scenes | Copies of assets/media/scenes/, unchanged: `cp assets/media/scenes/<id>.mp4 website/public/media/` | EUPL 1.2 |
| [website/public/media/ep03-cable.png](../website/public/media/ep03-cable.png), [ep06-yashima.png](../website/public/media/ep06-yashima.png), [ep18-bardiel.png](../website/public/media/ep18-bardiel.png), [ep19-bench.png](../website/public/media/ep19-bench.png) | Each scene's end, 1280 by 800 | Each clip's poster | The take's frame 0.4 s before its end, cut to 256 colors: `ffmpeg -sseof -0.4 -i <id>.mp4 -frames:v 1 -vf "split[a][b];[a]palettegen=max_colors=256[p];[b][p]paletteuse" <id>.png` | EUPL 1.2 |

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
