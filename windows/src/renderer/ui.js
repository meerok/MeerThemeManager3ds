// Tiny DOM helpers used to build every page.
function el(tag, attrs = {}, ...children) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k === 'class') e.className = v;
    else if (k === 'html') e.innerHTML = v;
    else if (k === 'style' && typeof v === 'object') Object.assign(e.style, v);
    else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else e.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat()) {
    if (c === null || c === undefined || c === false) continue;
    e.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return e;
}
const svg = (name) => { const s = document.createElement('span'); s.style.display = 'contents'; s.innerHTML = icon(name); return s; };

const rgbHex = (c) => '#' + c.slice(0, 3).map((v) => v.toString(16).padStart(2, '0')).join('').toUpperCase();
const hexRgb = (h) => { const m = /^#?([0-9a-f]{6})$/i.exec((h || '').trim()); if (!m) return null; const v = parseInt(m[1], 16); return [(v >> 16) & 255, (v >> 8) & 255, v & 255]; };
const fmtBytes = (n) => n < 1024 ? `${n} B` : n < 1048576 ? `${(n / 1024).toFixed(1)} KB` : `${(n / 1048576).toFixed(2)} MB`;
const fmtTime = (s) => { const t = Math.round(s); return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`; };

function btn(label, iconName, onclick, cls = '') {
  return el('button', { class: 'btn ' + cls, onclick, title: cls.includes('icon') ? label : undefined }, iconName ? svg(iconName) : null, cls.includes('icon') ? null : label);
}
function card(...children) { return el('div', { class: 'card' }, ...children); }
function cardHead(title, iconName, subtitle, right) {
  return el('div', { class: 'card-head' }, svg(iconName), el('div', { class: 't' }, el('b', {}, title), subtitle ? el('small', {}, subtitle) : null), right || null);
}
function pageHead(section, text) {
  return el('div', { class: 'page-head' }, el('div', { class: 'ico', html: icon(section.icon) }), el('div', {}, el('h1', {}, section.title), el('p', {}, text)));
}
function banner(text, iconName = 'info', warn = false) { return el('div', { class: 'banner' + (warn ? ' warn' : '') }, svg(iconName), el('div', {}, text)); }

function toggleSwitch(checked, onchange) {
  const input = el('input', { type: 'checkbox' }); input.checked = !!checked;
  input.addEventListener('change', () => onchange(input.checked));
  return el('label', { class: 'switch' }, input, el('span'));
}

/** Card with a switch bound to a theme flag. */
function toggleCard(title, iconName, subtitle, get, set, content, offText = 'Uses the standard HOME Menu look. Turn on to customize.') {
  const on = get();
  return card(
    cardHead(title, iconName, subtitle, toggleSwitch(on, (v) => { set(v); App.changed(true); })),
    on ? el('div', { class: 'divider' }) : null,
    on ? el('div', { style: { display: 'flex', flexDirection: 'column', gap: '4px' } }, ...content()) : el('div', { class: 'off' }, offText),
  );
}

function updateRangeFill(r) { const p = (r.value - r.min) / (r.max - r.min) * 100; r.style.setProperty('--p', p + '%'); }
function range(min, max, step, value, oninput) {
  const r = el('input', { type: 'range', min, max, step, value });
  updateRangeFill(r);
  r.addEventListener('input', () => { updateRangeFill(r); oninput(parseFloat(r.value)); });
  return r;
}

/** Color row with hex field, color well and drag-and-drop from the palette. */
function colorRow(label, help, get, set) {
  const cur = get();
  const hex = el('input', { type: 'text', class: 'hex', value: rgbHex(cur), spellcheck: 'false' });
  const well = el('input', { type: 'color', value: rgbHex(cur).toLowerCase() });
  const sw = el('div', { class: 'swatch', style: { background: rgbHex(cur) } }, well);
  const apply = (c, fromWell) => {
    const old = get(); const next = old.length === 4 ? [c[0], c[1], c[2], old[3]] : c;
    set(next); sw.style.background = rgbHex(c); hex.value = rgbHex(c); if (!fromWell) well.value = rgbHex(c).toLowerCase();
    App.changed();
  };
  well.addEventListener('input', () => apply(hexRgb(well.value), true));
  hex.addEventListener('change', () => { const c = hexRgb(hex.value); if (c) apply(c); else hex.value = rgbHex(get()); });
  const row = el('div', { class: 'color-row' }, el('div', { class: 'lbl' }, label, help ? el('small', {}, help) : null), hex, sw);
  row.addEventListener('dragover', (e) => { if (e.dataTransfer.types.includes('text/x-mtm3-color')) { e.preventDefault(); row.classList.add('drop'); } });
  row.addEventListener('dragleave', () => row.classList.remove('drop'));
  row.addEventListener('drop', (e) => { row.classList.remove('drop'); const c = hexRgb(e.dataTransfer.getData('text/x-mtm3-color')); if (c) { e.preventDefault(); apply(c); } });
  return row;
}
function colorAlphaRow(label, help, get, set) {
  const pct = el('span', {}, Math.round(get()[3] / 2.55) + '%');
  return el('div', {},
    colorRow(label, help, get, set),
    el('div', { class: 'alpha-row' }, el('span', { style: { width: '56px' } }, 'Opacity'),
      range(0, 255, 1, get()[3], (v) => { const c = get(); set([c[0], c[1], c[2], v]); pct.textContent = Math.round(v / 2.55) + '%'; App.changed(); }), pct));
}

/** Labeled slider; double-click the value to reset to `neutral`. */
function slider(label, get, set, min, max, step, neutral, format, help, onchange) {
  const val = el('span', { title: 'Double-click to reset' }, format(get()));
  const hasNeutral = neutral !== null && neutral !== undefined;
  const mark = () => val.classList.toggle('changed', hasNeutral && Math.abs(get() - neutral) > 1e-9);
  const r = range(min, max, step, get(), (v) => { set(v); val.textContent = format(v); mark(); (onchange || (() => App.changed()))(); });
  val.addEventListener('dblclick', () => { if (!hasNeutral) return; set(neutral); r.value = neutral; updateRangeFill(r); val.textContent = format(neutral); mark(); (onchange || (() => App.changed()))(); });
  mark();
  return el('div', { class: 'slider-row' }, el('div', { class: 'top' }, el('b', { style: { fontWeight: 500 } }, label), val), r, help ? el('small', {}, help) : null);
}
const percentSlider = (label, get, set, help) => slider(label, get, set, 0, 255, 1, null, (v) => Math.round(v / 2.55) + '%', help);

function modePicker(options, current, onpick) {
  return el('div', { class: 'modes' }, ...options.map(([value, title, iconName]) =>
    el('div', { class: 'mode' + (value === current ? ' sel' : ''), onclick: () => onpick(value) }, svg(iconName), title)));
}
function segmented(options, current, onpick) {
  return el('div', { class: 'seg' }, ...options.map(([value, title]) =>
    el('button', { class: value === current ? 'sel' : '', onclick: () => onpick(value) }, title)));
}
function selectBox(options, current, onpick) {
  const s = el('select', { onchange: () => onpick(options[s.selectedIndex][0]) }, ...options.map(([v, t]) => { const o = el('option', {}, t); if (v === current) o.selected = true; return o; }));
  return s;
}
function meter(label, used, limit) {
  const f = limit ? used / limit : 0;
  return el('div', { class: 'meter' + (f > 1 ? ' bad' : f > 0.85 ? ' warn' : '') },
    el('div', { class: 'top' }, label, el('span', {}, `${fmtBytes(used)} of ${fmtBytes(limit)}`)),
    el('div', { class: 'bar' }, el('div', { style: { width: Math.min(100, f * 100) + '%' } })));
}

/** Makes an element accept dropped files; calls handler(path). */
function fileDrop(node, handler, cls = 'drop') {
  node.addEventListener('dragover', (e) => { if (e.dataTransfer.types.includes('Files')) { e.preventDefault(); e.stopPropagation(); node.classList.add(cls); } });
  node.addEventListener('dragleave', () => node.classList.remove(cls));
  node.addEventListener('drop', (e) => {
    node.classList.remove(cls);
    const f = e.dataTransfer.files[0]; if (!f) return;
    e.preventDefault(); e.stopPropagation();
    handler(window.api.pathForFile(f));
  });
}

function toast(msg) {
  document.querySelectorAll('.toast').forEach((t) => t.remove());
  const t = el('div', { class: 'toast' }, msg); document.body.append(t);
  setTimeout(() => t.remove(), 3600);
}
const Busy = {
  node: null, bar: null,
  show(text, withProgress = false) {
    this.hide();
    this.bar = withProgress ? el('div', { class: 'progress' }, el('div', { style: { width: '0%' } })) : null;
    this.node = el('div', { class: 'busy' }, el('div', {}, el('div', { class: 'spinner' }), el('div', {}, el('b', {}, text), this.bar)));
    document.body.append(this.node);
  },
  progress(p) { if (this.bar) this.bar.firstChild.style.width = Math.round(p * 100) + '%'; },
  hide() { if (this.node) this.node.remove(); this.node = null; },
};
async function alertError(msg) { await window.api.confirm('Something went wrong', msg, ['OK']); }
