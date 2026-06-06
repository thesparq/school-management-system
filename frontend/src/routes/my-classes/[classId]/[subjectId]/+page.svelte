<script lang="ts">
  import type { PageData } from './$types';
  import type { Term } from '$lib/types';
  import { Card, CardHeader, CardTitle } from '$lib/components/ui/card';
  import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
  import { Skeleton } from '$lib/components/ui/skeleton';
  import { page, navigating } from '$app/stores';
  import { goto } from '$app/navigation';

	let { data }: { data: PageData } = $props();

	let termsSource = $derived(data.terms);
	let terms = $state<Term[]>(termsSource);

	$effect(() => {
		terms = termsSource;
	});
</script>

<div class="space-y-6">
  <h1 class="text-2xl font-display font-bold text-primary-700">{data.subjectName}</h1>

  {#if $navigating && (!terms || terms.length === 0)}
    <div class="flex gap-4 flex-wrap">
      {#each Array(3) as _}
        <Skeleton class="h-28 w-48" />
      {/each}
    </div>
  {:else if data.termsError}
    <StatusCard variant="error" title="Failed to load terms" description={data.termsError} onRetry={() => goto('/my-classes/' + $page.params.classId + '/' + $page.params.subjectId)} />
  {:else if terms.length === 0}
    <StatusCard variant="info" title="No Terms Available" description="No terms are available for this subject yet." />
  {:else}
    <div class="flex gap-4 flex-wrap">
      {#each terms as term (term.id)}
        <div class="flex flex-col">
          <a href="/my-classes/{$page.params.classId}/{$page.params.subjectId}/{term.id}">
            <Card class="w-48 hover:bg-primary-50 dark:hover:bg-primary-950/30 hover:ring-primary-200 dark:hover:ring-primary-700 transition cursor-pointer">
              <CardHeader class="pb-2">
                <CardTitle class="font-display text-base text-primary-700 dark:text-primary-300">{term.name}</CardTitle>
              </CardHeader>
            </Card>
          </a>
          {#if !term.active}
            <div class="flex items-center gap-1.5 mt-2 pl-1">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5 text-amber-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
              </svg>
              <span class="text-xs text-amber-600">Hidden from students</span>
            </div>
          {/if}
        </div>
      {/each}
    </div>
  {/if}
</div>
