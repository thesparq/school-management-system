<script lang="ts">
	import TeacherUserTable from './TeacherUserTable.svelte';
	import PageHeader from '$lib/components/PageHeader.svelte';
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
	<PageHeader title="Teacher Users" createLabel="Create Teacher" onCreate={() => showCreateDialog = true} />
	<TeacherUserTable bind:users bind:allGroups bind:showCreateDialog groupPk={data.groupPk ?? ''} {isLoading} {hasError} {errorMessage} />
</div>
