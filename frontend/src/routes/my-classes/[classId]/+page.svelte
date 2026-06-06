<script lang="ts">
  import type { PageData } from './$types';
  import { Card, CardHeader, CardTitle } from '$lib/components/ui/card';
  import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
  import { Skeleton } from '$lib/components/ui/skeleton';
  import { page, navigating } from '$app/stores';
  import { goto } from '$app/navigation';

  let { data }: { data: PageData } = $props();
</script>

<div class="space-y-6">
  <h1 class="text-2xl font-display font-bold text-primary-700">{data.classLevelName}</h1>

  {#if $navigating && (!data.subjects || data.subjects.length === 0)}
    <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      {#each Array(6) as _}
        <Skeleton class="h-28" />
      {/each}
    </div>
  {:else if data.subjectsError}
    <StatusCard variant="error" title="Failed to load subjects" description={data.subjectsError} onRetry={() => goto('/my-classes/' + $page.params.classId)} />
  {:else if data.subjects.length === 0}
    <StatusCard variant="info" title="No Subjects Available" description="No subjects have been assigned for this class." />
  {:else}
    <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      {#each data.subjects as subject (subject.subject_id)}
        <a href="/my-classes/{$page.params.classId}/{subject.subject_id}">
          <Card class="hover:bg-primary-50 dark:hover:bg-primary-950/30 hover:ring-primary-200 dark:hover:ring-primary-700 transition cursor-pointer">
            <CardHeader class="pb-0 min-h-[4.5rem]">
              <CardTitle class="flex flex-wrap items-center gap-x-2 gap-y-1 font-display text-base text-primary-700 dark:text-primary-300">
                <span class="truncate">{subject.subject_name}</span>
                {#if subject.subject_code}
                  <span class="rounded bg-primary-100 dark:bg-primary-900/40 px-1.5 py-0.5 text-xs font-mono text-primary-600 dark:text-primary-400 shrink-0">{subject.subject_code}</span>
                {/if}
              </CardTitle>
            </CardHeader>
          </Card>
        </a>
      {/each}
    </div>
  {/if}
</div>
