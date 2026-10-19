# Senior-secondary lesson context (SSS 1–3)

The other half of the tier. `README.md` proposes `class_levels.tier`; this file is what that tier should make
the lesson generator **do**, so a senior lesson is not a junior lesson with harder words.

## How a senior lesson request is put together

The generator's own signature is

```
GenerateNigerianLesson(subject, class_level, term, week, topic, age_group, context)
```

For a senior class, three of those arguments change and one is worth filling in every time:

| Argument | For SSS |
|---|---|
| `class_level` | `SSS_1` / `SSS_2` / `SSS_3` (new enum members — the enum currently stops at `JSS_3`) |
| `age_group` | the class level's own `age_range` (`14-15 years` for SSS 1 as proposed) |
| the prompt's age-wording branch | the senior branch: exam-standard, quantitative, technical vocabulary, longer content |
| `context` | the tier line + the subject's expectation (below) **+ the week's own content cell from the scheme** |

The last one is the one that makes the biggest difference, and the school already owns it: every week in
`schemes.json` carries a `content` cell — “Definition, history, branches, and importance of chemistry” —
which is exactly the “Additional Context Info” the generator's prompt asks for. A senior lesson should
always be generated with its week's cell, not with a bare topic title.

## What "senior" means, concretely

| | JSS (what the generator does today) | SSS (what the tier asks for) |
|---|---|---|
| Wording | “complex sentences, advanced vocabulary”, one shared branch for JSS 1–3 | examination register: subject terminology used correctly and defined, no simplification of terms of art |
| Content length | 500–600 words of body | 700–900 words of body, with a worked example or a close reading carrying real detail |
| Treatment | explanation of the idea | the idea plus its quantitative or textual practice — a calculation set, a case, a quotation-led analysis |
| Assessment | 9 MCQs and 9 theory questions per lesson | the same shape, but theory questions written the way WAEC/NECO ask them (with “state”, “explain”, “calculate”, “assess” command words) and marked out of the exam's own scheme |
| Outside the textbook | “reference WAEC/NECO syllabi where applicable” | explicit: which paper this topic feeds, and one past-question or practical angle |
| The Nigerian setting | local examples | local examples *and* the national context where the subject has one (the Nigerian economy, the constitution, Nigerian texts, local crops, WAEC prescribed texts) |
| Maths | plain prose and bare numbers | **LaTeX**: `$...$` for inline and `$$...$$` for display, which the app typesets (KaTeX, vendored). Subscripts and superscripts belong in the formula, not in words — `$1011_2 = 11_{10}$`, not "1011 base two equals 11 base ten" |

### How the maths should be written

