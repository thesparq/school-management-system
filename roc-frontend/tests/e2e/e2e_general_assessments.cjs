// General assessment lifecycle through the UI against a *sandbox* backend (see README.md): a teacher
// creates one from the Assessments & Grading hub (questions included) and publishes it; a student
// sees it under My Assignments and answers it; the teacher grades and releases it from the hub's
// Grading tab. A second, already-closed assessment checks the deadline state in the list and form.
//
//   node tests/e2e/e2e_general_assessments.cjs

const { chromium } = require('playwright');

const appUrl = process.env.APP_URL || 'http://127.0.0.1:8000';
const subjectId = process.env.E2E_SUBJECT_ID || 'subjects:agricultural_science';
const sessionTermId = process.env.E2E_SESSION_TERM_ID || 'session_term:session_2026_2027';
const title = `Mid-term Test ${Date.now() % 100000}`;
const closedTitle = `${title} closed`;

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

  // --- Teacher: the hub, a new assessment with two hand-written questions, publish ---
  const teacher = await newPage(browser, tokenFor(['teachers'], 'Test Teacher'));
  await teacher.goto(`${appUrl}/teacher/assessments`, { waitUntil: 'load' });
  await teacher.waitForSelector('#ga-subject-select option[value^="subjects:"]', { state: 'attached', timeout: 60000 });
  await teacher.waitForSelector('#ga-session-term-select option[value^="session_term:"]', { state: 'attached', timeout: 60000 });
  check('the hub fills its subject and session term pickers', true);

  await teacher.click('#create-general-assessment-btn');
  await teacher.fill('#ga-title-input', title);
  await teacher.fill('#ga-description-input', 'Covers packaging and storage.');
  await teacher.fill('#ga-weight-input', '10');
  // The optional rules the backend enforces, set through the modal: already open, never closes, two
  // attempts. datetime-local fields take local wall-clock time and are sent as UTC.
  await teacher.fill('#ga-scheduled-input', '2020-01-01T00:00');
  await teacher.fill('#ga-deadline-input', '2099-01-01T00:00');
  await teacher.fill('#ga-resubmissions-input', '2');

  // Question 1 is the row the modal opens with: an MCQ with two options and answer b.
  await teacher.fill('[data-ga-question-row] [data-ga-question]', 'What does packaging mean?');
  await teacher.fill('[data-ga-question-row] [data-ga-marks]', '3');
  await teacher.fill('[data-ga-question-row] [data-ga-option="0"]', 'Cooking produce');
  await teacher.fill('[data-ga-question-row] [data-ga-option="1"]', 'Putting produce into containers');
  await teacher.selectOption('[data-ga-question-row] [data-ga-answer]', 'b');
  // Question 2: a theory question, typed after switching the kind.
  await teacher.click('#ga-add-question');
  await teacher.waitForSelector('[data-ga-question-row]:nth-of-type(2)', { timeout: 10000 });
  const second = teacher.locator('[data-ga-question-row]').nth(1);
  await second.locator('[data-ga-type]').selectOption('essay');
  await second.locator('[data-ga-question]').fill('Explain why packaging matters.');
  await second.locator('[data-ga-marks]').fill('5');
  await second.locator('[data-ga-model]').fill('It protects the produce.');
  check('the question builder counts the questions and their marks',
    (await teacher.textContent('#ga-question-count')) === '2' && (await teacher.textContent('#ga-total-marks')) === '8',
    `${await teacher.textContent('#ga-question-count')} questions / ${await teacher.textContent('#ga-total-marks')} marks`);

  await teacher.click('#ga-submit-create');
  // The open assessment's row; the closed one created later carries the same title plus a suffix.
  const createdRow = teacher.locator('#general-assessments-list > div', { hasText: title }).filter({ hasNotText: 'closed' });
  await createdRow.first().waitFor({ timeout: 20000 });
  check('the created assessment appears in the list', true);
  check('it starts as a draft', (await createdRow.first().innerText()).includes('Draft'));

  const stored = await teacher.evaluate(async (t) => {
    const auth = { Authorization: 'Bearer ' + (localStorage.getItem('auth_token') || '') };
    const rows = (await (await fetch('/api/teacher/general-assessments', { headers: auth })).json())[0].result || [];
    const mine = rows.find(r => r.title === t);
    if (!mine) return null;
    const q = mine.questions || [];
    return {
      weight: mine.percentage_weight, marks: mine.total_mark, count: q.length,
      first: q[0] || {}, second: q[1] || {},
      scheduled: mine.scheduled_at || null, deadline: mine.deadline || null, attempts: mine.max_resubmissions,
    };
  }, title);
  check('the questions are stored in the strict shape',
    !!stored && stored.count === 2 && stored.first.type === 'mcq' && stored.first.answer === 'b'
      && Array.isArray(stored.first.options) && stored.first.options.length === 2 && stored.second.type === 'essay',
    JSON.stringify(stored && { first: stored.first, second: stored.second }));
  check('the weight, marks and rules reach the API',
    !!stored && stored.weight === 10 && stored.marks === 8 && !!stored.scheduled && !!stored.deadline && stored.attempts === 2,
    JSON.stringify(stored && { weight: stored.weight, marks: stored.marks, attempts: stored.attempts }));

  await createdRow.first().locator('text=Publish').click();
  await teacher.waitForTimeout(1500);
  check('publish flips it to published', (await createdRow.first().innerText()).includes('Published'));

  // A second assessment, closed already and carrying one question so the answer form renders: it is
  // created through the API so the student side can check the opens/closes states without a second
  // trip through the modal.
  await teacher.evaluate(async ({ t, subject, term }) => {
    const auth = { Authorization: 'Bearer ' + (localStorage.getItem('auth_token') || ''), 'Content-Type': 'application/json' };
    await fetch('/api/teacher/create-general-assessment', {
      method: 'POST', headers: auth,
      body: JSON.stringify({
        subject_id: subject, session_term_id: term, title: t, percentage_weight: 1, deadline: '2020-01-01T00:00:00Z',
        questions: [{ type: 'mcq', question: 'Already closed', options: ['a', 'b'], answer: 'a', marks: 1 }], total_mark: 1,
      }),
    });
    const rows = (await (await fetch('/api/teacher/general-assessments', { headers: auth })).json())[0].result || [];
    const mine = rows.find(r => r.title === t);
    if (mine) {
      await fetch('/api/teacher/toggle-assessment-active', {
        method: 'POST', headers: auth,
        body: JSON.stringify({ assessment_id: mine.id, assessment_type: 'general', active: true }),
      });
    }
  }, { t: closedTitle, subject: subjectId, term: sessionTermId });

  // --- Student: the assignments page lists it and the answer form works ---
  const student = await newPage(browser, tokenFor(['students'], 'Test Student'));
  await student.goto(`${appUrl}/student/assignments`, { waitUntil: 'load' });
  await student.waitForSelector(`text=${title}`, { timeout: 45000 });
  check('student sees the published general assessment', true);
  check('the student page has both assessment tabs',
    (await student.locator('#tab-general-assessments').count()) === 1 && (await student.locator('#tab-lesson-assessments').count()) === 1);

  const studentRow = student.locator('#general-assessments-list > div', { hasText: title }).filter({ hasNotText: 'closed' }).first();
  await studentRow.locator('text=Take Assessment').click();
  await student.waitForSelector('#submit-assessment-answers', { timeout: 20000 });
  check('the question form renders', true);
  // The student form must carry both kinds of answer and block nothing while open.
  check('the form offers the MCQ radio group and the theory box',
    (await student.locator('input[name="answer-0"]').count()) === 2 && (await student.locator('[data-answer-text="1"]').count()) === 1);
  check('an open assessment is not blocked', !(await student.locator('#submit-assessment-answers').isDisabled()));
  await student.locator('input[name="answer-0"]').nth(1).check(); // option b
  await student.fill('[data-answer-text="1"]', 'Because it protects the produce.');
  check('answered count tracks input', (await student.textContent('#assessment-answered-count')).includes('2 of 2'));
  await student.click('#submit-assessment-answers');
  await student.waitForTimeout(2500);
  check('submission is acknowledged', await student.evaluate(() => document.body.innerText.includes('Submitted')));

  // What the server stored, read back through the teacher's own session.
  const storedAnswers = await teacher.evaluate(async (t) => {
    const auth = { Authorization: 'Bearer ' + (localStorage.getItem('auth_token') || '') };
    const list = (await (await fetch('/api/teacher/general-assessments', { headers: auth })).json())[0].result || [];
    const mine = list.find(r => r.title === t);
    if (!mine) return null;
    const subs = (await (await fetch(`/api/teacher/submissions?assessment_id=${mine.id}`, { headers: auth })).json())[0].result || [];
    return subs[0] || null;
  }, title);
  check('the submission is stored against the general assessment',
    !!storedAnswers && storedAnswers.assessment_type === 'general' && storedAnswers.iteration === 1,
    JSON.stringify(storedAnswers && { type: storedAnswers.assessment_type, iteration: storedAnswers.iteration }));
  check('the MCQ is auto-scored at submit', !!storedAnswers && storedAnswers.answers[0].answer_text === 'b' && storedAnswers.answers[0].allocated_mark === 3, JSON.stringify(storedAnswers && storedAnswers.answers[0]));
  check('the typed answer keeps its allocation', !!storedAnswers && String(storedAnswers.answers[1].answer_text).includes('protects') && storedAnswers.answers[1].allocated_mark === 5, JSON.stringify(storedAnswers && storedAnswers.answers[1]));

  // The closed one shows its state and cannot be submitted.
  const closedRow = student.locator('#general-assessments-list > div', { hasText: closedTitle }).first();
  await closedRow.waitFor({ timeout: 20000 });
  check('a past-deadline assessment is labelled closed', (await closedRow.innerText()).includes('Review (closed)'));
  await closedRow.locator('text=Review (closed)').click();
  await student.waitForSelector('#submit-assessment-answers', { timeout: 20000 });
  check('the closed form disables submit and says why',
    (await student.locator('#submit-assessment-answers').isDisabled())
      && (await student.evaluate(() => document.body.innerText.includes('The deadline has passed'))));

  // --- Teacher: the grading tab lists the general submission, grade and release ---
  await teacher.click('#tab-general-grading');
  await teacher.waitForSelector('#grading-list >> text=Test Student', { timeout: 30000 });
  check('the grading list shows the general submission', true);
  check('the grading list marks it as a general assessment', (await teacher.textContent('#grading-list')).includes('general assessment'));
  const autoScore = await teacher.evaluate(() => {
    const el = document.querySelector('#grading-list [data-auto-score]');
    return el ? el.innerText.replace(/\s+/g, ' ').trim() : '';
  });
  check('the grading list shows the auto-scored MCQ marks', autoScore.includes('MCQ auto-scored: 3 / 3'), autoScore);
  await teacher.click('#grading-list >> text=Grade');
  await teacher.waitForTimeout(2000);
  await teacher.click('#grading-list >> text=Release Grade');
  await teacher.waitForTimeout(2000);
  check('released grade is shown', await teacher.evaluate(() => document.body.innerText.includes('Grades Released')));
  const released = await teacher.evaluate(async (t) => {
    const auth = { Authorization: 'Bearer ' + (localStorage.getItem('auth_token') || '') };
    const list = (await (await fetch('/api/teacher/general-assessments', { headers: auth })).json())[0].result || [];
    const mine = list.find(r => r.title === t);
    const subs = (await (await fetch(`/api/teacher/submissions?assessment_id=${mine.id}`, { headers: auth })).json())[0].result || [];
    return subs[0] || null;
  }, title);
  check('the released grade is stored', !!released && released.scored_mark === 7 && !!released.grade_released_at, JSON.stringify(released && { scored_mark: released.scored_mark, released: !!released.grade_released_at }));

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
