<script lang="ts">
	import type { PageData } from './$types';
	import { Card, CardContent, CardHeader, CardTitle } from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';

	let { data }: { data: PageData } = $props();

	let pingResult = $state<string | null>(null);
	let pingError = $state<string | null>(null);
	let isPinging = $state(false);

	async function testConnection() {
		isPinging = true;
		pingResult = null;
		pingError = null;

		try {
			const res = await fetch('/api/ping');
			const body = await res.json();
			if (body.data) {
				pingResult = body.data;
			} else {
				pingError = body.error?.message ?? 'Unknown error';
			}
		} catch {
			pingError = 'Network error — could not reach server.';
		} finally {
			isPinging = false;
		}
	}
</script>

<div class="mx-auto max-w-4xl space-y-6">
	<div>
		<h1 class="text-2xl font-display font-bold text-primary-700">
			Welcome, {data.user.name}
		</h1>
		<p class="mt-1 text-sm text-surface-700">
			{data.user.roles[0] ?? 'User'} dashboard
		</p>
	</div>

	<div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
		<Card>
			<CardHeader>
				<CardTitle class="text-base">Quick Actions</CardTitle>
			</CardHeader>
			<CardContent>
				<p class="text-sm text-surface-700">Dashboard widgets will appear here.</p>
			</CardContent>
		</Card>

		<Card>
			<CardHeader>
				<CardTitle class="text-base">Connection Status</CardTitle>
			</CardHeader>
			<CardContent class="space-y-3">
				<Button onclick={testConnection} disabled={isPinging}>
					{isPinging ? 'Testing...' : 'Test Connection'}
				</Button>

				{#if pingResult}
					<p class="text-sm text-success-500">Gateway: {pingResult}</p>
				{/if}

				{#if pingError}
					<p class="text-sm text-error-500">{pingError}</p>
				{/if}
			</CardContent>
		</Card>
	</div>
</div>
