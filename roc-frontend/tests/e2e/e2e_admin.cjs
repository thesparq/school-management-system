// Admin user management against a *sandbox* backend (see README.md): creates a student through the form,
// checks the new account shows up, and checks a validation error reaches the UI. The create now carries
// a generated password: Generate fills the field, the create lands, and the one-time credentials panel
// hands over the address and the (once-visible) password with a copy button.
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
  await page.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: `Bearer ${process.env.AUTH_TOKEN || 'dev-skip'}` },
  }));

  await page.goto(`${appUrl}/admin/users`, { waitUntil: 'load' });
  await page.waitForSelector('text=Add New User', { timeout: 45000 });
  check('user management page loads', true);

  const surname = `Nwosu${stamp % 10000}`;
  const fill = (placeholder, value) => page.locator(`input[placeholder="${placeholder}"]`).fill(value);
  await fill('e.g. Adamu', 'Grace');
  await fill('e.g. Ibrahim', 'Chioma');
  await fill('e.g. Musa', surname);
  await fill('e.g. adamu@johnethel.school', `grace${stamp}@example.com`);
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
  const panelText = await page.evaluate(() => {
    const els = [...document.querySelectorAll('#app div')];
    const panel = els.find(d => d.innerText && d.innerText.includes('copy the credentials to hand over') && d.querySelector('button'));
    return panel ? panel.innerText : '';
  });
  check('the credentials panel hands over the account once',
    panelText.includes(`grace${stamp}@example.com`) && panelText.includes(generated), '');
  await page.click('text=Copy credentials');
  await page.waitForSelector('text=Copied!', { timeout: 5000 }).catch(() => {});
  check('copy reports Copied', await page.evaluate(() => document.body.innerText.includes('Copied!')));
  const clip = await page.evaluate(async () => {
    try { return await navigator.clipboard.readText(); } catch (e) { return ''; }
  });
  check('the clipboard holds the address and the password',
    clip === `grace${stamp}@example.com\n${generated}`, JSON.stringify(clip));
  await page.waitForTimeout(2500);
  check('created student appears in the table', await page.evaluate((s) => document.body.innerText.includes(s), surname));

  // A form value that would corrupt the hand-written JSON (or the "|"-separated row format Edit
  // prefills from) is refused up front: a double quote in a name must surface as the form's own
  // message rather than a stored-silently-truncated value.
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
