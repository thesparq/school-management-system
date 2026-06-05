<script lang="ts">
	import UserTable from '../UserTable.svelte';
	import type { UserRow } from '$lib/types/user';

	let { data } = $props();

	let allGroups = $state(data.allGroups ?? []);
	let users: UserRow[] = $state(data.users ?? []);
	let showCreateDialog = $state(false);
	let isLoading = $state(false);
	let hasError = $state(!!data.error);
	let errorMessage = $state(data.error ?? '');
</script>

<UserTable
	bind:users
	bind:allGroups
	bind:showCreateDialog
	role="parent"
	groupPk={data.groupPk ?? ''}
	{isLoading}
	{hasError}
	{errorMessage}
/>
