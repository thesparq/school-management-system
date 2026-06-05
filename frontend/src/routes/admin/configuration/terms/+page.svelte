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
	let toggling = $state<Record<string, boolean>>({});

	$effect(() => { terms = data.terms; });

	async function handleToggle(termId: string, newActive: boolean) {
		const idx = terms.findIndex(t => t.id === termId);
		if (idx === -1) return;
		const prev = terms[idx].active;
		terms[idx].active = newActive;
		terms = [...terms];
		toggling[termId] = true;
		toggling = { ...toggling };

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
		} finally {
			toggling[termId] = false;
			toggling = { ...toggling };
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
									<div class="flex items-center gap-2">
										<Switch
											checked={term.active}
											disabled={toggling[term.id] ?? false}
											onCheckedChange={(checked) => handleToggle(term.id, checked)}
										/>
										{#if toggling[term.id]}
											<svg class="animate-spin h-4 w-4 text-surface-400" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
												<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
												<path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
											</svg>
										{/if}
									</div>
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
