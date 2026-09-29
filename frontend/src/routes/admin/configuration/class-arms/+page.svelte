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
	let classArms = $state([]);
	let classLevels = $state([]);

	$effect(() => { 
		if (data.streamed) {
			data.streamed.classArmsRes.then(res => classArms = res);
			data.streamed.classLevelsRes.then(res => classLevels = res);
		}
	});

	let showCreateDialog = $state(false);
	let createForm = $state({ class_level: '', name: '' });
	let createLoading = $state(false);
	let createError = $state('');

	async function handleCreate() {
		createLoading = true;
		createError = '';
		try {
			const res = await fetch('/api/admin/class-arms/create', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify(createForm)
			});
			const body = await res.json();
			if (!res.ok || body.error) throw new Error(body.error?.message || 'Failed to create class arm');
			
			addToast('success', 'Class Arm created', `${createForm.name} was successfully created.`);
			showCreateDialog = false;
			createForm = { class_level: '', name: '' };
			window.location.reload();
		} catch (err: any) {
			createError = err.message || 'An error occurred';
		} finally {
			createLoading = false;
		}
	}
</script>

<div class="space-y-6">
	<PageHeader title="Class Arms Management" />

	<div class="flex items-center justify-between">
		<p class="text-sm text-muted-foreground">Manage subdivisions of class levels (e.g. JSS 1A, JSS 1B).</p>
		<AppButton onclick={() => (showCreateDialog = true)}>Add Class Arm</AppButton>
	</div>

	{#if classArms.length === 0}
		<StatusCard
			title="No class arms found"
			description="Get started by creating a new class arm."
			actionLabel="Add Class Arm"
			onAction={() => (showCreateDialog = true)}
		/>
	{:else}
		<Card>
			<CardContent class="p-0 overflow-x-auto">
				<Table>
					<TableHeader>
						<TableRow>
							<TableHead>Level</TableHead>
							<TableHead>Name</TableHead>
						</TableRow>
					</TableHeader>
					<TableBody>
						{#each classArms as arm (arm.id || arm.name)}
							<TableRow>
								<TableCell>
									<span class="bg-muted text-muted-foreground px-2 py-1 rounded-md font-mono text-xs">{classLevels.find(l => l.id === arm.class_level)?.name || 'Unknown'}</span>
								</TableCell>
								<TableCell class="font-medium">{arm.name}</TableCell>
							</TableRow>
						{/each}
					</TableBody>
				</Table>
			</CardContent>
		</Card>
	{/if}
</div>

<Dialog bind:open={showCreateDialog}>
	<DialogContent>
		<DialogHeader>
			<DialogTitle>Create Class Arm</DialogTitle>
			<DialogDescription>
				Add a new subdivision (e.g. JSS 1A) to an existing class level.
			</DialogDescription>
		</DialogHeader>
		<form class="space-y-4" onsubmit={(e) => { e.preventDefault(); handleCreate(); }}>
			<div class="space-y-2">
				<Label>Class Level</Label>
				<select bind:value={createForm.class_level} required class="flex h-10 w-full items-center justify-between rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50">
					<option value="">Select a Class Level...</option>
					{#each classLevels as level}
						<option value={level.id}>{level.name}</option>
					{/each}
				</select>
			</div>
			
			<div class="space-y-2">
				<Label>Arm Name</Label>
				<Input bind:value={createForm.name} placeholder="e.g. JSS 1A" required />
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
				<AppButton type="submit" isLoading={createLoading}>Create</AppButton>
			</div>
		</form>
	</DialogContent>
</Dialog>
