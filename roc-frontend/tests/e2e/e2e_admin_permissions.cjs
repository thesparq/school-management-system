// The administrator's type and permissions, in the browser, against a *sandbox* backend (see README.md).
//
// Two halves, two callers:
//   * a super admin (the developer's own key, as the other suites use) fills the admin form: the type
//     picker lists the catalog, a fresh form starts on the school's narrowest type with its ticks, a tick
//     can be taken off and put back, choosing another type re-seeds them, Super Admin is every tick and
//     read-only, and the save posts the type and ticks the panel showed;
//   * a supervisor — an administrator whose row carries the LMS and assessments but not user management —
//     sees a sidebar without the screens the backend would refuse, is told which permission the user screen
//     needs when it deep-links to one, and still gets the LMS.
//
// Needs playwright + chromium (the same install the other e2e suites require):
//   cd roc-frontend && npm i -D playwright && npx playwright install chromium
//   node tests/e2e/e2e_admin_permissions.cjs

const { chromium } = require('playwright');

const appUrl = process.env.APP_URL || 'http://127.0.0.1:8000';
const apiToken = process.env.AUTH_TOKEN || 'dev-skip';
const stamp = Date.now();

const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
// A token the mock's userinfo endpoint honours: `sub` names a login it has, `exp` is in the future, and the
// claims the page reads for itself (its own `groups`) say administrator.
const jwtFor = (sub) => `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({
  iss: 'https://auth.johnethel.school/application/o/school-management-system/',
  sub,
  exp: Math.floor(Date.now() / 1000) + 3600,
  email: 'seed-admin@example.com',
  name: 'Seed Admin',
  groups: ['administrators'],
})}.sig`;

const results = [];
const check = (name, ok, extra = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); };

