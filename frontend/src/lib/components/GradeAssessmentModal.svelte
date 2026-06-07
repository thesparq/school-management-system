<script lang="ts">
  import type { SubmissionInfo } from '$lib/types';
  import * as Dialog from '$lib/components/ui/dialog/index.js';
  import { Input } from '$lib/components/ui/input/index.js';
  import { Label } from '$lib/components/ui/label/index.js';
  import { Badge } from '$lib/components/ui/badge';
  import AppButton from '$lib/components/ui/app-button.svelte';
  import { addToast } from '$lib/stores/toast';

  let { open, submission, onGradeComplete }: {
    open: boolean;
    submission: SubmissionInfo;
    onGradeComplete: () => void;
  } = $props();

  let saving = $state(false);
  let theoryScores: Record<number, string> = $state({});

  $effect(() => {
    if (open) {
      theoryScores = {};
      for (const a of submission.answers) {
        if (a.answer_type === 'theory') {
          theoryScores[a.question_index] = a.scored_mark != null ? String(a.scored_mark) : '';
        }
      }
    }
  });

  function getQuestionText(index: number): string {
    const a = submission.answers.find(a => a.question_index === index);
    return a?.answer_text ?? '';
  }

  async function handleSave() {
    saving = true;
    const gradedAnswers = submission.answers.map(a => {
      if (a.answer_type === 'theory') {
        const scoreStr = theoryScores[a.question_index] ?? '';
        const score = parseInt(scoreStr, 10);
        return {
          question_index: a.question_index,
          answer_type: a.answer_type,
          answer_text: a.answer_text,
          allocated_mark: a.allocated_mark,
          scored_mark: isNaN(score) ? null : Math.min(score, a.allocated_mark),
        };
      }
      return {
        question_index: a.question_index,
        answer_type: a.answer_type,
        answer_text: a.answer_text,
        allocated_mark: a.allocated_mark,
        scored_mark: a.scored_mark,
        correct: a.correct,
      };
    });

    try {
      const res = await fetch('/api/teacher/grade-submission', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ submission_id: submission.id, answers: gradedAnswers }),
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: { message: 'Failed to save grades' } }));
        throw new Error(err.error?.message ?? 'Failed to save grades');
      }
      addToast('success', 'Grades saved', `Graded ${submission.student_name ?? 'student'}'s submission.`);
      onGradeComplete();
    } catch (e) {
      addToast('error', 'Failed to save grades', e instanceof Error ? e.message : 'Unknown error');
    } finally {
      saving = false;
    }
  }
</script>

<Dialog.Root bind:open>
  <Dialog.Content class="sm:max-w-3xl max-h-[92vh] flex flex-col">
    <Dialog.Header>
      <Dialog.Title>Grade Submission</Dialog.Title>
      <Dialog.Description>
        {submission.student_name ?? 'Student'} &middot; Iteration {submission.iteration}
        &middot; Submitted {new Date(submission.submitted_at).toLocaleDateString()}
      </Dialog.Description>
    </Dialog.Header>

    <div class="flex-1 overflow-y-auto px-0.5 py-6 space-y-6">
      {#each submission.answers as answer (answer.question_index)}
        <div class="border border-border rounded-lg p-4 space-y-3">
          <div class="flex items-center justify-between">
            <span class="text-sm font-medium text-foreground">Question {answer.question_index + 1}</span>
            <Badge variant="outline" class="text-xs">
              {answer.answer_type === 'mcq' ? 'MCQ' : 'Theory'}
              &middot; {answer.allocated_mark} mark{answer.allocated_mark !== 1 ? 's' : ''}
            </Badge>
          </div>

          <p class="text-sm text-muted-foreground whitespace-pre-wrap">{getQuestionText(answer.question_index)}</p>

          {#if answer.answer_type === 'mcq'}
            <div class="flex items-center gap-3 text-sm">
              <span class="font-medium text-muted-foreground">Selected:</span>
              <span class="text-foreground">{answer.answer_text}</span>
              {#if answer.correct === true}
                <Badge class="bg-success-100 text-success-700 text-xs">Correct</Badge>
              {:else if answer.correct === false}
                <Badge variant="destructive" class="text-xs">Incorrect</Badge>
              {:else}
                <Badge variant="outline" class="text-xs">Not auto-graded</Badge>
              {/if}
            </div>
            <div class="text-sm text-muted-foreground">
              Score: <span class="font-medium text-foreground">{answer.scored_mark ?? '-'} / {answer.allocated_mark}</span>
            </div>
          {:else}
            <div class="space-y-2">
              <Label for="theory-score-{answer.question_index}">Score (max {answer.allocated_mark})</Label>
              <Input
                id="theory-score-{answer.question_index}"
                type="number"
                min="0"
                max={answer.allocated_mark}
                bind:value={theoryScores[answer.question_index]}
                placeholder="Enter score"
              />
            </div>
          {/if}
        </div>
      {/each}
    </div>

    <Dialog.Footer>
      <Dialog.Close>Cancel</Dialog.Close>
      <AppButton onclick={handleSave} disabled={saving}>{saving ? 'Saving...' : 'Save Grades'}</AppButton>
    </Dialog.Footer>
  </Dialog.Content>
</Dialog.Root>
