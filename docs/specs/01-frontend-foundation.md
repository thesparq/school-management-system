# Spec: 01-frontend-foundation

## Goal

Configure the SvelteKit frontend with the project's full design system (Tailwind v4 + shadcn-svelte + custom tokens from `ui-context.md`) and verify the toolchain works by rendering a static branded landing page.

## Design

- **CSS architecture**: A single `src/app.css` replaces `src/routes/layout.css`. It contains all `@import` statements (Tailwind, tw-animate-css, shadcn-svelte, fonts), the `:root`/`.dark` CSS variable blocks (using our design colors for shadcn's `--primary`, `--secondary`, `--destructive`, `--ring`), the `@theme inline` block with all design tokens from `ui-context.md`, plugins, variant definitions, and base layer styles.
- **Typography**: Body/display text uses Inter Variable (loaded via `@fontsource-variable/inter`). Mono uses JetBrains Mono Variable (already installed). The `html` base font changes from `font-mono` to `font-sans`.
- **Home page**: A centered, minimal static page — heading "School Management System", subtitle "Welcome to the School Management Portal", and an inert `<Button variant="default" size="lg">` labelled "Get Started" to visually confirm the design system renders in primary blue.
- **Dark mode**: Not wired in this unit. The `.dark` CSS class and `dark:` utility variants remain dormant; they will be activated in Unit 3 (layout shell) when `mode-watcher` is introduced.

## Implementation

### 1. Install font package

```
pnpm add -D @fontsource-variable/inter
```

### 2. Create `src/app.css`

File contents (in order):

**Imports:**
- `@import "tailwindcss";`
- `@import "tw-animate-css";`
- `@import "shadcn-svelte/tailwind.css";`
- `@import "@fontsource-variable/inter";`
- `@import "@fontsource-variable/jetbrains-mono";`

**Variants & plugins:**
- `@custom-variant dark (&:is(.dark *));`
- `@plugin '@tailwindcss/forms';`
- `@plugin '@tailwindcss/typography';`

**`:root` block** — shadcn-svelte CSS variables using project colors where applicable:
- `--primary: #3b82f6` (primary-500) — so `<Button variant="default">` renders primary blue
- `--primary-foreground: oklch(0.985 0 0)`
- `--secondary: #f59e0b` (secondary-500)
- `--secondary-foreground: oklch(0.205 0 0)`
- `--destructive: #ef4444` (error-500)
- `--destructive-foreground: oklch(0.985 0 0)`
- `--ring: #3b82f6` (primary-500)
- `--sidebar-primary: #3b82f6`
- All other variables (`--background`, `--foreground`, `--card`, `--popover`, `--muted`, `--accent`, `--border`, `--input`, `--chart-1` through `--chart-5`, `--radius`, `--sidebar`, `--sidebar-foreground`, `--sidebar-accent`, `--sidebar-accent-foreground`, `--sidebar-border`, `--sidebar-ring`) kept as shadcn-svelte's default oklch values.

**`.dark` block** — shadcn-svelte's existing dark-mode variable overrides, unchanged.

**`@theme inline` block** — all project design tokens:
- `--color-primary-50` through `--color-primary-950` (11 shades from `#eff6ff` to `#172554`)
- `--color-secondary-50` through `--color-secondary-900` (9 shades from `#fffbeb` to `#78350f`)
- `--color-success-50: #f0fdf4`, `--color-success-100: #dcfce7`, `--color-success-500: #22c55e`, `--color-success-600: #16a34a`
- `--color-error-50: #fef2f2`, `--color-error-100: #fee2e2`, `--color-error-500: #ef4444`, `--color-error-600: #dc2626`
- `--color-surface-50: #fafafa`, `--color-surface-100: #f4f4f5`, `--color-surface-200: #e4e4e7`, `--color-surface-700: #3f3f46`, `--color-surface-800: #27272a`, `--color-surface-900: #18181b`, `--color-surface-950: #09090b`
- `--font-sans: 'Inter Variable', system-ui, -apple-system, Segoe UI, Roboto, sans-serif`
- `--font-mono: 'JetBrains Mono Variable', 'Fira Code', monospace`
- `--font-display: 'Inter Variable', system-ui, sans-serif`
- `--radius-sm: 0.25rem`, `--radius-md: 0.375rem`, `--radius-lg: 0.5rem`, `--radius-xl: 0.75rem`, `--radius-full: 9999px`
- All existing shadcn-svelte variable mappings (`--color-background` through `--color-sidebar-ring`) preserved from the original `layout.css`.

**`@layer base` block:**
- `* { @apply border-border outline-ring/50; }`
- `body { @apply bg-background text-foreground; font-family: var(--font-sans); }`
- `html { @apply font-sans; }`

### 3. Install Button shadcn-svelte component

```
npx shadcn-svelte add button
```

### 4. Update `components.json`

Change `"css": "src/routes/layout.css"` to `"css": "src/app.css"`.

### 5. Update import in `src/routes/+layout.svelte`

Change `import './layout.css'` to `import '../app.css'`.

### 6. Replace `src/routes/+page.svelte`

Replace the default SvelteKit welcome page with:

```svelte
<script lang="ts">
  import { Button } from '$lib/components/ui/button';
</script>

<div class="flex min-h-screen items-center justify-center">
  <div class="text-center">
    <h1 class="text-4xl font-display font-bold text-primary-700">
      School Management System
    </h1>
    <p class="mt-2 text-surface-700">
      Welcome to the School Management Portal
    </p>
    <div class="mt-6">
      <Button variant="default" size="lg">Get Started</Button>
    </div>
  </div>
</div>
```

### 7. Delete `src/routes/layout.css`

### 8. Verify build

```
pnpm build
```

The build must succeed with zero errors and zero new warnings.

## Dependencies

| Package | Type | Purpose |
|---|---|---|
| `@fontsource-variable/inter` | devDependency | Inter Variable font for body and display text |

## Verification Checklist

1. `pnpm dev` starts without errors.
2. `pnpm build` succeeds with zero errors and zero new warnings.
3. Home page at `/` displays "School Management System" heading rendered in `font-display`.
4. A primary-blue `<Button>` labelled "Get Started" is visible on the page (rendered via shadcn-svelte's Button component).
5. `getComputedStyle(document.documentElement).getPropertyValue('--color-primary-500')` returns `#3b82f6`.
6. `getComputedStyle(document.documentElement).getPropertyValue('--color-secondary-500')` returns `#f59e0b`.
7. `src/app.css` is the sole CSS entry point; `src/routes/layout.css` does not exist.
8. `components.json` has `"css": "src/app.css"`.
9. No shadcn-svelte generated files were edited (Button was added via CLI, not manually).
10. Inter font is loaded and applied to body text (verifiable via DevTools computed styles on `<body>`).
11. Documentation updated: `progress-tracker.md` reflects Unit 1 as completed.
