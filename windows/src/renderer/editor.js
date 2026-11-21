// Full-screen picture editor: position, resize, rotate, flip and color-correct, previewed in real 3DS colors.
const Editor = {
  state: null,
  open(slot, title) {
    const src = App.sources[slot]; if (!src) return;
    this.state = { slot, title, edit: structuredClone(src.edit), original: structuredClone(src.edit), consoleColors: true, guides: true };
    this.build();
  },
  close(apply) {
    const s = this.state; if (!s) return;
    App.sources[s.slot].edit = apply ? s.edit : s.original;
    App.renderSlot(s.slot);
    this.node.remove(); this.node = null; this.state = null;
    document.removeEventListener('keydown', this.keyHandler);
    App.renderPage();
  },
  commitSoon() {
    clearTimeout(this.commitTimer);
    this.commitTimer = setTimeout(() => { if (!this.state) return; App.sources[this.state.slot].edit = structuredClone(this.state.edit); App.renderSlot(this.state.slot); }, 200);
  },
  build() {
    const s = this.state, e = s.edit, [vw, vh] = TK.Geometry.visible(s.slot, App.theme.flags);
    const fmt = TK.SLOTS[s.slot];
    const stage = el('div', { class: 'stage' });
    const view = document.createElement('canvas'); view.width = vw; view.height = vh;
    const guides = document.createElement('canvas'); guides.className = 'guides'; guides.width = vw * 2; guides.height = vh * 2;
    const frame = el('div', { class: 'frame' }, view, guides);
    const hint = el('div', { class: 'hint' });
    stage.append(frame, hint);

    const layout = () => {
      const r = stage.getBoundingClientRect();
      const scale = Math.min((r.width - 60) / vw, (r.height - 90) / vh, fmt === 'rgb565' ? 3 : 6);
      Object.assign(view.style, { width: vw * scale + 'px', height: vh * scale + 'px', imageRendering: scale >= 2 ? 'pixelated' : 'auto' });
      Object.assign(guides.style, { width: vw * scale + 'px', height: vh * scale + 'px' });
      s.scale = scale;
    };
    const redraw = () => {
      const img = App.renderSlotImage(s.slot, e);
      const shown = s.consoleColors ? Imaging.consolePreview(img, fmt, App.theme.ditherBackgrounds) : img;
      view.getContext('2d').drawImage(Imaging.imageToCanvas(shown), 0, 0);
      this.drawGuides(guides, s.slot, s.guides);
      hint.textContent = `Drag to move · Scroll to zoom · ${vw} × ${vh} px${s.consoleColors ? ' · showing real 3DS colors' : ''}`;
    };
    const update = () => { redraw(); this.commitSoon(); };
    this.update = update;

    // Drag to move, wheel to zoom
    let drag = null;
    frame.addEventListener('mousedown', (ev) => { drag = { x: ev.clientX, y: ev.clientY, ox: e.offsetX, oy: e.offsetY }; frame.classList.add('grabbing'); });
    window.addEventListener('mousemove', (ev) => { if (!drag || !this.state) return; e.offsetX = Math.round(drag.ox + (ev.clientX - drag.x) / s.scale); e.offsetY = Math.round(drag.oy + (ev.clientY - drag.y) / s.scale); syncSliders(); update(); });
    window.addEventListener('mouseup', () => { drag = null; frame.classList.remove('grabbing'); });
    frame.addEventListener('wheel', (ev) => { ev.preventDefault(); e.zoom = Math.min(4, Math.max(0.1, e.zoom * (ev.deltaY < 0 ? 1.06 : 1 / 1.06))); syncSliders(); update(); }, { passive: false });

    // Inspector
    const sliders = {};
    const sl = (key, label, min, max, step, neutral, format) => { const n = slider(label, () => e[key], (v) => { e[key] = v; }, min, max, step, neutral, format, null, update); sliders[key] = n; return n; };
    const syncSliders = () => { for (const [k, n] of Object.entries(sliders)) { const r = n.querySelector('input'); r.value = e[k]; updateRangeFill(r); } };
    const group = (title, ic, ...kids) => el('div', { class: 'igroup' }, el('b', {}, svg(ic), title), ...kids);
    const rebuild = () => { const scroll = insp.scrollTop; this.node.remove(); this.build(); this.node.querySelector('.insp').scrollTop = scroll; };
    const preset = (name, fn) => btn(name, null, () => { Imaging.resetColor(e); fn(e); update(); rebuild(); }, 'small');
    const edge = () => { const c = Imaging.renderCanvas(App.sources[s.slot].canvas, 8, 8, { ...Imaging.defaultEdit('stretch') }); const d = c.getContext('2d').getImageData(0, 0, 8, 8).data; let r = 0, g = 0, b = 0, n = 0; for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) if (!x || !y || x === 7 || y === 7) { const i = (y * 8 + x) * 4; r += d[i]; g += d[i + 1]; b += d[i + 2]; n++; } return [r / n | 0, g / n | 0, b / n | 0]; };
    const fitHelp = { fill: 'Covers the whole area; edges may be cropped.', fit: 'Shows the whole picture; empty space uses the background fill.', stretch: 'Squeezes the picture to the exact size.' };

    const insp = el('div', { class: 'insp' },
      el('div', {}, el('h2', {}, 'Edit ' + s.title), el('div', { class: 'muted small' }, App.sources[s.slot].fileName || '')),
      group('Size & Position', 'expand',
        segmented([['fill', 'Fill'], ['fit', 'Fit'], ['stretch', 'Stretch']], e.fit, (v) => { e.fit = v; update(); rebuild(); }),
        el('div', { class: 'muted small' }, fitHelp[e.fit]),
        sl('zoom', 'Zoom', 0.1, 4, 0.01, 1, (v) => Math.round(v * 100) + '%'),
        sl('offsetX', 'Move X', -vw, vw, 1, 0, (v) => (v >= 0 ? '+' : '') + Math.round(v) + ' px'),
        sl('offsetY', 'Move Y', -vh, vh, 1, 0, (v) => (v >= 0 ? '+' : '') + Math.round(v) + ' px'),
        el('div', { class: 'row' }, btn('Center', null, () => { e.offsetX = 0; e.offsetY = 0; syncSliders(); update(); }, 'small'), btn('Fit Whole Picture', null, () => { Object.assign(e, { fit: 'fit', zoom: 1, offsetX: 0, offsetY: 0 }); update(); rebuild(); }, 'small'))),
      group('Rotate & Flip', 'rotR',
        el('div', { class: 'row' }, btn('Left', 'rotL', () => { e.quarterTurns--; update(); }, 'small'), btn('Right', 'rotR', () => { e.quarterTurns++; update(); }, 'small'), el('div', { class: 'grow' }),
          btn('Flip horizontally', 'flipH', () => { e.flipH = !e.flipH; update(); rebuild(); }, 'icon small' + (e.flipH ? ' primary' : '')),
          btn('Flip vertically', 'flipV', () => { e.flipV = !e.flipV; update(); rebuild(); }, 'icon small' + (e.flipV ? ' primary' : ''))),
        sl('angle', 'Straighten', -45, 45, 0.5, 0, (v) => (v >= 0 ? '+' : '') + v.toFixed(1) + '°')),
      group('Background Fill', 'square',
        colorRow('Empty areas', 'Shown where the picture doesn\'t cover (Fit mode, zoomed out or rotated).', () => e.background, (v) => { e.background = v; update(); }),
        el('div', {}, btn('Match Picture Edge', null, () => { e.background = edge(); update(); rebuild(); }, 'small'))),
      group('Color', 'filter',
        sl('brightness', 'Brightness', -1, 1, 0.01, 0, (v) => (v >= 0 ? '+' : '') + Math.round(v * 100)),
        sl('contrast', 'Contrast', 0.25, 2, 0.01, 1, (v) => Math.round(v * 100) + '%'),
        sl('saturation', 'Saturation', 0, 2, 0.01, 1, (v) => Math.round(v * 100) + '%'),
        sl('hue', 'Hue', -180, 180, 1, 0, (v) => (v >= 0 ? '+' : '') + Math.round(v) + '°'),
        sl('warmth', 'Warmth', -1, 1, 0.01, 0, (v) => (v >= 0 ? '+' : '') + Math.round(v * 100)),
        sl('sharpen', 'Sharpen', 0, 2, 0.01, 0, (v) => Math.round(v * 50)),
        sl('blur', 'Blur', 0, 20, 0.5, 0, (v) => v.toFixed(1) + ' px'),
        sl('vignette', 'Vignette', 0, 2, 0.01, 0, (v) => Math.round(v * 50)),
        el('div', { class: 'row wrap' }, preset('Vivid', (x) => { x.saturation = 1.35; x.contrast = 1.12; }), preset('Soft', (x) => { x.contrast = 0.85; x.brightness = 0.08; x.saturation = 0.9; }), preset('Dim', (x) => { x.brightness = -0.25; x.contrast = 0.9; }), preset('B&W', (x) => { x.saturation = 0; x.contrast = 1.1; })),
        el('div', {}, btn('Reset Colors', null, () => { Imaging.resetColor(e); update(); rebuild(); }, 'small ghost'))),
      group('Preview', 'eye',
        el('label', { class: 'row' }, toggleSwitch(s.consoleColors, (v) => { s.consoleColors = v; redraw(); }), 'Show real 3DS colors'),
        fmt === 'rgb565' ? el('label', { class: 'row' }, toggleSwitch(App.theme.ditherBackgrounds, (v) => { App.theme.ditherBackgrounds = v; redraw(); }), 'Dithering (smoother gradients)') : null,
        el('label', { class: 'row' }, toggleSwitch(s.guides, (v) => { s.guides = v; redraw(); }), 'Show screen guides')));

    const exportPNG = async () => {
      const out = await window.api.saveFile('Export Edited Picture', s.title + '.png', [{ name: 'PNG image', extensions: ['png'] }]); if (!out) return;
      window.api.writeFile(out, await Imaging.canvasPNG(Imaging.imageToCanvas(App.renderSlotImage(s.slot, e)))); toast('Saved ' + window.api.basename(out));
    };
    const foot = el('div', { class: 'foot' },
      btn('Reset All', null, () => { Imaging.resetGeometry(e); Imaging.resetColor(e); e.fit = s.original.fit; update(); rebuild(); }),
      btn('Export as PNG…', 'image', exportPNG),
      el('div', { class: 'grow' }),
      btn('Cancel', null, () => this.close(false)),
      btn('Done', 'check', () => this.close(true), 'primary'));
    this.node = el('div', { class: 'modal-bg' }, el('div', { class: 'modal' }, el('div', { class: 'body' }, stage, insp), foot));
    document.body.append(this.node);
    this.keyHandler = (ev) => { if (ev.key === 'Escape') this.close(false); if (ev.key === 'Enter' && ev.target.tagName !== 'INPUT') this.close(true); };
    document.addEventListener('keydown', this.keyHandler);
    requestAnimationFrame(() => { layout(); redraw(); });
    window.addEventListener('resize', () => { if (this.state) layout(); });
  },
  drawGuides(c, slot, show) {
    const ctx = c.getContext('2d'); ctx.clearRect(0, 0, c.width, c.height);
    if (!show) return;
    const f = App.theme.flags, k = 2;
    ctx.setLineDash([10, 8]); ctx.lineWidth = 2; ctx.font = 'bold 20px Segoe UI, sans-serif'; ctx.fillStyle = '#fff'; ctx.textBaseline = 'top';
    const box = (x, y, w, h, color) => { ctx.strokeStyle = color; ctx.strokeRect(x * k + 1, y * k + 1, w * k - 2, h * k - 2); };
    const label = (t, x, y) => { ctx.save(); ctx.shadowColor = '#000'; ctx.shadowBlur = 4; ctx.fillText(t, x * k + 8, y * k + 6); ctx.restore(); };
    if (slot === 'top') {
      if (f.topFrameType !== 1) { box(0, 0, 412, 240, 'rgba(255,220,80,.9)'); box(1008 - 412, 0, 412, 240, 'rgba(255,220,80,.9)'); label('First screen', 6, 2); label('Last screen', 602, 2); }
      else { ctx.strokeStyle = 'rgba(255,90,110,.8)'; for (const x of [6, 406]) { ctx.beginPath(); ctx.moveTo(x * k, 0); ctx.lineTo(x * k, c.height); ctx.stroke(); } label('3D only', 6, 2); }
    } else if (slot === 'bottom') {
      const t = f.bottomFrameType, pages = t === 1 ? [0] : (t === 2 || t === 4) ? [0, 320, 640] : [0, 1008 - 320];
      pages.forEach((x, i) => {
        box(x, 0, 320, 240, 'rgba(255,220,80,.9)');
        ctx.strokeStyle = 'rgba(255,255,255,.6)'; ctx.beginPath(); ctx.roundRect((x + 12) * k, 39 * k, 296 * k, 170 * k, 20); ctx.stroke();
        if (pages.length > 1) label('Screen ' + (i + 1), x + 4, 2);
      });
      label('Icons area', 14, 41);
    } else {
      ctx.strokeStyle = 'rgba(255,255,255,.35)';
      ctx.beginPath(); ctx.moveTo(0, c.height / 2); ctx.lineTo(c.width, c.height / 2); ctx.moveTo(c.width / 2, 0); ctx.lineTo(c.width / 2, c.height); ctx.stroke();
    }
  },
};
