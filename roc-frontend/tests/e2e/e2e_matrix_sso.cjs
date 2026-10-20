// The chat page's own login, in Chromium, against a mock Synapse (see README.md): the Messaging tab
// sends the person to the homeserver's SSO entry point, the homeserver comes back to the page with a
// one-time `loginToken`, the page exchanges it for an access token and connects — with **no admin
// credential anywhere**. That is the property that replaced the old `/api/matrix/token` proxy, which
// minted tokens through Synapse's admin API with a shared `MATRIX_ADMIN_TOKEN`.
//
// Self-contained: it builds the backend, boots it (pointed at the mock homeserver, deliberately
// *without* MATRIX_ADMIN_TOKEN) plus the mock Synapse, and drives the real page. No database and no
// Authentik are needed — the app token is a DEV_MODE one, and the identity-provider hop is the mock's.
//
//   node tests/e2e/e2e_matrix_sso.cjs

const { chromium } = require('playwright');
const { spawn, spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const repo = path.resolve(__dirname, '../../..');
const mockPort = 9010;
const appPort = 8126;
const appUrl = `http://127.0.0.1:${appPort}`;
const mockUrl = `http://127.0.0.1:${mockPort}/`;

const results = [];
const check = (name, ok, extra = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); };
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const appToken = `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({
  iss: 'https://auth.johnethel.school/application/o/school-management-system/',
  exp: Math.floor(Date.now() / 1000) + 3600,
  email: 'chat@example.com', name: 'Chat Check', groups: ['administrators'],
})}.sig`;
// A pupil's token: no group the page maps to Administrator, so its view of the chat sidebar is a pupil's
// (see the pupil phase at the end).
const pupilToken = `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({
  iss: 'https://auth.johnethel.school/application/o/school-management-system/',
  exp: Math.floor(Date.now() / 1000) + 3600,
  email: 'pupil@example.com', name: 'Pupil Check', groups: ['students'],
})}.sig`;

