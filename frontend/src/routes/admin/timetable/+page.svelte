<script lang="ts">
  import { invalidateAll } from '$app/navigation';
  import { Button } from '$lib/components/ui/button';
  import { onMount } from 'svelte';
  
  let isGenerating = false;
  
  async function handleGenerateTimetable() {
    isGenerating = true;
    try {
      const response = await fetch('/api/admin/generate-timetable', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ timetable_id: 'default-timetable' })
      });
      const data = await response.json();
      console.log('Generate result:', data);
      await invalidateAll();
    } catch (e) {
      console.error('Failed to generate timetable', e);
    } finally {
      isGenerating = false;
    }
  }
</script>

<div class="flex flex-col h-full space-y-6">
  <!-- Header -->
  <div class="flex flex-col sm:flex-row justify-between items-start sm:items-end space-y-4 sm:space-y-0">
    <div>
      <div class="flex items-center space-x-2 mb-1.5 text-primary">
        <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M13 10V3L4 14h7v7l9-11h-7z" />
        </svg>
        <span class="font-black text-xs tracking-widest uppercase">Self-Healing Constraint Engine</span>
      </div>
      <h1 class="text-3xl font-black text-foreground tracking-tight">Curriculum Dashboard</h1>
      <p class="text-muted-foreground mt-1 text-sm font-medium">
        Multi-timetable allocation matrix with automated workload balancing, term staff scopes, and pairing diagnostics.
      </p>
    </div>
    <div class="flex space-x-3">
      <Button variant="outline">Configure Constraints</Button>
      <Button onclick={handleGenerateTimetable} disabled={isGenerating}>
        {isGenerating ? 'Generating...' : 'Generate Constraints'}
      </Button>
    </div>
  </div>
  
  <!-- Stats Row -->
  <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-2">
    <div class="bg-card p-5 rounded-2xl border border-border shadow-sm flex items-center space-x-4">
      <div class="w-12 h-12 bg-blue-50 text-blue-700 rounded-xl flex items-center justify-center border border-blue-100 shadow-xs">
        <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
        </svg>
      </div>
      <div>
        <p class="text-2xl font-black text-foreground">Dynamic</p>
        <p class="text-[11px] font-bold text-muted-foreground uppercase tracking-wider">Per-Day Period Allocation</p>
      </div>
    </div>
    
    <div class="bg-card p-5 rounded-2xl border border-border shadow-sm flex items-center space-x-4">
      <div class="w-12 h-12 bg-emerald-50 text-emerald-700 rounded-xl flex items-center justify-center border border-emerald-100 shadow-xs">
        <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
      </div>
      <div>
        <p class="text-2xl font-black text-foreground">100%</p>
        <p class="text-[11px] font-bold text-muted-foreground uppercase tracking-wider">Deterministic Solved</p>
      </div>
    </div>
    
    <div class="bg-card p-5 rounded-2xl border border-border shadow-sm flex items-center space-x-4">
      <div class="w-12 h-12 bg-purple-50 text-purple-700 rounded-xl flex items-center justify-center border border-purple-100 shadow-xs">
        <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
        </svg>
      </div>
      <div>
        <p class="text-2xl font-black text-foreground">Hybrid</p>
        <p class="text-[11px] font-bold text-muted-foreground uppercase tracking-wider">Master + Scope Overrides</p>
      </div>
    </div>
  </div>

  <div class="p-8 border border-dashed rounded-lg flex items-center justify-center text-muted-foreground font-medium">
    Timetable Grid will be loaded here.
  </div>
</div>
