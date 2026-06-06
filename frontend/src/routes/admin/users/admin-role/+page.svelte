<script lang="ts">
	import AdminUserTable from './AdminUserTable.svelte';
	import AppButton from '$lib/components/ui/app-button.svelte';
	import type { UserRow } from '$lib/types/user';

	let { data } = $props();

	let users: UserRow[] = $state(data.users ?? []);
	let allGroups: { pk: string; name: string }[] = $state(data.allGroups ?? []);
	let showCreateDialog = $state(false);

	let hasError = $state(!!data.error);
	let errorMessage = $state(data.error ?? '');
	let isLoading = $state(false);
</script>

<div class="space-y-6">
	<div class="flex items-center justify-between">
		<h1 class="text-2xl font-display font-bold text-primary-700">Admin Users</h1>
		<AppButton onclick={() => showCreateDialog = true}>Create Admin</AppButton>
	</div>
	<AdminUserTable bind:users bind:allGroups bind:showCreateDialog groupPk={data.groupPk ?? ''} {isLoading} {hasError} {errorMessage} />
</div>
