// The password-change requirement as the person meets it, in Chromium: an account created with a
// password the admin chose signs in, and the app takes them to Settings and keeps them there — the
// sidebar offers nothing else, the form is the only thing that writes, and the school's data is refused
// until they set a password of their own (see `db/schema-v15` and `password_change_cleared!` in main.roc).
//
//   node tests/e2e/e2e_password_change.cjs        (against a sandbox backend, see README.md)

const { chromium } = require('playwright');

const appUrl = process.env.APP_URL || 'http://127.0.0.1:8000';
const adminToken = process.env.AUTH_TOKEN || 'dev-skip';
const stamp = Date.now();

const results = [];
const check = (name, ok, extra = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); };

const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
// A token the mock's userinfo honours for the login just created: `sub` names it, `groups` gives its role.
const jwtFor = (sub) => `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({
  iss: 'https://auth.johnethel.school/application/o/school-management-system/',
  sub, exp: Math.floor(Date.now() / 1000) + 3600, email: 'pw-browser@example.com', name: 'Pw Browser', groups: ['Students'],
})}.sig`;

const api = async (method, path, body) => {
  const res = await fetch(`${appUrl}${path}`, {
    method,
    headers: { Authorization: `Bearer ${adminToken}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  return res.json();
};

(async () => {
  // A student created the school's way: the admin generates a password and hands it over.
  const created = await api('POST', '/api/users', {
    role: 'Student', email: `pw_browser_${stamp}@example.com`, first_name: 'Pw', surname: `Browser${stamp}`,
    date_of_birth: '2011-05-06', class_level: 'class_levels:jss_1', passport: 'https://example.com/pwb.jpg',
    password: `Admin-Chosen-${stamp}!`,
  });
  const pk = String(created[0].result[0].id).split(':')[1].replace(/`/g, '');
  const studentToken = jwtFor(pk);

  const browser = await chromium.launch({ channel: 'chromium' });
  const ctx = await browser.newContext();
  await ctx.addInitScript(t => localStorage.setItem('auth_token', t), studentToken);
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message.slice(0, 160)));
  await page.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: `Bearer ${studentToken}` },
  }));
  const hasText = (t) => page.evaluate((s) => document.body.innerText.includes(s), t);
  const navLabels = () => page.$$eval('#app div[data-nav]', els => els.map(e => e.textContent.trim()).filter(Boolean));

  // The dashboard is where a student lands; the requirement moves them to Settings.
  await page.goto(`${appUrl}/`, { waitUntil: 'load' });
  await page.waitForSelector('text=Add New User', { timeout: 1000 }).catch(() => {});
  await page.waitForTimeout(6000);
  check('the app moves to Settings on its own', page.url().endsWith('/settings'), page.url());
  check('the sidebar offers nothing else', JSON.stringify(await navLabels()) === '["Settings"]', JSON.stringify(await navLabels()));
  check('and says why the change is owed', await hasText('Your password was set for you'),
    (await page.evaluate(() => document.body.innerText.replace(/\s+/g, ' ').slice(0, 200))));
  check('the form is there', (await page.locator('#new-password-field input').count()) === 1);

  // The form refuses what the backend would refuse, without a round trip.
  await page.fill('#new-password-field input', 'short');
  await page.fill('#confirm-password-field input', 'short');
  await page.click('text=Set my password');
  await page.waitForTimeout(1200);
  check('a too-short password is refused in the form', await hasText('at least 8 characters'));
  await page.fill('#new-password-field input', `My-Own-${stamp}!`);
  await page.fill('#confirm-password-field input', `Different-${stamp}!`);
  await page.click('text=Set my password');
  await page.waitForTimeout(1200);
  check('and so is a mismatch', await hasText('do not match'));

  // The real thing: a password of one's own, and the app opens up.
  await page.fill('#new-password-field input', `My-Own-Password-${stamp}!`);
  await page.fill('#confirm-password-field input', `My-Own-Password-${stamp}!`);
  await page.click('text=Set my password');
  await page.waitForSelector('text=Your password is set', { timeout: 20000 }).catch(() => {});
  check('setting one of your own is accepted', await hasText('Your password is set'));
  await page.waitForTimeout(2500);
  const after = await navLabels();
  check('the sidebar comes back', after.includes('My Subjects') && !after.includes('Settings only'), JSON.stringify(after));

  // And the data the requirement was holding is open.
  await page.click('#app div[data-nav]:has-text("My Subjects")');
  await page.waitForTimeout(3500);
  check('and the pages work again', await page.evaluate(() => !document.body.innerText.includes('password_change_required')), page.url());

  // --- A change the person chose: the current password is asked, and checked by Authentik ---
  // Nothing is owed now, so this is the voluntary path: the form gains the current-password field and the
  // backend verifies it through the provider's password grant (the mock accepts `mock-current-password`
  // for any login it knows). It is what closes the hole a stolen session would otherwise have.
  await page.goto(`${appUrl}/settings`, { waitUntil: 'load' });
  await page.waitForTimeout(4000);
  check('Settings offers the current-password field when nothing is owed',
    (await page.locator('#current-password-field input').count()) === 1);
  await page.fill('#new-password-field input', `Chosen-${stamp}!`);
  await page.fill('#confirm-password-field input', `Chosen-${stamp}!`);
  await page.click('text=Set my password');
  await page.waitForTimeout(1500);
  check('a chosen change without it is refused', await hasText('Enter your current password'));
  await page.fill('#current-password-field input', 'not-the-password');
  await page.click('text=Set my password');
  await page.waitForSelector('text=not your current password', { timeout: 20000 }).catch(() => {});
  check('and a wrong one is refused by the check', await hasText('not your current password'));
  await page.fill('#current-password-field input', 'mock-current-password');
  await page.click('text=Set my password');
  await page.waitForSelector('text=Your password is set', { timeout: 20000 }).catch(() => {});
  check('the right one is accepted', await hasText('Your password is set'));

  check('no page errors', errors.length === 0, JSON.stringify(errors));

  await browser.close();
  await api('DELETE', '/api/users', { id: `student_profile:${pk}` });
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
