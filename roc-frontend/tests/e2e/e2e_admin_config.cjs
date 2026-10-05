// Admin configuration hub against a *sandbox* backend (see README.md): every section lists the rows
// its endpoint returns, a create lands in the list, and the backend's own message reaches the UI
// when a create is refused (400 validation text and the database's statement text).
//
//   node tests/e2e/e2e_admin_config.cjs

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
  page.on('pageerror', e => errors.push(e.message.slice(0, 60)));
  await page.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: `Bearer ${process.env.AUTH_TOKEN || 'dev-skip'}` },
  }));

  const hasText = (text) => page.evaluate((t) => document.body.innerText.includes(t), text);
  // One table row containing all the given texts (columns are plain cells).
  const rowHas = (...texts) => page.evaluate((wanted) => [...document.querySelectorAll('table tbody tr')]
    .some(tr => wanted.every(t => tr.innerText.includes(t))), texts);
  const tab = (label) => page.click(`button:has-text("${label}")`);
  const fill = (placeholder, value) => page.locator(`input[placeholder="${placeholder}"]`).fill(value);

  await page.goto(`${appUrl}/admin/config`, { waitUntil: 'load' });
  await page.waitForSelector('text=Configuration Hub', { timeout: 45000 });
  check('configuration hub loads', true);

  // --- Academic Terms: seeded rows, a create, a validation 400 and the database's own refusal ---
  await page.waitForSelector('text=Noel Term', { timeout: 20000 }).catch(() => {});
  check('terms section lists seeded rows', await rowHas('Noel Term', '1', 'Active') && await hasText('Calvary Term'));

  const termName = `Summer Term ${stamp % 100000}`;
  await fill('e.g. Summer Term', termName);
  await fill('e.g. 3', '3');
  await page.click('button:has-text("Create Term")');
  await page.waitForSelector('text=Term created', { timeout: 20000 }).catch(() => {});
  check('created term reports success', await hasText('Term created'));
  await page.waitForSelector(`text=${termName}`, { timeout: 20000 }).catch(() => {});
  check('created term appears in the list', await rowHas(termName, '3'));

  // Empty form -> the backend's 400 text, not a client-side guess.
  await page.click('button:has-text("Create Term")');
  await page.waitForSelector('text=name is required', { timeout: 20000 }).catch(() => {});
  check('blank name shows the validation text', await hasText('name is required'));

  // A name without a sort order -> the second validation answer.
  await fill('e.g. Summer Term', `Orderless ${stamp % 100000}`);
  await page.click('button:has-text("Create Term")');
  await page.waitForSelector('text=sort_order must be a whole number', { timeout: 20000 }).catch(() => {});
  check('missing sort order shows the validation text', await hasText('sort_order must be a whole number'));

  // A duplicate the unique index refuses: the database's own message has to come through.
  await fill('e.g. Summer Term', 'Noel Term');
  await fill('e.g. 3', '9');
  await page.click('button:has-text("Create Term")');
  await page.waitForSelector('text=already contains', { timeout: 20000 }).catch(() => {});
  check('duplicate term shows the database message', await hasText('already contains'), await hasText('idx_terms_name') ? 'idx_terms_name' : 'no index name');

  // --- Class Levels: seeded rows and a create ---
  await tab('Class Levels');
  await page.waitForSelector('text=JSS 1', { timeout: 20000 }).catch(() => {});
  check('class levels section lists seeded rows', await rowHas('JSS 1', 'jss_1', '10-11 years'));

  const levelName = `JSS 4 ${stamp % 100000}`;
  await fill('e.g. JSS 4', levelName);
  await fill('e.g. jss_4', `jss4_${stamp % 100000}`);
  await page.click('button:has-text("Create Class Level")');
  await page.waitForSelector('text=Class level created', { timeout: 20000 }).catch(() => {});
  check('created class level reports success', await hasText('Class level created'));
  await page.waitForSelector(`text=${levelName}`, { timeout: 20000 }).catch(() => {});
  check('created class level appears in the list', await rowHas(levelName, `jss4_${stamp % 100000}`));

  // --- Subjects: seeded rows and a create ---
  await tab('Subjects');
  await page.waitForSelector('text=Agricultural Science', { timeout: 20000 }).catch(() => {});
  check('subjects section lists seeded rows', await rowHas('Agricultural Science', 'AGR'));

  const subjectName = `Basic Science ${stamp % 100000}`;
  await fill('e.g. Mathematics', subjectName);
  await fill('e.g. MTH', 'BSC');
  await page.click('button:has-text("Create Subject")');
  await page.waitForSelector('text=Subject created', { timeout: 20000 }).catch(() => {});
  check('created subject reports success', await hasText('Subject created'));
  await page.waitForSelector(`text=${subjectName}`, { timeout: 20000 }).catch(() => {});
  check('created subject appears in the list', await rowHas(subjectName, 'BSC'));

  // --- Session Terms: the seeded row, then a create that pairs a session with a term ---
  await tab('Session Terms');
  await page.waitForSelector('text=2026/2027', { timeout: 20000 }).catch(() => {});
  check('session terms section lists seeded rows', await rowHas('2026/2027', 'Noel Term', 'Active'));

  const sessionName = `2027/2028 ${stamp % 100000}`;
  await fill('e.g. 2026/2027', sessionName);
  await page.selectOption('#new-session-term-select', { label: 'Calvary Term' });
  await page.click('button:has-text("Create Session Term")');
  await page.waitForSelector('text=Session term created', { timeout: 20000 }).catch(() => {});
  check('created session term reports success', await hasText('Session term created'));
  await page.waitForSelector(`text=${sessionName}`, { timeout: 20000 }).catch(() => {});
  check('created session term appears in the list', await rowHas(sessionName, 'Calvary Term', 'Inactive'));

  // --- Curriculum: the seeded edge and a new class level -> subject link ---
  await tab('Curriculum');
  await page.waitForSelector('text=Agricultural Science', { timeout: 20000 }).catch(() => {});
  check('curriculum section lists the seeded edge', await rowHas('JSS 1', 'Agricultural Science'));

  await page.selectOption('#new-curriculum-class-level-select', { label: 'JSS 2' });
  await page.selectOption('#new-curriculum-subject-select', { label: 'Agricultural Science' });
  await page.click('button:has-text("Link Subject")');
  await page.waitForSelector('text=Curriculum link created', { timeout: 20000 }).catch(() => {});
  check('created curriculum link reports success', await hasText('Curriculum link created'));
  await page.waitForSelector('text=JSS 2', { timeout: 20000 }).catch(() => {});
  check('created curriculum link appears in the list', await rowHas('JSS 2', 'Agricultural Science'));

  // ---------------------------------------------------------------------------------------------
  // Reuse of a link the unique index refuses, from the hub rather than by hand. The successful
  // create cleared the form, so the pair is chosen again before re-submitting.
  await page.selectOption('#new-curriculum-class-level-select', { label: 'JSS 2' });
  await page.selectOption('#new-curriculum-subject-select', { label: 'Agricultural Science' });
  await page.click('button:has-text("Link Subject")');
  await page.waitForSelector('text=already contains', { timeout: 20000 }).catch(() => {});
  check('duplicate curriculum link shows the database message', await hasText('already contains'), await hasText('idx_hs_unique') ? 'idx_hs_unique' : 'no index name');

  check('no page errors', errors.length === 0, JSON.stringify(errors));

  // --- Re-entering the hub from the dashboard refetches the lists (the sidebar path, not just the
  // deep-link load exercised above) ---
  await page.click('a:has-text("Dashboard")');
  await page.waitForSelector('text=Welcome back', { timeout: 20000 }).catch(() => {});
  check('dashboard renders after leaving the hub', await hasText('Welcome back'));
  await page.click('aside >> text="Configuration Hub"');
  await page.click('button:has-text("Academic Terms")');
  await page.waitForSelector('text=Noel Term', { timeout: 20000 }).catch(() => {});
  check('re-entering the hub lists the rows again', await rowHas('Noel Term', '1', 'Active'));
  check('the term created earlier survived the reload', await rowHas(termName, '3'));
  check('no page errors after navigation', errors.length === 0, JSON.stringify(errors));

  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
