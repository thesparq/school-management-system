<script lang="ts">
  import type { PageData } from './$types';
  import LessonPage from '$lib/components/LessonPage.svelte';
  import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
  import { Skeleton } from '$lib/components/ui/skeleton';
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';

  let { data }: { data: PageData } = $props();
</script>

<div class="mx-auto w-full max-w-5xl px-4 sm:px-6 lg:px-8">
  {#await data.streamed.lesson}
    <div class="space-y-6">
      <Skeleton class="h-4 w-24" />
      <Skeleton class="h-4 w-64" />
      <Skeleton class="h-10 w-72" />
      <Skeleton class="h-4 w-64" />
      <Skeleton class="h-40 w-full" />
      <Skeleton class="h-56 w-full" />
    </div>
  {:then result}
    {#if result.lessonError}
      <StatusCard variant="error" title="Failed to load lesson" description={result.lessonError} onRetry={() => goto('/my-classes/' + $page.params.classId + '/' + $page.params.subjectId + '/' + $page.params.termId + '/' + $page.params.lessonId)} />
    {:else}
      <LessonPage
        lesson={result.lesson!}
        isTeacher={true}
        backHref={`/my-classes/${$page.params.classId}/${$page.params.subjectId}/${$page.params.termId}`}
      />
    {/if}
  {/await}
</div>
