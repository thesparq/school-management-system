<script lang="ts">
  import * as Dialog from '$lib/components/ui/dialog/index.js';
  import { Button } from '$lib/components/ui/button';
  import { Input } from '$lib/components/ui/input';
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast';

  let { open = $bindable(false), classId, assessmentId, assessmentType = 'general', maxScore = 100 } = $props();

  let students = $state<any[]>([]);
  let submissions = $state<any[]>([]);
  let loading = $state(false);
  let submitting = $state(false);

  // local state mapping student_id -> current manual grade
  let grades = $state<Record<string, number | null>>({});

  $effect(() => {
    if (open) {
      loadData();
    }
  });

  async function loadData() {
    loading = true;
    try {
      // fetch students in class
      const stRes = await fetch(`/api/teacher/class-students?class_id=${encodeURIComponent(classId)}`);
      if (stRes.ok) {
        students = await stRes.json();
      }

      // fetch existing submissions to pre-fill grades
      const subRes = await fetch(`/api/teacher/submissions?assessment_type=${assessmentType}&assessment_id=${encodeURIComponent(assessmentId)}`);
      if (subRes.ok) {
        submissions = await subRes.json();
        const initialGrades: Record<string, number | null> = {};
        for (const sub of submissions) {
          initialGrades[sub.student_id] = sub.scored_mark;
        }
        grades = initialGrades;
      }
    } catch (e) {
      console.error(e);
    } finally {
      loading = false;
    }
  }

  async function handleSaveGrades() {
    submitting = true;
    try {
      // Build a promise list to update each changed grade
      const promises = [];
      for (const [studentId, grade] of Object.entries(grades)) {
        if (grade !== null && grade !== undefined) {
          promises.push(
            fetch('/api/teacher/manual-grade', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                student_id: studentId,
                assessment_type: assessmentType,
                assessment_id: assessmentId,
                score: grade
              })
            }).then(r => {
              if (!r.ok) throw new Error(`Failed to save for student ${studentId}`);
            })
          );
        }
      }

      await Promise.all(promises);
      addToast({ type: 'success', message: 'Manual grades saved successfully.' });
      open = false;
    } catch (e: any) {
      addToast({ type: 'error', message: e.message || 'Error saving grades' });
    } finally {
      submitting = false;
    }
  }
</script>

<Dialog.Root bind:open={open}>
  <Dialog.Content class="sm:max-w-3xl max-h-[85vh] overflow-y-auto">
    <Dialog.Header>
      <Dialog.Title>Enter Manual Grades</Dialog.Title>
      <Dialog.Description>
        Input offline or manual test scores. The maximum allowable score depends on your CA configuration (usually over 100 for percentage weight).
      </Dialog.Description>
    </Dialog.Header>

    <div class="py-4 space-y-4">
      {#if loading}
        <div class="py-8 text-center text-slate-500">Loading students...</div>
      {:else if students.length === 0}
        <div class="py-8 text-center text-slate-500">No students found in this class.</div>
      {:else}
        <div class="rounded-xl border border-slate-200 overflow-hidden">
          <table class="w-full text-sm text-left">
            <thead class="bg-slate-50 border-b border-slate-200">
              <tr>
                <th class="px-4 py-3 font-semibold text-slate-900">Student Name</th>
                <th class="px-4 py-3 font-semibold text-slate-900 w-48">Score</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
              {#each students as student}
                <tr class="hover:bg-slate-50/50">
                  <td class="px-4 py-3 font-medium text-slate-900">
                    {student.surname}, {student.first_name} {student.middle_name || ''}
                  </td>
                  <td class="px-4 py-2">
                    <Input 
                      type="number" 
                      min="0" 
                      max={maxScore}
                      step="0.1"
                      placeholder="0"
                      class="h-8"
                      bind:value={grades[student.id]} 
                    />
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    </div>

    <Dialog.Footer>
      <Button variant="outline" onclick={() => open = false} disabled={submitting}>Cancel</Button>
      <Button onclick={handleSaveGrades} disabled={submitting || loading}>
        {submitting ? 'Saving...' : 'Save Grades'}
      </Button>
    </Dialog.Footer>
  </Dialog.Content>
</Dialog.Root>
