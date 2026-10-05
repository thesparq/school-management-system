// The OAuth2 round trip through the browser, with Authentik's endpoints intercepted: the redirect
// URI the app sends must be `<origin>/auth/callback` on both legs (that exact string is what has to
// be registered on the Authentik provider), the code must be exchanged on the callback path, and
// the app must then start from the root.
//
//   node tests/e2e/e2e_auth_callback.cjs

const { chromium } = require('playwright');

const appUrl = process.env.APP_URL || 'http://127.0.0.1:8000';
const expectedRedirect = `${appUrl}/auth/callback`;
const tokenUrl = 'https://auth.johnethel.school/application/o/token/';
const authorizeGlob = 'https://auth.johnethel.school/application/o/authorize/**';

const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const jwt = `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({
  iss: 'https://auth.johnethel.school/application/o/school-management-system/',
  exp: Math.floor(Date.now() / 1000) + 3600,
  email: 'students@example.com', name: 'Test Student', groups: ['students'],
})}.sig`;

const results = [];
const check = (name, ok, extra = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); };

(async () => {
  const browser = await chromium.launch({ channel: 'chromium' });
  const errors = [];

  // --- The authorize leg: what the app asks Authentik for ---
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  page.on('pageerror', e => errors.push(e.message.slice(0, 80)));
  let authorizeUrl = '';
  await page.route(authorizeGlob, route => {
    authorizeUrl = route.request().url();
    return route.fulfill({ status: 200, contentType: 'text/html', body: '<p>authentik</p>' });
  });
  await page.goto(appUrl, { waitUntil: 'load' });
  await page.waitForTimeout(3000); // no token: the app starts the flow
  const sentRedirect = new URL(authorizeUrl || 'https://x/?').searchParams.get('redirect_uri');
  check('no token sends the browser to Authentik', authorizeUrl.startsWith('https://auth.johnethel.school/application/o/authorize/'), authorizeUrl.slice(0, 90));
  check('authorize leg asks for the callback path', sentRedirect === expectedRedirect, `redirect_uri=${sentRedirect}`);
  check('authorize leg is a PKCE request', new URL(authorizeUrl || 'https://x/?').searchParams.get('code_challenge_method') === 'S256');
  await ctx.close();

  // --- The callback leg: the code exchange and what happens to the URL afterwards ---
  const ctx2 = await browser.newContext();
  // A real callback arrives in the tab that started the flow, so the PKCE verifier is in
  // sessionStorage. Seed it the way startAuthFlow leaves it.
  await ctx2.addInitScript(() => sessionStorage.setItem('pkce_code_verifier', 'v'.repeat(43)));
  const page2 = await ctx2.newPage();
  page2.on('pageerror', e => errors.push(e.message.slice(0, 80)));
  let exchangeBody = '';
  let strayAuthorize = '';
  await page2.route(tokenUrl, route => {
    exchangeBody = route.request().postData() || '';
    return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ access_token: jwt, token_type: 'Bearer', expires_in: 3600 }) });
  });
  // A redirect back to Authentik here would mean the exchange never happened; record it instead of
  // letting the test wander off to the real host.
  await page2.route(authorizeGlob, route => {
    strayAuthorize = route.request().url();
    return route.fulfill({ status: 200, contentType: 'text/html', body: '<p>authentik</p>' });
  });
  // The app then reads prod through its own API; this suite is about the callback, so pass the
  // backend's dev token for those calls.
  await page2.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: 'Bearer dev-skip' },
  }));
  await page2.goto(`${appUrl}/auth/callback?code=test-code`, { waitUntil: 'load' });
  await page2.waitForTimeout(4000);

  const exchanged = new URLSearchParams(exchangeBody);
  check('the callback path loads the app', await page2.evaluate(() => !!window.app), 'window.app mounted');
  check('the exchange is attempted, not a redirect back to Authentik', strayAuthorize === '', strayAuthorize.slice(0, 80));
  check('the code is exchanged on the callback path', exchanged.get('code') === 'test-code', `code=${exchanged.get('code')}`);
  check('the exchange repeats the same redirect URI', exchanged.get('redirect_uri') === expectedRedirect, `redirect_uri=${exchanged.get('redirect_uri')}`);
  check('the exchange carries the PKCE verifier', (exchanged.get('code_verifier') || '').length > 20);
  check('the token is stored', await page2.evaluate(() => (localStorage.getItem('auth_token') || '').length > 20));
  check('the URL is cleaned back to the root', await page2.evaluate(() => window.location.pathname) === '/', await page2.evaluate(() => window.location.pathname));
  check('no page errors', errors.length === 0, JSON.stringify(errors));

  // A stray visit to the callback path with no code must not leave the router on that path.
  await page2.goto(`${appUrl}/auth/callback`, { waitUntil: 'load' });
  await page2.waitForTimeout(2500);
  check('a bare callback visit starts from the root', await page2.evaluate(() => window.location.pathname) === '/');

  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
