// Checks an origin's auth wiring against the real Authentik, without a browser: the redirect URI the
// app sends has to be registered on its provider, and the userinfo endpoint the backend validates
// tokens against has to exist. The second one is the trap this exists for — Authentik serves a
// single userinfo endpoint for the whole instance (`/application/o/userinfo/`), so deriving it from
// the per-application issuer 404s and every real token is then rejected. `dev-skip` skips Authentik
// entirely, so nothing local catches that.
//
//   node tests/e2e/auth_config_check.cjs [origin]
//
// Env overrides: AUTH_HOST, CLIENT_ID, ISSUER. Without an argument it checks the deployed origin;
// `http://127.0.0.1:8000` only passes if that origin is registered too.

const crypto = require('crypto');

const origin = process.argv[2] || process.env.APP_URL || 'https://app.johnethel.school';
const authHost = process.env.AUTH_HOST || 'https://auth.johnethel.school';
const clientId = process.env.CLIENT_ID || 'ZMZS84aG53o8USUYqH2lX1muDbH3GSZ4Q03KFhSu';
const issuer = process.env.ISSUER || `${authHost}/application/o/school-management-system/`;
const expectedUserinfo = `${authHost}/application/o/userinfo/`;

const results = [];
const check = (name, ok, extra = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); };

// Mirrors `userinfo_url` in roc-backend/AuthUrls.roc: cut the per-application issuer back to its
// host before appending the instance-wide path. If the two ever disagree, this fails.
const derivedUserinfo = (value) => value.includes('/application/o/')
  ? `${value.split('/application/o/')[0]}/application/o/userinfo/`
  : `${value}userinfo`;

const authorizeStatus = async (redirectUri) => {
  const codeChallenge = crypto.createHash('sha256').update('probe-verifier-0123456789abcdefghijklmn').digest('base64url');
  const url = new URL(`${authHost}/application/o/authorize/`);
  url.search = new URLSearchParams({
    client_id: clientId, response_type: 'code', scope: 'openid profile email',
    code_challenge: codeChallenge, code_challenge_method: 'S256', redirect_uri: redirectUri,
  });
  const res = await fetch(url, { redirect: 'manual' });
  return res.status;
};

const userinfoStatus = async (url) =>
  (await fetch(url, { headers: { Authorization: 'Bearer not-a-real-token' } })).status;

(async () => {
  console.log(`origin ${origin}\nissuer ${issuer}\n`);

  const discovery = await (await fetch(`${issuer}.well-known/openid-configuration`)).json();
  check('discovery advertises the instance-wide userinfo endpoint', discovery.userinfo_endpoint === expectedUserinfo, discovery.userinfo_endpoint);
  check('the backend derives the same endpoint', derivedUserinfo(issuer) === discovery.userinfo_endpoint, derivedUserinfo(issuer));
  check('that endpoint answers 401 for a bad token, not 404', await userinfoStatus(discovery.userinfo_endpoint) === 401, `status ${await userinfoStatus(discovery.userinfo_endpoint)}`);

  const callback = `${origin}/auth/callback`;
  check('the app\'s redirect URI is registered on the provider', await authorizeStatus(callback) === 302, `${callback} → ${await authorizeStatus(callback)}`);
  const stray = `${origin}/not-registered`;
  check('an unregistered redirect URI is rejected (control)', await authorizeStatus(stray) === 400, `${stray} → ${await authorizeStatus(stray)}`);

  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
