<script lang="ts">
	import type { PageData } from './$types';
	import UserTable from '../UserTable.svelte';
	import AppButton from '$lib/components/ui/app-button.svelte';
	import type { UserRow } from '$lib/types/user';

	let { data }: { data: PageData } = $props();

	let error: string | undefined = $derived(data.error);
	let groupPk: string | undefined = $derived(data.groupPk);
	let isLoading = $derived(!data.users && !data.error);
	let hasError = $derived(!!data.error);

	let users = $state<UserRow[]>((() => data.users as UserRow[])() || []);
	let allGroups = $state<{pk: string; name: string}[]>((() => data.allGroups)() || []);
	let showCreateDialog = $state(false);
</script>

<div class="mx-auto max-w-6xl space-y-6">
	<div class="flex justify-between items-start">
		<div>
			<h1 class="text-2xl font-display font-bold text-primary-700">Teacher Users</h1>
			<p class="mt-1 text-sm text-surface-700">Manage teacher initialization and Authentik status</p>
		</div>
		<AppButton onclick={() => showCreateDialog = true} variant="default">
			Create Teacher
		</AppButton>
	</div>

	<UserTable
		bind:users
		bind:allGroups
		role="teachers"
		groupPk={groupPk ?? ''}
		{isLoading}
		{hasError}
		bind:showCreateDialog
		errorMessage={error || ''}
	/>
</div>
