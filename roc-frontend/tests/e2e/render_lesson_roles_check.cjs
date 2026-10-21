// The lesson renderer's split between viewers, with no browser and no backend: it runs the page's own
// script against a lesson shaped like the ones prod stores, and reports which sections each viewer is
// shown. A pupil reads the lesson itself; staff read the whole record — the plan, the guidance, the
// references, the warm-up and practice lines, and the answer keys behind the question banks.
//
//   node tests/e2e/render_lesson_roles_check.cjs
//
// The record below carries every section prod's lessons carry, so a section that stops rendering (or
// starts reaching a pupil) fails here rather than in a classroom.

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..', '..');
const results = [];
const check = (name, ok, extra = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`); };

// --- a DOM stub, enough for the panel and the scroll-spy code that follows it ---
class El {
  constructor(id) {
    this.id = id; this._html = ''; this.textContent = ''; this.value = ''; this.dataset = {}; this.style = {};
    // The page reads `children` (the section navigator counts its dots), so the stub carries it.
    this.children = [];
    const set = new Set();
    this.classList = {
      add: (...c) => c.forEach(x => set.add(x)), remove: (...c) => c.forEach(x => set.delete(x)),
      toggle: (c, on) => (on ? set.add(c) : set.delete(c)), contains: (c) => set.has(c),
    };
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
global.window = {
  location: { pathname: '/', search: '', hash: '', origin: 'http://localhost:8000', href: '' },
  history: { pushState() {}, replaceState() {} }, addEventListener() {},
  localStorage: { getItem: () => null, setItem() {}, removeItem() {} },
};
global.localStorage = window.localStorage;
global.crypto = { getRandomValues: (a) => a };
const realSetTimeout = global.setTimeout;
global.fetch = async () => ({ ok: true, json: async () => [] });
global.setTimeout = () => 0;
window.fetch = global.fetch;

// A lesson as prod stores one: the metadata at the top, every section under `content`.
const LESSON = {
  id: 'lessons:sample', slug: 'sample', week: 3, duration_mins: 40,
  topic_title: 'Figures of Speech', subject_name: 'English Studies', term_name: 'Noel Term',
  content: {
    objectives: [
      { objective: 'define figure of speech', taxonomy_level: 'Knowledge' },
      { objective: 'identify four figures of speech in a sentence', taxonomy_level: 'Comprehension' },
    ],
    introduction: 'Writers choose words for the pictures they make in a reader\'s mind.',
    content_sections: [
      { section_number: 1, header: 'SIMILE', body: 'A simile compares with like or as.',
        sub_points: [{ sub_number: '(i)', text: 'Simile always uses like or as.' }, { sub_number: '(ii)', text: 'It compares two different things.' }] },
      { section_number: 2, header: 'METAPHOR', body: 'A metaphor says one thing is another.' },
    ],
    key_points: ['A figure of speech is a special way of using words.', 'Similes use like or as.'],
    conclusion: 'Figures of speech make writing vivid.',
    prior_knowledge: ['Words can have literal and non-literal meanings.'],
    success_criteria: ['Pupils can define figure of speech.'],
    extension_activities: ['Write a paragraph using three figures of speech.'],
    lesson_steps: [{ step_number: 1, phase: 'INTRODUCTION', teacher_actions: 'Ask what an exaggeration is.',
      pupil_activities: 'Pupils listen and answer.', teaching_strategy: 'Questioning', duration_mins: 7, assessment: 'Checks understanding.' }],
    materials: ['Chart of the five figures of speech.'],
    formative_assessment: 'Questioning during the lesson.',
    summative_assessment: 'End-of-lesson written exercise.',
    remediation: 'Pair struggling pupils with a stronger reader.',
    teacher_tips: 'Keep the examples local and familiar.',
    textbook_references: ['Macmillan English Course, Book 3, pp. 78-82.'],
    primary_sources: ['NERDC Basic Education Curriculum, Primary 3.'],
    mcq_questions: [{ question: 'Which uses like or as?', option_a: 'Metaphor', option_b: 'Simile', option_c: 'Hyperbole',
      correct_answer: 'b', explanation: 'A simile always uses like or as.' }],
    theoretical_questions: [{ question: 'What is a figure of speech?', parts: ['Give two examples.'],
      model_answer: 'A special way of using words to create pictures.', marking_scheme: '2 marks for the definition.' }],
    model: 'deepseek/deepseek-v4-flash',
  },
};

(async () => {
  const html = fs.readFileSync(path.join(root, 'www', 'index.html'), 'utf8');
  const script = html.match(/<script type="module">([\s\S]*?)<\/script>/)[1]
    .replace(/^\s*import \{ mount \} from '.*';$/m, '');
  // The role is module state the page sets from the token's groups; the harness reaches it the same
  // way that code does, rather than the page growing a test-only setter.
  const factory = new Function('mount', 'return (async () => {\n' + script
    + '\nreturn { renderLesson, lessonSections, setRole: (r) => { _viewerRole = r; } };\n})();');
  const api = await factory(async () => ({ onPort() {}, sendUrl() {} }));
  global.setTimeout = realSetTimeout;

  const headingsFor = (role) => {
    api.setRole(role);
    return api.lessonSections(LESSON)
      .filter(sec => sec.viewers === 'all' || role === 'Admin' || role === 'Teacher')
      .map(sec => sec.heading);
  };

  const student = headingsFor('Student');
  const teacher = headingsFor('Teacher');
  const admin = headingsFor('Admin');

  const STUDENT_SECTIONS = ['Learning Objectives', 'Introduction', 'SIMILE', 'METAPHOR', 'Key Points', 'Conclusion'];
  const STAFF_ONLY = ['Before you start', "What you'll be able to do", 'Extra practice',
    'Lesson Plan', 'Instructional Materials', 'Formative Assessment', 'Summative Assessment',
    'Support for Struggling Learners', "Teacher's Notes", 'Textbook References', 'Primary Sources',
    'Revision Questions (multiple choice)', 'Theoretical Questions'];

  check('a pupil is shown the lesson itself and nothing the school prepares around it',
    STUDENT_SECTIONS.every(h => student.includes(h)) && student.length === STUDENT_SECTIONS.length, JSON.stringify(student));
  check('a teacher is shown every section the record carries',
    STAFF_ONLY.every(h => teacher.includes(h)) && teacher.length === STUDENT_SECTIONS.length + STAFF_ONLY.length,
    `${teacher.length} sections`);
  check('an admin reads the same lesson as a teacher', JSON.stringify(admin) === JSON.stringify(teacher));

  api.setRole('Student');
  await api.renderLesson(LESSON);
  const panel = els['lesson-panel']._html;

  check('the pupil\'s page is the filtered list', STUDENT_SECTIONS.every(h => panel.includes(h)));
  check('and carries none of the staff headings', STAFF_ONLY.every(h => !panel.includes(h)),
    STAFF_ONLY.filter(h => panel.includes(h)).join(', '));
  check('nor the answer keys behind the question banks',
    !panel.includes('correct_answer') && !panel.includes('model_answer') && !panel.includes('marking_scheme')
      && !panel.includes('A simile always uses like or as.'), '');
  check('nor the teacher\'s own plan and guidance',
    !panel.includes('Ask what an exaggeration is.') && !panel.includes('Keep the examples local and familiar.'));
  check('no tables in a pupil\'s lesson', (panel.match(/<table/g) || []).length === 0);
  check('the staff lesson renders its tables',
    (api.lessonSections(LESSON).map(s => (s.html.match(/<table/g) || []).length).reduce((a, b) => a + b, 0)) === 3);
  check('the taxonomy level rides the pupil\'s objectives', panel.includes('Knowledge'));
  check('sub-points keep the generator\'s own numbering', panel.includes('(i)') && panel.includes('(ii)'));
  check('objectives render as text, not JSON', panel.includes('define figure of speech') && !panel.includes('taxonomy_level'));
  check('no raw JSON leaked into the page', !/\{"|\"objective\":/.test(panel));

  await api.renderLesson({ id: 'lessons:empty', topic_title: 'Empty' });
  check('a lesson with no content says so instead of rendering nothing',
    els['lesson-panel']._html.includes('No lesson content available yet'));

  const failed = results.filter(r => !r).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
