<script lang="ts">
	import StudentUserTable from './StudentUserTable.svelte';
	import PageHeader from '$lib/components/PageHeader.svelte';
	import type { UserRow } from '$lib/types/user';
	import TableSkeleton from '$lib/components/ui/skeleton/TableSkeleton.svelte';

	let { data } = $props();

	let users: UserRow[] = $state([]);
	let allGroups: { pk: string; name: string }[] = $state([]);
	let showCreateDialog = $state(false);
	let groupPk = $state('');

	let hasError = $state(false);
	let errorMessage = $state('');

	$effect(() => {
		if (data.streamed) {
			data.streamed.usersPromise.then((res: any) => {
				users = res.users;
				allGroups = res.allGroups;
				groupPk = res.groupPk;
			}).catch((err: Error) => {
				hasError = true;
				errorMessage = err.message;
			});
		}
	});
</script>

<div class="space-y-6">
	<PageHeader title="Students" createLabel="Create Student" onCreate={() => showCreateDialog = true} />
	{#await data.streamed.usersPromise}
		<TableSkeleton />
	{:then _}
		<StudentUserTable bind:users bind:allGroups bind:showCreateDialog {groupPk} {hasError} {errorMessage} />
	{:catch error}
		<div class="p-6 bg-destructive/10 text-destructive rounded-xl border border-destructive/20">
			<h3 class="font-semibold text-lg mb-2">Failed to load Students</h3>
			<p>{error.message}</p>
		</div>
	{/await}
</div>
