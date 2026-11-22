// MtM3 application state and core actions.
const SECTIONS = [
  { id: 'info', title: 'Theme Info', icon: 'info', group: 'Theme' },
  { id: 'top', title: 'Top Screen', icon: 'top', group: 'Wallpapers' },
  { id: 'bottom', title: 'Bottom Screen', icon: 'bottom', group: 'Wallpapers' },
  { id: 'icons', title: 'Icons & Cursor', icon: 'grid', group: 'Interface Colors' },
  { id: 'buttons', title: 'Buttons & Arrows', icon: 'buttons', group: 'Interface Colors' },
  { id: 'folderView', title: 'Folder View', icon: 'folder', group: 'Interface Colors' },
  { id: 'text', title: 'Text Boxes', icon: 'text', group: 'Interface Colors' },
  { id: 'music', title: 'Background Music', icon: 'music', group: 'Audio' },
  { id: 'sounds', title: 'Sound Effects', icon: 'speaker', group: 'Audio' },
  { id: 'converter', title: 'Converter Tools', icon: 'convert', group: 'Tools & Finish' },
  { id: 'export', title: 'Export & Share', icon: 'export', group: 'Tools & Finish' },
];
const SMALL_SLOTS = ['folderClosed', 'folderOpen', 'fileLarge', 'fileSmall', 'topPattern', 'topAltPattern'];

