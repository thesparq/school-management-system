<script lang="ts">
  import type { PageData } from './$types';
  import type { Term } from '$lib/types';
  import { Card, CardHeader, CardTitle } from '$lib/components/ui/card';
  import { Switch } from '$lib/components/ui/switch/index.js';
  import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
  import { Skeleton } from '$lib/components/ui/skeleton';
  import { page, navigating } from '$app/stores';
  import { goto } from '$app/navigation';
  import { addToast } from '$lib/stores/toast';

	let { data }: { data: PageData } = $props();

	let termsSource = $derived(data.terms);
	let terms = $state<Term[]>(termsSource);

	$effect(() => {
		terms = termsSource;
	});

	function visibleLabel(active: boolean): string {
    return active ? 'Visible to students' : 'Hidden from students';
  }

  async function handleToggleTerm(termId: string, newActive: boolean) {
    const idx = terms.findIndex(t => t.id === termId);
    if (idx === -1) return;
    const prev = terms[idx].active;
    terms[idx].active = newActive;
    terms = [...terms];

    try {
      const res = await fetch('/api/teacher/toggle-term', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ term_id: termId, active: newActive }),
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: { message: 'Request failed' } }));
        throw new Error(err.error?.message ?? 'Request failed');
      }
      addToast('success', 'Term updated', `${terms[idx].name} is now ${newActive ? 'visible' : 'hidden'} to students.`);
    } catch (e) {
      terms[idx].active = prev;
      terms = [...terms];
      addToast('error', 'Failed to update term', e instanceof Error ? e.message : 'Unknown error');
    }
  }
</script>

<div class="mx-auto max-w-4xl space-y-6">
  <h1 class="text-2xl font-display font-bold text-primary-700">{data.subjectName}</h1>

  {#if $navigating && (!terms || terms.length === 0)}
    <div class="flex gap-4 flex-wrap">
      {#each Array(3) as _}
        <Skeleton class="h-28 w-48" />
      {/each}
    </div>
  {:else if data.termsError}
    <StatusCard variant="error" title="Failed to load terms" description={data.termsError} onRetry={() => goto('/my-classes/' + $page.params.classId + '/' + $page.params.subjectId)} />
  {:else if terms.length === 0}
    <StatusCard variant="info" title="No Terms Available" description="No terms are available for this subject yet." />
  {:else}
    <div class="flex gap-4 flex-wrap">
      {#each terms as term (term.id)}
        <div class="flex flex-col">
          <a href="/my-classes/{$page.params.classId}/{$page.params.subjectId}/{term.id}">
            <Card class="w-48 hover:bg-primary-50 dark:hover:bg-primary-950/30 hover:ring-primary-200 dark:hover:ring-primary-700 transition cursor-pointer">
              <CardHeader class="pb-2">
                <CardTitle class="font-display text-base text-primary-700 dark:text-primary-300">{term.name}</CardTitle>
              </CardHeader>
            </Card>
          </a>
          <div class="flex items-center gap-2 mt-2 pl-1">
            <Switch
              checked={term.active}
              onCheckedChange={(checked) => handleToggleTerm(term.id, checked)}
            />
            <span
              class="text-xs"
              class:text-surface-500={term.active}
              class:text-amber-600={!term.active}
            >
              {visibleLabel(term.active)}
            </span>
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>
