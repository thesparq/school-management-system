<script lang="ts">
  import { onMount } from 'svelte';
  import { Card, CardHeader, CardTitle, CardContent } from '$lib/components/ui/card';
  import { Badge } from '$lib/components/ui/badge';
  import { addToast } from '$lib/stores/toast';

  let { termId, subjectId, lessons } = $props();

  let generalAssessments = $state<any[]>([]);
  let lessonAssessmentsMap = $state<Record<string, any[]>>({}); // lesson_id -> assessments
  let grades = $state<Record<string, any>>({}); // assessment_id -> submission
  
  let loading = $state(true);

  onMount(() => {
    loadData();
  });

  async function loadData() {
    loading = true;
    try {
      // 1. Fetch general assessments
      const genRes = await fetch(`/api/student/general-assessments?session_term_id=${termId}&subject_id=${subjectId}`).then(r => r.json()).catch(() => ({data: []}));
      generalAssessments = genRes.data || [];

      // 2. Fetch lesson assessments
      const lessonPromises = lessons.map((l: any) => 
        fetch(`/api/student/assessments?lesson_id=${l.id}`)
          .then(r => r.json())
          .then(json => ({ id: l.id, data: json.data || [] }))
          .catch(() => ({ id: l.id, data: [] }))
      );
      const lessonResults = await Promise.all(lessonPromises);
      
      const newMap: Record<string, any[]> = {};
      const gradePromises: Promise<any>[] = [];
      
      for (const res of lessonResults) {
        newMap[res.id] = res.data;
        for (const a of res.data) {
          gradePromises.push(
            fetch(`/api/student/my-grades?assessment_type=lesson&assessment_id=${a.id}`)
              .then(r => r.json())
              .then(g => ({ type: 'lesson', id: a.id, submission: g.data }))
              .catch(() => ({ type: 'lesson', id: a.id, submission: null }))
          );
        }
      }
      lessonAssessmentsMap = newMap;

      // 3. Fetch grades for general assessments
      for (const ga of generalAssessments) {
        gradePromises.push(
          fetch(`/api/student/my-grades?assessment_type=general&assessment_id=${ga.id}`)
            .then(r => r.json())
            .then(g => ({ type: 'general', id: ga.id, submission: g.data }))
            .catch(() => ({ type: 'general', id: ga.id, submission: null }))
        );
      }

      // Resolve all grades
      const gradeResults = await Promise.all(gradePromises);
      const nextGrades: Record<string, any> = {};
      for (const g of gradeResults) {
        if (g.submission) {
          nextGrades[g.id] = g.submission;
        }
      }
      grades = nextGrades;

    } catch (e) {
      console.error(e);
      addToast('error', 'Error', 'Failed to load grades dashboard');
    } finally {
      loading = false;
    }
  }
</script>

<div class="space-y-8 mt-6">
  
  <!-- General Assessments (CAs / Exams) -->
  <section class="space-y-4">
    <h2 class="text-xl font-bold border-b pb-2">Continuous Assessments & Exams</h2>
    {#if loading}
      <p class="text-sm text-muted-foreground">Loading CAs...</p>
    {:else if generalAssessments.length === 0}
      <div class="p-6 text-center border rounded-xl bg-surface-50">
        <p class="text-surface-500">No CAs or Exams found for this term.</p>
      </div>
    {:else}
      <div class="space-y-3">
        {#each generalAssessments as ga}
          {@const sub = grades[ga.id]}
          <Card>
            <CardContent class="p-4 flex items-center justify-between">
              <div>
                <h3 class="font-bold text-lg">{ga.title}</h3>
                <p class="text-sm text-muted-foreground">{ga.percentage_weight}% of Total Grade</p>
              </div>
              <div class="text-right">
                {#if sub && sub.grade_released_at}
                  <div class="flex flex-col items-end">
                    <span class="text-2xl font-bold text-success-700">{sub.scored_mark}/{sub.total_mark}</span>
                    <Badge class="bg-success-100 text-success-800">Graded</Badge>
                  </div>
                {:else if sub && sub.status === 'submitted'}
                  <Badge variant="outline" class="text-amber-600 border-amber-200 bg-amber-50">Awaiting Grade</Badge>
                {:else}
                  <Badge variant="outline" class="text-surface-500">Not Taken</Badge>
                  {#if !ga.compositions || ga.compositions.length === 0}
                    <AppButton variant="outline" size="sm" class="mt-2" href="/lms/{subjectId}/{termId}/assessment/{ga.id}">Take Exam</AppButton>
                  {/if}
                {/if}
              </div>
            </CardContent>
          </Card>
        {/each}
      </div>
    {/if}
  </section>

  <!-- Lesson Assessments -->
  <section class="space-y-4">
    <h2 class="text-xl font-bold border-b pb-2">Lesson Assessments</h2>
    {#if loading}
      <p class="text-sm text-muted-foreground">Loading lesson grades...</p>
    {:else}
      <div class="space-y-6">
        {#each lessons as lesson}
          {@const lAssessments = lessonAssessmentsMap[lesson.id] || []}
          {#if lAssessments.length > 0}
            <div class="space-y-2">
              <h3 class="font-semibold text-primary-700">Week {lesson.week}: {lesson.topic_title}</h3>
              <div class="grid gap-3 sm:grid-cols-2">
                {#each lAssessments as la}
                  {@const lSub = grades[la.id]}
                  <div class="border rounded-lg p-3 bg-white flex justify-between items-center shadow-sm">
                    <span class="text-sm font-medium">{la.title}</span>
                    <div>
                      {#if lSub && lSub.grade_released_at}
                        <Badge class="bg-success-100 text-success-700">{lSub.scored_mark}/{lSub.total_mark}</Badge>
                      {:else if lSub && lSub.status === 'submitted'}
                        <Badge variant="outline" class="text-amber-600 bg-amber-50">Pending</Badge>
                      {:else}
                        <Badge variant="outline" class="text-surface-500">Missed</Badge>
                      {/if}
                    </div>
                  </div>
                {/each}
              </div>
            </div>
          {/if}
        {/each}
        
        {#if Object.values(lessonAssessmentsMap).every(arr => arr.length === 0)}
          <div class="p-6 text-center border rounded-xl bg-surface-50">
            <p class="text-surface-500">No lesson assessments found.</p>
          </div>
        {/if}
      </div>
    {/if}
  </section>

</div>
