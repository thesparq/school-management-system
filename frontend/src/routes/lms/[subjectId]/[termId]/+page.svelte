<script lang="ts">
  import type { PageData } from './$types';
  import { Card, CardHeader, CardTitle } from '$lib/components/ui/card';
  import PageSkeleton from '$lib/components/ui/skeleton/PageSkeleton.svelte';
  import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
  import PageHeader from '$lib/components/PageHeader.svelte';
  import { page, navigating } from '$app/stores';
  import { invalidateAll } from '$app/navigation';

  let { data }: { data: any } = $props();
  import StudentTermGrades from '$lib/components/StudentTermGrades.svelte';
  let activeTab = $state<'lessons' | 'grades'>('lessons');
</script>

<div class="space-y-6">
  <div class="flex justify-between items-end border-b border-border pb-4">
    <h1 class="text-2xl font-display font-bold text-primary-700">{data.termName}</h1>
    <div class="flex space-x-4">
      <button class="px-3 py-1 font-semibold border-b-2 {activeTab === 'lessons' ? 'border-primary text-primary' : 'border-transparent text-muted-foreground'}" onclick={() => activeTab = 'lessons'}>Lessons</button>
      <button class="px-3 py-1 font-semibold border-b-2 {activeTab === 'grades' ? 'border-primary text-primary' : 'border-transparent text-muted-foreground'}" onclick={() => activeTab = 'grades'}>Grades & CA</button>
    </div>
  </div>

  {#if activeTab === 'lessons'}
    {#if $navigating && (!data.lessons || data.lessons.length === 0)}
    <PageSkeleton layout="list" rows={5} />
  {:else if data.lessonsError}
    <StatusCard variant="error" title="Failed to load lessons" description={data.lessonsError} onRetry={() => invalidateAll()} />
  {:else if data.lessons.length === 0}
    <StatusCard variant="info" title="No Lessons Available" description="No lessons are available for this term yet." />
  {:else}
    <div class="space-y-3">
      {#each data.lessons as lesson (lesson.id)}
        {#if lesson.active !== false}
          <a href="/lms/{$page.params.subjectId}/{$page.params.termId}/{lesson.id}" class="block">
            <Card class="hover:-translate-y-1 hover:shadow-md hover:bg-primary-50 dark:hover:bg-primary-950/30 transition cursor-pointer">
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
                <CardTitle class="font-display text-base text-muted-foreground">
                  Week {lesson.week}: {lesson.topic_title ?? 'Untitled Lesson'}
                </CardTitle>
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
  {:else}
    <StudentTermGrades termId={$page.params.termId} subjectId={$page.params.subjectId} lessons={data.lessons} />
  {/if}
</div>
