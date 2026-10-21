// What the page costs to load, in Chromium, against a *sandbox* backend (see README.md): the boot screen
// while the bundle comes down, what is deliberately not fetched until it is needed, and what a second
// visit to the same page fetches again.
//
//   node tests/e2e/e2e_boot_and_cache.cjs
//
// The bundle is ~3.4MB of wasm (~400KB compressed), so the wait is the thing a person sees first, and the
// caching is the difference between paying for it once per build and once per page load. The caching
// checks need the backend to serve a validator: `www/build-id.txt`, written by `build.roc`. Without it
// they fail with that name in the message rather than passing quietly.

const { chromium } = require('playwright');

const appUrl = process.env.APP_URL || 'http://127.0.0.1:8000';

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

  // ---- The boot screen, on a bundle that takes its time ----------------------------------------
  {
    const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
    await ctx.addInitScript((t) => localStorage.setItem('auth_token', t), token);
    const page = await ctx.newPage();
    await page.route('**/api/**', (route) => route.continue({
      headers: { ...route.request().headers(), authorization: `Bearer ${process.env.AUTH_TOKEN || 'dev-skip'}` },
    }));
    // Hold the bundle back: what a phone on a school connection sees for the first seconds.
    await page.route('**/app.wasm', async (route) => { await new Promise((r) => setTimeout(r, 11000)); await route.continue(); });

    const html = await (await page.request.get(`${appUrl}/`)).text();
    check('the served page carries the boot screen', /id="boot"/.test(html) && /\/boot\.js/.test(html));
    check('the boot screen names the app, with the logo and a spinner', /School Management System/.test(html) && /\/logo\.jpg/.test(html) && /boot-spinner/.test(html));
    check('its styles are inline, not in a stylesheet', /#boot \{[\s\S]*position: fixed/.test(html));

    await page.goto(`${appUrl}/admin/config`, { waitUntil: 'commit' });
    await page.waitForSelector('#boot', { timeout: 8000 });
    const first = await page.evaluate(() => {
      const boot = document.getElementById('boot');
      return { visible: !!boot && boot.getBoundingClientRect().height > 100, status: document.getElementById('boot-status').textContent };
    });
    check('while the bundle is still coming down, the boot screen is what is on screen', first.visible, first.status);
    check('and it says what it is doing', /Loading the app/.test(first.status), first.status);
    await page.waitForTimeout(8000);
    const slow = await page.evaluate(() => document.getElementById('boot-status').textContent);
    check('after a few seconds it says the wait is a slow connection, in the school\'s words', /slower|slow connection|Still loading/.test(slow), slow);
    await page.waitForSelector('h1:has-text("Configuration Hub")', { timeout: 45000 });
    await page.waitForTimeout(500);
    const gone = await page.evaluate(() => document.getElementById('boot') === null);
    check('once the app is up the boot screen is gone', gone);
    await ctx.close();
  }

  // ---- A bundle that never arrives -----------------------------------------------------------------
  {
    const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
    // Signed in: without a token the app sends the browser to Authentik instead of mounting, and the boot
    // screen's failure path is never reached (which is how this check first passed for the wrong reason).
    await ctx.addInitScript((t) => localStorage.setItem('auth_token', t), token);
    const page = await ctx.newPage();
    await page.route('**/app.wasm', (route) => route.abort());
    await page.goto(`${appUrl}/`, { waitUntil: 'commit' });
    await page.waitForTimeout(6000);
    const failed = await page.evaluate(() => ({
      status: (document.getElementById('boot-status') || {}).textContent || '',
      retry: !!(document.getElementById('boot-retry') && !document.getElementById('boot-retry').hidden),
    }));
    check('a bundle that never arrives says so', /could not start/i.test(failed.status), failed.status);
    check('and offers the one thing that helps: reload', failed.retry);
    await ctx.close();
  }

  // ---- What the admin pages do not fetch, and what a second visit costs ---------------------------
  {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
    await ctx.addInitScript((t) => localStorage.setItem('auth_token', t), token);
    const page = await ctx.newPage();
    await page.route('**/api/**', (route) => route.continue({
      headers: { ...route.request().headers(), authorization: `Bearer ${process.env.AUTH_TOKEN || 'dev-skip'}` },
    }));
    const requested = [];
    page.on('request', (r) => requested.push(r.url()));
    const first = {};
    page.on('response', (r) => {
      const u = r.url();
      if (u.endsWith('/app.wasm') || u.endsWith('/dist.css')) {
        first[u] = { status: r.status(), etag: r.headers()['etag'] || '', cacheControl: r.headers()['cache-control'] || '' };
      }
    });

    await page.goto(`${appUrl}/admin/users`, { waitUntil: 'load' });
    await page.waitForSelector('h1:has-text("User Management")', { timeout: 45000 });
    await page.waitForTimeout(2500);
    const katexOnAdmin = requested.filter((u) => u.includes('/katex/')).length;
    check('an admin page fetches no KaTeX', katexOnAdmin === 0, `${katexOnAdmin} request(s)`);

    const fonts = await page.evaluate(() => {
      const link = [...document.querySelectorAll('link[rel="stylesheet"]')].find((l) => l.href.includes('fonts.googleapis'));
      return link ? { media: link.media, resolves: link.sheet !== null } : null;
    });
    check('the webfonts arrive beside the page rather than in front of it', !!fonts && fonts.media === 'all' && fonts.resolves, JSON.stringify(fonts));

    // The same page again, in the same context: what the validator is for. Chromium *as this harness
    // launches it* never consults its own cache — its second load of every resource is a plain 200 with
    // the validator unread — so the browser half is not checkable here and the server half is: the
    // validator the first response carried, sent back, must earn a 304 with no body, and a validator from
    // an older build must earn the bundle again.
    const wasm = first[`${appUrl}/app.wasm`];
    const css = first[`${appUrl}/dist.css`];
    check('the bundle is served with a validator and `no-cache`',
      !!wasm && !!wasm.etag && /no-cache/.test(wasm.cacheControl || ''), JSON.stringify(wasm));
    check('so is the stylesheet',
      !!css && !!css.etag && /no-cache/.test(css.cacheControl || ''), JSON.stringify(css));
    if (wasm && wasm.etag) {
      const revalidated = await page.request.get(`${appUrl}/app.wasm`, { headers: { 'If-None-Match': wasm.etag } });
      check('the validator earns a 304 with no body', revalidated.status() === 304, `status ${revalidated.status()}`);
      const stale = await page.request.get(`${appUrl}/app.wasm`, { headers: { 'If-None-Match': '"an-older-build"' } });
      check('a validator from an older build earns the bundle again', stale.status() === 200, `status ${stale.status()}`);
    } else {
      check('the validator earns a 304 with no body', false, 'no validator to send: is www/build-id.txt there?');
      check('a validator from an older build earns the bundle again', false, 'no validator to send');
    }
    await ctx.close();
  }

  await browser.close();
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} checks passed`);
  process.exit(passed === results.length ? 0 : 1);
})();
