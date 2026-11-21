// Starts the app. In demo mode (used to make the README screenshots) it builds a sample theme
// from the files in <demo>/assets and captures each feature.
(async () => {
  await App.init();
  const demo = new URLSearchParams(location.search).get('demo');
  if (!demo) return;
  const A = (n) => window.api.join(demo, 'assets', n);
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const shot = async (name, ms = 900) => { await wait(ms); await window.api.capture(name); };
  try {
    App.name = 'Night Ride'; App.description = 'An evening bike ride past the city lights, with a snowy coastline below and a chiptune loop.'; App.author = 'Meer';
    const topPic = await Imaging.loadPath(A('top_custom.jpg'));
    App.theme.flags.topFrameType = 1;
    await App.setPicture('top', topPic, 'night-ride.jpg');
    App.sources.top.edit.offsetY = -34; App.renderSlot('top', true);
    App.theme.flags.bottomFrameType = 1; await App.setPicture('bottom', await Imaging.loadPath(A('bottom_custom.gif')), 'snowy-coast.gif');
    { const c = document.createElement('canvas'); c.width = 180; c.height = 180; c.getContext('2d').drawImage(topPic, -80, -300, topPic.width, topPic.height); App.setIcon(c); }
    await App.setPicture('folderClosed', await Imaging.loadPath(A('folder_closed.png')), 'folder_closed.png');
    await App.setPicture('folderOpen', await Imaging.loadPath(A('folder_open.png')), 'folder_open.png');
    const f = App.theme.flags, c = App.theme.colors;
    Object.assign(f, { cursorColor: true, folderColor: true, arrowButtonColor: true, arrowColor: true, openCloseColor: true, topCornerColor: true, bottomCornerColor: true, folderBackgroundColor: true, folderArrowColor: true, gameTextDrawType: 1, fileColor: true });
    // Night-blue interface with pink accents (the scarf) and warm lamp yellow.
    Object.assign(c.cursor, { main: [255, 92, 150], light: [255, 180, 210], shading: [170, 40, 100], glow: [255, 120, 170] });
    Object.assign(c.folder, { main: [236, 196, 92], light: [255, 232, 160], shading: [170, 120, 40], shadow: [40, 40, 90] });
    Object.assign(c.file, { main: [64, 78, 150], light: [120, 136, 210], shading: [34, 42, 96], shadow: [0, 0, 0, 90] });
    Object.assign(c.arrowButton, { main: [46, 58, 120], light: [104, 120, 196], shading: [24, 30, 70], shadow: [0, 0, 0, 120] });
    Object.assign(c.arrow, { unpressed: [255, 150, 190], pressed: [255, 230, 120], border: [255, 255, 255] });
    for (const o of [c.open, c.close]) Object.assign(o, { unpressed: [255, 92, 150], pressed: [190, 50, 110], light: [255, 180, 210], glow: [255, 210, 230], textUnpressed: [255, 255, 255], textPressed: [255, 240, 248], textShadow: [130, 20, 70] });
    Object.assign(c.topCorner, { main: [46, 58, 120], light: [104, 120, 196], text: [255, 214, 120] });
    Object.assign(c.bottomCorner, { main: [46, 58, 120], highlight: [104, 120, 196], border: [255, 150, 190], iconTop: [255, 230, 150], iconBottom: [236, 180, 70] });
    Object.assign(c.gameText, { main: [36, 46, 104], light: [96, 110, 190], shadow: [0, 0, 0, 140], text: [255, 222, 140] });
    Object.assign(c.folderBackground, { main: [40, 50, 112], border: [255, 150, 190], highlight: [120, 136, 210], glow: [20, 20, 60, 220] });
    Object.assign(c.folderArrow, { main: [255, 92, 150], highlight: [255, 180, 210], shading: [170, 40, 100], arrowUnpressed: [255, 255, 255] });
    App.changed(true);

    App.go('top'); await shot('01-top-screen', 1600);
    App.sources.top.edit.saturation = 1.2; App.sources.top.edit.contrast = 1.08;
    Editor.open('top', 'Top Wallpaper'); await shot('02-image-editor', 1400); Editor.close(true);
    Editor.open('folderClosed', 'Closed'); await shot('02b-image-editor-small', 1000); Editor.close(true);
    App.go('bottom'); await shot('03-bottom-screen');
    App.go('icons'); await shot('04-icons-and-cursor');
    App.go('buttons'); await shot('05-buttons-and-arrows');
    App.folderMode = true; App.renderPreviewControls(); App.go('folderView'); await shot('06-folder-view', 1300);
    App.folderMode = false; App.renderPreviewControls();
    App.go('text'); await shot('07-text-boxes');

    App.go('music');
    App.bgm.settings.edit.fadeOutSeconds = 2;
    App.bgm.settings.loopStart = 4;
    await App.importMusic(A('song.wav'));
    while (App.bgm.busy) await wait(200);
    App.go('music'); await shot('08-background-music');
    for (const [i, n] of [[0, 'cursor.wav'], [1, 'launch.wav'], [2, 'folder_open.wav'], [3, 'folder_close.wav']]) await App.importSound(A(n), i);
    App.go('sounds'); await shot('09-sound-effects');
    Converter.s.music = A('song.wav'); Converter.s.image = A('top_custom.jpg'); Converter.s.imageCanvas = topPic; Converter.s.target = 'topStill'; Converter.s.sfx = A('cursor.wav');
    App.go('converter'); await shot('10-converter-tools');
    App.go('info'); await shot('11-theme-info');
    App.go('export'); await wait(4000); await shot('12-export', 600);

    // Write a real exported theme + preview.png for verification
    const out = window.api.join(demo, 'export', 'Night Ride'); window.api.mkdir(out);
    const { pkg, body } = await App.buildPackage();
    for (const fl of TK.packageFiles(pkg, body)) window.api.writeFile(window.api.join(out, fl.name), fl.data);
    window.api.writeFile(window.api.join(demo, 'shots', 'preview.png'), pkg.preview);
  } catch (e) {
    window.api.writeFile(window.api.join(demo, 'error.txt'), new TextEncoder().encode(String(e && e.stack || e)));
  }
  await window.api.demoDone();
})();
