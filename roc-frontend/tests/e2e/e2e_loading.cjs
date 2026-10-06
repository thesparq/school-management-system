// Loading behaviour against a *sandbox* backend (see README.md), driven the way a person drives it:
// land on the dashboard and click through the sidebar. That is the path the other suites' `goto`
// never took, and it is exactly where a failed fetch used to leave every list on its loading message
// forever (one global flag, so switching tabs did not help). Checks the three list states — skeleton,
// loaded-and-empty, and failed-with-retry — the top border progress bar, and the nav bar's active
// session term.
//
//   node tests/e2e/e2e_loading.cjs
//
// The fixture's Authentik seeds a login per role, so every tab has at least one row and none is empty
// on its own: the empty state is observed on a tab whose payload is faked empty for one click (the
// same route interception the 500 case uses), which is what makes it a state of the list rather than
// an accident of the fixture.

const { chromium } = require('playwright');

const appUrl = process.env.APP_URL || 'http://127.0.0.1:8000';
// The users endpoints are held back so the skeleton is observable, later made to answer 500 with the
// API's own error shape, and one role's list is made to answer as loaded-and-empty.
const USERS_DELAY_MS = 800;
const FAILURE_BODY = { error: 'Database error', detail: 'the users query failed' };
const EMPTY_BODY = [{ result: [], status: 'OK' }];

const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const token = `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({
  iss: 'https://auth.johnethel.school/application/o/school-management-system/',
  exp: Math.floor(Date.now() / 1000) + 3600,
  email: 'bursar@example.com', name: 'Admin User', groups: ['administrators'],
})}.sig`;

const results = [];
const check = (name, ok, extra = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); };

const waitFor = (fn, timeout = 5000) => fn().then(() => true).catch(() => false);

