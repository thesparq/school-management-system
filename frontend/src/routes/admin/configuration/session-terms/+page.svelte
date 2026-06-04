<script lang="ts">
	import type { PageData } from './$types';
	import { Card, CardContent } from '$lib/components/ui/card';
	import AppButton from '$lib/components/ui/app-button.svelte';
	import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';
	import {
		Dialog,
		DialogContent,
		DialogHeader,
		DialogTitle,
		DialogDescription
	} from '$lib/components/ui/dialog';
	import {
		Table,
		TableBody,
		TableCell,
		TableHead,
		TableHeader,
		TableRow
	} from '$lib/components/ui/table';
	import { Badge } from '$lib/components/ui/badge';
	import { Input } from '$lib/components/ui/input';
	import { Label } from '$lib/components/ui/label';
	import { Skeleton } from '$lib/components/ui/skeleton';
	import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
	import { addToast } from '$lib/stores/toast';
	import { goto } from '$app/navigation';

	interface SessionTerm {
		id: string;
		session: string;
		term_name: string;
		active: boolean;
		created_at: string;
	}

	let { data }: { data: PageData } = $props();
	let sessionTerms: SessionTerm[] = $state(data.sessionTerms);

	$effect(() => {
		sessionTerms = data.sessionTerms;
	});

	let showCreateDialog = $state(false);
	let createForm = $state({ session: '', termId: '', active: true });
	let createLoading = $state(false);
	let createError = $state('');
	let activateLoading = $state<Record<string, boolean>>({});
	let showActivateConfirm = $state(false);
	let activatingStId = $state('');

	const hasActive = $derived(sessionTerms.some((st) => st.active));

	function formatDate(d: string) {
		if (!d) return '';
		return new Date(d).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
	}

	async function handleCreate() {
		if (!createForm.session || !createForm.termId) return;
		createLoading = true;
		createError = '';
		try {
			const res = await fetch('/api/admin/session-terms/create', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					session: createForm.session,
					term_id: createForm.termId,
					active: createForm.active
				})
			});
			const body = await res.json();
			if (!res.ok || body.error) throw new Error(body.error?.message || 'Create failed');
			addToast('success', 'Session term created', `${createForm.session} has been added.`);
			showCreateDialog = false;
			await goto('/admin/configuration/session-terms', { invalidateAll: true });
		} catch (err) {
			createError = err instanceof Error ? err.message : 'Create failed';
		} finally {
			createLoading = false;
		}
	}

	async function doActivate(stId: string) {
		showActivateConfirm = false;
		activateLoading = { ...activateLoading, [stId]: true };
		try {
			const res = await fetch(`/api/admin/session-terms/activate?session_term_id=${encodeURIComponent(stId)}`, {
				method: 'POST'
			});
			const body = await res.json();
			if (!res.ok || body.error) throw new Error(body.error?.message || 'Activation failed');
			addToast('success', 'Session term activated', 'The active term has been updated.');
			sessionTerms = sessionTerms.map(st => ({
				...st,
				active: st.id === stId
			}));
		} catch (err) {
			addToast('error', 'Activation failed', err instanceof Error ? err.message : 'An unknown error occurred');
		} finally {
			activateLoading = { ...activateLoading, [stId]: false };
		}
	}
</script>

