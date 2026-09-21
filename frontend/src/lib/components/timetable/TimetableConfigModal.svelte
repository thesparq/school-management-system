<script lang="ts">
  let { isOpen = false, onClose = () => {}, onSaved = () => {}, timetableId = '', timetableName = '', dayConfigs = [] }: { isOpen?: boolean, onClose?: () => void, onSaved?: () => void, timetableId?: string, timetableName?: string, dayConfigs?: any[] } = $props();
  import { Button } from '$lib/components/ui/button';
  import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '$lib/components/ui/dialog';
  import { Label } from '$lib/components/ui/label';
  
        
        
  let loading = $state(false);
  let activeTab: 'structure' | 'staff' | 'overrides' = 'structure';

  const DEFAULT_DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
  
  // Clone day configs so we can edit them
  let currentConfigs = DEFAULT_DAYS.map(day => {
    const existing = dayConfigs.find(c => c.day_of_week === day);
    if (existing) return { ...existing };
    return {
      day_of_week: day,
      periods_count: day === 'Friday' ? 6 : 7,
      excluded_periods: day === 'Friday' ? [6] : []
    };
  });

  async function handleSaveStructure() {
    loading = true;
    try {
      const res = await fetch(`/api/admin/timetables/config`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ timetable_id: timetableId, day_configs: currentConfigs })
      });
      if (!res.ok) throw new Error(await res.text());
      onSaved();
      onClose();
    } catch (err: any) {
      alert(`Failed to save configs: ${err.message}`);
    } finally {
      loading = false;
    }
  }

  function toggleExcluded(day: string, period: number) {
    currentConfigs = currentConfigs.map(c => {
      if (c.day_of_week === day) {
        if (c.excluded_periods.includes(period)) {
          return { ...c, excluded_periods: c.excluded_periods.filter((p: number) => p !== period) };
        } else {
          return { ...c, excluded_periods: [...c.excluded_periods, period].sort() };
        }
      }
      return c;
    });
  }
</script>

<Dialog bind:open={isOpen} onOpenChange={(v) => !v && onClose()}>
  <DialogContent class="sm:max-w-[700px] h-[80vh] flex flex-col">
    <DialogHeader>
      <DialogTitle>Configure: {timetableName}</DialogTitle>
      <DialogDescription>
        Adjust day periods, exclude specific slots, and manage overrides.
      </DialogDescription>
    </DialogHeader>

    <div class="flex border-b border-border mt-2">
      <button class="px-4 py-2 border-b-2 {activeTab === 'structure' ? 'border-primary font-bold' : 'border-transparent text-muted-foreground'}" onclick={() => activeTab = 'structure'}>Structure</button>
      <button class="px-4 py-2 border-b-2 {activeTab === 'staff' ? 'border-primary font-bold' : 'border-transparent text-muted-foreground'}" onclick={() => activeTab = 'staff'}>Staff Absences</button>
      <button class="px-4 py-2 border-b-2 {activeTab === 'overrides' ? 'border-primary font-bold' : 'border-transparent text-muted-foreground'}" onclick={() => activeTab = 'overrides'}>Subject Overrides</button>
    </div>

    <div class="flex-1 overflow-y-auto py-4">
      {#if activeTab === 'structure'}
        <div class="space-y-6">
          {#each currentConfigs as config}
            <div class="flex flex-col space-y-3 p-4 bg-muted/50 rounded-xl border border-border">
              <div class="flex justify-between items-center">
                <span class="font-bold">{config.day_of_week}</span>
                <div class="flex items-center space-x-2">
                  <Label>Periods:</Label>
                  <input type="number" min="1" max="12" class="w-16 px-2 py-1 border rounded" bind:value={config.periods_count} />
                </div>
              </div>
              <div class="flex flex-wrap gap-2">
                {#each Array(config.periods_count).fill(0).map((_, i) => i + 1) as p}
                  <button 
                    onclick={() => toggleExcluded(config.day_of_week, p)}
                    class="px-2.5 py-1 text-xs font-bold rounded border {config.excluded_periods.includes(p) ? 'bg-amber-100 text-amber-800 border-amber-300' : 'bg-white text-slate-600 border-slate-300'}"
                  >
                    P{p}
                  </button>
                {/each}
              </div>
            </div>
          {/each}
        </div>
      {:else if activeTab === 'staff'}
        <div class="text-muted-foreground italic">Staff absence toggles will be loaded here.</div>
      {:else}
        <div class="text-muted-foreground italic">Subject assignment overrides will be loaded here.</div>
      {/if}
    </div>

    <DialogFooter class="mt-auto pt-4 border-t border-border">
      <Button variant="outline" onclick={onClose}>Cancel</Button>
      <Button onclick={handleSaveStructure} disabled={loading}>
        {loading ? 'Saving...' : 'Save Configuration'}
      </Button>
    </DialogFooter>
  </DialogContent>
</Dialog>
