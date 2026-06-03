<script lang="ts">
  import type { PageData } from './$types';
  import { Card, CardHeader, CardTitle } from '$lib/components/ui/card';
  import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
  import { Skeleton } from '$lib/components/ui/skeleton';
  import { page, navigating } from '$app/stores';
  import { goto } from '$app/navigation';

  let { data }: { data: PageData } = $props();
</script>

<div class="mx-auto max-w-4xl space-y-6">
  <h1 class="text-2xl font-display font-bold text-primary-700">{data.subjectName}</h1>

  {#if $navigating && (!data.terms || data.terms.length === 0)}
    <div class="flex gap-4 flex-wrap">
      {#each Array(3) as _}
        <Skeleton class="h-28 w-48" />
      {/each}
    </div>
  {:else if data.termsError}
    <StatusCard variant="error" title="Failed to load terms" description={data.termsError} onRetry={() => goto('/my-classes/' + $page.params.classId + '/' + $page.params.subjectId)} />
  {:else if data.terms.length === 0}
    <StatusCard variant="info" title="No Terms Available" description="No terms are available for this subject yet." />
  {:else}
    <div class="flex gap-4 flex-wrap">
      {#each data.terms as term (term.id)}
        {#if term.active}
          <a href="/my-classes/{$page.params.classId}/{$page.params.subjectId}/{term.id}">
            <Card class="w-48 hover:bg-primary-50 dark:hover:bg-primary-950/30 hover:ring-primary-200 dark:hover:ring-primary-700 transition cursor-pointer">
              <CardHeader class="pb-2">
                <CardTitle class="font-display text-base text-primary-700">{term.name}</CardTitle>
              </CardHeader>
            </Card>
          </a>
        {:else}
          <Card class="w-48 opacity-50 pointer-events-none">
            <CardHeader class="pb-2">
              <div class="flex justify-between items-start">
                <CardTitle class="font-display text-base text-surface-400">{term.name}</CardTitle>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-surface-400 shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                </svg>
              </div>
            </CardHeader>
          </Card>
        {/if}
      {/each}
    </div>
  {/if}
</div>
