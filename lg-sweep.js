// Conservative resident-bloat sweep. Closes only non-essential apps; never core UI.
// Nothing is uninstalled — every app relaunches normally when opened.
const lgtv2 = require('lgtv2');
const path = require('path');

const KEY_FILE = process.env.KEY_FILE || path.join(__dirname, '.lg-client-key.json');
const TV_URL = process.argv[2] || process.env.TV_URL;

if (!TV_URL || TV_URL === 'help' || TV_URL === '--help') {
  console.log('Usage: node lg-sweep.js ws://<TV_IP>:3000');
  console.log('Closes non-essential background resident apps to immediately free RAM.');
  process.exit(1);
}

// RAM-heavy / ad / promo / demo apps. Safe to close: they relaunch if ever needed.
const SWEEP_LIST = [
  'com.webos.app.homeconnect',     // Home Dashboard
  'com.webos.app.discovery',       // LG Content Store
  'com.webos.app.dangbei-card',    // Region ad overlay
  'com.webos.app.dangbei-overlay',
  'com.webos.app.brandshop',
  'webos.day',                     // LG Streaming Week promo
  'lgchannels.home',               // LG Channels
  'com.webos.app.beanbrowser',     // Hidden webview
  'com.webos.app.magicnum',
  'com.webos.app.tips',            // Magic Link
  'com.webos.app.adapp',           // Advertisement
  'com.webos.app.cmp-client',      // CMP App
  'com.webos.app.crb',
  'com.webos.app.membership',
  'com.webos.app.customersupport',
  'com.webos.app.store-demo',
  'com.webos.app.sync-demo',
  'com.webos.app.remoteservice',
  'com.webos.app.livecudb',
  'com.webos.app.livepick'
];

// Never close these core apps:
const PROTECTED = [
  'com.webos.app.home', 'com.palm.app.settings', 'com.webos.app.settings',
  'com.webos.app.livetv', 'com.webos.app.livemenu', 'com.webos.app.tvhotkey',
  'com.webos.app.webapphost', 'com.webos.app.eula', 'com.palm.app.firstuse',
  'com.webos.app.inputcommon', 'com.webos.app.notificationcenter',
  'com.webos.app.screensaver', 'netflix', 'youtube.leanback.v4', 'hotstar',
  'com.zee5.app', 'com.sonyliv2.tvapp', 'com.apple.appletv', 'com.apple.applemusic',
  'airplay'
];
const PROTECT_SUBSTR = ['externalinput', 'hdmi', 'acroverlay'];

const tv = lgtv2({ url: TV_URL, keyFile: KEY_FILE, timeout: 6000, reconnect: 0, debug: false });
const req = (uri, payload) => new Promise((res) =>
  tv.request(uri, payload || {}, (e, r) => res(e ? { __error: String(e && e.message ? e.message : e) } : r)));

tv.on('connect', async () => {
  try {
    // Focus standard Home app first so we never close a foreground UI
    await req('ssap://system.launcher/open', { id: 'com.webos.app.home' });
    await new Promise((res) => setTimeout(res, 3000));
    const fg = await req('ssap://com.webos.applicationManager/getForegroundAppInfo');
    console.log('Foreground app: ' + (fg && fg.appId));

    let closed = 0, skipped = 0, errors = 0;
    for (const id of SWEEP_LIST) {
      if (PROTECTED.includes(id) || PROTECT_SUBSTR.some((s) => id.includes(s))) {
        console.log(`skip(protected) ${id}`);
        continue;
      }
      if (fg && fg.appId === id) {
        console.log(`skip(foreground) ${id}`);
        continue;
      }
      let r = await req('ssap://system.launcher/close', { id });
      if (r && r.__error) r = await req('ssap://com.webos.service.applicationmanager/close', { id });
      if (r && r.__error) {
        console.log(`error ${id}: ${r.__error}`);
        errors++;
      } else {
        console.log(`${r && r.returnValue !== false ? 'closed ' : 'failed '} ${id}`);
        if (r && r.returnValue !== false) closed++; else skipped++;
      }
    }
    console.log(`SWEEP_DONE: closed=${closed} skipped=${skipped} errors=${errors}`);
    await req('ssap://system.notifications/createToast', { message: 'RAM cleanup done — nothing was uninstalled' });
  } catch (e) {
    console.log('Sweep error:', e);
  }
  tv.disconnect();
  setTimeout(() => process.exit(0), 300);
});
tv.on('error', (e) => { console.log('ERROR:', e && e.message ? e.message : e); process.exit(1); });
tv.connect();
setTimeout(() => { console.log('TIMEOUT'); process.exit(2); }, 120000);
