# KaTeX, vendored

The unmodified distribution files of **KaTeX 0.16.11** (MIT — see the upstream package; the licence is the
only thing not copied here, and it lives at <https://github.com/KaTeX/KaTeX/blob/main/LICENSE>):

| File | What it is |
|---|---|
| `katex.min.js` | the typesetter (defines `window.katex`) |
| `auto-render.min.js` | KaTeX's `contrib` extension that walks a rendered element's text nodes and typesets the delimiters (defines `window.renderMathInElement`) |
| `katex.min.css` | the stylesheet, whose `@font-face` rules name `fonts/*.woff2` |
| `fonts/*.woff2` | the 20 fonts that stylesheet names — woff2 only |

**Why vendored:** the app is served from one origin and has to typeset maths on the school's network, so a
CDN is not an option. `Dockerfile.app` copies `roc-frontend/www` wholesale, so these ship with the image.

**Why woff2 only:** every browser this app targets (Chromium, and anything from 2016 on) reads woff2, which
is the first `src` entry the stylesheet lists. The `.woff` and `.ttf` fallbacks are not shipped: a browser
old enough to need them falls back to showing the LaTeX source, which is what a page that cannot load KaTeX
does anyway.

**How it is used:** `../index.html` links the stylesheet in `<head>` and loads both scripts with `defer`, and
`typesetMath(el)` (beside `escHtml` in that file) calls `renderMathInElement` after a lesson, a question bank
or an answer form is rendered — delimiters `$...$`, `$$...$$`, `\(...\)`, `\[...\]`, with
`throwOnError: false` so one broken formula cannot blank a lesson.

**Updating:** `npm pack katex@<version>` (or `https://registry.npmjs.org/katex/-/katex-<version>.tgz`), then
replace the three files and the woff2 fonts. Nothing else in the app changes.

**The check:** `../../tests/e2e/math_render_check.cjs` writes a lesson carrying LaTeX and asserts in
Chromium that it came out as KaTeX (display formula, inline formulas, no leftover `$`).
