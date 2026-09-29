<script lang="ts">
  let { isOpen = false, onClose = () => {}, onSaved = () => {}, timetableId = '', timetableName = '', sessionTerm = '', dayConfigs = [] }: { isOpen?: boolean, onClose?: () => void, onSaved?: () => void, timetableId?: string, timetableName?: string, sessionTerm?: string, dayConfigs?: any[] } = $props();
  import { Button } from '$lib/components/ui/button';
  import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '$lib/components/ui/dialog';
  import { Label } from '$lib/components/ui/label';
  
        
        
  let loading = $state(false);
  let activeTab: 'structure' | 'staff' | 'overrides' = $state('structure');

  
  let loadingStaffData = $state(false);
  let staffData: any = $state(null);
  
  let loadingOverrides = $state(false);
  let overrides: any[] = $state([]);

  async function fetchStaffData() {
    if (!sessionTerm) return;
    loadingStaffData = true;
    try {
      const res = await fetch(`/api/admin/timetable/staff-data?session_term=${sessionTerm}`);
      if (!res.ok) throw new Error(await res.text());
      const json = await res.json();
      staffData = json.data;
    } catch (err: any) {
      console.error('Failed to fetch staff data:', err);
    } finally {
      loadingStaffData = false;
    }
  }

  async function fetchOverrides() {
    if (!timetableId) return;
    loadingOverrides = true;
    try {
      const res = await fetch(`/api/admin/timetable/overrides?timetable_id=${timetableId}`);
      if (!res.ok) throw new Error(await res.text());
      const json = await res.json();
      overrides = json.data || [];
      overridesFetched = true;
    } catch (err: any) {
      console.error('Failed to fetch overrides:', err);
    } finally {
      loadingOverrides = false;
    }
  }

  let overridesFetched = $state(false);

  $effect(() => {
    if (isOpen) {
      if (activeTab === 'staff' && !staffData && !loadingStaffData) fetchStaffData();
      if ((activeTab === 'staff' || activeTab === 'overrides') && !overridesFetched && !loadingOverrides) fetchOverrides();
    }
  });
  async function toggleStaffAbsence(teacherId: string) {
    const existing = overrides.find(o => o.teacher === teacherId);
    const isAbsent = existing?.is_absent_override ?? false;
    
    try {
      const res = await fetch(`/api/admin/timetable/overrides`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          timetable: timetableId,
          teacher: teacherId,
          is_participating: existing?.is_participating ?? true,
          is_absent_override: !isAbsent,
          added_assignments: existing?.added_assignments || [],
          removed_assignments: existing?.removed_assignments || []
        })
      });
    
      if (res.ok) {
        await fetchOverrides();
      }
    } catch (err) {
      alert('Failed to update absence');
    }
  }

  const DEFAULT_DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
  
  // Clone day configs so we can edit them
  let currentConfigs = $state(DEFAULT_DAYS.map(day => {
    const existing = dayConfigs.find(c => c.day_of_week === day);
    if (existing) return { ...existing };
    return {
      day_of_week: day,
      periods_count: day === 'Friday' ? 6 : 7,
      excluded_periods: day === 'Friday' ? [6] : []
    };
  }));


  async function handleSaveStructure() {
    loading = true;
    try {
      const res = await fetch(`/api/admin/timetables/config`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ timetable: timetableId, day_configs: currentConfigs })
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
        
        {#if loadingStaffData || loadingOverrides}
          <div class="flex items-center justify-center p-8"><div class="animate-spin h-8 w-8 border-4 border-primary border-t-transparent rounded-full"></div></div>
        {:else if staffData}
          <div class="space-y-4">
            <h3 class="text-sm font-bold text-muted-foreground uppercase tracking-wider">Teacher Availability</h3>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              {#each staffData.teachers || [] as teacher}
                {@const ov = overrides.find(o => o.teacher === teacher.id)}
                {@const isAbsent = ov?.is_absent_override === true}
                <div class="flex items-center justify-between p-3 border rounded-xl bg-card">
                  <div>
                    <p class="font-semibold text-sm">{teacher.first_name} {teacher.surname}</p>
                  </div>
                  <Button size="sm" variant={isAbsent ? "destructive" : "outline"} onclick={() => toggleStaffAbsence(teacher.id)}>
                    {isAbsent ? 'Marked Absent' : 'Mark Absent'}
                  </Button>
                </div>
              {/each}
            </div>
          </div>
        {/if}

      {:else}
        
        {#if loadingStaffData || loadingOverrides}
          <div class="flex items-center justify-center p-8"><div class="animate-spin h-8 w-8 border-4 border-primary border-t-transparent rounded-full"></div></div>
        {:else if staffData}
          <div class="space-y-4">
            <h3 class="text-sm font-bold text-muted-foreground uppercase tracking-wider">Subject Overrides</h3>
            <p class="text-xs text-muted-foreground">Adjust maximum periods per week for a teacher's subjects.</p>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              {#each staffData.teachers || [] as teacher}
                {@const teaches = (staffData.teaches || []).filter((t: any) => t.teacher === teacher.id)}
                {#if teaches.length > 0}
                  <div class="flex flex-col space-y-2 p-3 border rounded-xl bg-card">
                    <div>
                      <p class="font-semibold text-sm">{teacher.first_name} {teacher.surname}</p>
                    </div>
                    {#each teaches as teach}
                      {@const subject = (staffData.subjects || []).find((s: any) => s.id === teach.has_subject)}
                      {#if subject}
                        <div class="flex items-center justify-between pl-2">
                          <span class="text-xs text-muted-foreground">- {subject.name}</span>
                          <!-- Coming soon: period count adjuster -->
                          <span class="text-xs font-medium text-slate-500 italic">Coming soon</span>
                        </div>
                      {/if}
                    {/each}
                  </div>
                {/if}
              {/each}
            </div>
          </div>
        {/if}

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
