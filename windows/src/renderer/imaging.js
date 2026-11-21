// Picture loading, editing (resize/crop/rotate/flip/color) and conversion helpers.
const Imaging = {
  defaultEdit(fit = 'fill') {
    return { fit, zoom: 1, offsetX: 0, offsetY: 0, quarterTurns: 0, angle: 0, flipH: false, flipV: false, background: [0, 0, 0],
      brightness: 0, contrast: 1, saturation: 1, hue: 0, warmth: 0, sharpen: 0, blur: 0, vignette: 0 };
  },
  resetColor(e) { Object.assign(e, { brightness: 0, contrast: 1, saturation: 1, hue: 0, warmth: 0, sharpen: 0, blur: 0, vignette: 0 }); },
  resetGeometry(e) { Object.assign(e, { zoom: 1, offsetX: 0, offsetY: 0, quarterTurns: 0, angle: 0, flipH: false, flipV: false }); },

  /** Loads a picture file into a canvas (shrunk if huge). */
  async loadPath(path) {
    const bytes = window.api.readFile(path);
    return Imaging.loadBytes(bytes);
  },
  async loadBytes(bytes, maxSide = 2400) {
    const bmp = await createImageBitmap(new Blob([bytes]));
    const s = Math.min(1, maxSide / Math.max(bmp.width, bmp.height));
    const c = document.createElement('canvas');
    c.width = Math.max(1, Math.round(bmp.width * s)); c.height = Math.max(1, Math.round(bmp.height * s));
    const ctx = c.getContext('2d'); ctx.imageSmoothingQuality = 'high'; ctx.drawImage(bmp, 0, 0, c.width, c.height);
    bmp.close && bmp.close();
    return c;
  },

  /** Renders a source picture into a width×height canvas using an edit. */
  renderCanvas(src, w, h, e) {
    const c = document.createElement('canvas'); c.width = w; c.height = h;
    const ctx = c.getContext('2d', { willReadFrequently: true });
    ctx.fillStyle = rgbHex(e.background); ctx.fillRect(0, 0, w, h);
    const turns = ((e.quarterTurns % 4) + 4) % 4, odd = turns % 2 === 1;
    const iw = src.width, ih = src.height, dw = odd ? ih : iw, dh = odd ? iw : ih;
    let sx, sy;
    if (e.fit === 'fill') { sx = sy = Math.max(w / dw, h / dh); }
    else if (e.fit === 'fit') { sx = sy = Math.min(w / dw, h / dh); }
    else { sx = w / dw; sy = h / dh; }
    sx *= e.zoom; sy *= e.zoom;
    const drawW = iw * (odd ? sy : sx), drawH = ih * (odd ? sx : sy);
    const filters = [];
    if (e.brightness) filters.push(`brightness(${1 + e.brightness * 0.6})`);
    if (e.contrast !== 1) filters.push(`contrast(${e.contrast})`);
    if (e.saturation !== 1) filters.push(`saturate(${e.saturation})`);
    if (e.hue) filters.push(`hue-rotate(${e.hue}deg)`);
    if (e.blur) filters.push(`blur(${e.blur}px)`);
    ctx.filter = filters.length ? filters.join(' ') : 'none';
    ctx.imageSmoothingQuality = 'high';
    ctx.save();
    ctx.translate(w / 2 + e.offsetX, h / 2 + e.offsetY);
    ctx.scale(e.flipH ? -1 : 1, e.flipV ? -1 : 1);
    ctx.rotate(turns * Math.PI / 2 + e.angle * Math.PI / 180);
    ctx.drawImage(src, -drawW / 2, -drawH / 2, drawW, drawH);
    ctx.restore();
    ctx.filter = 'none';
    if (e.vignette > 0) {
      const g = ctx.createRadialGradient(w / 2, h / 2, Math.min(w, h) * 0.25, w / 2, h / 2, Math.hypot(w, h) / 2);
      g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(1, `rgba(0,0,0,${Math.min(0.9, e.vignette * 0.45)})`);
      ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
    }
    if (e.warmth || e.sharpen) {
      const id = ctx.getImageData(0, 0, w, h), d = id.data;
      if (e.warmth) { const k = e.warmth * 28; for (let i = 0; i < d.length; i += 4) { d[i] = Math.min(255, Math.max(0, d[i] + k)); d[i + 2] = Math.min(255, Math.max(0, d[i + 2] - k)); } }
      if (e.sharpen) {
        const src2 = new Uint8ClampedArray(d), a = e.sharpen * 0.5;
        for (let y = 1; y < h - 1; y++) for (let x = 1; x < w - 1; x++) {
          const i = (y * w + x) * 4;
          for (let ch = 0; ch < 3; ch++) {
            const v = src2[i + ch] * (1 + 4 * a) - a * (src2[i - 4 + ch] + src2[i + 4 + ch] + src2[i - w * 4 + ch] + src2[i + w * 4 + ch]);
            d[i + ch] = v;
          }
        }
      }
      ctx.putImageData(id, 0, 0);
    }
    return c;
  },

  canvasToImage(c) {
    const d = c.getContext('2d', { willReadFrequently: true }).getImageData(0, 0, c.width, c.height).data;
    const img = TK.makeImage(c.width, c.height);
    for (let i = 0, j = 0; i < d.length; i += 4, j += 3) { img.pixels[j] = d[i]; img.pixels[j + 1] = d[i + 1]; img.pixels[j + 2] = d[i + 2]; }
    return img;
  },
  imageToCanvas(img, mask = false) {
    const c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
    const ctx = c.getContext('2d'), id = ctx.createImageData(img.width, img.height), d = id.data;
    for (let i = 0, j = 0; j < img.pixels.length; i += 4, j += 3) {
      if (mask) { d[i] = d[i + 1] = d[i + 2] = 255; d[i + 3] = img.pixels[j]; }
      else { d[i] = img.pixels[j]; d[i + 1] = img.pixels[j + 1]; d[i + 2] = img.pixels[j + 2]; d[i + 3] = 255; }
    }
    ctx.putImageData(id, 0, 0);
    return c;
  },
  /** How the picture will look on the 3DS (16-bit color / grayscale). */
  consolePreview(img, format, dither) {
    if (format === 'rgb565') {
      if (dither) return TK.Texture.ditherTo565(img);
      const o = { width: img.width, height: img.height, pixels: new Uint8Array(img.pixels) };
      for (let i = 0; i < o.pixels.length; i += 3) { o.pixels[i] = (o.pixels[i] >> 3) << 3; o.pixels[i + 1] = (o.pixels[i + 1] >> 2) << 2; o.pixels[i + 2] = (o.pixels[i + 2] >> 3) << 3; }
      return o;
    }
    if (format === 'a8') { const g = TK.grayLevels(img), o = TK.makeImage(img.width, img.height); for (let i = 0; i < g.length; i++) o.pixels[i * 3] = o.pixels[i * 3 + 1] = o.pixels[i * 3 + 2] = g[i]; return o; }
    return img;
  },
  async canvasPNG(c) {
    const blob = await new Promise((r) => c.toBlob(r, 'image/png'));
    return new Uint8Array(await blob.arrayBuffer());
  },
  /** Most-used colors, grouped and de-duplicated. */
  palette(img, maxColors = 12, tolerance = 0.025) {
    const buckets = new Map(), n = img.width * img.height, step = Math.max(1, Math.floor(n / 120000));
    for (let i = 0; i < n; i += step) {
      const r = img.pixels[i * 3], g = img.pixels[i * 3 + 1], b = img.pixels[i * 3 + 2], key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      const e = buckets.get(key) || [0, 0, 0, 0]; e[0]++; e[1] += r; e[2] += g; e[3] += b; buckets.set(key, e);
    }
    const sorted = [...buckets.values()].sort((a, b) => b[0] - a[0]).map((e) => [e[1] / e[0] | 0, e[2] / e[0] | 0, e[3] / e[0] | 0]);
    const minD = tolerance * 255 * 255 * 3, out = [];
    for (const c of sorted) { if (out.length >= maxColors) break; if (out.every((o) => (c[0] - o[0]) ** 2 + (c[1] - o[1]) ** 2 + (c[2] - o[2]) ** 2 > minD)) out.push(c); }
    const hue = (c) => { const r = c[0] / 255, g = c[1] / 255, b = c[2] / 255, mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn; if (d < 0.08) return -1 + (r + g + b) / 3; let h = mx === r ? (g - b) / d : mx === g ? 2 + (b - r) / d : 4 + (r - g) / d; h *= 60; return h < 0 ? h + 360 : h; };
    return out.sort((a, b) => hue(a) - hue(b));
  },
};
