// Converter Tools: everyday files ⇄ 3DS formats.
const IMAGE_TARGETS = [
  ['topStill', 'Top screen — still (412 × 240)', 412, 240],
  ['topScroll', 'Top screen — scrolling (1008 × 240)', 1008, 240],
  ['bottomStill', 'Bottom screen — still (320 × 240)', 320, 240],
  ['bottomPages', 'Bottom screen — page flip/bounce (960 × 240)', 960, 240],
  ['bottomScroll', 'Bottom screen — scrolling (1008 × 240)', 1008, 240],
  ['folder', 'Folder picture (128 × 64)', 128, 64],
  ['fileLarge', 'File picture, large (64 × 128)', 64, 128],
  ['fileSmall', 'File picture, small (32 × 64)', 32, 64],
  ['icon', 'Theme icon (48 × 48)', 48, 48],
  ['pattern', 'Top pattern (64 × 64)', 64, 64],
];

const Converter = {
  s: { music: null, musicRate: 32000, musicMono: false, musicLoop: 0, musicEdit: TK.AudioProcess.defaultEdit(), sfx: null, sfxRate: 22050, nin: null, image: null, imageCanvas: null, target: 'topStill', fit: 'fill', bg: [0, 0, 0] },

  dropField(key, prompt, filters, onset) {
    const s = this.s, has = !!s[key];
    const z = el('div', { class: 'dropzone' + (has ? ' has' : '') }, svg(has ? 'file' : 'tray'), el('div', { class: 'name' }, has ? window.api.basename(s[key]) : prompt),
      btn(has ? 'Change…' : 'Choose…', null, async () => { const p = await window.api.openFile(prompt, filters); if (p) set(p); }, 'small'),
      has ? btn('Clear', 'close', () => { s[key] = null; App.renderPage(); }, 'icon small ghost') : null);
    const set = async (p) => { s[key] = p; if (onset) await onset(p); App.renderPage(); };
    fileDrop(z, set);
    return z;
  },

  async run(label, fn) {
    Busy.show(label, true);
    try { await fn(); toast('Done!'); } catch (e) { alertError(e.message); }
    Busy.hide();
  },

  page() {
    const s = this.s, noop = () => {};
    const maxS = TK.AudioProcess.maxSeconds(s.musicRate, s.musicMono ? 1 : 2);
    const target = IMAGE_TARGETS.find((t) => t[0] === s.target);
    let preview = null;
    if (s.imageCanvas) {
      const e = Imaging.defaultEdit(s.fit); e.background = s.bg;
      preview = Imaging.renderCanvas(s.imageCanvas, target[2], target[3], e);
      Object.assign(preview.style, { maxHeight: '140px', maxWidth: '100%', borderRadius: '6px', imageRendering: target[2] < 140 ? 'pixelated' : 'auto', height: Math.min(140, target[3] * 3) + 'px' });
    }
    const isNin = s.nin && /\.(bcstm|bcwav)$/i.test(s.nin);
    return page(
      pageHead(sec('converter'), 'Turn everyday files into the formats the 3DS needs (and back again). Everything runs on your PC, so you don\'t need any other converters.'),

      card(cardHead('Music → BCSTM', 'music', 'MP3, WAV, M4A/AAC, OGG or FLAC → looping bgm.bcstm (DSP-ADPCM).'),
        this.dropField('music', 'Drop a song here', AUDIO_FILTERS.map((f) => ({ ...f, extensions: f.extensions.filter((x) => x !== 'bcstm') }))),
        segmented([[22050, '22 kHz'], [32000, '32 kHz'], [44100, '44 kHz']], s.musicRate, (v) => { s.musicRate = v; App.renderPage(); }),
        el('label', { class: 'row' }, toggleSwitch(s.musicMono, (v) => { s.musicMono = v; App.renderPage(); }), 'Mono (fits twice as much music)'),
        slider('Start at', () => s.musicEdit.startSeconds, (v) => { s.musicEdit.startSeconds = v; }, 0, 600, 0.5, 0, fmtTime, null, noop),
        slider('Loop back to', () => s.musicLoop, (v) => { s.musicLoop = v; }, 0, 600, 0.5, 0, (v) => (v ? fmtTime(v) : 'Beginning'), null, noop),
        slider('Fade out', () => s.musicEdit.fadeOutSeconds, (v) => { s.musicEdit.fadeOutSeconds = v; }, 0, 10, 0.5, 0, (v) => (v ? v.toFixed(1) + ' s' : 'Off'), null, noop),
        el('label', { class: 'row' }, toggleSwitch(s.musicEdit.normalize, (v) => { s.musicEdit.normalize = v; }), 'Normalize volume'),
        el('div', { class: 'muted small' }, `Songs longer than the 3DS limit at these settings (${fmtTime(maxS)}) are trimmed automatically.`),
        el('div', { class: 'row' }, el('div', { class: 'grow' }),
          btn('Convert & Save…', null, () => this.convertMusic(), 'small'),
          btn('Use as Theme Music', 'music', () => { const b = App.bgm.settings; b.rate = s.musicRate; b.mono = s.musicMono; b.loopStart = s.musicLoop; b.edit = { ...s.musicEdit }; App.go('music'); App.importMusic(s.music); }, 'primary'))),

      card(cardHead('Sound → BCWAV', 'speaker', 'Short sounds for HOME Menu sound effects. Silence is trimmed and volume is leveled.'),
        this.dropField('sfx', 'Drop a short sound here', SFX_FILTERS),
        segmented([[16000, '16 kHz (smallest)'], [22050, '22 kHz'], [32000, '32 kHz']], s.sfxRate, (v) => { s.sfxRate = v; App.renderPage(); }),
        el('div', { class: 'row' }, el('div', { class: 'grow' }), btn('Convert & Save…', null, () => this.convertSound(), 'small'))),

      card(cardHead('BCSTM / BCWAV → WAV', 'wave', 'Turn 3DS audio back into a normal WAV you can open in any audio app.'),
        this.dropField('nin', 'Drop a .bcstm or .bcwav here', [{ name: '3DS audio', extensions: ['bcstm', 'bcwav'] }]),
        el('div', { class: 'row' },
          isNin ? btn('Play', 'play', () => { try { Audio3DS.play(Audio3DS.decodeNintendo(window.api.readFile(s.nin)), true); } catch (e) { alertError(e.message); } }, 'small') : null,
          isNin ? btn('Stop', 'stop', () => Audio3DS.stop(), 'small') : null,
          el('div', { class: 'grow' }), btn('Convert & Save…', null, () => this.toWav(), 'small'))),

      card(cardHead('Picture Resizer', 'image', 'Resize any picture to an exact 3DS theme size. For full control, add it to the theme and click it to open the editor.'),
        this.dropField('image', 'Drop a picture here', IMG_FILTERS, async (p) => { s.imageCanvas = await Imaging.loadPath(p); }),
        selectBox(IMAGE_TARGETS.map((t) => [t[0], t[1]]), s.target, (v) => { s.target = v; App.renderPage(); }),
        segmented(FIT_OPTIONS, s.fit, (v) => { s.fit = v; App.renderPage(); }),
        s.fit === 'fit' ? colorRow('Background', null, () => s.bg, (v) => { s.bg = v; App.renderPage(); }) : null,
        preview ? el('div', { style: { display: 'flex', justifyContent: 'center', padding: '6px', background: 'rgba(0,0,0,.2)', borderRadius: '8px' } }, preview) : null,
        el('div', { class: 'row' }, el('div', { class: 'grow' }),
          btn('Save PNG…', null, () => this.saveResized(preview), 'small'),
          btn('Use in Theme', 'check', () => this.useImage(), 'primary'))),

      card(cardHead('Extract a Theme', 'box', 'Pull the wallpapers, icons, music, sounds and colors out of any theme (folder, .zip or body_LZ.bin) as PNG, WAV and JSON files.'),
        el('div', { class: 'row' }, el('div', { class: 'grow' }),
          btn('Extract Theme File…', 'zip', () => this.extract(false), 'small'), btn('Extract Theme Folder…', 'folder', () => this.extract(true), 'small'))),
    );
  },

  async convertMusic() {
    const s = this.s; if (!s.music) return alertError('Drop a song first.');
    const out = await window.api.saveFile('Save BCSTM', 'bgm.bcstm', [{ name: 'BCSTM', extensions: ['bcstm'] }]); if (!out) return;
    await this.run('Converting to BCSTM…', async () => {
      const pcm = await Audio3DS.load(s.music, s.musicRate, s.musicMono ? 1 : 2);
      const { audio } = Audio3DS.prepareMusic(pcm, s.musicEdit, s.musicLoop, s.musicRate, s.musicMono ? 1 : 2);
      window.api.writeFile(out, await Audio3DS.encodeBCSTM(audio, (p) => Busy.progress(p)));
    });
  },
  async convertSound() {
    const s = this.s; if (!s.sfx) return alertError('Drop a sound first.');
    const name = window.api.basename(s.sfx).replace(/\.[^.]+$/, '') + '.bcwav';
    const out = await window.api.saveFile('Save BCWAV', name, [{ name: 'BCWAV', extensions: ['bcwav'] }]); if (!out) return;
    await this.run('Converting to BCWAV…', async () => {
      const pcm = TK.AudioProcess.apply(await Audio3DS.load(s.sfx, s.sfxRate, 1, 10), { ...TK.AudioProcess.defaultEdit(), trimSilence: true, maxSeconds: 4 });
      window.api.writeFile(out, await Audio3DS.encodeBCWAV(pcm));
    });
  },
  async toWav() {
    const s = this.s; if (!s.nin) return alertError('Drop a .bcstm or .bcwav first.');
    const out = await window.api.saveFile('Save WAV', window.api.basename(s.nin).replace(/\.[^.]+$/, '') + '.wav', [{ name: 'WAV audio', extensions: ['wav'] }]); if (!out) return;
    await this.run('Converting to WAV…', async () => window.api.writeFile(out, TK.AudioProcess.wav(Audio3DS.decodeNintendo(window.api.readFile(s.nin)))));
  },
  async saveResized(canvas) {
    if (!canvas) return alertError('Drop a picture first.');
    const t = IMAGE_TARGETS.find((x) => x[0] === this.s.target);
    const out = await window.api.saveFile('Save Resized Picture', `${window.api.basename(this.s.image).replace(/\.[^.]+$/, '')}-${t[2]}x${t[3]}.png`, [{ name: 'PNG image', extensions: ['png'] }]); if (!out) return;
    window.api.writeFile(out, await Imaging.canvasPNG(canvas)); toast('Saved ' + window.api.basename(out));
  },
  async useImage() {
    const s = this.s, c = s.imageCanvas; if (!c) return alertError('Drop a picture first.');
    const f = App.theme.flags, name = window.api.basename(s.image);
    switch (s.target) {
      case 'topStill': f.topFrameType = 1; await App.setPicture('top', c, name); break;
      case 'topScroll': f.topFrameType = 3; await App.setPicture('top', c, name); break;
      case 'bottomStill': f.bottomFrameType = 1; await App.setPicture('bottom', c, name); break;
      case 'bottomPages': f.bottomFrameType = 2; await App.setPicture('bottom', c, name); break;
      case 'bottomScroll': f.bottomFrameType = 3; await App.setPicture('bottom', c, name); break;
      case 'folder': await App.setPicture('folderClosed', c, name); await App.setPicture('folderOpen', c, name); break;
      case 'fileLarge': await App.setPicture('fileLarge', c, name); break;
      case 'fileSmall': await App.setPicture('fileSmall', c, name); break;
      case 'icon': App.setIcon(c); break;
      case 'pattern': await App.setPicture('topPattern', c, name); break;
    }
    toast('Added to the theme. Click it to fine-tune in the editor.');
  },
  async extract(folder) {
    const src = folder ? await window.api.openFolder('Choose a theme folder to extract', 'Choose') : await window.api.openFile('Choose a theme to extract', [{ name: '3DS Themes', extensions: ['zip', 'bin'] }]);
    if (!src) return;
    const dest = await window.api.openFolder('Choose where to save the extracted files', 'Extract Here'); if (!dest) return;
    try {
      // Reuse the theme loader without touching the open document.
      let entries;
      if (window.api.isDir(src)) entries = window.api.readdir(src).map((n) => ({ name: n, data: window.api.isDir(window.api.join(src, n)) ? new Uint8Array(0) : window.api.readFile(window.api.join(src, n)) }));
      else { const b = window.api.readFile(src); entries = b[0] === 0x50 && b[1] === 0x4B ? TK.Zip.read(b, (x) => window.api.inflateRaw(x)) : [{ name: 'body_LZ.bin', data: b }]; }
      const body = App.findIn(entries, 'body_LZ.bin'); if (!body) throw new Error("There's no body_LZ.bin in this theme.");
      const t = TK.Theme.read(body.data), smdhE = App.findIn(entries, 'info.smdh');
      const smdh = smdhE ? TK.SMDH.read(smdhE.data) : null, name = TK.safeName(smdh ? TK.SMDH.primary(smdh).short : window.api.basename(src));
      const dir = window.api.join(dest, name + ' (extracted)'); window.api.mkdir(dir);
      let count = 0;
      const png = async (img, file, crop) => { if (!img) return; if (crop) img = TK.cropImage(img, Math.min(crop[0], img.width), Math.min(crop[1], img.height)); window.api.writeFile(window.api.join(dir, file), await Imaging.canvasPNG(Imaging.imageToCanvas(img))); count++; };
      await png(t.textures.top, 'top.png', TK.Geometry.visible('top', t.flags));
      await png(t.textures.bottom, 'bottom.png', TK.Geometry.visible('bottom', t.flags));
      await png(t.textures.topPattern, 'top_pattern.png'); await png(t.textures.topAltPattern, 'top_pattern2.png');
      await png(t.textures.folderClosed, 'folder_closed.png'); await png(t.textures.folderOpen, 'folder_open.png');
      await png(t.textures.fileLarge, 'file_large.png'); await png(t.textures.fileSmall, 'file_small.png');
      if (smdh) await png(smdh.largeIcon, 'icon.png');
      const pv = App.findIn(entries, 'preview.png'); if (pv) { window.api.writeFile(window.api.join(dir, 'preview.png'), pv.data); count++; }
      const bgm = App.findIn(entries, 'bgm.bcstm'); if (bgm) { try { window.api.writeFile(window.api.join(dir, 'bgm.wav'), TK.AudioProcess.wav(TK.BCSTM.decode(bgm.data))); count++; } catch (e) { /* skip */ } }
      TK.SFXBlock.decode(t.soundEffectData).forEach((d, i) => { if (!d) return; try { window.api.writeFile(window.api.join(dir, `sfx_${i + 1}_${TK.SFXBlock.slots[i].title.replace(/[^A-Za-z0-9]+/g, '_')}.wav`), TK.AudioProcess.wav(TK.BCWAV.decode(d))); count++; } catch (e) { /* skip */ } });
      window.api.writeFile(window.api.join(dir, 'colors.json'), new TextEncoder().encode(JSON.stringify({ app: 'MtM3', formatVersion: 1, flags: t.flags, colors: t.colors }, null, 2))); count++;
      toast(`Extracted ${count} files from “${name}”`); window.api.reveal(window.api.join(dir, 'colors.json'));
    } catch (e) { alertError("Couldn't extract that theme: " + e.message); }
  },
};
