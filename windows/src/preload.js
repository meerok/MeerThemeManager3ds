// Safe bridge between the UI and the computer (files, dialogs, networking).
const { contextBridge, ipcRenderer, webUtils } = require('electron');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

contextBridge.exposeInMainWorld('api', {
  // Dialogs
  openFile: (title, filters) => ipcRenderer.invoke('dialog:open', { title, filters }),
  openFolder: (title, button) => ipcRenderer.invoke('dialog:open', { title, folder: true, create: true, button }),
  saveFile: (title, name, filters) => ipcRenderer.invoke('dialog:save', { title, name, filters }),
  confirm: (message, detail, buttons) => ipcRenderer.invoke('dialog:confirm', { message, detail, buttons }),

  // Files
  readFile: (p) => new Uint8Array(fs.readFileSync(p)),
  writeFile: (p, data) => fs.writeFileSync(p, Buffer.from(data)),
  mkdir: (p) => fs.mkdirSync(p, { recursive: true }),
  readdir: (p) => fs.readdirSync(p),
  isDir: (p) => { try { return fs.statSync(p).isDirectory(); } catch (e) { return false; } },
  exists: (p) => fs.existsSync(p),
  remove: (p) => { try { fs.unlinkSync(p); } catch (e) { /* ignore */ } },
  join: (...parts) => path.join(...parts),
  basename: (p) => path.basename(p),
  dirname: (p) => path.dirname(p),
  extname: (p) => path.extname(p),
  pathForFile: (file) => webUtils.getPathForFile(file),
  inflateRaw: (bytes) => new Uint8Array(zlib.inflateRawSync(Buffer.from(bytes))),

  // Shell
  reveal: (p) => ipcRenderer.invoke('shell:reveal', p),
  openExternal: (url) => ipcRenderer.invoke('shell:open', url),

  // App
  info: () => ipcRenderer.invoke('app:info'),
  about: () => ipcRenderer.invoke('app:about'),
  closeWindow: () => ipcRenderer.invoke('app:close'),
  onMenu: (fn) => ipcRenderer.on('menu', (_e, action) => fn(action)),

  // CHMM2
  sendTheme: (ip, data) => ipcRenderer.invoke('net:send-theme', { ip, data }),
  onSendProgress: (fn) => ipcRenderer.on('net:progress', (_e, p) => fn(p)),

  // README screenshots
  capture: (name) => ipcRenderer.invoke('demo:capture', name),
  demoDone: () => ipcRenderer.invoke('demo:done'),
});
