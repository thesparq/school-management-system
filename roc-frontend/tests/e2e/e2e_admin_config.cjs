// Admin configuration hub against a *sandbox* backend (see README.md): every section lists the rows
// its endpoint returns, a create lands in the list, and the backend's own message reaches the UI
// when a create is refused (400 validation text and the database's statement text). The second half
// covers managing what is already there: a row edited in place (and a rename the unique index
// refuses), a subject deactivated and reactivated — off `/api/subjects`, still in the hub — and a
// curriculum link switched off and back on.
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
  // The status badge of the row containing `text`, so "Active" and "Inactive" are never confused.
  const rowStatus = (text) => page.evaluate((t) => {
    const tr = [...document.querySelectorAll('table tbody tr')].find(tr => tr.innerText.includes(t));
    return tr ? (tr.innerText.includes('Inactive') ? 'Inactive' : 'Active') : 'missing';
  }, text);
  // Wait for that badge: a toggle answers the banner first and the re-fetched list lands after it.
  const waitForRowStatus = async (text, status) => {
    await page.waitForFunction(([t, s]) => {
      const tr = [...document.querySelectorAll('table tbody tr')].find(tr => tr.innerText.includes(t));
      return tr ? (tr.innerText.includes('Inactive') ? 'Inactive' : 'Active') === s : false;
    }, [text, status], { timeout: 20000 }).catch(() => {});
  };
  // One list straight from the API, through the same bearer token the page uses.
  const api = (path) => page.evaluate(async (p) => {
    const res = await fetch(p, { headers: { 'Authorization': 'Bearer dev-skip' } });
    const body = await res.json();
    const envelope = Array.isArray(body) ? body[0] : body;
    if (envelope && typeof envelope === 'object' && 'result' in envelope) {
      return envelope.result == null ? [] : (Array.isArray(envelope.result) ? envelope.result : [envelope.result]);
    }
    return Array.isArray(body) ? body : [];
  }, path);
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

  // ---------------------------------------------------------------------------------------------
  // Managing the rows that are already there: an edit in place, a row switched off and back on, and
  // the curriculum link's toggle. The round trip above left the hub on the Academic Terms tab.

  // --- Editing a term: both of its editable columns, then the row after the list re-fetches ------
  const editedTermName = `Summer Term ${stamp % 100000} edited`;
  await page.click(`tr:has-text("${termName}") >> button:has-text("Edit")`);
  const termEditor = page.locator(`tr:has(input[placeholder="Term name"])`);
  check('Edit opens the row in place', await termEditor.count() === 1);
  await termEditor.locator('input[placeholder="Term name"]').fill(editedTermName);
  await termEditor.locator('input[placeholder="Sort order"]').fill('4');
  await termEditor.locator('button:has-text("Save")').click();
  await page.waitForSelector('text=Term updated', { timeout: 20000 }).catch(() => {});
  check('saving an edit reports success', await hasText('Term updated'));
  await page.waitForSelector(`text=${editedTermName}`, { timeout: 20000 }).catch(() => {});
  check('the edited term shows its new name and sort order after the re-fetch', await rowHas(editedTermName, '4'));
  check('the editor closed once the row was saved', await page.locator(`tr:has(input[placeholder="Term name"])`).count() === 0);

  // A rename onto a name another term already holds: the unique index refuses it, so the banner has
  // to carry db_response!'s detail and the row keeps the values it had.
  await page.click(`tr:has-text("${editedTermName}") >> button:has-text("Edit")`);
  await page.locator(`tr:has(input[placeholder="Term name"]) input[placeholder="Term name"]`).fill('Noel Term');
  await page.locator(`tr:has(input[placeholder="Term name"]) button:has-text("Save")`).click();
  await page.waitForSelector('text=already contains', { timeout: 20000 }).catch(() => {});
  check('a refused edit shows the database message', await hasText('already contains'), await hasText('idx_terms_name') ? 'idx_terms_name' : 'no index name');
  await page.locator(`tr:has(input[placeholder="Term name"]) button:has-text("Cancel")`).click();
  check('Cancel closes the editor again', await page.locator(`tr:has(input[placeholder="Term name"])`).count() === 0);
  check('the row the refused edit named still holds its own name and sort order', await rowHas(editedTermName, '4') && await rowStatus(editedTermName) === 'Active');

  // --- A class level: the three editable columns, age range included ---------------------------
  await tab('Class Levels');
  await page.waitForSelector(`text=${levelName}`, { timeout: 20000 }).catch(() => {});
  const editedLevelName = `${levelName} edited`;
  await page.click(`tr:has-text("${levelName}") >> button:has-text("Edit")`);
  const levelEditor = page.locator(`tr:has(input[placeholder="Age range"])`);
  check('a class level row opens with all three of its columns', await levelEditor.locator('input').count() === 3);
  await levelEditor.locator('input[placeholder="Class level name"]').fill(editedLevelName);
  await levelEditor.locator('input[placeholder="Age range"]').fill('13-14 years');
  await levelEditor.locator('button:has-text("Save")').click();
  await page.waitForSelector('text=Class level updated', { timeout: 20000 }).catch(() => {});
  check('saving a class level edit reports success', await hasText('Class level updated'));
  await page.waitForSelector(`text=${editedLevelName}`, { timeout: 20000 }).catch(() => {});
  check('the edited class level shows its new name and age range', await rowHas(editedLevelName, '13-14 years'));

  // --- A subject: deactivating takes it off the active-only list without removing the row --------
  await tab('Subjects');
  await page.waitForSelector(`text=${subjectName}`, { timeout: 20000 }).catch(() => {});
  check('the created subject starts out active', await rowStatus(subjectName) === 'Active');
  await page.click(`tr:has-text("${subjectName}") >> button:has-text("Deactivate")`);
  await page.waitForSelector('text=Subject deactivated', { timeout: 20000 }).catch(() => {});
  check('deactivating a subject reports success', await hasText('Subject deactivated'));
  await waitForRowStatus(subjectName, 'Inactive');
  check('the deactivated subject keeps its row and shows an Inactive badge', await rowHas(subjectName, 'BSC') && await rowStatus(subjectName) === 'Inactive');

  const subjectsAfterOff = await api('/api/subjects');
  check('/api/subjects no longer lists the deactivated subject', !subjectsAfterOff.some(s => s.name === subjectName), subjectsAfterOff.map(s => s.name).join(', ') || 'empty');
  const allSubjects = await api('/api/subjects?all=true');
  check('the hub\'s own list still carries it, flagged inactive', allSubjects.some(s => s.name === subjectName && s.active === false));

  await page.click(`tr:has-text("${subjectName}") >> button:has-text("Activate")`);
  await page.waitForSelector('text=Subject activated', { timeout: 20000 }).catch(() => {});
  check('reactivating the subject reports success', await hasText('Subject activated'));
  await waitForRowStatus(subjectName, 'Active');
  check('the reactivated subject shows an Active badge again', await rowStatus(subjectName) === 'Active');
  const subjectsAfterOn = await api('/api/subjects');
  check('the subject is back in the active-only list', subjectsAfterOn.some(s => s.name === subjectName));

  // --- A session term created inactive: activating it is what makes it usable --------------------
  await tab('Session Terms');
  await page.waitForSelector(`text=${sessionName}`, { timeout: 20000 }).catch(() => {});
  check('the new session term is listed inactive', await rowStatus(sessionName) === 'Inactive');
  await page.click(`tr:has-text("${sessionName}") >> button:has-text("Activate")`);
  await page.waitForSelector('text=Session term activated', { timeout: 20000 }).catch(() => {});
  check('activating the session term reports success', await hasText('Session term activated'));
  await waitForRowStatus(sessionName, 'Active');
  check('the session term now reads Active', await rowStatus(sessionName) === 'Active');

  // --- The curriculum edge: switched off in place, then back on ---------------------------------
  await tab('Curriculum');
  await page.waitForSelector('text=Agricultural Science', { timeout: 20000 }).catch(() => {});
  const edgeRow = `tr:has-text("JSS 2"):has-text("Agricultural Science")`;
  check('the linked edge starts out active', await rowStatus('JSS 2') === 'Active');
  await page.click(`${edgeRow} >> button:has-text("Deactivate")`);
  await page.waitForSelector('text=Curriculum link deactivated', { timeout: 20000 }).catch(() => {});
  check('deactivating the edge reports success', await hasText('Curriculum link deactivated'));
  await waitForRowStatus('JSS 2', 'Inactive');
  check('the switched-off edge stays in the hub as Inactive', await rowHas('JSS 2', 'Agricultural Science') && await rowStatus('JSS 2') === 'Inactive');
  const activeEdges = await api('/api/curriculum');
  check('/api/curriculum drops the deactivated edge', !activeEdges.some(e => String(e.in).includes('jss_2') && String(e.out).includes('agricultural_science')), JSON.stringify(activeEdges));

  await page.click(`${edgeRow} >> button:has-text("Activate")`);
  await page.waitForSelector('text=Curriculum link activated', { timeout: 20000 }).catch(() => {});
  check('reactivating the edge reports success', await hasText('Curriculum link activated'));
  const edgesBack = await api('/api/curriculum');
  check('the edge is back in the active curriculum', edgesBack.some(e => String(e.in).includes('jss_2') && String(e.out).includes('agricultural_science')));
  check('no page errors after the edits and toggles', errors.length === 0, JSON.stringify(errors));

  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
