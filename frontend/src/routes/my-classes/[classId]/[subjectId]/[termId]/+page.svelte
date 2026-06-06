<script lang="ts">
  import type { PageData } from './$types';
  import type { Lesson } from '$lib/types';
  import { Card, CardHeader, CardTitle } from '$lib/components/ui/card';
  import { Switch } from '$lib/components/ui/switch/index.js';
  import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
  import { Skeleton } from '$lib/components/ui/skeleton';
  import { page, navigating } from '$app/stores';
  import { goto } from '$app/navigation';
  import { addToast } from '$lib/stores/toast';

	let { data }: { data: PageData } = $props();

	let lessonsSource = $derived(data.lessons);
	let lessons = $state<Lesson[]>(lessonsSource);

	$effect(() => {
		lessons = lessonsSource;
	});

	async function handleToggleLesson(lessonId: string, newActive: boolean) {
    const idx = lessons.findIndex(l => l.id === lessonId);
    if (idx === -1) return;
    const prev = lessons[idx].active;
    lessons[idx].active = newActive;
    lessons = [...lessons];

    try {
      const res = await fetch('/api/teacher/toggle-lesson', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ lesson_id: lessonId, active: newActive }),
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: { message: 'Request failed' } }));
        throw new Error(err.error?.message ?? 'Request failed');
      }
      const title = lessons[idx].topic_title ?? 'Untitled Lesson';
      addToast('success', 'Lesson updated', `${title} is now ${newActive ? 'visible' : 'hidden'} to students.`);
    } catch (e) {
      lessons[idx].active = prev;
      lessons = [...lessons];
      addToast('error', 'Failed to update lesson', e instanceof Error ? e.message : 'Unknown error');
    }
  }
</script>

<div class="space-y-6">
  <h1 class="text-2xl font-display font-bold text-primary-700">{data.termName} — Lessons</h1>

  {#if $navigating && (!lessons || lessons.length === 0)}
    <div class="space-y-3">
      {#each Array(5) as _}
        <Skeleton class="h-16" />
      {/each}
    </div>
  {:else if data.lessonsError}
    <StatusCard variant="error" title="Failed to load lessons" description={data.lessonsError} onRetry={() => goto('/my-classes/' + $page.params.classId + '/' + $page.params.subjectId + '/' + $page.params.termId)} />
  {:else if lessons.length === 0}
    <StatusCard variant="info" title="No Lessons Available" description="No lessons are available for this term yet." />
  {:else}
    <div class="flex items-center gap-10 pb-1 border-b border-border">
      <span class="flex-1 min-w-0 text-xs font-medium uppercase text-muted-foreground tracking-wider pl-1">Lesson</span>
      <span class="shrink-0 w-44 text-xs font-medium uppercase text-muted-foreground tracking-wider">Visible</span>
    </div>
    <div class="space-y-3">
      {#each lessons as lesson (lesson.id)}
        <div class="flex items-center gap-10">
          <a href="/my-classes/{$page.params.classId}/{$page.params.subjectId}/{$page.params.termId}/{lesson.id}" class="block flex-1 min-w-0">
            <Card class="hover:bg-primary-50 dark:hover:bg-primary-950/30 transition cursor-pointer">
              <CardHeader class="pb-0">
                <div class="flex justify-between items-start">
                  <div>
                    <CardTitle class="font-display text-base text-primary-700 dark:text-primary-300">
                      Week {lesson.week}: {lesson.topic_title ?? 'Untitled Lesson'}
                    </CardTitle>
                  </div>
                </div>
              </CardHeader>
            </Card>
          </a>
          <div class="shrink-0 w-44 flex items-center gap-2">
            <Switch
              checked={lesson.active !== false}
              onCheckedChange={(checked) => handleToggleLesson(lesson.id, checked)}
            />
            <span
              class="text-xs"
              class:text-surface-500={lesson.active !== false}
              class:text-amber-600={lesson.active === false}
            >
              {lesson.active !== false ? 'Visible to students' : 'Hidden from students'}
            </span>
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>
