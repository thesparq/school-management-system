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

	let { data }: { data: PageData } = $props();

	let hasUsers = $derived(data.users && data.users.length > 0);
	let isLoading = $derived(!data.users && !data.error);
	let hasError = $derived(!!data.error);

	function handleRetry() {
		window.location.reload();
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
							<TableHead class="w-20">Actions</TableHead>
						</TableRow>
					</TableHeader>
					<TableBody>
						{#each data.users as user (user.pk)}
							<TableRow>
								<TableCell class="font-medium">
									{user.name || user.username}
								</TableCell>
								<TableCell class="text-surface-700">
									{user.email || '—'}
								</TableCell>
								<TableCell>
									<Badge variant="secondary">Pending</Badge>
								</TableCell>
								<TableCell>
									<!-- Actions wired in Unit 8 -->
								</TableCell>
							</TableRow>
						{/each}
					</TableBody>
				</Table>
			</CardContent>
		</Card>
	{/if}
</div>
