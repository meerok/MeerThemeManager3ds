// MtM3 (Meer Theme Manager 3ds) — Electron main process
const { app, BrowserWindow, Menu, ipcMain, dialog, shell, nativeImage } = require('electron');
const path = require('path');
const fs = require('fs');
const net = require('net');

const DEMO_DIR = process.env.MTM3_DEMO_DIR || null;   // used to generate README screenshots
let win;

function sendMenu(action) { if (win) win.webContents.send('menu', action); }

function buildMenu() {
  const isMac = process.platform === 'darwin';
  const template = [
    ...(isMac ? [{ role: 'appMenu' }] : []),
    {
      label: '&File',
      submenu: [
        { label: 'New Theme', accelerator: 'CmdOrCtrl+N', click: () => sendMenu('new') },
        { label: 'Open Theme Folder…', accelerator: 'CmdOrCtrl+O', click: () => sendMenu('open-folder') },
        { label: 'Open Theme File (.zip / body_LZ.bin)…', accelerator: 'CmdOrCtrl+Shift+O', click: () => sendMenu('open-file') },
        { type: 'separator' },
        { label: 'Export Theme Folder…', accelerator: 'CmdOrCtrl+S', click: () => sendMenu('export-folder') },
        { label: 'Export Theme ZIP…', accelerator: 'CmdOrCtrl+Shift+S', click: () => sendMenu('export-zip') },
        { label: 'Save Preview Image…', click: () => sendMenu('save-preview') },
        { type: 'separator' },
        { label: 'Export Colors & Settings…', click: () => sendMenu('export-preset') },
        { label: 'Import Colors & Settings…', click: () => sendMenu('import-preset') },
        { type: 'separator' },
        isMac ? { role: 'close' } : { role: 'quit', label: 'Exit' },
      ],
    },
    {
      label: '&Edit',
      submenu: [
        { label: 'Undo', accelerator: 'CmdOrCtrl+Z', click: () => sendMenu('undo') },
        { label: 'Redo', accelerator: 'CmdOrCtrl+Y', click: () => sendMenu('redo') },
        { type: 'separator' },
        { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' },
      ],
    },
    {
      label: '&View',
      submenu: [
        { label: 'Play / Pause Preview Animation', accelerator: 'CmdOrCtrl+Alt+P', click: () => sendMenu('toggle-animation') },
        { label: 'Home / Folder View', accelerator: 'CmdOrCtrl+Alt+F', click: () => sendMenu('toggle-folder') },
        { type: 'separator' },
        { role: 'resetZoom' }, { role: 'zoomIn' }, { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' },
        { role: 'toggleDevTools', visible: false },
      ],
    },
    {
      label: '&Help',
      submenu: [
        { label: 'How to Use MtM3', click: () => shell.openExternal('https://github.com/meerok/MeerThemeManager3ds#how-to-use') },
        { label: 'ThemePlaza', click: () => shell.openExternal('https://themeplaza.art/themes') },
        { type: 'separator' },
        { label: 'About Meer Theme Manager 3ds', click: () => sendMenu('about') },
      ],
    },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

function createWindow() {
  win = new BrowserWindow({
    width: DEMO_DIR ? 1440 : 1440,
    height: DEMO_DIR ? 900 : 920,
    minWidth: 1150,
    minHeight: 720,
    backgroundColor: '#0f1020',
    title: 'Meer Theme Manager 3ds',
    icon: path.join(__dirname, '..', 'assets', 'icon.png'),
    show: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
      backgroundThrottling: false,
    },
  });
  win.loadFile(path.join(__dirname, 'renderer', 'index.html'), DEMO_DIR ? { query: { demo: DEMO_DIR } } : undefined);
  win.on('close', (e) => {
    if (DEMO_DIR || win.forceClose) return;
    e.preventDefault();
    win.webContents.send('menu', 'request-close');
  });
}

// ───── IPC ─────
ipcMain.handle('dialog:open', async (_e, opts) => {
  const r = await dialog.showOpenDialog(win, {
    title: opts.title,
    properties: [opts.folder ? 'openDirectory' : 'openFile', ...(opts.create ? ['createDirectory'] : [])],
    filters: opts.filters,
    buttonLabel: opts.button,
  });
  return r.canceled ? null : r.filePaths[0];
});
ipcMain.handle('dialog:save', async (_e, opts) => {
  const r = await dialog.showSaveDialog(win, { title: opts.title, defaultPath: opts.name, filters: opts.filters });
  return r.canceled ? null : r.filePath;
});
ipcMain.handle('dialog:confirm', async (_e, opts) => {
  const r = await dialog.showMessageBox(win, { type: 'warning', message: opts.message, detail: opts.detail, buttons: opts.buttons, defaultId: 0, cancelId: opts.buttons.length - 1 });
  return r.response;
});
ipcMain.handle('shell:reveal', (_e, p) => shell.showItemInFolder(p));
ipcMain.handle('shell:open', (_e, url) => shell.openExternal(url));
ipcMain.handle('app:close', () => { win.forceClose = true; win.close(); });
ipcMain.handle('app:info', () => ({ version: app.getVersion(), demo: DEMO_DIR }));
ipcMain.handle('app:about', async () => {
  await dialog.showMessageBox(win, {
    type: 'info',
    title: 'About MtM3',
    icon: nativeImage.createFromPath(path.join(__dirname, '..', 'assets', 'icon.png')).resize({ width: 96, height: 96 }),
    message: 'Meer Theme Manager 3ds (MtM3)',
    detail: `Version ${app.getVersion()}\n\nMake Nintendo 3DS HOME Menu themes for ThemePlaza, Anemone3DS and CHMM2.\n\nFile formats based on Usagi 3DS Theme Editor and 3dbrew. DSP-ADPCM encoder ported from VGAudio.`,
  });
});

// Screenshot capture for the README (demo mode only)
ipcMain.handle('demo:capture', async (_e, name) => {
  if (!DEMO_DIR) return false;
  const img = await win.webContents.capturePage();
  fs.writeFileSync(path.join(DEMO_DIR, 'shots', name + '.png'), img.toPNG());
  return true;
});
ipcMain.handle('demo:done', () => app.quit());

// CHMM2 network sender ("YATA SENDER" protocol, TCP 5000)
ipcMain.handle('net:send-theme', (_e, { ip, data }) => new Promise((resolve) => {
  const zip = Buffer.from(data);
  const sock = net.createConnection({ host: ip, port: 5000 });
  let stage = 'hello', received = Buffer.alloc(0), done = false;
  const finish = (r) => { if (done) return; done = true; sock.destroy(); resolve(r); };
  const timer = setTimeout(() => finish({ ok: false, error: "Couldn't reach the 3DS. Make sure CHMM2 is waiting to receive and both devices are on the same Wi-Fi." }), 15000);
  sock.on('error', (e) => { clearTimeout(timer); finish({ ok: false, error: e.message }); });
  sock.on('data', (chunk) => {
    received = Buffer.concat([received, chunk]);
    if (stage === 'hello' && received.length >= 11) {
      if (received.subarray(0, 11).toString() !== 'YATA SENDER') { clearTimeout(timer); return finish({ ok: false, error: 'The 3DS answered, but not with the CHMM2 receiver handshake.' }); }
      received = received.subarray(11); stage = 'send';
      let off = 0;
      const pump = () => {
        while (off < zip.length) {
          const end = Math.min(off + 8192, zip.length);
          const ok = sock.write(zip.subarray(off, end)); off = end;
          win.webContents.send('net:progress', off / zip.length);
          if (!ok) { sock.once('drain', pump); return; }
        }
        stage = 'bye';
      };
      pump();
    }
    if (stage === 'bye' && received.length >= 9) { clearTimeout(timer); finish(received.subarray(0, 9).toString() === 'YATA TERM' ? { ok: true } : { ok: false, error: 'Unexpected reply from the 3DS.' }); }
  });
}));

app.whenReady().then(() => {
  if (DEMO_DIR) app.commandLine.appendSwitch('force-device-scale-factor', '1');
  buildMenu();
  createWindow();
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});
app.on('window-all-closed', () => app.quit());
