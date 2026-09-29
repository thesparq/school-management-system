<script lang="ts">
	import { page } from '$app/stores';
	import type { Snippet } from 'svelte';
	
	let { children }: { children: Snippet } = $props();

	const tabs = [
		{ name: 'Students', href: '/admin/users/students' },
		{ name: 'Teachers', href: '/admin/users/teachers' },
		{ name: 'Parents', href: '/admin/users/parents' },
		{ name: 'Administrators', href: '/admin/users/admin-role' }
	];
</script>

<div class="flex flex-col space-y-6">
	<!-- Tab Navigation -->
	<div class="border-b border-border">
		<nav class="-mb-px flex space-x-6 overflow-x-auto" aria-label="Tabs">
			{#each tabs as tab}
				{@const isActive = $page.url.pathname === tab.href || $page.url.pathname.startsWith(tab.href + '/')}
				<a
					href={tab.href}
					class="whitespace-nowrap border-b-2 py-4 px-1 text-sm font-medium {isActive ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:border-border hover:text-foreground'}"
				>
					{tab.name}
				</a>
			{/each}
		</nav>
	</div>

	<!-- Content -->
	<div class="flex-1">
		{@render children()}
	</div>
</div>
