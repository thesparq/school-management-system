<script lang="ts">
  import CurriculumSkeleton from '$lib/components/timetable/CurriculumSkeleton.svelte';
  import CurriculumManager from '$lib/components/timetable/CurriculumManager.svelte';
  import PageHeader from '$lib/components/PageHeader.svelte';

  let { data }: { data: import('./$types').PageData } = $props();
	let loadError = $state(data.loadError || '');
</script>

<div class="space-y-6">
  <PageHeader title="Curriculum Planner" />
  <p class="text-muted-foreground mt-1 text-sm font-medium -mt-2">
    Manage subjects, cohorts, class curriculums, and master teacher qualifications.
  </p>

  
  {#await data.streamed.plannerDataRes}
    <div class="flex-1 w-full flex flex-col">
      <CurriculumSkeleton />
    </div>
  {:then plannerData}
    <CurriculumManager {data} plannerData={plannerData} />
  {:catch error}
    <div class="p-6 bg-destructive/10 text-destructive rounded-xl border border-destructive/20">
      <h3 class="font-semibold text-lg mb-2">Failed to load curriculum data</h3>
      <p>{error.message}</p>
    </div>
  {/await}

</div>
