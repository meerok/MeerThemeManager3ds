// Draws an approximation of the 3DS HOME Menu with the theme's colors and pictures.
// Coordinates are console pixels: top screen 412×240 (incl. 3D margins), bottom 320×240.
const Preview = (() => {
  const DEF = TK.Theme.defaultColors();
  const css = (c, a = 1) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;
  const cssA = (c) => `rgba(${c[0]},${c[1]},${c[2]},${(c[3] ?? 255) / 255})`;
  const mix = (a, b, t) => [0, 1, 2].map((i) => Math.round(a[i] * (1 - t) + b[i] * t));

  function rr(ctx, x, y, w, h, r) { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); }
  function vgrad(ctx, top, bottom, y0, y1) { const g = ctx.createLinearGradient(0, y0, 0, y1); g.addColorStop(0, css(top)); g.addColorStop(1, css(bottom)); return g; }
  function shadowed(ctx, color, blur, dy, fn) { ctx.save(); ctx.shadowColor = color; ctx.shadowBlur = blur; ctx.shadowOffsetY = dy; fn(); ctx.restore(); }
  function text(ctx, s, x, y, size, color, align = 'center', weight = 700) {
    ctx.font = `${weight} ${size}px "Segoe UI", "Noto Sans", system-ui, sans-serif`; ctx.fillStyle = color; ctx.textAlign = align; ctx.textBaseline = 'middle'; ctx.fillText(s, x, y);
  }

  // Simple vector glyphs (no icon fonts needed)
  const glyphs = {
    sun(ctx, x, y, c) { ctx.strokeStyle = c; ctx.fillStyle = c; ctx.lineWidth = 1.6; ctx.beginPath(); ctx.arc(x, y, 3.2, 0, 7); ctx.fill(); for (let i = 0; i < 8; i++) { const a = i * Math.PI / 4; ctx.beginPath(); ctx.moveTo(x + Math.cos(a) * 5, y + Math.sin(a) * 5); ctx.lineTo(x + Math.cos(a) * 7, y + Math.sin(a) * 7); ctx.stroke(); } },
    pencil(ctx, x, y, c) { ctx.save(); ctx.translate(x, y); ctx.rotate(-Math.PI / 4); ctx.fillStyle = c; ctx.fillRect(-6, -2, 10, 4); ctx.beginPath(); ctx.moveTo(4, -2); ctx.lineTo(7.5, 0); ctx.lineTo(4, 2); ctx.fill(); ctx.restore(); },
    grid(ctx, x, y, c) { ctx.fillStyle = c; for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) ctx.fillRect(x - 6 + i * 4.5, y - 6 + j * 4.5, 3.4, 3.4); },
    brush(ctx, x, y, c) { ctx.save(); ctx.translate(x, y); ctx.rotate(Math.PI / 4); ctx.fillStyle = c; ctx.fillRect(-1.5, -8, 3, 9); rr(ctx, -3, 1, 6, 6, 2); ctx.fill(); ctx.restore(); },
    back(ctx, x, y, c) { ctx.strokeStyle = c; ctx.lineWidth = 2.4; ctx.lineCap = 'round'; ctx.beginPath(); ctx.arc(x + 1, y + 1, 5, -Math.PI / 2, Math.PI / 2); ctx.moveTo(x + 1, y - 4); ctx.lineTo(x - 5, y - 4); ctx.moveTo(x - 2, y - 7); ctx.lineTo(x - 5, y - 4); ctx.lineTo(x - 2, y - 1); ctx.stroke(); },
  };

  function drawImageTiled(ctx, img, w, h, dx, dy) {
    const iw = img.width, ih = img.height;
    for (let y = -ih + (dy % ih); y < h; y += ih) for (let x = -iw + (dx % iw); x < w; x += iw) ctx.drawImage(img, x, y);
  }

  function drawTop(ctx, s) {
    const { theme, images, time, forExport, folderMode } = s, f = theme.flags, c = theme.colors;
    ctx.save(); ctx.beginPath(); ctx.rect(0, 0, 412, 240); ctx.clip();
    const drawDefault = () => {
      ctx.fillStyle = vgrad(ctx, [232, 232, 238], [196, 196, 210], 0, 240); ctx.fillRect(0, 0, 412, 240);
      for (let i = 0; i < 9; i++) {
        const size = 18 + (i * 7) % 26, x = ((i * 53 + (forExport ? 0 : time * (6 + i))) % 460) - 30, y = 30 + (i * 37) % 180;
        ctx.fillStyle = 'rgba(255,255,255,.35)'; rr(ctx, x, y, size, size, 3); ctx.fill();
      }
    };
    if (f.topDrawType === 0) drawDefault();
    else if (f.topDrawType === 1 || f.topDrawType === 2) {
      const tb = c.topBackground;
      ctx.fillStyle = css(tb.main); ctx.fillRect(0, 0, 412, 240);
      const glow = [tb.gradientColor, tb.gradientColor, tb.gradientColor], k = tb.gradient / 255;
      const g = ctx.createLinearGradient(0, 0, 0, 240); g.addColorStop(0, css(glow, k * 0.85)); g.addColorStop(1, css(glow, 0)); ctx.fillStyle = g; ctx.fillRect(0, 0, 412, 240);
      if (f.topDrawType === 2) {
        const off = forExport ? 0 : (time * 8) % 64;
        const p = images.topPattern || images.__defaultPattern;
        if (p) { ctx.globalAlpha = tb.textureOpacity / 255; drawImageTiled(ctx, p, 412, 240, off, off); }
        if (images.topAltPattern) { ctx.globalAlpha = tb.alternateOpacity / 255; drawImageTiled(ctx, images.topAltPattern, 412, 240, -off, off * 0.5); }
        ctx.globalAlpha = 1;
      }
    } else if (f.topDrawType === 3 && images.top) {
      let x = 0;
      if (f.topFrameType !== 1 && !forExport) { const speed = f.topFrameType === 0 ? 2 : 3.5; x = (Math.sin(time / speed) + 1) / 2 * (1008 - 412); }
      ctx.drawImage(images.top, -x, 0);
    } else drawDefault();

    // status bar
    shadowed(ctx, 'rgba(0,0,0,.5)', 2, 1, () => {
      text(ctx, '12:30', 18, 11, 11, '#fff', 'left'); text(ctx, 'Sat 11/21', 54, 11, 10, '#fff', 'left', 600);
      ctx.strokeStyle = '#fff'; ctx.lineWidth = 1.2; rr(ctx, 376, 5, 20, 10, 2); ctx.stroke(); ctx.fillStyle = '#fff'; rr(ctx, 378, 7, 16, 6, 1); ctx.fill(); ctx.fillRect(396.5, 8, 2, 4);
      ctx.beginPath(); for (let i = 0; i < 3; i++) { ctx.moveTo(356 + i * 4, 15); ctx.lineTo(356 + i * 4, 15 - (i + 1) * 3); } ctx.lineWidth = 2.4; ctx.stroke();
    });
    if (folderMode) {
      const bob = forExport ? 0 : Math.sin(time * 1.6) * 4;
      drawFolder(ctx, s, 206 - 70, 70 + bob, 140, 104, true);
    } else if (f.gameTextDrawType !== 2) {
      const g = f.gameTextDrawType === 1 ? c.gameText : DEF.gameText;
      shadowed(ctx, cssA(g.shadow), 6, 2, () => { ctx.fillStyle = vgrad(ctx, g.light, g.main, 196, 228); rr(ctx, 86, 196, 240, 32, 9); ctx.fill(); });
      ctx.strokeStyle = css(g.light); ctx.lineWidth = 1; rr(ctx, 86.5, 196.5, 239, 31, 9); ctx.stroke();
      text(ctx, 'Meer Theme Manager', 206, 212, 13, css(g.text));
    }
    if (f.demoTextColor && !folderMode) { const d = c.demoText; ctx.fillStyle = css(d.main, 0.95); rr(ctx, 120, 26, 172, 22, 6); ctx.fill(); text(ctx, 'Demo text', 206, 37, 11, css(d.text), 'center', 600); }
    if (!forExport) { ctx.fillStyle = 'rgba(0,0,0,.18)'; ctx.fillRect(0, 0, 6, 240); ctx.fillRect(406, 0, 6, 240); }
    ctx.restore();
  }

  function folderPath(ctx, x, y, w, h) {
    const tabW = w * 0.42, tabH = h * 0.16;
    ctx.beginPath();
    ctx.moveTo(x + 4, y + tabH); ctx.lineTo(x + 4, y + 3); ctx.quadraticCurveTo(x + 4, y, x + 8, y);
    ctx.lineTo(x + tabW - 4, y); ctx.lineTo(x + tabW + 4, y + tabH); ctx.lineTo(x + w - 4, y + tabH);
    ctx.quadraticCurveTo(x + w, y + tabH, x + w, y + tabH + 4); ctx.lineTo(x + w, y + h - 4); ctx.quadraticCurveTo(x + w, y + h, x + w - 4, y + h);
    ctx.lineTo(x + 4, y + h); ctx.quadraticCurveTo(x, y + h, x, y + h - 4); ctx.lineTo(x, y + tabH + 4); ctx.quadraticCurveTo(x, y + tabH, x + 4, y + tabH);
    ctx.closePath();
  }
  function drawFolder(ctx, s, x, y, w, h, open) {
    const f = s.theme.flags, fc = f.folderColor ? s.theme.colors.folder : DEF.folder, big = w > 80;
    const tex = f.folderTexture ? s.images[open ? 'folderOpen' : 'folderClosed'] : null;
    shadowed(ctx, css(fc.shadow, 0.5), big ? 10 : 3, big ? 4 : 1, () => { folderPath(ctx, x, y, w, h); ctx.fillStyle = tex ? css(fc.main) : vgrad(ctx, fc.light, fc.main, y, y + h); ctx.fill(); });
    if (tex) { ctx.save(); folderPath(ctx, x, y, w, h); ctx.clip(); ctx.drawImage(tex, x, y, w, h); ctx.restore(); return; }
    const fy = y + h * (open ? 0.45 : 0.32);
    ctx.fillStyle = vgrad(ctx, fc.main, fc.shading, fy, y + h); rr(ctx, x, fy, w, y + h - fy, 4); ctx.fill();
    folderPath(ctx, x, y, w, h); ctx.strokeStyle = css(fc.shading, 0.6); ctx.lineWidth = 0.8; ctx.stroke();
  }
  function drawFile(ctx, s, x, y, w, h) {
    const f = s.theme.flags, fc = f.fileColor ? s.theme.colors.file : DEF.file, cx = x + 6, cw = w - 12;
    const tex = f.fileTexture ? (s.images.fileSmall || s.images.fileLarge) : null;
    shadowed(ctx, cssA(fc.shadow), 4, 1.5, () => { rr(ctx, cx, y, cw, h, 3); ctx.fillStyle = tex ? css(fc.main) : vgrad(ctx, fc.light, fc.main, y, y + h); ctx.fill(); });
    if (tex) { ctx.save(); rr(ctx, cx, y, cw, h, 3); ctx.clip(); ctx.drawImage(tex, cx, y, cw, h); ctx.restore(); return; }
    ctx.strokeStyle = css(fc.shading); ctx.lineWidth = 1; rr(ctx, cx + 0.5, y + 0.5, cw - 1, h - 1, 3); ctx.stroke();
    ctx.fillStyle = css(fc.shading, 0.55); rr(ctx, cx + 4, y + 6, cw - 8, h * 0.45, 2); ctx.fill();
  }
  function drawGeneric(ctx, x, y, w, h, tint, mark) {
    shadowed(ctx, 'rgba(0,0,0,.28)', 3, 1, () => { ctx.fillStyle = vgrad(ctx, mix(tint, [255, 255, 255], 0.35), tint, y, y + h); rr(ctx, x, y, w, h, 7); ctx.fill(); });
    ctx.fillStyle = 'rgba(255,255,255,.92)'; ctx.strokeStyle = 'rgba(255,255,255,.92)'; ctx.lineWidth = 2.4; ctx.lineCap = 'round';
    const cx = x + w / 2, cy = y + h / 2;
    switch (mark) {
      case 'play': ctx.beginPath(); ctx.moveTo(cx - 5, cy - 8); ctx.lineTo(cx + 8, cy); ctx.lineTo(cx - 5, cy + 8); ctx.fill(); break;
      case 'cam': rr(ctx, cx - 10, cy - 6, 20, 14, 3); ctx.fill(); ctx.fillStyle = css(tint); ctx.beginPath(); ctx.arc(cx, cy + 1, 4, 0, 7); ctx.fill(); break;
      case 'note': ctx.beginPath(); ctx.arc(cx - 4, cy + 6, 3.5, 0, 7); ctx.fill(); ctx.fillRect(cx - 1.5, cy - 9, 2.5, 15); ctx.fillRect(cx - 1.5, cy - 9, 9, 3); break;
      case 'globe': ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(cx, cy, 9, 0, 7); ctx.moveTo(cx - 9, cy); ctx.lineTo(cx + 9, cy); ctx.ellipse(cx, cy, 4, 9, 0, 0, 7); ctx.stroke(); break;
      case 'gear': ctx.beginPath(); ctx.arc(cx, cy, 6, 0, 7); ctx.lineWidth = 4; ctx.setLineDash([3, 2.5]); ctx.stroke(); ctx.setLineDash([]); break;
      default: ctx.beginPath(); for (let i = 0; i < 5; i++) { const a = -Math.PI / 2 + i * 4 * Math.PI / 5; ctx.lineTo(cx + Math.cos(a) * 9, cy + Math.sin(a) * 9); } ctx.fill();
    }
  }

  function drawBottom(ctx, s) {
    const { theme, images, time, forExport, folderMode } = s, f = theme.flags, c = theme.colors;
    ctx.save(); ctx.beginPath(); ctx.rect(0, 0, 320, 240); ctx.clip();
    const inner = [12, 39, 296, 170];
    const drawOuter = (o) => {
      ctx.fillStyle = css(o.main); ctx.fillRect(0, 0, 320, 240);
      let g = ctx.createLinearGradient(0, 0, 24, 0); g.addColorStop(0, css(o.glow)); g.addColorStop(1, css(o.main)); ctx.fillStyle = g; ctx.fillRect(0, 0, 24, 240);
      g = ctx.createLinearGradient(296, 0, 320, 0); g.addColorStop(0, css(o.main)); g.addColorStop(1, css(o.glow)); ctx.fillStyle = g; ctx.fillRect(296, 0, 24, 240);
      for (let i = 0; i < 7; i++) { ctx.strokeStyle = css(o.stripes, (1 - i / 7) / 2); ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(0, 240 - 4 * i - 2.5); ctx.lineTo(320, 240 - 4 * i - 2.5); ctx.stroke(); }
    };
    const drawInner = (p) => {
      shadowed(ctx, css(p.glow, 0.4), 8, 2, () => { ctx.fillStyle = css(p.main); rr(ctx, ...inner, 10); ctx.fill(); });
      ctx.strokeStyle = css(p.border); ctx.lineWidth = 1; rr(ctx, inner[0] + 0.5, inner[1] + 0.5, inner[2] - 1, inner[3] - 1, 10); ctx.stroke();
      ctx.strokeStyle = css(p.highlight, 0.6); ctx.lineWidth = 0.8; ctx.beginPath(); ctx.moveTo(22, 210); ctx.lineTo(298, 210); ctx.stroke();
    };
    if (f.bottomDrawType === 3 && images.bottom) {
      let x = 0;
      if (!forExport) {
        const t = f.bottomFrameType;
        if (t === 0 || t === 3) x = (Math.sin(time / (t === 0 ? 2 : 3.5)) + 1) / 2 * (1008 - 320);
        else if (t === 2) x = (Math.floor(time / 2.5) % 3) * 320;
        else if (t === 4) x = [0, 1, 2, 1][Math.floor(time / 2.5) % 4] * 320;
      }
      ctx.drawImage(images.bottom, -x, 0);
      if (folderMode && f.folderBackgroundColor) drawInner(c.folderBackground);
    } else {
      const custom = f.bottomDrawType === 1;
      drawOuter(custom && f.bottomOuterColor ? c.bottomOuter : DEF.bottomOuter);
      let ip = custom && f.bottomInnerColor ? c.bottomInner : DEF.bottomInner;
      if (folderMode) ip = f.folderBackgroundColor ? c.folderBackground : ip;
      drawInner(ip);
    }
    // icon grid
    const home = [['folder'], ['app'], ['file'], ['g', [230, 70, 60], 'play'], ['g', [70, 150, 230], 'cam'], ['g', [240, 150, 40], 'note'], ['g', [60, 180, 120], 'globe'], ['g', [140, 140, 150], 'gear'], ['file'], ['g', [200, 90, 200], 'star']];
    const folder = [['app'], ['file'], ['g', [230, 70, 60], 'play'], ['file'], ['g', [90, 120, 220], 'star']];
    const icons = folderMode ? folder : home, size = 42, gap = (inner[2] - 5 * size) / 6, sy = inner[1] + (folderMode ? 40 : 22);
    icons.forEach((ic, i) => {
      const col = i % 5, row = Math.floor(i / 5), x = inner[0] + gap + col * (size + gap), y = sy + row * (size + 20);
      if (ic[0] === 'folder') drawFolder(ctx, s, x + 1, y + 5, size - 2, size - 10, false);
      else if (ic[0] === 'file') drawFile(ctx, s, x, y, size, size);
      else if (ic[0] === 'app') {
        shadowed(ctx, 'rgba(0,0,0,.28)', 3, 1, () => { rr(ctx, x, y, size, size, 7); ctx.fillStyle = '#4b6bf5'; ctx.fill(); });
        if (s.icon) { ctx.save(); rr(ctx, x, y, size, size, 7); ctx.clip(); ctx.imageSmoothingEnabled = true; ctx.drawImage(s.icon, x, y, size, size); ctx.restore(); }
      } else drawGeneric(ctx, x, y, size, size, ic[1], ic[2]);
      if (i === 1) {
        const cc = f.cursorColor ? c.cursor : DEF.cursor, pulse = forExport ? 0.6 : (Math.sin(time * 4) + 1) / 2;
        ctx.save(); ctx.shadowColor = css(cc.glow, 0.9); ctx.shadowBlur = 6 + 6 * pulse; ctx.strokeStyle = css(cc.glow, 0.5 + 0.4 * pulse); ctx.lineWidth = 4; rr(ctx, x - 5, y - 5, size + 10, size + 10, 9); ctx.stroke(); ctx.restore();
        const g = ctx.createLinearGradient(0, y - 5, 0, y + size + 5); g.addColorStop(0, css(cc.light)); g.addColorStop(0.5, css(cc.main)); g.addColorStop(1, css(cc.shading));
        ctx.strokeStyle = g; ctx.lineWidth = 3; rr(ctx, x - 5, y - 5, size + 10, size + 10, 9); ctx.stroke();
      }
    });
    // arrow buttons
    const ab = f.arrowButtonColor ? c.arrowButton : DEF.arrowButton, ar = f.arrowColor ? c.arrow : DEF.arrow;
    const pressedRight = !forExport && Math.floor(time / 1.5) % 4 === 3;
    [[-10, 0], [304, 1]].forEach(([bx, i]) => {
      shadowed(ctx, cssA(ab.shadow), 4, 1, () => { ctx.fillStyle = vgrad(ctx, ab.light, ab.main, 102, 146); rr(ctx, bx, 102, 26, 44, 9); ctx.fill(); });
      ctx.strokeStyle = css(ab.shading); ctx.lineWidth = 1; rr(ctx, bx + 0.5, 102.5, 25, 43, 9); ctx.stroke();
      const cx = i === 0 ? bx + 17 : bx + 9, dir = i === 0 ? -1 : 1;
      ctx.beginPath(); ctx.moveTo(cx + 4 * dir, 124); ctx.lineTo(cx - 3 * dir, 118); ctx.lineTo(cx - 3 * dir, 130); ctx.closePath();
      ctx.fillStyle = css(i === 1 && pressedRight ? ar.pressed : ar.unpressed); ctx.fill(); ctx.strokeStyle = css(ar.border); ctx.lineWidth = 0.8; ctx.stroke();
    });
    // top corners
    const tc = f.topCornerColor ? c.topCorner : DEF.topCorner;
    [[-8, 'sun'], [266, 'pencil']].forEach(([x, g]) => {
      shadowed(ctx, css(tc.shadow, 0.45), 4, 1.5, () => { ctx.fillStyle = vgrad(ctx, tc.light, tc.main, -8, 24); rr(ctx, x, -8, 62, 32, 10); ctx.fill(); });
      glyphs[g](ctx, x + 31 + (x < 0 ? 4 : -4), 12, css(tc.text));
    });
    // bottom corners
    const bc = f.bottomCornerColor ? c.bottomCorner : DEF.bottomCorner;
    [[-8, 'grid'], [266, 'brush']].forEach(([x, g]) => {
      shadowed(ctx, css(bc.baseShadow, 0.45), 4, -1, () => { ctx.fillStyle = vgrad(ctx, bc.highlight, bc.main, 214, 248); rr(ctx, x, 214, 62, 34, 10); ctx.fill(); });
      ctx.strokeStyle = css(bc.border); ctx.lineWidth = 1; rr(ctx, x + 0.5, 214.5, 61, 33, 10); ctx.stroke();
      glyphs[g](ctx, x + 31 + (x < 0 ? 4 : -4), 227, css(mix(bc.iconTop, bc.iconBottom, 0.5)));
    });
    // open / close
    const oc = f.openCloseColor ? (folderMode ? c.close : c.open) : (folderMode ? DEF.close : DEF.open);
    const pressed = !forExport && Math.floor(time / 2) % 5 === 4;
    shadowed(ctx, cssA(oc.shadow), 5, 1.5, () => { ctx.fillStyle = vgrad(ctx, oc.light, pressed ? oc.pressed : oc.unpressed, 213, 237); rr(ctx, 112, 213, 96, 24, 12); ctx.fill(); });
    ctx.strokeStyle = css(oc.glow, 0.7); ctx.lineWidth = 1; rr(ctx, 112.5, 213.5, 95, 23, 12); ctx.stroke();
    const label = folderMode ? 'Close' : 'Open', dy = Math.max(-3, Math.min(3, oc.textShadowPosition));
    text(ctx, label, 160, 225 - dy, 13, css(oc.textShadow)); text(ctx, label, 160, 225, 13, css(pressed ? oc.textPressed : oc.textUnpressed));
    // folder back button
    if (folderMode) {
      const fa = f.folderArrowColor ? c.folderArrow : DEF.folderArrow;
      shadowed(ctx, cssA(fa.shadow), 4, 1.5, () => { ctx.fillStyle = vgrad(ctx, fa.highlight, fa.main, 46, 72); rr(ctx, 20, 46, 46, 26, 13); ctx.fill(); });
      ctx.strokeStyle = css(fa.shading); ctx.lineWidth = 1; rr(ctx, 20.5, 46.5, 45, 25, 13); ctx.stroke();
      glyphs.back(ctx, 43, 59, css(fa.arrowUnpressed));
      ctx.fillStyle = css(fa.main, 0.85); rr(ctx, 76, 48, 150, 22, 6); ctx.fill(); text(ctx, 'My Folder', 151, 59, 12, css(fa.arrowUnpressed));
    }
    ctx.restore();
  }

  /** Renders the 412×480 preview.png used by theme managers. */
  function exportCanvas(state) {
    const c = document.createElement('canvas'); c.width = 412; c.height = 480;
    const ctx = c.getContext('2d');
    ctx.fillStyle = '#141414'; ctx.fillRect(0, 0, 412, 480);
    const s = { ...state, time: 0, forExport: true, folderMode: false };
    drawTop(ctx, s);
    ctx.save(); ctx.translate(46, 240); drawBottom(ctx, s); ctx.restore();
    return c;
  }
  return { drawTop, drawBottom, exportCanvas };
})();
