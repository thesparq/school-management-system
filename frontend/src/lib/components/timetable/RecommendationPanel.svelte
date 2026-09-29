<script lang="ts">
  export type Recommendation = {
    id: string;
    severity: 'strict' | 'moderate' | 'simple' | string;
    title: string;
    description: string;
    suggested_action: string;
    category: 'deficit' | 'bottleneck' | 'coverage' | 'free_periods' | string;
  };

  let { recommendations = [] }: { recommendations: Recommendation[] } = $props();

  let filter = $state<'all' | 'strict' | 'moderate' | 'simple'>('all');
  let isExpanded = $state(true);

  let strictCount = $derived(recommendations.filter((r) => r.severity === 'strict').length);
  let moderateCount = $derived(recommendations.filter((r) => r.severity === 'moderate').length);
  let simpleCount = $derived(recommendations.filter((r) => r.severity === 'simple').length);

  let filtered = $derived(
    recommendations.filter((r) => {
      if (filter === 'all') return true;
      return r.severity === filter;
    })
  );

  const getSeverityBadge = (severity: string) => {
    switch (severity) {
      case 'strict':
        return 'bg-red-100 text-red-800 border-red-300';
      case 'moderate':
        return 'bg-amber-100 text-amber-900 border-amber-300';
      default:
        return 'bg-emerald-100 text-emerald-900 border-emerald-300';
    }
  };
  
  const getSeverityIndicator = (severity: string) => {
    switch (severity) {
      case 'strict':
        return 'bg-red-600 animate-ping';
      case 'moderate':
        return 'bg-amber-600';
      default:
        return 'bg-emerald-600';
    }
  };
  
  const getSeverityText = (severity: string) => {
    switch (severity) {
      case 'strict':
        return 'Target Deficit';
      case 'moderate':
        return 'Faculty Bottleneck';
      default:
        return 'Schedule Tip';
    }
  };

  const getCategoryBadgeClass = (category: string) => {
    switch (category) {
      case 'deficit':
        return 'bg-rose-50 text-rose-700 border-rose-200';
      case 'bottleneck':
        return 'bg-amber-50 text-amber-800 border-amber-200';
      case 'coverage':
        return 'bg-blue-50 text-blue-700 border-blue-200';
      default:
        return 'bg-slate-100 text-slate-700 border-slate-200';
    }
  };

  const getCategoryText = (category: string) => {
    switch (category) {
      case 'deficit':
        return '🎯 Weekly Target Shortfall';
      case 'bottleneck':
        return '⚠️ Over-Assigned Faculty';
      case 'coverage':
        return '👤 Missing Faculty Coverage';
      default:
        return '⏱️ Free Period Capacity';
    }
  };

  const getBorderColor = (severity: string) => {
    switch (severity) {
      case 'strict':
        return 'border-l-4 border-l-red-600 bg-red-50/30 border-slate-200';
      case 'moderate':
        return 'border-l-4 border-l-amber-500 bg-amber-50/20 border-slate-200';
      default:
        return 'border-l-4 border-l-emerald-600 bg-emerald-50/20 border-slate-200';
    }
  };

  const filters = [
    { id: 'all', label: `All` },
    { id: 'strict', label: `🔴 Target Deficits` },
    { id: 'moderate', label: `🟡 Faculty Bottlenecks` },
    { id: 'simple', label: `🟢 Capacity / Optimal` }
  ] as const;
  
  const getFilterCount = (id: string) => {
    if (id === 'all') return recommendations.length;
    if (id === 'strict') return strictCount;
    if (id === 'moderate') return moderateCount;
    return simpleCount;
  };
</script>

