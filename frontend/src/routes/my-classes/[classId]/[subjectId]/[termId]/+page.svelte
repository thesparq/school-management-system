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
  <h1 class="text-2xl font-display font-bold text-primary-700">{data.termName} — Lessons</h1>

  {#if $navigating && (!data.lessons || data.lessons.length === 0)}
    <div class="space-y-3">
      {#each Array(5) as _}
        <Skeleton class="h-16" />
      {/each}
    </div>
  {:else if data.lessonsError}
    <StatusCard variant="error" title="Failed to load lessons" description={data.lessonsError} onRetry={() => goto('/my-classes/' + $page.params.classId + '/' + $page.params.subjectId + '/' + $page.params.termId)} />
  {:else if data.lessons.length === 0}
    <StatusCard variant="info" title="No Lessons Available" description="No lessons are available for this term yet." />
  {:else}
    <div class="space-y-3">
      {#each data.lessons as lesson (lesson.id)}
        {#if lesson.active !== false}
          <a href="/lms/{$page.params.subjectId}/{$page.params.termId}/{lesson.id}" class="block">
            <Card class="hover:bg-primary-50 dark:hover:bg-primary-950/30 transition cursor-pointer">
              <CardHeader class="pb-0">
                <div class="flex justify-between items-start">
                  <CardTitle class="font-display text-base text-primary-700">
                    Week {lesson.week}: {lesson.topic_title ?? 'Untitled Lesson'}
                  </CardTitle>
                </div>
              </CardHeader>
            </Card>
          </a>
        {:else}
          <Card class="opacity-50 pointer-events-none">
            <CardHeader class="pb-0">
              <div class="flex justify-between items-start">
                <CardTitle class="font-display text-base text-surface-400">
                  Week {lesson.week}: {lesson.topic_title ?? 'Untitled Lesson'}
                </CardTitle>
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
