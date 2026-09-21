<script lang="ts">
  import { Button } from '$lib/components/ui/button';

  export let selectedClassId = '';
  export let dayConfigs: any[] = [];
  export let classSlots: any[] = [];
  export let classes: any[] = [];
  export let subjects: any[] = [];
  export let teachers: any[] = [];

  const defaultDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
  const DAY_ORDER: Record<string, number> = {
    'Monday': 1, 'Tuesday': 2, 'Wednesday': 3, 'Thursday': 4, 'Friday': 5, 'Saturday': 6, 'Sunday': 7
  };

  $: activeDays = (dayConfigs && dayConfigs.length > 0
    ? dayConfigs.map(c => c.day_of_week)
    : defaultDays
  ).sort((a, b) => (DAY_ORDER[a] || 99) - (DAY_ORDER[b] || 99));

  $: maxPeriods = dayConfigs && dayConfigs.length > 0
    ? Math.max(...dayConfigs.map(c => c.periods_count))
    : 8;

  $: periodList = Array.from({ length: maxPeriods }, (_, i) => i + 1);

  function getSubjectName(csId: string) {
    // Basic mapping for now
    const subject = subjects.find(s => s.id === csId);
    return subject ? subject.name : 'Unknown Subject';
  }

  function getTeacherName(teacherId: string) {
    const teacher = teachers.find(t => t.id === teacherId);
    return teacher ? `${teacher.first_name} ${teacher.last_name}` : 'Unknown';
  }

  function getSubjectColor(name: string) {
    // Simple mock coloring
    const colors = [
      'bg-indigo-50/90 border-indigo-200 text-indigo-950',
      'bg-emerald-50/90 border-emerald-200 text-emerald-950',
      'bg-rose-50/90 border-rose-200 text-rose-950',
      'bg-sky-50/90 border-sky-200 text-sky-950',
      'bg-amber-50/90 border-amber-200 text-amber-950',
    ];
    let hash = 0;
    for (let i = 0; i < name.length; i++) hash = name.charCodeAt(i) + ((hash << 5) - hash);
    return colors[Math.abs(hash) % colors.length];
  }
</script>

<div class="bg-white rounded-3xl border border-slate-200 shadow-sm overflow-hidden flex flex-col">
  <div class="overflow-x-auto">
    <table class="w-full border-collapse">
      <thead>
        <tr class="bg-slate-50/80 border-b border-slate-200">
          <th class="w-20 p-4 text-center font-black text-slate-400 text-xs uppercase tracking-wider border-r border-slate-200">
            Period
          </th>
          {#each activeDays as day}
            {@const cfg = dayConfigs.find(c => c.day_of_week === day)}
            <th class="p-4 text-center font-black text-slate-800 text-xs uppercase tracking-wide border-r border-slate-100 last:border-r-0 min-w-[180px]">
              <div>{day}</div>
              {#if cfg}
                <div class="text-[10px] font-bold text-slate-400 font-mono mt-0.5">
                  {cfg.periods_count} Periods
                </div>
              {/if}
            </th>
          {/each}
        </tr>
      </thead>
      <tbody class="divide-y divide-slate-200/80">
        {#each periodList as period}
          <tr class="group">
            <td class="p-0 border-r border-slate-200 text-center align-middle bg-white group-hover:bg-slate-50 transition-colors">
              <span class="text-xs font-black text-slate-400 font-mono">P{period}</span>
            </td>
            {#each activeDays as day}
              {@const cfg = dayConfigs.find(c => c.day_of_week === day)}
              {@const dayPeriodLimit = cfg ? cfg.periods_count : 8}
              
              {#if period > dayPeriodLimit}
                <td class="p-2 border-r border-slate-100 last:border-r-0 bg-slate-100/50 align-middle text-center">
                  <span class="text-[10px] font-black text-slate-400 uppercase tracking-widest">No Session</span>
                </td>
              {:else}
                {@const slot = classSlots.find(s => s.day_of_week === day && s.period_number === period)}
                
                {#if slot?.is_excluded}
                  <td class="p-2.5 border-r border-slate-100 last:border-r-0 align-top">
                    <div class="h-24 p-3 rounded-2xl border border-amber-300 bg-amber-100/70 flex flex-col justify-center items-center text-center shadow-xs">
                      <span class="inline-flex items-center space-x-1 text-xs font-black text-amber-950">
                        <svg class="w-4 h-4 text-amber-700" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                        </svg>
                        <span>Excluded Period</span>
                      </span>
                      <span class="text-[11px] text-amber-900 font-bold mt-1">
                        Reserved / Extracurricular
                      </span>
                    </div>
                  </td>
                {:else if !slot || !slot.class_subject_id}
                  <td class="p-2.5 border-r border-slate-100 last:border-r-0 align-top">
                    <div class="h-24 rounded-2xl border border-dashed border-slate-200 flex items-center justify-center bg-white/40">
                      <span class="text-[10px] font-bold text-slate-400 uppercase tracking-wider">Free Period</span>
                    </div>
                  </td>
                {:else}
                  {@const teacher = teachers.find(t => t.id === slot.teacher_id)}
                  {@const isAbsent = teacher?.is_absent}
                  {@const subjectName = getSubjectName(slot.class_subject_id)}
                  {@const colorClasses = isAbsent ? 'bg-red-50/90 border-red-300 text-red-950' : getSubjectColor(subjectName)}
                  
                  <td class="p-2.5 border-r border-slate-100 last:border-r-0 align-top">
                    <div class="relative h-24 p-3.5 rounded-2xl border transition-all duration-200 flex flex-col justify-between group/card {colorClasses} shadow-xs hover:shadow-md hover:-translate-y-0.5">
                      {#if isAbsent}
                        <div class="absolute top-2.5 right-2.5 w-2.5 h-2.5 rounded-full bg-red-600 animate-ping" title="Teacher Absent for this term"></div>
                      {/if}
                      
                      <div>
                        <div class="font-black text-sm leading-snug truncate">
                          {subjectName}
                        </div>
                        <div class="text-xs font-bold opacity-80 truncate mt-1 flex items-center space-x-1.5">
                          <svg class="w-3.5 h-3.5 opacity-70" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                          </svg>
                          <span>{getTeacherName(slot.teacher_id)}</span>
                        </div>
                      </div>
                    </div>
                  </td>
                {/if}
              {/if}
            {/each}
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
</div>