// The sandbox API, as the developer's own key: what the suite needs to set a seat up and read rows back.
const api = async (method, path, body, token = apiToken) => {
  const res = await fetch(`${appUrl}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  return res.json();
};
const rowsOf = (env) => (Array.isArray(env) ? (env[0] || {}).result : (env || {}).result) || [];

(async () => {
  const browser = await chromium.launch({ channel: 'chromium' });

  // --- Half one: the form, as a super admin ---
  const ctx = await browser.newContext();
  // The page validates the stored token itself (a JWT-shaped one with a future `exp`), while every /api/
  // call is rewritten to the developer's own key — the two halves of "a super admin using the form".
  await ctx.addInitScript(t => localStorage.setItem('auth_token', t), jwtFor('form-suite'));
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message.slice(0, 120)));
  await page.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: `Bearer ${apiToken}` },
  }));

  const hasText = (t) => page.evaluate((s) => document.body.innerText.includes(s), t);
  const tickOf = (key) => page.$eval(`[id="permission-tick-${key}"] button`, el => ({ text: el.textContent.trim(), disabled: el.disabled }));
  const headers = () => page.$$eval('#app table thead th', els => els.map(e => e.textContent.trim()).filter(Boolean));
  const openModal = async () => {
    await page.click('#app button:has-text("Add New User")');
    await page.waitForFunction(() => (document.querySelector('#app h3') || {}).textContent === 'Add New User', null, { timeout: 10000 }).catch(() => {});
  };

  await page.goto(`${appUrl}/admin/users`, { waitUntil: 'load' });
  await page.waitForSelector('text=Add New User', { timeout: 45000 });
  await page.click('#app button:has-text("Administrators")');
  await page.waitForTimeout(1200);
  check('the administrators table names the type column', (await headers()).includes('Admin type'), JSON.stringify(await headers()));
  // The rows land after the tab's fetch: wait for the table to carry one, then look for a type label in it.
  await page.waitForSelector('#app table tbody tr', { timeout: 20000 }).catch(() => {});
  await page.waitForFunction(() => {
    const cells = Array.from(document.querySelectorAll('#app table tbody tr td')).map(c => c.textContent.trim());
    return cells.includes('Supervisor') || cells.includes('Super Admin');
  }, null, { timeout: 20000 }).catch(() => {});
  check('and shows the type a seeded row carries', await page.evaluate(() => {
    const cells = Array.from(document.querySelectorAll('#app table tbody tr td')).map(c => c.textContent.trim());
    return cells.includes('Supervisor') || cells.includes('Super Admin');
  }));

  await openModal();
  await page.selectOption('#new-user-role-select', 'Admin');
  await page.waitForTimeout(400);
  check('the form offers an admin type picker', (await page.locator('#new-user-admin-type-select').count()) === 1);
  const options = await page.$$eval('#new-user-admin-type-select option', els => els.map(e => e.textContent.trim()));
  check('the picker lists the school\'s types', options.includes('Supervisor') && options.includes('Super Admin'), JSON.stringify(options));
  check('a fresh form starts on the narrowest type', (await page.$eval('#new-user-admin-type-select', el => el.value)) === 'supervisor');
  check('the panel lists every permission the school has', (await page.locator('[id^="permission-tick-"]').count()) === 6);
  check('with the ticks that type starts on', (await tickOf('lessons.manage')).text === '☑' && (await tickOf('assessments.manage')).text === '☑');
  check('and none of the others', (await tickOf('users.manage')).text === '☐' && (await tickOf('setup.manage')).text === '☐' && (await tickOf('permissions.manage')).text === '☐');

  await page.click('[id="permission-tick-users.manage"] button');
  await page.waitForTimeout(200);
  check('a tick can be put back on', (await tickOf('users.manage')).text === '☑');
  await page.click('[id="permission-tick-users.manage"] button');
  await page.waitForTimeout(200);
  check('and taken off again', (await tickOf('users.manage')).text === '☐');

  await page.selectOption('#new-user-admin-type-select', 'super_admin');
  await page.waitForTimeout(300);
  check('choosing Super Admin ticks everything', (await tickOf('users.manage')).text === '☑' && (await tickOf('permissions.manage')).text === '☑');
  check('and says the type holds every permission', await hasText('A super admin holds every permission'));
  check('with those ticks read-only', (await tickOf('users.manage')).disabled === true);

  await page.selectOption('#new-user-admin-type-select', 'supervisor');
  await page.waitForTimeout(300);
  check('choosing a narrower type ticks only its own', (await tickOf('lessons.manage')).text === '☑' && (await tickOf('users.manage')).text === '☐');

  // The save itself: what the panel shows is what the backend is asked to store.
  const surname = `Typecheck${stamp % 10000}`;
  let posted = null;
  page.on('request', r => { if (r.method() === 'POST' && r.url().includes('/api/users')) posted = r.postData(); });
  await page.locator('input[placeholder="e.g. Adamu"]').fill('Panel');
  await page.locator('input[placeholder="e.g. Musa"]').fill(surname);
  await page.locator('input[placeholder="e.g. adamu@johnethel.school"]').fill(`panel${stamp}@example.com`);
  await page.locator('input[placeholder="https://..."]').fill('https://example.com/panel.jpg');
  await page.click('[id="permission-tick-users.manage"] button');
  await page.waitForTimeout(200);
  await page.click('text=Create User');
  await page.waitForTimeout(2500);
  check('the create carries the type it was given', !!posted && posted.includes('"admin_type":"supervisor"'), posted ? posted.slice(0, 200) : 'no POST');
  check('and exactly the ticks that were ticked',
    !!posted && posted.includes('"permissions":["lessons.manage","assessments.manage","users.manage"]'),
    posted ? posted.slice(0, 240) : 'no POST');
  const created = rowsOf(await api('GET', '/api/users?role=Admin')).find(r => r.surname === surname);
  check('and the row is stored with them', !!created && created.admin_type === 'supervisor' && (created.permissions || []).join(',') === 'lessons.manage,assessments.manage,users.manage', JSON.stringify(created || {}));
  check('no page errors in the form', errors.length === 0, JSON.stringify(errors));

  // --- Half two: a supervisor's own view ---
  // The mock seeds an administrator login per process, and the profile rows earlier runs left behind carry
  // the same name, so the candidate whose pk this process's directory still honours is the one to use: the
  // mock answers a token for a login it has, and 401s one for a login it no longer knows.
  const admins = rowsOf(await api('GET', '/api/users?role=Admin'));
  const candidates = admins.filter(r => r.display_name === 'Seed Admin').map(r => String(r.id).replace('admin_profile:', ''));
  check('the sandbox directory has the seeded administrator', candidates.length > 0, JSON.stringify(admins.map(r => r.id)));
  let seedPk = '';
  let supervisorToken = '';
  // `/api/admin-rights` answers a bare object (`{"is_super":…,"permissions":[…]}`) rather than a SurrealDB
  // envelope, so the reader accepts either shape.
  const rightsOf = (answer) => (Array.isArray(answer) ? ((answer[0] || {}).result || null) : (answer && 'is_super' in answer ? answer : null));
  for (const pk of candidates) {
    const answer = await api('GET', '/api/admin-rights', null, jwtFor(pk));
    if (rightsOf(answer)) { seedPk = pk; supervisorToken = jwtFor(pk); break; }
  }
  check('and this process\'s seeded login is the one that answers', !!seedPk, JSON.stringify(candidates));
  // Giving that login a supervisor's seat is what makes the caller a supervisor: the ticks are the truth.
  await api('PUT', '/api/users', {
    id: `admin_profile:${seedPk}`,
    first_name: 'Seed',
    surname: 'Admin',
    passport: 'https://example.com/seed-admin.jpg',
    admin_type: 'supervisor',
    permissions: ['lessons.manage', 'assessments.manage'],
  });
  const rights = rightsOf(await api('GET', '/api/admin-rights', null, supervisorToken));
  check('the supervisor\'s own rights are the LMS and assessments', rights.is_super === false && rights.permissions.join(',') === 'lessons.manage,assessments.manage', JSON.stringify(rights));

  const supCtx = await browser.newContext();
  await supCtx.addInitScript(t => localStorage.setItem('auth_token', t), supervisorToken);
  const sup = await supCtx.newPage();
  const supErrors = [];
  sup.on('pageerror', e => supErrors.push(e.message.slice(0, 120)));
  const navLabels = () => sup.$$eval('#app aside [data-nav]', els => els.map(e => e.textContent.trim()).filter(Boolean));

  await sup.goto(`${appUrl}/admin/lms`, { waitUntil: 'load' });
  await sup.waitForTimeout(2500);
  const labels = await navLabels();
  check('a supervisor is offered the LMS', labels.includes('LMS'), JSON.stringify(labels));
  check('and not the user list', !labels.includes('User Management'), JSON.stringify(labels));
  check('nor the configuration hub', !labels.includes('Configuration Hub'), JSON.stringify(labels));
  check('and still gets the dashboard and messaging', labels.includes('Dashboard') && labels.includes('Messaging'), JSON.stringify(labels));
  check('the LMS itself opens for them', await sup.evaluate(() => !document.body.innerText.includes('needs another permission')));

  await sup.goto(`${appUrl}/admin/users`, { waitUntil: 'load' });
  await sup.waitForSelector('text=This screen needs another permission', { timeout: 20000 }).catch(() => {});
  check('a deep link to the user screen says which permission it needs',
    await sup.evaluate(() => document.body.innerText.includes("it needs 'Manage users'")),
    await sup.evaluate(() => document.body.innerText.slice(0, 200)));
  check('and offers no user actions there', (await sup.locator('#app button:has-text("Add New User")').count()) === 0);

  await sup.goto(`${appUrl}/admin/config`, { waitUntil: 'load' });
  await sup.waitForSelector('text=This screen needs another permission', { timeout: 20000 }).catch(() => {});
  check('so does the configuration hub', await sup.evaluate(() => document.body.innerText.includes("it needs 'Manage school setup'")));
  check('no page errors for the supervisor', supErrors.length === 0, JSON.stringify(supErrors));

  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
