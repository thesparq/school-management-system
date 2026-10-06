<script lang="ts">
  import { onMount } from 'svelte';
  import { Card, CardHeader, CardTitle, CardContent } from '$lib/components/ui/card';
  import AppButton from '$lib/components/ui/app-button.svelte';
  import * as Dialog from '$lib/components/ui/dialog/index.js';
  import { Input } from '$lib/components/ui/input/index.js';
  import { Label } from '$lib/components/ui/label/index.js';
  import { addToast } from '$lib/stores/toast';
  import ManualGradeModal from './ManualGradeModal.svelte';

  let { termId, subjectId, classId, lessons } = $props();

  let assessments = $state<any[]>([]);
  let percentageSummary = $state<{current: number, remaining: number}>({ current: 0, remaining: 100 });
  let loading = $state(true);

  let createModalOpen = $state(false);
  let creating = $state(false);
  let caTitle = $state('');
  let caWeight = $state<number | undefined>(undefined);
  
  // For compositional CA
  let allLessonAssessments = $state<any[]>([]);
  let selectedCompositions = $state<Record<string, number>>({}); // assessment_id -> weight

  let gradingModalOpen = $state(false);
  let gradingAssessmentId = $state('');
  let gradingMaxScore = $state(100);

  onMount(() => {
    loadData();
  });

  async function loadData() {
    loading = true;
    try {
      const p1 = fetch(`/api/teacher/general-assessments?session_term_id=${termId}&subject_id=${subjectId}`).then(r => r.json());
      const p2 = fetch(`/api/teacher/assessment-percentage-summary?session_term_id=${termId}&subject_id=${subjectId}`).then(r => r.json());
      
      // Load all lesson assessments for this term to allow composition
      const promises = lessons.map((l: any) => 
        fetch(`/api/teacher/lesson-assessments?lesson_id=${l.id}`).then(r => r.json())
      );
      
      const [genRes, sumRes, ...lessonRes] = await Promise.all([p1, p2, ...promises]);
      
      assessments = genRes.data || [];
      percentageSummary = sumRes.data || { current: 0, remaining: 100 };
      
      let allL = [];
      for (const res of lessonRes) {
        if (res.data) allL.push(...res.data);
      }
      allLessonAssessments = allL;
      
    } catch (e) {
      console.error(e);
      addToast('error', 'Error', 'Failed to load assessments');
    } finally {
      loading = false;
    }
  }

  function toggleComposition(id: string) {
    const next = { ...selectedCompositions };
    if (next[id] !== undefined) {
      delete next[id];
    } else {
      next[id] = 100; // default 100% of this assessment's value
    }
    selectedCompositions = next;
  }

  async function handleCreate() {
    if (!caTitle.trim() || !caWeight) return;
    if (caWeight > percentageSummary.remaining) {
      addToast('error', 'Weight Exceeded', `Cannot exceed remaining ${percentageSummary.remaining}%`);
      return;
    }

    creating = true;
    const compositions = Object.entries(selectedCompositions).map(([id, weight]) => ({
      lesson_assessment: id,
      weight_pct: weight
    }));

    if (compositions.length > 0) {
      const sum = compositions.reduce((acc, curr) => acc + curr.weight_pct, 0);
      if (sum !== 100) {
        addToast('error', 'Invalid Weights', 'The relative weights of selected lesson assessments must sum to exactly 100%. Currently: ' + sum + '%');
        return;
      }
    }

    try {
      const res = await fetch('/api/teacher/create-general-assessment', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          session_term_id: termId,
          subject_id: subjectId,
          title: caTitle.trim(),
          percentage_weight: caWeight,
          compositions
        })
      });

      if (!res.ok) throw new Error(await res.text());
      addToast('success', 'Created', 'CA created successfully');
      createModalOpen = false;
      caTitle = '';
      caWeight = undefined;
      selectedCompositions = {};
      await loadData();
    } catch (e: any) {
      addToast('error', 'Failed', e.message);
    } finally {
      creating = false;
    }
  }
</script>

