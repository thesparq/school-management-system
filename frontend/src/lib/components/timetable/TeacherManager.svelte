<script lang="ts">
  import { onMount } from 'svelte';
  import TeacherAvailabilityModal from './TeacherAvailabilityModal.svelte';

  type Teacher = {
    id: string;
    name: string;
    is_absent: boolean;
    is_active: boolean;
  };

  type TeacherAvailability = {
    id: string;
    teacher_id: string;
    day_of_week: string;
    period_number: number | null;
    is_available: boolean;
  };

  let teachers = $state<Teacher[]>([]);
  let availabilities = $state<TeacherAvailability[]>([]);
  let isModalOpen = $state(false);
  let editingTeacher = $state<Teacher | null>(null);
  let availabilityTeacher = $state<Teacher | null>(null);
  let formDataName = $state('');
  let loading = $state(false);

  const fetchTeachers = async () => {
    try {
      const [tRes, avRes] = await Promise.all([
        fetch('http://localhost:8000/api/teachers'),
        fetch('http://localhost:8000/api/teacher-availabilities'),
      ]);
      const tData = await tRes.json();
      const avData = await avRes.json();
      teachers = tData;
      availabilities = avData;
    } catch (err) {
      console.error('Failed to load teachers or availabilities:', err);
    }
  };

  onMount(() => {
    fetchTeachers();
  });

  const openAddModal = () => {
    editingTeacher = null;
    formDataName = '';
    isModalOpen = true;
  };

  const openEditModal = (t: Teacher) => {
    editingTeacher = t;
    formDataName = t.name;
    isModalOpen = true;
  };

  const openAvailabilityModal = (t: Teacher) => {
    availabilityTeacher = t;
  };

  const handleDelete = async (id: string) => {
    if (!confirm('Are you sure you want to remove this faculty member? This will clear all their class assignments and availability schedules.')) return;
    try {
      const res = await fetch(`http://localhost:8000/api/teachers/${id}`, { method: 'DELETE' });
      if (!res.ok) throw new Error(await res.text());
      teachers = teachers.filter(t => t.id !== id);
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event('schedule-updated'));
      }
    } catch (err: any) {
      alert(`Failed to delete teacher: ${err.message}`);
    }
  };

  const handleSubmit = async (e: Event) => {
    e.preventDefault();
    if (!formDataName.trim()) return;

    loading = true;
    const payload = { name: formDataName, max_daily_workload: 0, subject_expertise: '' };

    try {
      if (editingTeacher) {
        const res = await fetch(`http://localhost:8000/api/teachers/${editingTeacher.id}`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        if (!res.ok) throw new Error(await res.text());
        teachers = teachers.map(t => t.id === editingTeacher?.id ? { ...t, name: formDataName } : t);
      } else {
        const res = await fetch(`http://localhost:8000/api/teachers`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        if (!res.ok) throw new Error(await res.text());
        const newId = await res.json();
        teachers = [...teachers, { id: newId, name: formDataName, is_absent: false, is_active: true }];
      }
      isModalOpen = false;
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event('schedule-updated'));
      }
    } catch (err: any) {
      alert(`Failed to save teacher: ${err.message}`);
    } finally {
      loading = false;
    }
  };

  const getInitials = (name: string) => {
    const parts = name.trim().split(' ');
    const first = parts[0]?.[0] || '';
    const last = parts.length > 1 ? parts[parts.length - 1][0] : '';
    return (first + last).toUpperCase() || 'T';
  };

  const getAvailabilityStatus = (teacherId: string) => {
    const rules = availabilities.filter((a) => a.teacher_id === teacherId && !a.is_available);
    if (rules.length === 0) {
      return {
        label: 'Full Time (All Days)',
        type: 'full-time',
        badgeClass: 'bg-emerald-50 text-emerald-800 border-emerald-200',
        detail: 'Available Mon-Fri, P1-P8',
      };
    }

    const wholeDayBlocked = rules.filter((r) => r.period_number === null);
    const periodBlocked = rules.filter((r) => r.period_number !== null);

    let detail = '';
    if (wholeDayBlocked.length > 0) {
      const days = wholeDayBlocked.map((r) => r.day_of_week.slice(0, 3)).join(', ');
      detail = `Off: ${days}`;
    } else {
      detail = `${periodBlocked.length} periods blocked`;
    }

    return {
      label: 'Part Time / Custom',
      type: 'part-time',
      badgeClass: 'bg-amber-50 text-amber-900 border-amber-200',
      detail,
    };
  };
</script>

