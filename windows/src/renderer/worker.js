// Background worker: heavy encoding (BCSTM, BCWAV, LZ11 body) off the UI thread.
importScripts('../engine/themekit.js');
self.onmessage = (e) => {
  const { id, cmd, payload } = e.data;
  try {
    let result;
    if (cmd === 'bcstm') result = TK.BCSTM.encode(payload, (p) => self.postMessage({ id, progress: p }));
    else if (cmd === 'bcwav') result = TK.BCWAV.encode(payload);
    else if (cmd === 'body') result = TK.Theme.writeCompressedBody(payload);
    else throw new Error('Unknown command ' + cmd);
    self.postMessage({ id, result }, [result.buffer]);
  } catch (err) {
    self.postMessage({ id, error: err.message || String(err) });
  }
};
