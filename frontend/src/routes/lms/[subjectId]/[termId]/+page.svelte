<script lang="ts">
  import type { PageData } from './$types';
  import { Card, CardHeader, CardTitle } from '$lib/components/ui/card';
  import { Alert, AlertTitle, AlertDescription, AlertAction } from '$lib/components/ui/alert';
  import { Skeleton } from '$lib/components/ui/skeleton';
  import { Button } from '$lib/components/ui/button';
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
    <Alert variant="destructive">
      <AlertTitle>Failed to load lessons</AlertTitle>
      <AlertDescription>{data.lessonsError}</AlertDescription>
      <AlertAction>
        <Button variant="outline" onclick={() => goto('/lms/' + $page.params.subjectId + '/' + $page.params.termId)}>Retry</Button>
      </AlertAction>
    </Alert>
  {:else if data.lessons.length === 0}
    <div class="mx-auto max-w-lg py-16 text-center space-y-6">
      <div class="rounded-full bg-secondary-100 dark:bg-secondary-900/20 mx-auto w-fit p-4">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8 text-secondary-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <circle cx="12" cy="12" r="10" />
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 16v-4m0-4h.01" />
        </svg>
      </div>
      <h2 class="text-xl font-semibold text-surface-800">No Lessons Available</h2>
      <p class="text-surface-700">No lessons are available for this term yet.</p>
    </div>
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