<div class="space-y-6">
  <!-- Header bar -->
  <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 bg-white p-6 rounded-2xl border border-slate-200 shadow-sm">
    <div class="flex items-center space-x-3.5">
      <div class="w-10 h-10 rounded-xl bg-indigo-50 text-indigo-700 flex items-center justify-center font-bold">
        <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
        </svg>
      </div>
      <div>
        <h2 class="text-xl font-extrabold text-slate-900 tracking-tight">Master Faculty & Staff Directory</h2>
        <p class="text-xs font-medium text-slate-500 mt-0.5">Central repository of educators, part-time schedules, and availability</p>
      </div>
    </div>
    <button 
      onclick={openAddModal}
      class="bg-indigo-600 hover:bg-indigo-700 text-white px-5 py-2.5 rounded-xl text-sm font-bold transition-all shadow-sm hover:shadow flex items-center space-x-2"
    >
      <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
      </svg>
      <span>Hire New Teacher</span>
    </button>
  </div>

  <!-- Staff Table -->
  <div class="bg-white rounded-2xl shadow-sm border border-slate-200 overflow-hidden">
    <table class="w-full text-left border-collapse">
      <thead>
        <tr class="bg-slate-50 border-b border-slate-200">
          <th class="py-3.5 px-6 font-extrabold text-slate-500 uppercase text-[11px] tracking-wider">Teacher Profile</th>
          <th class="py-3.5 px-6 font-extrabold text-slate-500 uppercase text-[11px] tracking-wider">Global Status</th>
          <th class="py-3.5 px-6 font-extrabold text-slate-500 uppercase text-[11px] tracking-wider">Part-Time / Availability</th>
          <th class="py-3.5 px-6 font-extrabold text-slate-500 uppercase text-[11px] tracking-wider text-right">Actions</th>
        </tr>
      </thead>
      <tbody class="divide-y divide-slate-100">
        {#each teachers as t (t.id)}
          {@const avail = getAvailabilityStatus(t.id)}
          <tr class="hover:bg-slate-50/60 transition-colors group">
            <td class="py-4 px-6">
              <div class="flex items-center space-x-4">
                <div class="w-10 h-10 rounded-xl bg-gradient-to-br from-indigo-100 to-indigo-200 flex items-center justify-center text-indigo-800 font-extrabold text-sm shadow-inner">
                  {getInitials(t.name)}
                </div>
                <div>
                  <p class="font-bold text-slate-900 text-sm">{t.name}</p>
                  <p class="text-[11px] text-slate-400 font-mono mt-0.5">Ref: {t.id}</p>
                </div>
              </div>
            </td>

            <td class="py-4 px-6">
              <span class="inline-flex items-center space-x-1.5 px-3 py-1 rounded-full text-xs font-bold border {t.is_absent ? 'bg-red-50 text-red-700 border-red-200' : 'bg-emerald-50 text-emerald-700 border-emerald-200'}">
                <span class="w-1.5 h-1.5 rounded-full {t.is_absent ? 'bg-red-500' : 'bg-emerald-500'}"></span>
                <span>{t.is_absent ? 'Global Absent' : 'Available Active'}</span>
              </span>
            </td>

            <td class="py-4 px-6">
              <div class="flex items-center space-x-3">
                <span class="inline-flex items-center space-x-1.5 px-2.5 py-1 rounded-xl text-xs font-bold border {avail.badgeClass}">
                  <svg class="w-3.5 h-3.5 opacity-75" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                  <span>{avail.label}</span>
                </span>

                <button
                  onclick={() => openAvailabilityModal(t)}
                  class="text-indigo-600 hover:text-indigo-800 text-xs font-bold px-2.5 py-1 bg-indigo-50 hover:bg-indigo-100 rounded-lg border border-indigo-200 transition-colors"
                  title="Configure specific available days or period blackout windows"
                >
                  Schedule & Days
                </button>
              </div>
            </td>

            <td class="py-4 px-6 text-right space-x-2">
              <button 
                onclick={() => openEditModal(t)} 
                class="text-slate-600 hover:text-indigo-600 font-bold text-xs px-3 py-1.5 rounded-lg hover:bg-slate-100 transition-colors"
              >
                Edit
              </button>
              <button 
                onclick={() => handleDelete(t.id)} 
                class="text-red-500 hover:text-red-700 font-bold text-xs px-3 py-1.5 rounded-lg hover:bg-red-50 transition-colors"
              >
                Remove
              </button>
            </td>
          </tr>
        {/each}
        {#if teachers.length === 0}
          <tr>
            <td colspan="4" class="py-12 text-center text-slate-400 font-medium">
              No teachers found in directory. Click "Hire New Teacher" above to add staff.
            </td>
          </tr>
        {/if}
      </tbody>
    </table>
  </div>

  <!-- Edit / Hire Modal -->
  {#if isModalOpen}
    <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-gray-900/50 backdrop-blur-sm">
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md overflow-hidden">
        <div class="px-6 py-5 border-b border-slate-100 bg-slate-50/50 flex justify-between items-center">
          <h3 class="text-lg font-extrabold text-slate-900">
            {editingTeacher ? 'Edit Faculty Profile' : 'Hire New Faculty Member'}
          </h3>
          <button onclick={() => isModalOpen = false} class="text-slate-400 hover:text-slate-600">
            <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
        <form onsubmit={handleSubmit} class="p-6 space-y-4">
          <div>
            <label class="block text-xs font-bold uppercase tracking-wider text-slate-600 mb-1.5">Full Name & Title</label>
            <input 
              type="text" 
              autofocus
              bind:value={formDataName}
              placeholder="e.g. Dr. Jonathan Vance"
              class="w-full bg-slate-50/50 border border-slate-300 px-4 py-2.5 rounded-xl focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-600 text-slate-900 font-semibold text-sm transition-all outline-none" 
              required
            />
          </div>

          <div class="flex justify-end space-x-3 pt-4">
            <button 
              type="button" 
              onclick={() => isModalOpen = false}
              class="px-4 py-2 text-xs font-bold text-slate-600 hover:bg-slate-100 rounded-xl transition-colors"
            >
              Cancel
            </button>
            <button 
              type="submit" 
              disabled={loading}
              class="bg-indigo-600 hover:bg-indigo-700 text-white px-5 py-2 rounded-xl text-xs font-bold transition-all shadow-sm hover:shadow"
            >
              {loading ? 'Saving...' : 'Save Profile'}
            </button>
          </div>
        </form>
      </div>
    </div>
  {/if}

  <!-- Teacher Availability / Part-Time Schedule Modal -->
  {#if availabilityTeacher}
    <TeacherAvailabilityModal
      isOpen={!!availabilityTeacher}
      onClose={() => availabilityTeacher = null}
      teacher={availabilityTeacher}
      onSaved={() => fetchTeachers()}
    />
  {/if}
</div>
