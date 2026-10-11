// Browser checks for two things that share the admin LMS hub's page structure: the top-right toast
// notifications with a pausable countdown feeding the navbar bell's dropdown, and the admin LMS
// drill-down's breadcrumb/history navigation (each level is its own URL, so a crumb lands on the
// level it names and the browser's back/forward walks the drill).
//
// Needs playwright + chromium (the same install the other e2e suites require) and a sandbox
// backend (see README.md):
//   cd roc-frontend && npm i -D playwright && npx playwright install chromium
//   node tests/e2e/e2e_notifications_lms.cjs

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
  await ctx.addInitScript(t => localStorage.setItem('auth_token', t), token);
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message.slice(0, 120)));
  await page.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: `Bearer ${process.env.AUTH_TOKEN || 'dev-skip'}` },
  }));
  const hasText = (t) => page.evaluate((s) => document.body.innerText.includes(s), t);
  // The app pushes its URL from a 0ms timer, so a view can be on screen a moment before the address
  // bar catches up: wait for the URL rather than reading it straight after the click.
  const waitForUrl = (pred) => page.waitForFunction(`(${pred.toString()})(window.location.href)`, null, { timeout: 10000 }).catch(() => {});
  const barWidth = () => page.evaluate(() => {
    const el = document.querySelector('#toast-container .notification-bar');
    return el ? el.getBoundingClientRect().width : null;
  });

  // ----------------------------------------------------------------
  // 1. A write produces a toast with a countdown that pauses on hover
  // ----------------------------------------------------------------
  await page.goto(`${appUrl}/admin/config`, { waitUntil: 'load' });
  await page.waitForSelector('text=Configuration Hub', { timeout: 45000 });
  await page.locator('input[placeholder="e.g. Summer Term"]').fill(`Notify Term ${stamp}`);
  await page.locator('input[placeholder="e.g. 3"]').fill('9');
  await page.click('text=Create Term');
  await page.waitForSelector('#toast-container', { timeout: 15000 }).catch(() => {});
  check('a finished write raises a top-right toast', await page.locator('#toast-container').count() === 1);
  check('the toast carries the write\'s title and message', await page.evaluate(() => {
    const t = document.querySelector('#toast-container');
    return !!t && t.innerText.includes('Term') && t.innerText.includes('created');
  }));

  const w1 = await barWidth();
  await page.waitForTimeout(900);
  const w2 = await barWidth();
  check('the countdown bar shrinks as the toast ages', w1 !== null && w2 !== null && w2 < w1, `${w1} -> ${w2}`);

  await page.locator('#toast-container > div').first().hover();
  await page.waitForTimeout(150);
  const h1 = await barWidth();
  await page.waitForTimeout(900);
  const h2 = await barWidth();
  check('hovering pauses the countdown', h1 !== null && h2 !== null && Math.abs(h2 - h1) < 2, `${h1} -> ${h2}`);

  await page.mouse.move(10, 10);
  await page.waitForTimeout(150);
  const r1 = await barWidth();
  await page.waitForTimeout(900);
  const r2 = await barWidth();
  check('leaving resumes the countdown', r1 !== null && r2 !== null && r2 < r1, `${r1} -> ${r2}`);

  await page.waitForFunction(() => !document.querySelector('#toast-container'), null, { timeout: 8000 }).catch(() => {});
  check('the toast dismisses itself once the countdown runs out', await page.locator('#toast-container').count() === 0);

  // ----------------------------------------------------------------
  // 2. The bell keeps the history and its dropdown lists it
  // ----------------------------------------------------------------
  const badge = () => page.evaluate(() => {
    const b = document.querySelector('#notifications-bell-wrap span');
    if (!b) return null;
    const hidden = getComputedStyle(b).display === 'none';
    return hidden ? null : b.textContent;
  });
  check('the bell badge counts what dismissed toasts left behind', await badge() === '1', String(await badge()));

  await page.click('#notifications-bell-wrap button');
  await page.waitForTimeout(300);
  check('clicking the bell opens the dropdown', await page.evaluate(() => {
    const p = document.getElementById('notifications-panel');
    return !!p && !p.classList.contains('hidden');
  }));
  check('the dropdown lists the notification', await page.evaluate(() => {
    const p = document.getElementById('notifications-panel');
    return !!p && p.innerText.includes('Term');
  }));

  // Clear all empties the history through the app (the page reports it, the app renders the result).
  await page.click('text=Clear all');
  await page.waitForTimeout(400);
  check('Clear all empties the badge', await badge() === null, String(await badge()));
  await page.click('#notifications-bell-wrap button');
  await page.waitForTimeout(300);
  check('and the reopened dropdown says there is nothing yet', await page.evaluate(() => {
    const p = document.getElementById('notifications-panel');
    return !!p && !p.classList.contains('hidden') && p.innerText.includes('No notifications yet');
  }));

  // A click anywhere outside closes it (the page reports the click, the app owns the open flag).
  await page.mouse.click(20, 400);
  await page.waitForTimeout(300);
  check('a click outside closes the dropdown', await page.evaluate(() => {
    const p = document.getElementById('notifications-panel');
    return !!p && p.classList.contains('hidden');
  }));
  check('no page errors after the notification checks', errors.length === 0, JSON.stringify(errors));

  // ----------------------------------------------------------------
  // 3. The admin LMS drill: each level is a URL, so crumbs land where they say and back walks up
  // ----------------------------------------------------------------
  await page.goto(`${appUrl}/admin/lms`, { waitUntil: 'load' });
  await page.waitForSelector('text=JSS 1', { timeout: 45000 });
  check('the class picker is the first level', await hasText('Browse any class level'));

  await page.locator('#app h3', { hasText: 'JSS 1' }).click();
  await page.waitForSelector('text=Agricultural Science', { timeout: 15000 });
  await waitForUrl((u) => u.includes('class=class_levels:jss_1') && !u.includes('subject='));
  check('picking a class puts it in the URL', page.url().includes('class=class_levels:jss_1'), page.url());
  check('and shows that class\'s subjects', await hasText('Choose a subject to see its terms and lessons.'));

  await page.locator('#app h3', { hasText: 'Agricultural Science' }).click();
  await page.waitForSelector('text=Noel Term', { timeout: 15000 });
  await waitForUrl((u) => u.includes('subject=subjects:agricultural_science') && !u.includes('term='));
  check('picking a subject puts class and subject in the URL',
    page.url().includes('class=class_levels:jss_1') && page.url().includes('subject=subjects:agricultural_science'), page.url());
  check('and shows the terms', await hasText('Choose a term to view its lessons.'));

  await page.locator('#app h3', { hasText: 'Noel Term' }).click();
  await page.waitForSelector('text=Packaging Criteria for Farm Produce', { timeout: 15000 });
  await waitForUrl((u) => u.includes('term=terms:noel_term'));
  check('picking a term puts class, subject and term in the URL',
    page.url().includes('term=terms:noel_term'), page.url());
  const lessonsUrl = page.url();

  // The reported bug: from the lessons list, going up must reach the terms step, not the subjects step.
  await page.locator('#app', { hasText: 'Agricultural Science' }).locator('span', { hasText: 'Agricultural Science' }).first().click();
  await waitForUrl((u) => u.includes('subject=subjects:agricultural_science') && !u.includes('term='));
  check('the subject crumb on the lessons list lands on the terms step (not the subjects step)',
    await hasText('Choose a term to view its lessons.'), page.url());

  // The other crumbs land on their own level, not just one step up.
  await page.locator('span', { hasText: '← All classes' }).first().click();
  await waitForUrl((u) => !u.includes('class='));
  check('the All classes crumb lands on the class picker', await hasText('Browse any class level'), page.url());

  // Browser back walks the drill one level at a time. The history has to be built by drilling with
  // clicks (each step pushes its URL); a direct load of the deep URL would only have the entry the
  // goto created, so its predecessor is whatever page came before, not the shallower step.
  await page.goto(`${appUrl}/admin/lms`, { waitUntil: 'load' });
  await page.waitForSelector('text=JSS 1', { timeout: 45000 });
  await page.locator('#app h3', { hasText: 'JSS 1' }).click();
  await page.waitForSelector('text=Agricultural Science', { timeout: 15000 });
  await page.locator('#app h3', { hasText: 'Agricultural Science' }).click();
  await page.waitForSelector('text=Noel Term', { timeout: 15000 });
  await page.locator('#app h3', { hasText: 'Noel Term' }).click();
  await page.waitForSelector('text=Packaging Criteria for Farm Produce', { timeout: 15000 });
  await page.goBack();
  await waitForUrl((u) => u.includes('subject=subjects:agricultural_science') && !u.includes('term='));
  check('browser back from the lessons list reaches the terms step',
    page.url().includes('subject=subjects:agricultural_science') && !page.url().includes('term='), page.url());
  check('and the terms step is what renders', await hasText('Choose a term to view its lessons.'));
  await page.goForward();
  await waitForUrl((u) => u.includes('term=terms:noel_term'));
  check('browser forward returns to the lessons list', await hasText('Packaging Criteria for Farm Produce'), page.url());

  // A reload at depth restores the same step from the URL.
  await page.goto(lessonsUrl, { waitUntil: 'load' });
  await page.waitForTimeout(1200);
  check('a direct load of the deep URL restores that step', await hasText('Packaging Criteria for Farm Produce'));

  check('no page errors after the LMS checks', errors.length === 0, JSON.stringify(errors));

  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
