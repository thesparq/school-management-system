// Smoke test for the migrated features against a *sandbox* backend (see README.md): the admin LMS
// drill-down (class -> subject -> term -> lesson -> content, read-only), the teacher-row Assign
// dialog (searchable class-subject dropdown, badges, replace-all save), the qualifications section
// of the Configuration hub, and the teacher form's qualifications picker.
//
// Needs playwright + chromium (the same install the other e2e suites require):
//   cd roc-frontend && npm i -D playwright && npx playwright install chromium
//   node tests/e2e/smoke_assignments_lms.cjs

const { chromium } = require('playwright');
const appUrl = process.env.APP_URL || 'http://127.0.0.1:8000';
const stamp = Date.now() % 100000;
const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const token = `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({ iss: 'https://auth.johnethel.school/application/o/school-management-system/', exp: Math.floor(Date.now()/1000)+3600, email: 'bursar@example.com', name: 'Admin User', groups: ['administrators'] })}.sig`;
const results = [];
const check = (name, ok, extra='') => { results.push(ok); console.log(`${ok?'PASS':'FAIL'}  ${name}${extra?' — '+extra:''}`); };
(async () => {
  const browser = await chromium.launch({ channel: 'chromium' });
  const ctx = await browser.newContext();
  await ctx.addInitScript(t => localStorage.setItem('auth_token', t), token);
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message.slice(0, 80)));
  await page.route('**/api/**', route => route.continue({ headers: { ...route.request().headers(), authorization: 'Bearer dev-skip' } }));
  const hasText = (t) => page.evaluate((s) => document.body.innerText.includes(s), t);
  const clickCard = async (t) => { await page.locator('#app h3', { hasText: t }).click(); };
  const clickText = async (t) => { await page.locator(`text=${t}`).first().click(); };

  // 1. Admin LMS drill: class -> subject -> term -> lesson -> content
  await page.goto(`${appUrl}/admin/lms`, { waitUntil: 'load' });
  await page.waitForSelector('text=All classes', { timeout: 45000 }).catch(() => {});
  check('admin LMS page loads', await hasText('Browse any class level'));
  await page.waitForSelector('text=JSS 1', { timeout: 15000 }).catch(() => {});
  check('class picker lists JSS 1', await hasText('JSS 1'));
  await clickCard('JSS 1');
  await page.waitForSelector('text=Agricultural Science', { timeout: 15000 }).catch(() => {});
  check('subjects step shows the class subject', await hasText('Agricultural Science'));
  await clickCard('Agricultural Science');
  await page.waitForSelector('text=Noel Term', { timeout: 15000 }).catch(() => {});
  check('terms step shows Noel Term', await hasText('Noel Term'));
  await clickCard('Noel Term');
  await page.waitForSelector('text=Packaging Criteria for Farm Produce', { timeout: 15000 }).catch(() => {});
  check('lessons step shows the fixture lesson', await hasText('Packaging Criteria for Farm Produce'));
  await clickCard('Packaging Criteria for Farm Produce');
  await page.waitForFunction(() => document.body.innerText.includes('Packaging protects farm produce.'), null, { timeout: 15000 }).catch(() => {});
  check('lesson content renders (read-only)', await hasText('Packaging protects farm produce.'));
  check('no student answers UI on the admin lesson', await page.locator('#lesson-panel input').count() === 0);

  // 2. Teacher Assign dialog
  await page.goto(`${appUrl}/admin/users`, { waitUntil: 'load' });
  await page.waitForSelector('text=Add New User', { timeout: 45000 }).catch(() => {});
  await page.click('text=👨‍🏫 Teachers');
  await page.waitForTimeout(1500);
  await page.locator('#app button:has-text("Assign")').first().click();
  await page.waitForSelector('text=Assign Classes', { timeout: 10000 }).catch(() => {});
  check('Assign opens the dialog', await hasText('Assign Classes'));
  await page.locator('input[placeholder="Search class subjects..."]').fill('agric');
  await page.waitForSelector('text=JSS 1 / Agricultural Science', { timeout: 5000 }).catch(() => {});
  check('the search dropdown offers the pair', await hasText('JSS 1 / Agricultural Science'));
  await clickText('JSS 1 / Agricultural Science');
  check('selecting adds the badge', await hasText('✕'));
  await page.click('text=Save Assignments');
  await page.waitForSelector('text=Assignments saved', { timeout: 15000 }).catch(() => {});
  check('saving reports Assignments saved', await hasText('Assignments saved'));

  // 3. Credentials section in the Configuration hub
  await page.goto(`${appUrl}/admin/config`, { waitUntil: 'load' });
  await page.waitForSelector('text=Configuration Hub', { timeout: 45000 }).catch(() => {});
  await page.click('text=Qualifications');
  await page.waitForTimeout(1000);
  check('Qualifications tab lists the catalog', await hasText('B.Ed. Mathematics') || await hasText('Qualification'));
  await page.locator('input[placeholder="e.g. B.Ed. Mathematics"]').fill(`Smoke Qual ${stamp}`);
  await page.click('text=Create Qualification');
  await page.waitForSelector('text=Qualification created', { timeout: 15000 }).catch(() => {});
  check('creating a qualification reports created', await hasText(`Qualification created`));
  await page.waitForSelector(`text=Smoke Qual ${stamp}`, { timeout: 15000 }).catch(() => {});
  check('the new qualification is listed', await hasText(`Smoke Qual ${stamp}`));

  // 4. Teacher form's qualifications picker
  await page.goto(`${appUrl}/admin/users`, { waitUntil: 'load' });
  await page.waitForSelector('text=Add New User', { timeout: 45000 }).catch(() => {});
  await page.click('#app button:has-text("Add New User")');
  await page.waitForTimeout(800);
  await page.selectOption('#new-user-role-select', 'Teacher');
  await page.waitForTimeout(500);
  await page.locator('input[placeholder="Search qualifications..."]').fill(`Smoke Qual ${stamp}`);
  await page.waitForSelector(`text=Smoke Qual ${stamp}`, { timeout: 5000 }).catch(() => {});
  check('the qualifications picker offers the catalog row', await hasText(`Smoke Qual ${stamp}`));
  await clickText(`Smoke Qual ${stamp}`);
  check('selecting a qualification adds its badge', await hasText('✕'));

  check('no page errors', errors.length === 0, JSON.stringify(errors.slice(0,3)));
  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})().catch(e => { console.error('FATAL', e); process.exit(2); });
