<script lang="ts">
  import { exportTimetableToPdf } from '$lib/utils/pdfExport';
  import type { Recommendation } from './RecommendationPanel.svelte';

  let {
    isOpen,
    onClose,
    timetableName,
    timetableDescription,
    classes,
    slots,
    dayConfigs,
    subjects,
    classSubjects,
    teachers,
    recommendations = [],
    selectedClassId,
    initialEdition = 'clean',
  } = $props<{
    isOpen: boolean;
    onClose: () => void;
    timetableName: string;
    timetableDescription?: string;
    classes: Array<{ id: string; name: string }>;
    slots: any[];
    dayConfigs: any[];
    subjects: any[];
    classSubjects: any[];
    teachers: any[];
    recommendations?: Recommendation[];
    selectedClassId?: string;
    initialEdition?: 'clean' | 'diagnostic';
  }>();

  let documentEdition = $state<'clean' | 'diagnostic'>(initialEdition);
  let exportMode = $state<'current' | 'all' | 'custom'>(selectedClassId ? 'current' : 'all');
  let selectedCustomClasses = $state<string[]>(
    selectedClassId ? [selectedClassId] : classes.map((c: any) => c.id)
  );
  let includeLegend = $state(true);
  let includeRecommendations = $state(initialEdition === 'diagnostic');
  let includeExecutiveSummary = $state(initialEdition === 'diagnostic');
  let isExporting = $state(false);

  const handleEditionChange = (edition: 'clean' | 'diagnostic') => {
    documentEdition = edition;
    if (edition === 'clean') {
      includeRecommendations = false;
      includeExecutiveSummary = false;
      includeLegend = true;
    } else {
      includeRecommendations = true;
      includeExecutiveSummary = true;
      includeLegend = true;
    }
  };

  let currentClassObj = $derived(classes.find((c: any) => c.id === selectedClassId));

  const toggleClass = (classId: string) => {
    if (selectedCustomClasses.includes(classId)) {
      selectedCustomClasses = selectedCustomClasses.filter((id) => id !== classId);
    } else {
      selectedCustomClasses = [...selectedCustomClasses, classId];
    }
  };

  const selectAllClasses = () => {
    selectedCustomClasses = classes.map((c: any) => c.id);
  };

  const deselectAllClasses = () => {
    selectedCustomClasses = [];
  };

  const handleExport = async () => {
    isExporting = true;
    try {
      await new Promise((resolve) => setTimeout(resolve, 60));

      let targetClassesToExport: Array<{ id: string; name: string }> = [];

      if (exportMode === 'current') {
        targetClassesToExport = currentClassObj ? [currentClassObj] : classes.slice(0, 1);
      } else if (exportMode === 'all') {
        targetClassesToExport = classes;
      } else {
        targetClassesToExport = classes.filter((c: any) => selectedCustomClasses.includes(c.id));
      }

      if (targetClassesToExport.length === 0) {
        alert('Please select at least one class to export.');
        isExporting = false;
        return;
      }

      exportTimetableToPdf({
        timetableName,
        timetableDescription,
        classes: targetClassesToExport,
        slots,
        dayConfigs,
        subjects,
        classSubjects,
        teachers,
        recommendations,
        targetClassId: exportMode === 'current' ? currentClassObj?.id : undefined,
        includeLegend,
        includeRecommendations,
        includeExecutiveSummary: exportMode !== 'current' && includeExecutiveSummary,
      });

      onClose();
    } catch (err: any) {
      console.error('PDF export failed:', err);
      alert(`Failed to export PDF: ${err.message || 'Unknown error'}`);
    } finally {
      isExporting = false;
    }
  };

  let selectedCount = $derived(
    exportMode === 'current'
      ? 1
      : exportMode === 'all'
      ? classes.length
      : selectedCustomClasses.length
  );

  let totalSheetsEstimated = $derived(
    selectedCount + (exportMode !== 'current' && includeExecutiveSummary ? 1 : 0)
  );
</script>

