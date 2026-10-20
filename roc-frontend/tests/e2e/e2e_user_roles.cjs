// Browser checks for the admin user management's role-tailored form and list, against a
// *sandbox* backend (see README.md): one modal whose fields follow the picked role (a teacher's
// date employed and qualifications, a parent's linked students, an administrator's type and
// permissions, a student's date of birth and class), and a table whose extra column is that
// role's own (a student's class, a parent's students, an administrator's type). Also the modal's
// own behaviour: a blurred backdrop, and a click on it cancels the form without a write.
//
// Needs playwright + chromium (the same install the other e2e suites require):
//   cd roc-frontend && npm i -D playwright && npx playwright install chromium
//   node tests/e2e/e2e_user_roles.cjs

const { chromium } = require('playwright');

const appUrl = process.env.APP_URL || 'http://127.0.0.1:8000';
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
  await ctx.addInitScript(t => localStorage.setItem('auth_token', t), token);
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message.slice(0, 120)));
  await page.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: `Bearer ${process.env.AUTH_TOKEN || 'dev-skip'}` },
  }));
  const hasText = (t) => page.evaluate((s) => document.body.innerText.includes(s), t);
  // The table's column headings, read off the header row rather than the whole page (the modal and
  // the config cards both print many of the same words).
  const headers = () => page.$$eval('#app table thead th', els => els.map(e => e.textContent.trim()).filter(Boolean));
  const openModal = async () => {
    await page.click('#app button:has-text("Add New User")');
    await page.waitForFunction(() => (document.querySelector('#app h3') || {}).textContent === 'Add New User', null, { timeout: 10000 }).catch(() => {});
  };
  const pickRole = async (role) => {
    await page.selectOption('#new-user-role-select', role);
    await page.waitForTimeout(200);
  };

  await page.goto(`${appUrl}/admin/users`, { waitUntil: 'load' });
  await page.waitForSelector('text=Add New User', { timeout: 45000 });

  // --- The list's per-role column ---
  await page.waitForTimeout(1500);
  const studentHeaders = await headers();
  check('the students table carries a Class column', studentHeaders.includes('Class'), JSON.stringify(studentHeaders));

  await page.click('#app button:has-text("Teachers")');
  await page.waitForTimeout(1200);
  const teacherHeaders = await headers();
  check('and still the school number and status every tab shares',
    teacherHeaders.includes('School number') && teacherHeaders.includes('Status'), JSON.stringify(teacherHeaders));
  check('the teachers table adds no per-role column of its own',
    !teacherHeaders.includes('Class') && !teacherHeaders.includes('Students') && !teacherHeaders.includes('Admin type'), JSON.stringify(teacherHeaders));

  await page.click('#app button:has-text("Parents")');
  await page.waitForTimeout(1200);
  check('the parents table adds a Students column', (await headers()).includes('Students'), JSON.stringify(await headers()));

  await page.click('#app button:has-text("Administrators")');
  await page.waitForTimeout(1200);
  check('the administrators table adds an Admin type column', (await headers()).includes('Admin type'), JSON.stringify(await headers()));

  // --- The modal's fields follow the picked role ---
  await page.click('#app button:has-text("Students")');
  await page.waitForTimeout(800);
  await openModal();
  check('the backdrop blurs what is behind the modal', await page.evaluate(() => {
    const overlay = document.querySelector('#app div.fixed.inset-0');
    return !!overlay && getComputedStyle(overlay).backdropFilter.includes('blur');
  }));
  check('a student\'s form asks for date of birth and class level',
    (await hasText('Date of birth')) && (await hasText('Class level')));

  await pickRole('Teacher');
  check('a teacher\'s form asks for date employed', await hasText('Date employed'));
  check('and offers the qualifications picker', await hasText('Qualifications'));
  check('and asks for neither date of birth nor class level',
    !(await hasText('Date of birth')) && !(await hasText('Class level')));

  await pickRole('Parent');
  check('a parent\'s form offers the linked-students picker', await hasText('Linked students'));
  check('with a search box for the student list', await page.locator('input[placeholder="Search students..."]').count() === 1);
  check('and asks for no teacher fields', !(await hasText('Date employed')));

  await pickRole('Admin');
  check('an administrator\'s form asks for an admin type', (await page.locator('#new-user-admin-type-select').count()) === 1);
  check('and shows the permissions panel with the school\'s own wording',
    (await hasText('Permissions')) && (await hasText('Manage users')) && (await hasText('Manage school setup')));
  check('and asks for no parent fields', !(await hasText('Linked students')));

  // --- The backdrop cancels without a write ---
  let wrote = false;
  page.on('request', r => { if (r.method() === 'POST' && r.url().includes('/api/users')) wrote = true; });
  await page.mouse.click(8, 8);
  await page.waitForTimeout(600);
  check('a click on the backdrop closes the modal', (await page.locator('#app h3').count()) === 0);
  check('and it wrote nothing', !wrote);

  check('no page errors', errors.length === 0, JSON.stringify(errors));

  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
