// The order the admin and staff views render their lists in, in Chromium: the admin LMS class
// picker (Year 1-5, then JSS 1-3, then SSS 1-3 — the school's stage order), a class's subject cards,
// the Configuration hub's class level, subject and curriculum tables, and the teacher's own My
// Classes cards. The teacher's cards need pairs to render, so the suite assigns one pair per class
// to `teacher_profile:dev_teacher` (the identity the `dev-teacher` token stands for) in reverse and
// clears the set again at the end, leaving the sandbox as it found it.
//
//   node tests/e2e/e2e_list_order.cjs
//
// Needs a sandbox backend (see README.md) and the built frontend bundle.

const { chromium } = require('playwright');

const appUrl = process.env.APP_URL || 'http://127.0.0.1:8000';
const adminToken = process.env.AUTH_TOKEN || 'dev-skip';
// The eleven class levels prod holds, in the order the school shows them: the primary years, the
// junior school, the senior school. A sandbox other suites have written to carries extra levels;
// every check here reads the canonical ones out of what the view rendered and asks whether they are
// in this order.
const CANON = ['Year 1', 'Year 2', 'Year 3', 'Year 4', 'Year 5', 'JSS 1', 'JSS 2', 'JSS 3', 'SSS 1', 'SSS 2', 'SSS 3'];

const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const jwt = (groups) => `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({
  iss: 'https://auth.johnethel.school/application/o/school-management-system/',
  exp: Math.floor(Date.now() / 1000) + 3600,
  email: 'order@example.com', name: 'Order Check', groups,
})}.sig`;

const results = [];
const check = (name, ok, extra = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); };

// The canonical names, in the order the view rendered them, against the school's order. Names the
// school's list does not name (a suite's own row) are left out.
const canonicalOrder = (names) => {
  const seen = names.filter(n => CANON.includes(n));
  const want = CANON.filter(n => names.includes(n));
  return { ok: seen.length > 0 && seen.join('|') === want.join('|'), seen, want };
};

// A list of `{ className, subject }` cards: the classes must follow the school's order and each
// class's subjects must be alphabetical. Cards of a class the school's list does not name are left
// out.
const pairsOrder = (pairs) => {
  const rank = new Map(CANON.map((n, i) => [n, i]));
  let prev = null; const bad = []; let seen = 0;
  for (const p of pairs) {
    if (!rank.has(p.className)) continue;
    seen += 1;
    const key = [rank.get(p.className), p.subject];
    if (prev && (key[0] < prev[0] || (key[0] === prev[0] && key[1] < prev[1]))) bad.push(`${p.className} / ${p.subject}`);
    prev = key;
  }
  return { ok: seen > 0 && bad.length === 0, seen, bad };
};

const ascending = (names) => names.length > 0 && names.join('|') === [...names].sort().join('|');

