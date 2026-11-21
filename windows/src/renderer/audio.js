// Audio import (any format Chromium can decode: MP3, WAV, M4A/AAC, OGG, FLAC, WebM…), playback and background encoding.
const Audio3DS = (() => {
  const worker = new Worker('worker.js');
  let nextId = 1;
  const pending = new Map();
  worker.onmessage = (e) => {
    const { id, result, error, progress } = e.data, p = pending.get(id);
    if (!p) return;
    if (progress !== undefined) { p.onProgress && p.onProgress(progress); return; }
    pending.delete(id);
    error ? p.reject(new Error(error)) : p.resolve(result);
  };
  function run(cmd, payload, onProgress) {
    return new Promise((resolve, reject) => { const id = nextId++; pending.set(id, { resolve, reject, onProgress }); worker.postMessage({ id, cmd, payload }); });
  }

  /** Decodes an audio file to 16-bit PCM at `rate` with `channels` channels. */
  async function load(path, rate, channels, maxSeconds = 900) {
    const bytes = window.api.readFile(path);
    const ctx = new OfflineAudioContext(2, 1, rate);
    let buf;
    try { buf = await ctx.decodeAudioData(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)); }
    catch (e) { throw new Error(`“${window.api.basename(path)}” isn't an audio format MtM3 can read. Try MP3, WAV, M4A, OGG or FLAC.`); }
    const n = Math.min(buf.length, Math.floor(maxSeconds * rate));
    const src = []; for (let c = 0; c < buf.numberOfChannels; c++) src.push(buf.getChannelData(c));
    const out = [];
    for (let c = 0; c < channels; c++) {
      const ch = new Int16Array(n);
      for (let i = 0; i < n; i++) {
        let v;
        if (channels === 1) { v = 0; for (const s of src) v += s[i]; v /= src.length; }
        else v = src[Math.min(c, src.length - 1)][i];
        ch[i] = Math.max(-32768, Math.min(32767, Math.round(v * 32767)));
      }
      out.push(ch);
    }
    return { sampleRate: rate, channels: out, looping: false, loopStart: 0 };
  }

  // Playback
  let actx = null, source = null;
  function play(pcm, loop) {
    stop();
    if (!pcm || !pcm.channels.length || !pcm.channels[0].length) return;
    actx = actx || new AudioContext();
    const b = actx.createBuffer(pcm.channels.length, pcm.channels[0].length, pcm.sampleRate);
    pcm.channels.forEach((ch, c) => { const d = b.getChannelData(c); for (let i = 0; i < ch.length; i++) d[i] = ch[i] / 32768; });
    source = actx.createBufferSource(); source.buffer = b;
    if (loop) { source.loop = true; source.loopStart = pcm.looping ? pcm.loopStart / pcm.sampleRate : 0; source.loopEnd = b.duration; }
    source.connect(actx.destination); source.start();
  }
  function stop() { if (source) { try { source.stop(); } catch (e) { /* already stopped */ } source = null; } }
  const isPlaying = () => !!source;

  function decodeNintendo(bytes) {
    if (bytes[0] === 0x43 && bytes[1] === 0x57) return TK.BCWAV.decode(bytes);   // "CW"
    return TK.BCSTM.decode(bytes);
  }

  /** Trims, applies edits, fits to the 3DS limit and sets the loop point. */
  function prepareMusic(pcm, edit, loopStartSeconds, rate, channels) {
    let a = TK.AudioProcess.apply(pcm, edit);
    const maxSamples = Math.floor(TK.AudioProcess.maxSeconds(rate, channels) * rate);
    let trimmed = false;
    if (a.channels[0].length > maxSamples) { a.channels = a.channels.map((c) => c.slice(0, maxSamples)); trimmed = true; }
    a.looping = true;
    a.loopStart = Math.min(Math.floor(loopStartSeconds * rate), Math.max(0, a.channels[0].length - 14336));
    return { audio: a, trimmed };
  }

  return { load, play, stop, isPlaying, decodeNintendo, prepareMusic,
    encodeBCSTM: (a, onProgress) => run('bcstm', a, onProgress),
    encodeBCWAV: (a) => run('bcwav', a),
    compressBody: (t) => run('body', t) };
})();
