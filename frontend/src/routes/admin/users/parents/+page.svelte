<script lang="ts">
	import ParentUserTable from './ParentUserTable.svelte';
	import PageHeader from '$lib/components/PageHeader.svelte';
	import type { UserRow } from '$lib/types/user';

	let { data } = $props();

	let users: UserRow[] = $state(data.users ?? []);
	let allGroups: { pk: string; name: string }[] = $state(data.allGroups ?? []);
	let showCreateDialog = $state(false);

	let hasError = $state(!!data.error);
	let errorMessage = $state(data.error ?? '');
</script>

<div class="space-y-6">
	<PageHeader title="Parent Users" createLabel="Create Parent" onCreate={() => showCreateDialog = true} />
	<ParentUserTable bind:users bind:allGroups bind:showCreateDialog groupPk={data.groupPk ?? ''} {hasError} {errorMessage} />
</div>
