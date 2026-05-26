<script lang="ts">
	import type { PageData } from './$types';
	import { Card, CardContent, CardHeader, CardTitle } from '$lib/components/ui/card';

	let { data }: { data: PageData } = $props();
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
	</div>
</div>
