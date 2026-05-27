<script lang="ts">
	import type { PageData } from './$types';
	import UserTable from '../UserTable.svelte';
	import type { UserRow } from '$lib/types/user';

	let { data }: { data: PageData } = $props();

	let users = $state<UserRow[]>(data.users as UserRow[] || []);
	let initMap = $state<Record<string, string>>(data.initMap || {});
	let allGroups = $state<{pk: string; name: string}[]>(data.allGroups || []);
	let isLoading = $derived(!data.users && !data.error);
	let hasError = $derived(!!data.error);
</script>

<div class="mx-auto max-w-6xl space-y-6">
	<div>
		<h1 class="text-2xl font-display font-bold text-primary-700">Student Users</h1>
		<p class="mt-1 text-sm text-surface-700">Manage student initialization and Authentik status</p>
	</div>

	<UserTable
		bind:users
		bind:initMap
		bind:allGroups
		role="students"
		{isLoading}
		{hasError}
		errorMessage={data.error || ''}
	/>
</div>
