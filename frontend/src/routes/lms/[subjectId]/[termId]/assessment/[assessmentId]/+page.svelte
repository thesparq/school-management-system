<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import { addToast } from '$lib/stores/toast';
  import AppButton from '$lib/components/ui/app-button.svelte';
  import { Badge } from '$lib/components/ui/badge';

  let termId = $page.params.termId;
  let subjectId = $page.params.subjectId;
  let assessmentId = $page.params.assessmentId;

  let assessment = $state<any>(null);
  let loading = $state(true);
  
  let started = $state(false);
  let submitting = $state(false);
  let timeRemaining = $state(3600); // 60 mins default
  
  let mcqAnswers = $state<Record<number, string>>({});
  let theoryAnswers = $state<Record<number, string>>({});
  
  // Anti-cheat mechanisms
  let cheatWarnings = $state(0);
  const MAX_WARNINGS = 2;
  
  let timerInterval: any;

  onMount(async () => {
    try {
      const res = await fetch(`/api/student/general-assessments?session_term_id=${termId}&subject_id=${subjectId}`);
      if (res.ok) {
        const json = await res.json();
        assessment = (json.data || []).find((a: any) => a.id === assessmentId);
      }
    } catch (e) {
      console.error(e);
    }
    loading = false;
  });

  onDestroy(() => {
    stopCbtMode();
    if (timerInterval) clearInterval(timerInterval);
  });

  async function startExam() {
    if (!document.fullscreenElement) {
      try {
        await document.documentElement.requestFullscreen();
      } catch (err) {
        addToast('error', 'Fullscreen Required', 'You must allow fullscreen to start the exam.');
        return;
      }
    }
    
    started = true;
    startCbtMode();
    
    // Start timer
    timerInterval = setInterval(() => {
      if (timeRemaining > 0) {
        timeRemaining--;
      } else {
        clearInterval(timerInterval);
        addToast('warning', 'Time Up', 'Submitting exam automatically.');
        handleSubmit();
      }
    }, 1000);
  }

  function handleVisibilityChange() {
    if (document.hidden && started && !submitting) {
      recordCheat();
    }
  }
  
  function handleBlur() {
    if (started && !submitting) {
      recordCheat();
    }
  }

  function handleContextMenu(e: Event) {
    if (started) {
      e.preventDefault();
    }
  }

  function recordCheat() {
    cheatWarnings++;
    if (cheatWarnings > MAX_WARNINGS) {
      addToast('error', 'Exam Terminated', 'You have been caught leaving the exam page too many times. Your exam is being automatically submitted.');
      handleSubmit();
    } else {
      alert(`WARNING ${cheatWarnings}/${MAX_WARNINGS}: Please do not switch tabs or leave the exam page. Your exam will be automatically submitted if this happens again.`);
      
      // Force back to fullscreen if we lost it
      if (!document.fullscreenElement) {
        document.documentElement.requestFullscreen().catch(() => {});
      }
    }
  }

  function startCbtMode() {
    document.addEventListener('visibilitychange', handleVisibilityChange);
    window.addEventListener('blur', handleBlur);
    document.addEventListener('contextmenu', handleContextMenu);
  }

  function stopCbtMode() {
    document.removeEventListener('visibilitychange', handleVisibilityChange);
    window.removeEventListener('blur', handleBlur);
    document.removeEventListener('contextmenu', handleContextMenu);
    if (document.fullscreenElement) {
      document.exitFullscreen().catch(() => {});
    }
  }

  async function handleSubmit() {
    submitting = true;
    stopCbtMode();
    if (timerInterval) clearInterval(timerInterval);

    const questions = assessment?.questions || [];
    const answers = questions.map((q: any) => {
      if (q.question_type === 'mcq') {
        return {
          question_index: q.question_index,
          answer_type: 'mcq',
          answer_text: mcqAnswers[q.question_index] ?? '',
          allocated_mark: q.allocated_mark,
        };
      }
      return {
        question_index: q.question_index,
        answer_type: 'theory',
        answer_text: theoryAnswers[q.question_index] ?? '',
        allocated_mark: q.allocated_mark,
      };
    });

    try {
      const res = await fetch('/api/student/submit-assessment', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          assessment_type: 'general',
          assessment_id: assessmentId,
          answers,
        }),
      });
      if (!res.ok) {
        throw new Error('Submission failed');
      }
      addToast('success', 'Exam submitted', 'Your exam has been recorded.');
      goto(`/lms/${subjectId}/${termId}`);
    } catch (e: any) {
      addToast('error', 'Submission failed', e.message);
      submitting = false; // allow retry if network failed
    }
  }
  
  function formatTime(secs: number) {
    const m = Math.floor(secs / 60);
    const s = secs % 60;
    return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
  }
</script>

<svelte:head>
  <title>{assessment?.title || 'Exam'} - CBT</title>
</svelte:head>

