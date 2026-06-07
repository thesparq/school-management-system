<script lang="ts">
	import StudentUserTable from './StudentUserTable.svelte';
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
	<PageHeader title="Student Users" createLabel="Create Student" onCreate={() => showCreateDialog = true} />
	<StudentUserTable bind:users bind:allGroups bind:showCreateDialog groupPk={data.groupPk ?? ''} {hasError} {errorMessage} />
</div>
