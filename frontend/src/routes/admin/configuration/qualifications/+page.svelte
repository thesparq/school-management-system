<script lang="ts">
	import type { PageData } from './$types';
	import { Card, CardContent } from '$lib/components/ui/card';
	import AppButton from '$lib/components/ui/app-button.svelte';
	import {
		Table, TableBody, TableCell, TableHead, TableHeader, TableRow
	} from '$lib/components/ui/table';
	import {
		Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription
	} from '$lib/components/ui/dialog';
	import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';
	import { Input } from '$lib/components/ui/input';
	import { Label } from '$lib/components/ui/label';
	import PageHeader from '$lib/components/PageHeader.svelte';
	import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
	import { addToast } from '$lib/stores/toast';

	interface Qualification {
		id: string;
		name: string;
		active: boolean;
	}

	let { data }: { data: PageData } = $props();
	let qualifications: Qualification[] = $state(data.qualifications);

	$effect(() => {
		qualifications = data.qualifications;
	});

	let showCreateDialog = $state(false);
	let createName = $state('');
	let createLoading = $state(false);
	let createError = $state('');

	let showDeleteConfirm = $state(false);
	let deletingQual = $state<Qualification | null>(null);
	let deleteLoading = $state(false);

	async function handleCreate() {
		if (!createName.trim()) return;
		createLoading = true;
		createError = '';
		try {
			const res = await fetch('/api/admin/credentials', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ name: createName.trim() })
			});
			const body = await res.json();
			if (!res.ok || body.error) throw new Error(body.error?.message || 'Create failed');
			addToast('success', 'Qualification created', `${createName.trim()} has been added.`);
			showCreateDialog = false;
			createName = '';
			const reload = await fetch('/api/admin/credentials');
			const reloadBody = await reload.json();
			if (reloadBody.data) qualifications = reloadBody.data;
		} catch (err) {
			createError = err instanceof Error ? err.message : 'Create failed';
		} finally {
			createLoading = false;
		}
	}

	function confirmDelete(qual: Qualification) {
		deletingQual = qual;
		showDeleteConfirm = true;
	}

	async function handleDelete() {
		if (!deletingQual) return;
		deleteLoading = true;
		try {
			const res = await fetch(`/api/admin/credentials/${encodeURIComponent(deletingQual.id)}`, {
				method: 'DELETE'
			});
			const body = await res.json();
			if (!res.ok || body.error) throw new Error(body.error?.message || 'Delete failed');
			addToast('success', 'Qualification deleted', `${deletingQual.name} has been removed.`);
			qualifications = qualifications.filter(q => q.id !== deletingQual!.id);
		} catch (err) {
			addToast('error', 'Delete failed', err instanceof Error ? err.message : 'An unknown error occurred');
		} finally {
			deleteLoading = false;
			showDeleteConfirm = false;
			deletingQual = null;
		}
	}
</script>

<div class="space-y-6">
	<PageHeader title="Qualifications" createLabel="Create Qualification" onCreate={() => showCreateDialog = true} />

	{#if data.qualificationsError}
		<StatusCard variant="error" title="Failed to load data" description={data.qualificationsError} onRetry={() => window.location.reload()} />
	{:else if qualifications.length === 0}
		<StatusCard variant="info" title="No qualifications created yet." description="Create a qualification to use in teacher credential assignments." />
	{:else}
		<Card>
			<CardContent class="p-0">
				<Table>
					<TableHeader>
						<TableRow>
							<TableHead>Name</TableHead>
							<TableHead class="w-28">Actions</TableHead>
						</TableRow>
					</TableHeader>
					<TableBody>
						{#each qualifications as qual (qual.id)}
							<TableRow>
								<TableCell class="font-medium">{qual.name}</TableCell>
								<TableCell>
									<AppButton
										variant="destructive"
										size="sm"
										onclick={() => confirmDelete(qual)}
									>
										Delete
									</AppButton>
								</TableCell>
							</TableRow>
						{/each}
					</TableBody>
				</Table>
			</CardContent>
		</Card>
	{/if}
</div>

<Dialog open={showCreateDialog} onOpenChange={(o) => { showCreateDialog = o; if (!o) { createError = ''; createName = ''; } }}>
	<DialogContent class="sm:max-w-lg">
		<DialogHeader>
			<DialogTitle>Create Qualification</DialogTitle>
			<DialogDescription>
				Add a new qualification for teacher credential assignments.
			</DialogDescription>
		</DialogHeader>
		<form class="space-y-4" onsubmit={(e) => { e.preventDefault(); handleCreate(); }}>
			<div class="space-y-2">
				<Label for="qual-name">Name</Label>
				<Input id="qual-name" bind:value={createName} placeholder="e.g. B.Ed. Mathematics" required />
			</div>
			{#if createError}
				<p class="text-sm text-destructive">{createError}</p>
			{/if}
			<div class="flex justify-end gap-2">
				<AppButton
					type="button"
					variant="outline"
					onclick={() => { showCreateDialog = false; createError = ''; createName = ''; }}
				>
					Cancel
				</AppButton>
				<AppButton
					type="submit"
					variant="default"
					loading={createLoading}
					disabled={!createName.trim()}
				>
					{createLoading ? 'Creating...' : 'Create'}
				</AppButton>
			</div>
		</form>
	</DialogContent>
</Dialog>

<AlertDialog.Root bind:open={showDeleteConfirm}>
	<AlertDialog.Content>
		<AlertDialog.Header>
			<AlertDialog.Title>Delete Qualification</AlertDialog.Title>
			<AlertDialog.Description>
				Are you sure you want to delete <strong>{deletingQual?.name ?? ''}</strong>? This action cannot be undone.
			</AlertDialog.Description>
		</AlertDialog.Header>
		<AlertDialog.Footer>
			<AlertDialog.Cancel>Cancel</AlertDialog.Cancel>
			<AlertDialog.Action onclick={handleDelete} disabled={deleteLoading}>
				{deleteLoading ? 'Deleting...' : 'Delete'}
			</AlertDialog.Action>
		</AlertDialog.Footer>
	</AlertDialog.Content>
</AlertDialog.Root>