(async () => {
  const workdir = fs.mkdtempSync(path.join(os.tmpdir(), 'matrix-sso-'));
  const backendBin = path.join(workdir, 'backend');
  const mockLog = path.join(workdir, 'mock.log');
  // What the mock homeserver offers, in a file it re-reads per request: the last phase of this suite
  // changes it while the page is open (see the homeserver-with-no-provider block below).
  const providersFile = path.join(workdir, 'providers.json');
  fs.writeFileSync(providersFile, JSON.stringify([{ id: 'oidc-authentik', name: 'Johnethel School SSO' }]));
  fs.writeFileSync(mockLog, '');

  console.log('building the backend (first run is slow)...');
  const build = spawnSync('roc', ['build', 'roc-backend/main.roc', `--output=${backendBin}`], { cwd: repo, stdio: 'inherit' });
  if (build.status !== 0) { console.error('backend build failed'); process.exit(1); }

  const mock = spawn('python3', ['roc-frontend/tests/e2e/fixtures/mock_synapse.py', String(mockPort)], {
    cwd: repo, stdio: ['ignore', 'inherit', 'inherit'],
    env: { ...process.env, LOG_FILE: mockLog, SSO_PROVIDERS_FILE: providersFile },
  });
  // The mock has to be listening before the page can log in; wait for it rather than assuming.
  let mockUp = false;
  for (let i = 0; i < 40; i++) {
    try { await fetch(`http://127.0.0.1:${mockPort}/_matrix/client/v3/account/whoami`); mockUp = true; break; } catch { /* not up yet */ }
    await sleep(250);
  }
  check('the mock homeserver is listening', mockUp);
  // No MATRIX_ADMIN_TOKEN on purpose: the flow under test must not need one. A dead database URL, so
  // the sandbox can never reach prod; the chat route touches no database.
  const backend = spawn(backendBin, [], {
    // From `roc-backend`, like the deployment: the app's own static files are served from
    // `../roc-frontend/www` relative to the backend's working directory.
    cwd: path.join(repo, 'roc-backend'),
    stdio: 'ignore',
    env: {
      ...process.env,
      DEV_MODE: 'true',
      BIND_HOST: '127.0.0.1',
      PORT: String(appPort),
      SURREAL_URL: 'http://127.0.0.1:59999/sql',
      AUTHENTIK_ISSUER_URL: 'http://127.0.0.1:9000/application/o/school/',
      PUBLIC_MATRIX_URL: mockUrl,
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
  const countMatching = (needle) => mockLines().filter(l => l.includes(needle)).length;
  // Exact-path lines, for the paths that are prefixes of one another (`/login` and `/login/sso/...`).
  const countPath = (method, path) => mockLines().filter(l => l.trim() === `${method} ${path}`).length;

  const browser = await chromium.launch({ channel: 'chromium' });
  const ctx = await browser.newContext();
  await ctx.addInitScript(t => localStorage.setItem('auth_token', t), appToken);
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message.slice(0, 160)));
  // The app's own API calls are driven by a DEV_MODE admin token; the chat calls go to the mock
  // homeserver and must carry the person's own token, which the mock checks.
  await page.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: 'Bearer dev-skip' },
  }));

  const matrixToken = () => page.evaluate(() => sessionStorage.getItem('matrix_token'));
  const hasText = (t) => page.evaluate((s) => document.body.innerText.includes(s), t);
  // What the chat panel is showing, for a failure message: the page reports its own reasons there.
  const chatPanel = () => page.evaluate(() => (document.getElementById('matrix-rooms-list') || {}).innerText || 'no panel');

  // --- The first visit: the SSO trip out and back ---
  await page.goto(`${appUrl}/messaging`, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  check('the page asked the homeserver for an SSO login', countMatching('/login/sso/redirect') === 1,
    `mock log: ${JSON.stringify(mockLines())} | panel: ${await chatPanel()} | errors: ${JSON.stringify(errors)}`);
  // The provider is the homeserver's to name. The mock offers `oidc-authentik` — what Synapse makes of
  // the config's `idp_id: authentik` — and 404s anything else, so a pinned name fails here rather than on
  // the deployed homeserver.
  check('it asked which provider the homeserver offers', countPath('GET', '/_matrix/client/v3/login') === 1);
  check('and used the id it was offered, not the config file\u2019s',
    mockLines().some(l => l.startsWith('GET /_matrix/client/v3/login/sso/redirect/oidc-authentik?')),
    JSON.stringify(mockLines().slice(0, 3)));
  check('no attempt named a provider the homeserver does not offer',
    !mockLines().some(l => l.includes('/login/sso/redirect/authentik?')), JSON.stringify(mockLines().slice(0, 3)));
  check('the redirect carried the app page as its return address',
    mockLines().some(l => l.includes(encodeURIComponent(`${appUrl}/messaging`))), JSON.stringify(mockLines().slice(0, 3)));
  check('the one-time login token was exchanged for an access token', countMatching('POST /_matrix/client/v3/login') === 1);
  check('the page now holds that token', !!(await matrixToken()), await matrixToken());
  check('and it connected: the room list is the empty state, not an error',
    await hasText('No channels yet'), (await page.evaluate(() => (document.getElementById('matrix-rooms-list') || {}).innerText || '')).slice(0, 120));
  // A channel on this server is the school's, so making one is offered to an administrator only; joining a
  // public one stays everyone's (the pupil phase below holds the other half of that rule).
  check('an administrator is offered a new channel', await page.evaluate(() => !!document.getElementById('matrix-new-channel-btn')));
  check('and the sidebar offers joining a public one', await page.evaluate(() => !!document.getElementById('matrix-join-channel-btn')));
  check('the loginToken is gone from the address', !page.url().includes('loginToken'), page.url());
  check('nothing in the flow called the homeserver admin API', countMatching('/_synapse/admin/') === 0, JSON.stringify(mockLines()));

  // --- A reload: the tab's token is reused, no second login ---
  const redirectsAfterFirst = countMatching('/login/sso/redirect');
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(5000);
  check('a reload does not start another login', countMatching('/login/sso/redirect') === redirectsAfterFirst,
    `redirects ${redirectsAfterFirst} -> ${countMatching('/login/sso/redirect')}`);
  check('and the chat connects from the stored token', await hasText('No channels yet'));
  check('the stored token is unchanged', !!(await matrixToken()));

  // --- A token that has already been spent: an offer to retry, not a redirect loop ---
  // In a *fresh* tab session, so the stored token of the previous steps cannot answer for it — this is the
  // state a person is in when a redirect is replayed in a new tab, or when their first attempt failed.
  const spentCtx = await browser.newContext();
  await spentCtx.addInitScript(t => localStorage.setItem('auth_token', t), appToken);
  const spentPage = await spentCtx.newPage();
  spentPage.on('pageerror', e => errors.push(e.message.slice(0, 160)));
  await spentPage.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: 'Bearer dev-skip' },
  }));
  const redirectsBeforeSpent = countMatching('/login/sso/redirect');
  await spentPage.goto(`${appUrl}/messaging?loginToken=mock-login-token-1`, { waitUntil: 'load' });
  await spentPage.waitForTimeout(5000);
  check('a replayed login token is refused, not retried in a loop', countMatching('/login/sso/redirect') === redirectsBeforeSpent,
    `redirects ${redirectsBeforeSpent} -> ${countMatching('/login/sso/redirect')}`);
  check('and the page offers to connect again',
    await spentPage.evaluate(() => document.body.innerText.includes('Try again')),
    (await spentPage.evaluate(() => (document.getElementById('matrix-rooms-list') || {}).innerText || 'no panel')).slice(0, 120));
  check('with the refusal said in the page', await spentPage.evaluate(() => document.body.innerText.includes('Invalid login token')));

  // --- Try again: a fresh login, from the button ---
  await spentPage.click('button:has-text("Try again")');
  await spentPage.waitForTimeout(6000);
  check('the retry runs the login again', countMatching('/login/sso/redirect') === redirectsBeforeSpent + 1);
  check('and lands connected', await spentPage.evaluate(() => document.body.innerText.includes('No channels yet')));
  check('still without touching the admin API', countMatching('/_synapse/admin/') === 0);
  check('no page errors', errors.length === 0, JSON.stringify(errors));
  await spentCtx.close();

  // --- A pupil's own sidebar: join a public channel, but not make one ---
  // The other half of `renderMatrixChannelControls`' rule, driven with a token whose groups map to the
  // pupil role. Its own context, so the administrator's stored chat token cannot answer for it.
  const pupilCtx = await browser.newContext();
  await pupilCtx.addInitScript(t => localStorage.setItem('auth_token', t), pupilToken);
  const pupilPage = await pupilCtx.newPage();
  pupilPage.on('pageerror', e => errors.push(e.message.slice(0, 160)));
  await pupilPage.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: 'Bearer dev-skip' },
  }));
  await pupilPage.goto(`${appUrl}/messaging`, { waitUntil: 'load' });
  await pupilPage.waitForTimeout(6000);
  check('a pupil is not offered a way to make a channel',
    !(await pupilPage.evaluate(() => !!document.getElementById('matrix-new-channel-btn'))),
    (await pupilPage.evaluate(() => (document.getElementById('matrix-rooms') || {}).innerText || 'no sidebar')).slice(0, 160));
  check('but is offered joining a public one',
    await pupilPage.evaluate(() => !!document.getElementById('matrix-join-channel-btn')));
  check('and the empty sidebar says what a pupil can do',
    await pupilPage.evaluate(() => document.body.innerText.includes('join a public one, or wait for an invitation')));
  check('the pupil connected all the same',
    await pupilPage.evaluate(() => document.body.innerText.includes('No channels yet')));
  await pupilCtx.close();

  // --- A homeserver that offers no provider at all: said plainly, and no trip into a 404 ---
  // The state the deployed homeserver was in for the page's old, pinned id: an unknown provider answers
  // 404 in the browser as a bare JSON error. The connect path has to stop at the app instead and say what
  // is wrong — here, by the homeserver reporting an empty provider list.
  fs.writeFileSync(providersFile, '[]');
  const noProvCtx = await browser.newContext();
  await noProvCtx.addInitScript(t => localStorage.setItem('auth_token', t), appToken);
  const noProvPage = await noProvCtx.newPage();
  noProvPage.on('pageerror', e => errors.push(e.message.slice(0, 160)));
  await noProvPage.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: 'Bearer dev-skip' },
  }));
  const redirectsBeforeNoProvider = countMatching('/login/sso/redirect');
  await noProvPage.goto(`${appUrl}/messaging`, { waitUntil: 'load' });
  await noProvPage.waitForTimeout(4000);
  check('a homeserver with no provider is not sent to one',
    countMatching('/login/sso/redirect') === redirectsBeforeNoProvider);
  check('and the page says so',
    await noProvPage.evaluate(() => document.body.innerText.includes('offers no sign-in provider')),
    (await noProvPage.evaluate(() => (document.getElementById('matrix-rooms-list') || {}).innerText || 'no panel')).slice(0, 160));
  check('with the way to try again',
    await noProvPage.evaluate(() => document.body.innerText.includes('Try again')));
  check('still no page errors', errors.length === 0, JSON.stringify(errors));
  await noProvCtx.close();

  await browser.close();
  stop();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
