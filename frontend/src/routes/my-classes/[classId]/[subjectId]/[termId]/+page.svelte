<script lang="ts">
  import type { PageData } from './$types';
  import type { Lesson } from '$lib/types';
  import { Card, CardHeader, CardTitle } from '$lib/components/ui/card';
  import { Switch } from '$lib/components/ui/switch/index.js';
  import { Badge } from '$lib/components/ui/badge';
  import PageSkeleton from '$lib/components/ui/skeleton/PageSkeleton.svelte';
  import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
  import { page, navigating } from '$app/stores';
  import { goto } from '$app/navigation';
  import { addToast } from '$lib/stores/toast';
  import { onMount } from 'svelte';
  import TermAssessments from '$lib/components/TermAssessments.svelte';

	let { data }: { data: any } = $props();

	let lessons = $state<Lesson[]>([]);
	let assessmentCounts = $state<Record<string, number>>({});
	let activeTab = $state<'lessons' | 'assessments'>('lessons');
  let hasResolvedData = $state(false);

	$effect(() => {
    if (data.streamed) {
      data.streamed.dataPromise.then((res: any) => {
        lessons = res.lessons;
        hasResolvedData = true;
        loadAssessmentCounts(res.lessons);
      });
    }
	});

	async function loadAssessmentCounts(currentLessons: Lesson[]) {
		const counts: Record<string, number> = {};
		for (const lesson of currentLessons) {
			try {
				const res = await fetch(`/api/teacher/lesson-assessments?lesson_id=${encodeURIComponent(lesson.id)}`);
				if (res.ok) {
					const json = await res.json();
					counts[lesson.id] = (json.data ?? []).length;
				}
			} catch { /* ignore */ }
		}
		assessmentCounts = counts;
	}

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
  {#await data.streamed.dataPromise}
    <div class="flex justify-between items-end border-b border-border pb-4">
      <h1 class="text-2xl font-display font-bold text-primary-700">Loading...</h1>
    </div>
    <PageSkeleton layout="list" rows={5} />
  {:then resolvedData}
    <div class="flex justify-between items-end border-b border-border pb-4">
      <h1 class="text-2xl font-display font-bold text-primary-700">{resolvedData.termName}</h1>
      <div class="flex space-x-4">
        <button class="px-3 py-1 font-semibold border-b-2 {activeTab === 'lessons' ? 'border-primary text-primary' : 'border-transparent text-muted-foreground'}" onclick={() => activeTab = 'lessons'}>Lessons</button>
        <button class="px-3 py-1 font-semibold border-b-2 {activeTab === 'assessments' ? 'border-primary text-primary' : 'border-transparent text-muted-foreground'}" onclick={() => activeTab = 'assessments'}>Term Assessments</button>
      </div>
    </div>

    {#if activeTab === 'lessons'}
      {#if lessons.length === 0}
        <StatusCard variant="info" title="No Lessons Available" description="No lessons are available for this term yet." />
      {:else}
        <div class="flex items-center gap-10 pb-1 border-b border-border">
          <span class="flex-1 min-w-0 text-xs font-medium uppercase text-muted-foreground tracking-wider pl-1">Lesson</span>
          <span class="shrink-0 w-44 text-xs font-medium uppercase text-muted-foreground tracking-wider">Visible</span>
        </div>
        <div class="space-y-3">
          {#each lessons as lesson (lesson.id)}
            <div class="flex items-center gap-10">
              <a href="/my-classes/{data.classId}/{data.subjectId}/{data.termId}/{lesson.id}" class="block flex-1 min-w-0">
                <Card class="hover:-translate-y-1 hover:shadow-md hover:bg-primary-50 dark:hover:bg-primary-950/30 transition cursor-pointer">
                  <CardHeader class="pb-0">
                    <div class="flex justify-between items-start">
                      <div>
                        <CardTitle class="font-display text-base text-primary-700 dark:text-primary-300">
                          Week {lesson.week}: {lesson.topic_title ?? 'Untitled Lesson'}
                        </CardTitle>
                        <div class="flex items-center gap-2 mt-1.5">
                          {#if (assessmentCounts[lesson.id] ?? 0) > 0}
                            <Badge variant="outline" class="text-xs bg-primary-50 text-primary-600 border-primary-200">
                              {assessmentCounts[lesson.id]} assessment{assessmentCounts[lesson.id] !== 1 ? 's' : ''}
                            </Badge>
                          {:else}
                            <span class="text-xs text-muted-foreground">No assessments</span>
                          {/if}
                        </div>
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
    {:else}
      <TermAssessments termId={data.termId} subjectId={data.subjectId} classId={data.classId} {lessons} />
    {/if}
  {:catch error}
    <StatusCard variant="error" title="Failed to load lessons" description={error.message} onRetry={() => goto('/my-classes/' + data.classId + '/' + data.subjectId + '/' + data.termId)} />
  {/await}
</div>
