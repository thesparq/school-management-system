// The password-change requirement as the person meets it, in Chromium: an account created with a
// password the admin chose signs in, and the app takes them to Settings and keeps them there — the
// sidebar offers nothing else, the form is the only thing that writes, and the school's data is refused
// until they set a password of their own (see `db/schema-v15` and `password_change_cleared!` in main.roc).
//
// A password that lands ends the session that set it: the app signs the person out (Authentik's own
// session, so the next sign-in is a sign-in) and they come back in with the new password. The suite
// reads that from the intercepted end-session request, from the browser's stored token, and — the part
// that matters — by entering the app again afterwards and finding it open.
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
  // The sign-out the app performs when a password lands. It is a real navigation to Authentik's
  // end-session endpoint, so it is intercepted and answered here: the browser never leaves, and what
  // the app asked the provider for is read back from the intercepted request.
  const signoutUrls = [];
  await page.route('**/application/o/school-management-system/end-session/**', route => {
    signoutUrls.push(route.request().url());
    return route.fulfill({ status: 200, contentType: 'text/html', body: '<p>authentik</p>' });
  });
  const hasText = (t) => page.evaluate((s) => document.body.innerText.includes(s), t);
  // The sidebar is a list of real links now, so its items live inside the `aside` (the keyboard work).
  const navLabels = () => page.$$eval('#app aside [data-nav]', els => els.map(e => e.textContent.trim()).filter(Boolean));
  // The app's own storage for this origin, read from the context rather than the page: the harness
  // seeds a token on every navigation, so a `localStorage` read on the page would see its own seed.
  const storedToken = async () => {
    const state = await ctx.storageState();
    const origin = state.origins.find(o => o.origin === appUrl) || { localStorage: [] };
    return origin.localStorage.filter(i => i.name === 'auth_token' && i.value).length;
  };

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

  // The real thing: a password of one's own — and the session that set it ends with it. The provider's
  // session is ended, not just the app's token: that is what makes the next sign-in a sign-in, rather
  // than the page walking back in through the session cookie that is still there.
  await page.fill('#new-password-field input', `My-Own-Password-${stamp}!`);
  await page.fill('#confirm-password-field input', `My-Own-Password-${stamp}!`);
  await page.click('text=Set my password');
  await page.waitForURL(u => u.href.includes('/end-session/'), { timeout: 20000 }).catch(() => {});
  check('setting one of your own ends the session', signoutUrls.length === 1, JSON.stringify(signoutUrls));
  check('and ends Authentik\'s, not just the app\'s token',
    signoutUrls.length > 0 && signoutUrls[0].includes('/application/o/school-management-system/end-session/'),
    (signoutUrls[0] || '').slice(0, 90));
  check('and comes back to this origin\'s callback',
    decodeURIComponent(signoutUrls[0] || '').includes(`${appUrl}/auth/callback`));
  check('the token is gone from storage', (await storedToken()) === 0);

  // Back in with the password just set — which is the point of signing out at all — and the app opens
  // up rather than holding the person on Settings, because the write cleared the requirement.
  await page.goto(`${appUrl}/`, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  const after = await navLabels();
  check('and signing in again opens the app', after.includes('My Subjects') && !after.includes('Settings only'), JSON.stringify(after));

  // And the data the requirement was holding is open.
  await page.click('#app aside [data-nav]:has-text("My Subjects")');
  await page.waitForTimeout(3500);
  check('and the pages work again', await page.evaluate(() => !document.body.innerText.includes('password_change_required')), page.url());

  // --- A change the person chose: the current password is asked, and checked by Authentik ---
  // Nothing is owed now, so this is the voluntary path: the form gains the current-password field and the
  // backend verifies it through the provider's password grant (the mock accepts `mock-current-password`
  // for any login it knows). It is what closes the hole a stolen session would otherwise have.
  await page.goto(`${appUrl}/settings`, { waitUntil: 'load' });
  await page.waitForTimeout(4000);
  // --- The read-only details card above the form ---
  // The school's record of the person, as disabled inputs: the page looks like the app's other forms and shows
  // at a glance that none of it is the person's to edit. A student's rows here are the class and the number the
  // school gave them.
  check('the details card is on the page', await hasText('Your details'));
  const fieldValue = (id) => page.$eval(`#${id} input`, el => el.value);
  const fieldDisabled = (id) => page.$eval(`#${id} input`, el => el.disabled);
  check('with the person\'s name', (await fieldValue('profile-name')) === 'Pw Browser' + stamp, await fieldValue('profile-name'));
  check('their own address', (await fieldValue('profile-email')) === `pw_browser_${stamp}@example.com`, await fieldValue('profile-email'));
  check('their class, in the school\'s words', (await fieldValue('profile-class')) === 'JSS 1', await fieldValue('profile-class'));
  check('and every one of those fields is read-only',
    (await fieldDisabled('profile-name')) && (await fieldDisabled('profile-email')) && (await fieldDisabled('profile-class')));

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
  await page.waitForURL(u => u.href.includes('/end-session/'), { timeout: 20000 }).catch(() => {});
  check('the right one is accepted, and a change you chose signs you out too',
    signoutUrls.length === 2, JSON.stringify(signoutUrls));
  check('with the token gone from storage as well', (await storedToken()) === 0);

  check('no page errors', errors.length === 0, JSON.stringify(errors));

  await browser.close();
  await api('DELETE', '/api/users', { id: `student_profile:${pk}` });
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
