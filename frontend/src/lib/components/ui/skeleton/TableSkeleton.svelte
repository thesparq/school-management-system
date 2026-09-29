<script lang="ts">
	import { Skeleton } from '$lib/components/ui/skeleton';
</script>

<div class="space-y-4 w-full">
	<div class="flex items-center justify-between pb-2">
		<Skeleton class="h-8 w-[250px]" />
		<Skeleton class="h-8 w-[100px]" />
	</div>

	<div class="rounded-md border border-border w-full">
		<div class="border-b border-border bg-muted/50 px-4 py-3 grid grid-cols-4 gap-4 w-full">
			<Skeleton class="h-5 w-full" />
			<Skeleton class="h-5 w-full" />
			<Skeleton class="h-5 w-full" />
			<Skeleton class="h-5 w-full" />
		</div>
		<div class="divide-y divide-border w-full">
			{#each Array(5) as _}
				<div class="px-4 py-4 grid grid-cols-4 gap-4 items-center w-full">
					<Skeleton class="h-4 w-full" />
					<Skeleton class="h-4 w-full" />
					<Skeleton class="h-4 w-full" />
					<Skeleton class="h-4 w-full" />
				</div>
			{/each}
		</div>
	</div>
</div>
