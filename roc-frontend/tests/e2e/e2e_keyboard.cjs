// The keyboard, in Chromium, against a *sandbox* backend (see README.md): every control a pointer
// can work has to be workable from the keyboard too. Tab reaches the app's navigation and the
// controls inside a modal (and stops at the modal's edges), Enter follows a link and submits a
// form, Space toggles a tick and switches a tab, and Escape backs out of whatever is on top of the
// page — a modal (the app's own and the page's), the bell's panel.
//
//   node tests/e2e/e2e_keyboard.cjs
//
// The forms it submits are the real ones: the user form's create is answered by the sandbox's own
// backend, while the two writes that would leave a row behind for the other suites (the hub's term
// create and the assessment create) are answered by a stub, so this suite leaves the sandbox as it
// found it. The teacher's lesson needs a pair assigned to `teacher_profile:dev_teacher` (the
// identity the `dev-teacher` token stands for), which is cleared again at the end.

const { chromium } = require('playwright');

const appUrl = process.env.APP_URL || 'http://127.0.0.1:8000';
const adminToken = process.env.AUTH_TOKEN || 'dev-skip';

const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const jwt = (groups) => `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({
  iss: 'https://auth.johnethel.school/application/o/school-management-system/',
  exp: Math.floor(Date.now() / 1000) + 3600,
  email: 'keyboard@example.com', name: 'Keyboard Check', groups,
})}.sig`;

const results = [];
const check = (name, ok, extra = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); };

// What has the focus right now, in the terms the checks ask about it.
const focused = (page) => page.evaluate(() => {
  const a = document.activeElement;
  if (!a) return null;
  return {
    tag: a.tagName,
    id: a.id,
    href: a.getAttribute('href'),
    role: a.getAttribute('role'),
    insideDialog: !!a.closest('[data-dialog]'),
    text: (a.innerText || '').trim().slice(0, 40),
  };
});

const dialogVisible = (page) => page.evaluate(() => {
  const d = document.querySelector('[data-dialog]');
  return !!d && d.getClientRects().length > 0;
});

