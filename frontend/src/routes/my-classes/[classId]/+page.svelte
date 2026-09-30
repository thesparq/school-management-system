<script lang="ts">
  import type { PageData } from './$types';
  import { Card, CardHeader, CardTitle } from '$lib/components/ui/card';
  import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
  import PageSkeleton from '$lib/components/ui/skeleton/PageSkeleton.svelte';
  import { page, navigating } from '$app/stores';
  import { goto } from '$app/navigation';

  let { data }: { data: any } = $props();
</script>

<div class="space-y-6">
  {#await data.streamed.classDataPromise}
    <PageSkeleton layout="grid" rows={6} />
  {:then classData}
    <h1 class="text-2xl font-display font-bold text-primary-700">{classData.class_level_name}</h1>
    {#if classData.subjects.length === 0}
      <StatusCard variant="info" title="No Subjects Available" description="No subjects have been assigned for this class." />
    {:else}
      <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {#each classData.subjects as subject (subject.subject_id)}
          <a href="/my-classes/{data.classId}/{subject.subject_id}">
            <Card class="hover:-translate-y-1 hover:shadow-md hover:bg-primary-50 dark:hover:bg-primary-950/30 hover:ring-primary-200 dark:hover:ring-primary-700 transition cursor-pointer">
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
  {:catch error}
    <StatusCard variant="error" title="Failed to load subjects" description={error.message} onRetry={() => goto('/my-classes/' + data.classId)} />
  {/await}
</div>
