// User management's directory half against a *sandbox* backend (see README.md): a login an admin made
// in Authentik itself is listed with a `No profile yet` badge and a Complete profile action, that
// action loads the login into the form above (which switches to its completing mode), and the write it
// makes attaches the profile — the row then renders like any account the app made itself.
//
// The login this drives is one the fixture's Authentik starts with, and the fixture's database seeds
// no profile row for it. A previous run (or users_api.sh) leaves one behind, so a profile is deleted
// first: the tab then lists the bare login again, which is the state this suite covers. That delete
// switches the mock login off, the way a delete does — nothing here reads the enabled state, so the
// suite runs again and again against the same sandbox.
//
//   node tests/e2e/e2e_users_directory.cjs

const { chromium } = require('playwright');

const appUrl = process.env.APP_URL || 'http://127.0.0.1:8000';
const authToken = process.env.AUTH_TOKEN || 'dev-skip';
const stamp = Date.now();
// The fixture's seeded student login: the one whose row this suite completes.
const LOGIN_EMAIL = 'seed-student@example.com';

const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const token = `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({
  iss: 'https://auth.johnethel.school/application/o/school-management-system/',
  exp: Math.floor(Date.now() / 1000) + 3600,
  email: 'bursar@example.com', name: 'Admin User', groups: ['administrators'],
})}.sig`;

const results = [];
const check = (name, ok, extra = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); };

const rowsOf = (data) => {
  const envelope = Array.isArray(data) ? data[0] : data;
  return (envelope && Array.isArray(envelope.result)) ? envelope.result : [];
};

// The Students tab as the API answers it, so the row this suite drives is found the way the page finds
// it: by the login's address, not by a hard-coded id (a seeded pk carries the mock's own pid).
const studentsListing = async () => {
  const res = await fetch(`${appUrl}/api/users?role=Student`, { headers: { authorization: `Bearer ${authToken}` } });
  if (!res.ok) throw new Error(`GET /api/users?role=Student answered ${res.status}`);
  return rowsOf(await res.json());
};

const summary = () => {
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
};

