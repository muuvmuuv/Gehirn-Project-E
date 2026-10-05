# The bridge's fonts

`bridge/main.v` builds these into `gehirn-bridge` with `$embed_file`, so the bridge draws the same on every machine and no image needs a font installed. [bridge/README.md](../README.md) explains how the bridge sets them: the fallback chain, the squeeze and the fonts fontstash cannot read. Each is licensed under the SIL Open Font License 1.1, whose text sits beside it; the license lets a font be bundled and embedded with software, free or sold, as long as the font is not sold on its own and its license travels with it.

| File | Font | Source | License |
| --- | --- | --- | --- |
| `BarlowCondensed-SemiBold.ttf`, `BarlowCondensed-Black.ttf` | Barlow Condensed, the base face for Latin | google/fonts `ofl/barlowcondensed`, unmodified | `OFL-BarlowCondensed.txt` |
| `ZenOldMincho-Black-subset.ttf` | Zen Old Mincho Black, for 可決 and the other Japanese, cut to the glyphs the bridge draws | google/fonts `ofl/zenoldmincho`, subset | `OFL-ZenOldMincho.txt` |
| `DSEG7Classic-BoldItalic.ttf` | DSEG7 Classic, the umbilical's seven segment clock | github.com/keshikan/DSEG release v0.46, unmodified | `OFL-DSEG.txt` |

Neither Barlow nor Zen Old Mincho declares a Reserved Font Name, so the subset may keep its name. DSEG does reserve "DSEG", so its file stays exactly as released.

The full Zen Old Mincho Black is 5.4 MB. The subset keeps printable ASCII and the Japanese in `bridge/*.v`, about 100 KB. A string with a character the subset lacks draws that character from Arial Unicode or `VUI_FONT` where the machine has one and leaves it out elsewhere, so cut the subset again whenever the bridge draws new Japanese. fonttools lives in a throwaway virtual environment, never a global install:

```sh
python3 -m venv /tmp/fonttools && /tmp/fonttools/bin/pip install fonttools
curl -fsSLO https://raw.githubusercontent.com/google/fonts/main/ofl/zenoldmincho/ZenOldMincho-Black.ttf
rg -o --no-filename '[^\x00-\x7F]' bridge/*.v | sort -u | tr -d '\n' > /tmp/glyphs.txt
/tmp/fonttools/bin/pyftsubset ZenOldMincho-Black.ttf --text-file=/tmp/glyphs.txt --unicodes=U+0020-007E --output-file=bridge/fonts/ZenOldMincho-Black-subset.ttf
```
