// The boot screen's script: it owns the wait, and nothing else.
//
// The app is one wasm bundle — 3.4MB raw, ~400KB compressed — that a phone on a school connection takes a
// while to fetch, compile and start, and before this the page was simply blank for as long as that took.
// The screen itself is in index.html with inline styles, so it paints on the first frame; this file only
// says how the wait is going, and what went wrong if it ends badly. It is deliberately tiny and
// dependency-free: it runs before the app's own module, and it must not be one more thing that can fail.
(function () {
  var status = document.getElementById('boot-status');
  var retry = document.getElementById('boot-retry');
  var booted = false;

  // Called by the app once it has mounted (see the mount call in index.html).
  window.bootScreenDone = function () {
    booted = true;
    var boot = document.getElementById('boot');
    if (boot) boot.remove();
  };

  // Two thresholds: an ordinary wait says nothing more, a slow one explains itself, a very slow one says
  // what to do about it. The person on the other end is a teacher on a phone, not a developer.
  setTimeout(function () {
    if (!booted && status) status.textContent = 'Still loading — a slow connection can take a moment.';
  }, 7000);
  setTimeout(function () {
    if (!booted && status) {
      status.textContent = 'Still loading. If this does not finish, check your connection and reload.';
    }
  }, 20000);

  function fail(reason) {
    if (booted || !status) return;
    status.textContent = 'The app could not start.' + (reason ? ' ' + reason + '.' : '') +
      ' Check the connection and reload; if it keeps happening, tell the school office.';
    if (retry) retry.hidden = false;
  }

  // Called by the app when the mount itself fails (see the try/catch around the mount call in index.html):
  // a bundle the runtime could not fetch is not an uncaught error, so nothing else would reach this screen.
  window.bootScreenFailed = fail;

  // The usual causes are an asset the proxy answered with the wrong thing, or a connection that dropped.
  // The browser's own message is more use than a generic one, so it is passed through (shortened).
  window.addEventListener('error', function (event) {
    fail(event && event.message ? String(event.message).slice(0, 120) : '');
  });
  window.addEventListener('unhandledrejection', function (event) {
    var reason = event && event.reason ? (event.reason.message || event.reason) : '';
    fail(typeof reason === 'string' ? reason.slice(0, 120) : '');
  });
})();