(async () => {
  const browser = await chromium.launch({ channel: 'chromium' });

  // --- The admin's session: the LMS pages and the Configuration hub ---
  const adminCtx = await browser.newContext();
  await adminCtx.addInitScript(t => localStorage.setItem('auth_token', t), jwt(['administrators']));
  await adminCtx.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: `Bearer ${adminToken}` },
  }));
  const page = await adminCtx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message.slice(0, 80)));

  // Every card on a view (the sidebar carries no headings), the class or subject name it shows, and
  // the line under it (the teacher's cards carry their class there).
  const cards = (p) => p.$$eval('#app h3', els => els.map(h => {
    const under = h.parentElement.querySelector('p');
    return { name: h.textContent.trim(), under: under ? under.textContent.trim() : '' };
  }));
  const tableColumn = (p, n) => p.$$eval('table tbody tr', (rows, i) => rows.map(r => {
    const cells = [...r.querySelectorAll('td')];
    return cells[i] ? cells[i].innerText.trim() : '';
  }), n);
  // A hub table hands over from its skeleton rows (empty cells) to its data once the list lands; the
  // reads below want the data, not the placeholders.
  const waitForTable = (p) => p.waitForFunction(() => {
    const rows = [...document.querySelectorAll('table tbody tr')];
    return rows.length > 0 && rows[0].innerText.trim() !== '';
  }, null, { timeout: 20000 }).catch(() => {});

  // 1. The admin LMS class picker: the school's order, first card to last.
  await page.goto(`${appUrl}/admin/lms`, { waitUntil: 'load' });
  await page.waitForSelector('text=Browse any class level', { timeout: 45000 });
  await page.waitForSelector('#app h3', { timeout: 20000 }).catch(() => {});
  const picked = (await cards(page)).map(c => c.name);
  const pickerOrder = canonicalOrder(picked);
  check('the admin LMS class picker reads Year 1-5, JSS 1-3, SSS 1-3', pickerOrder.ok, picked.join(' | '));

  // 2. A class's subjects, in the picker one level down: alphabetical.
  await page.locator('#app h3', { hasText: /^JSS 1$/ }).first().click();
  await page.waitForSelector('text=Choose a subject to see its terms and lessons.', { timeout: 20000 });
  const subjectCards = (await cards(page)).map(c => c.name);
  check('a class\'s subject cards are alphabetical', ascending(subjectCards), subjectCards.join(' | '));

  // 3. The Configuration hub's own tables.
  await page.goto(`${appUrl}/admin/config`, { waitUntil: 'load' });
  await page.waitForSelector('text=Configuration Hub', { timeout: 45000 });
  await page.click('button:has-text("Class Levels")');
  await waitForTable(page);
  const levelRows = await tableColumn(page, 0);
  const hubOrder = canonicalOrder(levelRows);
  check('the hub\'s class-level table reads the school\'s order', hubOrder.ok, levelRows.join(' | '));

  await page.click('button:has-text("Subjects")');
  await waitForTable(page);
  const subjectRows = await tableColumn(page, 0);
  check('the hub\'s subject table is alphabetical', ascending(subjectRows), subjectRows.join(' | '));

  await page.click('button:has-text("Curriculum")');
  await waitForTable(page);
  const edgeClasses = await tableColumn(page, 0);
  const edgeSubjects = await tableColumn(page, 1);
  const edgeOrder = pairsOrder(edgeClasses.map((className, i) => ({ className, subject: edgeSubjects[i] || '' })));
  check('the hub\'s curriculum table follows the same class order, subjects alphabetical', edgeOrder.ok,
    edgeClasses.map((c, i) => `${c} / ${edgeSubjects[i]}`).join(' | '));

  // 4. The teacher's own view (the staff half of the same order). One pair per canonical class, sent
  // in reverse through the admin session: a view that echoed the write order would fail.
  const pairs = await page.evaluate(async (canon) => {
    const body = await (await fetch('/api/class-subjects')).json();
    const rows = (Array.isArray(body) ? body[0] : body).result || [];
    const seen = new Set(); const perClass = [];
    for (const r of rows) {
      if (!canon.includes(r.class_level_name) || seen.has(r.class_level_name)) continue;
      seen.add(r.class_level_name);
      perClass.push({ edge_id: r.edge_id });
    }
    return perClass.slice(0, 5).reverse();
  }, CANON);
  check('the suite found class-subject pairs to assign', pairs.length > 0, `${pairs.length} pairs`);
  const saved = await page.evaluate(async (set) => {
    const res = await fetch('/api/teacher-assignments', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ teacher_id: 'teacher_profile:dev_teacher', pairs: set }),
    });
    return res.ok;
  }, pairs);
  check('the deliberately reversed pair set saved', saved === true);

  const teacherCtx = await browser.newContext();
  await teacherCtx.addInitScript(t => localStorage.setItem('auth_token', t), jwt(['teachers']));
  await teacherCtx.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: 'Bearer dev-teacher' },
  }));
  const teacherPage = await teacherCtx.newPage();
  teacherPage.on('pageerror', e => errors.push(e.message.slice(0, 80)));

  let cleared = false;
  try {
    await teacherPage.goto(`${appUrl}/teacher/classes`, { waitUntil: 'load' });
    await teacherPage.waitForSelector('text=My Classes', { timeout: 45000 });
    await teacherPage.waitForSelector('#app h3', { timeout: 20000 }).catch(() => {});
    const teacherCards = (await cards(teacherPage)).map(c => ({ className: c.under, subject: c.name }));
    const teacherOrder = pairsOrder(teacherCards);
    check('My Classes reads the school\'s class order, subjects alphabetical inside a class', teacherOrder.ok,
      teacherCards.map(c => `${c.className} / ${c.subject}`).join(' | '));
  } finally {
    // The suite's own assignment is cleared again — also when a check above threw, so a failed run
    // cannot leave pairs behind for the suites that read this teacher's empty state.
    cleared = await page.evaluate(async () => {
      const res = await fetch('/api/teacher-assignments', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ teacher_id: 'teacher_profile:dev_teacher', pairs: [] }),
      });
      return res.ok;
    });
  }
  await teacherPage.reload({ waitUntil: 'load' });
  await teacherPage.waitForSelector('text=No classes assigned yet', { timeout: 20000 }).catch(() => {});
  check('the assignment is cleared again and My Classes shows its empty state',
    cleared === true && (await teacherPage.evaluate(() => document.body.innerText.includes('No classes assigned yet'))));

  check('no page errors', errors.length === 0, JSON.stringify(errors.slice(0, 3)));
  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})().catch(e => { console.error('FATAL', e); process.exit(2); });
