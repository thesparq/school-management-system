<script lang="ts">
  import type { AssessmentQuestion } from '$lib/types';
  import * as Dialog from '$lib/components/ui/dialog/index.js';
  import { Label } from '$lib/components/ui/label/index.js';
  import { Badge } from '$lib/components/ui/badge';
  import AppButton from '$lib/components/ui/app-button.svelte';
  import { addToast } from '$lib/stores/toast';

  let { open, assessmentId, assessmentType, title, questions, onSubmitComplete }: {
    open: boolean;
    assessmentId: string;
    assessmentType: string;
    title: string;
    questions: AssessmentQuestion[];
    onSubmitComplete: () => void;
  } = $props();

  let submitting = $state(false);
  let mcqAnswers: Record<number, string> = $state({});
  let theoryAnswers: Record<number, string> = $state({});

  $effect(() => {
    if (open) {
      mcqAnswers = {};
      theoryAnswers = {};
    }
  });

  async function handleSubmit() {
    submitting = true;
    const answers = questions.map(q => {
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
          assessment_type: assessmentType,
          assessment_id: assessmentId,
          answers,
        }),
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: { message: 'Submission failed' } }));
        throw new Error(err.error?.message ?? 'Submission failed');
      }
      addToast('success', 'Assessment submitted', 'Your answers have been recorded.');
      onSubmitComplete();
    } catch (e) {
      addToast('error', 'Submission failed', e instanceof Error ? e.message : 'Unknown error');
    } finally {
      submitting = false;
    }
  }
</script>

<Dialog.Root bind:open>
  <Dialog.Content class="sm:max-w-3xl max-h-[92vh] flex flex-col">
    <Dialog.Header>
      <Dialog.Title>{title}</Dialog.Title>
      <Dialog.Description>Answer all questions before submitting.</Dialog.Description>
    </Dialog.Header>

    <div class="flex-1 overflow-y-auto px-0.5 py-6 space-y-6">
      {#each questions as question, i (question.question_index)}
        <div class="border border-border rounded-lg p-4 space-y-3">
          <div class="flex items-center justify-between">
            <span class="text-sm font-medium text-foreground">Question {i + 1}</span>
            <Badge variant="outline" class="text-xs">
              {question.question_type === 'mcq' ? 'MCQ' : 'Theory'}
              &middot; {question.allocated_mark} mark{question.allocated_mark !== 1 ? 's' : ''}
            </Badge>
          </div>

          <p class="text-sm text-muted-foreground">{question.question_text}</p>

          {#if question.question_type === 'mcq'}
            <div class="space-y-2 pl-2">
              {#if question.option_a}
                <label class="flex items-center gap-3 py-2 px-3 rounded border border-border cursor-pointer hover:bg-muted/50 text-sm">
                  <input type="radio" name="mcq-{question.question_index}" value="A" bind:group={mcqAnswers[question.question_index]} class="accent-primary-500" />
                  <span>A. {question.option_a}</span>
                </label>
              {/if}
              {#if question.option_b}
                <label class="flex items-center gap-3 py-2 px-3 rounded border border-border cursor-pointer hover:bg-muted/50 text-sm">
                  <input type="radio" name="mcq-{question.question_index}" value="B" bind:group={mcqAnswers[question.question_index]} class="accent-primary-500" />
                  <span>B. {question.option_b}</span>
                </label>
              {/if}
              {#if question.option_c}
                <label class="flex items-center gap-3 py-2 px-3 rounded border border-border cursor-pointer hover:bg-muted/50 text-sm">
                  <input type="radio" name="mcq-{question.question_index}" value="C" bind:group={mcqAnswers[question.question_index]} class="accent-primary-500" />
                  <span>C. {question.option_c}</span>
                </label>
              {/if}
            </div>
          {:else}
            <textarea
              bind:value={theoryAnswers[question.question_index]}
              placeholder="Type your answer here..."
              class="w-full min-h-[100px] rounded-lg border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
            ></textarea>
          {/if}
        </div>
      {/each}
    </div>

    <Dialog.Footer>
      <Dialog.Close>Cancel</Dialog.Close>
      <AppButton onclick={handleSubmit} disabled={submitting}>{submitting ? 'Submitting...' : 'Submit'}</AppButton>
    </Dialog.Footer>
  </Dialog.Content>
</Dialog.Root>
