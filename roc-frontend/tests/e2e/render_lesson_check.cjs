// Runs the page's own renderLesson against a real lesson, with a stubbed DOM, and reports what a
// browser would show. Catches the data-shape bugs the prod schema exposes (objectives are objects,
// content lives under lesson.content, introduction/conclusion must render).
//
//   node tests/e2e/render_lesson_check.cjs
//   LESSON_ID=lessons:... APP_URL=http://127.0.0.1:8000 AUTH_TOKEN=dev-skip node tests/e2e/render_lesson_check.cjs

const fs = require('fs');
const path = require('path');

const appUrl = process.env.APP_URL || 'http://127.0.0.1:8000';
const token = process.env.AUTH_TOKEN || 'dev-skip';
const lessonId = process.env.LESSON_ID || 'lessons:3648pqtmuxopbjp1tyfk';
const root = path.resolve(__dirname, '..', '..');

class El {
  constructor(id) {
    this.id = id; this._html = ''; this.textContent = ''; this.value = ''; this.dataset = {}; this.style = {};
    const set = new Set();
    this.classList = { add: (...c) => c.forEach(x => set.add(x)), remove: (...c) => c.forEach(x => set.delete(x)),
      toggle: (c, on) => (on ? set.add(c) : set.delete(c)), contains: (c) => set.has(c) };
  }
  set innerHTML(v) { this._html = v; }
  get innerHTML() { return this._html; }
  addEventListener() {} appendChild() {} querySelectorAll() { return []; } scrollIntoView() {}
}

const els = {};
global.document = {
  getElementById: (id) => (els[id] = els[id] || new El(id)),
  querySelector: () => null, querySelectorAll: () => [], addEventListener: () => {}, createElement: () => new El(),
  documentElement: new El('html'),
};
global.window = { location: { pathname: '/', search: '', hash: '', origin: appUrl, href: '' },
  history: { pushState() {}, replaceState() {} }, addEventListener() {},
  localStorage: { getItem: () => null, setItem() {}, removeItem() {} } };
global.localStorage = window.localStorage;
global.crypto = { getRandomValues: (a) => { for (let i = 0; i < a.length; i++) a[i] = i; return a; } };
global.fetch = async () => ({ ok: true, json: async () => [] });
global.setTimeout = () => 0;

(async () => {
  const html = fs.readFileSync(path.join(root, 'www', 'index.html'), 'utf8');
  const script = html.match(/<script type="module">([\s\S]*?)<\/script>/)[1]
    .replace(/^\s*import \{ mount \} from '.*';$/m, '');
  const factory = new Function('mount', 'return (async () => {\n' + script + '\nreturn { renderLesson };\n})();');
  const api = await factory(async () => ({ onPort() {}, sendUrl() {} }));

  const res = await fetch(`${appUrl}/api/student/lesson?lesson_id=${encodeURIComponent(lessonId)}`,
    { headers: { Authorization: `Bearer ${token}` } });
  const data = await res.json();
  const lesson = (Array.isArray(data) ? data[0]?.result : data.result)?.[0];
  if (!lesson) throw new Error(`no lesson in the response for ${lessonId}`);

  api.renderLesson(lesson);
  const out = els['lesson-panel'] ? els['lesson-panel'].innerHTML : '';
  const content = lesson.content || {};
  const firstObjective = (content.objectives || [])[0];
  const firstSection = (content.content_sections || [])[0] || {};
  const firstSubPoint = (firstSection.sub_points || [])[0];

  const checks = {
    'introduction rendered': !!content.introduction && out.includes('id="section-introduction"') && out.includes(content.introduction.slice(0, 40)),
    'conclusion rendered': !!content.conclusion && out.includes('id="section-conclusion"') && out.includes(content.conclusion.slice(0, 40)),
    'objectives rendered as text': !!firstObjective && out.includes((firstObjective.objective || firstObjective).slice(0, 40)) && !out.includes('taxonomy_level'),
    'content section body rendered': !!firstSection.body && out.includes(firstSection.body.slice(0, 40)),
    'sub-points rendered': !!firstSubPoint && out.includes((firstSubPoint.text || '').slice(0, 40)),
    'key points rendered': (content.key_points || []).length > 0 && out.includes(String(content.key_points[0]).slice(0, 40)),
    'no raw JSON leaked': !out.includes('{"objective"') && !out.includes('"taxonomy_level"'),
  };

  let failed = 0;
  for (const [name, ok] of Object.entries(checks)) { console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}`); if (!ok) failed++; }
  console.log(failed ? `\n${failed} check(s) failed` : '\nAll render checks passed');
  process.exit(failed ? 1 : 0);
})();
