// Student drill-down against a running backend: subject cards, terms, lessons for a subject+term, the
// full lesson record, and the lesson renderer's sections. Read-only.
//
//   node tests/e2e/e2e_student.cjs
//   APP_URL=http://127.0.0.1:8000 SUBJECT="Agricultural Science" TERM="Noel Term" node tests/e2e/e2e_student.cjs

const { chromium } = require('playwright');

const appUrl = process.env.APP_URL || 'http://127.0.0.1:8000';
// Prefixed names: SUBJECT and TERM already exist in many shells (TERM=xterm-256color).
const subject = process.env.E2E_SUBJECT || 'Agricultural Science';
const term = process.env.E2E_TERM || 'Noel Term';
const lesson = process.env.E2E_LESSON || 'Packaging Criteria for Farm Produce';

const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const token = `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({
  iss: 'https://auth.johnethel.school/application/o/school-management-system/',
  exp: Math.floor(Date.now() / 1000) + 3600,
  email: 'student@example.com', name: 'Test Student', groups: ['students'],
})}.sig`;

const results = [];
const check = (name, ok, extra = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); };

(async () => {
  const browser = await chromium.launch({ channel: 'chromium' });
  const ctx = await browser.newContext();
  await ctx.addInitScript(t => localStorage.setItem('auth_token', t), token);
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message.slice(0, 60)));
  // Every /api path the page asks for. A pupil's cards have to come from the pupil-scoped list: the
  // school-wide `/api/subjects` filled this page before, so a page that asks for that one lists
  // subjects the pupil's class is not taught.
  const asked = [];
  page.on('request', (r) => { if (r.url().includes('/api/')) asked.push(new URL(r.url()).pathname); });
  // The page carries a stand-in JWT; a DEV_MODE backend accepts the dev-skip token instead.
  await page.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: `Bearer ${process.env.AUTH_TOKEN || 'dev-skip'}` },
  }));

  await page.goto(`${appUrl}/student/subjects`, { waitUntil: 'load' });
  await page.waitForSelector(`text=${subject}`, { timeout: 45000 });
  check('subject cards load', true);
  check('the cards came from the pupil-scoped subject list', asked.includes('/api/student/subjects'), JSON.stringify(asked));
  check('and the page never asked for the school-wide list', !asked.includes('/api/subjects'), JSON.stringify(asked));

  await page.click(`text=${subject}`);
  await page.waitForSelector(`text=${term}`, { timeout: 30000 });
  check('terms load', true);

  // The nav bar's session-term badge shows the active term's own name ("2026/2027 — Noel Term"),
  // and it sits before the cards in the DOM, so `text=` would click the badge. Scope to the card.
  await page.locator(`div.group:has(h3:text-is("${term}"))`).first().click();
  await page.waitForSelector(`text=${lesson}`, { timeout: 30000 });
  check('lessons load for the subject and term', true);

  await page.click(`text=${lesson}`);
  await page.waitForSelector('#lesson-panel >> text=Learning Objectives', { timeout: 30000 });
  const panel = await page.textContent('#lesson-panel');
  check('lesson content renders', panel.includes('Introduction') && panel.includes('Learning Objectives'));
  check('objectives render as text', !panel.includes('taxonomy_level'));
  const nav = await page.$$eval('#section-nav-labels button', els => els.map(e => e.textContent.trim()));
  check('scroll-spy lists the sections', ['Introduction', 'Learning Objectives', 'Key Points', 'Conclusion'].every(s => nav.includes(s)), JSON.stringify(nav));

  // The crumbs, from the lesson back one step: the term's crumb keeps the subject and the term and
  // drops only the lesson, so it lands on that term's lessons list. It used to clear the term too,
  // which jumped two steps up.
  await page.locator('#app a', { hasText: term }).first().click();
  await page.waitForSelector(`#app h1 >> text=${term}`, { timeout: 15000 });
  await page.waitForSelector(`text=${lesson}`, { timeout: 15000 });
  check('the term crumb comes back to the term\'s lessons list',
    (await page.locator('#lesson-panel').count()) === 0, 'the lesson panel is still on the page');
  check('no page errors', errors.length === 0, JSON.stringify(errors));

  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
