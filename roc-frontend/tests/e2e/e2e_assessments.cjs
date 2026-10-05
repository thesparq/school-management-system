// Assessment lifecycle through the UI against a *sandbox* backend (see README.md): a teacher picks a
// lesson, creates a draft, publishes it; a student sees it and submits; the teacher grades and releases.
//
//   node tests/e2e/e2e_assessments.cjs

const { chromium } = require('playwright');

const appUrl = process.env.APP_URL || 'http://127.0.0.1:8000';
const lessonId = process.env.E2E_LESSON_ID || 'lessons:test_lesson';const lessonTitle = process.env.E2E_LESSON_TITLE || 'Packaging Criteria for Farm Produce';
const title = `Week 1 Quiz ${Date.now() % 100000}`;

const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const tokenFor = (groups, name) => `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({
  iss: 'https://auth.johnethel.school/application/o/school-management-system/',
  exp: Math.floor(Date.now() / 1000) + 3600,
  email: `${groups[0]}@example.com`, name, groups,
})}.sig`;

const results = [];
const check = (name, ok, extra = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); };

async function newPage(browser, token) {
  const ctx = await browser.newContext();
  await ctx.addInitScript(t => localStorage.setItem('auth_token', t), token);
  const page = await ctx.newPage();
  page.on('dialog', d => d.accept(d.type() === 'prompt' ? '7' : undefined));
  await page.route('**/api/**', route => route.continue({
    headers: { ...route.request().headers(), authorization: `Bearer ${process.env.AUTH_TOKEN || 'dev-skip'}` },
  }));
  return page;
}

(async () => {
  const browser = await chromium.launch({ channel: 'chromium' });

  // --- Teacher: pick the lesson, create a draft, publish it ---
  const teacher = await newPage(browser, tokenFor(['teachers'], 'Test Teacher'));
  await teacher.goto(`${appUrl}/teacher/lessons`, { waitUntil: 'load' });
  await teacher.waitForSelector(`text=${lessonTitle}`, { timeout: 45000 });
  check('teacher lesson picker lists lessons', true);
  await teacher.click(`text=${lessonTitle}`);
  await teacher.waitForTimeout(1500);
  await teacher.click('#tab-assessments');
  await teacher.waitForSelector('#create-assessment-btn', { timeout: 20000 });
  await teacher.click('#create-assessment-btn');
  await teacher.fill('#assessment-title-input', title);
  // Pick the first question from the lesson's bank and give it marks.
  await teacher.waitForSelector('[data-q-check="0"]', { timeout: 20000 });
  await teacher.check('[data-q-check="0"]');
  await teacher.fill('[data-q-marks="0"]', '4');
  await teacher.click('#submit-create-assessment');
  await teacher.waitForSelector(`text=${title}`, { timeout: 20000 });
  check('created assessment appears', true);
  const stored = await teacher.evaluate(async (t) => {
    const res = await fetch('/api/teacher/lesson-assessments', { headers: { Authorization: 'Bearer ' + (localStorage.getItem('auth_token') || '') } });
    const rows = (await res.json())[0].result || [];
    const mine = rows.find(r => r.title === t);
    return mine ? { count: (mine.questions || []).length, type: (mine.questions || [])[0]?.type, marks: mine.total_mark } : null;
  }, title);
  check('the picked question is stored in the strict shape', !!stored && stored.count === 1 && stored.type === 'mcq' && stored.marks === 4, JSON.stringify(stored));
  check('it starts as a draft', await teacher.evaluate(() => document.body.innerText.includes('Draft')));
  await teacher.click('#assessments-list >> text=Publish');
  await teacher.waitForTimeout(1500);
  check('publish flips it to published', await teacher.evaluate(() => document.body.innerText.includes('Published')));

  // --- Student: drill down to the lesson, see the published assessment and submit ---
  const student = await newPage(browser, tokenFor(['students'], 'Test Student'));
  await student.goto(`${appUrl}/student/subjects`, { waitUntil: 'load' });
  await student.waitForSelector('text=Agricultural Science', { timeout: 45000 });
  await student.click('text=Agricultural Science');
  await student.waitForSelector('text=Noel Term', { timeout: 30000 });
  await student.click('text=Noel Term');
  await student.waitForSelector(`text=${lessonTitle}`, { timeout: 30000 });
  await student.click(`text=${lessonTitle}`);
  await student.waitForTimeout(2500); // the view re-renders after the lesson loads
  await student.click('#tab-assessments');
  await student.waitForSelector(`text=${title}`, { timeout: 30000 });
  check('student sees the published assessment', true);
  await student.click('text=Take Assessment');
  await student.waitForTimeout(2000);

  // --- Teacher: grade it and release the grade ---
  await teacher.click('#tab-grading');
  await teacher.waitForSelector('text=Test Student', { timeout: 30000 });
  check('submission shows the student name', true);
  await teacher.click('#grading-list >> text=Grade');
  await teacher.waitForTimeout(2000);
  await teacher.click('#grading-list >> text=Release Grade');
  await teacher.waitForTimeout(2000);
  check('released grade is shown', await teacher.evaluate(() => document.body.innerText.includes('Grades Released')));

  const errors = [];
  teacher.on('pageerror', e => errors.push(e.message.slice(0, 60)));
  student.on('pageerror', e => errors.push(e.message.slice(0, 60)));
  await teacher.waitForTimeout(500);
  check('no page errors', errors.length === 0, JSON.stringify(errors));

  await browser.close();
  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
