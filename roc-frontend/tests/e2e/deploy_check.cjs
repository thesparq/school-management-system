// Smoke-checks a deployed origin: does the container reach the database, does it serve the SPA and its
// assets, and is the local auth bypass really off? `auth_config_check.cjs` covers the Authentik
// wiring; this covers the deployment itself. No browser, no dependencies beyond node's fetch.
//
//   node tests/e2e/deploy_check.cjs [origin]
//
// Run it against the local dev backend to see the shape: every check passes there except the
// DEV_MODE one, which is the point of it — locally the bypass is on by design.

const origin = (process.argv[2] || process.env.APP_URL || 'https://app.johnethel.school').replace(/\/$/, '');

const results = [];
const check = (name, ok, extra = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); };

const get = async (path, init) => {
  try {
    const res = await fetch(`${origin}${path}`, { redirect: 'manual', ...init });
    return { status: res.status, headers: res.headers, body: await res.text() };
  } catch (e) {
    return { status: 0, headers: new Headers(), body: String(e.message || e) };
  }
};

(async () => {
  console.log(`origin ${origin}\n`);

  const health = await get('/health');
  check('the origin answers /health', health.status === 200, `status ${health.status}`);
  check('the container reaches SurrealDB', health.body.includes('surreal db is healthy'), health.body.slice(0, 80));

  const index = await get('/');
  check('the SPA is served at the root', index.status === 200 && index.body.includes('app.wasm'), `status ${index.status}, ${index.body.length} bytes`);

  const assets = [['/app.wasm', 'application/wasm'], ['/runtime.js', 'javascript'], ['/dist.css', 'text/css']];
  for (const [path, type] of assets) {
    const res = await get(path);
    check(`${path} is served as ${type}`, res.status === 200 && (res.headers.get('content-type') || '').includes(type), `${res.status}, ${res.headers.get('content-type') || '-'}, ${res.body.length} bytes`);
  }

  // The bypass: DEV_MODE must be off, so the token the test suites use is just an invalid token, and a
  // request with no token at all is unauthorized rather than a 500.
  const devToken = await get('/api/student/subjects', { headers: { Authorization: 'Bearer dev-skip' } });
  check('the dev-skip token is refused (DEV_MODE off)', devToken.status === 401, `status ${devToken.status}: ${devToken.body.slice(0, 60)}`);
  const noToken = await get('/api/student/subjects');
  check('an unauthenticated API call is 401, not a server error', noToken.status === 401, `status ${noToken.status}: ${noToken.body.slice(0, 60)}`);

  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