(async () => {
  const browser = await chromium.launch({ channel: 'chromium' });
  const errors = [];

  const adminCtx = await browser.newContext();
  await adminCtx.addInitScript(t => localStorage.setItem('auth_token', t), jwt(['administrators']));
  await adminCtx.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: `Bearer ${adminToken}` },
  }));
  const page = await adminCtx.newPage();
  page.on('pageerror', e => errors.push(e.message.slice(0, 80)));

  // ─── The shell's navigation ────────────────────────────────────────────────────────────────────
  await page.goto(`${appUrl}/admin/users`, { waitUntil: 'load' });
  await page.waitForSelector('text=Add New User', { timeout: 45000 });
  check('the admin page loads', true);

  const navLinks = await page.evaluate(() => Array.from(document.querySelectorAll('#app a[href]'))
    .map(a => a.getAttribute('href')));
  check('the sidebar and the breadcrumb are real links',
    navLinks.includes('/admin/config') && navLinks.includes('/') && navLinks.includes('/admin/users'),
    navLinks.slice(0, 8).join(' '));

  // Tab walks the page's own order; the sidebar's items are in it.
  await page.evaluate(() => document.body.focus());
  const stops = [];
  for (let i = 0; i < 30; i++) {
    await page.keyboard.press('Tab');
    const f = await focused(page);
    if (f) stops.push(f.href || f.text || f.tag);
    if (f && f.href === '/admin/config') break;
  }
  check('Tab reaches the sidebar\'s own items', stops.includes('/admin/config'), stops.slice(0, 8).join(' | '));

  // Enter follows the focused link, and the app does the navigating (no page load).
  await page.locator('#app a[href="/"]').first().focus();
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => location.pathname === '/', null, { timeout: 15000 }).catch(() => {});
  check('Enter follows the focused link',
    (await page.evaluate(() => location.pathname)) === '/' &&
      (await page.evaluate(() => document.body.innerText.includes('Dashboard'))),
    await page.evaluate(() => location.pathname));

  // ─── A modal: the focus, Tab, Escape and Enter ────────────────────────────────────────────────
  await page.goto(`${appUrl}/admin/users`, { waitUntil: 'load' });
  await page.waitForSelector('text=Add New User', { timeout: 45000 });
  const openForm = async () => {
    await page.click('#app button:has-text("Add New User")');
    await page.waitForFunction(() => {
      const h = document.querySelector('#app h3');
      return h && h.textContent === 'Add New User';
    }, null, { timeout: 10000 }).catch(() => {});
  };

  await openForm();
  const afterOpen = await focused(page);
  check('opening a modal moves the focus into it',
    (await dialogVisible(page)) && !!afterOpen && afterOpen.insideDialog, JSON.stringify(afterOpen));

  // Tab stops at the modal's edges instead of walking the page behind it.
  await page.evaluate(() => {
    const dialog = document.querySelector('[data-dialog]');
    const focusable = Array.from(dialog.querySelectorAll('a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'))
      .filter(el => el.getClientRects().length > 0);
    focusable[focusable.length - 1].focus();
  });
  await page.keyboard.press('Tab');
  const afterWrap = await focused(page);
  check('Tab wraps inside the modal rather than leaving it', !!afterWrap && afterWrap.insideDialog, JSON.stringify(afterWrap));

  await page.keyboard.press('Shift+Tab');
  const afterBack = await focused(page);
  check('Shift+Tab walks back inside the modal', !!afterBack && afterBack.insideDialog, JSON.stringify(afterBack));

  await page.keyboard.press('Escape');
  await page.waitForFunction(() => !document.querySelector('[data-dialog]'), null, { timeout: 10000 }).catch(() => {});
  const afterEscape = await focused(page);
  check('Escape closes the modal and the focus comes back to its opener',
    !(await dialogVisible(page)) && !!afterEscape && afterEscape.text.includes('Add New User'),
    JSON.stringify(afterEscape));

  // Enter in a field submits the form: the same POST the button sends.
  await openForm();
  const fill = async (placeholder, value) => page.locator(`input[placeholder="${placeholder}"]`).fill(value);
  await fill('e.g. Adamu', 'Grace');
  await fill('e.g. Ibrahim', 'Chioma');
  await fill('e.g. Musa', `Keyboard${Date.now() % 10000}`);
  await page.locator('input[type="date"]').fill('2011-09-14');
  await page.selectOption('#new-user-class-level', 'class_levels:jss_2');
  await fill('https://...', 'https://example.com/keyboard.jpg');
  await fill('e.g. adamu@johnethel.school', `keyboard${Date.now()}@example.com`);
  await page.click('text=Generate');
  const submit = page.waitForRequest(r => r.url().endsWith('/api/users') && r.method() === 'POST', { timeout: 20000 }).catch(() => null);
  await page.locator('input[placeholder="e.g. adamu@johnethel.school"]').focus();
  await page.keyboard.press('Enter');
  const posted = await submit;
  check('Enter in a field submits the form', !!posted, posted ? posted.method() : 'no request');
  await page.waitForFunction(() => !document.querySelector('[data-dialog]'), null, { timeout: 20000 }).catch(() => {});
  check('the submitted form closes its modal', !(await dialogVisible(page)));

  // ─── Space: a tick, a tab ─────────────────────────────────────────────────────────────────────
  const tick = page.locator('#app table [role="checkbox"]').first();
  await tick.focus();
  await page.keyboard.press('Space');
  await page.waitForFunction(() => {
    const box = document.querySelector('#app table [role="checkbox"]');
    return box && box.getAttribute('aria-checked') === 'true';
  }, null, { timeout: 10000 }).catch(() => {});
  check('Space ticks a row\'s checkbox',
    (await page.locator('#app table [role="checkbox"]').first().getAttribute('aria-checked')) === 'true' &&
      (await page.evaluate(() => document.body.innerText.includes('1 selected'))));
  await page.keyboard.press('Space');
  await page.waitForFunction(() => {
    const box = document.querySelector('#app table [role="checkbox"]');
    return box && box.getAttribute('aria-checked') === 'false';
  }, null, { timeout: 10000 }).catch(() => {});
  check('Space takes the tick off again',
    (await page.locator('#app table [role="checkbox"]').first().getAttribute('aria-checked')) === 'false');

  // ─── The configuration hub: a tab switched by Space, a form sent by Enter ─────────────────────
  await page.goto(`${appUrl}/admin/config`, { waitUntil: 'load' });
  await page.waitForSelector('text=Configuration Hub', { timeout: 45000 });
  const tablist = await page.evaluate(() => {
    const strip = document.querySelector('#app [role="tablist"]');
    return strip ? Array.from(strip.querySelectorAll('[role="tab"]')).map(t => ({ text: t.innerText.trim(), selected: t.getAttribute('aria-selected') })) : [];
  });
  check('the hub\'s sections are a tablist of tabs, one selected',
    tablist.length >= 6 && tablist.filter(t => t.selected === 'true').length === 1,
    tablist.map(t => `${t.text}:${t.selected}`).join(' '));

  const curriculumTab = page.locator('#app [role="tab"]:has-text("Curriculum")');
  await curriculumTab.focus();
  await page.keyboard.press('Space');
  await page.waitForSelector('text=Link Subject', { timeout: 15000 }).catch(() => {});
  check('Space switches the focused tab',
    (await curriculumTab.getAttribute('aria-selected')) === 'true' &&
      (await page.evaluate(() => document.body.innerText.includes('Link Subject'))));

  // The hub's create form is a real <form>: Enter in its field creates the row. The write is
  // answered by a stub, so no term is left behind for the other suites.
  await page.locator('#app [role="tab"]:has-text("Academic Terms")').focus();
  await page.keyboard.press('Space');
  await page.waitForSelector('input[placeholder="e.g. Summer Term"]', { timeout: 15000 });
  await page.route('**/api/terms', route => route.request().method() === 'POST'
    ? route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ ok: true, id: 'terms:keyboard_check' }) })
    // The list's own refetch still goes to the backend, and this handler is the one that matches
    // it: the bearer the suite's other requests carry has to be put back on by hand, or the refetch
    // would go out with the page's own (unmodelled) token and 401 the session.
    : route.continue({ headers: { ...route.request().headers(), authorization: `Bearer ${adminToken}` } }));
  const termPost = page.waitForRequest(r => r.url().endsWith('/api/terms') && r.method() === 'POST', { timeout: 15000 }).catch(() => null);
  await page.locator('input[placeholder="e.g. Summer Term"]').focus();
  await page.keyboard.type('Keyboard Term');
  await page.keyboard.press('Enter');
  const termPosted = await termPost;
  check('Enter in a create form sends it', !!termPosted, termPosted ? termPosted.method() : 'no request');
  check('the form is a real <form> the browser submits',
    await page.evaluate(() => !!document.querySelector('#app form')));

  // ─── Escape: the bell's panel, and the page's own modal ───────────────────────────────────────
  await page.click('#notifications-bell-wrap button');
  await page.waitForFunction(() => {
    const panel = document.getElementById('notifications-panel');
    return panel && !panel.classList.contains('hidden');
  }, null, { timeout: 10000 }).catch(() => {});
  await page.keyboard.press('Escape');
  await page.waitForFunction(() => {
    const panel = document.getElementById('notifications-panel');
    return panel && panel.classList.contains('hidden');
  }, null, { timeout: 10000 }).catch(() => {});
  check('Escape closes the bell\'s panel',
    await page.evaluate(() => document.getElementById('notifications-panel').classList.contains('hidden')));

  // ─── The page's own modal (the assessment one), as a teacher ──────────────────────────────────
  // The lesson under test is the sandbox fixture's own, and the teacher needs the pair it belongs
  // to — assigned here and cleared again below, like e2e_list_order does for its own checks.
  const edge = await page.evaluate(async () => {
    const body = await (await fetch('/api/class-subjects')).json();
    const rows = (Array.isArray(body) ? body[0] : body).result || [];
    const row = rows.find(r => r.subject_name === 'Agricultural Science' && r.class_level_name === 'JSS 1');
    return row ? row.edge_id : '';
  });
  const assigned = await page.evaluate(async (edgeId) => {
    const res = await fetch('/api/teacher-assignments', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ teacher_id: 'teacher_profile:dev_teacher', pairs: edgeId ? [edgeId] : [] }),
    });
    return res.ok;
  }, edge);
  check('the suite could assign the lesson\'s pair to the teacher', assigned === true, `edge=${edge}`);

  const teacherCtx = await browser.newContext();
  await teacherCtx.addInitScript(t => localStorage.setItem('auth_token', t), jwt(['teachers']));
  await teacherCtx.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: 'Bearer dev-teacher' },
  }));
  const teacher = await teacherCtx.newPage();
  teacher.on('pageerror', e => errors.push(e.message.slice(0, 80)));

  try {
    await teacher.goto(`${appUrl}/teacher/lessons?id=lessons:test_lesson`, { waitUntil: 'load' });
    // The lesson viewer's own tabs are the page's: a real button, switched by the page's click
    // delegation. Space on the focused one has to reach it, and the assessment panel is behind it.
    // The delegation is bound by the page's own `setupPageJS` after the app mounts, so the suite
    // waits for the lesson it loads (the first thing that proves the page's JavaScript is running)
    // before pressing anything.
    await teacher.waitForSelector('#tab-assessments', { timeout: 45000 });
    await teacher.waitForSelector('#section-introduction', { timeout: 30000 }).catch(() => {});
    await teacher.locator('#tab-assessments').focus();
    await teacher.keyboard.press('Space');
    await teacher.waitForSelector('#create-assessment-btn', { state: 'visible', timeout: 20000 }).catch(() => {});
    check('Space switches the lesson viewer\'s own tab',
      (await teacher.locator('#tab-assessments').getAttribute('aria-selected')) === 'true' &&
        (await teacher.evaluate(() => !document.getElementById('assessments-panel').classList.contains('hidden'))));

    await teacher.click('#create-assessment-btn');
    await teacher.waitForFunction(() => {
      const modal = document.getElementById('create-assessment-modal');
      return modal && !modal.classList.contains('hidden');
    }, null, { timeout: 15000 }).catch(() => {});
    const inModal = await focused(teacher);
    check('the page\'s own modal opens with the focus in it',
      (await dialogVisible(teacher)) && !!inModal && inModal.insideDialog, JSON.stringify(inModal));

    await teacher.route('**/api/teacher/create-lesson-assessment', route => route.fulfill({
      status: 200, contentType: 'application/json', body: JSON.stringify({ ok: true, id: 'lesson_assessments:keyboard_check' }),
    }));
    const assessmentPost = teacher.waitForRequest(r => r.url().endsWith('/api/teacher/create-lesson-assessment'), { timeout: 15000 }).catch(() => null);
    await teacher.locator('#assessment-title-input').focus();
    await teacher.keyboard.type('Keyboard Check Quiz');
    await teacher.keyboard.press('Enter');
    const assessmentPosted = await assessmentPost;
    check('Enter in the page\'s own form sends it', !!assessmentPosted, assessmentPosted ? assessmentPosted.method() : 'no request');
    await teacher.waitForFunction(() => {
      const modal = document.getElementById('create-assessment-modal');
      return modal && modal.classList.contains('hidden');
    }, null, { timeout: 15000 }).catch(() => {});
    check('the sent modal closes',
      await teacher.evaluate(() => document.getElementById('create-assessment-modal').classList.contains('hidden')));

    // Reopened, Escape closes it — the same button its ✕ runs.
    await teacher.click('#create-assessment-btn');
    await teacher.waitForFunction(() => {
      const modal = document.getElementById('create-assessment-modal');
      return modal && !modal.classList.contains('hidden');
    }, null, { timeout: 15000 }).catch(() => {});
    await teacher.keyboard.press('Escape');
    await teacher.waitForFunction(() => {
      const modal = document.getElementById('create-assessment-modal');
      return modal && modal.classList.contains('hidden');
    }, null, { timeout: 15000 }).catch(() => {});
    check('Escape closes the page\'s own modal',
      await teacher.evaluate(() => document.getElementById('create-assessment-modal').classList.contains('hidden')));
  } finally {
    const cleared = await page.evaluate(async () => {
      const res = await fetch('/api/teacher-assignments', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ teacher_id: 'teacher_profile:dev_teacher', pairs: [] }),
      });
      return res.ok;
    });
    check('the suite\'s own assignment is cleared again', cleared === true);
  }

  check('no page errors', errors.length === 0, JSON.stringify(errors.slice(0, 3)));

  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})().catch(e => { console.error('FATAL', e); process.exit(2); });
