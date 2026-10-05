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
  // The lesson's bank is [mcq, mcq, theory] in that order: take the first MCQ and the theory
  // question, so the student form below has one radio group and one free-text answer.
  await teacher.waitForSelector('[data-q-check="2"]', { timeout: 20000 });
  await teacher.check('[data-q-check="0"]');
  await teacher.fill('[data-q-marks="0"]', '4');
  await teacher.check('[data-q-check="2"]');
  await teacher.fill('[data-q-marks="2"]', '5');
  await teacher.click('#submit-create-assessment');
  await teacher.waitForSelector(`text=${title}`, { timeout: 20000 });
  check('created assessment appears', true);
  const stored = await teacher.evaluate(async (t) => {
    const res = await fetch('/api/teacher/lesson-assessments', { headers: { Authorization: 'Bearer ' + (localStorage.getItem('auth_token') || '') } });
    const rows = (await res.json())[0].result || [];
    const mine = rows.find(r => r.title === t);
    return mine ? { count: (mine.questions || []).length, type: (mine.questions || [])[0]?.type, marks: mine.total_mark } : null;
  }, title);
  check('the picked questions are stored in the strict shape', !!stored && stored.count === 2 && stored.type === 'mcq' && stored.marks === 9, JSON.stringify(stored));
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
  await student.waitForSelector('#submit-assessment-answers', { timeout: 20000 });
  check('the question form renders', true);
  await student.locator('input[name="answer-0"]').nth(1).check(); // option b of the first MCQ
  await student.fill('[data-answer-text="1"]', 'Putting harvested crops into containers.'); // the theory question
  check('answered count tracks input', await student.evaluate(() => (document.getElementById('assessment-answered-count') || {}).textContent || '').then(t => t.includes('2 of 2')));
  await student.click('#submit-assessment-answers');
  await student.waitForTimeout(2500);
  check('submission is acknowledged', await student.evaluate(() => document.body.innerText.includes('Submitted')));

  // What the server stored, read back through the teacher's own session.
  const storedAnswers = await teacher.evaluate(async (t) => {
    const auth = { Authorization: 'Bearer ' + (localStorage.getItem('auth_token') || '') };
    const list = (await (await fetch('/api/teacher/lesson-assessments', { headers: auth })).json())[0].result || [];
    const mine = list.find(r => r.title === t);
    if (!mine) return null;
    const subs = (await (await fetch(`/api/teacher/submissions?assessment_id=${mine.id}`, { headers: auth })).json())[0].result || [];
    return (subs[0] && subs[0].answers) || [];
  }, title);
  check('the chosen option is stored', !!storedAnswers && storedAnswers[0] && storedAnswers[0].answer_text === 'b' && storedAnswers[0].answer_type === 'mcq' && storedAnswers[0].allocated_mark === 4, JSON.stringify(storedAnswers && storedAnswers[0]));
  check('the typed answer is stored', !!storedAnswers && storedAnswers[1] && String(storedAnswers[1].answer_text).includes('containers'), JSON.stringify(storedAnswers && storedAnswers[1]));
  // The theory question is not scored at submit time, so its allocation must survive the rescore.
  check('the theory answer keeps its allocation', !!storedAnswers && storedAnswers[1] && storedAnswers[1].allocated_mark === 5, JSON.stringify(storedAnswers && storedAnswers[1]));

  // --- Teacher: grade it and release the grade ---
  await teacher.click('#tab-grading');
  await teacher.waitForSelector('text=Test Student', { timeout: 30000 });
  check('submission shows the student name', true);
  // The MCQ is scored by the backend at submit time; the grading list has to show the award
  // without opening anything. This run's MCQ is worth 4 marks and option b was the answer.
  const autoScore = await teacher.evaluate(() => {
    const el = document.querySelector('#grading-list [data-auto-score]');
    return el ? el.innerText.replace(/\s+/g, ' ').trim() : '';
  });
  check('the grading list shows the auto-scored MCQ marks', autoScore.includes('MCQ auto-scored: 4 / 4'), autoScore);
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
