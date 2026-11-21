# Meer Theme Manager 3ds (MtM3)

A native macOS app for making Nintendo 3DS HOME Menu themes. It exports the standard files used by
ThemePlaza, Anemone3DS and CHMM2:

| File | What it holds |
|---|---|
| `body_LZ.bin` | Wallpapers, colors, folder/file art and sound effects (LZ11-compressed) |
| `info.smdh` | Name, description, author and 48×48 icon |
| `preview.png` | 412×480 screenshot of both screens |
| `bgm.bcstm` | Looping background music (DSP-ADPCM) |

You never have to make these by hand: MtM3 converts normal pictures and audio for you.

## Build

Requires macOS 14+ and Xcode (or the Command Line Tools).

```bash
./build_app.sh
open "build/Meer Theme Manager 3ds.app"
```

You can also open `Package.swift` in Xcode and run the **MtM3** scheme.

## Features

**Built-in converters (Converter Tools page)**
- Music → BCSTM from MP3, WAV, M4A/AAC, AIFF, FLAC, CAF, with loop point, start trim, fade and normalize
- Sound → BCWAV for sound effects (silence trimmed, volume leveled)
- BCSTM / BCWAV → WAV
- Picture resizer to every 3DS theme size (save as PNG or send straight into the theme)
- Theme extractor: pull wallpapers, icons, music, sounds and colors out of any theme

**Image editor** (click Edit… on any picture)
- Drag to position, pinch/slider zoom, Fill / Fit / Stretch, background fill color
- Rotate 90°, straighten ±45°, flip horizontal/vertical
- Brightness, contrast, saturation, hue, warmth, sharpen, blur, vignette + quick presets
- Real 3DS color preview (16-bit + dithering) and screen guides (3D margins, scroll windows, icon area)
- Export the edited picture as PNG

**Theme editing**
- Top screen: default, solid color (gradient), color + two moving patterns, or a picture (still / slow / fast scroll)
- Bottom screen: default, recolored panels, or a picture (still, slow/fast scroll, page flip, bounce)
- Folder and file icons: colors or your own pictures
- Every interface color group with plain-English labels, hex codes and a draggable wallpaper palette
- Background music with trim, loop point, volume, fades and quality/size control
- Eight custom sound effects
- Live animated preview of both screens (home and folder view)
- Open existing themes (folder, `.zip`, `body_LZ.bin`), export folder or `.zip`, send to CHMM2 over Wi-Fi
- Undo/redo, recent files, color presets, size checks against the 3DS limits

`mtm3-cli` (built alongside the app) converts audio to BCSTM/BCWAV and inspects themes from Terminal.

## Credits

File formats follow Usagi 3DS Theme Editor (MIT, Usagirei) and 3dbrew. The DSP-ADPCM encoder is a port of the
one in VGAudio (MIT, Alex Barney).
