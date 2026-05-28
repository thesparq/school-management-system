<script lang="ts">
	import type { PageData } from './$types';
	import UserTable from '../UserTable.svelte';
	import { Button } from '$lib/components/ui/button';
	import type { UserRow } from '$lib/types/user';

	let { data }: { data: PageData } = $props();
	let { users: initialUsers, initMap: initialInitMap, allGroups: initialAllGroups, error, groupPk } = data;

	let users = $state<UserRow[]>(initialUsers as UserRow[] || []);
	let initMap = $state<Record<string, string>>(initialInitMap || {});
	let allGroups = $state<{pk: string; name: string}[]>(initialAllGroups || []);
	let isLoading = $derived(!initialUsers && !error);
	let hasError = $derived(!!error);
	let showCreateDialog = $state(false);
</script>

<div class="mx-auto max-w-6xl space-y-6">
	<div class="flex justify-between items-start">
		<div>
			<h1 class="text-2xl font-display font-bold text-primary-700">Admin Users</h1>
			<p class="mt-1 text-sm text-surface-700">Manage admin initialization and Authentik status</p>
		</div>
		<Button onclick={() => showCreateDialog = true} variant="default" class="cursor-pointer">
			Create Admin
		</Button>
	</div>

	<UserTable
		bind:users
		bind:initMap
		bind:allGroups
		role="admin-role"
		groupPk={groupPk ?? ''}
		{isLoading}
		{hasError}
		bind:showCreateDialog
		errorMessage={error || ''}
	/>
</div>
