// Builds each editor page.
const IMG_FILTERS = [{ name: 'Pictures', extensions: ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'tif', 'tiff'] }];
const AUDIO_FILTERS = [{ name: 'Audio', extensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'oga', 'flac', 'opus', 'webm', 'aif', 'aiff', 'bcstm'] }];
const SFX_FILTERS = [{ name: 'Audio', extensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'opus', 'bcwav'] }];
const FIT_OPTIONS = [['fill', 'Fill (crop edges)'], ['fit', 'Fit (letterbox)'], ['stretch', 'Stretch']];

function sec(id) { return SECTIONS.find((s) => s.id === id); }
function page(...children) { return el('div', { class: 'page' }, ...children); }
const F = () => App.theme.flags, C = () => App.theme.colors;

/** Picture slot with thumbnail, drop target, Edit/Replace/Remove. */
function imageSlot(slot, title, detail, height = 130) {
  const f = F(), [vw, vh] = TK.Geometry.visible(slot, f), [cw, ch] = TK.Geometry.canvas(slot, f);
  const src = App.sources[slot], img = App.images[slot];
  const thumb = el('div', { class: 'thumb' + (img ? ' has' : ''), style: { height: height + 'px' } });
  if (img) {
    const c = document.createElement('canvas'); c.width = Math.min(vw, img.width); c.height = Math.min(vh, img.height);
    const x = c.getContext('2d');
    if (TK.SLOTS[slot] === 'a8') { x.fillStyle = '#000'; x.fillRect(0, 0, c.width, c.height); }
    x.drawImage(img, 0, 0);
    if (c.width < 140) c.classList.add('px');
    Object.assign(c.style, { position: 'absolute', inset: '4px', width: 'calc(100% - 8px)', height: 'calc(100% - 8px)', objectFit: 'contain' });
    thumb.append(c, el('div', { class: 'hover' }, src ? 'Click to edit' : ''));
  } else {
    thumb.append(el('div', { class: 'empty' }, svg('imagePlus'), 'Drop any picture here — it\'s resized automatically'));
  }
  const choose = async () => { const p = await window.api.openFile(`Choose a picture for ${title}`, IMG_FILTERS); if (p) App.loadPicture(slot, p); };
  thumb.addEventListener('click', () => (src ? Editor.open(slot, title) : choose()));
  fileDrop(thumb, (p) => App.loadPicture(slot, p));
  const controls = el('div', { class: 'row wrap' },
    btn(src ? 'Replace…' : 'Choose…', 'open', choose, 'small'),
    src ? btn('Edit…', 'sliders', () => Editor.open(slot, title), 'small') : null,
    src ? selectBox(FIT_OPTIONS, src.edit.fit, (v) => { src.edit.fit = v; App.renderSlot(slot); App.renderPage(); }) : null,
    el('div', { class: 'grow' }),
    src || img ? btn('Remove', 'trash', () => App.clearPicture(slot), 'small danger') : null);
  if (controls.querySelector('select')) Object.assign(controls.querySelector('select').style, { width: '150px', padding: '5px 26px 5px 8px', fontSize: '12px' });
  return el('div', { style: { display: 'flex', flexDirection: 'column', gap: '10px' } },
    el('div', { class: 'slot-head' }, el('div', { class: 't' }, el('b', {}, title), el('small', {}, detail)),
      el('span', { class: 'pill' }, vw === cw && vh === ch ? `${cw} × ${ch}` : `${vw} × ${vh} visible`)),
    thumb, controls);
}