<div class="max-w-4xl mx-auto py-8 px-4 h-screen flex flex-col">
  {#if loading}
    <div class="flex-1 flex items-center justify-center">
      <p class="text-muted-foreground animate-pulse">Loading Exam...</p>
    </div>
  {:else if !assessment}
    <div class="flex-1 flex items-center justify-center">
      <div class="text-center space-y-4">
        <h2 class="text-2xl font-bold text-destructive">Exam Not Found</h2>
        <AppButton href="/lms/{subjectId}/{termId}">Go Back</AppButton>
      </div>
    </div>
  {:else if !started}
    <div class="flex-1 flex items-center justify-center">
      <div class="text-center space-y-6 max-w-lg p-8 border rounded-xl shadow-sm bg-white">
        <h1 class="text-3xl font-bold text-primary-700">{assessment.title}</h1>
        <div class="bg-amber-50 text-amber-800 p-4 rounded text-left text-sm space-y-2">
          <p class="font-bold">⚠️ CBT Instructions & Rules</p>
          <ul class="list-disc pl-4 space-y-1">
            <li>This exam will be conducted in Fullscreen Mode.</li>
            <li>Do not switch tabs, minimize the window, or open other applications.</li>
            <li>If you leave the exam screen more than {MAX_WARNINGS} times, your exam will be automatically submitted.</li>
            <li>Right-clicking is disabled.</li>
            <li>You have 60 minutes to complete the exam.</li>
          </ul>
        </div>
        <AppButton class="w-full text-lg py-6" onclick={startExam}>Start Exam</AppButton>
      </div>
    </div>
  {:else}
    <!-- CBT Interface -->
    <div class="flex-1 flex flex-col h-full bg-surface-50 -mx-4 -mt-8 px-4 pt-4 select-none">
      <div class="bg-white border-b sticky top-0 z-10 flex justify-between items-center p-4 rounded-t-xl shadow-sm mb-6">
        <h1 class="text-xl font-bold">{assessment.title}</h1>
        <div class="flex items-center gap-4">
          <div class="text-xl font-mono font-bold text-red-600 bg-red-50 px-4 py-2 rounded-lg">
            {formatTime(timeRemaining)}
          </div>
          <AppButton disabled={submitting} onclick={handleSubmit}>
            {submitting ? 'Submitting...' : 'Finish Exam'}
          </AppButton>
        </div>
      </div>
      
      <div class="flex-1 overflow-y-auto space-y-8 pb-32">
        {#if !assessment.questions || assessment.questions.length === 0}
          <div class="text-center p-8 bg-white rounded-lg shadow-sm">
            <p>No questions configured for this exam.</p>
          </div>
        {:else}
          {#each assessment.questions as question, i}
            <div class="bg-white p-6 rounded-lg shadow-sm border border-border">
              <div class="flex items-center justify-between mb-4">
                <span class="text-lg font-bold text-primary-700">Question {i + 1}</span>
                <Badge variant="outline">{question.allocated_mark} Mark{question.allocated_mark > 1 ? 's' : ''}</Badge>
              </div>
              
              <p class="text-base text-foreground mb-6 select-text">{question.question_text}</p>
              
              {#if question.question_type === 'mcq'}
                <div class="space-y-3">
                  {#if question.option_a}
                    <label class="flex items-center gap-3 p-4 rounded-lg border cursor-pointer hover:bg-surface-50 transition {mcqAnswers[question.question_index] === 'A' ? 'border-primary-500 bg-primary-50' : 'border-border'}">
                      <input type="radio" name="mcq-{question.question_index}" value="A" bind:group={mcqAnswers[question.question_index]} class="w-5 h-5 accent-primary-600" />
                      <span class="text-base">A. {question.option_a}</span>
                    </label>
                  {/if}
                  {#if question.option_b}
                    <label class="flex items-center gap-3 p-4 rounded-lg border cursor-pointer hover:bg-surface-50 transition {mcqAnswers[question.question_index] === 'B' ? 'border-primary-500 bg-primary-50' : 'border-border'}">
                      <input type="radio" name="mcq-{question.question_index}" value="B" bind:group={mcqAnswers[question.question_index]} class="w-5 h-5 accent-primary-600" />
                      <span class="text-base">B. {question.option_b}</span>
                    </label>
                  {/if}
                  {#if question.option_c}
                    <label class="flex items-center gap-3 p-4 rounded-lg border cursor-pointer hover:bg-surface-50 transition {mcqAnswers[question.question_index] === 'C' ? 'border-primary-500 bg-primary-50' : 'border-border'}">
                      <input type="radio" name="mcq-{question.question_index}" value="C" bind:group={mcqAnswers[question.question_index]} class="w-5 h-5 accent-primary-600" />
                      <span class="text-base">C. {question.option_c}</span>
                    </label>
                  {/if}
                </div>
              {:else}
                <textarea
                  bind:value={theoryAnswers[question.question_index]}
                  placeholder="Type your answer here..."
                  class="w-full min-h-[150px] rounded-lg border border-input bg-background px-4 py-3 text-base ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500"
                ></textarea>
              {/if}
            </div>
          {/each}
        {/if}
      </div>
    </div>
  {/if}
</div>