(async () => {
  // --- The state the suite starts from: that login listed, with no profile to complete ---
  let login;
  try {
    const listed = await studentsListing();
    login = listed.find(r => r.email === LOGIN_EMAIL);
    if (login && login.has_profile) {
      const res = await fetch(`${appUrl}/api/users`, {
        method: 'DELETE',
        headers: { authorization: `Bearer ${authToken}`, 'content-type': 'application/json' },
        body: JSON.stringify({ id: login.id }),
      });
      if (!res.ok) throw new Error(`DELETE /api/users answered ${res.status}`);
      login = (await studentsListing()).find(r => r.email === LOGIN_EMAIL);
    }
  } catch (err) {
    console.error(`FAIL  the sandbox could not be prepared — ${err.message}`);
    process.exit(1);
  }
  const prepared = !!login && login.has_profile === false;
  check('the directory login is listed with no profile to complete', prepared,
    prepared ? '' : `${LOGIN_EMAIL} is not listed as a login without a profile — run against the sandbox (see README.md)`);
  if (!prepared) summary();
  const loginId = login.id;
  // The name the directory gives that login: the row is rendered from it while it has no profile, so
  // the completed row is checked against it rather than against the fixture's spelling.
  const directoryName = login.display_name;

  const browser = await chromium.launch({ channel: 'chromium' });
  const ctx = await browser.newContext();
  await ctx.addInitScript(t => localStorage.setItem('auth_token', t), token);
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message.slice(0, 80)));
  // The completing write, captured as the browser sends it: it has to name the login and carry no
  // email (that address belongs to Authentik's login, and the form does not send it).
  let write = null;
  page.on('request', r => {
    if (r.method() === 'PUT' && r.url().includes('/api/users')) {
      write = r.postDataJSON ? r.postDataJSON() : JSON.parse(r.postData());
    }
  });
  await page.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: `Bearer ${authToken}` },
  }));

  await page.goto(`${appUrl}/admin/users`, { waitUntil: 'load' });
  await page.waitForSelector('text=Add New User', { timeout: 45000 });
  check('user management page loads', true);

  const hasText = (t) => page.evaluate((s) => document.body.innerText.includes(s), t);
  const cardTitle = () => page.locator('#app h3').first().innerText();
  const row = (t) => page.locator('#app table tbody tr', { hasText: t });
  // A row's second cell is its name (the first is the avatar, and a profile-less row puts its badge
  // in the name cell too, on a line of its own).
  const rowName = async (r) => (await r.locator('td').nth(1).innerText()).split('\n')[0].trim();

  // --- The profile-less row: the badge, and the one action that completes it ---
  await page.waitForSelector(`text=${LOGIN_EMAIL}`, { timeout: 20000 });
  const seededRow = row(LOGIN_EMAIL);
  check('the login is listed as a row of its tab', (await seededRow.count()) === 1);
  check('the row carries the No profile yet badge', (await seededRow.locator('text=No profile yet').count()) === 1);
  const rowActions = await seededRow.locator('button').allInnerTexts();
  check('and offers Complete profile as its only action', rowActions.length === 1 && rowActions[0] === 'Complete profile', JSON.stringify(rowActions));

  // --- That action loads the login into the form above, which switches to its completing mode ---
  await seededRow.locator('button', { hasText: 'Complete profile' }).click();
  await page.waitForFunction(() => (document.querySelector('#app h3') || {}).textContent === 'Complete Profile', null, { timeout: 10000 }).catch(() => {});
  const title = await cardTitle();
  check('the form switches to Complete Profile', title === 'Complete Profile', title);
  check('showing the login\'s address in a disabled email field',
    await page.locator('input[type="email"]').evaluate((el, email) => el.disabled && el.value === email, LOGIN_EMAIL));
  check('with the role picker fixed to the row\'s own tab',
    await page.locator('#new-user-role-select').evaluate(el => el.disabled && el.value === 'Student'));
  // The form's submit and the rows' actions share the label; the card is above the table, so the
  // form's button is the first one in the DOM (see AdminView.roc's note).
  const submit = page.locator('#app button:has-text("Complete profile")').first();
  const submitLabel = await submit.innerText();
  check('and a submit that says Complete profile', submitLabel === 'Complete profile', submitLabel);

  // --- Filling it and submitting: the completing write ---
  const surname = `Directory${stamp % 10000}`;
  const fill = (placeholder, value) => page.locator(`input[placeholder="${placeholder}"]`).fill(value);
  await fill('e.g. Adamu', 'Ada');
  await fill('e.g. Musa', surname);
  await page.selectOption('#new-user-class-level', 'class_levels:jss_2');
  await fill('https://...', 'https://example.com/directory.jpg');
  await page.locator('input[type="date"]').fill('2011-07-08');
  await submit.click();

  await page.waitForSelector('text=Profile completed', { timeout: 20000 }).catch(() => {});
  check('the completing write reports Profile completed', await hasText('Profile completed'));
  check('as a PUT that names that login and carries no email',
    !!write && write.id === loginId && write.email === undefined, JSON.stringify(write));

  // --- The row the write completed: a normal one, showing the profile's own name and the login's email ---
  // The write refreshes all four lists, so wait for that render rather than for a fixed time: the row
  // stops saying No profile yet when it lands.
  await page.waitForFunction((email) => {
    const row = [...document.querySelectorAll('#app table tbody tr')].find(r => r.innerText.includes(email));
    return !!row && !row.innerText.includes('No profile yet');
  }, LOGIN_EMAIL, { timeout: 20000 }).catch(() => {});
  const completedRow = row(LOGIN_EMAIL);
  check('the row is no longer waiting for a profile', (await completedRow.locator('text=No profile yet').count()) === 0);
  // The row now renders from the profile: its name is the profile's own, not the login's directory
  // name. (Which profile name shows depends on what the row had: a row PUT has to make gets the name
  // derived from the form, while a row that is already there — one an earlier run soft-deleted — is
  // patched and keeps the name it had, because the form has no display-name field to send.)
  const completedName = await rowName(completedRow);
  check("it shows the profile's own name, not the directory's", completedName !== '' && completedName !== directoryName, completedName);
  check("and the login's address is still its email", (await completedRow.innerText()).includes(LOGIN_EMAIL));
  const completedActions = await completedRow.locator('button').allInnerTexts();
  check('with Edit and Deactivate back', completedActions.join(',') === 'Edit,Deactivate', JSON.stringify(completedActions));

  // --- The form is ready for the next account again ---
  check('the form returns to Add New User',
    (await cardTitle()) === 'Add New User' && await page.locator('input[type="email"]').evaluate(el => !el.disabled && el.value === ''));

  check('no page errors', errors.length === 0, JSON.stringify(errors));

  await browser.close();
  summary();
})();