const Pages = {
  paletteCard() {
    if (!App.palette.length) return el('div', { class: 'palette-host' });
    return el('div', { class: 'palette-host' }, card(
      cardHead('Wallpaper Palette', 'palette', 'Drag a swatch onto any color below. Click to copy its hex code.'),
      el('div', { class: 'palette' }, ...App.palette.map((c) => {
        const d = el('div', { draggable: 'true', title: rgbHex(c), style: { background: rgbHex(c) } });
        d.addEventListener('dragstart', (e) => e.dataTransfer.setData('text/x-mtm3-color', rgbHex(c)));
        d.addEventListener('click', () => { navigator.clipboard.writeText(rgbHex(c)); toast('Copied ' + rgbHex(c)); });
        return d;
      }))));
  },

  info() {
    const field = (label, limit, value, set, multiline, placeholder, help) => {
      const count = el('span', {}, `${value.length}/${limit}`);
      const input = multiline ? el('textarea', { maxlength: limit, placeholder }) : el('input', { type: 'text', maxlength: limit, placeholder });
      input.value = value;
      input.addEventListener('input', () => { set(input.value); count.textContent = `${input.value.length}/${limit}`; App.setDirty(true); App.updateTopbar(); App.renderSidebar(); });
      return el('div', { class: 'field' }, el('label', {}, label, count), input, el('small', {}, help));
    };
    const iconCv = document.createElement('canvas'); iconCv.width = 48; iconCv.height = 48;
    if (App.iconCanvas) iconCv.getContext('2d').drawImage(App.iconCanvas, 0, 0);
    Object.assign(iconCv.style, { width: '96px', height: '96px', imageRendering: 'pixelated', borderRadius: '14px' });
    const iconBox = el('div', { class: 'thumb has', style: { width: '100px', height: '100px', flex: 'none' } }, iconCv);
    const pickIcon = async () => { const p = await window.api.openFile('Choose a theme icon', IMG_FILTERS); if (p) App.setIcon(await Imaging.loadPath(p)); };
    iconBox.addEventListener('click', pickIcon);
    fileDrop(iconBox, async (p) => App.setIcon(await Imaging.loadPath(p)));
    return page(
      pageHead(sec('info'), 'The name, description and icon shown in theme managers like Anemone3DS and on ThemePlaza. Saved in info.smdh automatically.'),
      card(cardHead('Details', 'text'),
        field('Theme Name', 64, App.name, (v) => { App.name = v; }, false, 'My Awesome Theme', 'Up to 64 characters.'),
        field('Description', 128, App.description, (v) => { App.description = v; }, true, 'A short description of your theme', 'Up to 128 characters.'),
        field('Author', 64, App.author, (v) => { App.author = v; }, false, 'Your name', 'Your name or username.')),
      card(cardHead('Theme Icon', 'image', '48 × 48 pixels. The 24 × 24 version is made automatically.'),
        el('div', { class: 'row', style: { gap: '18px' } }, iconBox,
          el('div', { style: { display: 'flex', flexDirection: 'column', gap: '8px' } },
            el('div', { class: 'muted' }, 'Drop any picture onto the icon, or choose one. Bold, simple artwork reads best at this tiny size.'),
            el('div', { class: 'row' }, btn('Choose Picture…', 'open', pickIcon, 'small'),
              App.sources.top ? btn('Use Top Wallpaper', 'top', () => App.setIcon(App.sources.top.canvas), 'small') : null)))),
      banner('Tip: ThemePlaza shows your preview image plus the name and description from this page, so fill them in before exporting.'),
    );
  },

  top() {
    const f = F(), tb = C().topBackground;
    const out = [pageHead(sec('top'), 'The upper screen\'s background. Use a picture, a solid color, or a color with moving patterns.'),
      card(cardHead('Background Style', 'palette'), modePicker([[0, 'Default', 'circleSlash'], [1, 'Color', 'brush'], [2, 'Color + Pattern', 'pattern'], [3, 'Picture', 'image']], f.topDrawType, (v) => { f.topDrawType = v; App.changed(true); }))];
    if (f.topDrawType === 3) {
      out.push(card(cardHead('Movement', 'arrows', 'Scrolling wallpapers are wider and pan as you scroll through your icons.'),
        segmented([[1, 'Still'], [3, 'Slow Scroll'], [0, 'Fast Scroll']], f.topFrameType, (v) => { f.topFrameType = v; App.frameChanged(); App.changed(true); })));
      out.push(card(imageSlot('top', 'Top Wallpaper', f.topFrameType !== 1 ? 'Best size: 1008 × 240 (it scrolls sideways).' : 'Best size: 412 × 240. The outer 6 px on each side only show in 3D.', 160),
        el('label', { class: 'row' }, toggleSwitch(App.theme.ditherBackgrounds, (v) => { App.theme.ditherBackgrounds = v; App.changed(); }), el('span', {}, 'Smooth gradients (dithering) — reduces color banding on the 3DS\'s 16-bit screen'))));
    } else if (f.topDrawType === 1 || f.topDrawType === 2) {
      out.push(card(cardHead('Color', 'brush'),
        colorRow('Background Color', null, () => tb.main, (v) => { tb.main = v; }),
        percentSlider('Gradient Strength', () => tb.gradient, (v) => { tb.gradient = v; }, 'How strongly the glow fades down the screen.'),
        percentSlider('Gradient Brightness', () => tb.gradientColor, (v) => { tb.gradientColor = v; }, '0% fades to black, 100% fades to white.')));
      if (f.topDrawType === 2) {
        out.push(card(imageSlot('topPattern', 'Pattern', '64 × 64 grayscale mask that tiles across the screen. White = visible, black = transparent.', 110),
          percentSlider('Pattern Opacity', () => tb.textureOpacity, (v) => { tb.textureOpacity = v; })));
        out.push(card(imageSlot('topAltPattern', 'Second Pattern (optional)', 'Another 64 × 64 mask layered on top, moving the other way.', 110),
          percentSlider('Second Pattern Opacity', () => tb.alternateOpacity, (v) => { tb.alternateOpacity = v; })));
      }
    } else out.push(banner('The default HOME Menu background will be used. Pick a style above to customize it.'));
    out.push(Pages.paletteCard());
    return page(...out);
  },

  bottom() {
    const f = F(), c = C();
    const helpSize = { 1: 'Best size: 320 × 240.', 2: 'Best size: 960 × 240 (three screens side by side).', 4: 'Best size: 960 × 240 (three screens side by side).', 0: 'Best size: 1008 × 240 (it scrolls sideways).', 3: 'Best size: 1008 × 240 (it scrolls sideways).' };
    const helpMove = { 1: 'The wallpaper stays put.', 3: 'The wallpaper pans smoothly with your icons.', 0: 'The wallpaper pans quickly with your icons.', 2: 'Jumps one screen (320 px) at a time across 3 screens.', 4: 'Like Page Flip, but bounces back from the last screen.' };
    const out = [pageHead(sec('bottom'), 'The lower (touch) screen behind your icons. Use a picture or recolor the panels.'),
      card(cardHead('Background Style', 'palette'), modePicker([[0, 'Default', 'circleSlash'], [1, 'Colors', 'brush'], [3, 'Picture', 'image']], f.bottomDrawType, (v) => { f.bottomDrawType = v; App.changed(true); }))];
    if (f.bottomDrawType === 3) {
      out.push(card(cardHead('Movement', 'arrows', helpMove[f.bottomFrameType]),
        segmented([[1, 'Still'], [3, 'Slow Scroll'], [0, 'Fast Scroll'], [2, 'Page Flip'], [4, 'Bounce']], f.bottomFrameType, (v) => { f.bottomFrameType = v; App.frameChanged(); App.changed(true); })));
      out.push(card(imageSlot('bottom', 'Bottom Wallpaper', helpSize[f.bottomFrameType], 160),
        el('label', { class: 'row' }, toggleSwitch(App.theme.ditherBackgrounds, (v) => { App.theme.ditherBackgrounds = v; App.changed(); }), el('span', {}, 'Smooth gradients (dithering)'))));
    } else if (f.bottomDrawType === 1) {
      out.push(toggleCard('Inner Panel', 'square', 'The rounded area that holds your icons.', () => f.bottomInnerColor, (v) => { f.bottomInnerColor = v; }, () => [
        colorRow('Panel Color', null, () => c.bottomInner.main, (v) => { c.bottomInner.main = v; }),
        colorRow('Border', null, () => c.bottomInner.border, (v) => { c.bottomInner.border = v; }),
        colorRow('Bottom Highlight', 'Thin line along the panel\'s lower edge.', () => c.bottomInner.highlight, (v) => { c.bottomInner.highlight = v; }),
        colorAlphaRow('Shadow', 'Soft shadow around the panel.', () => c.bottomInner.glow, (v) => { c.bottomInner.glow = v; })]));
      out.push(toggleCard('Outer Frame', 'bottom', 'The area around the inner panel.', () => f.bottomOuterColor, (v) => { f.bottomOuterColor = v; }, () => [
        colorRow('Frame Color', null, () => c.bottomOuter.main, (v) => { c.bottomOuter.main = v; }),
        colorRow('Side Glow', 'Gradient on the left and right edges.', () => c.bottomOuter.glow, (v) => { c.bottomOuter.glow = v; }),
        colorRow('Stripes', 'Fine lines near the bottom.', () => c.bottomOuter.stripes, (v) => { c.bottomOuter.stripes = v; })]));
    } else out.push(banner('The default HOME Menu background will be used. Pick a style above to customize it.'));
    out.push(Pages.paletteCard());
    return page(...out);
  },

  icons() {
    const f = F(), c = C(), t = App.theme.textures;
    return page(pageHead(sec('icons'), 'The selection cursor, folder icons and file icons in your HOME Menu grid.'), Pages.paletteCard(),
      toggleCard('Cursor', 'cursor', 'The highlight around the selected icon.', () => f.cursorColor, (v) => { f.cursorColor = v; }, () => [
        colorRow('Main', null, () => c.cursor.main, (v) => { c.cursor.main = v; }),
        colorRow('Light Edge', null, () => c.cursor.light, (v) => { c.cursor.light = v; }),
        colorRow('Shading', null, () => c.cursor.shading, (v) => { c.cursor.shading = v; }),
        colorRow('Glow', 'The pulsing glow around the cursor.', () => c.cursor.glow, (v) => { c.cursor.glow = v; })]),
      toggleCard('Folder Colors', 'folder', 'Colors of the 3D folder icons.', () => f.folderColor, (v) => { f.folderColor = v; }, () => [
        colorRow('Main', null, () => c.folder.main, (v) => { c.folder.main = v; }),
        colorRow('Light', null, () => c.folder.light, (v) => { c.folder.light = v; }),
        colorRow('Shading', null, () => c.folder.shading, (v) => { c.folder.shading = v; }),
        colorRow('Shadow', null, () => c.folder.shadow, (v) => { c.folder.shadow = v; })]),
      toggleCard('Folder Pictures', 'image', 'Wrap your own art onto folder icons (both pictures required).', () => f.folderTexture, (v) => { f.folderTexture = v; }, () => [
        el('div', { class: 'cols2' }, imageSlot('folderClosed', 'Closed', '128 × 64', 90), imageSlot('folderOpen', 'Open', '128 × 64', 90)),
        !(t.folderClosed && t.folderOpen) ? banner('Add both the closed and open pictures, or folder pictures won\'t be included.', 'warn', true) : null], 'Folders use their colors. Turn on to add pictures.'),
      toggleCard('File Colors', 'file', 'Colors of the 3D file / cartridge icons.', () => f.fileColor, (v) => { f.fileColor = v; }, () => [
        colorRow('Main', null, () => c.file.main, (v) => { c.file.main = v; }),
        colorRow('Light', null, () => c.file.light, (v) => { c.file.light = v; }),
        colorRow('Shading', null, () => c.file.shading, (v) => { c.file.shading = v; }),
        colorAlphaRow('Shadow', null, () => c.file.shadow, (v) => { c.file.shadow = v; })]),
      toggleCard('File Pictures', 'image', 'Your own art on file icons (both pictures required).', () => f.fileTexture, (v) => { f.fileTexture = v; }, () => [
        el('div', { class: 'cols2' }, imageSlot('fileLarge', 'Large', '64 × 128', 110), imageSlot('fileSmall', 'Small', '32 × 64', 110)),
        !(t.fileLarge && t.fileSmall) ? banner('Add both the large and small pictures, or file pictures won\'t be included.', 'warn', true) : null], 'Files use their colors. Turn on to add pictures.'));
  },

  buttons() {
    const f = F(), c = C();
    const oc = (title, o) => [el('b', { class: 'muted small', style: { marginTop: '4px' } }, title),
      colorRow('Button', null, () => o.unpressed, (v) => { o.unpressed = v; }),
      colorRow('Button (Pressed)', null, () => o.pressed, (v) => { o.pressed = v; }),
      colorRow('Highlight', null, () => o.light, (v) => { o.light = v; }),
      colorRow('Glow / Edge', null, () => o.glow, (v) => { o.glow = v; }),
      colorAlphaRow('Shadow', null, () => o.shadow, (v) => { o.shadow = v; }),
      colorRow('Text', null, () => o.textUnpressed, (v) => { o.textUnpressed = v; }),
      colorRow('Text (Pressed)', null, () => o.textPressed, (v) => { o.textPressed = v; }),
      colorRow('Text Shadow', null, () => o.textShadow, (v) => { o.textShadow = v; }),
      slider('Text Shadow Offset', () => o.textShadowPosition, (v) => { o.textShadowPosition = v; }, -3, 3, 0.25, title.startsWith('Open') ? -1.25 : 1, (v) => (v >= 0 ? '+' : '') + v.toFixed(2))];
    return page(pageHead(sec('buttons'), 'The scroll arrows, the Open/Close button and the corner buttons on the bottom screen.'), Pages.paletteCard(),
      toggleCard('Arrow Buttons', 'arrows', 'The tabs on the left and right edges used to scroll.', () => f.arrowButtonColor, (v) => { f.arrowButtonColor = v; }, () => [
        colorRow('Main', null, () => c.arrowButton.main, (v) => { c.arrowButton.main = v; }),
        colorRow('Highlight', null, () => c.arrowButton.light, (v) => { c.arrowButton.light = v; }),
        colorRow('Shading', null, () => c.arrowButton.shading, (v) => { c.arrowButton.shading = v; }),
        colorAlphaRow('Shadow', null, () => c.arrowButton.shadow, (v) => { c.arrowButton.shadow = v; })]),
      toggleCard('Arrows', 'play', 'The arrow symbols inside the arrow buttons.', () => f.arrowColor, (v) => { f.arrowColor = v; }, () => [
        colorRow('Arrow', null, () => c.arrow.unpressed, (v) => { c.arrow.unpressed = v; }),
        colorRow('Arrow (Pressed)', null, () => c.arrow.pressed, (v) => { c.arrow.pressed = v; }),
        colorRow('Outline', null, () => c.arrow.border, (v) => { c.arrow.border = v; })]),
      toggleCard('Open & Close Buttons', 'buttons', '“Open” appears when software is selected; “Close” appears in folders.', () => f.openCloseColor, (v) => { f.openCloseColor = v; }, () => [
        ...oc('Open Button', c.open), el('div', { class: 'divider' }), ...oc('Close Button', c.close)]),
      toggleCard('Top Corner Buttons', 'corner', 'The buttons in the top-left and top-right of the bottom screen.', () => f.topCornerColor, (v) => { f.topCornerColor = v; }, () => [
        colorRow('Main', null, () => c.topCorner.main, (v) => { c.topCorner.main = v; }),
        colorRow('Light', null, () => c.topCorner.light, (v) => { c.topCorner.light = v; }),
        colorRow('Shadow', null, () => c.topCorner.shadow, (v) => { c.topCorner.shadow = v; }),
        colorRow('Icon / Text', null, () => c.topCorner.text, (v) => { c.topCorner.text = v; })]),
      toggleCard('Bottom Corner Buttons', 'corner', 'The buttons in the bottom-left and bottom-right corners.', () => f.bottomCornerColor, (v) => { f.bottomCornerColor = v; }, () => [
        colorRow('Main', null, () => c.bottomCorner.main, (v) => { c.bottomCorner.main = v; }),
        colorRow('Highlight', null, () => c.bottomCorner.highlight, (v) => { c.bottomCorner.highlight = v; }),
        colorRow('Border', null, () => c.bottomCorner.border, (v) => { c.bottomCorner.border = v; }),
        colorRow('Shadow', null, () => c.bottomCorner.baseShadow, (v) => { c.bottomCorner.baseShadow = v; }),
        colorRow('Icon (Top)', null, () => c.bottomCorner.iconTop, (v) => { c.bottomCorner.iconTop = v; }),
        colorRow('Icon (Bottom)', null, () => c.bottomCorner.iconBottom, (v) => { c.bottomCorner.iconBottom = v; }),
        colorRow('Icon Text', null, () => c.bottomCorner.iconText, (v) => { c.bottomCorner.iconText = v; })]));
  },

  folderView() {
    const f = F(), c = C();
    return page(pageHead(sec('folderView'), 'How the bottom screen looks while a folder is open. Switch the preview to Folder to see it.'), Pages.paletteCard(),
      toggleCard('Folder Background', 'square', 'The inner panel shown inside folders.', () => f.folderBackgroundColor, (v) => { f.folderBackgroundColor = v; }, () => [
        colorRow('Panel Color', null, () => c.folderBackground.main, (v) => { c.folderBackground.main = v; }),
        colorRow('Border', null, () => c.folderBackground.border, (v) => { c.folderBackground.border = v; }),
        colorRow('Bottom Highlight', null, () => c.folderBackground.highlight, (v) => { c.folderBackground.highlight = v; }),
        colorAlphaRow('Shadow', null, () => c.folderBackground.glow, (v) => { c.folderBackground.glow = v; })]),
      toggleCard('Folder Back Button', 'undo', 'The button that leaves the folder, and the folder name tab.', () => f.folderArrowColor, (v) => { f.folderArrowColor = v; }, () => [
        colorRow('Button', null, () => c.folderArrow.main, (v) => { c.folderArrow.main = v; }),
        colorRow('Highlight', null, () => c.folderArrow.highlight, (v) => { c.folderArrow.highlight = v; }),
        colorRow('Shading', null, () => c.folderArrow.shading, (v) => { c.folderArrow.shading = v; }),
        colorRow('Glow', null, () => c.folderArrow.glow, (v) => { c.folderArrow.glow = v; }),
        colorAlphaRow('Shadow', null, () => c.folderArrow.shadow, (v) => { c.folderArrow.shadow = v; }),
        colorRow('Arrow', null, () => c.folderArrow.arrowUnpressed, (v) => { c.folderArrow.arrowUnpressed = v; }),
        colorRow('Arrow (Pressed)', null, () => c.folderArrow.arrowPressed, (v) => { c.folderArrow.arrowPressed = v; }),
        colorRow('Arrow Glow', null, () => c.folderArrow.arrowGlow, (v) => { c.folderArrow.arrowGlow = v; })]),
      el('div', {}, btn(App.folderMode ? 'Show Home View in Preview' : 'Show Folder View in Preview', 'eye', () => { App.folderMode = !App.folderMode; App.renderPreviewControls(); App.renderPage(); })));
  },

  text() {
    const f = F(), c = C();
    return page(pageHead(sec('text'), 'Text boxes on the top screen, like the selected software\'s title.'), Pages.paletteCard(),
      card(cardHead('Software Title Box', 'text', 'The box showing the name of the selected software.'),
        segmented([[0, 'Default'], [1, 'Custom Colors'], [2, 'Hidden']], f.gameTextDrawType, (v) => { f.gameTextDrawType = v; App.changed(true); }),
        f.gameTextDrawType === 1 ? el('div', {},
          colorRow('Box', null, () => c.gameText.main, (v) => { c.gameText.main = v; }),
          colorRow('Highlight', null, () => c.gameText.light, (v) => { c.gameText.light = v; }),
          colorAlphaRow('Shadow', null, () => c.gameText.shadow, (v) => { c.gameText.shadow = v; }),
          colorRow('Text', null, () => c.gameText.text, (v) => { c.gameText.text = v; })) : null,
        f.gameTextDrawType === 2 ? el('div', { class: 'muted' }, 'The one-row title box is hidden, leaving your top wallpaper unobstructed.') : null),
      toggleCard('Demo Text', 'text', 'Box used for demo and informational text on the top screen.', () => f.demoTextColor, (v) => { f.demoTextColor = v; }, () => [
        colorRow('Box', null, () => c.demoText.main, (v) => { c.demoText.main = v; }),
        colorRow('Text', null, () => c.demoText.text, (v) => { c.demoText.text = v; })]));
  },

  music() {
    const b = App.bgm, s = b.settings, e = s.edit, f = F();
    const wave = el('div', { class: 'wave' + (b.preview ? ' has' : '') });
    if (b.busy) wave.append(el('div', { style: { display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '8px' } }, el('div', { class: 'progress', id: 'bgmProgress' }, el('div', { style: { width: Math.round(b.progress * 100) + '%' } })), el('span', { class: 'muted' }, 'Converting to 3DS format…')));
    else if (b.preview) wave.append(waveform(b.preview));
    else wave.append(el('div', { class: 'thumb', style: { border: 0, background: 'none' } }, el('div', { class: 'empty' }, svg('wave'), 'Drop an MP3, WAV, M4A, OGG or FLAC here')));
    fileDrop(wave, (p) => App.importMusic(p));
    const choose = async () => { const p = await window.api.openFile('Choose music', AUDIO_FILTERS); if (p) App.importMusic(p); };
    const out = [pageHead(sec('music'), 'Add a song that plays on the HOME Menu. Drop in any MP3, WAV, M4A, OGG or FLAC. MtM3 converts it to the 3DS\'s looping BCSTM format for you.'),
      card(cardHead('Music', 'music', b.sourceName || 'No music added', b.data ? toggleSwitch(f.backgroundMusic, (v) => { f.backgroundMusic = v; App.changed(true); }) : null),
        wave,
        el('div', { class: 'row' }, btn('Choose Audio…', 'open', choose, 'small'),
          b.preview ? btn(Audio3DS.isPlaying() ? 'Stop' : 'Play', Audio3DS.isPlaying() ? 'stop' : 'play', () => { Audio3DS.isPlaying() ? Audio3DS.stop() : Audio3DS.play(b.preview, true); App.renderPage(); }, 'small') : null,
          b.preview ? el('span', { class: 'muted small' }, `${fmtTime(b.preview.channels[0].length / b.preview.sampleRate)} · ${b.preview.sampleRate / 1000} kHz · ${b.preview.channels.length === 1 ? 'Mono' : 'Stereo'}`) : null,
          el('div', { class: 'grow' }), b.data || b.source ? btn('Remove', 'trash', () => App.removeMusic(), 'small danger') : null),
        b.data ? meter('bgm.bcstm size', b.data.length, TK.Limits.maxBGM) : null)];
    if (b.source) {
      const dur = b.source.channels[0].length / b.source.sampleRate;
      const noop = () => {};
      out.push(card(cardHead('Trim & Volume', 'scissors', 'Pick the part of the song you want, then click Apply & Re-convert.'),
        slider('Start at', () => e.startSeconds, (v) => { e.startSeconds = v; }, 0, Math.max(1, dur - 1), 0.5, 0, fmtTime, null, noop),
        slider('Length', () => e.maxSeconds, (v) => { e.maxSeconds = v; }, 0, Math.max(10, dur), 1, 0, (v) => (v ? fmtTime(v) : 'Whole song'), null, noop),
        slider('Loop back to', () => s.loopStart, (v) => { s.loopStart = v; }, 0, Math.max(1, dur - 1), 0.5, 0, (v) => (v ? fmtTime(v) : 'Beginning'), 'Where the song jumps back to when it reaches the end.', noop),
        el('label', { class: 'row' }, toggleSwitch(e.normalize, (v) => { e.normalize = v; }), 'Normalize volume (as loud as possible without distortion)'),
        slider('Volume', () => e.gainDB, (v) => { e.gainDB = v; }, -12, 12, 0.5, 0, (v) => (v >= 0 ? '+' : '') + v.toFixed(1) + ' dB', null, noop),
        slider('Fade in', () => e.fadeInSeconds, (v) => { e.fadeInSeconds = v; }, 0, 10, 0.5, 0, (v) => (v ? v.toFixed(1) + ' s' : 'Off'), null, noop),
        slider('Fade out', () => e.fadeOutSeconds, (v) => { e.fadeOutSeconds = v; }, 0, 10, 0.5, 0, (v) => (v ? v.toFixed(1) + ' s' : 'Off'), 'Makes songs that don\'t loop cleanly sound smoother when they restart.', noop),
        el('label', { class: 'row' }, toggleSwitch(e.trimSilence, (v) => { e.trimSilence = v; }), 'Remove silence at the start and end')));
      const maxS = TK.AudioProcess.maxSeconds(s.rate, s.mono ? 1 : 2);
      out.push(card(cardHead('Quality', 'sliders', 'Lower quality fits a longer song into the 3DS\'s 3.3 MB music limit.'),
        segmented([[22050, '22 kHz (longest)'], [32000, '32 kHz (recommended)'], [44100, '44 kHz (best)']], s.rate, (v) => { s.rate = v; App.renderPage(); }),
        segmented([[false, 'Stereo'], [true, 'Mono (twice as long)']], s.mono, (v) => { s.mono = v; App.renderPage(); }),
        el('div', { class: 'small', style: { color: App.editedMusicSeconds() > maxS ? 'var(--warn)' : 'var(--text2)' } }, `At these settings up to ${fmtTime(maxS)} fits; your selection is ${fmtTime(App.editedMusicSeconds())}. Anything longer is trimmed automatically. The loop point snaps to the nearest 0.45 s block for a seamless loop.`),
        el('div', { class: 'row' }, btn('Reset', null, () => { b.settings = { rate: 32000, mono: false, loopStart: 0, edit: TK.AudioProcess.defaultEdit() }; App.renderPage(); }, 'small ghost'), el('div', { class: 'grow' }),
          btn('Apply & Re-convert', 'convert', () => App.applyMusicSettings(), 'primary'))));
    }
    out.push(banner('Already have a .bcstm (for example from LoopingAudioConverter)? Drop it in and it\'s used as-is.'));
    return page(...out);
  },

  sounds() {
    const f = F();
    const rows = TK.SFXBlock.slots.map((slot, i) => {
      const d = App.sfx[i];
      const row = el('div', { class: 'sfx-row' + (d ? ' has' : '') },
        el('div', { class: 'ic', html: icon(['cursor', 'play', 'folder', 'folder', 'arrows', 'arrows', 'arrows', 'sun'][i]) }),
        el('div', { class: 'grow' }, el('b', { style: { fontWeight: 600 } }, slot.title), el('div', { class: 'muted small' }, d ? `${App.sfxNames[i] || 'Custom sound'} · ${fmtBytes(d.length)}` : slot.detail)),
        d ? btn('Play', 'play', () => Audio3DS.play(TK.BCWAV.decode(d), false), 'icon small ghost') : null,
        d ? btn('Remove', 'close', () => App.clearSound(i), 'icon small ghost') : null,
        btn('Choose…', null, async () => { const p = await window.api.openFile(`Choose a sound for ${slot.title}`, SFX_FILTERS); if (p) App.importSound(p, i); }, 'small'));
      fileDrop(row, (p) => App.importSound(p, i));
      return row;
    });
    return page(pageHead(sec('sounds'), 'Replace the HOME Menu\'s sound effects. Drop any short MP3/WAV/OGG onto a slot. It\'s trimmed, leveled and converted to BCWAV automatically.'),
      card(cardHead('Custom Sound Effects', 'speaker', null, toggleSwitch(f.soundEffects, (v) => { if (TK.SFXBlock.isEmpty(App.sfx)) return App.renderPage(); f.soundEffects = v; App.changed(true); })),
        meter('Sound effects size', TK.SFXBlock.isEmpty(App.sfx) ? 0 : TK.SFXBlock.estimatedSize(App.sfx), TK.Limits.maxSoundEffects)),
      card(...rows),
      banner('Custom sound effects are experimental on some theme managers. Keep them short: all eight together must fit in about 187 KB.', 'warn', true));
  },

  converter() { return Converter.page(); },

  export() {
    const v = App.lastValidation;
    const checks = card(cardHead('Checklist', 'check', 'Make sure everything fits the 3DS\'s limits before you share.'));
    if (!v) { checks.append(el('div', { class: 'row muted' }, el('div', { class: 'spinner' }), 'Checking…')); }
    else {
      checks.append(meter('body_LZ.bin', v.bodySize, TK.Limits.maxCompressedBody));
      if (F().backgroundMusic && App.bgm.data) checks.append(meter('bgm.bcstm', v.bgmSize, TK.Limits.maxBGM));
      v.errors.forEach((m) => checks.append(el('div', { class: 'check e' }, svg('x'), m)));
      v.warnings.forEach((m) => checks.append(el('div', { class: 'check w' }, svg('warn'), m)));
      if (!v.errors.length && !v.warnings.length) checks.append(el('div', { class: 'check ok' }, svg('check'), 'Everything looks good and fits within the limits.'));
    }
    const file = (name, detail, yes) => el('div', { class: 'f ' + (yes ? 'yes' : 'no') }, svg(yes ? 'check' : 'circleSlash'), el('code', {}, name), el('span', { class: 'muted small' }, detail));
    checks.append(el('div', { class: 'files' },
      file('body_LZ.bin', 'Theme graphics, colors' + (F().soundEffects ? ' & sound effects' : ''), true),
      file('info.smdh', 'Name, description, author & icon', true),
      file('preview.png', '412 × 480 screenshot of both screens', true),
      file('bgm.bcstm', 'Background music', F().backgroundMusic && !!App.bgm.data)));
    const key = (App.changeCount || 0) + '|' + App.name + '|' + (App.bgm.data ? App.bgm.data.length : 0);
    if (!App.validating && App.validatedKey !== key) {
      App.validating = true; App.validatedKey = key;
      setTimeout(async () => {
        try { App.lastValidation = (await App.buildPackage()).validation; } catch (e) { /* ignore */ }
        App.validating = false;
        if (App.section === 'export') App.renderPage();
      }, 50);
    }
    const ipInput = el('input', { type: 'text', placeholder: '3DS IP address, e.g. 192.168.1.42', style: { maxWidth: '260px' } });
    ipInput.value = localStorage.getItem('chmmIP') || '';
    const sendResult = el('div', { class: 'muted small' });
    const send = async () => {
      const ip = ipInput.value.trim(); if (!ip) return; localStorage.setItem('chmmIP', ip);
      Busy.show('Sending to your 3DS…', true);
      try {
        const { pkg, body } = await App.buildPackage();
        const zip = TK.Zip.write(TK.packageFiles(pkg, body).map((f) => ({ name: TK.safeName(App.name) + '/' + f.name, data: f.data })));
        const r = await window.api.sendTheme(ip, zip);
        sendResult.textContent = r.ok ? 'Sent! Your theme should appear in CHMM2.' : r.error;
      } catch (e) { sendResult.textContent = e.message; }
      Busy.hide();
    };
    return page(pageHead(sec('export'), 'Save your theme in the format ThemePlaza, Anemone3DS and other theme managers use: body_LZ.bin, info.smdh, preview.png and bgm.bcstm.'),
      checks,
      card(cardHead('Save', 'export'),
        el('div', { class: 'big-actions' },
          el('button', { class: 'big', onclick: () => App.exportFolder() }, svg('folderPlus'), el('div', {}, el('b', {}, 'Export Folder'), el('small', {}, 'For your SD card\'s /Themes folder'))),
          el('button', { class: 'big', onclick: () => App.exportZip() }, svg('zip'), el('div', {}, el('b', {}, 'Export ZIP'), el('small', {}, 'Upload to ThemePlaza or share')))),
        el('div', { class: 'row wrap' }, btn('Save Preview Image…', 'image', () => App.savePreview(), 'small'), btn('Export Colors…', 'palette', () => App.exportPreset(), 'small'), btn('Import Colors…', 'open', () => App.importPreset(), 'small'))),
      card(cardHead('Upload to ThemePlaza', 'globe', 'themeplaza.art hosts community themes that install by QR code.'),
        el('div', { class: 'steps' }, ...['Export your theme (folder or ZIP) with the buttons above.', 'Sign in at themeplaza.art and choose Upload → Theme.', 'Attach body_LZ.bin, preview.png and (if you added music) bgm.bcstm from the exported folder. Fill in the name and description.', 'After approval, anyone can scan its QR code with Anemone3DS or the Theme Plaza app to install it.'].map((t, i) => el('div', { class: 'step' }, el('i', {}, i + 1), el('div', {}, t)))),
        el('div', {}, btn('Open ThemePlaza', 'link', () => window.api.openExternal('https://themeplaza.art/themes'), 'small'))),
      card(cardHead('Install Directly', 'sd', 'Copy the exported folder or ZIP into /Themes on your SD card, then apply it with Anemone3DS.'),
        el('div', { class: 'divider' }),
        cardHead('Send to 3DS over Wi-Fi', 'wifi', 'Open CHMM2 on your 3DS, choose to receive a theme, and type the IP address it shows.'),
        el('div', { class: 'row' }, ipInput, btn('Send', 'wifi', send, 'primary')), sendResult));
  },
};

