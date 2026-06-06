<script lang="ts">
  import { Skeleton } from '$lib/components/ui/skeleton';

  let {
    layout = 'list',
    rows = 6
  }: {
    layout?: 'list' | 'grid' | 'card';
    rows?: number;
  } = $props();
</script>

{#if layout === 'list'}
  <div class="space-y-3">
    {#each Array(rows) as _}
      <Skeleton class="h-12 w-full" />
    {/each}
  </div>
{:else if layout === 'grid'}
  <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
    {#each Array(rows) as _}
      <Skeleton class="h-28 w-full rounded-lg" />
    {/each}
  </div>
{:else if layout === 'card'}
  <Skeleton class="h-48 w-full rounded-lg" />
{/if}
