// The three administration pages at the width of a phone, in Chromium, against a *sandbox* backend
// (see README.md): the configuration hub, user management and messaging at 390x844. What a phone gets
// is not a table panned sideways inside its card, so the checks are about *layout*: a stackable table
// lays each row out as a card whose cells print their column's name, nothing crosses the right edge of
// the screen, a tab strip scrolls inside its own box rather than off the edge, a page header's action
// button is whole, and the two messaging panels stack instead of sharing one screenful. The last
// section re-checks the same pages at a desktop width, where all of that must be gone again: the
// tables are tables, the table header is visible, and the messaging panels sit side by side.
//
//   node tests/e2e/e2e_admin_responsive.cjs
//
// The chat list's own behaviour (logging in, making and joining channels) is not this suite's subject
// — e2e_chat_channels.cjs and e2e_matrix_sso.cjs drive that against a mock homeserver. Here the
// messaging page is measured against whatever its sandbox says, which may be a homeserver it cannot
// reach: the panels' geometry is the same either way.

const { chromium } = require('playwright');

const appUrl = process.env.APP_URL || 'http://127.0.0.1:8000';
const PHONE = { width: 390, height: 844 };
const DESKTOP = { width: 1280, height: 800 };

const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const token = `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({
  iss: 'https://auth.johnethel.school/application/o/school-management-system/',
  exp: Math.floor(Date.now() / 1000) + 3600,
  email: 'bursar@example.com', name: 'Admin User', groups: ['administrators'],
})}.sig`;

const results = [];
const check = (name, ok, extra = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); };

// What the page's own layout says about one table: whether its rows are stacked cards, whether the
// header row is dropped, and the name each cell prints (from the `stack-label` pseudo-element, which
// is how the phone layout shows a column without a header row to show it in).
const tableLayout = (page, tableIndex = 0) => page.evaluate((i) => {
  const table = document.querySelectorAll('#app table')[i];
  if (!table) return null;
  const row = table.querySelector('tbody tr');
  const first = row && row.querySelector('td');
  const labelled = row && row.querySelector('td[data-label]');
  const content = labelled ? getComputedStyle(labelled, '::before').content : '';
  return {
    tableDisplay: getComputedStyle(table).display,
    theadDisplay: table.querySelector('thead') ? getComputedStyle(table.querySelector('thead')).display : 'none',
    rowDisplay: row ? getComputedStyle(row).display : 'none',
    firstCellDisplay: first ? getComputedStyle(first).display : 'none',
    label: labelled ? labelled.getAttribute('data-label') : '',
    labelContent: String(content).replace(/^"|"$/g, ''),
    wrapperScrolls: table.parentElement.scrollWidth > table.parentElement.clientWidth + 1,
  };
}, tableIndex);

// Everything that crosses the right edge of the screen, ignoring the off-screen mobile drawer (the
// shell's own overlay, which is `hidden` at every width) and anything inside a horizontally scrolling
// box — a tab strip and a still-tableable table are *meant* to extend past it.
const offenders = (page) => page.evaluate(() => {
  const vw = window.innerWidth;
  const scrolls = (el) => {
    for (let n = el; n && n !== document.body; n = n.parentElement) {
      const overflow = getComputedStyle(n).overflowX;
      if (overflow === 'auto' || overflow === 'scroll') return true;
      if (n.classList.contains('hidden')) return true;
    }
    return false;
  };
  const out = [];
  document.querySelectorAll('#app *').forEach((el) => {
    const b = el.getBoundingClientRect();
    if (b.width > 0 && b.height > 0 && b.right > vw + 1 && !scrolls(el)) {
      out.push(`${el.tagName}#${el.id}.${String(el.className).slice(0, 40)}`);
    }
  });
  return { count: out.length, sample: out.slice(0, 4), docScrolls: document.documentElement.scrollWidth > document.documentElement.clientWidth + 1 };
});

const openPage = async (ctx, path, heading) => {
  const page = await ctx.newPage();
  await page.route('**/api/**', (route) => route.continue({
    headers: { ...route.request().headers(), authorization: `Bearer ${process.env.AUTH_TOKEN || 'dev-skip'}` },
  }));
  await page.goto(`${appUrl}${path}`, { waitUntil: 'load' });
  await page.waitForSelector(`h1:has-text("${heading}")`, { timeout: 45000 });
  await page.waitForTimeout(2000);
  return page;
};

