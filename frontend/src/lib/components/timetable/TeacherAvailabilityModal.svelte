<script lang="ts">
  import { onMount } from 'svelte';

  let {
    isOpen,
    onClose,
    teacher,
    onSaved,
  } = $props<{
    isOpen: boolean;
    onClose: () => void;
    teacher: { id: string; name: string } | null;
    onSaved: () => void;
  }>();

  const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
  const PERIODS = [1, 2, 3, 4, 5, 6, 7, 8];

  let grid = $state<Record<string, boolean[]>>({});
  
  // Initialize grid
  const initGrid = () => {
    let next: Record<string, boolean[]> = {};
    DAYS.forEach((d) => {
      next[d] = Array(PERIODS.length).fill(true);
    });
    grid = next;
  };

  let loading = $state(false);
  let saving = $state(false);

  $effect(() => {
    if (isOpen && teacher) {
      loading = true;
      initGrid();
      
      // In a real app we'd use our golem API proxy, for now using the mocked React endpoint structure.
      fetch(`http://localhost:8000/api/teachers/${teacher.id}/availability`)
        .then((res) => res.json())
        .then((rules: any[]) => {
          let next = { ...grid };
          
          rules.forEach((r) => {
            const day = r.day_of_week;
            if (next[day]) {
              if (r.period_number === null || r.period_number === undefined) {
                next[day] = Array(PERIODS.length).fill(r.is_available);
              } else {
                const pIdx = r.period_number - 1;
                if (pIdx >= 0 && pIdx < PERIODS.length) {
                  next[day][pIdx] = r.is_available;
                }
              }
            }
          });

          grid = next;
        })
        .catch((err) => {
          console.error('Failed to fetch teacher availability:', err);
        })
        .finally(() => {
          loading = false;
        });
    }
  });

  const toggleCell = (day: string, periodIdx: number) => {
    let next = { ...grid };
    next[day] = [...next[day]];
    next[day][periodIdx] = !next[day][periodIdx];
    grid = next;
  };

  const toggleDay = (day: string) => {
    let next = { ...grid };
    const allTrue = next[day].every((v) => v);
    next[day] = Array(PERIODS.length).fill(!allTrue);
    grid = next;
  };

  const togglePeriodColumn = (pIdx: number) => {
    let next = { ...grid };
    const allTrue = DAYS.every((d) => next[d][pIdx]);
    DAYS.forEach((d) => {
      next[d] = [...next[d]];
      next[d][pIdx] = !allTrue;
    });
    grid = next;
  };

  // Preset Handlers
  const applyPresetFullTime = () => {
    let next: Record<string, boolean[]> = {};
    DAYS.forEach((d) => {
      next[d] = Array(PERIODS.length).fill(true);
    });
    grid = next;
  };

  const applyPresetMorningOnly = () => {
    let next: Record<string, boolean[]> = {};
    DAYS.forEach((d) => {
      next[d] = PERIODS.map((p) => p <= 4);
    });
    grid = next;
  };

  const applyPresetAfternoonOnly = () => {
    let next: Record<string, boolean[]> = {};
    DAYS.forEach((d) => {
      next[d] = PERIODS.map((p) => p >= 4);
    });
    grid = next;
  };

  const applyPresetMonWedFri = () => {
    let next: Record<string, boolean[]> = {};
    DAYS.forEach((d) => {
      const isMWF = ['Monday', 'Wednesday', 'Friday'].includes(d);
      next[d] = Array(PERIODS.length).fill(isMWF);
    });
    grid = next;
  };

  const applyPresetTueThu = () => {
    let next: Record<string, boolean[]> = {};
    DAYS.forEach((d) => {
      const isTT = ['Tuesday', 'Thursday'].includes(d);
      next[d] = Array(PERIODS.length).fill(isTT);
    });
    grid = next;
  };

  const handleSave = async () => {
    saving = true;
    try {
      const rules: Array<{
        day_of_week: string;
        period_number: number | null;
        is_available: boolean;
      }> = [];

      DAYS.forEach((day) => {
        const periods = grid[day] || [];
        const allFalse = periods.every((v) => !v);
        const allTrue = periods.every((v) => v);

        if (allFalse) {
          rules.push({
            day_of_week: day,
            period_number: null,
            is_available: false,
          });
        } else if (!allTrue) {
          periods.forEach((isAvail, idx) => {
            if (!isAvail) {
              rules.push({
                day_of_week: day,
                period_number: idx + 1,
                is_available: false,
              });
            }
          });
        }
      });

      if (!teacher) return;
      const res = await fetch(`http://localhost:8000/api/teachers/${teacher.id}/availability`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ rules }),
      });

      if (!res.ok) throw new Error(await res.text());

      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event('schedule-updated'));
      }
      onSaved();
      onClose();
    } catch (err: any) {
      console.error('Failed to save availability:', err);
      alert(`Failed to save availability: ${err.message || 'Unknown error'}`);
    } finally {
      saving = false;
    }
  };

  let totalAvailableSlots = $derived.by(() => {
    let count = 0;
    DAYS.forEach((d) => {
      count += (grid[d] || []).filter(Boolean).length;
    });
    return count;
  });

  let activeDaysCount = $derived.by(() => {
    let count = 0;
    DAYS.forEach((d) => {
      if ((grid[d] || []).filter(Boolean).length > 0) count++;
    });
    return count;
  });

  let isFullyAvailable = $derived(totalAvailableSlots === DAYS.length * PERIODS.length);
