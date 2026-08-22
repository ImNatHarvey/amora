# Brand art

**Both files here are generated placeholders. Replacing them is one file each
and no code or layout change.**

| What | Path | Size | Format |
|---|---|---|---|
| Logo | `apps/mobile/assets/brand/logo.png` | **512 × 512** | PNG, transparent, square |
| Mascot | `apps/mobile/assets/brand/mascot.png` | **512 × 512** | PNG, transparent, square |

## How to swap one

Overwrite the file, keep the name, run the app. Nothing else.

Everything draws through `lib/theme/brand_mark.dart`, which puts the art in a
square box of a fixed size and uses `BoxFit.contain`. So art that is not
square, or is a different pixel size, still lands inside the same box and
nothing around it moves. Square at 512 is the recommendation, not a
requirement — it is simply the shape that wastes no space.

Keep the background transparent. The mark sits on both light and dark surfaces,
and a white plate behind it will show as a white plate in dark mode.

## The launcher icon is separate

It is Android resource art, not a Flutter asset, and it lives at:

```
apps/mobile/android/app/src/main/res/
  mipmap-mdpi/ic_launcher.png              48 × 48
  mipmap-hdpi/ic_launcher.png              72 × 72
  mipmap-xhdpi/ic_launcher.png             96 × 96
  mipmap-xxhdpi/ic_launcher.png           144 × 144
  mipmap-xxxhdpi/ic_launcher.png          192 × 192

  mipmap-mdpi/ic_launcher_foreground.png  108 × 108
  mipmap-hdpi/ic_launcher_foreground.png  162 × 162
  mipmap-xhdpi/ic_launcher_foreground.png 216 × 216
  mipmap-xxhdpi/ic_launcher_foreground.png 324 × 324
  mipmap-xxxhdpi/ic_launcher_foreground.png 432 × 432
```

The `_foreground` set is the adaptive icon's top layer
(`mipmap-anydpi-v26/ic_launcher.xml`); its background is the flat colour
`ic_launcher_background` in `values/colors.xml`, currently `#B4436C` — the seed
the whole `ColorScheme` is generated from.

**The outer 18% of an adaptive icon can be masked away** by whatever shape the
launcher uses, so the foreground art is drawn at 72% scale inside the safe zone.
Art that fills the frame edge to edge will lose its edges on a round-mask
launcher.

Replacing all ten by hand is tedious; `flutter_launcher_icons` generates them
from one 1024 × 1024 source. It is a dev dependency and has not been added —
adding a package needs asking first (`CLAUDE.md`).
