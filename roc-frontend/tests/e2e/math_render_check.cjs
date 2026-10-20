#!/usr/bin/env node
// Maths in a senior lesson renders as maths, not as its LaTeX source.
//
// The senior subjects carry equations — `$$1011_2 = 1\times 2^3 + 0\times 2^2 + 1\times 2^1 + 1\times 2^0
// = 11_{10}$$` — and the lesson body stores them as LaTeX inside ordinary strings. KaTeX (vendored in
// `www/katex/`) typesets `$...$` and `$$...$$` after a lesson renders, so this drives one real lesson
// through Chromium and looks at what the pupil sees.
//
// It writes its own lesson (week 99 under the fixture's edge, so it cannot collide with the seeded week 1)
// and deletes it afterwards, then checks that the same content is in the DOM as KaTeX markup — no raw
// `\times`, no `$$` left standing — and that the display formula was typeset as a display formula.
//
//   APP_URL=http://127.0.0.1:8000 SURREAL_URL=http://127.0.0.1:8002/sql node tests/e2e/math_render_check.cjs

const { chromium } = require('playwright');
const os = require('os');
const path = require('path');

const APP = process.env.APP_URL || 'http://127.0.0.1:8000';
const SQL = process.env.SURREAL_URL || 'http://127.0.0.1:8002/sql';
const NS = process.env.SURREAL_NS || 'main';
const DB = process.env.SURREAL_DB || 'lessons';
const USER = process.env.SURREAL_USER || 'root';
const PASS = process.env.SURREAL_PASS || 'root';
const TOKEN = process.env.AUTH_TOKEN || 'dev-skip';
const CLASS = 'class_levels:jss_1';
const SUBJECT = 'subjects:agricultural_science';
const TERM = 'terms:noel_term';
const WEEK = 99;
const SLUG = 'math-render-check';

// The page keeps a token and reads its `exp`, so a bare `dev-skip` reads as expired and the app sends the
// browser to Authentik. The suites therefore hand the page a stand-in JWT and swap the Authorization
// header on every /api/ call for the DEV_MODE token the sandbox backend accepts.
const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const PAGE_TOKEN = `${b64u({ alg: 'RS256', typ: 'JWT' })}.${b64u({
    iss: 'https://auth.johnethel.school/application/o/school-management-system/',
    exp: Math.floor(Date.now() / 1000) + 3600,
    email: 'admin@example.com', name: 'Math Check', groups: ['authentik Admins'],
})}.sig`;

let pass = 0, fail = 0;
const results = [];
function check(label, ok, detail) {
    results.push(ok);
    if (ok) { pass++; console.log(`PASS  ${label}`); }
    else { fail++; console.log(`FAIL  ${label}${detail ? ` — ${detail}` : ''}`); }
}

async function db(statement) {
    const res = await fetch(SQL, {
        method: 'POST',
        headers: {
            authorization: 'Basic ' + Buffer.from(`${USER}:${PASS}`).toString('base64'),
            'surreal-ns': NS, 'surreal-db': DB, 'content-type': 'application/json',
        },
        body: statement,
    });
    if (!res.ok) throw new Error(`db answered ${res.status}: ${(await res.text()).slice(0, 200)}`);
    const blocks = await res.json();
    for (const block of blocks) {
        if (block.status !== 'OK') throw new Error(`${block.status}: ${JSON.stringify(block.result).slice(0, 200)}`);
    }
    return blocks[blocks.length - 1].result;
}

