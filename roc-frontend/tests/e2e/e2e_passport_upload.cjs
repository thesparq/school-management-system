// Passport upload from the admin form against a *sandbox* backend (see README.md).
//
// Default mode drives the whole flow with R2's PUT intercepted (no real credentials): the file
// input asks the backend to sign a URL, PUTs the photo, the public URL lands in the passport
// field, and the created profile carries it.
//
// `503` mode runs the same form against a backend started *without* the R2 variables and checks
// that the form shows the backend's own message instead of pretending the upload worked.
//
//   APP_URL=http://127.0.0.1:8308 node tests/e2e/e2e_passport_upload.cjs
//   APP_URL=http://127.0.0.1:8308 node tests/e2e/e2e_passport_upload.cjs 503

const { chromium } = require('playwright');

const appUrl = process.env.APP_URL || 'http://127.0.0.1:8308';
const mode = process.argv[2] || 'upload';
const stamp = Date.now();

const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const token = `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({
  iss: 'https://auth.johnethel.school/application/o/school-management-system/',
  exp: Math.floor(Date.now() / 1000) + 3600,
  email: 'bursar@example.com', name: 'Admin User', groups: ['administrators'],
})}.sig`;

const results = [];
const check = (name, ok, extra = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); };

// A 1x1 PNG, so the browser has a real image to read for the preview.
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64'
);

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

  // Whatever the page uploads to R2. Intercepted, so no bucket and no CORS policy are needed;
  // the preflight the browser sends for a cross-origin PUT is answered here too.
  const puts = [];
  await page.route('https://example.r2.cloudflarestorage.com/**', async (route) => {
    const req = route.request();
    if (req.method() === 'OPTIONS') {
      return route.fulfill({
        status: 204,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'PUT, OPTIONS',
          'Access-Control-Allow-Headers': 'content-type',
        },
      });
    }
    puts.push({ url: req.url(), method: req.method(), bytes: (req.postDataBuffer() || Buffer.alloc(0)).length });
    await route.fulfill({ status: 200, headers: { 'Access-Control-Allow-Origin': '*' }, body: '' });
  });

  // The create request, so the profile's passport value can be read out of it. Continuing with
  // the same dev-skip header the catch-all API route adds, since this route takes precedence.
  const creates = [];
  await page.route('**/api/users', async (route) => {
    if (route.request().method() === 'POST') { creates.push(route.request().postData() || ''); }
    await route.continue({
      headers: { ...route.request().headers(), authorization: `Bearer ${process.env.AUTH_TOKEN || 'dev-skip'}` },
    });
  });

  await page.goto(`${appUrl}/admin/users`, { waitUntil: 'load' });
  await page.waitForSelector('text=Add New User', { timeout: 45000 });
  check('user management page loads', true);

  const surname = `Upload${stamp % 10000}`;
  const fill = (placeholder, value) => page.locator(`input[placeholder="${placeholder}"]`).fill(value);
  await fill('e.g. Adamu', 'Grace');
  await fill('e.g. Musa', surname);
  await fill('e.g. adamu@johnethel.school', `upload${stamp}@example.com`);
  await fill('jss_1, jss_2, jss_3, year_1 ...', 'jss_2');
  await page.locator('input[type="date"]').fill('2011-09-14');

  await page.setInputFiles('#passport-file-input', { name: 'passport.png', mimeType: 'image/png', buffer: PNG });

  if (mode === '503') {
    await page.waitForFunction(
      () => (document.getElementById('passport-upload-status') || {}).textContent
        && document.getElementById('passport-upload-status').textContent.includes('not configured'),
      { timeout: 20000 }
    ).catch(() => {});
    const status = await page.evaluate(() => (document.getElementById('passport-upload-status') || {}).textContent || '');
    check('the form shows the backend 503 message', status.includes('R2 uploads are not configured'), status.slice(0, 120));
    check('no upload was attempted without a signed URL', puts.length === 0, JSON.stringify(puts));
    check('the passport URL field stays empty', await page.evaluate(() => !document.querySelector('#passport-url-field input').value));
    check('no page errors', errors.length === 0, JSON.stringify(errors));

    await browser.close();
    const failed = results.filter(r => !r).length;
    console.log(`\n${results.length - failed}/${results.length} checks passed`);
    process.exit(failed ? 1 : 0);
  }

  // The public URL the backend answered with must land in the passport field.
  await page.waitForFunction(
    () => /^https:\/\/cdn\.example\.com\/student\/passports\/.+\.jpg$/.test(document.querySelector('#passport-url-field input').value),
    { timeout: 20000 }
  ).catch(() => {});
  const passportUrl = await page.evaluate(() => document.querySelector('#passport-url-field input').value);
  check('the file input fills the passport field with the public URL', /^https:\/\/cdn\.example\.com\/student\/passports\/.+\.jpg$/.test(passportUrl), passportUrl);
  check('the photo was PUT to the signed URL', puts.length === 1 && puts[0].method === 'PUT' && puts[0].bytes === PNG.length,
    JSON.stringify(puts.map(p => ({ method: p.method, bytes: p.bytes, path: new URL(p.url).pathname }))));
  check('the signed URL carries the key and the sigv4 parameters',
    puts.length === 1 && /\/test\/student\/passports\/.+\.jpg\?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIDEXAMPLE%2F\d{8}%2Fauto%2Fs3%2Faws4_request&X-Amz-Date=\d{8}T\d{6}Z&X-Amz-Expires=600&X-Amz-SignedHeaders=host&X-Amz-Signature=[0-9a-f]{64}$/.test(puts[0].url),
    puts.length === 1 ? puts[0].url.slice(0, 160) : '');
  const status = await page.evaluate(() => (document.getElementById('passport-upload-status') || {}).textContent || '');
  check('the form reports the upload', status.includes('Photo uploaded'), status.slice(0, 120));

  // The field is what the create path submits, so the profile stores the uploaded photo's URL.
  await page.click('text=Add User');
  await page.waitForSelector('text=User created', { timeout: 20000 }).catch(() => {});
  check('form submit reports success', await page.evaluate(() => document.body.innerText.includes('User created')));
  const created = creates.length === 1 ? creates[0] : '';
  check('the created profile carries the uploaded public URL', created.includes(`"passport":"${passportUrl}"`), created.slice(0, 200));
  await page.waitForTimeout(2500);
  check('created student appears in the table', await page.evaluate((s) => document.body.innerText.includes(s), surname));
  check('no page errors', errors.length === 0, JSON.stringify(errors));

  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
