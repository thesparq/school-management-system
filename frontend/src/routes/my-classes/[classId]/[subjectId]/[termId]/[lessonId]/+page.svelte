<script lang="ts">
  import type { PageData } from './$types';
  import type { LessonContent, LessonObjective, LessonContentSection, McqQuestion, TheoreticalQuestion } from '$lib/types';
  import { Card, CardHeader, CardTitle, CardContent } from '$lib/components/ui/card';
  import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
  import { Skeleton } from '$lib/components/ui/skeleton';
  import { Badge } from '$lib/components/ui/badge';
  import { Button } from '$lib/components/ui/button';
  import * as Dialog from '$lib/components/ui/dialog/index.js';
  import * as Accordion from '$lib/components/ui/accordion/index.js';
  import { Checkbox } from '$lib/components/ui/checkbox/index.js';
  import { Input } from '$lib/components/ui/input/index.js';
  import { Label } from '$lib/components/ui/label/index.js';
  import { page, navigating } from '$app/stores';
  import { goto } from '$app/navigation';

  const SECTION_IDS = {
    objectives: 'section-objectives',
    keyPoints: 'section-key-points',
  };

  function contentSectionId(sectionNumber: number): string {
    return `section-content-${sectionNumber}`;
  }

  // Tab state
  let activeTab = $state<'lesson' | 'assessments' | 'grading'>('lesson');

  // Side nav state
  let sideNavOpen = $state(false);
  let sideNavMobileOpen = $state(false);
  let activeSection = $state('lesson-top');
  let closeTimer: ReturnType<typeof setTimeout> | undefined = $state();

  // Assessment modal state
  let assessmentModalOpen = $state(false);
  let assessmentTitle = $state('');
  let selectedMcq = $state(new Set<number>());
  let selectedTheory = $state(new Set<number>());

  function openAssessmentModal() {
    assessmentTitle = '';
    selectedMcq = new Set();
    selectedTheory = new Set();
    assessmentModalOpen = true;
  }

  function handleSideNavEnter() {
    clearTimeout(closeTimer);
    sideNavOpen = true;
  }

  function handleSideNavLeave() {
    closeTimer = setTimeout(() => { sideNavOpen = false; }, 300);
  }

  function scrollSpy(node: HTMLElement) {
    let ticking = false;
    function onScroll() {
      if (!ticking) {
        requestAnimationFrame(() => {
          const sectionEls = node.querySelectorAll<HTMLElement>('[data-section]');
          let current = '';
          for (const el of sectionEls) {
            if (el.getBoundingClientRect().top <= 120) {
              current = el.id;
            }
          }
          if (current) activeSection = current;
          ticking = false;
        });
        ticking = true;
      }
    }
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return { destroy() { window.removeEventListener('scroll', onScroll); } };
  }

  function scrollToSection(id: string) {
    const el = document.getElementById(id);
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'start' });
      activeSection = id;
      sideNavMobileOpen = false;
    }
  }

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

  function isMcqQuestion(v: unknown): v is McqQuestion {
    return typeof v === 'object' && v !== null && typeof (v as Record<string, unknown>).question === 'string' && Array.isArray((v as Record<string, unknown>).options);
  }

  function isTheoreticalQuestion(v: unknown): v is TheoreticalQuestion {
    return typeof v === 'object' && v !== null && typeof (v as Record<string, unknown>).question === 'string';
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

  function toggleMcq(i: number) {
    const next = new Set(selectedMcq);
    if (next.has(i)) next.delete(i); else next.add(i);
    selectedMcq = next;
  }

  function toggleTheory(i: number) {
    const next = new Set(selectedTheory);
    if (next.has(i)) next.delete(i); else next.add(i);
    selectedTheory = next;
  }
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
      {@const lesson = result.lesson!}
      {@const objectives = parseJson<LessonObjective>(lesson.objectives, isLessonObjective)}
      {@const contentSections = parseJson<LessonContentSection>(lesson.content_sections, isLessonContentSection)}
      {@const keyPoints = parseJson<string>(lesson.key_points, isString)}
      {@const mcqQuestions = parseJson<McqQuestion>(lesson.mcq_questions, isMcqQuestion)}
      {@const theoryQuestions = parseJson<TheoreticalQuestion>(lesson.theoretical_questions, isTheoreticalQuestion)}
      {@const sectionHeadings = (() => {
        const headings: { id: string; label: string }[] = [];
        if (objectives && objectives.length > 0) {
          headings.push({ id: SECTION_IDS.objectives, label: 'Learning Objectives' });
        }
        if (contentSections && contentSections.length > 0) {
          for (const s of contentSections) {
            if (s.header) {
              headings.push({ id: contentSectionId(s.section_number), label: stripBold(s.header) });
            }
          }
        }
        if (keyPoints && keyPoints.length > 0) {
          headings.push({ id: SECTION_IDS.keyPoints, label: 'Key Points' });
        }
        return headings;
      })()}

      <!-- Tab Bar -->
      <div class="flex border-b border-surface-200 mb-6">
        <button
          onclick={() => activeTab = 'lesson'}
          class="px-4 py-2 text-sm border-b-2 transition cursor-pointer"
          class:border-primary-500 class:text-primary-700 class:font-medium={activeTab === 'lesson'}
          class:border-transparent class:text-surface-500 hover:text-surface-700={activeTab !== 'lesson'}
        >
          Lesson
        </button>
        <button
          onclick={() => activeTab = 'assessments'}
          class="px-4 py-2 text-sm border-b-2 transition cursor-pointer"
          class:border-primary-500 class:text-primary-700 class:font-medium={activeTab === 'assessments'}
          class:border-transparent class:text-surface-500 hover:text-surface-700={activeTab !== 'assessments'}
        >
          Assessments
        </button>
        <button
          onclick={() => activeTab = 'grading'}
          class="px-4 py-2 text-sm border-b-2 transition cursor-pointer"
          class:border-primary-500 class:text-primary-700 class:font-medium={activeTab === 'grading'}
          class:border-transparent class:text-surface-500 hover:text-surface-700={activeTab !== 'grading'}
        >
          Grading
        </button>
      </div>

      <!-- Tab 1: Lesson -->
      {#if activeTab === 'lesson'}
        <div class="flex flex-col md:flex-row gap-0 md:gap-12">
          <div use:scrollSpy class="min-w-0 flex-1 space-y-8 pb-16">

        <div class="space-y-3">
          <Button variant="ghost" class="-ml-3 text-surface-400 hover:text-surface-600" onclick={() => goto('/my-classes/' + $page.params.classId + '/' + $page.params.subjectId + '/' + $page.params.termId)}>
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
            {#if lesson.week != null}
              <Badge variant="outline" class="shrink-0 px-3 py-1 text-sm">
                Week {lesson.week}
              </Badge>
            {/if}
          </div>
        </div>

        {#if objectives && objectives.length > 0}
          <div id={SECTION_IDS.objectives} data-section>
          <Card class="border-primary-100">
            <CardHeader class="pb-2 px-6">
              <CardTitle class="text-xl font-display font-bold text-primary-700">Learning Objectives</CardTitle>
            </CardHeader>
            <CardContent class="pt-4 px-6">
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
          </div>
        {/if}

        {#if contentSections && contentSections.length > 0}
          <div class="space-y-6">
            {#each contentSections as section (section.section_number)}
              <div id={contentSectionId(section.section_number)} data-section>
              <Card>
                {#if section.header}
                  <CardHeader class="pb-2 px-6">
                    <CardTitle class="text-xl font-display font-bold text-primary-700">{stripBold(section.header)}</CardTitle>
                  </CardHeader>
                {/if}
                {#if section.body}
                  <CardContent class="pt-4 space-y-5 px-6">
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
              </div>
            {/each}
          </div>
        {/if}

        {#if keyPoints && keyPoints.length > 0}
          <div id={SECTION_IDS.keyPoints} data-section>
          <Card class="border-amber-200 bg-amber-50/40">
            <CardHeader class="pb-2 px-6">
              <CardTitle class="text-xl font-display font-bold text-amber-800">Key Points</CardTitle>
            </CardHeader>
            <CardContent class="pt-4 px-6">
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
          </div>
        {/if}

          </div>

          {#if sectionHeadings.length > 0}
          <div class="hidden md:block shrink-0 self-start"
               style="position: sticky; top: 50vh; transform: translateY(-50%); z-index: 50; width: 3.5rem;"
               role="navigation"
               aria-label="Lesson sections"
               onmouseenter={handleSideNavEnter}
               onmouseleave={handleSideNavLeave}>

            <div class="absolute right-full top-1/2 -translate-y-1/2
                        transition-all duration-200"
                 class:opacity-100={sideNavOpen}
                 class:translate-x-0={sideNavOpen}
                 class:opacity-0={!sideNavOpen}
                 class:translate-x-2={!sideNavOpen}
                 class:pointer-events-none={!sideNavOpen}>
              <div class="w-52 bg-white dark:bg-surface-900 border border-surface-200 rounded-lg shadow-lg p-3 space-y-2">
                {#each sectionHeadings as heading}
                  <button
                    onclick={() => scrollToSection(heading.id)}
                    class="text-sm text-left w-full block cursor-pointer truncate leading-snug"
                    class:text-primary-600={activeSection === heading.id}
                    class:font-medium={activeSection === heading.id}
                    class:text-surface-600={activeSection !== heading.id}>
                    {heading.label}
                  </button>
                {/each}
              </div>
            </div>

            <div class="flex flex-col items-center gap-2.5 py-3"
                 class:opacity-100={sideNavOpen}
                 class:opacity-70={!sideNavOpen}>
              {#each sectionHeadings as heading}
                <span class="h-3 w-3 rounded-full ring-1 ring-inset"
                      class:bg-primary-500={activeSection === heading.id}
                      class:ring-primary-300={activeSection === heading.id}
                      class:bg-primary-300={activeSection !== heading.id}
                      class:ring-primary-200={activeSection !== heading.id}>
                </span>
              {/each}
            </div>
          </div>
          {/if}
        </div>

        {#if sectionHeadings.length > 0}
        <div class="fixed bottom-6 right-6 z-50 md:hidden"
          role="navigation"
          aria-label="Lesson sections">

          <button
            aria-label="Table of contents"
            class="h-12 w-12 rounded-full bg-primary-500 text-white shadow-lg flex items-center justify-center hover:bg-primary-600 transition"
            onclick={() => { sideNavMobileOpen = !sideNavMobileOpen; }}>
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 12h16M4 18h16" />
            </svg>
          </button>

          {#if sideNavMobileOpen}
            <div class="fixed inset-0" role="button" tabindex="-1" onclick={() => { sideNavMobileOpen = false; }} onkeydown={(e) => { if (e.key === 'Enter' || e.key === ' ') { sideNavMobileOpen = false; } }}></div>

            <div class="absolute bottom-16 right-0 bg-white dark:bg-surface-900 border border-surface-200 rounded-lg shadow-xl p-3 space-y-2 min-w-44 max-w-64">
              {#each sectionHeadings as heading}
                <button
                  onclick={() => scrollToSection(heading.id)}
                  class="text-sm text-left w-full block cursor-pointer truncate leading-snug py-1"
                  class:text-primary-600={activeSection === heading.id}
                  class:font-medium={activeSection === heading.id}
                  class:text-surface-600={activeSection !== heading.id}>
                  {heading.label}
                </button>
              {/each}
            </div>
          {/if}
        </div>
      {/if}
      {/if}
      <!-- End Tab 1: Lesson -->

      <!-- Tab 2: Assessments -->
      {#if activeTab === 'assessments'}
        <div class="space-y-6">
          <div class="flex items-center justify-between">
            <h2 class="text-xl font-display font-bold text-primary-700">Assessments</h2>
            <Button onclick={openAssessmentModal}>Create Assessment</Button>
          </div>

          <div class="space-y-2">
            <!-- Future assessment accordion rows will render here -->
          </div>

          <StatusCard variant="info" title="No Assessments" description="No assessments have been created for this lesson yet." />
        </div>
      {/if}
      <!-- End Tab 2: Assessments -->

      <!-- Tab 3: Grading -->
      {#if activeTab === 'grading'}
        <div class="space-y-6">
          <h2 class="text-xl font-display font-bold text-primary-700">Grading</h2>

          <div>
            <!-- Future assessment → submissions accordion list will render here -->
          </div>

          <StatusCard variant="info" title="No Submissions" description="No submissions to grade yet." />
        </div>
      {/if}
      <!-- End Tab 3: Grading -->

      <!-- Assessment Create Dialog -->
      <Dialog.Root bind:open={assessmentModalOpen}>
  <Dialog.Content class="sm:max-w-lg">
    <Dialog.Header>
      <Dialog.Title>Create Assessment</Dialog.Title>
      <Dialog.Description>Select questions from this lesson.</Dialog.Description>
    </Dialog.Header>
    <div class="space-y-4 py-4">
      <div class="space-y-2">
        <Label for="assessment-title">Assessment Title</Label>
        <Input id="assessment-title" bind:value={assessmentTitle} placeholder="e.g. Week 3 Quiz" />
      </div>
      {#if mcqQuestions && mcqQuestions.length > 0 || theoryQuestions && theoryQuestions.length > 0}
        <Accordion.Root type="multiple" value={['mcq']}>
          {#if mcqQuestions && mcqQuestions.length > 0}
            <Accordion.Item value="mcq">
              <Accordion.Trigger class="text-sm font-medium">MCQ Questions ({mcqQuestions.length})</Accordion.Trigger>
              <Accordion.Content class="pt-2 space-y-1 max-h-64 overflow-y-auto">
                {#each mcqQuestions as q, i}
                  <div class="flex items-start gap-3 py-1">
                    <Checkbox checked={selectedMcq.has(i)} onCheckedChange={() => toggleMcq(i)} />
                    <span class="text-sm text-surface-700">{q.question}</span>
                    <Badge variant="outline" class="shrink-0 text-xs">{q.options.length} options</Badge>
                  </div>
                {/each}
              </Accordion.Content>
            </Accordion.Item>
          {/if}
          {#if theoryQuestions && theoryQuestions.length > 0}
            <Accordion.Item value="theory">
              <Accordion.Trigger class="text-sm font-medium">Theoretical Questions ({theoryQuestions.length})</Accordion.Trigger>
              <Accordion.Content class="pt-2 space-y-1 max-h-64 overflow-y-auto">
                {#each theoryQuestions as q, i}
                  <div class="flex items-start gap-3 py-1">
                    <Checkbox checked={selectedTheory.has(i)} onCheckedChange={() => toggleTheory(i)} />
                    <span class="text-sm text-surface-700">{q.question}</span>
                  </div>
                {/each}
              </Accordion.Content>
            </Accordion.Item>
          {/if}
        </Accordion.Root>
      {:else}
        <p class="text-sm text-surface-500 text-center py-4">No questions available for this lesson.</p>
      {/if}
    </div>
    <Dialog.Footer>
      <Dialog.Close>Cancel</Dialog.Close>
      <Button disabled={!assessmentTitle.trim()} onclick={() => { assessmentModalOpen = false; }}>Create</Button>
    </Dialog.Footer>
  </Dialog.Content>
</Dialog.Root>

  {/if}
{/await}
</div>
