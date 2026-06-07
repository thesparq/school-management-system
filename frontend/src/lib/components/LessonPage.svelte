<script lang="ts">
  import type {
    LessonContent, LessonObjective, LessonContentSection, McqQuestion, TheoreticalQuestion,
    LessonAssessmentInfo, SubmissionInfo
  } from '$lib/types';
  import { Card, CardHeader, CardTitle, CardContent } from '$lib/components/ui/card';
  import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
  import { Skeleton } from '$lib/components/ui/skeleton';
  import { Badge } from '$lib/components/ui/badge';
  import AppButton from '$lib/components/ui/app-button.svelte';
  import * as Dialog from '$lib/components/ui/dialog/index.js';
  import * as Accordion from '$lib/components/ui/accordion/index.js';
  import { Checkbox } from '$lib/components/ui/checkbox/index.js';
  import { Input } from '$lib/components/ui/input/index.js';
  import { Label } from '$lib/components/ui/label/index.js';
  import GradeAssessmentModal from './GradeAssessmentModal.svelte';
  import SubmitAssessmentModal from './SubmitAssessmentModal.svelte';
  import { fade } from 'svelte/transition';
  import { goto } from '$app/navigation';
  import { addToast } from '$lib/stores/toast';
  import { onMount } from 'svelte';

  let { lesson, isTeacher = false, backHref }: {
    lesson: LessonContent;
    isTeacher?: boolean;
    backHref: string;
  } = $props();

  let activeTab = $state<'lesson' | 'assessments' | 'grading'>('lesson');

  let sideNavOpen = $state(false);
  let sideNavMobileOpen = $state(false);
  let activeSection = $state('lesson-top');
  let closeTimer: ReturnType<typeof setTimeout> | undefined = $state();

  // Real data state
  let loadingAssessments = $state(true);
  let assessmentsError = $state<string | null>(null);
  let assessments = $state<LessonAssessmentInfo[]>([]);

  let loadingSubmissions = $state(true);
  let submissionsError = $state<string | null>(null);
  let submissionsByAssessment = $state<Record<string, SubmissionInfo[]>>({});

  // Create assessment modal
  let createModalOpen = $state(false);
  let assessmentTitle = $state('');
  let selectedMcq = $state(new Set<number>());
  let selectedTheory = $state(new Set<number>());
  let creating = $state(false);

  // Grade modal
  let gradeModalOpen = $state(false);
  let currentGradeSubmission = $state<SubmissionInfo | null>(null);

  // Submit modal
  let submitModalOpen = $state(false);
  let currentSubmitAssessment = $state<LessonAssessmentInfo | null>(null);

  let expandedAssessment = $state<string | undefined>(undefined);
  let expandedGradingAssessment = $state<string | undefined>(undefined);

  const tabs = isTeacher
    ? ['lesson', 'assessments', 'grading'] as const
    : ['lesson', 'assessments'] as const;

  const tabLabels = { lesson: 'Lesson', assessments: 'Assessments', grading: 'Grading' } as const;

  async function loadAssessments() {
    loadingAssessments = true;
    assessmentsError = null;
    try {
      const endpoint = isTeacher ? '/api/teacher/lesson-assessments' : '/api/student/assessments';
      const res = await fetch(`${endpoint}?lesson_id=${encodeURIComponent(lesson.id)}`);
      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: { message: 'Failed to load assessments' } }));
        throw new Error(err.error?.message ?? 'Failed to load assessments');
      }
      const json = await res.json();
      assessments = (json.data ?? []) as LessonAssessmentInfo[];
    } catch (e) {
      assessmentsError = e instanceof Error ? e.message : 'Unknown error';
      assessments = [];
    } finally {
      loadingAssessments = false;
    }
  }

  async function loadSubmissions() {
    if (!isTeacher) return;
    loadingSubmissions = true;
    submissionsError = null;
    try {
      const all: Record<string, SubmissionInfo[]> = {};
      for (const a of assessments) {
        const res = await fetch(`/api/teacher/submissions?assessment_type=lesson&assessment_id=${encodeURIComponent(a.id)}`);
        if (res.ok) {
          const json = await res.json();
          all[a.id] = (json.data ?? []) as SubmissionInfo[];
        } else {
          all[a.id] = [];
        }
      }
      submissionsByAssessment = all;
    } catch (e) {
      submissionsError = e instanceof Error ? e.message : 'Unknown error';
    } finally {
      loadingSubmissions = false;
    }
  }

  function getSubmittedCount(assessmentId: string): number {
    return (submissionsByAssessment[assessmentId] ?? []).filter(s => s.status === 'submitted').length;
  }

  onMount(() => {
    loadAssessments();
  });

  $effect(() => {
    if (assessments.length > 0 && isTeacher) {
      loadSubmissions();
    }
  });

  function openCreateModal() {
    assessmentTitle = '';
    selectedMcq = new Set();
    selectedTheory = new Set();
    createModalOpen = true;
  }

  async function handleCreateAssessment() {
    if (!assessmentTitle.trim()) return;
    creating = true;
    const questions: Record<string, unknown>[] = [];
    let idx = 0;

    for (const mcqIdx of selectedMcq) {
      const q = mcqQuestions?.[mcqIdx];
      if (q) {
        questions.push({
          question_index: idx++,
          question_type: 'mcq',
          source_index: mcqIdx,
          question_text: q.question,
          option_a: q.option_a,
          option_b: q.option_b,
          option_c: q.option_c,
          correct_answer: q.correct_answer,
          allocated_mark: 1,
        });
      }
    }
    for (const theoryIdx of selectedTheory) {
      const q = theoryQuestions?.[theoryIdx];
      if (q) {
        questions.push({
          question_index: idx++,
          question_type: 'theory',
          source_index: theoryIdx,
          question_text: q.question,
          allocated_mark: 5,
        });
      }
    }

    const body = {
      lesson_id: lesson.id,
      title: assessmentTitle.trim(),
      questions,
      max_resubmissions: 1,
    };

    try {
      const res = await fetch('/api/teacher/create-lesson-assessment', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: { message: 'Failed to create assessment' } }));
        throw new Error(err.error?.message ?? 'Failed to create assessment');
      }
      addToast('success', 'Assessment created', `"${assessmentTitle.trim()}" has been created.`);
      createModalOpen = false;
      loadAssessments();
    } catch (e) {
      addToast('error', 'Failed to create assessment', e instanceof Error ? e.message : 'Unknown error');
    } finally {
      creating = false;
    }
  }

  function openGradeModal(submission: SubmissionInfo) {
    currentGradeSubmission = submission;
    gradeModalOpen = true;
  }

  function openSubmitModal(assessment: LessonAssessmentInfo) {
    currentSubmitAssessment = assessment;
    submitModalOpen = true;
  }

  function getMySubmission(assessmentId: string): SubmissionInfo | undefined {
    return submissionsByAssessment[assessmentId]?.[0];
  }

  // Helpers
  const SECTION_IDS = { objectives: 'section-objectives', keyPoints: 'section-key-points' };

  function contentSectionId(sectionNumber: number): string {
    return `section-content-${sectionNumber}`;
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
            if (el.getBoundingClientRect().top <= 120) current = el.id;
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
    if (el) { el.scrollIntoView({ behavior: 'smooth', block: 'start' }); activeSection = id; sideNavMobileOpen = false; }
  }

  function parseJson<T>(raw: string | null, isElement: (v: unknown) => v is T): T[] | null {
    if (!raw) return null;
    try { const p = JSON.parse(raw); return Array.isArray(p) && p.every(v => isElement(v)) ? p : null; } catch { return null; }
  }

  function isLessonObjective(v: unknown): v is LessonObjective {
    return typeof v === 'object' && v !== null && typeof (v as Record<string, unknown>).objective === 'string' && typeof (v as Record<string, unknown>).taxonomy_level === 'string';
  }
  function isLessonContentSection(v: unknown): v is LessonContentSection {
    return typeof v === 'object' && v !== null
      && typeof (v as Record<string, unknown>).header === 'string'
      && typeof (v as Record<string, unknown>).body === 'string'
      && typeof (v as Record<string, unknown>).section_number === 'number';
  }
  function isString(v: unknown): v is string { return typeof v === 'string'; }

  function isMcqQuestion(v: unknown): v is McqQuestion {
    return typeof v === 'object' && v !== null && typeof (v as Record<string, unknown>).question === 'string' && typeof (v as Record<string, unknown>).option_a === 'string';
  }
  function isTheoreticalQuestion(v: unknown): v is TheoreticalQuestion {
    return typeof v === 'object' && v !== null && typeof (v as Record<string, unknown>).question === 'string';
  }

  function stripBold(text: string): string { return text.replace(/\*\*([^*]+)\*\*/g, '$1'); }
  function cleanNum(s: string): string { return s.replace(/[()]/g, '') + '.'; }

  function formatSubPoint(text: string): { label?: string; rest: string } {
    const clean = stripBold(text);
    const idx = clean.indexOf(':');
    if (idx > 0 && idx < 60) return { label: clean.slice(0, idx), rest: clean.slice(idx + 1).trimStart() };
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

  const objectives = parseJson<LessonObjective>(lesson.objectives, isLessonObjective);
  const contentSections = parseJson<LessonContentSection>(lesson.content_sections, isLessonContentSection);
  const keyPoints = parseJson<string>(lesson.key_points, isString);
  const mcqQuestions = parseJson<McqQuestion>(lesson.mcq_questions, isMcqQuestion);
  const theoryQuestions = parseJson<TheoreticalQuestion>(lesson.theoretical_questions, isTheoreticalQuestion);

  const sectionHeadings = (() => {
    const h: { id: string; label: string }[] = [];
    if (objectives && objectives.length > 0) h.push({ id: SECTION_IDS.objectives, label: 'Learning Objectives' });
    if (contentSections && contentSections.length > 0)
      for (const s of contentSections) if (s.header) h.push({ id: contentSectionId(s.section_number), label: stripBold(s.header) });
    if (keyPoints && keyPoints.length > 0) h.push({ id: SECTION_IDS.keyPoints, label: 'Key Points' });
    return h;
  })();
</script>

<div class="mx-auto w-full max-w-5xl px-4 sm:px-6 lg:px-8">
  <div class="flex border-b border-border mb-6">
    {#each tabs as tab}
      <button
        onclick={() => activeTab = tab}
        class="px-4 py-2 text-sm border-b-2 transition cursor-pointer"
        class:border-secondary-500={activeTab === tab}
        class:text-secondary-700={activeTab === tab}
        class:font-medium={activeTab === tab}
        class:border-transparent={activeTab !== tab}
        class:text-surface-500={activeTab !== tab}
        class:hover:text-muted-foreground={activeTab !== tab}
      >
        {tabLabels[tab]}
      </button>
    {/each}
  </div>

{#if activeTab === 'lesson'}
    <div>
      <div class="flex flex-col md:flex-row gap-0 md:gap-12">
        <div use:scrollSpy class="min-w-0 flex-1 space-y-8 pb-16">

          <div class="space-y-3">
              <AppButton variant="ghost" class="-ml-3 text-muted-foreground hover:text-muted-foreground" onclick={() => goto(backHref)}>
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 mr-1.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" />
            </svg>
            Back to lessons
          </AppButton>
          </div>

          <div class="space-y-3">
            <div class="flex items-start justify-between gap-6">
              <div class="space-y-2">
                <h1 class="text-3xl font-display font-bold text-primary-700 leading-tight">{stripBold(lesson.topic_title ?? '')}</h1>
                <p class="text-sm text-muted-foreground font-medium tracking-wide uppercase">{lesson.subject_name ?? 'Subject'} &middot; {lesson.term_name ?? 'Term'}</p>
              </div>
              {#if lesson.week != null}
                <Badge variant="outline" class="shrink-0 px-3 py-1 text-sm">Week {lesson.week}</Badge>
              {/if}
            </div>
          </div>

          {#if objectives && objectives.length > 0}
            <div id={SECTION_IDS.objectives} data-section>
            <Card class="border-primary-100">
              <CardHeader class="pb-2 px-6"><CardTitle class="text-xl font-display font-bold text-primary-700">Learning Objectives</CardTitle></CardHeader>
              <CardContent class="pt-4 px-6">
                <ul class="space-y-4 text-muted-foreground">
                  {#each objectives as objective, idx (objective.objective)}
                    <li class="flex items-start gap-4">
                      <span class="mt-1 flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-primary-100 text-sm font-bold text-primary-700">{idx + 1}</span>
                      <div class="flex-1 space-y-1.5">
                        <p class="leading-relaxed">{stripBold(objective.objective)}</p>
                        <Badge variant="outline" class="text-xs text-muted-foreground border-border">{objective.taxonomy_level}</Badge>
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
                    <CardHeader class="pb-2 px-6"><CardTitle class="text-xl font-display font-bold text-primary-700">{stripBold(section.header)}</CardTitle></CardHeader>
                  {/if}
                  {#if section.body}
                    <CardContent class="pt-4 space-y-5 px-6">
                      <p class="leading-relaxed text-muted-foreground whitespace-pre-wrap">{stripBold(section.body)}</p>
                      {#if section.sub_points && section.sub_points.length > 0}
                        <ul class="space-y-4 pl-5">
                          {#each section.sub_points as sp (sp.sub_number)}
                            {@const fmt = formatSubPoint(sp.text)}
                            <li class="flex items-start gap-3 text-sm text-muted-foreground">
                              <span class="shrink-0 font-semibold text-primary-600 w-8 text-right text-xs leading-5">{cleanNum(sp.sub_number)}</span>
                              <div class="flex-1 leading-relaxed">
                                {#if fmt.label}<strong class="font-semibold text-muted-foreground">{fmt.label}</strong> {fmt.rest}{:else}{fmt.rest}{/if}
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
              <CardHeader class="pb-2 px-6"><CardTitle class="text-xl font-display font-bold text-amber-800">Key Points</CardTitle></CardHeader>
              <CardContent class="pt-4 px-6">
                <ul class="space-y-3 text-muted-foreground">
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
             role="navigation" aria-label="Lesson sections"
             onmouseenter={handleSideNavEnter} onmouseleave={handleSideNavLeave}>
          <div class="absolute right-full top-1/2 -translate-y-1/2 transition-all duration-200"
               class:opacity-100={sideNavOpen} class:translate-x-0={sideNavOpen}
               class:opacity-0={!sideNavOpen} class:translate-x-2={!sideNavOpen} class:pointer-events-none={!sideNavOpen}>
            <div class="w-52 bg-background dark:bg-surface-900 border border-border rounded-lg shadow-lg p-3 space-y-2">
              {#each sectionHeadings as heading}
                <button onclick={() => scrollToSection(heading.id)}
                  class="text-sm text-left w-full block cursor-pointer truncate leading-snug"
                  class:text-primary-600={activeSection === heading.id} class:font-medium={activeSection === heading.id}
                  class:text-muted-foreground={activeSection !== heading.id}>{heading.label}</button>
              {/each}
            </div>
          </div>
          <div class="flex flex-col items-center gap-2.5 py-3" class:opacity-100={sideNavOpen} class:opacity-70={!sideNavOpen}>
            {#each sectionHeadings as heading}
              <span class="h-3 w-3 rounded-full ring-1 ring-inset"
                    class:bg-primary-500={activeSection === heading.id} class:ring-primary-300={activeSection === heading.id}
                    class:bg-primary-300={activeSection !== heading.id} class:ring-primary-200={activeSection !== heading.id}></span>
            {/each}
          </div>
        </div>
        {/if}
      </div>

      {#if sectionHeadings.length > 0}
      <div class="fixed bottom-6 right-6 z-50 md:hidden" role="navigation" aria-label="Lesson sections">
        <button aria-label="Table of contents"
          class="h-12 w-12 rounded-full bg-primary-500 text-white shadow-lg flex items-center justify-center hover:bg-primary-600 transition"
          onclick={() => { sideNavMobileOpen = !sideNavMobileOpen; }}>
          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 12h16M4 18h16" />
          </svg>
        </button>
        {#if sideNavMobileOpen}
          <div class="fixed inset-0" role="button" tabindex="-1" onclick={() => { sideNavMobileOpen = false; }} onkeydown={(e) => { if (e.key === 'Enter' || e.key === ' ') { sideNavMobileOpen = false; } }}></div>
          <div class="absolute bottom-16 right-0 bg-background dark:bg-surface-900 border border-border rounded-lg shadow-xl p-3 space-y-2 min-w-44 max-w-64">
            {#each sectionHeadings as heading}
              <button onclick={() => scrollToSection(heading.id)}
                class="text-sm text-left w-full block cursor-pointer truncate leading-snug py-1"
                class:text-primary-600={activeSection === heading.id} class:font-medium={activeSection === heading.id}
                class:text-muted-foreground={activeSection !== heading.id}>{heading.label}</button>
            {/each}
          </div>
        {/if}
      </div>
      {/if}
    </div>
    {/if}

  <!-- Assessments Tab -->
  {#if activeTab === 'assessments'}
    <div>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <h2 class="text-xl font-display font-bold text-primary-700">Assessments</h2>
          {#if isTeacher}
            <AppButton onclick={openCreateModal}>Create Assessment</AppButton>
          {/if}
        </div>

        {#if loadingAssessments}
          <div class="space-y-3">
            <Skeleton class="h-12 w-full" />
            <Skeleton class="h-12 w-full" />
          </div>
        {:else if assessmentsError}
          <StatusCard variant="error" title="Failed to load assessments" description={assessmentsError} onRetry={loadAssessments} />
        {:else if assessments.length === 0}
          <StatusCard variant="info" title={isTeacher ? 'No Assessments' : 'Your Assignments'} description={isTeacher ? 'Create your first assessment for this lesson.' : 'Assigned assessments will appear here. Check back when your teacher creates one.'} />
        {:else}
          <Accordion.Root type="single" bind:value={expandedAssessment}>
            {#each assessments as a (a.id)}
              <Accordion.Item value={a.id}>
                <Accordion.Trigger class="text-sm font-medium">
                  <div class="flex items-center gap-3">
                    <span>{a.title}</span>
                    <span class="text-xs text-muted-foreground font-normal">
                      {a.questions.length} question{a.questions.length !== 1 ? 's' : ''}
                      {#if a.deadline}
                        &middot; Due {new Date(a.deadline).toLocaleDateString()}
                      {/if}
                    </span>
                    {#if !a.active}
                      <span class="text-xs text-amber-600 font-normal">Inactive</span>
                    {/if}
                  </div>
                </Accordion.Trigger>
                <Accordion.Content class="pt-2 pl-4 space-y-4">
                  {#if a.description}
                    <p class="text-sm text-muted-foreground">{a.description}</p>
                  {/if}

                  <div class="space-y-2">
                    {#each a.questions as q, i}
                      <div class="flex items-start gap-3 py-1 border-l-2 border-border pl-3">
                        <span class="text-xs font-medium text-muted-foreground w-5 shrink-0">{i + 1}.</span>
                        <div class="min-w-0">
                          <span class="text-sm text-muted-foreground">{q.question_text}</span>
                          <span class="text-xs text-muted-foreground ml-2">
                            ({q.question_type === 'mcq' ? 'MCQ' : 'Theory'} &middot; {q.allocated_mark} mark{q.allocated_mark !== 1 ? 's' : ''})
                          </span>
                        </div>
                      </div>
                    {/each}
                  </div>

                  {#if !isTeacher}
                    {@const mySub = getMySubmission(a.id)}
                    {#if mySub}
                      <div class="flex items-center gap-3 pt-2">
                        <Badge class="text-xs bg-success-50 text-success-600 border-success-200">
                          Submitted &middot; Iteration {mySub.iteration}
                        </Badge>
                        {#if mySub.grade_released_at}
                          <span class="text-sm font-medium text-foreground">Score: {mySub.scored_mark ?? '-'}/{mySub.total_mark}</span>
                        {/if}
                      </div>
                    {:else}
                      <AppButton size="sm" onclick={() => openSubmitModal(a)}>Take Assessment</AppButton>
                    {/if}
                  {/if}
                </Accordion.Content>
              </Accordion.Item>
            {/each}
          </Accordion.Root>
        {/if}
      </div>
    </div>
  {/if}

  <!-- Grading Tab (teacher only) -->
  {#if activeTab === 'grading'}
    <div>
      <div class="space-y-6">
        <h2 class="text-xl font-display font-bold text-primary-700">Grading</h2>

        {#if loadingSubmissions || loadingAssessments}
          <div class="space-y-3">
            <Skeleton class="h-12 w-full" />
            <Skeleton class="h-12 w-full" />
          </div>
        {:else if submissionsError}
          <StatusCard variant="error" title="Failed to load submissions" description={submissionsError} />
        {:else if assessments.length === 0}
          <StatusCard variant="info" title="No Submissions" description="Create an assessment first to see student submissions." />
        {:else}
          <Accordion.Root type="single" bind:value={expandedGradingAssessment}>
            {#each assessments as a (a.id)}
              {@const subs = submissionsByAssessment[a.id] ?? []}
              {@const submittedCount = subs.filter(s => s.status === 'submitted').length}
              <Accordion.Item value={a.id}>
                <Accordion.Trigger class="text-sm font-medium">
                  <div class="flex items-center gap-3">
                    <span>{a.title}</span>
                    <span class="text-xs text-muted-foreground font-normal">{submittedCount} submission{submittedCount !== 1 ? 's' : ''}</span>
                  </div>
                </Accordion.Trigger>
                <Accordion.Content class="pt-2 pl-4 space-y-1">
                  {#if subs.length === 0}
                    <p class="text-sm text-muted-foreground py-3">No submissions yet.</p>
                  {:else}
                    {#each subs as s}
                      <div class="flex items-center justify-between py-2 px-3 rounded border border-border">
                        <div class="flex items-center gap-3">
                          <span class="text-sm text-muted-foreground font-medium">{s.student_name ?? 'Unknown Student'}</span>
                          {#if s.status === 'submitted'}
                            <Badge variant="outline" class="text-xs bg-success-50 text-success-600 border-success-200">Submitted</Badge>
                            <span class="text-xs text-muted-foreground">Iteration {s.iteration}</span>
                            {#if s.scored_mark != null}
                              <span class="text-xs text-muted-foreground">{s.scored_mark}/{s.total_mark}</span>
                            {/if}
                          {:else}
                            <Badge variant="outline" class="text-xs bg-muted text-surface-500-500">Not Submitted</Badge>
                          {/if}
                        </div>
                        <div class="flex items-center gap-2">
                          {#if s.grade_released_at}
                            <Badge class="text-xs bg-success-50 text-success-600">Grades Released</Badge>
                          {:else if s.status === 'submitted'}
                            <AppButton variant="outline" size="sm" onclick={() => openGradeModal(s)}>Grade</AppButton>
                            <AppButton variant="ghost" size="sm" onclick={async () => {
                              try {
                                const r = await fetch('/api/teacher/release-grades', {
                                  method: 'POST',
                                  headers: { 'Content-Type': 'application/json' },
                                  body: JSON.stringify({ submission_id: s.id }),
                                });
                                if (r.ok) {
                                  addToast('success', 'Grades released', 'Student can now see their grades.');
                                  loadSubmissions();
                                }
                              } catch {}
                            }}>Release</AppButton>
                          {/if}
                        </div>
                      </div>
                    {/each}
                  {/if}
                </Accordion.Content>
              </Accordion.Item>
            {/each}
          </Accordion.Root>
        {/if}
      </div>
    </div>
    {/if}

  <!-- Create Assessment Modal (teacher only) -->
  {#if isTeacher}
    <Dialog.Root bind:open={createModalOpen}>
      <Dialog.Content class="sm:max-w-5xl max-h-[92vh] flex flex-col">
        <Dialog.Header>
          <Dialog.Title>Create Assessment</Dialog.Title>
          <Dialog.Description>Select questions from this lesson.</Dialog.Description>
        </Dialog.Header>

        <div class="flex-1 overflow-y-auto px-0.5 py-6 space-y-8">
          <div class="space-y-2">
            <Label for="assessment-title">Assessment Title</Label>
            <Input id="assessment-title" bind:value={assessmentTitle} placeholder="e.g. Week 3 Quiz" />
          </div>

          {#if mcqQuestions && mcqQuestions.length > 0 || theoryQuestions && theoryQuestions.length > 0}
            <Accordion.Root type="multiple" value={[]}>
              <Accordion.Item value="mcq">
                <Accordion.Trigger class="text-base font-medium py-4 sticky top-0 bg-background dark:bg-surface-950 z-10">MCQ Questions ({mcqQuestions?.length ?? 0})</Accordion.Trigger>
                <Accordion.Content class="pt-3 space-y-4">
                  {#if mcqQuestions && mcqQuestions.length > 0}
                    {#each mcqQuestions as q, i}
                      <div class="flex items-start gap-4 py-3 px-2 rounded hover:bg-surface-50">
                        <Checkbox checked={selectedMcq.has(i)} onCheckedChange={() => toggleMcq(i)} />
                        <div class="flex-1 min-w-0 space-y-2">
                          <p class="text-sm text-foreground leading-relaxed">{q.question}</p>
                          <div class="flex flex-wrap gap-x-6 gap-y-1 text-xs text-surface-500">
                            <span>A. {q.option_a}</span>
                            <span>B. {q.option_b}</span>
                            <span>C. {q.option_c}</span>
                          </div>
                        </div>
                      </div>
                    {/each}
                  {:else}
                    <p class="text-sm text-muted-foreground text-center py-8">No MCQ questions available for this lesson.</p>
                  {/if}
                </Accordion.Content>
              </Accordion.Item>

              <Accordion.Item value="theory">
                <Accordion.Trigger class="text-base font-medium py-4 sticky top-0 bg-background dark:bg-surface-950 z-10">Theoretical Questions ({theoryQuestions?.length ?? 0})</Accordion.Trigger>
                <Accordion.Content class="pt-3 space-y-3">
                  {#if theoryQuestions && theoryQuestions.length > 0}
                    {#each theoryQuestions as q, i}
                      <div class="flex items-start gap-4 py-3 px-2 rounded hover:bg-surface-50">
                        <Checkbox checked={selectedTheory.has(i)} onCheckedChange={() => toggleTheory(i)} />
                        <p class="text-sm text-foreground leading-relaxed">{q.question}</p>
                      </div>
                    {/each}
                  {:else}
                    <p class="text-sm text-muted-foreground text-center py-8">No theoretical questions available for this lesson.</p>
                  {/if}
                </Accordion.Content>
              </Accordion.Item>
            </Accordion.Root>
          {:else}
            <p class="text-sm text-surface-500 text-center py-12">No questions available for this lesson.</p>
          {/if}
        </div>

        <Dialog.Footer>
          <Dialog.Close>Cancel</Dialog.Close>
          <AppButton disabled={!assessmentTitle.trim() || creating} onclick={handleCreateAssessment}>
            {creating ? 'Creating...' : 'Create'}
          </AppButton>
        </Dialog.Footer>
      </Dialog.Content>
    </Dialog.Root>
  {/if}

  {#if currentGradeSubmission}
    <GradeAssessmentModal
      open={gradeModalOpen}
      submission={currentGradeSubmission}
      onGradeComplete={() => {
        gradeModalOpen = false;
        currentGradeSubmission = null;
        loadSubmissions();
      }}
    />
  {/if}

  {#if currentSubmitAssessment}
    <SubmitAssessmentModal
      open={submitModalOpen}
      assessmentId={currentSubmitAssessment.id}
      assessmentType="lesson"
      title={currentSubmitAssessment.title}
      questions={currentSubmitAssessment.questions}
      onSubmitComplete={() => {
        submitModalOpen = false;
        currentSubmitAssessment = null;
        loadAssessments();
      }}
    />
  {/if}

</div>
