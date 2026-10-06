<script lang="ts">
	import type { PageData } from './$types';
	import { Card, CardContent } from '$lib/components/ui/card';
	import { Switch } from '$lib/components/ui/switch/index.js';
	import {
		Table, TableBody, TableCell, TableHead, TableHeader, TableRow
	} from '$lib/components/ui/table';
	import TableSkeleton from '$lib/components/ui/skeleton/TableSkeleton.svelte';
	import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
	import PageHeader from '$lib/components/PageHeader.svelte';
	import AppButton from '$lib/components/ui/app-button.svelte';
	import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '$lib/components/ui/dialog';
	import { Label } from '$lib/components/ui/label';
	import { Input } from '$lib/components/ui/input';
	import { addToast } from '$lib/stores/toast';

	interface TermItem {
		id: string;
		name: string;
		active: boolean;
		sort_order: number;
	}

	let { data }: { data: any } = $props();
	let toggling = $state<Record<string, boolean>>({});

	let showCreateDialog = $state(false);
	let createForm = $state({ name: '', sort_order: 1 });
	let createLoading = $state(false);
	let createError = $state('');

	async function handleToggle(terms: TermItem[], termId: string, newActive: boolean) {
		const idx = terms.findIndex(t => t.id === termId);
		if (idx === -1) return;
		const prev = terms[idx].active;
		terms[idx].active = newActive;
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
			addToast('error', 'Failed to update term', e instanceof Error ? e.message : 'Unknown error');
		} finally {
			toggling[termId] = false;
			toggling = { ...toggling };
		}
	}

	async function handleCreate() {
		createLoading = true;
		createError = '';
		try {
			const res = await fetch('/api/admin/terms', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ name: createForm.name, sort_order: createForm.sort_order })
			});
			const body = await res.json();
			if (!res.ok || body.error) throw new Error(body.error?.message || 'Failed to create term');
			
			addToast('success', 'Term created', `${createForm.name} was successfully created.`);
			showCreateDialog = false;
			createForm = { name: '', sort_order: 1 };
			window.location.reload();
		} catch (err: any) {
			createError = err.message || 'An error occurred';
		} finally {
			createLoading = false;
		}
	}
</script>

<div class="space-y-6">
	<PageHeader title="Terms" createLabel="Create Term" onCreate={() => showCreateDialog = true} />

	{#await data.streamed.termsPromise}
		<TableSkeleton />
	{:then terms}
		{#if terms.length === 0}
			<StatusCard variant="info" title="No Terms Available" description="No terms exist in the database yet." />
		{:else}
			<Card>
				<CardContent class="p-0 overflow-x-auto">
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
												onCheckedChange={(checked) => handleToggle(terms, term.id, checked)}
											/>
											{#if toggling[term.id]}
												<svg class="animate-spin h-4 w-4 text-muted-foreground" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
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
	{:catch error}
		<StatusCard variant="error" title="Failed to load terms" description={error.message} onRetry={() => window.location.reload()} />
	{/await}
</div>

<Dialog open={showCreateDialog} onOpenChange={(o) => { showCreateDialog = o; if (!o) createError = ''; }}>
	<DialogContent class="sm:max-w-lg">
		<DialogHeader>
			<DialogTitle>Create New Term</DialogTitle>
			<DialogDescription>
				Add a new grading period or term structure.
			</DialogDescription>
		</DialogHeader>
		<form class="space-y-4" onsubmit={(e) => { e.preventDefault(); handleCreate(); }}>
			<div class="space-y-2">
				<Label for="term-name">Term Name</Label>
				<Input id="term-name" bind:value={createForm.name} placeholder="e.g. 1st Term" required />
			</div>
			<div class="space-y-2">
				<Label for="term-sort">Sort Order</Label>
				<Input id="term-sort" type="number" min="1" bind:value={createForm.sort_order} required />
				<p class="text-xs text-muted-foreground">Terms are sorted in ascending order for display.</p>
			</div>
			{#if createError}
				<p class="text-sm text-destructive">{createError}</p>
			{/if}
			<div class="flex justify-end gap-2">
				<AppButton
					type="button"
					variant="outline"
					onclick={() => { showCreateDialog = false; createError = ''; }}
				>
					Cancel
				</AppButton>
				<AppButton
					type="submit"
					variant="default"
					loading={createLoading}
					disabled={!createForm.name}
				>
					{createLoading ? 'Creating...' : 'Create'}
				</AppButton>
			</div>
		</form>
	</DialogContent>
</Dialog>
