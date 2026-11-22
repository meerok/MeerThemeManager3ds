// Draws the 3DS HOME Menu with the theme's colors and pictures, laid out like the real console.
// Coordinates are console pixels: top screen 412×240 (incl. 3D margins), bottom 320×240.
// Element positions follow the real HOME Menu (and Usagi's measurements of it).
const Preview = (() => {
  // What the HOME Menu looks like when a color group is switched off (the console's own look).
  const REAL = {
    cursor: { shading: [51, 225, 154], main: [57, 237, 166], light: [170, 255, 222], glow: [57, 237, 166] },
    folder: { shading: [70, 132, 150], main: [101, 168, 187], light: [146, 225, 238], shadow: [0, 0, 0] },
    file: { shading: [208, 208, 208], main: [246, 246, 246], light: [252, 252, 252], shadow: [0, 0, 0, 70] },
    arrowButton: { shading: [206, 206, 206], main: [240, 240, 240], light: [255, 255, 255], shadow: [0, 0, 0, 70] },
    arrow: { border: [151, 181, 176], unpressed: [161, 192, 186], pressed: [177, 255, 240] },
    open: { textShadowPosition: -1.25, pressed: [160, 156, 152], unpressed: [189, 185, 181], light: [230, 227, 223], shadow: [0, 0, 0, 60], glow: [240, 238, 234], textShadow: [239, 237, 233], textUnpressed: [61, 61, 61], textPressed: [40, 40, 40] },
    close: { textShadowPosition: 1, pressed: [60, 58, 52], unpressed: [75, 72, 65], light: [88, 85, 78], shadow: [0, 0, 0, 60], glow: [134, 131, 124], textShadow: [90, 90, 90], textUnpressed: [239, 237, 233], textPressed: [200, 200, 200] },
    gameText: { main: [250, 250, 250], light: [255, 255, 255], shadow: [0, 0, 0, 60], text: [61, 61, 61] },
    bottomInner: { highlight: [127, 127, 127], main: [223, 220, 215], border: [234, 234, 234], glow: [63, 63, 63, 255] },
    bottomOuter: { stripes: [208, 208, 216], main: [226, 226, 234], glow: [227, 228, 233] },
    folderBackground: { highlight: [127, 127, 127], main: [223, 220, 215], border: [234, 234, 234], glow: [63, 63, 63, 255] },
    folderArrow: { arrowShadowPosition: -1.25, shading: [43, 45, 42], main: [78, 75, 68], highlight: [140, 135, 129], shadow: [0, 0, 0, 90], glow: [120, 116, 110], arrowGlow: [0, 0, 0], arrowUnpressed: [255, 255, 255], arrowPressed: [187, 187, 187] },
    bottomCorner: { border: [220, 220, 220], main: [233, 233, 234], highlight: [250, 250, 250], baseShadow: [0, 0, 0], iconBottom: [130, 156, 196], iconTop: [149, 176, 211], iconText: [149, 176, 211] },
    topCorner: { main: [255, 255, 255], light: [255, 255, 255], shadow: [0, 0, 0], text: [61, 61, 61] },
    demoText: { main: [60, 60, 60], text: [255, 255, 255] },
  };
  const FLAG = {
    cursor: 'cursorColor', folder: 'folderColor', file: 'fileColor', arrowButton: 'arrowButtonColor', arrow: 'arrowColor',
    open: 'openCloseColor', close: 'openCloseColor', bottomCorner: 'bottomCornerColor', topCorner: 'topCornerColor',
    folderArrow: 'folderArrowColor', folderBackground: 'folderBackgroundColor', demoText: 'demoTextColor',
  };
  /** The colors actually used for a group: the theme's when its switch is on, otherwise the console's own. */
  function col(s, key) {
    const f = s.theme.flags, c = s.theme.colors;
    if (key === 'gameText') return f.gameTextDrawType === 1 ? c.gameText : REAL.gameText;
    if (key === 'bottomInner') return f.bottomDrawType === 1 && f.bottomInnerColor ? c.bottomInner : REAL.bottomInner;
    if (key === 'bottomOuter') return f.bottomDrawType === 1 && f.bottomOuterColor ? c.bottomOuter : REAL.bottomOuter;
    return f[FLAG[key]] ? c[key] : REAL[key];
  }

  const css = (c, a = 1) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;
  const cssA = (c, k = 1) => `rgba(${c[0]},${c[1]},${c[2]},${((c[3] ?? 255) / 255) * k})`;
  const mix = (a, b, t) => [0, 1, 2].map((i) => Math.round(a[i] * (1 - t) + b[i] * t));
  const WHITE = [255, 255, 255], BLACK = [0, 0, 0];
  const FONT = '"Nunito", "Segoe UI", "SF Pro Rounded", "Helvetica Neue", system-ui, sans-serif';

  function rr(ctx, x, y, w, h, r) { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); }
  function lin(ctx, x0, y0, x1, y1, stops) { const g = ctx.createLinearGradient(x0, y0, x1, y1); for (const [o, c] of stops) g.addColorStop(o, c); return g; }
  function vgrad(ctx, top, bottom, y0, y1) { return lin(ctx, 0, y0, 0, y1, [[0, css(top)], [1, css(bottom)]]); }
  function withShadow(ctx, color, blur, dx, dy, fn) { ctx.save(); ctx.shadowColor = color; ctx.shadowBlur = blur; ctx.shadowOffsetX = dx; ctx.shadowOffsetY = dy; fn(); ctx.restore(); }
  function text(ctx, s, x, y, size, color, align = 'center', weight = 800) {
    ctx.font = `${weight} ${size}px ${FONT}`; ctx.fillStyle = color; ctx.textAlign = align; ctx.textBaseline = 'middle'; ctx.fillText(s, x, y);
  }
  function outlinedText(ctx, s, x, y, size, fill, stroke, align = 'center', weight = 800) {
    ctx.font = `${weight} ${size}px ${FONT}`; ctx.textAlign = align; ctx.textBaseline = 'middle';
    ctx.lineJoin = 'round'; ctx.lineWidth = 2.5; ctx.strokeStyle = stroke; ctx.strokeText(s, x, y); ctx.fillStyle = fill; ctx.fillText(s, x, y);
  }
  function fitText(ctx, s, maxW, size, weight = 800) {
    ctx.font = `${weight} ${size}px ${FONT}`;
    if (ctx.measureText(s).width <= maxW) return s;
    let t = s; while (t.length > 1 && ctx.measureText(t + '…').width > maxW) t = t.slice(0, -1);
    return t + '…';
  }
  function drawImageTiled(ctx, img, w, h, dx, dy) {
    const iw = img.width, ih = img.height;
    for (let y = -ih + (((dy % ih) + ih) % ih); y < h; y += ih) for (let x = -iw + (((dx % iw) + iw) % iw); x < w; x += iw) ctx.drawImage(img, x, y);
  }
  const modeOf = (s) => s.mode || (s.folderMode ? 'folder' : 'home');

  // ───────────── App artwork (original designs, drawn in a 38×38 box centered on 0,0) ─────────────
  function appBg(ctx, top, bottom) { ctx.fillStyle = lin(ctx, 0, -19, 0, 19, [[0, css(top)], [1, css(bottom)]]); ctx.fillRect(-19, -19, 38, 38); ctx.fillStyle = 'rgba(255,255,255,.22)'; ctx.beginPath(); ctx.ellipse(0, -19, 30, 17, 0, 0, Math.PI); ctx.fill(); }
  const ART = {
    settings(ctx) {
      appBg(ctx, [176, 182, 192], [104, 110, 122]);
      ctx.fillStyle = '#fff'; ctx.beginPath();
      for (let i = 0; i < 16; i++) { const a = (i / 16) * Math.PI * 2, r = i % 2 ? 9 : 12; ctx.lineTo(Math.cos(a) * r, Math.sin(a) * r); }
      ctx.closePath(); ctx.fill(); ctx.fillStyle = css([128, 134, 146]); ctx.beginPath(); ctx.arc(0, 0, 4.5, 0, 7); ctx.fill();
    },
    camera(ctx) {
      appBg(ctx, [70, 74, 84], [30, 32, 38]);
      ctx.fillStyle = '#e8e8ec'; rr(ctx, -13, -7, 26, 18, 4); ctx.fill(); rr(ctx, -5, -11, 10, 5, 2); ctx.fill();
      ctx.fillStyle = '#2c2f36'; ctx.beginPath(); ctx.arc(0, 2, 6.5, 0, 7); ctx.fill();
      ctx.fillStyle = '#5ab0ff'; ctx.beginPath(); ctx.arc(0, 2, 3.6, 0, 7); ctx.fill(); ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(-1.2, 0.8, 1.1, 0, 7); ctx.fill();
    },
    music(ctx) {
      appBg(ctx, [255, 172, 64], [232, 104, 24]);
      ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.ellipse(-6, 8, 4.6, 3.6, -0.4, 0, 7); ctx.fill(); ctx.beginPath(); ctx.ellipse(7, 5, 4.6, 3.6, -0.4, 0, 7); ctx.fill();
      ctx.fillRect(-2.3, -11, 2.6, 19); ctx.fillRect(10.7, -14, 2.6, 19); ctx.beginPath(); ctx.moveTo(-2.3, -11); ctx.lineTo(13.3, -14); ctx.lineTo(13.3, -9); ctx.lineTo(-2.3, -6); ctx.fill();
    },
    browser(ctx) {
      appBg(ctx, [86, 170, 255], [28, 98, 214]);
      ctx.strokeStyle = '#fff'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(0, 0, 11, 0, 7); ctx.stroke();
      ctx.beginPath(); ctx.ellipse(0, 0, 5, 11, 0, 0, 7); ctx.moveTo(-11, 0); ctx.lineTo(11, 0); ctx.moveTo(-9, -6); ctx.lineTo(9, -6); ctx.moveTo(-9, 6); ctx.lineTo(9, 6); ctx.lineWidth = 1.4; ctx.stroke();
    },
    shop(ctx) {
      appBg(ctx, [120, 214, 110], [40, 150, 64]);
      ctx.fillStyle = '#fff'; rr(ctx, -11, -5, 22, 17, 3); ctx.fill();
      ctx.strokeStyle = '#fff'; ctx.lineWidth = 2.2; ctx.beginPath(); ctx.arc(0, -5, 6, Math.PI, 0); ctx.stroke();
      ctx.fillStyle = css([40, 150, 64]); ctx.beginPath(); ctx.arc(0, 3.5, 3, 0, 7); ctx.fill();
    },
    mail(ctx) {
      appBg(ctx, [90, 222, 214], [18, 150, 160]);
      ctx.fillStyle = '#fff'; rr(ctx, -12, -8, 24, 17, 2.5); ctx.fill();
      ctx.strokeStyle = css([18, 150, 160]); ctx.lineWidth = 1.8; ctx.lineJoin = 'round'; ctx.beginPath(); ctx.moveTo(-11, -7); ctx.lineTo(0, 2); ctx.lineTo(11, -7); ctx.stroke();
    },
    game(ctx) {
      appBg(ctx, [196, 120, 255], [112, 48, 196]);
      ctx.fillStyle = '#fff'; ctx.beginPath();
      for (let i = 0; i < 10; i++) { const a = -Math.PI / 2 + (i * Math.PI) / 5, r = i % 2 ? 5.2 : 12; ctx.lineTo(Math.cos(a) * r, Math.sin(a) * r + 1); }
      ctx.closePath(); ctx.fill();
    },
    heart(ctx) {
      appBg(ctx, [255, 140, 170], [222, 60, 110]);
      ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.moveTo(0, 11); ctx.bezierCurveTo(-16, 0, -9, -14, 0, -5); ctx.bezierCurveTo(9, -14, 16, 0, 0, 11); ctx.fill();
    },
    download(ctx) {
      appBg(ctx, [255, 214, 70], [236, 160, 20]);
      ctx.fillStyle = '#fff'; ctx.fillRect(-3, -12, 6, 12); ctx.beginPath(); ctx.moveTo(-9, -1); ctx.lineTo(9, -1); ctx.lineTo(0, 9); ctx.fill(); rr(ctx, -12, 10, 24, 3, 1.5); ctx.fill();
    },
  };

  function drawArt(ctx, s, kind) {
    ctx.save(); rr(ctx, -19, -19, 38, 38, 3); ctx.clip();
    if (kind === 'theme') {
      ctx.fillStyle = '#4b6bf5'; ctx.fillRect(-19, -19, 38, 38);
      if (s.icon) { ctx.imageSmoothingEnabled = true; ctx.drawImage(s.icon, -19, -19, 38, 38); }
    } else (ART[kind] || ART.game)(ctx);
    ctx.restore();
    ctx.strokeStyle = 'rgba(0,0,0,.14)'; ctx.lineWidth = 0.75; rr(ctx, -18.6, -18.6, 37.2, 37.2, 3); ctx.stroke();
  }

  // ───────────── Grid pieces (all drawn centered on 0,0 at icon scale) ─────────────
  /** The frame every app icon sits in (the "file" colors / picture). */
  function drawFileFrame(ctx, s) {
    const fc = col(s, 'file'), f = s.theme.flags, tex = f.fileTexture ? s.images.fileLarge : null;
    withShadow(ctx, cssA(fc.shadow), 4, 0, 2, () => { rr(ctx, -24, -24, 48, 48, 8); ctx.fillStyle = css(fc.main); ctx.fill(); });
    if (tex) {
      // The picture holds the left half of the frame; the console mirrors it for the right half.
      ctx.save(); rr(ctx, -24, -24, 48, 48, 8); ctx.clip(); ctx.imageSmoothingEnabled = true;
      ctx.drawImage(tex, 1, 1, 34, 69, -24, -24, 24, 48);
      ctx.scale(-1, 1); ctx.drawImage(tex, 1, 1, 34, 69, -24, -24, 24, 48);
      ctx.restore(); return;
    }
    ctx.save(); rr(ctx, -24, -24, 48, 48, 8); ctx.clip();
    ctx.lineWidth = 3.2; ctx.strokeStyle = lin(ctx, 0, -24, 0, 24, [[0, css(fc.light)], [1, css(fc.shading)]]); rr(ctx, -24, -24, 48, 48, 8); ctx.stroke();
    ctx.restore();
    ctx.lineWidth = 0.8; ctx.strokeStyle = css(fc.shading, 0.9); rr(ctx, -23.6, -23.6, 47.2, 47.2, 7.8); ctx.stroke();
  }
  function drawAppTile(ctx, s, kind) { drawFileFrame(ctx, s); drawArt(ctx, s, kind); }

  /** The game card slot with no card inserted (not affected by themes). */
  function drawCardSlot(ctx) {
    withShadow(ctx, 'rgba(0,0,0,.18)', 3, 0, 1.5, () => { rr(ctx, -24, -24, 48, 48, 8); ctx.fillStyle = '#e0e0de'; ctx.fill(); });
    ctx.fillStyle = '#d3d3d1'; ctx.strokeStyle = '#b9b9b7'; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(-12, -16); ctx.lineTo(9, -16); ctx.lineTo(14, -11); ctx.lineTo(14, 16); ctx.lineTo(-12, 16); ctx.quadraticCurveTo(-14, 16, -14, 14); ctx.lineTo(-14, -14); ctx.quadraticCurveTo(-14, -16, -12, -16); ctx.closePath(); ctx.fill(); ctx.stroke();
    ctx.fillStyle = '#e0e0de'; rr(ctx, -9, -11, 18, 15, 2); ctx.fill();
    for (let i = 0; i < 5; i++) { ctx.fillStyle = '#c4c4c2'; ctx.fillRect(-8 + i * 4, 9, 2.4, 5); }
  }

  const P_BACK = (() => { const p = new Path2D(); p.moveTo(-24, 0); p.lineTo(-24, -17); p.arcTo(-24, -20, -21, -20, 3); p.lineTo(-5, -20); p.lineTo(-3, -17); p.lineTo(21, -17); p.arcTo(24, -17, 24, -14, 3); p.lineTo(24, 0); p.closePath(); return p; })();
  const P_FRONT_CLOSED = (() => { const p = new Path2D(); p.roundRect(-24, -14, 48, 36, 3); return p; })();
  const P_FRONT_OPEN = (() => { const p = new Path2D(); p.moveTo(-21, -6); p.lineTo(21, -6); p.quadraticCurveTo(24, -6, 24, -3); p.lineTo(21, 19); p.quadraticCurveTo(21, 22, 18, 22); p.lineTo(-18, 22); p.quadraticCurveTo(-21, 22, -21, 19); p.lineTo(-24, -3); p.quadraticCurveTo(-24, -6, -21, -6); p.closePath(); return p; })();
  const P_WHOLE = (() => { const p = new Path2D(); p.addPath(P_BACK); p.addPath(P_FRONT_CLOSED); return p; })();
  /** A HOME Menu folder icon; open shows the front flap tipped forward. */
  function drawFolderIcon(ctx, s, open) {
    const fc = col(s, 'folder'), f = s.theme.flags, front = open ? P_FRONT_OPEN : P_FRONT_CLOSED;
    const tex = f.folderTexture ? s.images[open ? 'folderOpen' : 'folderClosed'] : null;
    if (tex) {
      withShadow(ctx, css(fc.shadow, 0.45), 4, 0, 2, () => { ctx.fillStyle = css(fc.main); ctx.fill(P_WHOLE, 'nonzero'); });
      ctx.save(); ctx.clip(P_WHOLE, 'nonzero'); ctx.imageSmoothingEnabled = true;
      ctx.drawImage(tex, 0, 0, open ? 82 : 74, 64, -24, -20, 48, 42); ctx.restore(); return;
    }
    // back panel with tab
    withShadow(ctx, css(fc.shadow, 0.45), 4, 0, 2, () => { ctx.fillStyle = lin(ctx, 0, -20, 0, 0, [[0, css(mix(fc.main, WHITE, 0.25))], [1, css(fc.shading)]]); ctx.fill(P_BACK); });
    // a file peeking out
    ctx.save(); ctx.beginPath(); ctx.rect(-20, -23, 40, open ? 18 : 9); ctx.clip();
    const fl = col(s, 'file'); rr(ctx, -15, -17, 30, 36, 4); ctx.fillStyle = css(fl.main); ctx.fill(); ctx.strokeStyle = css(fl.shading); ctx.lineWidth = 1; ctx.stroke(); ctx.restore();
    // front flap
    withShadow(ctx, css(fc.shadow, 0.3), 2, 0, open ? 2 : 1, () => { ctx.fillStyle = lin(ctx, 0, open ? -6 : -14, 0, 22, [[0, css(fc.light)], [1, css(fc.main)]]); ctx.fill(front); });
    ctx.strokeStyle = css(fc.shading); ctx.lineWidth = 0.9; ctx.stroke(front);
    ctx.strokeStyle = css(mix(fc.light, WHITE, 0.5), 0.8); ctx.lineWidth = 0.8; ctx.beginPath(); ctx.moveTo(-20, open ? -4.5 : -12.5); ctx.lineTo(20, open ? -4.5 : -12.5); ctx.stroke();
  }

  /** The four-corner selection cursor, pulsing like the console's. */
  function cursorPath(ctx) {
    ctx.beginPath(); ctx.roundRect(-27, -27, 54, 54, 6); ctx.roundRect(-23, -23, 46, 46, 4);
  }
  function drawCursor(ctx, s) {
    const cc = col(s, 'cursor'), t = s.forExport ? 0.5 : (Math.sin(s.time * Math.PI * 2) + 1) / 2;
    const k = 1 + 0.05 * t;
    ctx.save(); ctx.scale(k, k);
    // keep only the corners: cut away a diamond through the middle of each side
    ctx.beginPath(); ctx.rect(-40, -40, 80, 80); ctx.moveTo(0, -38.2); ctx.lineTo(-38.2, 0); ctx.lineTo(0, 38.2); ctx.lineTo(38.2, 0); ctx.closePath(); ctx.clip('evenodd');
    withShadow(ctx, css(cc.glow, 0.95), 5 + 5 * t, 0, 0, () => { cursorPath(ctx); ctx.fillStyle = css(cc.glow, 0.35 + 0.6 * t); ctx.fill('evenodd'); });
    cursorPath(ctx); ctx.fillStyle = lin(ctx, 0, -27, 0, 27, [[0, css(mix(cc.main, cc.light, 0.45))], [0.5, css(cc.main)], [1, css(cc.main)]]); ctx.fill('evenodd');
    ctx.strokeStyle = css(cc.shading); ctx.lineWidth = 1; cursorPath(ctx); ctx.stroke();
    ctx.strokeStyle = css(cc.light, 0.9); ctx.lineWidth = 0.8; rr(ctx, -25.6, -25.6, 51.2, 51.2, 5); ctx.stroke();
    ctx.restore();
  }

  // ───────────── Bottom screen ─────────────
  const COLS = [54, 107, 160, 213, 266, 320], ROWS = [70, 123, 176], FROWS = [112, 166];

  function drawPanel(ctx, p, area) {
    const [x, y, w, h] = area, R = 10, a = ((p.glow[3] ?? 255) / 255) / 25;
    ctx.fillStyle = css(p.glow, a);
    for (let dx = -2; dx <= 2; dx++) for (let dy = -2; dy <= 2; dy++) { rr(ctx, x + dx, y + dy + 2, w, h, R); ctx.fill(); }
    rr(ctx, x, y, w, h, R); ctx.fillStyle = css(p.main); ctx.fill(); ctx.strokeStyle = css(p.border); ctx.lineWidth = 1; ctx.stroke();
    ctx.strokeStyle = css(p.highlight); ctx.lineWidth = 0.5; ctx.beginPath(); ctx.moveTo(x + R, y + h + 1); ctx.lineTo(x + w - 2 * R, y + h + 1); ctx.stroke();
  }
  function drawSlotMarks(ctx, p, rows, solid, skip) {
    for (const cx of COLS) for (const cy of rows) {
      if (skip(cx, cy)) continue;
      if (solid) {
        rr(ctx, cx - 8.5, cy - 8.5, 16, 16, 2); ctx.strokeStyle = css(p.border); ctx.lineWidth = 1; ctx.stroke();
        ctx.strokeStyle = css(p.highlight); ctx.lineWidth = 0.5; ctx.beginPath(); ctx.moveTo(cx - 6.5, cy - 8.5); ctx.lineTo(cx + 5.5, cy - 8.5); ctx.stroke();
      } else { rr(ctx, cx - 8, cy - 8, 16, 16, 2); ctx.fillStyle = 'rgba(255,255,255,.2)'; ctx.fill(); }
    }
  }

  function drawBottomBackground(ctx, s, mode, occupied) {
    const f = s.theme.flags, c = s.theme.colors, images = s.images, folder = mode === 'folder';
    const area = folder ? [12, 69, 320, 140] : [12, 39, 320, 170], rows = folder ? FROWS : ROWS;
    const panel = folder ? col(s, 'folderBackground') : col(s, 'bottomInner');
    if (f.bottomDrawType === 3 && images.bottom) {
      let x = 0;
      if (!s.forExport) {
        const t = f.bottomFrameType, tm = s.time;
        if (t === 0 || t === 3) x = (Math.sin(tm / (t === 0 ? 2 : 3)) + 1) / 2 * (1008 - 320);
        else if (t === 2) x = (Math.floor(tm / 2.5) % 3) * 320;
        else if (t === 4) x = [0, 1, 2, 1][Math.floor(tm / 2.5) % 4] * 320;
      }
      ctx.drawImage(images.bottom, -x, 0);
      if (folder && f.folderBackgroundColor) { drawPanel(ctx, c.folderBackground, area); drawSlotMarks(ctx, c.folderBackground, rows, true, occupied); }
      else if (mode !== 'zoom') drawSlotMarks(ctx, panel, rows, false, occupied);
      return;
    }
    const o = col(s, 'bottomOuter');
    ctx.fillStyle = css(o.main); ctx.fillRect(0, 0, 320, 240);
    ctx.fillStyle = lin(ctx, 0, 0, 24, 0, [[0, css(o.glow)], [0.3, css(o.glow)], [1, css(o.main)]]); ctx.fillRect(0, 0, 24, 240);
    ctx.fillStyle = lin(ctx, 296, 0, 320, 0, [[0, css(o.main)], [0.7, css(o.glow)], [1, css(o.glow)]]); ctx.fillRect(296, 0, 24, 240);
    for (let i = 0; i < 7; i++) { ctx.strokeStyle = css(o.stripes, (1 - i / 7) / 2 + 0.15); ctx.lineWidth = 0.6; ctx.beginPath(); ctx.moveTo(0, 240 - 4 * i - 2.5); ctx.lineTo(320, 240 - 4 * i - 2.5); ctx.stroke(); }
    drawPanel(ctx, panel, area);
    if (mode !== 'zoom') drawSlotMarks(ctx, panel, rows, true, occupied);
  }

  /** HOME Menu settings (left) and icon-size buttons (right) along the top of the bottom screen. */
  function drawCornerButtons(ctx, s) {
    const bc = col(s, 'bottomCorner');
    for (const x of [-8, 268]) {
      withShadow(ctx, css(bc.baseShadow, 0.35), 4, 0, 1.5, () => { rr(ctx, x, -8, 59, 38, 8); ctx.fillStyle = css(bc.main); ctx.fill(); });
      rr(ctx, x, -8, 59, 38, 8); ctx.fillStyle = lin(ctx, 0, -8, 0, 30, [[0, css(bc.highlight)], [0.55, css(bc.main)], [1, css(mix(bc.main, BLACK, 0.06))]]); ctx.fill();
      ctx.strokeStyle = css(bc.border); ctx.lineWidth = 1; rr(ctx, x + 0.5, -7.5, 58, 37, 8); ctx.stroke();
    }
    const glyph = () => lin(ctx, 0, 4, 0, 27, [[0, css(bc.iconTop)], [1, css(bc.iconBottom)]]);
    const well = (x, y, w, h) => { rr(ctx, x, y, w, h, 3); ctx.fillStyle = 'rgba(255,255,255,.08)'; ctx.fill(); ctx.strokeStyle = css(bc.iconText, 0.55); ctx.lineWidth = 0.75; ctx.stroke(); };
    // left: HOME Menu settings (a house with a brush)
    well(3, 3, 45, 25);
    ctx.save(); ctx.translate(13, 5); ctx.fillStyle = glyph();
    ctx.beginPath(); ctx.moveTo(1, 9); ctx.lineTo(10, 0); ctx.lineTo(18, 8); ctx.lineTo(15, 11); ctx.lineTo(15, 18); ctx.lineTo(5, 18); ctx.quadraticCurveTo(3, 18, 3, 16); ctx.lineTo(3, 9); ctx.closePath(); ctx.fill();
    ctx.fillStyle = css(bc.main); ctx.fillRect(7.5, 11, 5, 7);
    ctx.fillStyle = glyph(); ctx.beginPath(); ctx.moveTo(16, 19); ctx.lineTo(22, 10); ctx.quadraticCurveTo(25, 9, 25, 12); ctx.lineTo(19, 21); ctx.quadraticCurveTo(16, 23, 16, 19); ctx.fill();
    ctx.restore();
    // right: larger / smaller icons
    well(271, 4, 20, 23); well(297, 4, 20, 23);
    ctx.fillStyle = glyph(); rr(ctx, 275, 10, 12, 12, 3); ctx.fill();
    for (const [dx, dy] of [[0, 0], [7, 0], [0, 7], [7, 7]]) { rr(ctx, 301 + dx, 10 + dy, 5, 5, 1); ctx.fill(); }
    ctx.strokeStyle = css(bc.border); ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(293.5, 4); ctx.lineTo(293.5, 27); ctx.stroke();
    ctx.strokeStyle = css(bc.highlight); ctx.beginPath(); ctx.moveTo(294.5, 4); ctx.lineTo(294.5, 27); ctx.stroke();
  }

  /** The row of built-in program shortcuts between the corner buttons (not affected by themes). */
  function drawShortcuts(ctx) {
    const items = [
      [[255, 205, 60], (x) => { ctx.fillStyle = '#fff'; rr(ctx, x - 6, -6, 11, 13, 1.5); ctx.fill(); ctx.strokeStyle = '#d29a10'; ctx.lineWidth = 1; for (let i = 0; i < 3; i++) { ctx.beginPath(); ctx.moveTo(x - 4, -3 + i * 3.5); ctx.lineTo(x + 3, -3 + i * 3.5); ctx.stroke(); } }],
      [[255, 150, 70], (x) => { ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(x, 0, 7, 0, 7); ctx.fill(); ctx.fillStyle = '#ff8a3c'; ctx.beginPath(); ctx.arc(x - 2.5, -1.5, 1.2, 0, 7); ctx.arc(x + 2.5, -1.5, 1.2, 0, 7); ctx.fill(); ctx.strokeStyle = '#ff8a3c'; ctx.lineWidth = 1.2; ctx.beginPath(); ctx.arc(x, 0.5, 3.6, 0.2, Math.PI - 0.2); ctx.stroke(); }],
      [[110, 205, 90], (x) => { ctx.fillStyle = '#fff'; rr(ctx, x - 7, -6, 14, 10, 3); ctx.fill(); ctx.beginPath(); ctx.moveTo(x - 3, 3); ctx.lineTo(x - 5, 7.5); ctx.lineTo(x + 1, 3); ctx.fill(); ctx.fillStyle = '#4fb53a'; ctx.fillRect(x - 0.8, -4.5, 1.6, 4); ctx.fillRect(x - 0.8, 0.5, 1.6, 1.6); }],
      [[80, 160, 250], (x) => { ctx.strokeStyle = '#fff'; ctx.lineWidth = 1.4; ctx.beginPath(); ctx.arc(x, 0, 6.5, 0, 7); ctx.moveTo(x - 6.5, 0); ctx.lineTo(x + 6.5, 0); ctx.stroke(); ctx.beginPath(); ctx.ellipse(x, 0, 3, 6.5, 0, 0, 7); ctx.stroke(); }],
      [[160, 120, 240], (x) => { ctx.fillStyle = '#fff'; rr(ctx, x - 7, -6, 10, 8, 2.5); ctx.fill(); rr(ctx, x - 2, -2, 10, 8, 2.5); ctx.fill(); ctx.fillStyle = '#a078f0'; ctx.fillRect(x, 1, 6, 1.2); }],
    ];
    items.forEach(([c, draw], i) => {
      const x = 82 + i * 39;
      ctx.save(); ctx.translate(0, 14);
      withShadow(ctx, 'rgba(0,0,0,.25)', 2, 0, 1, () => { rr(ctx, x - 12, -10, 24, 20, 5); ctx.fillStyle = lin(ctx, 0, -10, 0, 10, [[0, css(mix(c, WHITE, 0.25))], [1, css(c)]]); ctx.fill(); });
      ctx.strokeStyle = 'rgba(255,255,255,.7)'; ctx.lineWidth = 0.8; rr(ctx, x - 11.6, -9.6, 23.2, 19.2, 4.6); ctx.stroke();
      draw(x); ctx.restore();
    });
  }

  /** The half-round scroll button on the right edge. */
  function drawArrowButton(ctx, s, pressed) {
    const ab = col(s, 'arrowButton'), ar = col(s, 'arrow'), shift = pressed ? 2 : 0;
    ctx.save(); ctx.translate(shift, 0);
    withShadow(ctx, cssA(ab.shadow), 4, -1, 1, () => { ctx.beginPath(); ctx.ellipse(338, 123, 38, 39, 0, 0, 7); ctx.fillStyle = css(ab.main); ctx.fill(); });
    ctx.save(); ctx.beginPath(); ctx.ellipse(338, 123, 38, 39, 0, 0, 7); ctx.clip();
    ctx.fillStyle = lin(ctx, 0, 84, 0, 162, [[0, css(ab.main, 0)], [0.5, css(ab.main, 0)], [1, css(ab.shading, 0.95)]]); ctx.fillRect(296, 80, 30, 86);
    ctx.fillStyle = lin(ctx, 300, 0, 312, 0, [[0, css(ab.light, 0.95)], [1, css(ab.light, 0)]]); ctx.fillRect(296, 80, 30, 86);
    ctx.restore();
    ctx.strokeStyle = 'rgba(255,255,255,.9)'; ctx.lineWidth = 1; ctx.beginPath(); ctx.ellipse(338, 123, 37.5, 38.5, 0, Math.PI * 0.62, Math.PI * 1.38); ctx.stroke();
    ctx.translate(303, 123);
    ctx.beginPath(); ctx.moveTo(1, 2); ctx.lineTo(7, 2); ctx.lineTo(7, 7); ctx.lineTo(14, 0); ctx.lineTo(7, -7); ctx.lineTo(7, -2); ctx.lineTo(1, -2); ctx.quadraticCurveTo(0, -2, 0, 0); ctx.quadraticCurveTo(0, 2, 1, 2); ctx.closePath();
    ctx.fillStyle = css(pressed ? ar.pressed : ar.unpressed); ctx.fill(); ctx.strokeStyle = css(ar.border); ctx.lineWidth = 1; ctx.stroke();
    ctx.restore();
  }

  /** The Open bar across the bottom (or Close + Resume when software is suspended). */
  function drawButtonBar(ctx, s, mode, pressed) {
    const title = s.title || 'My Theme';
    const one = (o, x, w, label, roundLeft, roundRight, isPressed) => {
      const path = () => { ctx.beginPath(); ctx.roundRect(x, 215, w, 50, [roundLeft ? 10 : 0, roundRight ? 10 : 0, 0, 0]); };
      withShadow(ctx, cssA(o.shadow), 5, 0, -1, () => { path(); ctx.fillStyle = css(o.unpressed); ctx.fill(); });
      path(); ctx.fillStyle = lin(ctx, 0, 215, 0, 240, [[0, css(o.light)], [1, css(isPressed ? o.pressed : o.unpressed)]]); ctx.fill();
      ctx.save(); path(); ctx.clip();
      ctx.strokeStyle = css(o.glow); ctx.lineWidth = 1.2; ctx.beginPath(); ctx.moveTo(x + (roundLeft ? 8 : 0), 216); ctx.lineTo(x + w - (roundRight ? 8 : 0), 216); ctx.stroke();
      ctx.restore();
      ctx.strokeStyle = css(mix(o.unpressed, BLACK, 0.12)); ctx.lineWidth = 0.8; path(); ctx.stroke();
      const t = fitText(ctx, label, w - 16, 13), dy = Math.max(-3, Math.min(3, o.textShadowPosition)) * 1.2, ty = 227.5 + (isPressed ? 1 : 0);
      text(ctx, t, x + w / 2, ty - dy, 13, css(o.textShadow)); text(ctx, t, x + w / 2, ty, 13, css(isPressed ? o.textPressed : o.textUnpressed));
    };
    if (mode === 'paused') {
      one(col(s, 'close'), 0, 106, 'Close', true, false, pressed);
      one(col(s, 'open'), 106, 214, title, false, true, false);
      ctx.strokeStyle = 'rgba(0,0,0,.25)'; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(106, 217); ctx.lineTo(106, 240); ctx.stroke();
    } else one(col(s, 'open'), 0, 320, title, true, true, pressed);
  }

  /** The button that leaves a folder, and the folder's name. */
  function drawFolderHeader(ctx, s, pressed) {
    const fa = col(s, 'folderArrow');
    withShadow(ctx, cssA(fa.shadow), 4, 0, 2, () => { rr(ctx, 27, 47, 66, 30, 8); ctx.fillStyle = css(fa.main); ctx.fill(); });
    rr(ctx, 27, 47, 66, 30, 8); ctx.fillStyle = lin(ctx, 0, 47, 0, 77, [[0, css(fa.highlight)], [0.3, css(fa.main)], [1, css(pressed ? mix(fa.main, BLACK, 0.2) : fa.main)]]); ctx.fill();
    ctx.strokeStyle = css(fa.shading); ctx.lineWidth = 1; rr(ctx, 27.5, 47.5, 65, 29, 8); ctx.stroke();
    ctx.strokeStyle = css(fa.glow); ctx.lineWidth = 0.9; ctx.beginPath(); ctx.moveTo(35, 49); ctx.lineTo(85, 49); ctx.stroke();
    const arrow = () => { ctx.beginPath(); ctx.moveTo(7, 4); ctx.lineTo(10, 4); ctx.arc(10, 10, 6, -Math.PI / 2, Math.PI / 2); ctx.lineTo(7, 16); ctx.lineTo(7, 13); ctx.lineTo(10, 13); ctx.arc(10, 10, 3, Math.PI / 2, -Math.PI / 2, true); ctx.lineTo(7, 7); ctx.lineTo(7, 10); ctx.lineTo(0, 5.5); ctx.lineTo(7, 0); ctx.closePath(); };
    const dy = Math.max(-3, Math.min(3, fa.arrowShadowPosition)) * 1.2;
    ctx.save(); ctx.translate(51, 52 + (pressed ? 1 : 0));
    ctx.save(); ctx.translate(0, -dy); arrow(); ctx.fillStyle = css(fa.arrowGlow, 0.8); ctx.fill(); ctx.restore();
    arrow(); ctx.fillStyle = css(pressed ? fa.arrowPressed : fa.arrowUnpressed); ctx.fill();
    ctx.restore();
    outlinedText(ctx, 'My Folder', 104, 62, 13, '#3d3d3d', 'rgba(255,255,255,.95)', 'left');
  }

  const HOME_GRID = [
    [0, 0, 'card'], [1, 0, 'theme'], [2, 0, 'folder'], [3, 0, 'camera'], [4, 0, 'music'],
    [0, 1, 'settings'], [1, 1, 'browser'], [2, 1, 'shop'], [3, 1, 'mail'],
    [0, 2, 'game'], [1, 2, 'download'],
  ];
  const FOLDER_GRID = [[0, 0, 'theme'], [1, 0, 'heart'], [2, 0, 'game'], [0, 1, 'music']];

  function drawBottom(ctx, s) {
    const mode = modeOf(s), time = s.time, ex = s.forExport;
    ctx.save(); ctx.beginPath(); ctx.rect(0, 0, 320, 240); ctx.clip();
    const grid = mode === 'folder' ? FOLDER_GRID : HOME_GRID, rows = mode === 'folder' ? FROWS : ROWS;
    const taken = new Set(grid.map(([c, r]) => COLS[c] + ',' + rows[r]));
    drawBottomBackground(ctx, s, mode, (x, y) => taken.has(x + ',' + y));

    const placeAt = (x, y, k, fn) => { ctx.save(); ctx.translate(x, y); ctx.scale(k, k); fn(); ctx.restore(); };
    const drawItem = (kind) => (kind === 'card' ? drawCardSlot(ctx) : kind === 'folder' ? drawFolderIcon(ctx, s, false) : drawAppTile(ctx, s, kind));
    if (mode === 'zoom') {
      // Largest icon size: one big row, with the selected title shown above the cursor.
      const k = 1.72, y = 132, xs = [-12, 160, 332], kinds = ['card', 'theme', 'folder'];
      xs.forEach((x, i) => placeAt(x, y, k, () => drawItem(kinds[i])));
      placeAt(160, y, k, () => drawCursor(ctx, s));
      const gt = s.theme.flags.gameTextDrawType;
      if (gt !== 2) {
        const g = col(s, 'gameText'), label = fitText(ctx, s.title || 'My Theme', 200, 12), w = Math.max(90, ctx.measureText(label).width + 28);
        withShadow(ctx, cssA(g.shadow), 4, 0, 2, () => { rr(ctx, 160 - w / 2, 50, w, 24, 7); ctx.fillStyle = css(g.main); ctx.fill(); });
        ctx.beginPath(); ctx.moveTo(154, 74); ctx.lineTo(160, 80); ctx.lineTo(166, 74); ctx.fillStyle = css(g.main); ctx.fill();
        rr(ctx, 160 - w / 2, 50, w, 24, 7); ctx.fillStyle = lin(ctx, 0, 50, 0, 74, [[0, css(g.light)], [0.6, css(g.main, 0)]]); ctx.fill();
        text(ctx, label, 160, 62.5, 12, css(g.text));
      }
    } else {
      for (const [c, r, kind] of grid) placeAt(COLS[c], rows[r], 1, () => drawItem(kind));
      placeAt(COLS[1], rows[0], 1, () => drawCursor(ctx, s));
    }
    if (mode === 'folder') drawFolderHeader(ctx, s, !ex && Math.floor(time / 1.7) % 4 === 3);
    drawCornerButtons(ctx, s);
    drawShortcuts(ctx);
    if (mode !== 'folder') drawArrowButton(ctx, s, !ex && Math.floor(time / 1.5) % 4 === 3);
    drawButtonBar(ctx, s, mode, !ex && Math.floor(time / 2) % 5 === 4);
    ctx.restore();
  }

  // ───────────── Top screen ─────────────
  function drawStatusBar(ctx, s) {
    const now = s.clock || new Date(), blink = s.forExport || Math.floor(s.time * 2) % 2 === 0;
    const day = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][now.getDay()];
    // signal + "Internet"
    ctx.save(); ctx.translate(8, 3);
    const bars = [[3, 7, 3, 10], [7, 12, 5, 5], [12, 7, 5, 10], [17, 2, 5, 15]];
    ctx.fillStyle = '#27b7eb'; ctx.strokeStyle = '#fff'; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.arc(4, 4, 2.5, 0, 7); ctx.fill(); ctx.stroke();
    for (const [x, y, w, h] of bars.slice(0, 1)) { ctx.fillRect(x, y, w, h); ctx.strokeRect(x, y, w, h); }
    for (const [x, y, w, h] of bars.slice(1)) { ctx.fillRect(x, y, w, h); ctx.strokeRect(x, y, w, h); }
    ctx.restore();
    rr(ctx, 33, 3, 104, 16, 2.5); ctx.fillStyle = lin(ctx, 0, 3, 0, 19, [[0, '#31aadf'], [0.5, '#59c3f3'], [0.5, '#31aadf'], [1, '#59c3f3']]); ctx.fill(); ctx.strokeStyle = '#fff'; ctx.lineWidth = 0.8; ctx.stroke();
    text(ctx, 'Internet', 85, 11.5, 11, '#fff', 'center', 700);
    // coins
    ctx.beginPath(); ctx.arc(155, 11, 7, 0, 7); ctx.fillStyle = '#d5c500'; ctx.fill(); ctx.strokeStyle = '#fff'; ctx.lineWidth = 0.8; ctx.stroke();
    ctx.strokeStyle = '#fff'; ctx.lineWidth = 1; ctx.strokeRect(153, 8, 4, 6); ctx.beginPath(); ctx.moveTo(153, 11); ctx.lineTo(157, 11); ctx.stroke();
    outlinedText(ctx, '300', 166, 11.5, 12, '#3d3d3d', '#fff', 'left');
    // date, time, battery
    const hh = String(now.getHours()), mm = String(now.getMinutes()).padStart(2, '0');
    outlinedText(ctx, `${now.getMonth() + 1}/${now.getDate()} (${day})`, 300, 11.5, 12, '#3d3d3d', '#fff', 'right');
    outlinedText(ctx, hh, 340, 11.5, 12, '#3d3d3d', '#fff', 'right');
    if (blink) outlinedText(ctx, ':', 343, 10.5, 12, '#3d3d3d', '#fff', 'center');
    outlinedText(ctx, mm, 346, 11.5, 12, '#3d3d3d', '#fff', 'left');
    ctx.fillStyle = '#000'; ctx.strokeStyle = '#fff'; ctx.lineWidth = 1;
    rr(ctx, 376, 3, 27, 16, 2); ctx.fill(); ctx.stroke(); ctx.fillRect(373.5, 8, 2.5, 6); ctx.strokeRect(373.5, 8, 2.5, 6);
    ctx.fillStyle = lin(ctx, 0, 6, 0, 16, [[0, '#7fe08a'], [0.3, '#fff'], [0.45, '#3fb54d'], [1, '#2a9a3a']]); ctx.fillRect(380, 6, 20, 10);
  }

  /** The camera shortcut tabs in the lower corners of the top screen. */
  function drawCameraTabs(ctx, s) {
    const tc = col(s, 'topCorner'), fg = css(tc.text);
    ctx.save(); ctx.translate(0, 217);
    const shape = () => {
      ctx.beginPath(); ctx.moveTo(0, 23); ctx.lineTo(0, 0); ctx.lineTo(76, 0); ctx.quadraticCurveTo(88, 0, 90, 10); ctx.lineTo(92, 23); ctx.closePath();
      ctx.moveTo(320, 23); ctx.lineTo(323, 10); ctx.quadraticCurveTo(326, 0, 334, 0); ctx.lineTo(412, 0); ctx.lineTo(412, 23); ctx.closePath();
    };
    withShadow(ctx, css(tc.shadow, 0.5), 3, 0, 0, () => { shape(); ctx.fillStyle = css(tc.main, 0.78); ctx.fill(); });
    shape(); ctx.fillStyle = lin(ctx, 0, 0, 0, 12, [[0, css(tc.light, 0.55)], [1, css(tc.light, 0)]]); ctx.fill();
    // left: camera + Y
    ctx.strokeStyle = fg; ctx.fillStyle = fg; ctx.lineWidth = 1.8;
    ctx.save(); ctx.translate(20, 5);
    ctx.beginPath(); ctx.moveTo(9, 12); ctx.lineTo(2, 12); ctx.quadraticCurveTo(0, 12, 0, 10); ctx.lineTo(0, 2); ctx.quadraticCurveTo(0, 0, 2, 0); ctx.lineTo(15, 0); ctx.quadraticCurveTo(17, 0, 17, 2); ctx.stroke();
    rr(ctx, 11, 6, 12, 8, 1.5); ctx.fill(); rr(ctx, 14, 4, 6, 4, 2); ctx.fill();
    ctx.fillStyle = css(tc.main); ctx.beginPath(); ctx.arc(17, 10, 2.3, 0, 7); ctx.fill(); ctx.restore();
    ctx.beginPath(); ctx.arc(60, 11, 7.5, 0, 7); ctx.lineWidth = 1.6; ctx.stroke(); text(ctx, 'Y', 60, 11.5, 10, fg, 'center', 800);
    // right: camera + L + R
    ctx.save(); ctx.translate(318, 5); ctx.fillStyle = fg; rr(ctx, 0, 2, 16, 12, 1.5); ctx.fill(); rr(ctx, 4, 0, 8, 4, 2); ctx.fill();
    ctx.fillStyle = css(tc.main); ctx.beginPath(); ctx.arc(8, 8, 3, 0, 7); ctx.fill(); ctx.restore();
    const lr = (x, flip, ch) => { ctx.save(); ctx.translate(x, 5); ctx.beginPath(); if (!flip) { ctx.moveTo(0, 13); ctx.quadraticCurveTo(2, 0, 3, 0); ctx.lineTo(16, 0); ctx.quadraticCurveTo(15, 2, 13, 13); } else { ctx.moveTo(16, 13); ctx.quadraticCurveTo(14, 0, 13, 0); ctx.lineTo(0, 0); ctx.quadraticCurveTo(1, 2, 3, 13); } ctx.closePath(); ctx.lineWidth = 1.4; ctx.strokeStyle = fg; ctx.stroke(); text(ctx, ch, 8, 7, 9.5, fg, 'center', 800); ctx.restore(); };
    lr(338, false, 'L'); text(ctx, '+', 367, 11.5, 11, fg, 'center', 800); lr(372, true, 'R');
    ctx.restore();
  }

  function drawTop(ctx, s) {
    const { theme, images, time, forExport } = s, f = theme.flags, c = theme.colors, mode = modeOf(s);
    ctx.save(); ctx.beginPath(); ctx.rect(0, 0, 412, 240); ctx.clip();
    const drawDefault = () => {
      ctx.fillStyle = lin(ctx, 0, 0, 0, 240, [[0, '#f4f4f6'], [1, '#d9d9e0']]); ctx.fillRect(0, 0, 412, 240);
      ctx.strokeStyle = 'rgba(255,255,255,.55)'; ctx.lineWidth = 1;
      const off = forExport ? 0 : (time * 6) % 24;
      for (let x = -240 + off; x < 412; x += 24) { ctx.beginPath(); ctx.moveTo(x, 240); ctx.lineTo(x + 240, 0); ctx.stroke(); }
    };
    if (f.topDrawType === 1 || f.topDrawType === 2) {
      const tb = c.topBackground;
      ctx.fillStyle = css(tb.main); ctx.fillRect(0, 0, 412, 240);
      const g = [tb.gradientColor, tb.gradientColor, tb.gradientColor], k = tb.gradient / 255;
      ctx.fillStyle = lin(ctx, 0, 0, 0, 240, [[0, css(g, k * 0.85)], [1, css(g, 0)]]); ctx.fillRect(0, 0, 412, 240);
      if (f.topDrawType === 2) {
        const off = forExport ? 0 : (time * 8) % 64, p = images.topPattern || images.__defaultPattern;
        if (p) { ctx.globalAlpha = tb.textureOpacity / 255; drawImageTiled(ctx, p, 412, 240, off, off); }
        if (images.topAltPattern) { ctx.globalAlpha = tb.alternateOpacity / 255; drawImageTiled(ctx, images.topAltPattern, 412, 240, -off, off * 0.5); }
        ctx.globalAlpha = 1;
      }
    } else if (f.topDrawType === 3 && images.top) {
      let x = 0;
      if (f.topFrameType !== 1 && !forExport) { const speed = f.topFrameType === 0 ? 2 : 3; x = (Math.sin(time / speed) + 1) / 2 * (1008 - 412); }
      ctx.drawImage(images.top, -x, 0);
    } else drawDefault();

    if (mode === 'folder') {
      // The selected folder floats in the middle of the top screen.
      const bob = forExport ? 0 : Math.sin(time * 1.6) * 4, tilt = forExport ? 0 : Math.sin(time * 0.8) * 0.06;
      ctx.save(); ctx.translate(206, 118 + bob); ctx.rotate(tilt); ctx.scale(2.7, 2.7); drawFolderIcon(ctx, s, true); ctx.restore();
    }
    if (f.demoTextColor && mode !== 'folder') {
      const d = c.demoText; withShadow(ctx, 'rgba(0,0,0,.3)', 4, 0, 1, () => { rr(ctx, 116, 176, 180, 24, 6); ctx.fillStyle = css(d.main, 0.95); ctx.fill(); });
      text(ctx, 'Remaining uses: 10', 206, 188.5, 11.5, css(d.text), 'center', 700);
    }
    drawStatusBar(ctx, s);
    drawCameraTabs(ctx, s);
    if (!forExport) { ctx.fillStyle = 'rgba(0,0,0,.22)'; ctx.fillRect(0, 0, 6, 240); ctx.fillRect(406, 0, 6, 240); }
    ctx.restore();
  }

  /** Renders the 412×480 preview.png used by theme managers. */
  function exportCanvas(state) {
    const c = document.createElement('canvas'); c.width = 412; c.height = 480;
    const ctx = c.getContext('2d');
    ctx.fillStyle = '#141414'; ctx.fillRect(0, 0, 412, 480);
    const s = { ...state, time: 0, forExport: true, mode: 'home', folderMode: false };
    drawTop(ctx, s);
    ctx.save(); ctx.translate(46, 240); drawBottom(ctx, s); ctx.restore();
    return c;
  }

  // ───────────── Console shell around the two screens ─────────────
  /** Size of the console drawing in console pixels, used to scale it to the pane. */
  function shellSize(compact) { return compact ? [440, 540] : [480, 622]; }
  function mountShell(consoleEl) {
    if (!consoleEl || consoleEl.classList.contains('ds')) return;
    const [topBezel, botBezel] = consoleEl.querySelectorAll('.bezel');
    const mk = (cls, ...kids) => { const d = document.createElement('div'); d.className = cls; kids.forEach((k) => d.append(k)); return d; };
    const dots = (cls) => { const g = mk('ds-spk ' + cls); for (let i = 0; i < 21; i++) g.append(mk('d')); return g; };
    const top = mk('ds-shell ds-top', mk('ds-cam'), dots('l'), dots('r'), mk('ds-slider', mk('k')), mk('ds-3d', '3D'), topBezel);
    const hinge = mk('ds-hinge', mk('ds-led'));
    const pad = mk('ds-cpad', mk('n')), dpad = mk('ds-dpad', mk('h'), mk('v'), mk('c'));
    const btn = (l, cls) => { const b = mk('b ' + cls); b.textContent = l; return b; };
    const abxy = mk('ds-abxy', btn('X', 'x'), btn('Y', 'y'), btn('A', 'a'), btn('B', 'b2'));
    const row = mk('ds-row', mk('ds-sm', 'SELECT'), mk('ds-home'), mk('ds-sm', 'START'));
    const bottom = mk('ds-shell ds-bot', pad, dpad, abxy, mk('ds-power'), botBezel, row, mk('ds-mic'));
    consoleEl.classList.add('ds'); consoleEl.innerHTML = ''; consoleEl.append(top, hinge, bottom);
  }

  return { drawTop, drawBottom, exportCanvas, mountShell, shellSize, MODES: [['home', 'Home'], ['folder', 'Folder'], ['zoom', 'Big Icons'], ['paused', 'Suspended']], REAL };
})();
