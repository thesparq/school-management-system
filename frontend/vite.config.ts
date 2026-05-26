import tailwindcss from '@tailwindcss/vite';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';
import { moonbit } from 'vite-plugin-moonbit';

export default defineConfig({
	plugins: [
		tailwindcss(),
		sveltekit(),
		moonbit({
			target: 'js',
			watch: true,
			showLogs: true
		})
	]
});