{#if recommendations && recommendations.length > 0}
  <div class="bg-white rounded-3xl shadow-sm border border-slate-200 overflow-hidden mb-6">
    <!-- Header -->
    <div class="p-5 border-b border-slate-200 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 bg-gradient-to-r from-slate-50 via-indigo-50/30 to-slate-50">
      <div class="flex items-center space-x-3.5">
        <div class="w-10 h-10 rounded-xl bg-indigo-600 text-white flex items-center justify-center shadow-md shrink-0">
          <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z" />
          </svg>
        </div>
        <div>
          <div class="flex items-center space-x-2">
            <h3 class="font-extrabold text-slate-900 text-base">
              Free Period Elimination & Target Suggestions
            </h3>
            <span class="text-xs bg-indigo-100 text-indigo-800 font-black px-2.5 py-0.5 rounded-full border border-indigo-200">
              {recommendations.length} Actionable
            </span>
          </div>
          <p class="text-xs text-slate-500 font-medium mt-0.5">
            Specific steps to eliminate unallocated free periods and fulfill weekly required subject frequencies.
          </p>
        </div>
      </div>

      <div class="flex items-center space-x-2 w-full sm:w-auto justify-between sm:justify-end">
        <!-- Quick summary badges -->
        <div class="flex items-center space-x-1.5 text-xs font-bold">
          {#if strictCount > 0}
            <span class="px-2.5 py-1 rounded-xl bg-red-100 text-red-800 border border-red-300">
              {strictCount} Deficit
            </span>
          {/if}
          {#if moderateCount > 0}
            <span class="px-2.5 py-1 rounded-xl bg-amber-100 text-amber-900 border border-amber-300">
              {moderateCount} Bottlenecks
            </span>
          {/if}
          {#if simpleCount > 0}
            <span class="px-2.5 py-1 rounded-xl bg-emerald-100 text-emerald-900 border border-emerald-300">
              {simpleCount} Capacity
            </span>
          {/if}
        </div>

        <button
          onclick={() => isExpanded = !isExpanded}
          class="p-2 text-slate-500 hover:text-slate-800 rounded-xl hover:bg-slate-100 transition-colors"
          title={isExpanded ? 'Collapse Suggestions' : 'Expand Suggestions'}
        >
          <svg
            class="w-5 h-5 transform transition-transform {isExpanded ? 'rotate-180' : ''}"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
        </button>
      </div>
    </div>

    <!-- Body -->
    {#if isExpanded}
      <div class="p-6 space-y-4">
        <!-- Filter tabs -->
        <div class="flex flex-wrap items-center gap-2 border-b border-slate-100 pb-3">
          <span class="text-[11px] font-extrabold text-slate-400 uppercase tracking-wider mr-2">
            Filter:
          </span>
          {#each filters as tab}
            <button
              onclick={() => filter = tab.id}
              class="px-3 py-1 rounded-xl text-xs font-bold transition-all {filter === tab.id ? 'bg-indigo-600 text-white shadow-sm' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}"
            >
              {tab.label} ({getFilterCount(tab.id)})
            </button>
          {/each}
        </div>

        <!-- Cards Grid -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          {#each filtered as rec (rec.id)}
            <div class="p-4 rounded-2xl border transition-all hover:shadow-sm space-y-3 {getBorderColor(rec.severity)}">
              <div class="flex items-start justify-between gap-2">
                <div>
                  <h4 class="font-extrabold text-slate-900 text-sm leading-snug">
                    {rec.title}
                  </h4>
                  <div class="mt-1">
                    <span class="text-[10px] font-bold px-2 py-0.5 rounded-md border {getCategoryBadgeClass(rec.category)}">
                      {getCategoryText(rec.category)}
                    </span>
                  </div>
                </div>
                <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-[10px] font-black border uppercase tracking-wider shrink-0 {getSeverityBadge(rec.severity)}">
                  <span class="w-1.5 h-1.5 rounded-full mr-1.5 {getSeverityIndicator(rec.severity)}"></span>
                  {getSeverityText(rec.severity)}
                </span>
              </div>

              <p class="text-xs text-slate-600 font-medium leading-relaxed">
                {rec.description}
              </p>

              <div class="bg-white p-3.5 rounded-xl border border-slate-200 text-xs shadow-xs space-y-2">
                <div class="flex items-center space-x-1.5 font-bold text-indigo-700 uppercase tracking-wider text-[10px]">
                  <svg class="w-3.5 h-3.5 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
                  </svg>
                  <span>Recommended Action:</span>
                </div>
                <p class="text-slate-800 font-semibold">{rec.suggested_action}</p>

                <div class="pt-1 flex items-center space-x-2">
                  <a
                    href="/admin/configuration/curriculum"
                    class="text-[11px] font-bold text-indigo-600 hover:text-indigo-800 hover:underline flex items-center space-x-1"
                  >
                    <span>→ Open Curriculum Manager</span>
                  </a>
                  <span class="text-slate-300">•</span>
                  <a
                    href="/admin/configuration/teachers"
                    class="text-[11px] font-bold text-slate-600 hover:text-slate-800 hover:underline flex items-center space-x-1"
                  >
                    <span>→ Faculty Schedules</span>
                  </a>
                </div>
              </div>
            </div>
          {/each}
        </div>
      </div>
    {/if}
  </div>
{/if}
