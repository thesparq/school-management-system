<script lang="ts">
	import type { PageData } from './$types';
	import { Card, CardContent } from '$lib/components/ui/card';
	import {
		Table, TableBody, TableCell, TableHead, TableHeader, TableRow
	} from '$lib/components/ui/table';
	import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
	import PageHeader from '$lib/components/PageHeader.svelte';
	import AppButton from '$lib/components/ui/app-button.svelte';
	import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '$lib/components/ui/dialog';
	import { Label } from '$lib/components/ui/label';
	import { Input } from '$lib/components/ui/input';
	
	import { addToast } from '$lib/stores/toast';

	let { data }: { data: PageData } = $props();
	let loadError = $state(data.loadError || '');
	let subjects = $state([]);

	

	let showCreateDialog = $state(false);
	let createForm = $state({ id: '', name: '', code: '', description: '' });
	let createLoading = $state(false);
	let createError = $state('');

	async function handleCreate() {
		createLoading = true;
		createError = '';
		try {
			const res = await fetch('/api/admin/subjects', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ ...createForm, code: createForm.code.trim().toUpperCase() })
			});
			const body = await res.json();
			if (!res.ok || body.error) throw new Error(body.error?.message || 'Failed to create subject');
			
			addToast('success', 'Subject created', `${createForm.name} was successfully created.`);
			showCreateDialog = false;
			createForm = { id: '', name: '', code: '', description: '' };
			window.location.reload();
		} catch (err: any) {
			createError = err.message || 'An error occurred';
		} finally {
			createLoading = false;
		}
	}
	$effect(() => {
		if (data.streamed) {
			data.streamed.subjectsRes.then(json => { if (json && json.data) subjects = json.data; if (json && json.error) loadError = json.error.message; });
		}
	});
</script>

<div class="space-y-6">
	<PageHeader title="Subjects" createLabel="Create Subject" onCreate={() => showCreateDialog = true} />

	{#if loadError}
		<StatusCard variant="error" title="Failed to load subjects" description={loadError} onRetry={() => window.location.reload()} />
	{:else if subjects.length === 0}
		<StatusCard variant="info" title="No Subjects Available" description="No subjects exist in the database yet. Click Create Subject to add one." />
	{:else}
		<Card>
			<CardContent class="p-0 overflow-x-auto">
				<Table>
					<TableHeader>
						<TableRow>
							<TableHead>Code</TableHead>
							<TableHead>Title</TableHead>
							<TableHead>Description</TableHead>
						</TableRow>
					</TableHeader>
					<TableBody>
						{#each subjects as subject (subject.id)}
							<TableRow>
								<TableCell><span class="bg-muted text-muted-foreground px-2 py-1 rounded-md font-mono text-xs">{subject.code}</span></TableCell>
								<TableCell>{subject.name}</TableCell>
								<TableCell class="text-sm text-muted-foreground">{subject.description || '-'}</TableCell>
							</TableRow>
						{/each}
					</TableBody>
				</Table>
			</CardContent>
		</Card>
	{/if}
</div>

<Dialog open={showCreateDialog} onOpenChange={(o) => { showCreateDialog = o; if (!o) createError = ''; }}>
	<DialogContent class="sm:max-w-lg">
		<DialogHeader>
			<DialogTitle>Create New Subject</DialogTitle>
			<DialogDescription>
				Add a new subject to the school curriculum.
			</DialogDescription>
		</DialogHeader>
		<form class="space-y-4" onsubmit={(e) => { e.preventDefault(); handleCreate(); }}>
			<div class="space-y-2">
				<Label for="sub-id">ID (Optional)</Label>
				<Input id="sub-id" bind:value={createForm.id} placeholder="e.g. math_jss (leave empty to auto-generate)" />
			</div>
			<div class="space-y-2">
				<Label for="sub-code">Subject Code</Label>
				<Input id="sub-code" bind:value={createForm.code} placeholder="e.g. MTH101" required />
			</div>
			<div class="space-y-2">
				<Label for="sub-name">Title</Label>
				<Input id="sub-name" bind:value={createForm.name} placeholder="e.g. Mathematics" required />
			</div>
			<div class="space-y-2">
				<Label for="sub-desc">Description (Optional)</Label>
				<textarea id="sub-desc" bind:value={createForm.description} placeholder="Subject syllabus description..." class="flex min-h-[80px] w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"></textarea>
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
					disabled={!createForm.name || !createForm.code}
				>
					{createLoading ? 'Creating...' : 'Create'}
				</AppButton>
			</div>
		</form>
	</DialogContent>
</Dialog>