const App = {
  theme: TK.Theme.create(),
  name: '', description: '', author: '',
  smdh: TK.SMDH.create(),
  icon: TK.SMDH.defaultIcon(48),
  iconCanvas: null,
  sources: {},          // slot -> { canvas, edit, fileName }
  images: {},           // slot -> canvas for drawing the preview
  palette: [],
  bgm: { data: null, source: null, sourceName: null, sourcePath: null, preview: null, busy: false, progress: 0, settings: { rate: 32000, mono: false, loopStart: 0, edit: TK.AudioProcess.defaultEdit() } },
  sfx: new Array(8).fill(null), sfxNames: new Array(8).fill(null),
  section: 'info', animate: true, previewMode: 'home', dirty: false, path: null,
  get folderMode() { return this.previewMode === 'folder'; },
  set folderMode(v) { this.previewMode = v ? 'folder' : 'home'; },
  showPreview(mode) { if (mode && this.previewMode !== mode) { this.previewMode = mode; this.renderPreviewControls(); } },
  undoStack: [], redoStack: [], lastSnap: null, lastPush: 0, paletteTimer: null,

  // ───── change tracking ─────
  snapshot() {
    const t = this.theme;
    return { flags: structuredClone(t.flags), colors: structuredClone(t.colors), textures: { ...t.textures }, sfx: t.soundEffectData, dither: t.ditherBackgrounds };
  },
  restore(s) {
    Object.assign(this.theme, { flags: structuredClone(s.flags), colors: structuredClone(s.colors), textures: { ...s.textures }, soundEffectData: s.sfx, ditherBackgrounds: s.dither });
    this.refreshImages();
    this.sfx = TK.SFXBlock.decode(this.theme.soundEffectData);
    this.lastSnap = this.snapshot();
    this.setDirty(true); this.renderPage(); this.renderSidebar();
  },
  changed(structural = false) {
    const now = Date.now();
    if (this.lastSnap && now - this.lastPush > 600) { this.undoStack.push(this.lastSnap); if (this.undoStack.length > 60) this.undoStack.shift(); this.redoStack = []; }
    this.lastPush = now;
    this.changeCount = (this.changeCount || 0) + 1;
    this.lastSnap = this.snapshot();
    this.setDirty(true);
    if (structural) this.renderPage();
    this.renderSidebar();
    this.updateTopbar();
  },
  undo() { const s = this.undoStack.pop(); if (!s) return; this.redoStack.push(this.snapshot()); this.restore(s); toast('Undone'); },
  redo() { const s = this.redoStack.pop(); if (!s) return; this.undoStack.push(this.snapshot()); this.restore(s); toast('Redone'); },
  setDirty(v) { this.dirty = v; document.getElementById('dirtyDot').classList.toggle('on', v); },

  // ───── textures ─────
  setTexture(slot, img, quiet) {
    if (img) this.theme.textures[slot] = img; else delete this.theme.textures[slot];
    this.refreshImage(slot);
    this.schedulePalette();
    if (!quiet) this.changed();
  },
  refreshImage(slot) {
    const img = this.theme.textures[slot];
    if (img) this.images[slot] = Imaging.imageToCanvas(img, TK.SLOTS[slot] === 'a8'); else delete this.images[slot];
  },
  refreshImages() { this.images = {}; for (const s of Object.keys(TK.SLOTS)) this.refreshImage(s); this.schedulePalette(); },
  schedulePalette() {
    clearTimeout(this.paletteTimer);
    this.paletteTimer = setTimeout(() => {
      const f = this.theme.flags, out = [];
      for (const slot of ['top', 'bottom']) {
        const img = this.theme.textures[slot]; if (!img) continue;
        const [w, h] = TK.Geometry.visible(slot, f);
        out.push(...Imaging.palette(TK.cropImage(img, Math.min(w, img.width), Math.min(h, img.height)), 12));
      }
      const seen = new Set(); this.palette = out.filter((c) => { const k = c.join(); if (seen.has(k)) return false; seen.add(k); return true; });
      document.querySelectorAll('.palette-host').forEach((n) => n.replaceWith(Pages.paletteCard()));
    }, 250);
  },
  renderSlotImage(slot, edit) {
    const src = this.sources[slot]; if (!src) return null;
    const [vw, vh] = TK.Geometry.visible(slot, this.theme.flags);
    return Imaging.canvasToImage(Imaging.renderCanvas(src.canvas, vw, vh, edit || src.edit));
  },
  renderSlot(slot, quiet) {
    const vis = this.renderSlotImage(slot); if (!vis) return;
    const [cw, ch] = TK.Geometry.canvas(slot, this.theme.flags);
    this.setTexture(slot, TK.bleedImage(vis, cw, ch), quiet);
  },
  async setPicture(slot, canvas, fileName) {
    this.sources[slot] = { canvas, edit: Imaging.defaultEdit(SMALL_SLOTS.includes(slot) ? 'stretch' : 'fill'), fileName };
    this.renderSlot(slot, true);
    const f = this.theme.flags, t = this.theme.textures;
    if (slot === 'top') f.topDrawType = 3;
    if (slot === 'topPattern' || slot === 'topAltPattern') f.topDrawType = 2;
    if (slot === 'bottom') f.bottomDrawType = 3;
    if ((slot === 'folderClosed' || slot === 'folderOpen') && t.folderClosed && t.folderOpen) f.folderTexture = true;
    if ((slot === 'fileLarge' || slot === 'fileSmall') && t.fileLarge && t.fileSmall) f.fileTexture = true;
    this.changed(true);
  },
  async loadPicture(slot, path) {
    try { await this.setPicture(slot, await Imaging.loadPath(path), window.api.basename(path)); if (slot === 'top' || slot === 'bottom') toast('Picture added. Click it to crop, resize, rotate or adjust colors.'); }
    catch (e) { alertError(`“${window.api.basename(path)}” couldn't be opened as a picture.`); }
  },
  clearPicture(slot) { delete this.sources[slot]; this.setTexture(slot, null, true); this.changed(true); },
  frameChanged() { for (const s of ['top', 'bottom']) if (this.sources[s]) this.renderSlot(s, true); this.schedulePalette(); },
  setIcon(canvas) {
    const c = Imaging.renderCanvas(canvas, 48, 48, Imaging.defaultEdit('fill'));
    this.icon = Imaging.canvasToImage(c); this.iconCanvas = Imaging.imageToCanvas(this.icon);
    this.changed(true); this.renderSidebar();
  },

  // ───── new / open ─────
  async confirmDiscard() {
    if (!this.dirty) return true;
    return (await window.api.confirm(`Discard unsaved changes to “${this.displayName()}”?`, "Your changes haven't been exported yet.", ['Discard Changes', 'Cancel'])) === 0;
  },
  displayName() { return this.name.trim() || 'Untitled Theme'; },
  reset() {
    Audio3DS.stop();
    this.theme = TK.Theme.create(); this.name = ''; this.description = ''; this.author = '';
    this.smdh = TK.SMDH.create(); this.icon = TK.SMDH.defaultIcon(48); this.iconCanvas = Imaging.imageToCanvas(this.icon);
    this.sources = {}; this.images = {}; this.palette = [];
    this.bgm = { data: null, source: null, sourceName: null, sourcePath: null, preview: null, busy: false, progress: 0, settings: { rate: 32000, mono: false, loopStart: 0, edit: TK.AudioProcess.defaultEdit() } };
    this.sfx = new Array(8).fill(null); this.sfxNames = new Array(8).fill(null);
    this.undoStack = []; this.redoStack = []; this.lastSnap = this.snapshot(); this.path = null;
    this.setDirty(false); this.section = 'info'; this.renderAll();
  },
  findIn(entries, name) { return entries.find((e) => e.name.split(/[\\/]/).pop().toLowerCase() === name.toLowerCase() && !e.name.includes('__MACOSX')); },
  async open(path) {
    try {
      let entries = [];
      if (window.api.isDir(path)) {
        entries = window.api.readdir(path).filter((n) => /\.(bin|smdh|bcstm|png)$/i.test(n)).map((n) => ({ name: n, data: window.api.readFile(window.api.join(path, n)) }));
      } else {
        const bytes = window.api.readFile(path);
        if (bytes[0] === 0x50 && bytes[1] === 0x4B) entries = TK.Zip.read(bytes, (b) => window.api.inflateRaw(b));
        else {
          entries = [{ name: 'body_LZ.bin', data: bytes }];
          const dir = window.api.dirname(path);
          for (const n of window.api.readdir(dir)) if (/^(info\.smdh|bgm\.bcstm|preview\.png)$/i.test(n)) entries.push({ name: n, data: window.api.readFile(window.api.join(dir, n)) });
        }
      }
      const body = this.findIn(entries, 'body_LZ.bin');
      if (!body) throw new Error("There's no body_LZ.bin in this theme.");
      const theme = TK.Theme.read(body.data);
      this.reset();
      this.theme = theme;
      const smdhE = this.findIn(entries, 'info.smdh');
      if (smdhE) { try { this.smdh = TK.SMDH.read(smdhE.data); const p = TK.SMDH.primary(this.smdh); this.name = p.short; this.description = p.long; this.author = p.publisher; this.icon = this.smdh.largeIcon; this.iconCanvas = Imaging.imageToCanvas(this.icon); } catch (e) { /* ignore broken smdh */ } }
      for (const slot of Object.keys(theme.textures)) {
        const img = theme.textures[slot], [vw, vh] = TK.Geometry.visible(slot, theme.flags);
        this.sources[slot] = { canvas: Imaging.imageToCanvas(TK.cropImage(img, Math.min(vw, img.width), Math.min(vh, img.height))), edit: Imaging.defaultEdit('stretch'), fileName: 'From theme' };
      }
      this.sfx = TK.SFXBlock.decode(theme.soundEffectData);
      this.sfx.forEach((s, i) => { if (s) this.sfxNames[i] = 'From theme'; });
      const bgmE = this.findIn(entries, 'bgm.bcstm');
      if (bgmE) { this.bgm.data = bgmE.data; this.bgm.sourceName = 'bgm.bcstm (from theme)'; try { this.bgm.preview = TK.BCSTM.decode(bgmE.data); } catch (e) { /* preview unavailable */ } }
      this.refreshImages();
      this.path = path; this.lastSnap = this.snapshot(); this.setDirty(false);
      this.renderAll();
      toast(`Opened “${this.displayName()}”`);
    } catch (e) { alertError(`Couldn't open this theme: ${e.message}`); }
  },
  async openFileDialog() {
    if (!(await this.confirmDiscard())) return;
    const p = await window.api.openFile('Open a theme (.zip or body_LZ.bin)', [{ name: '3DS Themes', extensions: ['zip', 'bin'] }]);
    if (p) this.open(p);
  },
  async openFolderDialog() {
    if (!(await this.confirmDiscard())) return;
    const p = await window.api.openFolder('Open a theme folder', 'Open');
    if (p) this.open(p);
  },

  // ───── music & sounds ─────
  async importMusic(path) {
    Audio3DS.stop();
    const ext = window.api.extname(path).toLowerCase();
    if (ext === '.bcstm') {
      try {
        const bytes = window.api.readFile(path);
        this.bgm.preview = TK.BCSTM.decode(bytes); this.bgm.data = bytes; this.bgm.source = null; this.bgm.sourceName = window.api.basename(path);
        this.theme.flags.backgroundMusic = true; this.changed(true);
        if (bytes.length > TK.Limits.maxBGM) alertError(`This BCSTM is ${fmtBytes(bytes.length)}, over the 3DS limit of ${fmtBytes(TK.Limits.maxBGM)}.`);
      } catch (e) { alertError(`Couldn't read this BCSTM: ${e.message}`); }
      return;
    }
    const s = this.bgm.settings;
    this.bgm.busy = true; this.bgm.progress = 0; this.bgm.sourceName = window.api.basename(path); this.bgm.sourcePath = path; this.renderPage();
    try {
      this.bgm.source = await Audio3DS.load(path, s.rate, s.mono ? 1 : 2);
      this.theme.flags.backgroundMusic = true;
      await this.encodeMusic();
    } catch (e) { this.bgm.busy = false; this.renderPage(); alertError(e.message); }
  },
  async applyMusicSettings() {
    const s = this.bgm.settings, src = this.bgm.source; if (!src) return;
    if (src.sampleRate !== s.rate || src.channels.length !== (s.mono ? 1 : 2)) {
      if (this.bgm.sourcePath && window.api.exists(this.bgm.sourcePath)) return this.importMusic(this.bgm.sourcePath);
    }
    return this.encodeMusic();
  },
  async encodeMusic() {
    const s = this.bgm.settings; Audio3DS.stop();
    this.bgm.busy = true; this.renderPage();
    const { audio, trimmed } = Audio3DS.prepareMusic(this.bgm.source, s.edit, s.loopStart, s.rate, s.mono ? 1 : 2);
    try {
      const bytes = await Audio3DS.encodeBCSTM(audio, (p) => { this.bgm.progress = p; const bar = document.querySelector('#bgmProgress div'); if (bar) bar.style.width = Math.round(p * 100) + '%'; });
      this.bgm.data = bytes; this.bgm.preview = TK.BCSTM.decode(bytes);
      toast(trimmed ? `Music was trimmed to ${fmtTime(TK.AudioProcess.maxSeconds(s.rate, s.mono ? 1 : 2))} to fit the 3DS limit.` : `Music converted (${fmtBytes(bytes.length)}).`);
    } catch (e) { alertError('Music conversion failed: ' + e.message); }
    this.bgm.busy = false; this.changed(true);
  },
  removeMusic() { Audio3DS.stop(); Object.assign(this.bgm, { data: null, source: null, sourceName: null, sourcePath: null, preview: null }); this.theme.flags.backgroundMusic = false; this.changed(true); },
  editedMusicSeconds() {
    const src = this.bgm.source; if (!src) return this.bgm.preview ? this.bgm.preview.channels[0].length / this.bgm.preview.sampleRate : 0;
    const e = this.bgm.settings.edit; let sec = Math.max(0, src.channels[0].length / src.sampleRate - e.startSeconds); if (e.maxSeconds > 0) sec = Math.min(sec, e.maxSeconds); return sec;
  },
  syncSfx() { this.theme.soundEffectData = TK.SFXBlock.isEmpty(this.sfx) ? new Uint8Array(0) : TK.SFXBlock.encode(this.sfx); },
  async importSound(path, i) {
    try {
      let data;
      if (window.api.extname(path).toLowerCase() === '.bcwav') { data = window.api.readFile(path); TK.BCWAV.decode(data); }
      else {
        const edit = { ...TK.AudioProcess.defaultEdit(), trimSilence: true, maxSeconds: 4 };
        data = await Audio3DS.encodeBCWAV(TK.AudioProcess.apply(await Audio3DS.load(path, 22050, 1, 10), edit));
      }
      this.sfx[i] = data; this.sfxNames[i] = window.api.basename(path); this.syncSfx();
      this.theme.flags.soundEffects = true; this.changed(true);
      if (TK.SFXBlock.estimatedSize(this.sfx) > TK.Limits.maxSoundEffects) alertError('Sound effects are now over the 3DS size limit (about 187 KB in total). Use shorter sounds.');
    } catch (e) { alertError(`Couldn't import “${window.api.basename(path)}”: ${e.message}`); }
  },
  clearSound(i) { this.sfx[i] = null; this.sfxNames[i] = null; this.syncSfx(); if (TK.SFXBlock.isEmpty(this.sfx)) this.theme.flags.soundEffects = false; this.changed(true); },

  // ───── export ─────
  async buildPackage() {
    TK.SMDH.setAll(this.smdh, this.name, this.description, this.author);
    this.smdh.largeIcon = this.icon; this.smdh.smallIcon = TK.SMDH.downscale(this.icon, 24);
    const preview = await Imaging.canvasPNG(Preview.exportCanvas(this.previewState()));
    const theme = { ...this.theme, soundEffectData: this.theme.flags.soundEffects ? TK.SFXBlock.encode(this.sfx) : new Uint8Array(0) };
    const body = await Audio3DS.compressBody(theme);
    const pkg = { theme, info: this.smdh, bgm: this.bgm.data, preview };
    return { pkg, body, validation: TK.validate(pkg, body) };
  },
  async exportFolder() {
    const parent = await window.api.openFolder('Choose where to save the theme folder', 'Export Here'); if (!parent) return;
    Busy.show('Building theme…');
    try {
      const { pkg, body, validation } = await this.buildPackage();
      Busy.hide();
      if (validation.errors.length) return alertError(validation.errors[0]);
      const dir = window.api.join(parent, TK.safeName(this.name)); window.api.mkdir(dir);
      for (const f of TK.packageFiles(pkg, body)) window.api.writeFile(window.api.join(dir, f.name), f.data);
      if (!this.theme.flags.backgroundMusic) window.api.remove(window.api.join(dir, 'bgm.bcstm'));
      this.path = dir; this.setDirty(false); this.updateTopbar();
      toast(`Exported “${TK.safeName(this.name)}”`); window.api.reveal(window.api.join(dir, 'body_LZ.bin'));
    } catch (e) { Busy.hide(); alertError('Export failed: ' + e.message); }
  },
  async exportZip() {
    const out = await window.api.saveFile('Export Theme ZIP', TK.safeName(this.name) + '.zip', [{ name: 'ZIP archive', extensions: ['zip'] }]); if (!out) return;
    Busy.show('Building theme…');
    try {
      const { pkg, body, validation } = await this.buildPackage();
      Busy.hide();
      if (validation.errors.length) return alertError(validation.errors[0]);
      window.api.writeFile(out, TK.Zip.write(TK.packageFiles(pkg, body)));
      this.setDirty(false); toast(`Saved ${window.api.basename(out)}`); window.api.reveal(out);
    } catch (e) { Busy.hide(); alertError('Export failed: ' + e.message); }
  },
  async savePreview() {
    const out = await window.api.saveFile('Save Preview Image', 'preview.png', [{ name: 'PNG image', extensions: ['png'] }]); if (!out) return;
    window.api.writeFile(out, await Imaging.canvasPNG(Preview.exportCanvas(this.previewState()))); toast('Saved preview image');
  },
  async exportPreset() {
    const out = await window.api.saveFile('Export Colors & Settings', TK.safeName(this.name) + ' Colors.json', [{ name: 'MtM3 preset', extensions: ['json'] }]); if (!out) return;
    window.api.writeFile(out, new TextEncoder().encode(JSON.stringify({ app: 'MtM3', formatVersion: 1, flags: this.theme.flags, colors: this.theme.colors }, null, 2)));
    toast('Saved colors');
  },
  async importPreset() {
    const p = await window.api.openFile('Import Colors & Settings', [{ name: 'MtM3 preset', extensions: ['json'] }]); if (!p) return;
    try {
      const j = JSON.parse(new TextDecoder().decode(window.api.readFile(p)));
      if (!j.colors || !j.flags) throw new Error('bad preset');
      const t = this.theme, keep = { backgroundMusic: t.flags.backgroundMusic, soundEffects: t.flags.soundEffects };
      t.colors = Object.assign(TK.Theme.defaultColors(), j.colors);
      t.flags = Object.assign(TK.Theme.defaultFlags(), j.flags, keep);
      if (t.flags.topDrawType === 3 && !t.textures.top) t.flags.topDrawType = 0;
      if (t.flags.bottomDrawType === 3 && !t.textures.bottom) t.flags.bottomDrawType = 0;
      if (t.flags.folderTexture && !(t.textures.folderClosed && t.textures.folderOpen)) t.flags.folderTexture = false;
      if (t.flags.fileTexture && !(t.textures.fileLarge && t.textures.fileSmall)) t.flags.fileTexture = false;
      this.frameChanged(); this.changed(true); toast('Imported colors');
    } catch (e) { alertError("That file isn't an MtM3 color preset."); }
  },

  // ───── rendering ─────
  previewState() { return { theme: this.theme, images: { ...this.images, __defaultPattern: this.defaultPatternCanvas }, icon: this.iconCanvas, mode: this.previewMode, title: this.name || 'My Theme', time: 0, forExport: false }; },
  go(section) { this.section = section; Audio3DS.stop(); this.showPreview({ icons: 'home', buttons: 'home', top: 'home', bottom: 'home', folderView: 'folder', text: 'zoom' }[section]); this.renderSidebar(); this.renderPage(); document.getElementById('editor').scrollTop = 0; },
  renderAll() { this.renderSidebar(); this.renderPage(); this.updateTopbar(); this.renderPreviewControls(); },
  updateTopbar() {
    document.getElementById('docName').textContent = this.displayName();
    document.getElementById('docPath').textContent = this.path ? '— ' + this.path : '';
    const bar = document.getElementById('topActions'); bar.innerHTML = '';
    const u = btn('Undo (Ctrl+Z)', 'undo', () => this.undo(), 'icon ghost'); u.disabled = !this.undoStack.length;
    const r = btn('Redo (Ctrl+Y)', 'redo', () => this.redo(), 'icon ghost'); r.disabled = !this.redoStack.length;
    bar.append(u, r, btn('Open Theme', 'open', () => this.openFileDialog()), btn('Export', 'export', () => this.go('export'), 'primary'));
  },
  isCustomized(id) {
    const f = this.theme.flags;
    switch (id) {
      case 'info': return !!this.name;
      case 'top': return f.topDrawType !== 0;
      case 'bottom': return f.bottomDrawType !== 0;
      case 'icons': return f.cursorColor || f.folderColor || f.folderTexture || f.fileColor || f.fileTexture;
      case 'buttons': return f.arrowButtonColor || f.arrowColor || f.openCloseColor || f.topCornerColor || f.bottomCornerColor;
      case 'folderView': return f.folderBackgroundColor || f.folderArrowColor;
      case 'text': return f.gameTextDrawType !== 0 || f.demoTextColor;
      case 'music': return f.backgroundMusic && !!this.bgm.data;
      case 'sounds': return f.soundEffects;
      default: return false;
    }
  },
  renderSidebar() {
    const nav = document.getElementById('sidebar'); nav.innerHTML = '';
    let group = null, g;
    for (const s of SECTIONS) {
      if (s.group !== group) { group = s.group; g = el('div', { class: 'nav-group' }, el('h6', {}, group)); nav.append(g); }
      g.append(el('div', { class: 'nav-item' + (this.section === s.id ? ' active' : ''), onclick: () => this.go(s.id) }, svg(s.icon), s.title, this.isCustomized(s.id) ? el('span', { class: 'badge', title: 'Customized' }) : null));
    }
    const foot = el('div', { class: 'sidebar-foot' }, this.iconCanvas || el('span'), el('div', {}, el('b', {}, this.displayName()), el('span', {}, this.author || 'No author')));
    nav.append(foot);
  },
  renderPage() {
    const ed = document.getElementById('editor'), top = ed.scrollTop;
    ed.innerHTML = '';
    ed.append(Pages[this.section]());
    ed.scrollTop = top;
  },
  renderPreviewControls() {
    const c = document.getElementById('previewControls'); c.innerHTML = '';
    c.append(
      segmented(Preview.MODES, this.previewMode, (v) => { this.previewMode = v; this.renderPreviewControls(); if (this.section === 'folderView') this.renderPage(); }),
      btn(this.animate ? 'Pause' : 'Play', this.animate ? 'pause' : 'play', () => { this.animate = !this.animate; this.renderPreviewControls(); }, 'small'),
      btn('Save preview.png', 'image', () => this.savePreview(), 'small ghost'),
    );
  },
  startPreviewLoop() {
    const top = document.getElementById('topCanvas'), bot = document.getElementById('bottomCanvas'), pane = document.getElementById('preview'), shell = document.getElementById('console');
    Preview.mountShell(shell);
    let frozen = 0;
    const frame = (ts) => {
      const dpr = window.devicePixelRatio || 1;
      const mob = window.innerWidth <= 860, padX = mob ? 16 : 40, padY = mob ? 64 : 120;
      const fits = (c) => { const [w, h] = Preview.shellSize(c); return Math.min((pane.clientWidth - padX) / w, (pane.clientHeight - padY) / h); };
      const compact = mob || fits(false) < 0.62, scale = Math.max(mob ? 0.2 : 0.45, Math.min(2.2, fits(compact)));
      if (compact !== shell.classList.contains('compact')) shell.classList.toggle('compact', compact);
      if (shell.style.getPropertyValue('--s') !== String(scale)) shell.style.setProperty('--s', String(scale));
      for (const [cv, w] of [[top, 412], [bot, 320]]) {
        const W = Math.round(w * scale * dpr), H = Math.round(240 * scale * dpr);
        if (cv.width !== W || cv.height !== H) { cv.width = W; cv.height = H; cv.style.width = W / dpr + 'px'; cv.style.height = H / dpr + 'px'; }
      }
      const time = this.animate ? ts / 1000 : frozen; if (this.animate) frozen = time;
      const s = { ...this.previewState(), time };
      let ctx = top.getContext('2d'); ctx.setTransform(scale * dpr, 0, 0, scale * dpr, 0, 0); Preview.drawTop(ctx, s);
      ctx = bot.getContext('2d'); ctx.setTransform(scale * dpr, 0, 0, scale * dpr, 0, 0); Preview.drawBottom(ctx, s);
      requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  },
  async init() {
    this.defaultPatternCanvas = Imaging.imageToCanvas(TK.DEFAULT_PATTERN, true);
    this.iconCanvas = Imaging.imageToCanvas(this.icon);
    this.lastSnap = this.snapshot();
    window.api.onMenu((a) => this.menu(a));
    window.api.onSendProgress((p) => Busy.progress(p));
    // Drop a theme anywhere to open it
    document.addEventListener('dragover', (e) => e.preventDefault());
    document.addEventListener('drop', async (e) => {
      e.preventDefault(); const f = e.dataTransfer.files[0]; if (!f) return;
      const p = window.api.pathForFile(f);
      if (window.api.isDir(p) || /\.(zip|bin)$/i.test(p)) { if (await this.confirmDiscard()) this.open(p); }
    });
    this.renderAll();
    this.startPreviewLoop();
  },
  async menu(a) {
    switch (a) {
      case 'new': if (await this.confirmDiscard()) this.reset(); break;
      case 'open-folder': this.openFolderDialog(); break;
      case 'open-file': this.openFileDialog(); break;
      case 'export-folder': this.exportFolder(); break;
      case 'export-zip': this.exportZip(); break;
      case 'save-preview': this.savePreview(); break;
      case 'export-preset': this.exportPreset(); break;
      case 'import-preset': this.importPreset(); break;
      case 'undo': this.undo(); break;
      case 'redo': this.redo(); break;
      case 'toggle-animation': this.animate = !this.animate; this.renderPreviewControls(); break;
      case 'toggle-folder': this.folderMode = !this.folderMode; this.renderPreviewControls(); break;
      case 'about': window.api.about(); break;
      case 'request-close': if (await this.confirmDiscard()) window.api.closeWindow(); break;
    }
  },
};
