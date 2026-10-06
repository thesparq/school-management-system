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
  // The page carries a stand-in JWT; a DEV_MODE backend accepts the dev-skip token instead.
  await page.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: `Bearer ${process.env.AUTH_TOKEN || 'dev-skip'}` },
  }));

  await page.goto(`${appUrl}/student/subjects`, { waitUntil: 'load' });
  await page.waitForSelector(`text=${subject}`, { timeout: 45000 });
  check('subject cards load', true);

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
  check('no page errors', errors.length === 0, JSON.stringify(errors));

  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
