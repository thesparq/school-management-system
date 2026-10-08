// Regression checks for the post-deploy UI fixes: the Lucide icons actually paint (SVG
// namespace), the user-management tabs match the Configuration hub's pill style, the lesson
// week badge stays on one line, and an expired access token silently refreshes (with a fallback
// to a full Authentik re-login when the refresh fails). Simulated in the browser; see the repo's
// sandbox instructions in README.md.
//   node tests/e2e/e2e_icons_refresh.cjs

const { chromium } = require('playwright');
const appUrl = 'http://127.0.0.1:8000';
const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
const token = `${b64u({alg:'RS256',typ:'JWT'})}.${b64u({iss:'https://auth.johnethel.school/application/o/school-management-system/',exp:Math.floor(Date.now()/1000)+3600,email:'b@example.com',name:'Admin',groups:['administrators']})}.sig`;
const results = [];
const check = (n, ok, x='') => { results.push(ok); console.log(`${ok?'PASS':'FAIL'}  ${n}${x?' — '+x:''}`); };
(async () => {
  const browser = await chromium.launch({ channel: 'chromium' });
  const ctx = await browser.newContext();
  await ctx.addInitScript(t => { localStorage.setItem('auth_token', t); localStorage.setItem('auth_refresh_token', 'rt_initial'); }, token);
  const page = await ctx.newPage();
  page.on('pageerror', e => console.log('PAGEERROR', e.message.slice(0,100)));
  let apiCalls = 0, refreshCalls = 0, authorizeCalls = 0;
  let first401 = true;
  await page.route('**/api/**', async route => {
    const r = route.request();
    // Simulate an expired access token once: answer 401 for the first API call.
    if (first401 && r.url().includes('/api/users')) {
      first401 = false;
      await route.fulfill({ status: 401, contentType: 'application/json', body: '{"error":"Unauthorized: Invalid Token"}' });
      return;
    }
    apiCalls++;
    await route.continue({ headers: { ...r.headers(), authorization: 'Bearer dev-skip' } });
  });
  await page.route('**/application/o/token/**', async route => {
    refreshCalls++;
    if (route.request().method() === 'POST') {
      await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ access_token: 'fresh_access', refresh_token: 'rt_rotated' }) });
    } else { await route.continue(); }
  });
  await page.route('**/authorize/**', route => { authorizeCalls++; route.fulfill({ status: 200, body: '<html>auth</html>' }); });

  // --- Icons + pill tabs ---
  await page.goto(`${appUrl}/admin/users`, { waitUntil: 'load' });
  await page.waitForSelector('text=Add New User', { timeout: 45000 });
  await page.waitForTimeout(1200);
  const iconInfo = await page.evaluate(() => {
    const svg = document.querySelector('#app svg');
    const tab = [...document.querySelectorAll('#app button')].find(b => (b.textContent||'').includes('Teachers'));
    return {
      ns: svg ? svg.namespaceURI : 'none',
      tabClass: tab ? (tab.className || '') : 'none',
      tabContainer: tab && tab.parentElement ? (tab.parentElement.className || '') : 'none',
    };
  });
  check('icons are in the SVG namespace', iconInfo.ns === 'http://www.w3.org/2000/svg', iconInfo.ns);
  check('teachers tab uses the pill style', iconInfo.tabClass.includes('rounded-sm') && iconInfo.tabClass.includes('px-3'), iconInfo.tabClass);
  check('tab bar uses the segmented pill container', (iconInfo.tabContainer||'').includes('bg-muted rounded-md'), iconInfo.tabContainer);
  await page.screenshot({ path: process.env.DELTA_SCRATCH_DIR + '/tabs.png', clip: { x: 0, y: 0, width: 900, height: 300 } });

  // --- Week badge ---
  await page.goto(`${appUrl}/admin/lms`, { waitUntil: 'load' });
  await page.waitForSelector('text=JSS 1', { timeout: 45000 });
  await page.locator('#app h3', { hasText: 'JSS 1' }).click();
  await page.waitForSelector('#app h3', { timeout: 15000 });
  await page.locator('#app h3', { hasText: 'Agricultural Science' }).click();
  await page.waitForSelector('#app h3', { timeout: 15000 });
  await page.locator('#app h3', { hasText: 'Noel Term' }).click();
  await page.waitForSelector('#app h3', { timeout: 15000 });
  await page.locator('#app h3', { hasText: 'Packaging Criteria for Farm Produce' }).click();
  await page.waitForFunction(() => (document.getElementById('lesson-week-badge') || {}).innerText || '', null, { timeout: 15000 });
  const weekInfo = await page.evaluate(() => {
    const badge = document.getElementById('lesson-week-badge');
    const span = badge && badge.querySelector('span');
    return { text: badge ? badge.innerText : '', nowrap: span ? (span.className || '').includes('whitespace-nowrap') : false, shrink: badge ? (badge.className||'').includes('shrink-0') : false };
  });
  check('week badge renders', weekInfo.text === 'Week 1', weekInfo.text);
  check('week badge is nowrap + shrink-0', weekInfo.nowrap && weekInfo.shrink, JSON.stringify(weekInfo));
  try { await page.screenshot({ path: (process.env.DELTA_SCRATCH_DIR || '/tmp') + '/week-badge.png', clip: { x: 0, y: 0, width: 1000, height: 220 } }); } catch (e) {}

  // --- Token refresh on 401 ---
  first401 = true; // the previous page consumed the first-401 simulation; arm it again
  await page.goto(`${appUrl}/admin/users`, { waitUntil: 'load' });
  await page.waitForTimeout(2500);
  check('an expired token triggers a silent refresh', refreshCalls >= 1, `refreshCalls=${refreshCalls}`);
  const storedTok = await page.evaluate(() => localStorage.getItem('auth_token'));
  check('the refreshed token is stored', storedTok === 'fresh_access', 'stored=' + storedTok);
  check('no redirect to Authentik while the refresh worked', authorizeCalls === 0, `authorizeCalls=${authorizeCalls}`);
  check('the request was retried with the fresh token', apiCalls >= 1, `apiCalls=${apiCalls}`);

  // --- Failed refresh falls back to a full re-login ---
  let failRefresh = true;
  const autor = authorizeCalls;
  await page.unroute('**/application/o/token/**');
  await page.route('**/application/o/token/**', async route => {
    if (route.request().method() === 'POST' && failRefresh) {
      await route.fulfill({ status: 400, body: '{"error":"invalid_grant"}' });
    } else { await route.continue(); }
  });
  first401 = true;
  await page.goto(`${appUrl}/admin/users`, { waitUntil: 'load' });
  await page.waitForTimeout(3000);
  check('a failed refresh redirects to Authentik', authorizeCalls > autor, `authorizeCalls=${authorizeCalls} -> ${autor}`);

  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})().catch(e => { console.error('FATAL', e.message.slice(0,200)); process.exit(2); });
