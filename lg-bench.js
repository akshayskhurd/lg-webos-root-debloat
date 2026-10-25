// Launch-app timing benchmark over the LG ws API.
// Usage: node lg-bench.js ws://<TV_IP>:3000 [app1,app2,...]
const lgtv2 = require('lgtv2');
const path = require('path');

const KEY_FILE = process.env.KEY_FILE || path.join(__dirname, '.lg-client-key.json');
const TV_URL = process.argv[2] || process.env.TV_URL;

if (!TV_URL || TV_URL === 'help' || TV_URL === '--help') {
  console.log('Usage: node lg-bench.js ws://<TV_IP>:3000 [app1,app2,...]');
  console.log('Example: node lg-bench.js ws://192.168.1.50:3000 netflix,youtube.leanback.v4');
  process.exit(1);
}

const APPS = (process.argv[3] || 'netflix,youtube.leanback.v4').split(',');

const tv = lgtv2({ url: TV_URL, keyFile: KEY_FILE, timeout: 6000, reconnect: 0, debug: false });
const req = (uri, payload) => new Promise((res) =>
  tv.request(uri, payload || {}, (e, r) => res(e ? { __error: String(e && e.message ? e.message : e) } : r)));

async function waitForeground(id, timeoutMs) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    const r = await req('ssap://com.webos.applicationManager/getForegroundAppInfo');
    if (r && r.appId === id) return (Date.now() - t0) / 1000;
    await new Promise((res2) => setTimeout(res2, 250));
  }
  return -1;
}

tv.on('connect', async () => {
  try {
    for (const app of APPS) {
      const t0 = Date.now();
      const lr = await req('ssap://system.launcher/open', { id: app });
      if (lr && lr.__error) { console.log(`LAUNCH ${app}: REQUEST ERROR ${lr.__error}`); continue; }
      const secs = await waitForeground(app, 120000);
      console.log(`LAUNCH ${app}: ${secs < 0 ? 'TIMEOUT (not foreground in 120s)' : secs.toFixed(1) + 's'}`);
      await new Promise((res2) => setTimeout(res2, 2000));
    }
    console.log('BENCH_DONE');
  } catch (e) {
    console.log('Benchmarking error:', e);
  }
  tv.disconnect();
  setTimeout(() => process.exit(0), 300);
});
tv.on('error', (e) => { console.log('ERROR:', e && e.message ? e.message : e); process.exit(1); });
tv.connect();
setTimeout(() => { console.log('TIMEOUT'); process.exit(2); }, Math.min(600000, 30000 + APPS.length * 150000));