</script>

{#if isOpen && teacher}
  <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-fadeIn">
    <div class="bg-white rounded-3xl shadow-2xl border border-slate-200 max-w-2xl w-full overflow-hidden flex flex-col max-h-[92vh]">
      <!-- Header -->
      <div class="px-6 py-5 bg-gradient-to-r from-slate-900 to-indigo-950 text-white flex justify-between items-center">
        <div class="flex items-center space-x-3.5">
          <div class="w-10 h-10 rounded-xl bg-indigo-500/20 border border-indigo-400/30 flex items-center justify-center text-indigo-300">
            <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
            </svg>
          </div>
          <div>
            <h3 class="text-lg font-black tracking-tight">{teacher.name}</h3>
            <p class="text-xs font-semibold text-slate-300">
              Part-Time & Slot Availability Schedule
            </p>
          </div>
        </div>
        <button
          onclick={onClose}
          class="text-slate-400 hover:text-white transition-colors p-1.5 rounded-lg hover:bg-white/10"
        >
          <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      <!-- Body -->
      <div class="p-6 space-y-5 overflow-y-auto flex-1">
        <!-- Quick Preset Toolbar -->
        <div>
          <div class="flex justify-between items-center mb-2">
            <span class="text-[11px] font-black uppercase tracking-wider text-slate-500">
              Quick Schedule Presets
            </span>
            <span class="text-xs font-bold text-indigo-700">
              {#if isFullyAvailable}
                Full Time (All Slots)
              {:else}
                Part-Time ({activeDaysCount} Days, {totalAvailableSlots} Periods)
              {/if}
            </span>
          </div>
          <div class="flex flex-wrap gap-2">
            <button
              type="button"
              onclick={applyPresetFullTime}
              class="px-3 py-1.5 bg-emerald-50 hover:bg-emerald-100 text-emerald-800 border border-emerald-200 rounded-xl text-xs font-bold transition-all shadow-xs"
            >
              ✓ Full Time (All)
            </button>
            <button
              type="button"
              onclick={applyPresetMorningOnly}
              class="px-3 py-1.5 bg-indigo-50 hover:bg-indigo-100 text-indigo-700 border border-indigo-200 rounded-xl text-xs font-bold transition-all shadow-xs"
            >
              Morning Only (P1-P4)
            </button>
            <button
              type="button"
              onclick={applyPresetAfternoonOnly}
              class="px-3 py-1.5 bg-indigo-50 hover:bg-indigo-100 text-indigo-700 border border-indigo-200 rounded-xl text-xs font-bold transition-all shadow-xs"
            >
              Afternoon Only (P4-P8)
            </button>
            <button
              type="button"
              onclick={applyPresetMonWedFri}
              class="px-3 py-1.5 bg-blue-50 hover:bg-blue-100 text-blue-700 border border-blue-200 rounded-xl text-xs font-bold transition-all shadow-xs"
            >
              Mon / Wed / Fri Only
            </button>
            <button
              type="button"
              onclick={applyPresetTueThu}
              class="px-3 py-1.5 bg-purple-50 hover:bg-purple-100 text-purple-700 border border-purple-200 rounded-xl text-xs font-bold transition-all shadow-xs"
            >
              Tue / Thu Only
            </button>
          </div>
        </div>

        <!-- Interactive Matrix Grid -->
        <div class="border border-slate-200 rounded-2xl overflow-hidden bg-white shadow-xs">
          {#if loading}
            <div class="h-56 flex items-center justify-center space-x-2">
              <div class="w-5 h-5 border-2 border-indigo-600 border-t-transparent rounded-full animate-spin"></div>
              <span class="text-xs font-bold text-slate-500">Loading schedule rules...</span>
            </div>
          {:else}
            <table class="w-full text-center border-collapse">
              <thead>
                <tr class="bg-slate-100 border-b border-slate-200">
                  <th class="p-2.5 text-xs font-black text-slate-600 uppercase tracking-wider text-left pl-4 border-r border-slate-200">
                    Day / Period
                  </th>
                  {#each PERIODS as p, pIdx}
                    <th
                      onclick={() => togglePeriodColumn(pIdx)}
                      class="p-2 text-xs font-extrabold text-slate-700 border-r border-slate-200 last:border-r-0 cursor-pointer hover:bg-slate-200/80 transition-colors"
                      title="Click to toggle all Period {p} slots"
                    >
                      P{p}
                    </th>
                  {/each}
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-200">
                {#each DAYS as day}
                  {@const daySlots = grid[day] || []}
                  {@const isDayActive = daySlots.some(Boolean)}
                  
                  <tr class="hover:bg-slate-50/50 transition-colors">
                    <td class="p-2.5 text-xs font-black text-slate-800 text-left pl-4 border-r border-slate-200 bg-slate-50">
                      <button
                        type="button"
                        onclick={() => toggleDay(day)}
                        class="flex items-center space-x-2 text-left hover:text-indigo-600 group"
                        title="Click to toggle entire {day}"
                      >
                        <span class="w-2.5 h-2.5 rounded-full {isDayActive ? 'bg-emerald-500' : 'bg-red-400'}"></span>
                        <span class="group-hover:underline">{day}</span>
                      </button>
                    </td>

                    {#each PERIODS as p, pIdx}
                      {@const isAvail = daySlots[pIdx] ?? true}
                      <td class="p-1.5 border-r border-slate-200 last:border-r-0">
                        <button
                          type="button"
                          onclick={() => toggleCell(day, pIdx)}
                          class="w-full py-2.5 rounded-xl font-black text-xs transition-all flex flex-col items-center justify-center {isAvail ? 'bg-emerald-500 text-white shadow-xs hover:bg-emerald-600 ring-1 ring-emerald-600' : 'bg-red-50 text-red-600 border border-red-200 hover:bg-red-100 opacity-80'}"
                          title="{day} P{pIdx + 1}: {isAvail ? 'Available (Click to block)' : 'Unavailable (Click to enable)'}"
                        >
                          <span>{isAvail ? '✓' : '✕'}</span>
                        </button>
                      </td>
                    {/each}
                  </tr>
                {/each}
              </tbody>
            </table>
          {/if}
        </div>

        <!-- Helper Legend & Notice -->
        <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 p-3.5 bg-slate-50 border border-slate-200 rounded-2xl text-xs">
          <div class="flex items-center space-x-4">
            <span class="flex items-center space-x-1.5 font-bold text-emerald-800">
              <span class="w-3 h-3 rounded-md bg-emerald-500"></span>
              <span>Available Slot</span>
            </span>
            <span class="flex items-center space-x-1.5 font-bold text-red-700">
              <span class="w-3 h-3 rounded-md bg-red-100 border border-red-300"></span>
              <span>Unavailable / Off Slot</span>
            </span>
          </div>
          <span class="text-slate-500 font-medium">
            Click any cell, column, or day to toggle.
          </span>
        </div>
      </div>

      <!-- Footer -->
      <div class="p-4 bg-slate-50 border-t border-slate-200 flex justify-end space-x-3">
        <button
          type="button"
          onclick={onClose}
          disabled={saving}
          class="px-4 py-2 text-xs font-bold text-slate-600 hover:text-slate-800 transition-colors"
        >
          Cancel
        </button>
        <button
          type="button"
          onclick={handleSave}
          disabled={saving}
          class="px-5 py-2.5 rounded-xl font-extrabold text-xs text-white shadow-md flex items-center space-x-2 transition-all {saving ? 'bg-indigo-400 cursor-not-allowed shadow-none' : 'bg-indigo-600 hover:bg-indigo-700 hover:shadow-indigo-600/30'}"
        >
          {#if saving}
            <svg class="animate-spin h-4 w-4 text-white" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            <span>Saving Schedule...</span>
          {:else}
            <span>Save & Apply Availability</span>
          {/if}
        </button>
      </div>
    </div>
  </div>
{/if}
