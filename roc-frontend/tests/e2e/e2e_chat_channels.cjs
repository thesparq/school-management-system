// The school's chat channels, in Chromium, against a mock Synapse and a real sandbox database: an
// administrator makes a channel of either kind, and the two kinds behave the way they are told to — a
// public one is listed for everyone to find and join, a private one is listed to administrators only and
// is opened by the code its creator hands out. Also the rules around them: a pupil is not offered a way to
// make a channel, and a code nobody holds opens nothing.
//
//   node tests/e2e/e2e_chat_channels.cjs
//
// Needs the sandbox (see README.md): the channels are rows, so unlike the login suite this one cannot use
// a dead database. It builds the backend, boots it against the sandbox database and the mock homeserver,
// installs the channel table if it is missing, and takes its own rows back out.

const { chromium } = require('playwright');
const { spawn, spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const repo = path.resolve(__dirname, '../../..');
const mockPort = 9011;
const appPort = 8128;
const appUrl = `http://127.0.0.1:${appPort}`;
const surrealUrl = process.env.SURREAL_URL || 'http://127.0.0.1:8002/sql';

const results = [];
const check = (name, ok, extra = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); };
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const tokenFor = (groups, name, email) => `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({
  iss: 'https://auth.johnethel.school/application/o/school-management-system/',
  exp: Math.floor(Date.now() / 1000) + 3600, email, name, groups,
})}.sig`;

const surreal = async (statement) => {
  const res = await fetch(surrealUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'surreal-ns': 'main', 'surreal-db': 'lessons', Accept: 'application/json', Authorization: 'Basic ' + Buffer.from('root:root').toString('base64') },
    body: statement,
  });
  return res.text();
};

