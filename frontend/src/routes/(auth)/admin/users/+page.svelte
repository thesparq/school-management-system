<script lang="ts">
	import type { PageData } from './$types';
	import {
		Table,
		TableBody,
		TableCell,
		TableHead,
		TableHeader,
		TableRow
	} from '$lib/components/ui/table';
	import { Badge } from '$lib/components/ui/badge';
	import { Card, CardContent, CardHeader, CardTitle } from '$lib/components/ui/card';
	import { Skeleton } from '$lib/components/ui/skeleton';
	import { Alert, AlertDescription, AlertTitle } from '$lib/components/ui/alert';
	import { Button } from '$lib/components/ui/button';

	interface UserWithStatus {
		pk: number;
		uuid: string;
		username: string;
		name: string;
		email: string;
		type: string;
		groups: number[];
		activationStatus: string;
	}

	let { data }: { data: PageData } = $props();

	let users = $state<UserWithStatus[]>(data.users as UserWithStatus[] || []);
	let hasUsers = $derived(users.length > 0);
	let isLoading = $derived(!data.users && !data.error);
	let hasError = $derived(!!data.error);

	let actionStates = $state<Record<number, string>>({});
	let actionErrors = $state<Record<number, string>>({});

	function handleRetry() {
		window.location.reload();
	}

	function statusVariant(status: string) {
		switch (status) {
			case 'active': return 'default';
			case 'deactivated': return 'destructive';
			case 'suspended': return 'secondary';
			default: return 'secondary';
		}
	}

	function statusLabel(status: string) {
		switch (status) {
			case 'active': return 'Active';
			case 'deactivated': return 'Deactivated';
			case 'suspended': return 'Suspended';
			default: return 'Pending';
		}
	}

	function getUser(pk: number): UserWithStatus | undefined {
		return users.find(u => u.pk === pk);
	}

	async function handleActivate(pk: number) {
		const user = getUser(pk);
		if (!user) return;
		const originalStatus = user.activationStatus;

		actionStates = { ...actionStates, [pk]: 'loading' };
		actionErrors = { ...actionErrors, [pk]: '' };

		users = users.map(u => u.pk === pk ? { ...u, activationStatus: 'active' } : u);

		try {
			const res = await fetch(`/api/admin/users/${user.uuid}/activate`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ role: 'student' })
			});
			const body = await res.json();
			if (!res.ok || body.error) {
				throw new Error(body.error?.message || 'Activation failed');
			}
		} catch (err) {
			users = users.map(u =>
				u.pk === pk ? { ...u, activationStatus: originalStatus } : u
			);
			actionErrors = { ...actionErrors, [pk]: err instanceof Error ? err.message : 'Activation failed' };
		} finally {
			actionStates = { ...actionStates, [pk]: 'idle' };
		}
	}

	async function handleDeactivate(pk: number) {
		const user = getUser(pk);
		if (!user) return;
		const originalStatus = user.activationStatus;

		actionStates = { ...actionStates, [pk]: 'loading' };
		actionErrors = { ...actionErrors, [pk]: '' };

		users = users.map(u => u.pk === pk ? { ...u, activationStatus: 'deactivated' } : u);

		try {
			const res = await fetch(`/api/admin/users/${user.uuid}/deactivate`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' }
			});
			const body = await res.json();
			if (!res.ok || body.error) {
				throw new Error(body.error?.message || 'Deactivation failed');
			}
		} catch (err) {
			users = users.map(u =>
				u.pk === pk ? { ...u, activationStatus: originalStatus } : u
			);
			actionErrors = { ...actionErrors, [pk]: err instanceof Error ? err.message : 'Deactivation failed' };
		} finally {
			actionStates = { ...actionStates, [pk]: 'idle' };
		}
	}
</script>

<div class="mx-auto max-w-4xl space-y-6">
	<div>
		<h1 class="text-2xl font-display font-bold text-primary-700">User Management</h1>
		<p class="mt-1 text-sm text-surface-700">
			Manage user activation and roles
		</p>
	</div>

	{#if isLoading}
		<Card>
			<CardHeader>
				<Skeleton class="h-5 w-32" />
			</CardHeader>
			<CardContent class="space-y-3">
				{#each Array(5) as _}
					<div class="flex gap-4">
						<Skeleton class="h-4 flex-1" />
						<Skeleton class="h-4 flex-1" />
						<Skeleton class="h-4 w-20" />
						<Skeleton class="h-4 w-16" />
					</div>
				{/each}
			</CardContent>
		</Card>

	{:else if hasError}
		<Alert variant="destructive">
			<AlertTitle>Failed to load users</AlertTitle>
			<AlertDescription>
				{data.error}
			</AlertDescription>
			<Button onclick={handleRetry} variant="outline" class="mt-3">
				Retry
			</Button>
		</Alert>

	{:else if !hasUsers}
		<Card>
			<CardContent class="py-8 text-center">
				<p class="text-surface-700">No users found.</p>
				<p class="mt-1 text-sm text-surface-700">
					Ensure your Authentik service account has the correct permissions.
				</p>
			</CardContent>
		</Card>

	{:else}
		<Card>
			<CardContent class="p-0">
				<Table>
					<TableHeader>
						<TableRow>
							<TableHead>Name</TableHead>
							<TableHead>Email</TableHead>
							<TableHead>Status</TableHead>
							<TableHead class="w-32">Actions</TableHead>
						</TableRow>
					</TableHeader>
					<TableBody>
						{#each users as user (user.pk)}
							<TableRow>
								<TableCell class="font-medium">
									{user.name || user.username}
								</TableCell>
								<TableCell class="text-surface-700">
									{user.email || '—'}
								</TableCell>
								<TableCell>
									<Badge variant={statusVariant(user.activationStatus)}>
										{statusLabel(user.activationStatus)}
									</Badge>
								</TableCell>
								<TableCell class="w-32">
									{#if user.activationStatus === 'active'}
										<Button
											variant="destructive"
											size="sm"
											onclick={() => handleDeactivate(user.pk)}
											disabled={actionStates[user.pk] === 'loading'}
										>
											{actionStates[user.pk] === 'loading' ? '...' : 'Deactivate'}
										</Button>
									{:else}
										<Button
											variant="default"
											size="sm"
											onclick={() => handleActivate(user.pk)}
											disabled={actionStates[user.pk] === 'loading'}
										>
											{actionStates[user.pk] === 'loading' ? '...' : 'Activate'}
										</Button>
									{/if}
									{#if actionErrors[user.pk]}
										<p class="mt-1 text-xs text-error-500">{actionErrors[user.pk]}</p>
									{/if}
								</TableCell>
							</TableRow>
						{/each}
					</TableBody>
				</Table>
			</CardContent>
		</Card>
	{/if}
</div>
