// Cross-checks the JS engine against reference vectors (Python port of the Swift engine)
// and runs round-trip tests. Usage: node test/engine-test.js [vectorDir]
const fs = require('fs'), path = require('path');
const TK = require('../src/engine/themekit.js');
const V = process.argv[2] || path.join(__dirname, 'vectors');
let fails = 0;
const check = (name, ok) => { console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}`); if (!ok) fails++; };
const eq = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
const rd = (f) => new Uint8Array(fs.readFileSync(path.join(V, f)));
const i16 = (f) => { const b = fs.readFileSync(path.join(V, f)); return new Int16Array(b.buffer, b.byteOffset, b.length / 2).slice(); };

// LZ11
const lzin = rd('lzin.bin');
check('LZ11 compress matches reference', eq(TK.LZ11.compress(lzin), rd('lzout.bin')));
check('LZ11 round trip', eq(TK.LZ11.decompress(TK.LZ11.compress(lzin)), lzin));

// DSP-ADPCM
const L = i16('L.bin'), R = i16('R.bin');
const coefs = TK.DSP.calculateCoefficients(L);
check('DSP coefficients match reference', eq(Array.from(coefs), JSON.parse(fs.readFileSync(path.join(V, 'coefsL.json')))));
check('DSP encode matches reference', eq(TK.DSP.encode(L, coefs), rd('adpcmL.bin')));

// BCSTM
for (const [name, ls] of [['loop0', 0], ['aligned', 14336], ['unaligned', 20000]]) {
  const out = TK.BCSTM.encode({ sampleRate: 32000, channels: [L, R], looping: true, loopStart: ls });
  check(`BCSTM ${name} byte-identical`, eq(out, rd(`${name}.bcstm`)));
  const back = TK.BCSTM.decode(out);
  check(`BCSTM ${name} decodes (${back.channels[0].length} samples, loop ${back.loopStart})`, back.channels.length === 2 && back.looping);
}
// BCWAV
const wv = TK.BCWAV.encode({ sampleRate: 16000, channels: [L.slice(0, 8000)] });
check('BCWAV byte-identical', eq(wv, rd('mono.bcwav')));
check('BCWAV decodes', TK.BCWAV.decode(wv).channels[0].length === 8000);

// Theme body
function grad(w, h) { const img = TK.makeImage(w, h); for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const i = (y * w + x) * 3; img.pixels[i] = Math.floor(x * 255 / Math.max(1, w - 1)); img.pixels[i + 1] = Math.floor(y * 255 / Math.max(1, h - 1)); img.pixels[i + 2] = (x ^ y) & 0xFF; } return img; }
const t = TK.Theme.create();
Object.assign(t.flags, { backgroundMusic: true, topDrawType: 3, topFrameType: 3, bottomDrawType: 3, bottomFrameType: 4, cursorColor: true, folderColor: true, folderTexture: true, fileColor: true, fileTexture: true, arrowButtonColor: true, arrowColor: true, openCloseColor: true, gameTextDrawType: 1, bottomInnerColor: true, bottomOuterColor: true, folderBackgroundColor: true, folderArrowColor: true, bottomCornerColor: true, topCornerColor: true, demoTextColor: true, soundEffects: true });
t.colors.cursor.shading = [1, 2, 3]; t.colors.topCorner.text = [200, 100, 50];
t.textures = { top: grad(1024, 256), bottom: grad(1024, 256), folderClosed: grad(128, 64), folderOpen: grad(128, 64), fileLarge: grad(64, 128), fileSmall: grad(32, 64) };
const sounds = new Array(8).fill(null);
sounds[0] = TK.BCWAV.encode({ sampleRate: 16000, channels: [L.slice(0, 4000)] });
sounds[4] = TK.BCWAV.encode({ sampleRate: 16000, channels: [R.slice(0, 3000)] });
t.soundEffectData = TK.SFXBlock.encode(sounds);
const body = TK.Theme.writeBody(t);
check('Theme body byte-identical to reference', eq(body, rd('body.bin')));
const lz = TK.Theme.writeCompressedBody(t);
const back = TK.Theme.read(lz);
check('Theme read-back flags', JSON.stringify(back.flags) === JSON.stringify(t.flags));
check('Theme read-back colors', JSON.stringify(back.colors.cursor) === JSON.stringify(t.colors.cursor) && back.colors.open.textShadowPosition === -1.25);
check('Theme read-back textures', eq(back.textures.folderClosed.pixels, t.textures.folderClosed.pixels));
check('SFX block round trip', TK.SFXBlock.decode(back.soundEffectData)[4].length === sounds[4].length);
console.log(`body_LZ.bin: ${lz.length} bytes (limit ${TK.Limits.maxCompressedBody})`);

// SMDH
const s = TK.SMDH.create(); TK.SMDH.setAll(s, 'Test Theme', 'Description', 'Meer');
const sb = TK.SMDH.write(s);
check('SMDH size 0x36C0', sb.length === 0x36C0);
check('SMDH round trip', TK.SMDH.primary(TK.SMDH.read(sb)).short === 'Test Theme');

// ZIP
const zipped = TK.Zip.write([{ name: 'a.txt', data: new TextEncoder().encode('hello') }, { name: 'b/c.bin', data: lz }]);
const unz = TK.Zip.read(zipped, () => { throw new Error('no deflate'); });
check('ZIP round trip', unz.length === 2 && eq(unz[1].data, lz));

// Audio edit
const edited = TK.AudioProcess.apply({ sampleRate: 32000, channels: [L] }, { ...TK.AudioProcess.defaultEdit(), startSeconds: 0.1, maxSeconds: 0.5, fadeOutSeconds: 0.1 });
check('Audio edit trims to 0.5 s', edited.channels[0].length === 16000);

console.log(fails ? `\n${fails} FAILED` : '\nAll engine checks passed');
process.exit(fails ? 1 : 0);