// A lesson body the way the generator writes one, with the maths a senior topic carries.
const LESSON_CONTENT = {
    introduction: 'Every counting system is built on a base. In base two the only digits are 0 and 1, and each column is a power of two: $1011_2 = 11_{10}$.',
    objectives: [
        { objective: 'Convert a number from any base to base ten', taxonomy_level: 'Application' },
        { objective: 'Explain the place value of a digit in a given base', taxonomy_level: 'Comprehension' },
    ],
    content_sections: [
        {
            section_number: 1,
            header: 'PLACE VALUE IN BASE TWO',
            body: 'In base two the columns are the powers of two: $$1011_2 = 1\\times 2^3 + 0\\times 2^2 + 1\\times 2^1 + 1\\times 2^0 = 11_{10}$$',
            sub_points: [
                { sub_number: '(i)', text: 'The rightmost digit is worth $2^0 = 1$.' },
                { sub_number: '(ii)', text: 'The next one to the left is worth $2^1 = 2$.' },
            ],
        },
        {
            section_number: 2,
            header: 'BASES OTHER THAN TWO',
            body: 'Base eight uses digits 0 to 7, so $17_8 = 1\\times 8 + 7 = 15_{10}$.',
            sub_points: [],
        },
    ],
    conclusion: 'A number in any base expands into its place values, and the sum of those values is its decimal form: $11011_2 = 27_{10}$.',
    key_points: ['$$1011_2 = 11_{10}$$', 'Base two has two digits, base eight has eight.'],
    mcq_questions: [
        { question: 'What is $1111_2$ in base ten?', option_a: '15', option_b: '16', option_c: '31', correct_answer: 'a', explanation: '$1 + 2 + 4 + 8 = 15$.' },
    ],
    theoretical_questions: [
        { question: 'Convert $11011_2$ to base ten.', parts: ['Show the place value of each digit.'], model_answer: '$11011_2 = 16 + 8 + 0 + 2 + 1 = 27_{10}$.', marking_scheme: '1 mark for the place values, 1 mark for the sum.' },
    ],
    lesson_steps: [{ step_number: 1, phase: 'INTRODUCTION', duration_mins: 5, teacher_actions: 'Recall base ten place values.', pupil_activities: 'Name the place values.', teaching_strategy: 'Questioning', assessment: 'Oral' }],
    materials: ['Charts of place values', 'Counters'],
    formative_assessment: 'Pupils convert $101_2$ while the teacher checks.',
    summative_assessment: 'A short conversion exercise.',
    success_criteria: ['Converts a three-digit binary number correctly'],
    remediation: 'Return to base ten place values before the powers.',
    extension_activities: ['Convert $0.625_{10}$ to base two.'],
    primary_sources: ['NERDC curriculum'],
    textbook_references: ['New General Mathematics for SSS 1'],
    teacher_tips: 'Insist on writing the powers under the digits before adding.',
    prior_knowledge: ['Place value in base ten'],
    duration_mins: 40,
};

(async () => {
    let lessonId;
    try {
        const rows = await db(`CREATE lessons SET has_subject = (SELECT VALUE id FROM has_subject WHERE \`in\` = ${CLASS} AND out = ${SUBJECT} LIMIT 1)[0], term = ${TERM}, week = ${WEEK}, topic_title = 'Number Base System (maths render check)', slug = '${SLUG}', duration_mins = 40, active = true, context = 'Place value and conversions in base two', content = ${JSON.stringify(LESSON_CONTENT)};`);
        lessonId = rows[0].id;
    } catch (err) {
        console.error(`FAIL  the sandbox could not be prepared — ${err.message}`);
        console.error('      (this check needs the sandbox backend and its database; see README.md)');
        process.exit(1);
    }

    const url = `${APP}/admin/lms?class=${CLASS}&subject=${SUBJECT}&term=${TERM}&lesson=${encodeURIComponent(lessonId)}`;
    const browser = await chromium.launch({ channel: 'chromium' });
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 1000 } });
    await ctx.addInitScript((token) => localStorage.setItem('auth_token', token), PAGE_TOKEN);
    const page = await ctx.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(String(e && e.message ? e.message : e)));
    await page.route('**/api/**', (route) => route.continue({
        headers: { ...route.request().headers(), authorization: `Bearer ${TOKEN}` },
    }));

    try {
        await page.goto(url, { waitUntil: 'load' });
        await page.waitForSelector('#lesson-panel .katex', { timeout: 30000 });
        const inline = await page.locator('#lesson-panel .katex').count();
        const display = await page.locator('#lesson-panel .katex-display').count();
        const body = await page.locator('#lesson-panel').innerText();
        check('a lesson carrying LaTeX typesets it', inline > 0, `${inline} KaTeX nodes`);
        check('the display formula is a display formula', display > 0, `${display} display blocks`);
        check('the inline formula typeset too, not just the display one', inline > display, `${inline} inline vs ${display} display`);
        check('no raw \\times left in the text', !body.includes('\\times'));
        check('no $$ delimiters left standing', !body.includes('$$'));
        check('the arithmetic kept its meaning', body.includes('11') || body.includes('15'), body.slice(0, 80));
        // A local artifact for eyeballing the result; MATH_CHECK_SCREENSHOT says where.
        const shot = process.env.MATH_CHECK_SCREENSHOT || path.join(os.tmpdir(), 'math-render-check.png');
        await page.screenshot({ path: shot, fullPage: true });
        console.log(`      screenshot: ${shot}`);
    } catch (err) {
        check('the lesson page rendered at all', false, err.message);
    } finally {
        check('no page errors', errors.length === 0, JSON.stringify(errors));
        await browser.close();
        try { await db(`DELETE ${lessonId};`); } catch (err) { console.error(`  (cleanup failed: ${err.message})`); }
    }

    const failed = results.filter((r) => !r).length;
    console.log(`\n${results.length - failed}/${results.length} checks passed`);
    process.exit(failed ? 1 : 0);
})();
