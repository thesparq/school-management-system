// Admin user management against a *sandbox* backend (see README.md): creates a student through the form
// (with no address at all — the number the school issues is their login), checks the new account shows
// up, and checks a validation error reaches the UI. The create carries a generated password: Generate
// fills the field, the create lands, and the one-time credentials panel hands over the number and the
// (once-visible) password with a copy button.
//
//   node tests/e2e/e2e_admin.cjs

const { chromium } = require('playwright');

const appUrl = process.env.APP_URL || 'http://127.0.0.1:8000';
const stamp = Date.now();

const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const token = `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({
  iss: 'https://auth.johnethel.school/application/o/school-management-system/',
  exp: Math.floor(Date.now() / 1000) + 3600,
  email: 'bursar@example.com', name: 'Admin User', groups: ['administrators'],
})}.sig`;

const results = [];
const check = (name, ok, extra = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); };

(async () => {
  const browser = await chromium.launch({ channel: 'chromium' });
  const ctx = await browser.newContext();
  // The copy button uses the async clipboard API; read permission lets the suite verify the
  // clipboard's contents rather than only the button's feedback.
  await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: appUrl });
  await ctx.addInitScript(t => localStorage.setItem('auth_token', t), token);
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message.slice(0, 60)));
  const hasText = (t) => page.evaluate((s) => document.body.innerText.includes(s), t);
  const cardTitle = () => page.locator('#app h3').first().innerText();
  await page.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: `Bearer ${process.env.AUTH_TOKEN || 'dev-skip'}` },
  }));

  await page.goto(`${appUrl}/admin/users`, { waitUntil: 'load' });
  await page.waitForSelector('text=Add New User', { timeout: 45000 });
  check('user management page loads', true);

  const surname = `Nwosu${stamp % 10000}`;
  const fill = (placeholder, value) => page.locator(`input[placeholder="${placeholder}"]`).fill(value);
  const openAddModal = async () => {
    await page.click('#app button:has-text("Add New User")');
    await page.waitForFunction(() => (document.querySelector('#app h3') || {}).textContent === 'Add New User', null, { timeout: 10000 }).catch(() => {});
  };
  await openAddModal();
  check('the form opens in a modal', (await page.locator('#app h3').first().innerText()) === 'Add New User');
  // The login is the school's own number, drawn by the write that makes the account: the form shows the
  // field read-only and empty until then, because nothing on the page can know the number in advance.
  const emptyLogin = await page.evaluate(() => {
    const el = document.querySelector('#new-user-login-field input');
    return el ? { disabled: el.disabled === true, value: el.value } : null;
  });
  check('the number field is there, empty and not the form\'s to set',
    !!emptyLogin && emptyLogin.disabled && emptyLogin.value === '', JSON.stringify(emptyLogin));
  await fill('e.g. Adamu', 'Grace');
  await fill('e.g. Ibrahim', 'Chioma');
  await fill('e.g. Musa', surname);
  // No address at all: a pupil's login is the number the school gives them, and nothing in this
  // deployment sends mail. (A parent is the one role whose address is required — it is their login.)
  await page.selectOption('#new-user-class-level', 'class_levels:jss_2');
  await fill('https://...', 'https://example.com/grace.jpg');
  await page.locator('input[type="date"]').fill('2011-09-14');
  // The password half of the form: Generate fills the field, and the created account's credentials
  // come back once, in the panel, with a copy button.
  await page.click('text=Generate');
  const generated = await page.locator('#new-user-password-field input').inputValue();
  check('Generate fills a password field', generated.length >= 12, `len=${generated.length}`);
  await page.click('text=Create User');
  await page.waitForSelector('text=User created', { timeout: 20000 }).catch(() => {});
  check('form submit reports success', await page.evaluate(() => document.body.innerText.includes('User created')));
  check('the modal closes after the write', (await page.locator('#app h3').count()) === 0);
  const panelText = await page.evaluate(() => {
    const els = [...document.querySelectorAll('#app div')];
    const panel = els.find(d => d.innerText && d.innerText.includes('copy the credentials to hand over') && d.querySelector('button'));
    return panel ? panel.innerText : '';
  });
  const loginMatch = panelText.match(/JES-\d{6}/);
  check('the credentials panel hands over the login the school issued', !!loginMatch, panelText.slice(0, 160));
  check('and the once-visible password with it', panelText.includes(generated), '');
  await page.click('text=Copy credentials');
  await page.waitForSelector('text=Copied!', { timeout: 5000 }).catch(() => {});
  check('copy reports Copied', await page.evaluate(() => document.body.innerText.includes('Copied!')));
  const clip = await page.evaluate(async () => {
    try { return await navigator.clipboard.readText(); } catch (e) { return ''; }
  });
  check('the clipboard holds the login and the password',
    clip === `${loginMatch ? loginMatch[0] : '?'}\n${generated}`, JSON.stringify(clip));
  await page.waitForTimeout(2500);
  check('created student appears in the table', await page.evaluate((s) => document.body.innerText.includes(s), surname));
  check('and its row shows the same number as its login', await page.evaluate((n) => document.body.innerText.includes(n), loginMatch ? loginMatch[0] : '?'), loginMatch ? loginMatch[0] : 'no number in the panel');

  // The row's own Edit form shows that login, read-only: it is the account's identity, and the school is
  // what issues it. Then the row's Reset password action, which switches the same modal to its
  // password-only mode and names the account by that login rather than by an address it may not have.
  await page.locator('#app table tbody tr', { hasText: surname }).locator('button', { hasText: 'Edit' }).click();
  await page.waitForFunction(() => (document.querySelector('#app h3') || {}).textContent === 'Edit User', null, { timeout: 10000 }).catch(() => {});
  const editLogin = await page.evaluate(() => {
    const el = document.querySelector('#new-user-login-field input');
    return el ? { disabled: el.disabled === true, value: el.value } : null;
  });
  check('the Edit form shows the number the account signs in with, still read-only',
    !!editLogin && editLogin.disabled && editLogin.value === (loginMatch ? loginMatch[0] : '?'), JSON.stringify(editLogin));
  // Closed the way a person would close it: a click on the dark backdrop. (The row's own actions sit
  // under that backdrop, so this also has to happen before the next one is clicked.)
  await page.mouse.click(5, 5);
  await page.waitForFunction(() => (document.querySelector('#app h3') || {}).textContent !== 'Edit User', null, { timeout: 10000 }).catch(() => {});
  check('and the backdrop closes the modal again', (await page.locator('#app h3').count()) === 0);

  // The row's Reset password action: the modal switches to its password-only mode, names the account by
  // its login (the number, not an address a pupil may not have), the new value is handed over once
  // through the same credentials panel, and Authentik's set-password answers 200.
  await page.locator('#app table tbody tr', { hasText: surname }).locator('button', { hasText: 'Reset password' }).click();
  await page.waitForFunction(() => (document.querySelector('#app h3') || {}).textContent === 'Reset password', null, { timeout: 10000 }).catch(() => {});
  check('Reset password opens the password-only modal', (await cardTitle()) === 'Reset password', await cardTitle());
  check('and the modal names the account by its login, not an address', await page.evaluate((n) => {
    const card = document.querySelector('#app [data-close-input] > div');
    return !!card && card.innerText.includes('Login') && card.innerText.includes(n);
  }, loginMatch ? loginMatch[0] : '?'), loginMatch ? loginMatch[0] : 'no login');
  await page.click('text=Generate');
  const resetPw = await page.locator('#new-user-password-field input').inputValue();
  check('Generate fills the reset field too', resetPw.length >= 12, `len=${resetPw.length}`);
  // Exact match: a bare substring would hit every row's "Reset password" button instead.
  await page.getByRole('button', { name: 'Set password', exact: true }).click();
  await page.waitForSelector('text=Password updated', { timeout: 20000 }).catch(() => {});
  check('the reset reports Password updated', await hasText('Password updated'));
  check('and hands the new password over once', await page.evaluate((e) => {
    const els = [...document.querySelectorAll('#app div')];
    const panel = els.find(d => d.innerText && d.innerText.includes('copy the credentials to hand over'));
    return !!(panel && panel.innerText.includes(e));
  }, resetPw));

  // A form value that would corrupt the hand-written JSON (or the "|"-separated row format Edit
  // prefills from) is refused up front: a double quote in a name must surface as the form's own
  // message rather than a stored-silently-truncated value.
  await openAddModal();
  await fill('e.g. Adamu', 'A"da');
  await fill('e.g. Musa', `Quote${stamp % 10000}`);
  await fill('e.g. adamu@johnethel.school', `quote${stamp}@example.com`);
  await fill('https://...', 'https://example.com/quote.jpg');
  await page.click('text=Create User');
  await page.waitForSelector('text=may not contain double quotes', { timeout: 20000 }).catch(() => {});
  check('a quoted value is refused before it is sent', await page.evaluate(() => document.body.innerText.includes('may not contain double quotes, backslashes, pipes or line breaks')));

  // Validation path: a second submit without a passport URL.
  await fill('e.g. Adamu', 'No');
  await fill('e.g. Musa', `Passport${stamp % 10000}`);
  await fill('e.g. adamu@johnethel.school', `nopassport${stamp}@example.com`);
  await fill('https://...', '');
  await page.click('text=Create User');
  await page.waitForSelector('text=passport is required', { timeout: 20000 }).catch(() => {});
  check('validation error surfaces in the UI', await page.evaluate(() => document.body.innerText.includes('passport is required')));

  check('no page errors', errors.length === 0, JSON.stringify(errors));

  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