<div class="space-y-6 mt-6">
  <div class="grid grid-cols-2 gap-4">
    <Card class="bg-blue-50 border-blue-100">
      <CardContent class="p-6">
        <p class="text-sm font-medium text-blue-800">Allocated Weight</p>
        <p class="text-3xl font-bold text-blue-900">{percentageSummary.current}%</p>
      </CardContent>
    </Card>
    <Card class="bg-emerald-50 border-emerald-100">
      <CardContent class="p-6">
        <p class="text-sm font-medium text-emerald-800">Remaining Weight</p>
        <p class="text-3xl font-bold text-emerald-900">{percentageSummary.remaining}%</p>
      </CardContent>
    </Card>
  </div>

  <div class="flex justify-between items-center">
    <h2 class="text-xl font-bold">Continuous Assessments & Exams</h2>
    <AppButton onclick={() => createModalOpen = true}>+ Create CA/Exam</AppButton>
  </div>

  {#if loading}
    <p class="text-sm text-muted-foreground">Loading...</p>
  {:else if assessments.length === 0}
    <div class="p-8 text-center border rounded-xl bg-surface-50">
      <p class="text-surface-500">No CAs or Exams created yet.</p>
    </div>
  {:else}
    <div class="space-y-3">
      {#each assessments as a}
        <Card>
          <CardContent class="p-4 flex justify-between items-center">
            <div>
              <h3 class="font-bold text-lg">{a.title}</h3>
              <p class="text-sm text-muted-foreground">
                {#if a.compositions && a.compositions.length > 0}
                  Composed of {a.compositions.length} lesson assessments
                {:else}
                  Direct Assessment
                {/if}
              </p>
            </div>
            <div class="text-right flex items-center justify-end gap-2">
              <Button variant="outline" size="sm" onclick={() => { gradingAssessmentId = a.id; gradingMaxScore = a.percentage_weight; gradingModalOpen = true; }}>
                Grade Manually
              </Button>
              <span class="inline-flex items-center justify-center bg-primary-100 text-primary-800 text-xs font-bold px-2.5 py-0.5 rounded-full">
                {a.percentage_weight}% Weight
              </span>
            </div>
          </CardContent>
        </Card>
      {/each}
    </div>
  {/if}

  <Dialog.Root bind:open={createModalOpen}>
    <Dialog.Content class="sm:max-w-2xl max-h-[85vh] overflow-y-auto">
      <Dialog.Header>
        <Dialog.Title>Create Continuous Assessment (CA)</Dialog.Title>
        <Dialog.Description>
          Define the weight out of the total 100% for the term.
        </Dialog.Description>
      </Dialog.Header>

      <div class="space-y-6 py-4">
        <div class="grid grid-cols-4 gap-4">
          <div class="col-span-3 space-y-2">
            <Label>Title</Label>
            <Input bind:value={caTitle} placeholder="e.g. First CA Test" />
          </div>
          <div class="space-y-2">
            <Label>Weight (%)</Label>
            <Input type="number" min="1" max={percentageSummary.remaining} bind:value={caWeight} />
            <p class="text-xs text-muted-foreground text-right">Max: {percentageSummary.remaining}%</p>
          </div>
        </div>

        <div class="pt-4 border-t border-border">
          <h3 class="text-sm font-semibold mb-3">Compose from Lesson Assessments (Optional)</h3>
          <p class="text-xs text-muted-foreground mb-4">
            Select existing lesson assessments to automatically combine them into this CA.
            The system will normalize the scores to fit the {caWeight || 0}% weight.
          </p>

          {#if allLessonAssessments.length === 0}
            <p class="text-sm text-amber-600 bg-amber-50 p-3 rounded">No lesson assessments found in this term.</p>
          {:else}
            <div class="space-y-2">
              {#each allLessonAssessments as la}
                <div class="flex items-center gap-3 p-3 border rounded hover:bg-surface-50">
                  <input type="checkbox" class="w-4 h-4" checked={selectedCompositions[la.id] !== undefined} onchange={() => toggleComposition(la.id)} />
                  <div class="flex-1">
                    <p class="text-sm font-medium">{la.title}</p>
                  </div>
                  {#if selectedCompositions[la.id] !== undefined}
                    <div class="flex items-center gap-2">
                      <Label class="text-xs">Relative Weight (%)</Label>
                      <Input type="number" min="1" max="100" class="w-16 h-8 text-xs" bind:value={selectedCompositions[la.id]} />
                    </div>
                  {/if}
                </div>
              {/each}
            </div>
          {/if}
        </div>
      </div>

      <Dialog.Footer>
        <Dialog.Close>Cancel</Dialog.Close>
        <AppButton disabled={!caTitle.trim() || !caWeight || creating} onclick={handleCreate}>
          {creating ? 'Creating...' : 'Create CA'}
        </AppButton>
      </Dialog.Footer>
    </Dialog.Content>
  </Dialog.Root>
</div>

  {#if gradingModalOpen}
    <ManualGradeModal 
      bind:open={gradingModalOpen} 
      classId={classId} 
      assessmentId={gradingAssessmentId} 
      assessmentType="general" 
      maxScore={gradingMaxScore} 
    />
  {/if}