(async () => {
  const browser = await chromium.launch({ channel: 'chromium' });

  // ---- A phone --------------------------------------------------------------------------------
  const phoneCtx = await browser.newContext({ viewport: PHONE });
  await phoneCtx.addInitScript((t) => localStorage.setItem('auth_token', t), token);

  const config = await openPage(phoneCtx, '/admin/config', 'Configuration Hub');
  const tabs = ['Academic Terms', 'Class Levels', 'Curriculum', 'Session Terms', 'Subjects', 'Qualifications'];
  const labelsSeen = { 'Academic Terms': 'Term', 'Class Levels': 'Class level', 'Curriculum': 'Class level', 'Session Terms': 'Session', 'Subjects': 'Subject', 'Qualifications': 'Qualification' };
  for (const tab of tabs) {
    await config.click(`button:has-text("${tab}")`);
    await config.waitForTimeout(900);
    const layout = await tableLayout(config);
    check(`config/${tab}: rows lay out as cards`, !!layout && layout.rowDisplay === 'block', layout ? `row display=${layout.rowDisplay}` : 'no table');
    check(`config/${tab}: the header row is dropped`, !!layout && layout.theadDisplay === 'none', layout ? `thead=${layout.theadDisplay}` : 'no table');
    check(`config/${tab}: a cell prints its column's name`, !!layout && layout.labelContent.toLowerCase() === labelsSeen[tab].toLowerCase(), layout ? `${layout.label} -> ::before ${JSON.stringify(layout.labelContent)}` : 'no table');
    const outside = await offenders(config);
    check(`config/${tab}: nothing crosses the right edge`, outside.count === 0 && !outside.docScrolls, outside.sample.join(', '));
  }
  const configTabsFit = await config.evaluate(() => {
    const strip = [...document.querySelectorAll('#app div')].find(d => String(d.className).includes('overflow-x-auto') && String(d.className).includes('bg-muted'));
    if (!strip) return { found: false };
    return { found: true, right: Math.round(strip.getBoundingClientRect().right), inner: window.innerWidth, scrolls: strip.scrollWidth > strip.clientWidth + 1 };
  });
  check('config: the tab strip stays on screen and scrolls in place', configTabsFit.found && configTabsFit.right <= configTabsFit.inner + 1 && configTabsFit.scrolls, JSON.stringify(configTabsFit));

  const users = await openPage(phoneCtx, '/admin/users', 'User Management');
  const usersLayout = await tableLayout(users);
  check('users: rows lay out as cards', !!usersLayout && usersLayout.rowDisplay === 'block', usersLayout ? `row display=${usersLayout.rowDisplay}` : 'no table');
  check('users: the header row is dropped', !!usersLayout && usersLayout.theadDisplay === 'none');
  const cellNames = await users.evaluate(() => [...document.querySelectorAll('#app table tbody tr:first-child td[data-label]')].map(td => td.getAttribute('data-label')));
  check('users: the cells carry their column names', ['Email', 'School number', 'Status'].every(n => cellNames.includes(n)), JSON.stringify(cellNames));
  const firstLine = await users.evaluate(() => {
    const cells = [...document.querySelectorAll('#app table tbody tr:first-child td')].slice(0, 3).map(td => td.getBoundingClientRect());
    if (cells.length < 3) return null;
    const tops = cells.map(c => Math.round(c.top));
    return { sameLine: Math.max(...tops) - Math.min(...tops) <= 20, tops };
  });
  check('users: the tick, avatar and name stay on one line', !!firstLine && firstLine.sameLine, JSON.stringify(firstLine));
  const usersOutside = await offenders(users);
  check('users: nothing crosses the right edge', usersOutside.count === 0 && !usersOutside.docScrolls, usersOutside.sample.join(', '));
  const addButton = await users.evaluate(() => {
    const btn = [...document.querySelectorAll('button')].find(b => b.textContent.includes('Add New User'));
    if (!btn) return null;
    const b = btn.getBoundingClientRect();
    return { right: Math.round(b.right), inner: window.innerWidth, clipped: btn.scrollWidth > btn.clientWidth + 1, height: Math.round(b.height), textHeight: Math.round(b.scrollHeight) };
  });
  check('users: the Add New User button is whole and on screen', !!addButton && !addButton.clipped && addButton.right <= addButton.inner + 1, JSON.stringify(addButton));
  const actionsVisible = await users.evaluate(() => ['Edit', 'Reset password'].every(t => [...document.querySelectorAll('#app table tbody button')].some(b => b.textContent.trim() === t)));
  check('users: the row actions are the row\'s own buttons', actionsVisible);

  await users.click('button:has-text("Add New User")');
  await users.waitForTimeout(800);
  const modal = await users.evaluate(() => {
    const card = document.querySelector('#app [data-close-input] > div');
    if (!card) return null;
    const b = card.getBoundingClientRect();
    return { left: Math.round(b.left), right: Math.round(b.right), inner: window.innerWidth, height: Math.round(b.height) };
  });
  check('users: the form modal fits the screen', !!modal && modal.left >= -1 && modal.right <= modal.inner + 1, JSON.stringify(modal));
  const modalStacked = await users.evaluate(() => {
    const inputs = [...document.querySelectorAll('#app [data-close-input] input[type="text"], #app [data-close-input] input[type="email"]')];
    const boxes = inputs.slice(0, 3).map(i => i.getBoundingClientRect());
    if (boxes.length < 3) return null;
    const lefts = boxes.map(b => Math.round(b.left));
    const tops = boxes.map(b => Math.round(b.top));
    return {
      sameLeft: Math.max(...lefts) - Math.min(...lefts) <= 2,
      stackedDown: new Set(tops).size === 3,
      boxes: boxes.map((b, i) => [lefts[i], tops[i], Math.round(b.width)]),
    };
  });
  check('users: the modal\'s fields stack one per row', !!modalStacked && modalStacked.sameLeft && modalStacked.stackedDown, JSON.stringify(modalStacked));
  await users.close();

  const messaging = await openPage(phoneCtx, '/messaging', 'Messaging');
  await messaging.waitForTimeout(1500);
  const panels = await messaging.evaluate(() => {
    const rooms = document.getElementById('matrix-rooms');
    const name = document.getElementById('matrix-room-name');
    const chat = name && name.parentElement;
    const input = document.getElementById('matrix-input');
    const send = document.getElementById('matrix-send-btn');
    if (!rooms || !chat || !input || !send) return null;
    const r = rooms.getBoundingClientRect();
    const c = chat.getBoundingClientRect();
    const i = input.getBoundingClientRect();
    const s = send.getBoundingClientRect();
    return {
      stacked: c.top >= r.bottom - 1,
      roomsHeight: Math.round(r.height),
      chatHeight: Math.round(c.height),
      inputRight: Math.round(i.right), sendRight: Math.round(s.right), inner: window.innerWidth,
      composerVisible: i.bottom <= c.bottom + 1 && s.bottom <= c.bottom + 1,
    };
  });
  check('messaging: the channel list and the conversation stack', !!panels && panels.stacked, JSON.stringify(panels));
  check('messaging: the conversation gets a real height', !!panels && panels.chatHeight >= 320, panels ? `chat=${panels.chatHeight}px rooms=${panels.roomsHeight}px` : 'no panels');
  check('messaging: the composer is inside the panel and the screen', !!panels && panels.composerVisible && panels.inputRight <= panels.inner + 1 && panels.sendRight <= panels.inner + 1, panels ? JSON.stringify({ inputRight: panels.inputRight, sendRight: panels.sendRight, inner: panels.inner }) : 'no panels');
  const messagingOutside = await offenders(messaging);
  check('messaging: nothing crosses the right edge', messagingOutside.count === 0 && !messagingOutside.docScrolls, messagingOutside.sample.join(', '));
  const roomRows = await messaging.evaluate(() => {
    const vw = window.innerWidth;
    const rights = [...document.querySelectorAll('#matrix-rooms-list button')].map(b => Math.round(b.getBoundingClientRect().right));
    return { count: rights.length, allFit: rights.every(r => r <= vw + 1) };
  });
  check('messaging: any channel row fits the panel', roomRows.allFit, `${roomRows.count} row(s)`);
  await messaging.close();
  await phoneCtx.close();

  // ---- A desktop, where none of the phone layout may show --------------------------------------
  const desktopCtx = await browser.newContext({ viewport: DESKTOP });
  await desktopCtx.addInitScript((t) => localStorage.setItem('auth_token', t), token);
  const desktopConfig = await openPage(desktopCtx, '/admin/config', 'Configuration Hub');
  const desktopLayout = await tableLayout(desktopConfig);
  check('desktop/config: rows are table rows again', !!desktopLayout && desktopLayout.rowDisplay === 'table-row', desktopLayout ? `row display=${desktopLayout.rowDisplay}` : 'no table');
  check('desktop/config: the header row is back', !!desktopLayout && desktopLayout.theadDisplay === 'table-header-group', desktopLayout ? `thead=${desktopLayout.theadDisplay}` : 'no table');
  const deskLabels = await desktopConfig.evaluate(() => [...document.querySelectorAll('#app table td[data-label]')].filter(td => getComputedStyle(td, '::before').content !== 'none' && getComputedStyle(td, '::before').content !== '').length);
  check('desktop/config: no column name is printed in a cell', deskLabels === 0, `${deskLabels} labelled cell(s) would print`);
  await desktopConfig.close();
  const desktopMessaging = await openPage(desktopCtx, '/messaging', 'Messaging');
  const deskPanels = await desktopMessaging.evaluate(() => {
    const rooms = document.getElementById('matrix-rooms');
    const chat = document.getElementById('matrix-room-name')?.parentElement;
    if (!rooms || !chat) return null;
    const r = rooms.getBoundingClientRect();
    const c = chat.getBoundingClientRect();
    return { sideBySide: c.left >= r.right - 1, roomsTop: Math.round(r.top), chatTop: Math.round(c.top) };
  });
  check('desktop/messaging: the panels sit side by side again', !!deskPanels && deskPanels.sideBySide, JSON.stringify(deskPanels));
  await desktopMessaging.close();
  await desktopCtx.close();

  await browser.close();
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} checks passed`);
  process.exit(passed === results.length ? 0 : 1);
})();
