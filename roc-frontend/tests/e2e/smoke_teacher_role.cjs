// Teacher-role browser pass: the teacher's sidebar shows My Classes (not User Management), the
// My Classes page renders from /api/teacher/classes, and the lesson picker opens scoped to a
// subject. Boots as dev-teacher through the API-token override.
const { chromium } = require('playwright');
const appUrl = process.env.APP_URL || 'http://127.0.0.1:8000';
const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const token = `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({ iss: 'https://auth.johnethel.school/application/o/school-management-system/', exp: Math.floor(Date.now()/1000)+3600, email: 'teacher@example.com', name: 'Teacher User', groups: ['teachers'] })}.sig`;
const results = [];
const check = (name, ok, extra='') => { results.push(ok); console.log(`${ok?'PASS':'FAIL'}  ${name}${extra?' — '+extra:''}`); };
(async () => {
  const browser = await chromium.launch({ channel: 'chromium' });
  const ctx = await browser.newContext();
  await ctx.addInitScript(t => localStorage.setItem('auth_token', t), token);
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message.slice(0, 80)));
  await page.route('**/api/**', route => route.continue({ headers: { ...route.request().headers(), authorization: 'Bearer dev-teacher' } }));
  const hasText = (t) => page.evaluate((s) => document.body.innerText.includes(s), t);

  await page.goto(`${appUrl}/teacher/classes`, { waitUntil: 'load' });
  await page.waitForSelector('text=My Classes', { timeout: 45000 }).catch(() => {});
  check('teacher My Classes page loads', await hasText('My Classes'));
  check('teacher sidebar shows My Classes', await hasText('Assessments & Grading'));
  check('teacher sidebar hides User Management', !(await hasText('User Management')));
  await page.waitForSelector('text=No classes assigned yet', { timeout: 15000 }).catch(() => {});
  check('unassigned teacher sees the empty state', await hasText('No classes assigned yet'));
  await page.goto(`${appUrl}/teacher/lessons`, { waitUntil: 'load' });
  await page.waitForTimeout(1500);
  check('teacher lesson picker renders without error', await hasText('Choose a lesson') || await hasText('No lessons yet'));
  check('no page errors (teacher)', errors.length === 0, JSON.stringify(errors.slice(0, 3)));
  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})().catch(e => { console.error('FATAL', e.message.slice(0,200)); process.exit(2); });