(async () => {
  const workdir = fs.mkdtempSync(path.join(os.tmpdir(), 'chat-channels-'));
  const backendBin = path.join(workdir, 'backend');
  const mockLog = path.join(workdir, 'mock.log');
  fs.writeFileSync(mockLog, '');

  // The table the flows are about, and a clean slate for this suite's rooms (the mock names every room it
  // makes `!mockroom…`, which nothing else in the sandbox shares).
  await surreal(fs.readFileSync(path.join(repo, 'db/schema-v16-chat-channels.surql'), 'utf8'));
  await surreal("DELETE chat_channel WHERE room_id CONTAINS 'mockroom';");

  console.log('building the backend (first run is slow)...');
  const build = spawnSync('roc', ['build', 'roc-backend/main.roc', `--output=${backendBin}`], { cwd: repo, stdio: 'inherit' });
  if (build.status !== 0) { console.error('backend build failed'); process.exit(1); }

  const mock = spawn('python3', ['roc-frontend/tests/e2e/fixtures/mock_synapse.py', String(mockPort)], {
    cwd: repo, stdio: ['ignore', 'inherit', 'inherit'], env: { ...process.env, LOG_FILE: mockLog },
  });
  let mockUp = false;
  for (let i = 0; i < 40; i++) {
    try { await fetch(`http://127.0.0.1:${mockPort}/_matrix/client/v3/account/whoami`); mockUp = true; break; } catch { /* not up yet */ }
    await sleep(250);
  }
  check('the mock homeserver is listening', mockUp);

  const backend = spawn(backendBin, [], {
    cwd: path.join(repo, 'roc-backend'),
    stdio: 'ignore',
    env: {
      ...process.env,
      DEV_MODE: 'true',
      BIND_HOST: '127.0.0.1',
      PORT: String(appPort),
      SURREAL_URL: surrealUrl,
      SURREAL_USER: 'root',
      SURREAL_PASS: 'root',
      AUTHENTIK_API_URL: 'http://127.0.0.1:9000/api/v3/core/users/',
      AUTHENTIK_API_TOKEN: 'mock',
      AUTHENTIK_ISSUER_URL: 'http://127.0.0.1:9000/application/o/school/',
      PUBLIC_MATRIX_URL: `http://127.0.0.1:${mockPort}/`,
    },
  });
  const stop = () => { try { backend.kill(); } catch {} try { mock.kill(); } catch {} };
  process.on('exit', stop);
  process.on('SIGINT', () => { stop(); process.exit(130); });

  for (let i = 0; i < 40; i++) {
    try { const r = await fetch(`${appUrl}/health`); if (r.ok) break; } catch {}
    await sleep(500);
  }

  const mockLines = () => fs.readFileSync(mockLog, 'utf8').split('\n').filter(Boolean);
  const browser = await chromium.launch({ channel: 'chromium' });
  const errors = [];
  const consoleNotes = [];

  // One page for a role. `apiToken` is what the app's own backend is asked with: the administrator drives it
  // with the developer token (DEV_MODE), the pupil with the mock's own student token — so the backend really
  // does resolve a pupil, which is what decides whether a private channel is in the directory.
  async function openChat({ token, apiToken, label }) {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
    await ctx.addInitScript(t => localStorage.setItem('auth_token', t), token);
    const page = await ctx.newPage();
    page.on('pageerror', e => errors.push(`${label}: ${e.message.slice(0, 140)}`));
    page.on('console', m => { if (m.type() === 'error') consoleNotes.push(`${label}: ${m.text().slice(0, 200)}`); });
    await page.route('**/api/**', route => route.continue({ headers: { ...route.request().headers(), authorization: `Bearer ${apiToken}` } }));
    await page.goto(`${appUrl}/messaging`, { waitUntil: 'load' });
    await page.waitForTimeout(6500);
    return { ctx, page };
  }

  const sidebarText = (page) => page.evaluate(() => (document.getElementById('matrix-rooms') || {}).innerText || '');
  // The sidebar as a whole, not just the room list: the create form and the directory are siblings of it,
  // both of them inside the same panel. A directory entry shows a channel that has *not* been joined, so
  // "is this channel in the pupil's own list" has to read the list itself.
  const panelText = sidebarText;
  const roomListText = (page) => page.evaluate(() => (document.getElementById('matrix-rooms-list') || {}).innerText || '');
  // Open the join panel, closing it first if it is already open: the panel re-reads the directory when it
  // is shown, which is the difference between "the pupil is not offered that channel" and "the pupil is
  // looking at a list from a minute ago".
  async function openJoinPanel(page) {
    const visible = await page.evaluate(() => {
      const form = document.getElementById('matrix-join-channel-form');
      return !!form && !form.classList.contains('hidden');
    });
    if (visible) { await page.click('#matrix-join-channel-btn'); await page.waitForTimeout(250); }
    await page.click('#matrix-join-channel-btn');
    await page.waitForTimeout(1300);
  }

  const admin = await openChat({ token: tokenFor(['administrators'], 'Samuel Iyeh', 'thesparq@example.com'), apiToken: 'dev-skip', label: 'admin' });
  check('the administrator is connected to the chat', (await sidebarText(admin.page)).includes('Channels'), await sidebarText(admin.page));
  check('and offered a new channel', await admin.page.evaluate(() => !!document.getElementById('matrix-new-channel-btn')));

  // --- A public channel: listed for the school, joined from the list ---
  await admin.page.click('#matrix-new-channel-btn');
  await admin.page.waitForTimeout(300);
  await admin.page.fill('#matrix-new-name', 'Suite Assembly');
  await admin.page.selectOption('#matrix-new-visibility', 'public');
  await admin.page.click('#matrix-new-create');
  await admin.page.waitForTimeout(4000);
  const publicRooms = mockLines().filter(l => l.startsWith('POST /_matrix/client/v3/createRoom'));
  check('the channel is made public', publicRooms.some(l => l.includes('"visibility":"public"')), JSON.stringify(publicRooms.slice(-1)));
  const publicRoomId = (publicRooms[publicRooms.length - 1] || '').match(/"name":"Suite Assembly"/) ? 'true' : 'false';
  check('with the name the administrator typed', publicRoomId === 'true', JSON.stringify(publicRooms.slice(-1)));
  const codePanel = await admin.page.evaluate(() => (document.getElementById('matrix-rooms') || {}).innerText.match(/[A-Z0-9]{6}/g) || []);
  check('a code comes back to hand out', codePanel.length > 0, JSON.stringify(codePanel));

  // --- The pupil sees the public channel and can join it ---
  const pupil = await openChat({ token: tokenFor(['students'], 'Ada Pupil', 'pupil@example.com'), apiToken: 'mock-student-token', label: 'pupil' });
  await openJoinPanel(pupil.page);
  check('the pupil\u2019s directory lists the public channel', (await panelText(pupil.page)).includes('Suite Assembly'),
    JSON.stringify({ panel: await panelText(pupil.page), console: consoleNotes }));
  await pupil.page.click('#matrix-join-results button[data-join]');
  await pupil.page.waitForTimeout(2500);
  check('joining it is a real join', mockLines().some(l => l.startsWith('POST /_matrix/client/v3/rooms/') && l.includes('/join')),
    JSON.stringify(mockLines().filter(l => l.includes('/rooms/'))));
  check('and the channel is then in the pupil\u2019s own list', (await roomListText(pupil.page)).includes('Suite Assembly'), await roomListText(pupil.page));

  // --- A private channel: not listed for the pupil, opened by its code ---
  await admin.page.click('#matrix-new-channel-btn');
  await admin.page.waitForTimeout(300);
  await admin.page.fill('#matrix-new-name', 'Suite Staff Room');
  await admin.page.selectOption('#matrix-new-visibility', 'private');
  await admin.page.click('#matrix-new-create');
  await admin.page.waitForTimeout(4000);
  const privateRooms = mockLines().filter(l => l.startsWith('POST /_matrix/client/v3/createRoom') && l.includes('Suite Staff Room'));
  check('the private channel is made unlisted', privateRooms.some(l => l.includes('"visibility":"private"')), JSON.stringify(privateRooms.slice(-1)));
  const privateCode = (await admin.page.evaluate(() => {
    const box = [...document.querySelectorAll('#matrix-rooms > div')].find(el => el.innerText.includes('Suite Staff Room') && el.innerText.match(/[A-Z0-9]{6}/));
    const match = box ? box.innerText.match(/[A-Z0-9]{6}/) : null;
    return match ? match[0] : '';
  }));
  check('and its code comes back', privateCode.length === 6, privateCode);
  await openJoinPanel(pupil.page);
  check('the pupil\u2019s directory does not list it', !(await panelText(pupil.page)).includes('Suite Staff Room'),
    JSON.stringify({ panel: await panelText(pupil.page), console: consoleNotes }));
  check('nor the administrator-only listing it came with', !(await panelText(pupil.page)).includes('code '));

  // The wrong code first: nothing opens, and the page says so.
  await pupil.page.fill('#matrix-join-code', 'ZZZZZZ');
  await pupil.page.click('#matrix-join-go');
  await pupil.page.waitForTimeout(1500);
  check('a code nobody holds opens nothing', (await panelText(pupil.page)).includes('No channel is open with that code'), await panelText(pupil.page));

  if (privateCode) {
    await pupil.page.fill('#matrix-join-code', privateCode);
    await pupil.page.click('#matrix-join-go');
    await pupil.page.waitForTimeout(2500);
    check('the code lets the pupil in', (await roomListText(pupil.page)).includes('Suite Staff Room'), await roomListText(pupil.page));
  }

  check('no page errors', errors.length === 0, JSON.stringify(errors));

  await admin.ctx.close();
  await pupil.ctx.close();
  await browser.close();

  await surreal("DELETE chat_channel WHERE room_id CONTAINS 'mockroom';");
  stop();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
