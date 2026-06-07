<script lang="ts">
  import type { PageData } from './$types';
  import { Card, CardHeader, CardTitle } from '$lib/components/ui/card';
  import PageSkeleton from '$lib/components/ui/skeleton/PageSkeleton.svelte';
  import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
  import PageHeader from '$lib/components/PageHeader.svelte';
  import { page, navigating } from '$app/stores';
  import { goto } from '$app/navigation';

  let { data }: { data: PageData } = $props();
</script>

<div class="space-y-6">
  <PageHeader title={data.subjectName} />

  {#if $navigating && (!data.terms || data.terms.length === 0)}
    <PageSkeleton layout="grid" rows={3} />
  {:else if data.termsError}
    <StatusCard variant="error" title="Failed to load terms" description={data.termsError} onRetry={() => goto('/lms/' + $page.params.subjectId)} />
  {:else if data.terms.length === 0}
    <StatusCard variant="info" title="No Terms Available" description="No terms are available for this subject yet." />
  {:else}
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {#each data.terms as term (term.id)}
        {#if term.active !== false}
          <a href="/lms/{$page.params.subjectId}/{term.id}" class="block">
            <Card class="hover:bg-primary-50 dark:hover:bg-primary-950/30 transition cursor-pointer">
              <CardHeader>
                <CardTitle class="font-display text-base text-primary-700 dark:text-primary-300">{term.name}</CardTitle>
              </CardHeader>
            </Card>
          </a>
        {:else}
          <Card class="opacity-50 pointer-events-none">
            <CardHeader>
              <div class="flex justify-between items-start">
                <CardTitle class="font-display text-base text-muted-foreground">{term.name}</CardTitle>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-muted-foreground shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
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
