/* MtM3 ThemeKit — 3DS HOME Menu theme engine (JavaScript port of the Swift ThemeKit).
 * Works in Node, the Electron renderer and Web Workers. */
(function (root) {
  'use strict';

  // ───────────────────────── Binary helpers ─────────────────────────
  class ByteWriter {
    constructor(capacity = 1024) { this.buf = new Uint8Array(Math.max(16, capacity)); this.length = 0; }
    get count() { return this.length; }
    ensure(n) {
      if (this.length + n <= this.buf.length) return;
      let cap = this.buf.length * 2;
      while (cap < this.length + n) cap *= 2;
      const nb = new Uint8Array(cap); nb.set(this.buf.subarray(0, this.length)); this.buf = nb;
    }
    u8(v) { this.ensure(1); this.buf[this.length++] = v & 0xFF; }
    u16(v) { this.ensure(2); this.buf[this.length++] = v & 0xFF; this.buf[this.length++] = (v >>> 8) & 0xFF; }
    i16(v) { this.u16(v & 0xFFFF); }
    u32(v) { this.ensure(4); v = v >>> 0; this.buf[this.length++] = v & 0xFF; this.buf[this.length++] = (v >>> 8) & 0xFF; this.buf[this.length++] = (v >>> 16) & 0xFF; this.buf[this.length++] = (v >>> 24) & 0xFF; }
    i32(v) { this.u32(v | 0); }
    f32(v) { const b = new Uint8Array(new Float32Array([v]).buffer); this.append(b); }
    append(bytes) { if (!bytes || !bytes.length) return; this.ensure(bytes.length); this.buf.set(bytes, this.length); this.length += bytes.length; }
    ascii(s) { for (let i = 0; i < s.length; i++) this.u8(s.charCodeAt(i)); }
    zeros(n) { if (n > 0) { this.ensure(n); this.buf.fill(0, this.length, this.length + n); this.length += n; } }
    pad(m) { const r = this.length % m; if (r) this.zeros(m - r); }
    padTo(n) { if (this.length < n) this.zeros(n - this.length); }
    bytes() { return this.buf.slice(0, this.length); }
  }

  class ByteReader {
    constructor(bytes) { this.b = bytes; this.p = 0; this.dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength); }
    get remaining() { return this.b.length - this.p; }
    check(n) { if (this.p < 0 || this.p + n > this.b.length) throw new Error('The file ended unexpectedly (it may be damaged).'); }
    u8() { this.check(1); return this.b[this.p++]; }
    u16() { this.check(2); const v = this.dv.getUint16(this.p, true); this.p += 2; return v; }
    i16() { this.check(2); const v = this.dv.getInt16(this.p, true); this.p += 2; return v; }
    u32() { this.check(4); const v = this.dv.getUint32(this.p, true); this.p += 4; return v; }
    i32() { this.check(4); const v = this.dv.getInt32(this.p, true); this.p += 4; return v; }
    f32() { this.check(4); const v = this.dv.getFloat32(this.p, true); this.p += 4; return v; }
    read(n) { this.check(n); const v = this.b.slice(this.p, this.p + n); this.p += n; return v; }
    ascii(n) { return String.fromCharCode(...this.read(n)); }
    skip(n) { this.check(n); this.p += n; }
    u32At(o) { if (o + 4 > this.b.length) throw new Error('Unexpected end of file'); return this.dv.getUint32(o, true); }
  }

  const CRC_TABLE = (() => { const t = new Uint32Array(256); for (let i = 0; i < 256; i++) { let c = i; for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1); t[i] = c >>> 0; } return t; })();
  function crc32(bytes) { let c = 0xFFFFFFFF; for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; }

  // ───────────────────────── LZ11 ─────────────────────────
  const LZ11 = {
    isCompressed(d) { return d.length >= 4 && d[0] === 0x11; },
    decompress(d) {
      if (d.length < 4 || d[0] !== 0x11) throw new Error('This file is not LZ11-compressed.');
      let p = 4, size = d[1] | (d[2] << 8) | (d[3] << 16);
      if (size === 0) { size = (d[4] | (d[5] << 8) | (d[6] << 16) | (d[7] << 24)) >>> 0; p = 8; }
      if (size > 64 * 1024 * 1024) throw new Error('Decompressed size is unreasonably large.');
      const out = new Uint8Array(size); let o = 0;
      while (o < size) {
        if (p >= d.length) throw new Error('Unexpected end of compressed data');
        const flags = d[p++];
        for (let bit = 0; bit < 8 && o < size; bit++) {
          if (flags & (0x80 >> bit)) {
            const b1 = d[p]; let len, disp;
            switch (b1 >> 4) {
              case 0: len = (((b1 & 0xF) << 4) | (d[p + 1] >> 4)) + 0x11; disp = (((d[p + 1] & 0xF) << 8) | d[p + 2]) + 1; p += 3; break;
              case 1: len = (((b1 & 0xF) << 12) | (d[p + 1] << 4) | (d[p + 2] >> 4)) + 0x111; disp = (((d[p + 2] & 0xF) << 8) | d[p + 3]) + 1; p += 4; break;
              default: len = (b1 >> 4) + 1; disp = (((b1 & 0xF) << 8) | d[p + 1]) + 1; p += 2;
            }
            if (disp > o) throw new Error('Compressed data refers outside the buffer.');
            for (let i = 0; i < len && o < size; i++) { out[o] = out[o - disp]; o++; }
          } else { out[o++] = d[p++]; }
        }
      }
      return out;
    },
    compress(inp) {
      const n = inp.length;
      const w = new ByteWriter(n / 2 + 16);
      if (n <= 0xFFFFFF) { w.u8(0x11); w.u8(n & 0xFF); w.u8((n >> 8) & 0xFF); w.u8((n >> 16) & 0xFF); }
      else { w.u8(0x11); w.u8(0); w.u8(0); w.u8(0); w.u32(n); }
      if (n === 0) return w.bytes();
      const hashBits = 16, head = new Int32Array(1 << hashBits).fill(-1), prev = new Int32Array(n).fill(-1);
      const maxChain = 192, window = 0x1000, maxMatch = 0x10110;
      const hash = (i) => (Math.imul((inp[i] << 16) | (inp[i + 1] << 8) | inp[i + 2], 2654435761 | 0) >>> 0) >>> (32 - hashBits);
      const insert = (i) => { if (i + 2 < n) { const h = hash(i); prev[i] = head[h]; head[h] = i; } };
      let pos = 0;
      while (pos < n) {
        const fi = w.length; w.u8(0); let flags = 0;
        for (let bit = 0; bit < 8; bit++) {
          if (pos >= n) break;
          let bestLen = 0, bestDisp = 0;
          if (pos + 2 < n) {
            const limit = Math.min(maxMatch, n - pos);
            let cand = head[hash(pos)], chain = 0;
            while (cand >= 0 && pos - cand <= window && chain < maxChain) {
              if (bestLen === 0 || inp[cand + bestLen] === inp[pos + bestLen]) {
                let l = 0; while (l < limit && inp[cand + l] === inp[pos + l]) l++;
                if (l > bestLen) { bestLen = l; bestDisp = pos - cand; if (l === limit) break; }
              }
              cand = prev[cand]; chain++;
            }
          }
          if (bestLen >= 3) {
            flags |= 0x80 >> bit;
            const d = bestDisp - 1;
            if (bestLen <= 0x10) { w.u8(((bestLen - 1) << 4) | (d >> 8)); w.u8(d & 0xFF); }
            else if (bestLen <= 0x110) { const l = bestLen - 0x11; w.u8(l >> 4); w.u8(((l & 0xF) << 4) | (d >> 8)); w.u8(d & 0xFF); }
            else { const l = bestLen - 0x111; w.u8(0x10 | (l >> 12)); w.u8((l >> 4) & 0xFF); w.u8(((l & 0xF) << 4) | (d >> 8)); w.u8(d & 0xFF); }
            for (let k = 0; k < bestLen; k++) insert(pos + k);
            pos += bestLen;
          } else { w.u8(inp[pos]); insert(pos); pos++; }
        }
        w.buf[fi] = flags;
      }
      w.pad(4);
      return w.bytes();
    },
  };

  // ───────────────────────── Images & textures ─────────────────────────
  function makeImage(width, height, fill) {
    const px = new Uint8Array(width * height * 3);
    if (fill) for (let i = 0; i < px.length; i += 3) { px[i] = fill[0]; px[i + 1] = fill[1]; px[i + 2] = fill[2]; }
    return { width, height, pixels: px };
  }
  function cropImage(img, w, h) {
    const out = makeImage(w, h);
    for (let y = 0; y < Math.min(h, img.height); y++) for (let x = 0; x < Math.min(w, img.width); x++) {
      const si = (y * img.width + x) * 3, di = (y * w + x) * 3;
      out.pixels[di] = img.pixels[si]; out.pixels[di + 1] = img.pixels[si + 1]; out.pixels[di + 2] = img.pixels[si + 2];
    }
    return out;
  }
  function bleedImage(img, w, h) {
    const out = makeImage(w, h); const cw = Math.min(img.width, w), ch = Math.min(img.height, h);
    for (let y = 0; y < h; y++) { const sy = Math.min(y, ch - 1); for (let x = 0; x < w; x++) {
      const sx = Math.min(x, cw - 1), si = (sy * img.width + sx) * 3, di = (y * w + x) * 3;
      out.pixels[di] = img.pixels[si]; out.pixels[di + 1] = img.pixels[si + 1]; out.pixels[di + 2] = img.pixels[si + 2];
    } }
    return out;
  }
  function grayLevels(img) {
    const n = img.width * img.height, g = new Uint8Array(n);
    for (let i = 0; i < n; i++) g[i] = Math.min(255, Math.floor((img.pixels[i * 3] * 299 + img.pixels[i * 3 + 1] * 587 + img.pixels[i * 3 + 2] * 114) / 1000));
    return g;
  }
  function compact(v) {
    let x = v & 0x55555555; x = (x | (x >>> 1)) & 0x33333333; x = (x | (x >>> 2)) & 0x0F0F0F0F;
    x = (x | (x >>> 4)) & 0x00FF00FF; x = (x | (x >>> 8)) & 0x0000FFFF; return x;
  }
  function coord(j, w) {
    const tpr = Math.max(1, (w + 7) >> 3), within = j % 64, tile = Math.floor(j / 64);
    return [compact(within) + (tile % tpr) * 8, compact(within >>> 1) + Math.floor(tile / tpr) * 8];
  }
  const BAYER = [1,49,13,61,4,52,16,64,33,17,45,29,36,20,48,32,9,57,5,53,12,60,8,56,41,25,37,21,44,28,40,24,3,51,15,63,2,50,14,62,35,19,47,31,34,18,46,30,11,59,7,55,10,58,6,54,43,27,39,23,42,26,38,22];
  function ditherTo565(img) {
    const out = { width: img.width, height: img.height, pixels: new Uint8Array(img.pixels) }, p = img.pixels;
    for (let y = 0; y < img.height; y++) for (let x = 0; x < img.width; x++) {
      const t = BAYER[((y & 7) << 3) + (x & 7)], i = (y * img.width + x) * 3;
      const r = Math.min(255, p[i] + Math.floor(t * 8 / 65)), g = Math.min(255, p[i + 1] + Math.floor(t * 4 / 65)), b = Math.min(255, p[i + 2] + Math.floor(t * 8 / 65));
      out.pixels[i] = (r >> 3) << 3; out.pixels[i + 1] = (g >> 2) << 2; out.pixels[i + 2] = (b >> 3) << 3;
    }
    return out;
  }
  const BPP = { rgb565: 2, bgr888: 3, a8: 1 };
  const Texture = {
    encode(img, format, dither = true) {
      const w = img.width, h = img.height, count = w * h;
      if (format === 'rgb565') {
        const src = dither ? ditherTo565(img) : img, out = new Uint8Array(count * 2), p = src.pixels;
        for (let j = 0; j < count; j++) { const [x, y] = coord(j, w), i = (y * w + x) * 3; const v = ((p[i] >> 3) << 11) | ((p[i + 1] >> 2) << 5) | (p[i + 2] >> 3); out[j * 2] = v & 0xFF; out[j * 2 + 1] = v >> 8; }
        return out;
      }
      if (format === 'bgr888') {
        const out = new Uint8Array(count * 3), p = img.pixels;
        for (let j = 0; j < count; j++) { const [x, y] = coord(j, w), i = (y * w + x) * 3; out[j * 3] = p[i + 2]; out[j * 3 + 1] = p[i + 1]; out[j * 3 + 2] = p[i]; }
        return out;
      }
      // a8 (square, rotated counter-clockwise)
      const gray = grayLevels(img), rot = new Uint8Array(count);
      for (let i = 0; i < w; i++) for (let j = 0; j < h; j++) rot[j * w + i] = gray[(w - 1 - i) * w + j];
      const out = new Uint8Array(count);
      for (let k = 0; k < count; k++) { const [x, y] = coord(k, w); out[k] = rot[y * w + x]; }
      return out;
    },
    decode(data, w, h, format) {
      const count = w * h, img = makeImage(w, h), p = img.pixels;
      if (data.length < count * BPP[format]) throw new Error('Texture data is truncated');
      if (format === 'rgb565') {
        for (let j = 0; j < count; j++) { const v = data[j * 2] | (data[j * 2 + 1] << 8), [x, y] = coord(j, w), i = (y * w + x) * 3;
          const r = (v >> 11) & 31, g = (v >> 5) & 63, b = v & 31; p[i] = (r << 3) | (r >> 2); p[i + 1] = (g << 2) | (g >> 4); p[i + 2] = (b << 3) | (b >> 2); }
      } else if (format === 'bgr888') {
        for (let j = 0; j < count; j++) { const [x, y] = coord(j, w), i = (y * w + x) * 3; p[i] = data[j * 3 + 2]; p[i + 1] = data[j * 3 + 1]; p[i + 2] = data[j * 3]; }
      } else {
        const rot = new Uint8Array(count);
        for (let k = 0; k < count; k++) { const [x, y] = coord(k, w); rot[y * w + x] = data[k]; }
        for (let i = 0; i < w; i++) for (let j = 0; j < h; j++) { const v = rot[j * w + i], di = ((w - 1 - i) * w + j) * 3; p[di] = v; p[di + 1] = v; p[di + 2] = v; }
      }
      return img;
    },
    ditherTo565,
  };

  // ───────────────────────── Theme model ─────────────────────────
  const Limits = { maxCompressedBody: 0x150000, maxBGM: 0x337000, maxSoundEffects: 0x2DC00 };

  // Field lists in binary order. Types: rgb, rgba, f32, pad (rgb padding).
  const SCHEMA = {
    cursor: [['shading', 'rgb'], ['main', 'rgb'], ['light', 'rgb'], ['glow', 'rgb']],
    folder: [['shading', 'rgb'], ['main', 'rgb'], ['light', 'rgb'], ['shadow', 'rgb']],
    file: [['shading', 'rgb'], ['main', 'rgb'], ['light', 'rgb'], ['shadow', 'rgba']],
    arrowButton: [['shading', 'rgb'], ['main', 'rgb'], ['light', 'rgb'], ['shadow', 'rgba']],
    arrow: [['border', 'rgb'], ['unpressed', 'rgb'], ['pressed', 'rgb']],
    open: [['textShadowPosition', 'f32'], ['pressed', 'rgb'], ['unpressed', 'rgb'], ['light', 'rgb'], ['shadow', 'rgba'], ['glow', 'rgb'], ['textShadow', 'rgb'], ['textUnpressed', 'rgb'], ['textPressed', 'rgb'], ['padding', 'rgb']],
    gameText: [['main', 'rgb'], ['light', 'rgb'], ['shadow', 'rgba'], ['text', 'rgb']],
    inner: [['highlight', 'rgb'], ['main', 'rgb'], ['border', 'rgb'], ['glow', 'rgba']],
    outer: [['stripes', 'rgb'], ['main', 'rgb'], ['glow', 'rgb']],
    folderArrow: [['arrowShadowPosition', 'f32'], ['shading', 'rgb'], ['main', 'rgb'], ['highlight', 'rgb'], ['shadow', 'rgba'], ['glow', 'rgb'], ['arrowGlow', 'rgb'], ['arrowUnpressed', 'rgb'], ['arrowPressed', 'rgb'], ['padding', 'rgb']],
    bottomCorner: [['border', 'rgb'], ['main', 'rgb'], ['highlight', 'rgb'], ['baseShadow', 'rgb'], ['iconBottom', 'rgb'], ['iconTop', 'rgb'], ['iconText', 'rgb']],
    topCorner: [['main', 'rgb'], ['light', 'rgb'], ['shadow', 'rgb'], ['text', 'rgb']],
    demoText: [['main', 'rgb'], ['text', 'rgb']],
  };
  // [colorKey, schema, headerOffsetField]
  const COLOR_BLOCKS = [
    ['cursor', 'cursor', 0x30], ['folder', 'folder', 0x38], ['file', 'file', 0x4C], ['arrowButton', 'arrowButton', 0x60],
    ['arrow', 'arrow', 0x68], ['open', 'open', 0x70], ['close', 'open', 0x74], ['gameText', 'gameText', 0x7C],
    ['bottomInner', 'inner', 0x84], ['bottomOuter', 'outer', 0x8C], ['folderBackground', 'inner', 0x94],
    ['folderArrow', 'folderArrow', 0x9C], ['bottomCorner', 'bottomCorner', 0xA4], ['topCorner', 'topCorner', 0xAC], ['demoText', 'demoText', 0xB4],
  ];

  function defaultColors() {
    const oc = (pos) => ({ textShadowPosition: pos, pressed: [200, 200, 208], unpressed: [245, 245, 248], light: [255, 255, 255], shadow: [0, 0, 0, 80], glow: [255, 255, 255], textShadow: [255, 255, 255], textUnpressed: [60, 60, 70], textPressed: [28, 140, 230], padding: [0, 0, 0] });
    return {
      topBackground: { main: [204, 204, 217], gradient: 64, textureOpacity: 128, alternateOpacity: 128, gradientColor: 255 },
      cursor: { shading: [8, 110, 180], main: [28, 176, 255], light: [150, 222, 255], glow: [70, 200, 255] },
      folder: { shading: [196, 142, 26], main: [250, 206, 82], light: [255, 236, 160], shadow: [110, 80, 20] },
      file: { shading: [176, 176, 186], main: [238, 238, 242], light: [255, 255, 255], shadow: [0, 0, 0, 64] },
      arrowButton: { shading: [190, 190, 200], main: [242, 242, 246], light: [255, 255, 255], shadow: [0, 0, 0, 64] },
      arrow: { border: [90, 90, 104], unpressed: [140, 140, 152], pressed: [28, 176, 255] },
      open: oc(-1.25), close: oc(1.0),
      gameText: { main: [250, 250, 252], light: [255, 255, 255], shadow: [0, 0, 0, 60], text: [50, 50, 60] },
      bottomInner: { highlight: [127, 127, 127], main: [223, 220, 215], border: [234, 234, 234], glow: [63, 63, 63, 255] },
      bottomOuter: { stripes: [208, 208, 216], main: [226, 226, 234], glow: [227, 228, 233] },
      folderBackground: { highlight: [127, 127, 127], main: [223, 220, 215], border: [234, 234, 234], glow: [63, 63, 63, 255] },
      folderArrow: { arrowShadowPosition: -1.25, shading: [200, 200, 208], main: [245, 245, 248], highlight: [255, 255, 255], shadow: [0, 0, 0, 100], glow: [255, 255, 255], arrowGlow: [255, 255, 255], arrowUnpressed: [90, 90, 104], arrowPressed: [28, 140, 230], padding: [0, 0, 0] },
      bottomCorner: { border: [170, 170, 180], main: [240, 240, 244], highlight: [255, 255, 255], baseShadow: [39, 35, 49], iconBottom: [110, 110, 124], iconTop: [150, 150, 164], iconText: [39, 35, 49] },
      topCorner: { main: [240, 240, 244], light: [244, 226, 245], shadow: [39, 35, 49], text: [60, 60, 70] },
      demoText: { main: [250, 250, 252], text: [50, 50, 60] },
    };
  }

  // Draw types: top 0 none / 1 color / 2 color+pattern / 3 picture. Frame: 0 fast, 1 still, 3 slow (+2 page, 4 bounce on bottom)
  function defaultFlags() {
    return { backgroundMusic: false, topDrawType: 0, topFrameType: 1, bottomDrawType: 0, bottomFrameType: 1,
      cursorColor: false, folderColor: false, folderTexture: false, fileColor: false, fileTexture: false, arrowButtonColor: false,
      arrowColor: false, openCloseColor: false, gameTextDrawType: 0, bottomInnerColor: false, bottomOuterColor: false,
      folderBackgroundColor: false, folderArrowColor: false, bottomCornerColor: false, topCornerColor: false, demoTextColor: false, soundEffects: false };
  }
  function newTheme() { return { flags: defaultFlags(), colors: defaultColors(), textures: {}, soundEffectData: new Uint8Array(0), ditherBackgrounds: true }; }

  const SLOTS = {
    top: 'rgb565', topPattern: 'a8', topAltPattern: 'a8', bottom: 'rgb565',
    folderClosed: 'bgr888', folderOpen: 'bgr888', fileLarge: 'bgr888', fileSmall: 'bgr888',
  };
  const scrolls = (frame) => frame !== 1;
  const Geometry = {
    canvas(slot, f) {
      switch (slot) {
        case 'top': return scrolls(f.topFrameType) ? [1024, 256] : [512, 256];
        case 'bottom': return f.bottomFrameType !== 1 ? [1024, 256] : [512, 256];
        case 'topPattern': case 'topAltPattern': return [64, 64];
        case 'folderClosed': case 'folderOpen': return [128, 64];
        case 'fileLarge': return [64, 128];
        case 'fileSmall': return [32, 64];
      }
    },
    visible(slot, f) {
      if (slot === 'top') return scrolls(f.topFrameType) ? [1008, 240] : [412, 240];
      if (slot === 'bottom') { const t = f.bottomFrameType; return t === 1 ? [320, 240] : (t === 2 || t === 4) ? [960, 240] : [1008, 240]; }
      return Geometry.canvas(slot, f);
    },
  };

  const inflate100 = (v) => Math.min(255, Math.floor(v * 255 / 100));
  const deflate100 = (v) => Math.min(100, Math.floor(v * 100 / 255));

  function writeColorBlock(w, schema, obj) {
    for (const [k, t] of SCHEMA[schema]) {
      const v = obj[k];
      if (t === 'f32') w.f32(v);
      else if (t === 'rgba') { w.u8(v[0]); w.u8(v[1]); w.u8(v[2]); w.u8(v[3]); }
      else { const c = v || [0, 0, 0]; w.u8(c[0]); w.u8(c[1]); w.u8(c[2]); }
    }
  }
  function readColorBlock(r, schema) {
    const o = {};
    for (const [k, t] of SCHEMA[schema]) {
      if (t === 'f32') o[k] = r.f32();
      else if (t === 'rgba') o[k] = [r.u8(), r.u8(), r.u8(), r.u8()];
      else o[k] = [r.u8(), r.u8(), r.u8()];
    }
    return o;
  }

  function fitTexture(img, slot, f) {
    const [cw, ch] = Geometry.canvas(slot, f);
    if (img.width === cw && img.height === ch) return img;
    return bleedImage(cropImage(img, Math.min(img.width, cw), Math.min(img.height, ch)), cw, ch);
  }

  const Theme = {
    create: newTheme,
    defaultColors, defaultFlags,
    read(raw) {
      const data = LZ11.isCompressed(raw) ? LZ11.decompress(raw) : raw;
      if (data.length < 0xC4) throw new Error('This body file is too small to be a theme.');
      const r = new ByteReader(data);
      if (r.u32At(0) !== 1) throw new Error('This is not a 3DS theme body (version field is not 1).');
      const u = (o) => r.u32At(o), flag = (o) => u(o) !== 0;
      const t = newTheme(), f = t.flags;
      f.backgroundMusic = data[5] !== 0;
      f.topDrawType = [0, 1, 2, 3].includes(u(0x0C)) ? u(0x0C) : 0;
      f.topFrameType = [0, 1, 3].includes(u(0x10)) ? u(0x10) : 1;
      f.bottomDrawType = [0, 1, 3].includes(u(0x20)) ? u(0x20) : 0;
      f.bottomFrameType = [0, 1, 2, 3, 4].includes(u(0x24)) ? u(0x24) : 1;
      f.cursorColor = flag(0x2C); f.folderColor = flag(0x34); f.folderTexture = flag(0x3C); f.fileColor = flag(0x48);
      f.fileTexture = flag(0x50); f.arrowButtonColor = flag(0x5C); f.arrowColor = flag(0x64); f.openCloseColor = flag(0x6C);
      f.gameTextDrawType = [0, 1, 2].includes(u(0x78)) ? u(0x78) : 0;
      f.bottomInnerColor = flag(0x80); f.bottomOuterColor = flag(0x88); f.folderBackgroundColor = flag(0x90);
      f.folderArrowColor = flag(0x98); f.bottomCornerColor = flag(0xA0); f.topCornerColor = flag(0xA8);
      f.demoTextColor = flag(0xB0); f.soundEffects = flag(0xB8);
      const at = (field, fn) => { try { const o = u(field); if (o <= 0 || o >= data.length) return null; const rr = new ByteReader(data); rr.p = o; return fn(rr); } catch (e) { return null; } };
      const tb = at(0x14, (rr) => {
        const m = [rr.u8(), rr.u8(), rr.u8()].map(inflate100), o = { main: m, gradient: inflate100(rr.u8()), textureOpacity: inflate100(rr.u8()), alternateOpacity: 128, gradientColor: 255 };
        if (f.topDrawType === 2) { o.alternateOpacity = inflate100(rr.u8()); o.gradientColor = inflate100(rr.u8()); }
        return o;
      });
      if (tb) t.colors.topBackground = tb;
      for (const [key, schema, field] of COLOR_BLOCKS) { const v = at(field, (rr) => readColorBlock(rr, schema)); if (v) t.colors[key] = v; }
      const tex = (off, w, h, fmt) => { const len = w * h * BPP[fmt]; if (off <= 0 || off + len > data.length) return null; try { return Texture.decode(data.subarray(off, off + len), w, h, fmt); } catch (e) { return null; } };
      if (f.topDrawType === 3) { const [w, h] = Geometry.canvas('top', f); t.textures.top = tex(u(0x18), w, h, 'rgb565'); }
      if (f.topDrawType === 2) { t.textures.topPattern = tex(u(0x18), 64, 64, 'a8'); t.textures.topAltPattern = tex(u(0x1C), 64, 64, 'a8'); }
      if (f.bottomDrawType === 3) { const [w, h] = Geometry.canvas('bottom', f); t.textures.bottom = tex(u(0x28), w, h, 'rgb565'); }
      if (f.folderTexture) { t.textures.folderClosed = tex(u(0x40), 128, 64, 'bgr888'); t.textures.folderOpen = tex(u(0x44), 128, 64, 'bgr888'); }
      if (f.fileTexture) { t.textures.fileLarge = tex(u(0x54), 64, 128, 'bgr888'); t.textures.fileSmall = tex(u(0x58), 32, 64, 'bgr888'); }
      for (const k of Object.keys(t.textures)) if (!t.textures[k]) delete t.textures[k];
      const sl = u(0xBC), so = u(0xC0);
      if (sl > 0 && so > 0 && so + sl <= data.length) t.soundEffectData = data.slice(so, so + sl);
      return t;
    },

    writeBody(t) {
      const f = t.flags, c = t.colors, x = t.textures;
      const w = new ByteWriter(1200000);
      w.zeros(0xD0);
      const off = {};
      const ext = f.topDrawType === 2;
      off.top = w.count;
      const tb = c.topBackground;
      w.u8(deflate100(tb.main[0])); w.u8(deflate100(tb.main[1])); w.u8(deflate100(tb.main[2]));
      w.u8(deflate100(tb.gradient)); w.u8(deflate100(tb.textureOpacity));
      if (ext) { w.u8(deflate100(tb.alternateOpacity)); w.u8(deflate100(tb.gradientColor)); }
      for (const [key, schema, field] of COLOR_BLOCKS) { off[field] = w.count; writeColorBlock(w, schema, c[key]); }
      const o = { tex: 0, texExt: 0, bottom: 0, fc: 0, fo: 0, fl: 0, fs: 0 };
      let topDraw = f.topDrawType, bottomDraw = f.bottomDrawType, folderTex = f.folderTexture, fileTex = f.fileTexture;
      if (f.topDrawType === 3) {
        if (x.top) { o.tex = w.count; w.append(Texture.encode(fitTexture(x.top, 'top', f), 'rgb565', t.ditherBackgrounds !== false)); } else topDraw = 0;
      } else if (f.topDrawType === 2) {
        o.tex = w.count; w.append(Texture.encode(fitTexture(x.topPattern || DEFAULT_PATTERN, 'topPattern', f), 'a8'));
        if (x.topAltPattern) { o.texExt = w.count; w.append(Texture.encode(fitTexture(x.topAltPattern, 'topAltPattern', f), 'a8')); }
      }
      if (f.bottomDrawType === 3) {
        if (x.bottom) { o.bottom = w.count; w.append(Texture.encode(fitTexture(x.bottom, 'bottom', f), 'rgb565', t.ditherBackgrounds !== false)); } else bottomDraw = 0;
      }
      if (f.folderTexture) {
        if (x.folderClosed && x.folderOpen) { o.fc = w.count; w.append(Texture.encode(fitTexture(x.folderClosed, 'folderClosed', f), 'bgr888')); o.fo = w.count; w.append(Texture.encode(fitTexture(x.folderOpen, 'folderOpen', f), 'bgr888')); }
        else folderTex = false;
      }
      if (f.fileTexture) {
        if (x.fileLarge && x.fileSmall) { o.fl = w.count; w.append(Texture.encode(fitTexture(x.fileLarge, 'fileLarge', f), 'bgr888')); o.fs = w.count; w.append(Texture.encode(fitTexture(x.fileSmall, 'fileSmall', f), 'bgr888')); }
        else fileTex = false;
      }
      const sfx = f.soundEffects ? (t.soundEffectData || new Uint8Array(0)) : new Uint8Array(0);
      const oSfx = w.count; w.append(sfx); w.pad(0x10);

      const b = (v) => (v ? 1 : 0), h = new ByteWriter(0xD0);
      h.u32(1); h.u8(0); h.u8(b(f.backgroundMusic)); h.u8(0); h.u8(0); h.u32(0);
      h.u32(topDraw); h.u32(f.topFrameType); h.u32(off.top); h.u32(o.tex); h.u32(o.texExt);
      h.u32(bottomDraw); h.u32(f.bottomFrameType); h.u32(o.bottom);
      h.u32(b(f.cursorColor)); h.u32(off[0x30]);
      h.u32(b(f.folderColor)); h.u32(off[0x38]);
      h.u32(b(folderTex)); h.u32(o.fc); h.u32(o.fo);
      h.u32(b(f.fileColor)); h.u32(off[0x4C]);
      h.u32(b(fileTex)); h.u32(o.fl); h.u32(o.fs);
      h.u32(b(f.arrowButtonColor)); h.u32(off[0x60]);
      h.u32(b(f.arrowColor)); h.u32(off[0x68]);
      h.u32(b(f.openCloseColor)); h.u32(off[0x70]); h.u32(off[0x74]);
      h.u32(f.gameTextDrawType); h.u32(off[0x7C]);
      h.u32(b(f.bottomInnerColor)); h.u32(off[0x84]);
      h.u32(b(f.bottomOuterColor)); h.u32(off[0x8C]);
      h.u32(b(f.folderBackgroundColor)); h.u32(off[0x94]);
      h.u32(b(f.folderArrowColor)); h.u32(off[0x9C]);
      h.u32(b(f.bottomCornerColor)); h.u32(off[0xA4]);
      h.u32(b(f.topCornerColor)); h.u32(off[0xAC]);
      h.u32(b(f.demoTextColor)); h.u32(off[0xB4]);
      h.u32(b(f.soundEffects && sfx.length > 0)); h.u32(sfx.length); h.u32(oSfx);
      if (h.count !== 0xC4) throw new Error('header size mismatch');
      const out = w.bytes(); out.set(h.bytes(), 0);
      return out;
    },
    writeCompressedBody(t) { return LZ11.compress(Theme.writeBody(t)); },
  };

  const DEFAULT_PATTERN = (() => { const img = makeImage(64, 64); for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) { const v = Math.floor((x + y) / 8) % 2 === 0 ? 255 : 90, i = (y * 64 + x) * 3; img.pixels[i] = v; img.pixels[i + 1] = v; img.pixels[i + 2] = v; } return img; })();

  // ───────────────────────── SMDH ─────────────────────────
  function defaultIcon(size) {
    const img = makeImage(size, size);
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) { const t = y / size, i = (y * size + x) * 3; img.pixels[i] = 40 + 60 * t | 0; img.pixels[i + 1] = 140 + 50 * t | 0; img.pixels[i + 2] = 230 - 30 * t | 0; }
    return img;
  }
  function downscale(img, size) {
    const out = makeImage(size, size), sx = img.width / size, sy = img.height / size;
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
      const x0 = Math.floor(x * sx), x1 = Math.max(x0 + 1, Math.floor((x + 1) * sx)), y0 = Math.floor(y * sy), y1 = Math.max(y0 + 1, Math.floor((y + 1) * sy));
      let r = 0, g = 0, b = 0, n = 0;
      for (let yy = y0; yy < Math.min(y1, img.height); yy++) for (let xx = x0; xx < Math.min(x1, img.width); xx++) { const i = (yy * img.width + xx) * 3; r += img.pixels[i]; g += img.pixels[i + 1]; b += img.pixels[i + 2]; n++; }
      n = Math.max(n, 1); const o = (y * size + x) * 3; out.pixels[o] = r / n | 0; out.pixels[o + 1] = g / n | 0; out.pixels[o + 2] = b / n | 0;
    }
    return out;
  }
  const SMDH = {
    create() { return { titles: Array.from({ length: 16 }, () => ({ short: '', long: '', publisher: '' })), settings: null, largeIcon: defaultIcon(48), smallIcon: defaultIcon(24) }; },
    primary(s) { if (s.titles[1].short) return s.titles[1]; return s.titles.find((t) => t.short) || { short: '', long: '', publisher: '' }; },
    setAll(s, name, desc, author) { s.titles = Array.from({ length: 16 }, () => ({ short: name.slice(0, 64), long: desc.slice(0, 128), publisher: author.slice(0, 64) })); },
    read(bytes) {
      if (bytes.length < 0x36C0) throw new Error('info.smdh is too small.');
      const r = new ByteReader(bytes);
      if (r.ascii(4) !== 'SMDH') throw new Error('This is not an SMDH file.');
      r.skip(4);
      const rd = (n) => { const raw = r.read(n); let s = ''; for (let i = 0; i + 1 < raw.length; i += 2) { const u = raw[i] | (raw[i + 1] << 8); if (!u) break; s += String.fromCharCode(u); } return s; };
      const titles = []; for (let i = 0; i < 16; i++) titles.push({ short: rd(0x80), long: rd(0x100), publisher: rd(0x80) });
      const settings = r.read(0x30); r.skip(8);
      const smallIcon = Texture.decode(r.read(24 * 24 * 2), 24, 24, 'rgb565');
      const largeIcon = Texture.decode(r.read(48 * 48 * 2), 48, 48, 'rgb565');
      return { titles, settings, largeIcon, smallIcon };
    },
    write(s) {
      const w = new ByteWriter(0x36C0);
      w.ascii('SMDH'); w.u16(0); w.u16(0);
      const wr = (str, n) => { const units = []; for (let i = 0; i < str.length && units.length * 2 < n - 2; i++) units.push(str.charCodeAt(i)); for (const u of units) w.u16(u); w.zeros(n - units.length * 2); };
      for (let i = 0; i < 16; i++) { const t = s.titles[i] || { short: '', long: '', publisher: '' }; wr(t.short, 0x80); wr(t.long, 0x100); wr(t.publisher, 0x80); }
      if (s.settings && s.settings.length === 0x30) w.append(s.settings);
      else { w.zeros(16); w.u32(0x7FFFFFFF); w.zeros(12); w.u32(1); w.zeros(4); w.f32(0); w.u32(0); }
      w.zeros(8);
      w.append(Texture.encode(s.smallIcon && s.smallIcon.width === 24 ? s.smallIcon : downscale(s.largeIcon, 24), 'rgb565', false));
      w.append(Texture.encode(s.largeIcon, 'rgb565', false));
      return w.bytes();
    },
    defaultIcon, downscale,
  };

  // ───────────────────────── DSP-ADPCM ─────────────────────────
  const clamp16 = (v) => (v > 32767 ? 32767 : v < -32768 ? -32768 : v);
  const clamp4 = (v) => (v > 7 ? 7 : v < -8 ? -8 : v);
  const SN = [0, 1, 2, 3, 4, 5, 6, 7, -8, -7, -6, -5, -4, -3, -2, -1];
  const s2nib = (n) => 16 * Math.floor(n / 14) + (n % 14 === 0 ? 0 : (n % 14) + 2);
  const s2bytes = (n) => (s2nib(n) + 1) >> 1;
  const f32 = Math.fround;
  const tdiv = (a, b) => Math.trunc(a / b);

  const DSP = {
    sampleCountToByteCount: s2bytes,
    decode(adpcm, coefs, count, h1 = 0, h2 = 0) {
      const pcm = new Int16Array(count); let ii = 0, o = 0;
      const frames = Math.ceil(count / 14);
      for (let fr = 0; fr < frames; fr++) {
        if (ii >= adpcm.length) break;
        const ps = adpcm[ii++], scale = (1 << (ps & 0xF)) * 2048, pred = (ps >> 4) & 0xF;
        const c1 = coefs[Math.min(pred * 2, 15)], c2 = coefs[Math.min(pred * 2 + 1, 15)];
        const n = Math.min(14, count - o);
        for (let s = 0; s < n; s++) {
          if (ii >= adpcm.length) break;
          let nib; if (s % 2 === 0) nib = SN[adpcm[ii] >> 4]; else { nib = SN[adpcm[ii] & 0xF]; ii++; }
          const v = clamp16(Math.floor((scale * nib + c1 * h1 + c2 * h2 + 1024) / 2048));
          h2 = h1; h1 = v; pcm[o++] = v;
        }
      }
      return pcm;
    },
    encode(pcm, coefs) {
      const n = pcm.length, adpcm = new Uint8Array(s2bytes(n));
      const buf = new Int32Array(16);
      const pcmOut = Array.from({ length: 8 }, () => new Int32Array(16)), adOut = Array.from({ length: 8 }, () => new Int32Array(14));
      const scales = new Int32Array(8), dist = new Float64Array(8);
      const frames = Math.ceil(n / 14);
      for (let fr = 0; fr < frames; fr++) {
        const tc = Math.min(n - fr * 14, 14);
        for (let i = 0; i < 14; i++) buf[2 + i] = i < tc ? pcm[fr * 14 + i] : 0;
        for (let i = 0; i < 8; i++) {
          const r = encodeCoef(buf, coefs[i * 2], coefs[i * 2 + 1], pcmOut[i], adOut[i]);
          scales[i] = r[0]; dist[i] = r[1];
        }
        let best = 0, mn = Infinity;
        for (let i = 0; i < 8; i++) if (dist[i] < mn) { mn = dist[i]; best = i; }
        for (let s = 0; s < 14; s++) buf[s + 2] = pcmOut[best][s + 2];
        const frame = [((best << 4) | (scales[best] & 0xF)) & 0xFF];
        for (let i = 0; i < 7; i++) frame.push(((adOut[best][i * 2] << 4) | (adOut[best][i * 2 + 1] & 0xF)) & 0xFF);
        const nb = s2bytes(tc);
        for (let b = 0; b < nb; b++) adpcm[fr * 8 + b] = frame[b];
        buf[0] = buf[14]; buf[1] = buf[15];
      }
      return adpcm;
    },
    calculateCoefficients: calcCoefs,
  };

  function encodeCoef(pin, c0, c1, pout, aout) {
    let maxD = 0;
    pout[0] = pin[0]; pout[1] = pin[1];
    for (let s = 0; s < 14; s++) {
      const pred = tdiv(pin[s] * c1 + pin[s + 1] * c0, 2048);
      const d = clamp16(pin[s + 2] - pred);
      if (Math.abs(d) > Math.abs(maxD)) maxD = d;
    }
    let sp = 0;
    while (sp <= 12 && (maxD > 7 || maxD < -8)) { maxD = tdiv(maxD, 2); sp++; }
    sp = sp <= 1 ? -1 : sp - 2;
    let total, maxO;
    const half = f32(0.4999999);
    do {
      sp++;
      const scale = (1 << sp) * 2048;
      total = 0; maxO = 0;
      for (let s = 0; s < 14; s++) {
        const inp = pin[s + 2] * 2048;
        const pred = pout[s] * c1 + pout[s + 1] * c0;
        const dist = inp - pred;
        const q = f32(f32(dist) / f32(scale));
        const un = dist > 0 ? Math.trunc(q + half) : Math.trunc(q - half);
        const smp = clamp4(un);
        if (smp !== un) { const ov = Math.abs(un - smp); if (ov > maxO) maxO = ov; }
        aout[s] = smp;
        pout[s + 2] = clamp16(Math.floor((pred + smp * scale + 1024) / 2048));
        const a = pin[s + 2] - pout[s + 2]; total += a * a;
      }
      for (let x = maxO + 8; x > 256; x >>= 1) { sp++; if (sp >= 12) sp = 11; }
    } while (sp < 12 && maxO > 1);
    return [sp, total];
  }

  function calcCoefs(src) {
    const fc = Math.ceil(src.length / 14);
    const hist = new Float64Array(28);
    let vec1 = [0, 0, 0]; const buffer = [0, 0, 0];
    const mtx = [[0, 0, 0], [0, 0, 0], [0, 0, 0]], idx = [0, 0, 0];
    const records = Array.from({ length: Math.max(1, fc * 2) }, () => [0, 0, 0]);
    let rc = 0;
    const best = Array.from({ length: 8 }, () => [0, 0, 0]);
    const ipm = (v, p) => { for (let i = 0; i < 3; i++) { v[i] = 0; for (let x = 0; x < 14; x++) v[i] -= p[14 + x - i] * p[14 + x]; } };
    const opm = (m, p) => { for (let x = 1; x <= 2; x++) for (let y = 1; y <= 2; y++) { m[x][y] = 0; for (let z = 0; z < 14; z++) m[x][y] += p[14 + z - x] * p[14 + z - y]; } };
    const analyze = (m, vi, rec) => {
      for (let x = 1; x <= 2; x++) { const val = Math.max(Math.abs(m[x][1]), Math.abs(m[x][2])); if (val < Number.MIN_VALUE) return true; rec[x] = 1 / val; }
      let mi = 0;
      for (let i = 1; i <= 2; i++) {
        for (let x = 1; x < i; x++) { let t = m[x][i]; for (let y = 1; y < x; y++) t -= m[x][y] * m[y][i]; m[x][i] = t; }
        let val = 0;
        for (let x = i; x <= 2; x++) { let t = m[x][i]; for (let y = 1; y < i; y++) t -= m[x][y] * m[y][i]; m[x][i] = t; t = Math.abs(t) * rec[x]; if (t >= val) { val = t; mi = x; } }
        if (mi !== i) { for (let y = 1; y <= 2; y++) { const t = m[mi][y]; m[mi][y] = m[i][y]; m[i][y] = t; } rec[mi] = rec[i]; }
        vi[i] = mi;
        if (i !== 2) { const t = 1 / m[i][i]; for (let x = i + 1; x <= 2; x++) m[x][i] *= t; }
      }
      let mn = 1e10, mx = 0;
      for (let i = 1; i <= 2; i++) { const t = Math.abs(m[i][i]); if (t < mn) mn = t; if (t > mx) mx = t; }
      return mn / mx < 1e-10;
    };
    const bidi = (m, vi, v) => {
      let x = 0;
      for (let i = 1; i <= 2; i++) { const index = vi[i]; let t = v[index]; v[index] = v[i]; if (x !== 0) { for (let y = x; y <= i - 1; y++) t -= v[y] * m[i][y]; } else if (t !== 0) x = i; v[i] = t; }
      for (let i = 2; i > 0; i--) { let t = v[i]; for (let y = i + 1; y <= 2; y++) t -= v[y] * m[i][y]; v[i] = t / m[i][i]; }
      v[0] = 1;
    };
    const qmerge = (v) => { const v2 = v[2], t = 1 - v2 * v2; if (t === 0) return true; const v0 = (v[0] - v2 * v2) / t, v1 = (v[1] - v[1] * v2) / t; v[0] = v0; v[1] = v1; return Math.abs(v1) > 1; };
    const finish = (inr, outr) => { for (let z = 1; z <= 2; z++) { if (inr[z] >= 1) inr[z] = 0.9999999999; else if (inr[z] <= -1) inr[z] = -0.9999999999; } outr[0] = 1; outr[1] = inr[2] * inr[1] + inr[1]; outr[2] = inr[2]; };
    const mfilter = (s, dst, m) => {
      m[2][0] = 1; for (let i = 1; i <= 2; i++) m[2][i] = -s[i];
      for (let i = 2; i > 0; i--) { const val = 1 - m[i][i] * m[i][i]; for (let y = 1; y <= i; y++) m[i - 1][y] = (m[i][i] * m[i][y] + m[i][y]) / val; }
      dst[0] = 1; for (let i = 1; i <= 2; i++) { dst[i] = 0; for (let y = 1; y <= i; y++) dst[i] += m[i][y] * dst[i - y]; }
    };
    const mfr = (s, dst) => {
      const tmp = [0, 0, 0]; let val = s[0]; dst[0] = 1;
      for (let i = 1; i <= 2; i++) {
        let v2 = 0; for (let y = 1; y < i; y++) v2 += dst[y] * s[i - y];
        dst[i] = val > 0 ? -(v2 + s[i]) / val : 0; tmp[i] = dst[i];
        for (let y = 1; y < i; y++) dst[y] += dst[i] * dst[i - y];
        val *= 1 - dst[i] * dst[i];
      }
      finish(tmp, dst);
    };
    const contrast = (s1, s2) => { const val = (s2[2] * s2[1] + -s2[1]) / (1 - s2[2] * s2[2]); const v1 = s1[0] * s1[0] + s1[1] * s1[1] + s1[2] * s1[2], v2 = s1[0] * s1[1] + s1[1] * s1[2], v3 = s1[0] * s1[2]; return v1 + 2 * val * v2 + 2 * (-s2[1] * val + -s2[2]) * v3; };
    const frecords = (vb, exp) => {
      const bl = Array.from({ length: 8 }, () => [0, 0, 0]), m = [[0, 0, 0], [0, 0, 0], [0, 0, 0]], b1 = new Int32Array(8), b2 = [0, 0, 0];
      for (let pass = 0; pass < 2; pass++) {
        for (let y = 0; y < exp; y++) { b1[y] = 0; bl[y][0] = bl[y][1] = bl[y][2] = 0; }
        for (let z = 0; z < rc; z++) {
          let index = 0, value = 1e30;
          for (let i = 0; i < exp; i++) { const t = contrast(vb[i], records[z]); if (t < value) { value = t; index = i; } }
          b1[index]++; mfilter(records[z], b2, m); for (let i = 0; i < 3; i++) bl[index][i] += b2[i];
        }
        for (let i = 0; i < exp; i++) if (b1[i] > 0) for (let y = 0; y < 3; y++) bl[i][y] /= b1[i];
        for (let i = 0; i < exp; i++) mfr(bl[i], vb[i]);
      }
    };
    for (let sample = 0, rem = src.length; sample < src.length; sample += 14, rem -= 14) {
      for (let i = 14; i < 28; i++) hist[i] = 0;
      for (let i = 0; i < Math.min(14, rem); i++) hist[14 + i] = src[sample + i];
      ipm(vec1, hist);
      if (Math.abs(vec1[0]) > 10) { opm(mtx, hist); if (!analyze(mtx, idx, buffer)) { bidi(mtx, idx, vec1); if (!qmerge(vec1)) { finish(vec1, records[rc]); rc++; } } }
      for (let i = 0; i < 14; i++) hist[i] = hist[14 + i];
    }
    vec1 = [1, 0, 0];
    for (let z = 0; z < rc; z++) { mfilter(records[z], best[0], mtx); for (let y = 1; y <= 2; y++) vec1[y] += best[0][y]; }
    for (let y = 1; y <= 2; y++) vec1[y] /= rc;
    mfr(vec1, best[0]);
    let exp = 1;
    for (let w = 0; w < 3;) {
      const vec2 = [0, -1, 0];
      for (let i = 0; i < exp; i++) for (let y = 0; y < 3; y++) best[exp + i][y] = 0.01 * vec2[y] + best[i][y];
      w++; exp = 1 << w; frecords(best, exp);
    }
    const coefs = new Int16Array(16);
    const roundEven = (d) => { const r = Math.round(d); return (Math.abs(d % 1) === 0.5 && r % 2 !== 0) ? r - 1 : r; };
    for (let z = 0; z < 8; z++) for (let k = 1; k <= 2; k++) {
      const d = -best[z][k] * 2048;
      let v;
      if (Number.isNaN(d)) v = 0; else if (d > 0) v = d > 32767 ? 32767 : roundEven(d); else v = d < -32768 ? -32768 : roundEven(d);
      coefs[z * 2 + k - 1] = v;
    }
    return coefs;
  }

  // ───────────────────────── BCSTM / BCWAV / SFX ─────────────────────────
  const nm = (v, m) => (v % m === 0 ? v : v + (m - (v % m)));
  const SPB = 0x3800, BS = 0x2000;

  function encodeChannel(pcm, loopStart, looping) {
    const coefs = calcCoefs(pcm), adpcm = DSP.encode(pcm, coefs), decoded = DSP.decode(adpcm, coefs, pcm.length);
    const e = { coefs, adpcm, decoded, sps: adpcm.length ? adpcm[0] : 0, lps: 0, lh1: 0, lh2: 0 };
    if (looping) { const fb = Math.floor(loopStart / 14) * 8; e.lps = fb < adpcm.length ? adpcm[fb] : 0; e.lh1 = loopStart >= 1 ? decoded[loopStart - 1] : 0; e.lh2 = loopStart >= 2 ? decoded[loopStart - 2] : 0; }
    else e.lps = e.sps;
    return e;
  }
  function writeAdpcmInfo(w, e) { for (const c of e.coefs) w.i16(c); w.i16(e.sps); w.i16(0); w.i16(0); w.i16(e.lps); w.i16(e.lh1); w.i16(e.lh2); w.i16(0); }

  function alignLoop(audio) {
    if (!audio.looping || audio.loopStart <= 0 || audio.loopStart % SPB === 0) return audio;
    const al = nm(audio.loopStart, SPB), shift = al - audio.loopStart;
    const channels = audio.channels.map((ch) => {
      const out = new Int16Array(ch.length + shift); out.set(ch);
      const span = Math.max(1, ch.length - audio.loopStart);
      for (let i = 0; i < shift; i++) out[ch.length + i] = ch[audio.loopStart + (i % span)];
      return out;
    });
    return { ...audio, channels, loopStart: al };
  }

  const BCSTM = {
    encode(input, progress) {
      const audio = alignLoop(input);
      const cc = audio.channels.length, sc = audio.channels[0].length, ls = audio.looping ? audio.loopStart : 0;
      const enc = audio.channels.map((ch, i) => { const e = encodeChannel(ch, ls, audio.looping); if (progress) progress((i + 1) / cc); return e; });
      const tc = (cc + 1) >> 1, ads = nm(s2bytes(sc), 0x20), ic = Math.max(1, Math.ceil(sc / SPB));
      const lbs = sc - (ic - 1) * SPB, lbnp = s2bytes(lbs), lb = nm(lbnp, 0x20), se = Math.max(1, Math.ceil(sc / SPB));
      const i1 = 0x38 + 0xC, i2 = 4 + 8 * tc, i3 = (4 + 8 * cc) + 0x14 * tc + 8 * cc + 0x2E * cc;
      const isz = nm(8 + 24 + i1 + i2 + i3, 0x20), ssz = nm(8 + se * cc * 4, 0x20);
      const hs = 0x40, io = hs, so = hs + isz, dof = so + ssz, dsz = 0x20 + ads * cc, fs = dof + dsz;
      const w = new ByteWriter(fs);
      w.ascii('CSTM'); w.u16(0xFEFF); w.u16(hs); w.u32(0x0201 << 16); w.u32(fs); w.u16(3); w.u16(0);
      w.u16(0x4000); w.u16(0); w.u32(io); w.u32(isz);
      w.u16(0x4001); w.u16(0); w.u32(so); w.u32(ssz);
      w.u16(0x4002); w.u16(0); w.u32(dof); w.u32(dsz);
      w.padTo(hs);
      const istart = w.count;
      w.ascii('INFO'); w.u32(isz);
      w.u16(0x4100); w.u16(0); w.u32(24);
      w.u16(0x0101); w.u16(0); w.u32(24 + i1);
      w.u16(0x0101); w.u16(0); w.u32(24 + i1 + i2);
      w.u8(2); w.u8(audio.looping ? 1 : 0); w.u8(cc); w.u8(0);
      w.u32(audio.sampleRate); w.u32(ls); w.u32(sc); w.u32(ic); w.u32(BS); w.u32(SPB);
      w.u32(lbnp); w.u32(lbs); w.u32(lb); w.u32(4); w.u32(SPB);
      w.u16(0x1F00); w.u16(0); w.u32(0x18);
      w.u16(0x0100); w.u16(0); w.u32(0); w.i32(-1);
      const cts = 4 + 8 * cc;
      w.u32(tc); for (let i = 0; i < tc; i++) { w.u16(0x4101); w.u16(0); w.u32(i2 + cts + 0x14 * i); }
      const tts = 0x14 * tc;
      w.u32(cc); for (let i = 0; i < cc; i++) { w.u16(0x4102); w.u16(0); w.u32(cts + tts + 8 * i); }
      for (let t = 0; t < tc; t++) { const chn = Math.min(cc - t * 2, 2); w.u8(0x7F); w.u8(0x40); w.u16(0); w.u16(0x0100); w.u16(0); w.u32(0xC); w.u32(chn); w.u8(t * 2); w.u8(chn >= 2 ? t * 2 + 1 : 0); w.u16(0); }
      for (let i = 0; i < cc; i++) { w.u16(0x0300); w.u16(0); w.u32(8 * cc - 8 * i + 0x2E * i); }
      for (const e of enc) writeAdpcmInfo(w, e);
      w.padTo(istart + isz);
      w.ascii('SEEK'); w.u32(ssz);
      for (let k = 0; k < se; k++) for (const e of enc) {
        if (k === 0) { w.i16(0); w.i16(0); } else { const idx = k * SPB; w.i16(idx - 1 < e.decoded.length ? e.decoded[idx - 1] : 0); w.i16(idx - 2 < e.decoded.length ? e.decoded[idx - 2] : 0); }
      }
      w.padTo(so + ssz);
      w.ascii('DATA'); w.u32(dsz); w.padTo(dof + 0x20);
      for (let b = 0; b < ic; b++) {
        const osz = b === ic - 1 ? lb : BS;
        for (const e of enc) { const st = b * BS, en = Math.min(st + osz, e.adpcm.length); if (st < en) w.append(e.adpcm.subarray(st, en)); w.zeros(osz - Math.max(0, en - st)); }
      }
      w.padTo(fs);
      return w.bytes();
    },
    decode(b) {
      const r = new ByteReader(b);
      if (r.ascii(4) !== 'CSTM') throw new Error('This is not a BCSTM file.');
      if (r.u16() !== 0xFEFF) throw new Error('Unsupported BCSTM byte order.');
      r.skip(2 + 4 + 4);
      const nb = r.u16(); r.skip(2);
      let io = 0, dof = 0;
      for (let i = 0; i < nb; i++) { const t = r.u16(); r.skip(2); const o = r.u32(); r.u32(); if (t === 0x4000) io = o; if (t === 0x4002) dof = o; }
      if (!io || !dof) throw new Error('BCSTM is missing INFO or DATA.');
      r.p = io; if (r.ascii(4) !== 'INFO') throw new Error('Invalid BCSTM INFO block.'); r.u32();
      const base = r.p; r.skip(4); const sref = r.i32(); r.skip(8); r.skip(4); const cref = r.i32();
      r.p = base + sref;
      const codec = r.u8(), looping = r.u8() !== 0, cc = r.u8(); r.skip(1);
      const rate = r.u32(), ls = r.u32(), sc = r.u32(), nblk = r.u32(), bsz = r.u32(); r.u32(); r.u32(); r.u32(); const lbp = r.u32(); r.u32(); r.u32(); r.skip(4); const sdo = r.i32();
      const coefs = [], starts = [];
      if (codec === 2) {
        const ts = base + cref; r.p = ts; const n = r.u32(); const offs = [];
        for (let i = 0; i < n; i++) { r.skip(4); offs.push(ts + r.i32()); }
        for (const e of offs) { r.p = e; r.skip(4); const ao = r.i32(); r.p = e + ao; const c = []; for (let k = 0; k < 16; k++) c.push(r.i16()); r.i16(); const h1 = r.i16(), h2 = r.i16(); coefs.push(c); starts.push([h1, h2]); }
      }
      const per = Array.from({ length: cc }, () => []); let p = dof + 8 + sdo;
      for (let blk = 0; blk < nblk; blk++) { const size = blk === nblk - 1 ? lbp : bsz; for (let c = 0; c < cc; c++) { per[c].push(b.subarray(p, Math.min(p + size, b.length))); p += size; } }
      const join = (arr) => { const t = arr.reduce((a, x) => a + x.length, 0), o = new Uint8Array(t); let q = 0; for (const x of arr) { o.set(x, q); q += x.length; } return o; };
      const channels = per.map((parts, c) => {
        const raw = join(parts);
        if (codec === 2) return DSP.decode(raw, coefs[c] || new Array(16).fill(0), sc, (starts[c] || [0, 0])[0], (starts[c] || [0, 0])[1]);
        const out = new Int16Array(sc);
        if (codec === 1) { const dv = new DataView(raw.buffer, raw.byteOffset, raw.byteLength); for (let i = 0; i < Math.min(sc, raw.length >> 1); i++) out[i] = dv.getInt16(i * 2, true); }
        else if (codec === 0) { for (let i = 0; i < Math.min(sc, raw.length); i++) out[i] = ((raw[i] << 24) >> 24) * 256; }
        else throw new Error('Unsupported BCSTM codec ' + codec);
        return out;
      });
      return { sampleRate: rate, channels, looping, loopStart: ls };
    },
  };

  const BCWAV = {
    encode(audio) {
      let mono = audio.channels[0];
      if (audio.channels.length > 1) { mono = new Int16Array(mono.length); for (let i = 0; i < mono.length; i++) { let s = 0; for (const ch of audio.channels) s += ch[i]; mono[i] = clamp16(Math.trunc(s / audio.channels.length)); } }
      const e = encodeChannel(mono, 0, false), sc = mono.length;
      const hs = 0x40, ib = 0x14 + 4 + 8 + 0x14 + 0x2E, isz = nm(8 + ib, 0x20), dsz = nm(0x20 + s2bytes(sc), 0x20), io = hs, dof = hs + isz, fs = dof + dsz;
      const w = new ByteWriter(fs);
      w.ascii('CWAV'); w.u16(0xFEFF); w.u16(hs); w.u32(0x02010000); w.u32(fs); w.u16(2); w.u16(0);
      w.u16(0x7000); w.u16(0); w.u32(io); w.u32(isz);
      w.u16(0x7001); w.u16(0); w.u32(dof); w.u32(dsz);
      w.padTo(hs);
      w.ascii('INFO'); w.u32(isz);
      w.u8(2); w.u8(0); w.u16(0); w.u32(audio.sampleRate); w.u32(0); w.u32(sc); w.u32(0);
      w.u32(1); w.u16(0x7100); w.u16(0); w.u32(0xC);
      w.u16(0x1F00); w.u16(0); w.u32(0x18);
      w.u16(0x0300); w.u16(0); w.u32(0x14);
      w.u32(0);
      writeAdpcmInfo(w, e);
      w.padTo(io + isz);
      w.ascii('DATA'); w.u32(dsz); w.padTo(dof + 0x20);
      w.append(e.adpcm); w.padTo(fs);
      return w.bytes();
    },
    decode(b) {
      const r = new ByteReader(b);
      if (r.ascii(4) !== 'CWAV') throw new Error('This is not a BCWAV file.');
      if (r.u16() !== 0xFEFF) throw new Error('Unsupported BCWAV byte order.');
      r.skip(10); const nb = r.u16(); r.skip(2);
      let io = 0, dof = 0;
      for (let i = 0; i < nb; i++) { const t = r.u16(); r.skip(2); const o = r.u32(); r.u32(); if (t === 0x7000) io = o; if (t === 0x7001) dof = o; }
      r.p = io + 8; const codec = r.u8(); r.skip(3); const rate = r.u32(); r.u32(); const sc = r.u32(); r.skip(4);
      const ts = r.p; const n = r.u32(); if (!n) throw new Error('BCWAV has no channels.'); r.skip(4); const ci = ts + r.i32();
      r.p = ci; r.skip(4); const so = r.i32(); r.skip(4); const ao = r.i32();
      const raw = b.subarray(dof + 8 + so);
      let pcm;
      if (codec === 2) { r.p = ci + ao; const c = []; for (let k = 0; k < 16; k++) c.push(r.i16()); r.i16(); const h1 = r.i16(), h2 = r.i16(); pcm = DSP.decode(raw, c, sc, h1, h2); }
      else if (codec === 1) { pcm = new Int16Array(sc); const dv = new DataView(raw.buffer, raw.byteOffset, raw.byteLength); for (let i = 0; i < Math.min(sc, raw.length >> 1); i++) pcm[i] = dv.getInt16(i * 2, true); }
      else if (codec === 0) { pcm = new Int16Array(sc); for (let i = 0; i < Math.min(sc, raw.length); i++) pcm[i] = ((raw[i] << 24) >> 24) * 256; }
      else throw new Error('Unsupported BCWAV codec ' + codec);
      return { sampleRate: rate, channels: [pcm], looping: false, loopStart: 0 };
    },
  };

  const SFX_SLOTS = [
    { title: 'Cursor Move', detail: 'Plays when the cursor moves between icons.' },
    { title: 'Launch Software', detail: 'Plays when software is opened from the HOME Menu.' },
    { title: 'Open Folder', detail: 'Plays when a folder is opened.' },
    { title: 'Close Folder', detail: 'Plays when a folder is closed.' },
    { title: 'Scroll Sound 1', detail: 'Played while the icon grid scrolls or changes page.' },
    { title: 'Scroll Sound 2', detail: 'Played while the icon grid scrolls or changes page.' },
    { title: 'Scroll Sound 3', detail: 'Played while the icon grid scrolls or changes page.' },
    { title: 'Open Lid / Wake', detail: 'Plays when the system is woken by opening the lid.' },
  ];
  const SFXBlock = {
    slots: SFX_SLOTS,
    isEmpty: (sounds) => sounds.every((s) => !s || !s.length),
    estimatedSize: (sounds) => 8 + 44 + sounds.reduce((a, s) => a + 8 + (s ? s.length : 0), 0),
    encode(sounds) {
      const w = new ByteWriter(); w.u32(2); w.u32(0x64);
      for (let i = 0; i < 8; i++) {
        if (i === 4) for (const v of [0x00, 0x64, 0x00, 0x64, 0x64, 0x00, 0x64, 0x64, 0x00, 0x00, 0x00]) w.u32(v);
        const d = sounds[i]; w.u32(d ? d.length : 0); w.u32(d && d.length ? 0x50 : 1); if (d) w.append(d);
      }
      return w.bytes();
    },
    decode(bytes) {
      const sounds = new Array(8).fill(null);
      if (!bytes || bytes.length < 8) return sounds;
      try {
        const r = new ByteReader(bytes); r.skip(8);
        for (let i = 0; i < 8; i++) {
          if (!r.remaining) break; if (i === 4) r.skip(44);
          let size = r.u32(); r.u32(); if (!size) continue; if (size > r.remaining) size = r.remaining;
          const chunk = r.read(size); if (String.fromCharCode(...chunk.subarray(0, 4)) !== 'CWAV') break; sounds[i] = chunk;
        }
      } catch (e) { /* keep what was read */ }
      return sounds;
    },
  };

  // ───────────────────────── Audio editing ─────────────────────────
  const AudioProcess = {
    defaultEdit() { return { startSeconds: 0, maxSeconds: 0, gainDB: 0, normalize: true, fadeInSeconds: 0, fadeOutSeconds: 0, trimSilence: false }; },
    trimSilence(a, threshold = 128) {
      const n = a.channels[0].length; if (!n) return a;
      const loud = (i) => a.channels.some((c) => Math.abs(c[i]) > threshold);
      let first = 0; while (first < n && !loud(first)) first++;
      let last = n - 1; while (last > first && !loud(last)) last--;
      if (first >= n) return a;
      const pad = Math.min(Math.floor(a.sampleRate * 0.01), first);
      return { ...a, channels: a.channels.map((c) => c.slice(first - pad, last + 1)) };
    },
    apply(input, e) {
      let a = { ...input, looping: false, loopStart: 0 };
      if (e.trimSilence) a = AudioProcess.trimSilence(a);
      const rate = a.sampleRate, total = a.channels[0].length;
      const start = Math.min(total, Math.max(0, Math.floor(e.startSeconds * rate)));
      let end = total; if (e.maxSeconds > 0) end = Math.min(end, start + Math.floor(e.maxSeconds * rate));
      if (start > 0 || end < total) a.channels = a.channels.map((c) => c.slice(start, Math.max(start, end)));
      const n = a.channels[0].length; if (!n) return a;
      let gain = Math.pow(10, e.gainDB / 20);
      if (e.normalize) { let peak = 1; for (const c of a.channels) for (let i = 0; i < c.length; i++) { const v = Math.abs(c[i]); if (v > peak) peak = v; } gain *= 32000 / peak; }
      const fi = Math.floor(e.fadeInSeconds * rate), fo = Math.floor(e.fadeOutSeconds * rate);
      if (gain !== 1 || fi > 0 || fo > 0) {
        a.channels = a.channels.map((c) => { const out = new Int16Array(n); for (let i = 0; i < n; i++) { let g = gain; if (fi > 0 && i < fi) g *= i / fi; if (fo > 0 && i >= n - fo) g *= (n - 1 - i) / fo; out[i] = clamp16(Math.round(c[i] * g)); } return out; });
      }
      return a;
    },
    estimatedBCSTMSize(seconds, rate, ch) { const s = Math.floor(seconds * rate); return 0x200 + s2bytes(s) * ch + (Math.floor(s / 14336) + 1) * 4 * ch; },
    maxSeconds(rate, ch) { return (Limits.maxBGM - 0x1000) / (rate * 8 / 14 * ch); },
    wav(audio) {
      const ch = audio.channels.length, n = audio.channels[0].length, w = new ByteWriter(44 + n * ch * 2);
      w.ascii('RIFF'); w.u32(36 + n * ch * 2); w.ascii('WAVE'); w.ascii('fmt '); w.u32(16); w.u16(1); w.u16(ch); w.u32(audio.sampleRate);
      w.u32(audio.sampleRate * ch * 2); w.u16(ch * 2); w.u16(16); w.ascii('data'); w.u32(n * ch * 2);
      for (let i = 0; i < n; i++) for (let c = 0; c < ch; c++) w.i16(audio.channels[c][i]);
      return w.bytes();
    },
  };

  // ───────────────────────── ZIP ─────────────────────────
  const Zip = {
    write(entries) {
      const w = new ByteWriter(), cd = new ByteWriter(), dosDate = ((2026 - 1980) << 9) | (1 << 5) | 1;
      for (const e of entries) {
        const name = new TextEncoder().encode(e.name), crc = crc32(e.data), off = w.count;
        w.u32(0x04034B50); w.u16(20); w.u16(0x0800); w.u16(0); w.u16(0); w.u16(dosDate); w.u32(crc); w.u32(e.data.length); w.u32(e.data.length); w.u16(name.length); w.u16(0); w.append(name); w.append(e.data);
        cd.u32(0x02014B50); cd.u16(20); cd.u16(20); cd.u16(0x0800); cd.u16(0); cd.u16(0); cd.u16(dosDate); cd.u32(crc); cd.u32(e.data.length); cd.u32(e.data.length); cd.u16(name.length); cd.u16(0); cd.u16(0); cd.u16(0); cd.u16(0); cd.u32(0); cd.u32(off); cd.append(name);
      }
      const cdo = w.count; w.append(cd.bytes());
      w.u32(0x06054B50); w.u16(0); w.u16(0); w.u16(entries.length); w.u16(entries.length); w.u32(cd.count); w.u32(cdo); w.u16(0);
      return w.bytes();
    },
    /** inflateRaw(bytes, expectedSize) -> Uint8Array must be supplied by the host (Node zlib). */
    read(bytes, inflateRaw) {
      let eocd = -1; for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 22 - 65535); i--) if (bytes[i] === 0x50 && bytes[i + 1] === 0x4B && bytes[i + 2] === 5 && bytes[i + 3] === 6) { eocd = i; break; }
      if (eocd < 0) throw new Error('Not a ZIP file.');
      const r = new ByteReader(bytes); r.p = eocd + 10; const count = r.u16(); r.u32(); r.p = r.u32();
      const out = [];
      for (let k = 0; k < count; k++) {
        if (r.u32() !== 0x02014B50) break;
        r.skip(6); const method = r.u16(); r.skip(8); const cs = r.u32(), us = r.u32(), nl = r.u16(), el = r.u16(), cl = r.u16(); r.skip(8); const lo = r.u32();
        const name = new TextDecoder().decode(r.read(nl)); r.skip(el + cl);
        if (name.endsWith('/')) continue;
        const lr = new ByteReader(bytes); lr.p = lo; if (lr.u32() !== 0x04034B50) continue; lr.skip(22); const ln = lr.u16(), le = lr.u16(); lr.skip(ln + le);
        const comp = lr.read(cs);
        if (method === 0) out.push({ name, data: comp }); else if (method === 8) out.push({ name, data: inflateRaw(comp, us) });
      }
      return out;
    },
  };

  // ───────────────────────── Package helpers ─────────────────────────
  function safeName(name) { const base = (name || '').trim() || 'My 3DS Theme'; return base.replace(/[^A-Za-z0-9 \-_()]/g, '_').trim(); }
  function validate(pkg, body) {
    const v = { errors: [], warnings: [], bodySize: body.length, bgmSize: pkg.bgm ? pkg.bgm.length : 0 };
    if (body.length > Limits.maxCompressedBody) v.errors.push(`body_LZ.bin is ${body.length.toLocaleString()} bytes; the limit is ${Limits.maxCompressedBody.toLocaleString()}. Use simpler images or fewer sound effects.`);
    if (pkg.theme.flags.backgroundMusic) {
      if (!pkg.bgm) v.warnings.push('Background music is turned on but no music has been added. It will be exported without BGM.');
      else if (pkg.bgm.length > Limits.maxBGM) v.errors.push(`bgm.bcstm is ${pkg.bgm.length.toLocaleString()} bytes; the limit is ${Limits.maxBGM.toLocaleString()}.`);
    }
    if (pkg.theme.flags.soundEffects && pkg.theme.soundEffectData.length > Limits.maxSoundEffects) v.errors.push('Sound effects are too large. Use shorter sounds.');
    if (!SMDH.primary(pkg.info).short) v.warnings.push('The theme has no name. ThemePlaza and theme managers show the name from info.smdh.');
    if (!pkg.preview) v.warnings.push('No preview.png will be included.');
    return v;
  }
  function packageFiles(pkg, body) {
    const files = [{ name: 'body_LZ.bin', data: body }, { name: 'info.smdh', data: SMDH.write(pkg.info) }];
    if (pkg.preview) files.push({ name: 'preview.png', data: pkg.preview });
    if (pkg.theme.flags.backgroundMusic && pkg.bgm) files.push({ name: 'bgm.bcstm', data: pkg.bgm });
    return files;
  }

  const TK = { ByteWriter, ByteReader, crc32, LZ11, Texture, Theme, SMDH, DSP, BCSTM, BCWAV, SFXBlock, AudioProcess, Zip, Geometry, Limits, SLOTS, makeImage, cropImage, bleedImage, grayLevels, safeName, validate, packageFiles, DEFAULT_PATTERN };
  if (typeof module !== 'undefined' && module.exports) module.exports = TK; else root.TK = TK;
})(typeof self !== 'undefined' ? self : this);