(async () => {
  const browser = await chromium.launch({ channel: 'chromium' });
  const ctx = await browser.newContext();
  await ctx.addInitScript(t => localStorage.setItem('auth_token', t), token);
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message.slice(0, 80)));

  let usersFail = false;
  // The role whose tab answers an empty list, so the loaded-and-empty state is observable on demand.
  let emptyRole = null;
  await page.route('**/api/**', async route => {
    const url = route.request().url();
    if (url.includes('/api/users?role=')) {
      if (usersFail) {
        return route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify(FAILURE_BODY) });
      }
      if (emptyRole && url.includes(`/api/users?role=${emptyRole}`)) {
        return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(EMPTY_BODY) });
      }
      await new Promise(r => setTimeout(r, USERS_DELAY_MS));
    }
    return route.continue({
      headers: { ...route.request().headers(), authorization: `Bearer ${process.env.AUTH_TOKEN || 'dev-skip'}` },
    });
  });

  const hasText = (t) => page.evaluate((s) => document.body.innerText.includes(s), t);
  const skeletonCount = () => page.evaluate(() => document.querySelectorAll('#app [data-skeleton]').length);
  const barVisible = () => page.waitForFunction(() => {
    const bar = document.getElementById('nav-progress');
    return !!bar && !bar.classList.contains('hidden');
  }, null, { timeout: 5000 });
  const barHidden = () => page.waitForFunction(() => {
    const bar = document.getElementById('nav-progress');
    return !!bar && bar.classList.contains('hidden');
  }, null, { timeout: 5000 });
  const skeletonVisible = () => page.waitForFunction(() =>
    document.querySelectorAll('#app [data-skeleton]').length > 0, null, { timeout: 5000 });

  // --- Land on the dashboard, the way a login does ---
  await page.goto(`${appUrl}/`, { waitUntil: 'load' });
  await page.waitForSelector('text=Welcome back', { timeout: 45000 });
  check('dashboard loads', true);

  // What the API says is active is what the bar has to show. Read it rather than hard-coding the
  // fixture's term: a sandbox other suites have already written to has a different one active.
  const activeTerm = await page.evaluate(async () => {
    const res = await fetch('/api/session_terms/active');
    const body = await res.json();
    const envelope = Array.isArray(body) ? body[0] : body;
    const rows = envelope && envelope.result ? (Array.isArray(envelope.result) ? envelope.result : [envelope.result]) : [];
    const row = rows[0] || null;
    return row ? { name: row.session_name, term: row.term_name } : null;
  });

  await page.waitForSelector('#active-session-term', { timeout: 20000 }).catch(() => {});
  const badge = await page.evaluate(() => (document.getElementById('active-session-term') || {}).innerText || '');
  check('the nav bar shows the active session term',
    !!activeTerm && badge.includes(activeTerm.name) && badge.includes(activeTerm.term),
    activeTerm ? `${badge} (api: ${activeTerm.name} — ${activeTerm.term})` : `no active term; badge: ${badge}`);

  // --- A sidebar click into User Management: bar, skeleton, then the table ---
  await page.click('aside >> text="User Management"');
  check('the border bar shows for the navigation', await waitFor(barVisible));
  check('the users table shows its skeleton while the list loads', await waitFor(skeletonVisible));
  check('nothing says "Loading" while the skeleton is up', !(await hasText('Loading')));

  check('the skeleton hands over to the table', await waitFor(() => page.waitForFunction(() =>
    document.querySelectorAll('#app [data-skeleton]').length === 0 &&
    document.querySelectorAll('#app table tbody tr').length > 0, null, { timeout: 20000 })));
  check('the seeded student is listed', await hasText('Test Student'));
  check('no skeleton is left behind once the list has loaded', (await skeletonCount()) === 0);
  check('the session term is still shown after navigating', !!activeTerm && (await hasText(activeTerm.name)));

  // --- A tab switch: the bar appears and settles, and the tab shows its own list ---
  await page.click('button:has-text("Teachers")');
  check('the border bar shows for a tab switch', await waitFor(barVisible));
  check('the border bar goes away once the switch has rendered', await waitFor(barHidden));
  // The fixture's directory seeds a teacher login, so this tab has a row of its own — not the
  // students' — and the list it shows is the one the switch asked for.
  await page.waitForSelector('text=Seed Teacher', { timeout: 20000 }).catch(() => {});
  check('the switched-to tab shows its own list', (await hasText('Seed Teacher')) && !(await hasText('Test Student')));

  // --- A loaded-and-empty list: the three states again, with the empty one faked ---
  // Every tab of the fixture's directory has a row, so the empty state is forced on one tab for this
  // click instead of waiting for a tab that happens to be empty.
  emptyRole = 'Parent';
  await page.click('button:has-text("Parents")');
  await page.waitForSelector('text=No parents yet', { timeout: 20000 }).catch(() => {});
  check('a loaded-and-empty list shows a real empty state',
    (await hasText('No parents yet')) && (await hasText('Add a parent above to get started.')));
  check('no loading message after the tab switch', !(await hasText('Loading')));
  emptyRole = null;

  // --- /api/users answering 500: an error state naming what failed, with a retry ---
  usersFail = true;
  await page.click('a:has-text("Dashboard")');
  await page.waitForSelector('text=Welcome back', { timeout: 20000 }).catch(() => {});
  await page.click('aside >> text="User Management"');
  await page.waitForFunction(() => {
    const el = document.querySelector('#app [data-error-state]');
    return !!el && document.body.innerText.includes('the users query failed');
  }, null, { timeout: 20000 }).catch(() => {});
  check('a failed list shows the backend\'s own message', await hasText('the users query failed'), (await hasText('Database error')) ? 'error + detail' : 'no error headline');
  check('a failed list offers a retry', (await page.locator('#app button:has-text("Retry")').count()) > 0);
  check('a failed list leaves no skeleton behind', (await skeletonCount()) === 0);
  check('a failed list leaves no loading message behind', !(await hasText('Loading')));

  // --- The retry, with the endpoint healthy again, loads the list ---
  // The user-management tab the error was seen on is still the active one (Parents), and its empty
  // payload was only the route interception above, so the retry has to show the seeded parent row.
  usersFail = false;
  await page.click('#app button:has-text("Retry")');
  await page.waitForSelector('text=Seed Parent', { timeout: 20000 }).catch(() => {});
  check('the retry loads the list', (await hasText('Seed Parent')) && !(await hasText('the users query failed')));

  check('no page errors', errors.length === 0, JSON.stringify(errors));

  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
