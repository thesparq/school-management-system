import tailwindcss from '@tailwindcss/vite';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';
import { moonbit } from 'vite-plugin-moonbit';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
	plugins: [
		tailwindcss(),
		sveltekit(),
		moonbit({
			target: 'js',
			watch: true,
			showLogs: true
		})
  ],
  server: {
      fs: {
        allow: [
          // Default: allow everything in the project root (frontend/)
          path.resolve(__dirname),
          // Also allow the monorepo root node_modules (where pnpm hoists)
          path.resolve(__dirname, '../node_modules'),
        ],
      },
    },
});
