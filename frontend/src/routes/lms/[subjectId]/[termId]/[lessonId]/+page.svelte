<script lang="ts">
  import type { PageData } from './$types';
  import type { LessonContent, LessonObjective, LessonContentSection } from '$lib/types';
  import { Card, CardHeader, CardTitle, CardContent } from '$lib/components/ui/card';
  import { Alert, AlertTitle, AlertDescription, AlertAction } from '$lib/components/ui/alert';
  import { Skeleton } from '$lib/components/ui/skeleton';
  import { Badge } from '$lib/components/ui/badge';
  import { Separator } from '$lib/components/ui/separator';
  import { Button } from '$lib/components/ui/button';
  import { page, navigating } from '$app/stores';
  import { goto } from '$app/navigation';

  let { data }: { data: PageData } = $props();

  function parseJson<T>(raw: string | null, isElement: (v: unknown) => v is T): T[] | null {
    if (!raw) return null;
    try {
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) && parsed.every(v => isElement(v)) ? parsed : null;
    } catch {
      return null;
    }
  }

  function isLessonObjective(v: unknown): v is LessonObjective {
    return typeof v === 'object' && v !== null && typeof (v as Record<string, unknown>).objective === 'string' && typeof (v as Record<string, unknown>).taxonomy_level === 'string';
  }

  function isLessonContentSection(v: unknown): v is LessonContentSection {
    return typeof v === 'object' && v !== null && typeof (v as Record<string, unknown>).header === 'string' && typeof (v as Record<string, unknown>).body === 'string';
  }

  function isString(v: unknown): v is string {
    return typeof v === 'string';
  }

  function stripBold(text: string): string {
    return text.replace(/\*\*([^*]+)\*\*/g, '$1');
  }

  function cleanNum(s: string): string {
    return s.replace(/[()]/g, '') + '.';
  }

  function formatSubPoint(text: string): { label?: string; rest: string } {
    const clean = stripBold(text);
    const idx = clean.indexOf(':');
    if (idx > 0 && idx < 60) {
      return { label: clean.slice(0, idx), rest: clean.slice(idx + 1).trimStart() };
    }
    return { rest: clean };
  }
</script>

<div class="mx-auto max-w-4xl space-y-8">
  {#await data.streamed.lesson}
    <div class="space-y-6">
      <Skeleton class="h-4 w-24" />
      <Skeleton class="h-10 w-72" />
      <Skeleton class="h-4 w-64" />
      <Skeleton class="h-40 w-full" />
      <Skeleton class="h-56 w-full" />
    </div>
  {:then result}
    {#if result.lessonError}
      <Alert variant="destructive">
        <AlertTitle>Failed to load lesson</AlertTitle>
        <AlertDescription>{result.lessonError}</AlertDescription>
        <AlertAction>
          <Button variant="outline" onclick={() => goto('/lms/' + $page.params.subjectId + '/' + $page.params.termId + '/' + $page.params.lessonId)}>Retry</Button>
        </AlertAction>
      </Alert>
    {:else}
      {@const lesson = result.lesson!}
      {@const objectives = parseJson<LessonObjective>(lesson.objectives, isLessonObjective)}
      {@const contentSections = parseJson<LessonContentSection>(lesson.content_sections, isLessonContentSection)}
      {@const keyPoints = parseJson<string>(lesson.key_points, isString)}

      <div class="space-y-3">
        <Button variant="ghost" class="-ml-3 text-surface-400 hover:text-surface-600" onclick={() => goto('/lms/' + $page.params.subjectId + '/' + $page.params.termId)}>
          <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 mr-1.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
          Back to lessons
        </Button>
      </div>

      <div class="space-y-3">
        <div class="flex items-start justify-between gap-6">
          <div class="space-y-2">
            <h1 class="text-3xl font-display font-bold text-primary-700 leading-tight">{stripBold(lesson.topic_title ?? '')}</h1>
            <p class="text-sm text-surface-400 font-medium tracking-wide uppercase">{lesson.subject_name ?? 'Subject'} &middot; {lesson.term_name ?? 'Term'}</p>
          </div>
          {#if lesson.week !== null}
            <Badge variant="outline" class="shrink-0 px-3 py-1 text-sm">
              Week {lesson.week}
            </Badge>
          {/if}
        </div>
      </div>

      <Separator />

      {#if objectives && objectives.length > 0}
        <Card class="border-primary-100">
          <CardHeader class="pb-2">
            <CardTitle class="text-xl font-display font-bold text-primary-700">Learning Objectives</CardTitle>
          </CardHeader>
          <CardContent class="pt-4">
            <ul class="space-y-4 text-surface-700">
              {#each objectives as objective, idx (objective.objective)}
                <li class="flex items-start gap-4">
                  <span class="mt-1 flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-primary-100 text-sm font-bold text-primary-700">
                    {idx + 1}
                  </span>
                  <div class="flex-1 space-y-1.5">
                    <p class="leading-relaxed">{stripBold(objective.objective)}</p>
                    <Badge variant="outline" class="text-xs text-surface-400 border-surface-200">
                      {objective.taxonomy_level}
                    </Badge>
                  </div>
                </li>
              {/each}
            </ul>
          </CardContent>
        </Card>
      {/if}

      {#if contentSections && contentSections.length > 0}
        <div class="space-y-6">
          {#each contentSections as section (section.section_number)}
            <Card>
              {#if section.header}
                <CardHeader class="pb-2">
                  <CardTitle class="text-xl font-display font-bold text-primary-700">{stripBold(section.header)}</CardTitle>
                </CardHeader>
              {/if}
              {#if section.body}
                <CardContent class="pt-4 space-y-5">
                  <p class="leading-relaxed text-surface-700 whitespace-pre-wrap">{stripBold(section.body)}</p>
                  {#if section.sub_points && section.sub_points.length > 0}
                    <ul class="space-y-4 pl-5">
                      {#each section.sub_points as sp (sp.sub_number)}
                        {@const fmt = formatSubPoint(sp.text)}
                        <li class="flex items-start gap-3 text-sm text-surface-600">
                          <span class="shrink-0 font-semibold text-primary-600 w-8 text-right text-xs leading-5">{cleanNum(sp.sub_number)}</span>
                          <div class="flex-1 leading-relaxed">
                            {#if fmt.label}
                              <strong class="font-semibold text-surface-700">{fmt.label}</strong>
                              {fmt.rest}
                            {:else}
                              {fmt.rest}
                            {/if}
                          </div>
                        </li>
                      {/each}
                    </ul>
                  {/if}
                </CardContent>
              {/if}
            </Card>
          {/each}
        </div>
      {/if}

      {#if keyPoints && keyPoints.length > 0}
        <Card class="border-amber-200 bg-amber-50/40">
          <CardHeader class="pb-2">
            <CardTitle class="text-xl font-display font-bold text-amber-800">Key Points</CardTitle>
          </CardHeader>
          <CardContent class="pt-4">
            <ul class="space-y-3 text-surface-700">
              {#each keyPoints as point}
                <li class="flex items-start gap-3 leading-relaxed">
                  <span class="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-amber-400"></span>
                  <span>{stripBold(point)}</span>
                </li>
              {/each}
            </ul>
          </CardContent>
        </Card>
      {/if}
    {/if}
  {/await}
</div>