<div class="mx-auto max-w-4xl space-y-6">
	<h1 class="text-2xl font-display font-bold text-primary-700">Session Terms</h1>

	{#if data.sessionTermsError}
		<StatusCard variant="error" title="Failed to load data" description={data.sessionTermsError} onRetry={() => window.location.reload()} />
	{:else if sessionTerms.length === 0}
		<div class="space-y-4">
			<StatusCard variant="info" title="No session terms created yet." description="Create a session term to begin scoping assignments to a school period." />
			<div class="flex justify-start">
				<AppButton variant="default" onclick={() => showCreateDialog = true}>Create Session Term</AppButton>
			</div>
		</div>
	{:else}
		<div class="space-y-4">
			{#if !hasActive}
				<StatusCard variant="warning" title="No active session term" description="Teacher assignments cannot be scoped to a term. Activate a session term below." />
			{/if}

			<div class="flex justify-end">
				<AppButton variant="default" onclick={() => showCreateDialog = true}>Create Session Term</AppButton>
			</div>

			<Card>
				<CardContent class="p-0">
					<Table>
						<TableHeader>
							<TableRow>
								<TableHead>Session</TableHead>
								<TableHead>Term</TableHead>
								<TableHead>Active</TableHead>
								<TableHead>Created</TableHead>
								<TableHead class="w-28">Actions</TableHead>
							</TableRow>
						</TableHeader>
						<TableBody>
							{#each sessionTerms as st (st.id)}
								<TableRow>
									<TableCell class="font-medium">{st.session}</TableCell>
									<TableCell class="text-surface-700">{st.term_name}</TableCell>
									<TableCell>
										<Badge variant={st.active ? 'default' : 'secondary'}>
											{st.active ? 'Active' : 'Inactive'}
										</Badge>
									</TableCell>
									<TableCell class="text-surface-700 text-sm">{formatDate(st.created_at)}</TableCell>
									<TableCell>
										<AppButton
											variant="outline"
											size="sm"
											loading={activateLoading[st.id]}
											disabled={st.active}
											onclick={() => { activatingStId = st.id; showActivateConfirm = true; }}
										>
											{activateLoading[st.id] ? '...' : 'Activate'}
										</AppButton>
									</TableCell>
								</TableRow>
							{/each}
						</TableBody>
					</Table>
				</CardContent>
			</Card>
		</div>
	{/if}
</div>

<Dialog open={showCreateDialog} onOpenChange={(o) => { showCreateDialog = o; if (!o) createError = ''; }}>
	<DialogContent class="sm:max-w-lg">
		<DialogHeader>
			<DialogTitle>Create Session Term</DialogTitle>
			<DialogDescription>
				Create a new school session term. Only one can be active at a time.
			</DialogDescription>
		</DialogHeader>
		<form class="space-y-4" onsubmit={(e) => { e.preventDefault(); handleCreate(); }}>
			<div class="space-y-2">
				<Label for="st-session">Session</Label>
				<Input id="st-session" bind:value={createForm.session} placeholder="e.g. 2024" required />
			</div>
			<div class="space-y-2">
				<Label for="st-term">Term</Label>
				{#if data.terms.length > 0}
					<select
						id="st-term"
						class="flex h-9 w-full rounded-none border border-input bg-transparent px-3 py-1 text-sm transition-colors focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-1 cursor-pointer"
						bind:value={createForm.termId}
						required
					>
						<option value="" disabled>Select a term…</option>
						{#each data.terms as term (term.id)}
							<option value={term.id}>{term.name}</option>
						{/each}
					</select>
				{:else}
					<Input id="st-term" bind:value={createForm.termId} placeholder="e.g. terms:summer_term" required />
					<p class="text-xs text-surface-500">Terms list unavailable. Enter the term record ID manually.</p>
				{/if}
			</div>
			<div class="flex items-center gap-2">
				<input
					id="st-active"
					type="checkbox"
					checked={createForm.active}
					onchange={(e) => createForm.active = e.currentTarget.checked}
					class="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500 cursor-pointer"
				/>
				<Label for="st-active">Set as active session term</Label>
			</div>
			{#if createError}
				<p class="text-sm text-error-500">{createError}</p>
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
					disabled={!createForm.session || !createForm.termId}
				>
					{createLoading ? 'Creating...' : 'Create'}
				</AppButton>
			</div>
		</form>
	</DialogContent>
</Dialog>

<AlertDialog.Root bind:open={showActivateConfirm}>
	<AlertDialog.Content>
		<AlertDialog.Header>
			<AlertDialog.Title>Activate Session Term</AlertDialog.Title>
			<AlertDialog.Description>This will activate the selected session term and deactivate all others. Continue?</AlertDialog.Description>
		</AlertDialog.Header>
		<AlertDialog.Footer>
			<AlertDialog.Cancel>Cancel</AlertDialog.Cancel>
			<AlertDialog.Action onclick={() => doActivate(activatingStId)}>Activate</AlertDialog.Action>
		</AlertDialog.Footer>
	</AlertDialog.Content>
</AlertDialog.Root>
