<script lang="ts">
	import { Button } from '$lib/components/ui/button';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	let isLoggingOut = $state(false);
	let error = $state('');

	async function handleLogout() {
		if (isLoggingOut) return;
		isLoggingOut = true;
		error = '';

		try {
			const res = await fetch('/api/auth/logout', {
					method: 'POST',
					headers: { 'X-Requested-With': 'XMLHttpRequest' }
				});
			if (!res.ok) {
				error = 'Logout failed. Please try again.';
				isLoggingOut = false;
				return;
			}
			const body = await res.json();
			if (body.url) {
				window.location.href = body.url;
			}
		} catch {
			error = 'An error occurred during logout. Please try again.';
			isLoggingOut = false;
		}
	}
</script>

<div class="flex min-h-screen items-center justify-center">
	<div class="text-center">
		<h1 class="text-2xl font-display font-bold text-primary-700">
			Hello, {data.user.name}
		</h1>
		<p class="mt-1 text-sm text-surface-700">{data.user.email}</p>

		{#if error}
			<p class="mt-4 text-sm text-error-500">{error}</p>
		{/if}

		<div class="mt-6">
			<Button onclick={handleLogout} variant="outline" disabled={isLoggingOut}>
				{isLoggingOut ? 'Signing out...' : 'Sign out'}
			</Button>
		</div>
	</div>
</div>