The calculation subjects (Mathematics, Further Mathematics, Physics, Chemistry, Biology's genetics,
Economics' and Financial Accounting's figures, Geography's bearings and gradients) carry equations every
week, and the app renders LaTeX in every place a lesson shows text: the body, objectives, key points,
questions, options and model answers.

* Inline maths goes in single dollars — `the mole ratio is $1:2$`.
* A formula that sits on its own line goes in double dollars — `$$PV = nRT$$`.
* Standard LaTeX works (`\frac{2}{3}`, `\times`, `\int x^2\,dx`, `\sqrt{5}`, `\begin{aligned}…`), including
the `aligned` block when a derivation runs over several lines.
* Chemical formulae and units stay outside the maths: `$2H_2 + O_2 \rightarrow 2H_2O$` for the equation,
but "23.0 g mol⁻¹" written normally.
* Do not wrap a whole sentence in dollars, and do not use `$` for money — a price is "₦2,500", not
`$2,500` (that last one would typeset as maths and break the sentence).
* One broken formula does not blank a lesson: it shows its own source in red instead.


## Per subject

| Subject | The senior year (from the scheme) | What a senior lesson must carry |
|---|---|---|
| English Language | Every week runs the four skills together — oral (consonants, stress, intonation), structure (nouns, tenses, clauses, affixes), comprehension/vocabulary (registers, antonyms, synonyms), writing (narrative → expository → argumentative → articles, summaries, letters) — with the SS3 year as exam drill. | The week's skill quartet with its register-specific vocabulary; one written model (composition, letter, article); comprehension with inference questions; WAEC-style stems and marking guidance. |
| Mathematics | Number bases, modular arithmetic, indices and logarithms, equations and variations, constructions and proofs, trigonometry, mensuration, statistics; SS2 adds sequences, circle geometry, linear programming, bearings, probability; SS3 adds logic, matrices, spherical geometry, calculus, financial arithmetic. | Rigour over recipe — why a rule holds and when it fails; worked examples to exam standard; table/calculator work; a past-question set. |
| Chemistry | Matter and separation, atomic structure and bonding, the mole and stoichiometry, gas laws, acids/bases/salts, energetics, kinetics, equilibrium, electrochemistry, metals and non-metals, organic chemistry (alkanes → esters, polymers). | Quantitative treatment (mole calculations, titration, solubility), balanced equations with states, IUPAC naming, apparatus and safety, and the qualitative-analysis skills WAEC practicals ask for. |
| Physics | Measurement and units, motion, forces, work/energy/machines, heat, waves, light, electricity and magnetism, electronics, atomic and nuclear physics; SS3 turns to energy conversion, machines and their maintenance. | Units and significant figures, gradients and areas read off graphs, calculations shown step by step, and an experiment embedded in the lesson (apparatus, procedure, expected result). |
| Biology | Cell structure and physiology, nutrition, respiration, transport, growth, reproduction, genetics and evolution, ecology, disease, conservation, biotechnology (genetic engineering, GMOs). | Labelled drawings, observation and microscope work, classification, genetics problems (crosses and ratios), and WAEC practical skills (specimen identification and drawing). |
| Further Mathematics | Sets and inequalities, polynomials, partial fractions, matrices, calculus, conic sections, probability distributions, correlation, vectors, statics and dynamics, modelling, game theory. | Proof-level treatment, longer multi-step problems, and the paper structure kept visible (pure, mechanics, statistics). |
| Government | Concepts (power, authority, legitimacy, sovereignty), systems and constitutions, separation of powers, federalism, political parties and elections, the Nigerian state from colonial rule through the republics and military era, foreign policy, international organisations. | Definition → features → merits/demerits worked through in full; country and Nigerian cases; evaluation questions (“assess”, “to what extent”) with the marking scheme. |
| History | Sources and historiography, land and peoples, pre-colonial political systems, the Atlantic slave trade and its abolition, colonial conquest and administration, nationalism and constitutional development, the civil war, military rule, the republics, Nigeria in the world. | Chronology with dates, source-based questions (extract plus evidence), cause-and-consequence analysis, and an essay answer with a factual spine. |
| Financial Accounting | Bookkeeping to final accounts (double entry, ledgers, trial balance, errors, bank reconciliation), depreciation, partnership accounts, company accounts and the capital market; SS3 adds consignment, joint venture, contract, departmental and branch accounts, public-sector accounting. | Worked ledger and computation sets, the correct format of each account, and past-question computations laid out the way an examiner marks them. |
| Economics | Demand and supply, production and cost, market structures, national income, money and banking, inflation, public finance, international trade and the balance of payments, development planning — with Nigerian case studies throughout. | Graphical analysis drawn and read accurately, calculations (elasticity, national income, multiplier), and structured essay answers illustrated from Nigeria. |
| Commerce | Trade and occupation, production and specialisation, business units (sole trader → companies), capital and credit, banking, insurance, advertising and marketing, consumer protection, payment systems, the capital market. | Definitions with features and functions, Nigerian documents and agencies named correctly, and short-answer plus essay practice. |
| Christian Religious Studies | The synoptic Gospels (Jesus' teachings and miracles, the passion and resurrection), Christian living (faith, the fruit of the Spirit, prayer, witnessing, persecution), biblical leadership (Joseph, Moses, Joshua, the judges), decisions and greed, and civic/social issues (corruption, HIV/AIDS, dignity of labour). | Scripture quoted and referenced accurately, doctrine explained rather than asserted, application to Nigerian life, and answers that give the biblical basis the examiner looks for. |
| Literature in English | Literary appreciation and devices, the genres, then the set texts: African and non-African drama, prose and poetry (SS2 and SS3 study the WAEC 2026–2030 list below). | Close reading of a scene, chapter or poem with quotation; character and theme analysis; devices identified with their effect; essay answers built on textual evidence. |
| Visual Arts | Drawing and painting, design and graphics, modelling and sculpture, indigenous arts (motifs, calabash, murals, craft), Nigerian and Western art history and the modern movements, art professions, studio practice. | A studio task with materials and steps; visual analysis using the elements and principles; artist/period facts; portfolio and exam-practical preparation. |
| Agricultural Science | Crop and animal improvement, husbandry (ornamental plants, horticulture crops, livestock, poultry, aquaculture, apiculture), animal health, agricultural finance, insurance and extension, farm records and marketing, soil and land management. | Terminology tied to Nigerian practice (crops, breeds, tools, agencies), labelled diagrams, farm-record computations, and WAEC practical skills (specimens, tools, machinery). |
| Food and Nutrition | Nutrients and their functions, foods in the locality, the scientific study of foods (tests, heat effects), meal planning and special diets, preservation and storage, kitchen management (equipment, hygiene, safety, first aid), catering practice, consumer education. | Nutrient science with the test and its result, recipe work with quantities, methods and reasons, hygiene and safety explained, and a practical task justified dietetically. |
| Digital Technologies | Hardware and software, operating systems, number systems and data representation, networks, internet and cybersecurity, applications (word processing, spreadsheets, databases, presentations), programming and control structures, data science basics, mobile and cloud, emerging technologies, and a project. | A practical task with steps whose result can be checked (files, formulas, queries, code and expected output), the terminology defined, and trouble-shooting and ethics discussed. |
| Geography | The earth in space and its structure, weather and climate, landforms and denudation, vegetation, population, settlements, agriculture and industry, transport and trade, resources and environmental problems, map reading (scale, bearings, gradients, relief), and GIS basics. | Map and photograph interpretation with measured work (bearings, gradients, cross-sections), diagrams drawn to scale, Nigerian case studies, and data-response questions. |

## WAEC recommended literature, 2026–2030 (from the same PDF)

The document lists the prescribed texts; they are what Literature lessons in SSS 2 and SSS 3 must be built on:

| Kind | Texts |
|---|---|
| Shakespearean | *Antony and Cleopatra* |
| African prose | Pede Hollist – *So the Path Does Not Die*; Elma Shaw – *Redemption Road* |
| Non-African prose | Harper Lee – *To Kill a Mockingbird*; Susanne Bellefeuille – *Path of Lucas: The Journey He Endured* |
| African drama | Bosede Ademilua-Afolayan – *Once Upon an Elephant*; Efua Sutherland – *The Marriage of Anansewa* |
| Non-African drama | J. B. Priestley – *An Inspector Calls*; Robert Bolt – *A Man for All Seasons* |
| African poetry | Gabriel Okara – *Once Upon a Time*; Elizabeth L. A. Kamara – *New Tongue*; Wole Soyinka – *Night*; Niyi Osundare – *Not My Business*; S. O. H. Afriyie-Vidza – *Hearty Garlands*; Syl Cheney-Coker – *The Breast of the Sea* |
| Non-African poetry | Lord Byron – *She Walks in Beauty*; Geoffrey Chaucer – *The Nun's Priest's Tale* (shortened); Seamus Heaney – *Digging*; Maya Angelou – *Still I Rise*; Fleur Adcock – *The Telephone Call*; Wilfred Wilson Gibson – *The Stone* |
