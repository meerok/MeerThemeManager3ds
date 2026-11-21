# 3DS theme file formats (as written by MtM3)

All values are little-endian. Offsets are in hexadecimal.

## body_LZ.bin

`body_LZ.bin` is the theme body compressed with **LZ11** (header byte `0x11`, 24-bit decompressed size; 2/3/4-byte back-references, window 4 KB, max match 0x10110). MtM3 pads the compressed file to a multiple of 4 bytes.

### Decompressed header (0xC4 bytes, data starts at 0xD0)

| Offset | Size | Field |
|---|---|---|
| 00 | 4 | Version (always 1) |
| 05 | 1 | Background music enabled |
| 0C | 4 | Top draw type: 0 default, 1 color, 2 color + pattern, 3 picture |
| 10 | 4 | Top frame type: 0 fast scroll, 1 still, 3 slow scroll |
| 14 | 4 | Offset → top color block |
| 18 | 4 | Offset → top texture (picture, or pattern in mode 2) |
| 1C | 4 | Offset → second top pattern (mode 2, optional) |
| 20 | 4 | Bottom draw type: 0 default, 1 color, 3 picture |
| 24 | 4 | Bottom frame type: 0 fast, 1 still, 2 page flip, 3 slow, 4 bounce |
| 28 | 4 | Offset → bottom texture |
| 2C / 30 | 4 + 4 | Cursor colors enabled / offset |
| 34 / 38 | 4 + 4 | 3D folder colors enabled / offset |
| 3C / 40 / 44 | 4 + 4 + 4 | Folder pictures enabled / closed offset / open offset |
| 48 / 4C | 4 + 4 | 3D file colors enabled / offset |
| 50 / 54 / 58 | 4 + 4 + 4 | File pictures enabled / large offset / small offset |
| 5C / 60 | 4 + 4 | Arrow-button colors enabled / offset |
| 64 / 68 | 4 + 4 | Arrow colors enabled / offset |
| 6C / 70 / 74 | 4 + 4 + 4 | Open/Close colors enabled / open offset / close offset |
| 78 / 7C | 4 + 4 | Software title box: 0 default, 1 colored, 2 hidden / offset |
| 80 / 84 | 4 + 4 | Bottom inner panel colors enabled / offset |
| 88 / 8C | 4 + 4 | Bottom outer frame colors enabled / offset |
| 90 / 94 | 4 + 4 | Folder background colors enabled / offset |
| 98 / 9C | 4 + 4 | Folder arrow colors enabled / offset |
| A0 / A4 | 4 + 4 | Bottom corner button colors enabled / offset |
| A8 / AC | 4 + 4 | Top corner button colors enabled / offset |
| B0 / B4 | 4 + 4 | Demo text colors enabled / offset |
| B8 / BC / C0 | 4 + 4 + 4 | Sound effects enabled / size / offset |

### Color blocks (in file order)

`RGB` = 3 bytes, `RGBA` = 4 bytes, `f32` = float.

| Block | Layout |
|---|---|
| Top background | RGB main, gradient, texture opacity (+ alt opacity, gradient color in mode 2). **Every value is stored as 0–100 %.** |
| Cursor | RGB shading, main, light, glow |
| 3D folder | RGB shading, main, light, shadow |
| 3D file / Arrow button | RGB shading, main, light, RGBA shadow |
| Arrow | RGB border, unpressed, pressed |
| Open / Close | f32 text-shadow offset; RGB pressed, unpressed, light; RGBA shadow; RGB glow, text shadow, text, text pressed, padding |
| Software title | RGB main, light; RGBA shadow; RGB text |
| Inner panel / folder background | RGB highlight, main, border; RGBA glow |
| Outer frame | RGB stripes, main, glow |
| Folder arrow | f32 shadow offset; RGB shading, main, highlight; RGBA shadow; RGB glow, arrow glow, arrow, arrow pressed, padding |
| Bottom corner | RGB border, main, highlight, shadow, icon bottom, icon top, icon text |
| Top corner | RGB main, light, shadow, text |
| Demo text | RGB main, text |

### Textures

Textures are stored in the GPU's **8 × 8 Morton-tiled** order (tiles row by row; inside a tile, the X bits sit at even and the Y bits at odd positions of the index).

- Wallpapers: **RGB565**. MtM3 applies Bayer 8 × 8 ordered dithering by default.
- Folder/file pictures: **BGR888**.
- Top patterns: **A8**, square, rotated 90° counter-clockwise before tiling.

The unused area of each texture (for example 412 × 240 inside 512 × 256) is filled by repeating the edge pixels so filtering never shows seams.

### Sound effect block

`u32 2, u32 0x64`, then eight entries `u32 size, u32 (size ? 0x50 : 1), BCWAV bytes`. Before the 5th entry come 11 `u32` values: `0,100,0,100,100,0,100,100,0,0,0`. Slot order: cursor, launch, open folder, close folder, scroll 1–3, open lid.

## bgm.bcstm

CSTM version 2.1 (0x02010000), DSP-ADPCM, little-endian, three blocks (INFO, SEEK, DATA):

- Interleave: 0x2000 bytes (14,336 samples) per channel per block. The last block is padded to 0x20.
- Stream info includes a region-info reference (none), a track table (one track per stereo pair, volume 0x7F, pan 0x40) and per-channel ADPCM info (16 coefficients, start context, loop context).
- The seek table holds history samples every 14,336 samples.
- **Loop points are aligned** to 14,336 samples by repeating the start of the loop, which is how official tools keep loops seamless.

The block layout follows VGAudio's BCSTM writer.

## Sound effects (BCWAV)

CWAV version 2.1, mono DSP-ADPCM, INFO + DATA blocks; sample data starts 0x20 into DATA.

## info.smdh

`SMDH` magic, 16 × (0x80 short title, 0x100 long description, 0x80 publisher) in UTF-16LE, 0x30 bytes of settings (region-free, visible), 8 reserved bytes, 24 × 24 then 48 × 48 RGB565 Morton-tiled icons. Total 0x36C0 bytes.

## preview.png

412 × 480: the top screen (412 × 240, including the 3D margins) above the bottom screen (320 × 240) centered at x = 46.
