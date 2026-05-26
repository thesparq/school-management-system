<script lang="ts">
	import { Button } from '$lib/components/ui/button';

	let loading = $state(false);
	let error = $state('');

	async function signIn() {
		loading = true;
		error = '';
		try {
			const res = await fetch('/api/auth/login');
			if (!res.ok) {
				const body = await res.json();
				error = body.error?.message ?? 'Failed to initiate sign in';
				loading = false;
				return;
			}
			const data = await res.json();
			window.location.href = data.url;
		} catch {
			error = 'Network error. Please try again.';
			loading = false;
		}
	}
</script>

<div class="flex min-h-screen items-center justify-center bg-surface-50">
	<div class="w-full max-w-sm rounded-lg border border-surface-200 bg-white p-8 text-center shadow-sm">
		<h1 class="text-2xl font-display font-bold text-primary-700">
			School Management System
		</h1>
		<p class="mt-2 text-sm text-surface-700">
			Sign in to access the school management portal
		</p>

		{#if error}
			<p class="mt-4 text-sm text-error-500">{error}</p>
		{/if}

		<div class="mt-6">
			<Button onclick={signIn} disabled={loading} variant="default" size="lg" class="w-full">
				{loading ? 'Redirecting...' : 'Sign in with Authentik'}
			</Button>
		</div>
	</div>
</div>
