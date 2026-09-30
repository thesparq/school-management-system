<script lang="ts">
	import type { PageData } from './$types';
	import { Card, CardContent } from '$lib/components/ui/card';
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

	let { data }: { data: any } = $props();
	let loadError = $state(data.loadError || '');
	let classLevels = $state(data.classLevels);

	$effect(() => {
		if (data.streamed) {
			data.streamed.classLevelsRes.then((json: any) => {
				if (json && json.data) classLevels = json.data;
				if (json && json.error) loadError = json.error.message;
			}).catch((err: Error) => { loadError = err.message; });
		}
	});

	let showCreateDialog = $state(false);
	let createForm = $state({ id: '', name: '' });
	let createLoading = $state(false);
	let createError = $state('');

	async function handleCreate() {
		createLoading = true;
		createError = '';
		try {
			const res = await fetch('/api/admin/class-levels', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify(createForm)
			});
			const body = await res.json();
			if (!res.ok || body.error) throw new Error(body.error?.message || 'Failed to create class level');
			
			addToast('success', 'Class Level created', `${createForm.name} was successfully created.`);
			showCreateDialog = false;
			createForm = { id: '', name: '' };
			window.location.reload();
		} catch (err: any) {
			createError = err.message || 'An error occurred';
		} finally {
			createLoading = false;
		}
	}
</script>

<div class="space-y-6">
	<PageHeader title="Class Levels" createLabel="Create Class Level" onCreate={() => showCreateDialog = true} />

	{#await data.streamed.classLevelsRes}
		<TableSkeleton />
	{:then _}
		{#if loadError}
			<StatusCard variant="error" title="Failed to load class levels" description={loadError} onRetry={() => window.location.reload()} />
		{:else if classLevels.length === 0}
			<StatusCard variant="info" title="No Class Levels Available" description="No class levels exist in the database yet. Click Create Class Level to add one." />
		{:else}
			<Card>
				<CardContent class="p-0 overflow-x-auto">
					<Table>
						<TableHeader>
							<TableRow>
								<TableHead>Level ID</TableHead>
								<TableHead>Name</TableHead>
							</TableRow>
						</TableHeader>
						<TableBody>
							{#each classLevels as level (level.id)}
								<TableRow>
									<TableCell>
										<span class="bg-muted text-muted-foreground px-2 py-1 rounded-md font-mono text-xs">{level.id}</span>
									</TableCell>
									<TableCell>{level.name}</TableCell>
								</TableRow>
							{/each}
						</TableBody>
					</Table>
				</CardContent>
			</Card>
		{/if}
	{:catch error}
		<StatusCard variant="error" title="Failed to load class levels" description={error.message} onRetry={() => window.location.reload()} />
	{/await}
</div>

<Dialog open={showCreateDialog} onOpenChange={(o) => { showCreateDialog = o; if (!o) createError = ''; }}>
	<DialogContent class="sm:max-w-lg">
		<DialogHeader>
			<DialogTitle>Create New Class Level</DialogTitle>
			<DialogDescription>
				Add a new grade or class level (e.g. JSS 1, Grade 1).
			</DialogDescription>
		</DialogHeader>
		<form class="space-y-4" onsubmit={(e) => { e.preventDefault(); handleCreate(); }}>
			<div class="space-y-2">
				<Label for="cl-id">ID (Optional)</Label>
				<Input id="cl-id" bind:value={createForm.id} placeholder="e.g. jss_1 (leave empty to auto-generate)" />
			</div>
			<div class="space-y-2">
				<Label for="cl-name">Name</Label>
				<Input id="cl-name" bind:value={createForm.name} placeholder="e.g. JSS 1" required />
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
