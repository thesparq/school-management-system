<script lang="ts">
	import { Label } from '$lib/components/ui/label';
	import { Input } from '$lib/components/ui/input';
	import { Badge } from '$lib/components/ui/badge';
	import type { CredentialInfo } from '$lib/types';
	import { onMount } from 'svelte';

	let {
		selected = $bindable([] as string[])
	}: {
		selected: string[];
	} = $props();

	let credentials = $state<CredentialInfo[]>([]);
	let loading = $state(true);
	let search = $state('');
	let dropdownOpen = $state(false);

	onMount(async () => {
		try {
			const res = await fetch('/api/admin/credentials');
			const body = await res.json();
			credentials = body?.data ?? [];
		} catch {
			credentials = [];
		} finally {
			loading = false;
		}
	});

	let filtered = $derived(
		credentials.filter(
			(c) =>
				!selected.includes(c.id) &&
				c.name.toLowerCase().includes(search.toLowerCase())
		)
	);

	let selectedItems = $derived(
		credentials.filter((c) => selected.includes(c.id))
	);

	function add(id: string) {
		selected = [...selected, id];
		search = '';
		dropdownOpen = false;
	}

	function remove(id: string) {
		selected = selected.filter((s) => s !== id);
	}
</script>

<div class="space-y-2">
	<Label>Qualifications</Label>

	{#if loading}
		<div class="text-sm text-surface-400">Loading credentials...</div>
	{:else}
		<div class="flex flex-wrap gap-1.5">
			{#each selectedItems as item (item.id)}
				<Badge variant="secondary" class="gap-1">
					{item.name}
					<button type="button" onclick={() => remove(item.id)} class="ml-0.5 rounded-full hover:bg-surface-200">
						<svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
							<path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
						</svg>
					</button>
				</Badge>
			{/each}
		</div>

		<div class="relative">
			<Input
				bind:value={search}
				placeholder="Search credentials..."
				onfocus={() => (dropdownOpen = true)}
				onblur={() => setTimeout(() => (dropdownOpen = false), 150)}
			/>
			{#if dropdownOpen && filtered.length > 0}
				<div class="absolute z-20 mt-1 max-h-48 w-full overflow-y-auto rounded-md border bg-white shadow-lg dark:bg-surface-900">
					{#each filtered as c (c.id)}
						<button
							type="button"
							onmousedown={() => add(c.id)}
							class="w-full px-3 py-2 text-left text-sm hover:bg-primary-50 dark:hover:bg-primary-950/30"
						>
							{c.name}
						</button>
					{/each}
				</div>
			{/if}
		</div>
	{/if}
</div>
