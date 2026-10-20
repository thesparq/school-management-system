// The nav bar's avatar menu and the sign-out flow, in Chromium. The sign-out navigation is
// intercepted (we never leave the app), and the token is read back from the browser context's
// storage for the app's origin — the harness seeds a token on every navigation, so a plain
// `localStorage` read after navigating would see its own seed rather than the app's clearing.
//
//   node tests/e2e/e2e_signout.cjs

const { chromium } = require('playwright');

const appUrl = process.env.APP_URL || 'http://127.0.0.1:8000';

const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const tokenFor = (groups, name, email) => `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({
  iss: 'https://auth.johnethel.school/application/o/school-management-system/',
  exp: Math.floor(Date.now() / 1000) + 3600,
  email, name, groups,
})}.sig`;

const results = [];
const check = (name, ok, extra = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); };

(async () => {
  const browser = await chromium.launch({ channel: 'chromium' });
  const ctx = await browser.newContext();
  // Seed the token on navigation, but stop after this flag: the sign-out's own clearing is what the
  // last check reads, and a seed would mask it.
  await ctx.addInitScript(t => { if (!sessionStorage.getItem('no_seed')) localStorage.setItem('auth_token', t); },
    tokenFor(['administrators'], 'Samuel Iyeh', 'thesparq@example.com'));
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message.slice(0, 120)));
  await page.route('**/api/**', r => r.continue({ headers: { ...r.request().headers(), authorization: `Bearer ${process.env.AUTH_TOKEN || 'dev-skip'}` } }));
  let signoutUrl = '';
  await page.route('**/application/o/school-management-system/end-session/**', r => {
    signoutUrl = r.request().url();
    return r.fulfill({ status: 200, contentType: 'text/html', body: '<p>authentik</p>' });
  });

  await page.goto(`${appUrl}/`, { waitUntil: 'load' });
  await page.waitForTimeout(3500);
  const menuHidden = () => page.evaluate(() => { const m = document.getElementById('user-menu'); return !m || m.classList.contains('hidden'); });

  check('the avatar menu starts closed', await menuHidden());
  await page.click('#user-menu-button');
  await page.waitForTimeout(400);
  check('clicking the avatar opens it', !(await menuHidden()));
  const menuText = await page.evaluate(() => (document.getElementById('user-menu') || {}).innerText || '');
  check('it shows who is signed in', menuText.includes('Samuel Iyeh') && menuText.includes('thesparq@example.com'), menuText.replace(/\n+/g, ' | '));
  check('and offers Sign Out', menuText.includes('Sign Out'));
  await page.mouse.click(500, 320); // a point in the content area, well away from the menu
  await page.waitForTimeout(400);
  check('a click outside closes it', await menuHidden());

  await page.click('#user-menu-button');
  await page.waitForTimeout(300);
  await page.evaluate(() => sessionStorage.setItem('no_seed', '1'));
  await page.click('#user-menu >> text=Sign Out');
  await page.waitForTimeout(1500);

  check('signing out ends the Authentik session', signoutUrl.includes('/end-session/'), signoutUrl.slice(0, 90));
  check('and comes back to this origin\'s callback', decodeURIComponent(signoutUrl).includes(`${appUrl}/auth/callback`));
  const state = await ctx.storageState();
  const appOrigin = state.origins.find(o => o.origin === appUrl) || { localStorage: [] };
  check('the token is gone from storage', appOrigin.localStorage.filter(i => i.name === 'auth_token' && i.value).length === 0);
  check('no page errors', errors.length === 0, JSON.stringify(errors));

  // --- The signed-out card itself, as a person sees it ---
  // What is on screen while a sign-out is under way. The sign-out navigation is held open (its request is
  // never answered: a new document replaces this one only when it commits), because a click driven through
  // the protocol waits for the navigation it starts — and that is the state being measured. Phone width,
  // where the card used to sit in a fixed 60vh band: high on the page, with the empty half below it.
  const cardCtx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  await cardCtx.addInitScript(t => localStorage.setItem('auth_token', t), tokenFor(['administrators'], 'Samuel Iyeh', 'thesparq@example.com'));
  const cardPage = await cardCtx.newPage();
  cardPage.on('pageerror', e => errors.push(e.message.slice(0, 120)));
  await cardPage.route('**/api/**', r => r.continue({ headers: { ...r.request().headers(), authorization: `Bearer ${process.env.AUTH_TOKEN || 'dev-skip'}` } }));
  await cardPage.route('**/application/o/school-management-system/end-session/**', () => { /* held open */ });
  await cardPage.goto(`${appUrl}/`, { waitUntil: 'load' });
  await cardPage.waitForTimeout(4000);
  // Measured inside the page and reported on the console: a `page.evaluate` is refused while the held
  // navigation is pending, and the console is the channel that stays open. The click is scheduled the
  // same way, and for the same reason (a click driven through the protocol waits for its navigation).
  const cardSeen = new Promise(resolve => cardPage.on('console', m => {
    const text = m.text();
    if (text.startsWith('SIGNED_OUT_CARD ')) resolve(JSON.parse(text.slice('SIGNED_OUT_CARD '.length)));
  }));
  await cardPage.evaluate(() => {
    const measure = () => {
      const h2 = [...document.querySelectorAll('h2')].find(x => x.textContent.includes('Authentication Required'));
      if (!h2) return null;
      const cardEl = h2.closest('div[class*="rounded-xl"]');
      const icon = h2.parentElement.querySelector('div');
      const text = h2.parentElement.querySelector('p');
      const c = cardEl.getBoundingClientRect(), i = icon.getBoundingClientRect(), t = text.getBoundingClientRect();
      return {
        gapAboveCard: Math.round(c.top - 64), gapBelowCard: Math.round(innerHeight - c.bottom),
        gapAboveIcon: Math.round(i.top - c.top), gapBelowText: Math.round(c.bottom - t.bottom),
        width: Math.round(c.width), overflowX: document.documentElement.scrollWidth > innerWidth,
      };
    };
    setTimeout(() => {
      const b = [...document.querySelectorAll('#user-menu button')].find(x => x.innerText.includes('Sign Out'));
      if (b) b.click();
      setTimeout(() => console.log('SIGNED_OUT_CARD ' + JSON.stringify(measure())), 400);
    }, 50);
  });
  await cardPage.waitForTimeout(1200);
  const card = await Promise.race([cardSeen, new Promise(r => setTimeout(() => r(null), 1000))]);
  check('the signed-out card is on the page', !!card, JSON.stringify(card));
  check('it sits in the middle of the visible page', card && Math.abs(card.gapAboveCard - card.gapBelowCard) < 40,
    card ? `above ${card.gapAboveCard}px, below ${card.gapBelowCard}px` : 'no card');
  check('and is evenly padded inside', card && card.gapAboveIcon > 20 && Math.abs(card.gapAboveIcon - card.gapBelowText) < 24,
    card ? `above the icon ${card.gapAboveIcon}px, below the text ${card.gapBelowText}px` : 'no card');
  check('with nothing spilling sideways at phone width', card && card.overflowX === false && card.width <= 390 - 32,
    card ? `card ${card.width}px wide, viewport 390px` : 'no card');
  await cardCtx.close();

  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
