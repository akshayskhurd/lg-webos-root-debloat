// Zero-risk LG webOS control link: pair once, capture client key, read out info.
const lgtv2 = require('lgtv2');
const path = require('path');

const KEY_FILE = process.env.KEY_FILE || path.join(__dirname, '.lg-client-key.json');
const TV_URL = process.argv[2] || process.env.TV_URL;

if (!TV_URL || TV_URL === 'help' || TV_URL === '--help') {
  console.log('Usage: node lg-connect.js ws://<TV_IP>:3000 [cmd] [arg]');
  console.log('Or set the TV_URL environment variable.');
  console.log('Commands:');
  console.log('  info              Print system & firmware info (default)');
  console.log('  apps              List all installed apps');
  console.log('  running           Get currently active foreground app');
  console.log('  launch <appId>    Launch an application');
  console.log('  close <appId>     Close an application');
  console.log('  toast <message>   Display a toast notification on the TV');
  console.log('  off               Turn off the TV screen');
  process.exit(1);
}

const CMD = process.argv[3] || 'info';
const ARG = process.argv[4] || '';

const tv = lgtv2({ url: TV_URL, keyFile: KEY_FILE, timeout: 6000, reconnect: 0, debug: false });
const get = (uri, payload) => new Promise((res) =>
  tv.request(uri, payload, (e, r) => res(e ? { __error: String(e && e.message ? e.message : e) } : r)));

tv.on('prompt', () => console.log('PROMPT_ON_TV: A dialog appeared on the TV — select OK / Allow with the remote.'));
tv.on('connecting', () => console.log('Connecting to ' + TV_URL + ' ...'));
tv.on('connect', async () => {
  console.log('CONNECTED & registered.');
  try {
    if (CMD === 'info') {
      const sys = await get('ssap://system/getSystemInfo');
      const sw = await get('ssap://com.webos.service.update/getCurrentSWInformation');
      console.log('\n== SYSTEM ==\n' + JSON.stringify(sys, null, 2));
      console.log('\n== FIRMWARE ==\n' + JSON.stringify(sw, null, 2));
    }
    if (CMD === 'apps') {
      const apps = await get('ssap://com.webos.applicationManager/listApps');
      const list = apps && apps.apps ? apps.apps.map((a) => ({ id: a.id, title: a.title, type: a.type })) : apps;
      console.log('\n== INSTALLED APPS ==\n' + JSON.stringify(list, null, 2));
    }
    if (CMD === 'running') {
      const fg = await get('ssap://com.webos.applicationManager/getForegroundAppInfo', {});
      console.log('\n== FOREGROUND ==\n' + JSON.stringify(fg, null, 2));
    }
    if (CMD === 'close') {
      const id = ARG;
      let r = await get('ssap://system.launcher/close', { id });
      if (r && r.__error) r = await get('ssap://com.webos.service.applicationmanager/close', { id });
      console.log('close ' + id + ' -> ' + JSON.stringify(r));
    }
    if (CMD === 'launch') {
      const r = await get('ssap://system.launcher/open', { id: ARG });
      console.log('launch ' + ARG + ' -> ' + JSON.stringify(r));
    }
    if (CMD === 'toast') {
      const r = await get('ssap://system.notifications/createToast', { message: ARG || 'Hello from LG control!' });
      console.log('toast -> ' + JSON.stringify(r));
    }
    if (CMD === 'off') {
      console.log('off -> ' + JSON.stringify(await get('ssap://system/turnOff', {})));
    }
  } catch (e) {
    console.log('Command execution error:', e);
  }
  tv.disconnect();
  setTimeout(() => process.exit(0), 300);
});
tv.on('error', (e) => {
  console.log('ERROR:', e && e.message ? e.message : e);
  process.exit(1);
});
tv.connect();
setTimeout(() => { console.log('TIMEOUT: no registration within 75s.'); process.exit(2); }, 75000);
