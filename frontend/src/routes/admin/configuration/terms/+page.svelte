<script lang="ts">
	import type { PageData } from './$types';
	import { Card, CardContent } from '$lib/components/ui/card';
	import { Switch } from '$lib/components/ui/switch/index.js';
	import {
		Table, TableBody, TableCell, TableHead, TableHeader, TableRow
	} from '$lib/components/ui/table';
	import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
	import { addToast } from '$lib/stores/toast';

	interface TermItem {
		id: string;
		name: string;
		active: boolean;
		sort_order: number;
	}

	let { data }: { data: PageData } = $props();
	let terms: TermItem[] = $state(data.terms);

	$effect(() => { terms = data.terms; });

	async function handleToggle(termId: string, newActive: boolean) {
		const idx = terms.findIndex(t => t.id === termId);
		if (idx === -1) return;
		const prev = terms[idx].active;
		terms[idx].active = newActive;
		terms = [...terms];

		try {
			const res = await fetch('/api/admin/toggle-term', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ term_id: termId, active: newActive }),
			});
			if (!res.ok) {
				const err = await res.json().catch(() => ({ error: { message: 'Request failed' } }));
				throw new Error(err.error?.message ?? 'Request failed');
			}
			addToast('success', 'Term updated', `${terms[idx].name} is now ${newActive ? 'visible' : 'hidden'} to students.`);
		} catch (e) {
			terms[idx].active = prev;
			terms = [...terms];
			addToast('error', 'Failed to update term', e instanceof Error ? e.message : 'Unknown error');
		}
	}
</script>

<div class="mx-auto max-w-6xl space-y-6">
	<h1 class="text-2xl font-display font-bold text-primary-700">Terms</h1>

	{#if data.termsError}
		<StatusCard variant="error" title="Failed to load terms" description={data.termsError} onRetry={() => window.location.reload()} />
	{:else if terms.length === 0}
		<StatusCard variant="info" title="No Terms Available" description="No terms exist in the database yet." />
	{:else}
		<Card>
			<CardContent class="p-0">
				<Table>
					<TableHeader>
						<TableRow>
							<TableHead>Name</TableHead>
							<TableHead class="w-24">Active</TableHead>
							<TableHead class="w-24">Sort Order</TableHead>
						</TableRow>
					</TableHeader>
					<TableBody>
						{#each terms as term (term.id)}
							<TableRow>
								<TableCell class="font-medium">{term.name}</TableCell>
								<TableCell>
									<Switch
										checked={term.active}
										onCheckedChange={(checked) => handleToggle(term.id, checked)}
									/>
								</TableCell>
								<TableCell class="text-surface-500 text-sm">{term.sort_order}</TableCell>
							</TableRow>
						{/each}
					</TableBody>
				</Table>
			</CardContent>
		</Card>
	{/if}
</div>
