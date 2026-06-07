<script lang="ts" generics="T">
	import { Input } from '$lib/components/ui/input';
	import type { Snippet } from 'svelte';

	let {
		items = [] as T[],
		search = $bindable(''),
		placeholder = 'Search...',
		filterFn = (item: T, query: string) =>
			String(item).toLowerCase().includes(query.toLowerCase()),
		onSelect = (_item: T) => {},
		children,
		class: className = '',
	}: {
		items: T[];
		search?: string;
		placeholder?: string;
		filterFn?: (item: T, query: string) => boolean;
		onSelect?: (item: T) => void;
		children?: Snippet<[{ item: T }]>;
		class?: string;
	} = $props();

	let dropdownOpen = $state(false);

	const filtered = $derived(items.filter((i) => filterFn(i, search)));

	function handleSelect(item: T) {
		onSelect(item);
		search = '';
		dropdownOpen = false;
	}
</script>

<div class="relative {className}">
	<Input
		bind:value={search}
		{placeholder}
		onfocus={() => (dropdownOpen = true)}
		onblur={() => setTimeout(() => (dropdownOpen = false), 150)}
	/>
	{#if dropdownOpen && filtered.length > 0}
		<div
			class="absolute z-20 mt-1 max-h-48 w-full overflow-y-auto rounded-md border bg-background shadow-lg dark:bg-surface-900"
		>
			{#each filtered as item}
				<button
					type="button"
					onmousedown={() => handleSelect(item)}
					class="w-full px-3 py-2 text-left text-sm hover:bg-primary-50 dark:hover:bg-accent"
				>
					{#if children}
						{@render children({ item })}
					{:else}
						{item}
					{/if}
				</button>
			{/each}
		</div>
	{/if}
</div>
