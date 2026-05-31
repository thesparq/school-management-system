<script lang="ts">
  import type { PageData } from './$types';
  import { Card, CardHeader, CardTitle } from '$lib/components/ui/card';
  import { Alert, AlertTitle, AlertDescription, AlertAction } from '$lib/components/ui/alert';
  import { Skeleton } from '$lib/components/ui/skeleton';
  import { Button } from '$lib/components/ui/button';
  import { page, navigating } from '$app/stores';
  import { goto } from '$app/navigation';

  let { data }: { data: PageData } = $props();
</script>

<div class="mx-auto max-w-6xl space-y-6">
  <h1 class="text-2xl font-display font-bold text-primary-700">{data.classLevelName}</h1>

  {#if $navigating && (!data.subjects || data.subjects.length === 0)}
    <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      {#each Array(6) as _}
        <Skeleton class="h-28" />
      {/each}
    </div>
  {:else if data.subjectsError}
    <Alert variant="destructive">
      <AlertTitle>Failed to load subjects</AlertTitle>
      <AlertDescription>{data.subjectsError}</AlertDescription>
      <AlertAction>
        <Button variant="outline" onclick={() => goto('/my-classes/' + $page.params.classId)}>Retry</Button>
      </AlertAction>
    </Alert>
  {:else if data.subjects.length === 0}
    <div class="mx-auto max-w-lg py-16 text-center space-y-6">
      <div class="rounded-full bg-secondary-100 dark:bg-secondary-900/20 mx-auto w-fit p-4">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8 text-secondary-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <circle cx="12" cy="12" r="10" />
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 16v-4m0-4h.01" />
        </svg>
      </div>
      <h2 class="text-xl font-semibold text-surface-800">No Subjects Available</h2>
      <p class="text-surface-700">No subjects have been assigned for this class.</p>
    </div>
  {:else}
    <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      {#each data.subjects as subject (subject.subject_id)}
        <a href="/my-classes/{$page.params.classId}/{subject.subject_id}">
          <Card class="hover:bg-primary-50 dark:hover:bg-primary-950/30 hover:ring-primary-200 dark:hover:ring-primary-700 transition cursor-pointer">
            <CardHeader class="pb-0 min-h-[4.5rem]">
              <CardTitle class="flex flex-wrap items-center gap-x-2 gap-y-1 font-display text-base text-primary-700 dark:text-primary-300">
                <span class="truncate">{subject.subject_name}</span>
                {#if subject.subject_code}
                  <span class="rounded bg-primary-100 dark:bg-primary-900/40 px-1.5 py-0.5 text-xs font-mono text-primary-600 dark:text-primary-400 shrink-0">{subject.subject_code}</span>
                {/if}
              </CardTitle>
            </CardHeader>
          </Card>
        </a>
      {/each}
    </div>
  {/if}
</div>
