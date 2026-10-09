// Regression checks for the live reports: a student's subject list renders on first in-app
// navigation (no reload), the boot fetches are scoped by role (no 403 noise for students), the
// authorize request carries offline_access (the refresh token), and the lesson section navigator
// exists on the admin LMS view and stays open while the pointer is inside its box.
//   node tests/e2e/e2e_nav_fixes.cjs

const { chromium } = require('playwright');
const appUrl = 'http://127.0.0.1:8000';
const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
const mk = (groups, name) => `${b64u({alg:'RS256',typ:'JWT'})}.${b64u({iss:'https://auth.johnethel.school/application/o/school-management-system/',exp:Math.floor(Date.now()/1000)+3600,email:name+'@example.com',name,groups})}.sig`;
const results = [];
const check = (n, ok, x='') => { results.push(ok); console.log(`${ok?'PASS':'FAIL'}  ${n}${x?' — '+x:''}`); };
(async () => {
  const browser = await chromium.launch({ channel: 'chromium' });
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  page.on('pageerror', e => console.log('PAGEERROR', e.message.slice(0,100)));
  const statuses = [];
  let authorizeScope = '';
  await page.route('**/application/o/authorize/**', route => { authorizeScope = decodeURIComponent(route.request().url().split('scope=')[1] || '').split('&')[0]; route.fulfill({ status: 200, body: '<html>x</html>' }); });
  await page.route('**/api/**', route => {
    const r = route.request();
    statuses.push(r.url().split('?')[0].replace(appUrl, '') + ':' + r.method());
    route.continue({ headers: { ...r.headers(), authorization: 'Bearer dev-student' } });
  });
  ctx.on('response', r => statuses.push(String(r.status())));

  await ctx.addInitScript(t => localStorage.setItem('auth_token', t), mk(['students'], 'Student'));
  await page.goto(`${appUrl}/`, { waitUntil: 'load' });
  await page.waitForSelector('#app', { timeout: 45000 });
  await page.waitForTimeout(1500);
  await page.click('aside >> text="My Subjects"');
  await page.waitForSelector('text=Agricultural Science', { timeout: 20000 }).catch(() => {});
  check('student subjects render after clicking My Subjects (no reload)', await page.evaluate(() => document.body.innerText.includes('Agricultural Science')));
  check('student session made no 403 responses', !statuses.some(s => s === '403'), JSON.stringify(statuses.slice(0, 10)));
  await ctx.addInitScript(() => localStorage.clear());
  await page.goto(`${appUrl}/`, { waitUntil: 'load' });
  await page.waitForTimeout(1500);
  check('the authorize request carried offline_access', authorizeScope.includes('offline_access'), authorizeScope);

  const adminToken = mk(['administrators'], 'Admin');
  await ctx.addInitScript(t => localStorage.setItem('auth_token', t), adminToken);
  await page.route('**/api/**', route => route.continue({ headers: { ...route.request().headers(), authorization: 'Bearer dev-skip' } }));
  await page.goto(`${appUrl}/admin/lms`, { waitUntil: 'load' });
  await page.waitForSelector('text=JSS 1', { timeout: 45000 });
  await page.locator('#app h3', { hasText: 'JSS 1' }).click();
  await page.waitForSelector('#app h3', { timeout: 15000 });
  await page.locator('#app h3', { hasText: 'Agricultural Science' }).click();
  await page.waitForSelector('#app h3', { timeout: 15000 });
  await page.locator('#app h3', { hasText: 'Noel Term' }).click();
  await page.waitForSelector('#app h3', { timeout: 15000 });
  await page.locator('#app h3', { hasText: 'Packaging Criteria for Farm Produce' }).click();
  await page.waitForFunction(() => document.querySelectorAll('#section-nav-dots .nav-dot').length > 0, null, { timeout: 15000 });
  check('admin lesson view has the section navigator', await page.evaluate(() => document.getElementById('section-nav-dots') && document.getElementById('section-nav-dots').children.length >= 3));
  const dots = page.locator('#section-nav-dots .nav-dot').first();
  const bbox = await dots.boundingBox();
  await page.mouse.move(bbox.x + bbox.width / 2, bbox.y + bbox.height / 2);
  await page.waitForTimeout(400);
  const panelBox = await page.locator('#section-nav-panel').boundingBox();
  await page.mouse.move(panelBox.x + panelBox.width / 2, panelBox.y + panelBox.height / 2);
  await page.waitForTimeout(400);
  const opacity = await page.locator('#section-nav-panel').evaluate(el => getComputedStyle(el).opacity);
  check('the nav box stays open while the pointer is inside it', Number(opacity) > 0.5, 'opacity=' + opacity);
  const label = page.locator('#section-nav-labels .nav-label').last();
  await label.click({ trial: true });
  const afterClick = await page.locator('#section-nav-panel').evaluate(el => getComputedStyle(el).opacity);
  check('a label inside the box is clickable and the box stays open', Number(afterClick) > 0.5, 'opacity=' + afterClick);

  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})().catch(e => { console.error('FATAL', e.message.slice(0,200)); process.exit(2); });