{#if isOpen}
  <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-fadeIn">
    <div class="bg-white rounded-3xl shadow-2xl border border-slate-200 max-w-xl w-full overflow-hidden flex flex-col max-h-[90vh]">
      <!-- Modal Header -->
      <div class="px-6 py-5 bg-gradient-to-r from-slate-900 to-indigo-950 text-white flex justify-between items-center">
        <div class="flex items-center space-x-3">
          <div class="w-10 h-10 rounded-xl bg-indigo-500/20 border border-indigo-400/30 flex items-center justify-center text-indigo-300">
            <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
          </div>
          <div>
            <h3 class="text-lg font-black tracking-tight">Export PDF Timetable Sheets</h3>
            <p class="text-xs font-semibold text-slate-300">
              {timetableName} • Print-Ready High-Contrast Layout
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

      <!-- Modal Body -->
      <div class="p-6 space-y-5 overflow-y-auto flex-1">
        <!-- Document Edition Selector -->
        <div>
          <label class="block text-xs font-black uppercase tracking-wider text-slate-500 mb-2">
            Select Document Edition
          </label>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <button
              type="button"
              onclick={() => handleEditionChange('clean')}
              class="p-3.5 rounded-2xl border text-left transition-all relative {documentEdition === 'clean' ? 'border-emerald-600 bg-emerald-50/70 text-emerald-950 ring-2 ring-emerald-500/20' : 'border-slate-200 hover:border-slate-300 bg-white text-slate-700'}"
            >
              <div class="flex items-center space-x-2">
                <span class="w-2.5 h-2.5 rounded-full bg-emerald-500"></span>
                <span class="font-extrabold text-xs">Standard Classroom Timetable</span>
              </div>
              <div class="text-[11px] text-slate-500 font-medium mt-1">
                Clean timetable grid & official subject directory. Zero diagnostic warnings. Ready for students, classrooms & parents.
              </div>
            </button>

            <button
              type="button"
              onclick={() => handleEditionChange('diagnostic')}
              class="p-3.5 rounded-2xl border text-left transition-all relative {documentEdition === 'diagnostic' ? 'border-indigo-600 bg-indigo-50/70 text-indigo-950 ring-2 ring-indigo-500/20' : 'border-slate-200 hover:border-slate-300 bg-white text-slate-700'}"
            >
              <div class="flex items-center space-x-2">
                <span class="w-2.5 h-2.5 rounded-full bg-indigo-500"></span>
                <span class="font-extrabold text-xs">Administrative Diagnostic Report</span>
              </div>
              <div class="text-[11px] text-slate-500 font-medium mt-1">
                Master report with institutional KPIs, faculty bottleneck analysis, and class-specific optimization advice.
              </div>
            </button>
          </div>
        </div>

        <!-- Scope Selector -->
        <div>
          <label class="block text-xs font-black uppercase tracking-wider text-slate-500 mb-2.5">
            Select Export Scope
          </label>
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-2.5">
            <button
              type="button"
              onclick={() => exportMode = 'current'}
              class="p-3.5 rounded-2xl border text-left transition-all {exportMode === 'current' ? 'border-indigo-600 bg-indigo-50/70 text-indigo-950 ring-2 ring-indigo-500/20' : 'border-slate-200 hover:border-slate-300 bg-white text-slate-700'}"
            >
              <div class="font-extrabold text-xs">Current Class</div>
              <div class="text-[11px] font-semibold text-slate-500 truncate mt-0.5">
                {currentClassObj?.name || 'Selected Cohort'}
              </div>
            </button>

            <button
              type="button"
              onclick={() => exportMode = 'all'}
              class="p-3.5 rounded-2xl border text-left transition-all {exportMode === 'all' ? 'border-indigo-600 bg-indigo-50/70 text-indigo-950 ring-2 ring-indigo-500/20' : 'border-slate-200 hover:border-slate-300 bg-white text-slate-700'}"
            >
              <div class="font-extrabold text-xs">All Classes</div>
              <div class="text-[11px] font-semibold text-slate-500 mt-0.5">
                All {classes.length} Cohorts (1 Doc)
              </div>
            </button>

            <button
              type="button"
              onclick={() => exportMode = 'custom'}
              class="p-3.5 rounded-2xl border text-left transition-all {exportMode === 'custom' ? 'border-indigo-600 bg-indigo-50/70 text-indigo-950 ring-2 ring-indigo-500/20' : 'border-slate-200 hover:border-slate-300 bg-white text-slate-700'}"
            >
              <div class="font-extrabold text-xs">Custom Selection</div>
              <div class="text-[11px] font-semibold text-slate-500 mt-0.5">
                Choose specific classes
              </div>
            </button>
          </div>
        </div>

        <!-- Custom Class Selection Checkbox List -->
        {#if exportMode === 'custom'}
          <div class="p-4 bg-slate-50 rounded-2xl border border-slate-200 space-y-3">
            <div class="flex justify-between items-center">
              <span class="text-xs font-bold text-slate-600">
                Select Cohorts ({selectedCustomClasses.length}/{classes.length} selected):
              </span>
              <div class="space-x-2">
                <button
                  type="button"
                  onclick={selectAllClasses}
                  class="text-[11px] font-bold text-indigo-600 hover:underline"
                >
                  Select All
                </button>
                <span class="text-slate-300">•</span>
                <button
                  type="button"
                  onclick={deselectAllClasses}
                  class="text-[11px] font-bold text-slate-500 hover:underline"
                >
                  Deselect All
                </button>
              </div>
            </div>

            <div class="grid grid-cols-2 sm:grid-cols-3 gap-2 max-h-40 overflow-y-auto pr-1">
              {#each classes as cls}
                <label
                  class="flex items-center space-x-2 p-2 rounded-xl border text-xs font-bold cursor-pointer transition-colors {selectedCustomClasses.includes(cls.id) ? 'bg-indigo-50 border-indigo-200 text-indigo-950' : 'bg-white border-slate-200 text-slate-600 hover:bg-slate-100'}"
                >
                  <input
                    type="checkbox"
                    checked={selectedCustomClasses.includes(cls.id)}
                    onchange={() => toggleClass(cls.id)}
                    class="rounded text-indigo-600 focus:ring-indigo-500 border-slate-300"
                  />
                  <span class="truncate">{cls.name}</span>
                </label>
              {/each}
            </div>
          </div>
        {/if}

        <!-- Options -->
        <div class="p-4 bg-slate-50 rounded-2xl border border-slate-200 space-y-3">
          <div class="text-xs font-black uppercase tracking-wider text-slate-500">
            PDF Layout & Diagnostic Inclusions
          </div>

          <label class="flex items-center space-x-3 cursor-pointer">
            <input
              type="checkbox"
              bind:checked={includeRecommendations}
              class="w-4 h-4 rounded text-indigo-600 focus:ring-indigo-500 border-slate-300"
            />
            <div>
              <div class="text-xs font-bold text-slate-800">
                Include Actionable Recommendations & Deficit Insights
              </div>
              <div class="text-[11px] text-slate-500 font-medium">
                Prints class-specific optimization advice & actionable steps on each sheet
              </div>
            </div>
          </label>

          <label class="flex items-center space-x-3 cursor-pointer">
            <input
              type="checkbox"
              bind:checked={includeLegend}
              class="w-4 h-4 rounded text-indigo-600 focus:ring-indigo-500 border-slate-300"
            />
            <div>
              <div class="text-xs font-bold text-slate-800">
                Include Subject & Faculty Matrix Breakdown
              </div>
              <div class="text-[11px] text-slate-500 font-medium">
                Prints the curriculum summary box at the bottom of each timetable sheet
              </div>
            </div>
          </label>

          {#if exportMode !== 'current'}
            <label class="flex items-center space-x-3 cursor-pointer">
              <input
                type="checkbox"
                bind:checked={includeExecutiveSummary}
                class="w-4 h-4 rounded text-indigo-600 focus:ring-indigo-500 border-slate-300"
              />
              <div>
                <div class="text-xs font-bold text-slate-800">
                  Include Institutional Executive Overview (Page 1)
                </div>
                <div class="text-[11px] text-slate-500 font-medium">
                  Adds an initial dashboard cover page with school-wide KPIs and bottleneck summary
                </div>
              </div>
            </label>
          {/if}
        </div>

        <!-- Info Banner -->
        <div class="flex items-center space-x-3 p-3.5 bg-blue-50/80 border border-blue-200 rounded-2xl text-blue-950">
          <svg class="w-5 h-5 text-blue-600 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <span class="text-xs font-medium">
            Will generate <strong>{totalSheetsEstimated} Landscape A4 sheet{totalSheetsEstimated > 1 ? 's' : ''}</strong> formatted with high-contrast vector grid layout and side-by-side diagnostic cards.
          </span>
        </div>
      </div>

      <!-- Modal Footer -->
      <div class="p-4 bg-slate-50 border-t border-slate-200 flex justify-end space-x-3">
        <button
          type="button"
          onclick={onClose}
          disabled={isExporting}
          class="px-4 py-2 text-xs font-bold text-slate-600 hover:text-slate-800 transition-colors"
        >
          Cancel
        </button>

        <button
          type="button"
          onclick={handleExport}
          disabled={isExporting || selectedCount === 0}
          class="px-5 py-2.5 rounded-xl font-extrabold text-xs text-white shadow-md flex items-center space-x-2 transition-all {isExporting || selectedCount === 0 ? 'bg-indigo-400 cursor-not-allowed shadow-none' : 'bg-indigo-600 hover:bg-indigo-700 hover:shadow-indigo-600/30'}"
        >
          {#if isExporting}
            <svg class="animate-spin h-4 w-4 text-white" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            <span>Rendering PDF Sheets...</span>
          {:else}
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
            </svg>
            <span>Download PDF ({totalSheetsEstimated} Sheet{totalSheetsEstimated > 1 ? 's' : ''})</span>
          {/if}
        </button>
      </div>
    </div>
  </div>
{/if}