function waveform(pcm) {
  const c = document.createElement('canvas'); c.width = 1400; c.height = 180;
  requestAnimationFrame(() => {
    const ctx = c.getContext('2d'), ch = pcm.channels[0], W = c.width, H = c.height, bins = W / 3, per = Math.max(1, Math.floor(ch.length / bins));
    const g = ctx.createLinearGradient(0, 0, W, 0); g.addColorStop(0, '#5b7cff'); g.addColorStop(1, '#7ab6ff'); ctx.fillStyle = g;
    for (let b = 0; b < bins; b++) {
      let peak = 0; const st = b * per; for (let i = st; i < Math.min(ch.length, st + per); i += Math.max(1, per >> 6)) peak = Math.max(peak, Math.abs(ch[i]));
      const h = peak / 32768 * H / 2; ctx.fillRect(b * 3, H / 2 - h, 2, Math.max(1, h * 2));
    }
    if (pcm.looping && pcm.loopStart > 0) { const x = pcm.loopStart / ch.length * W; ctx.strokeStyle = '#ffb547'; ctx.setLineDash([6, 4]); ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, H); ctx.stroke(); ctx.fillStyle = '#ffb547'; ctx.font = 'bold 22px Segoe UI, sans-serif'; ctx.fillText('Loop', x + 6, 24); }
  });
  return c;
}
