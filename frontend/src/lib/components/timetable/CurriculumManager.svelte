<script lang="ts">
  import { onMount } from 'svelte';
  import SearchableSelect from './SearchableSelect.svelte';

  let { data, plannerData }: { data: any, plannerData: any } = $props();
  
  let staff = $state(data.staff);

  let loading = $state(false);
  
  // Forms for adding individual classes & subjects
  let newClass = $state('');
  let newSubject = $state('');
  
  // Offering Creation Mode: 'bulk' | 'clone' | 'single'
  let offeringMode = $state<'bulk' | 'clone' | 'single'>('bulk');

  // Single Offering State
  let csClass = $state('');
  let csSubject = $state('');
  let csTier = $state(3);

  // Bulk Multi-Class & Multi-Subject Enroller State
  let bulkClassIds = $state<string[]>([]);
  let bulkSelectedSubjectIds = $state<string[]>([]);
  let bulkDefaultTier = $state<number>(3);

  // Clone / Replicate Curriculum State
  let cloneSourceClass = $state('');
  let cloneTargetClasses = $state<string[]>([]);
  let cloneCopyTeachers = $state(true);

  // Offering Filter State
  let offeringClassFilter = $state('ALL');

  // Bulk Offering Selection State
  let selectedOfferingIds = $state<string[]>([]);

  // Teacher Qualification State
  let taMode = $state<'bulk' | 'single'>('bulk');
  let taTeacher = $state('');
  let taClassSubject = $state('');
  let taBulkSelectedOfferings = $state<string[]>([]);
  let taOfferingSearch = $state('');
  let taListFilterTeacher = $state('ALL');

  // Search filters
  let subjectSearch = $state('');
  let classSearch = $state('');

  // Editing state for Class / Subject
  let editingItem = $state<{ type: 'class' | 'subject'; id: string; name: string } | null>(null);

  $effect(() => {
    if (data && data.staff) {
      staff = data.staff;
      import('svelte').then(({ untrack }) => {
        untrack(() => {
          if (staff?.length > 0 && !taTeacher) taTeacher = staff[0].id;
        });
      });
    }
  });

  $effect(() => {
    if (plannerData) {
      import('svelte').then(({ untrack }) => {
        untrack(() => {
          if (plannerData.classes?.length > 0) {
            if (!csClass) csClass = plannerData.classes[0].id;
            if (!cloneSourceClass) cloneSourceClass = plannerData.classes[0].id;
          }
          if (plannerData.subjects?.length > 0 && !csSubject) csSubject = plannerData.subjects[0].id;
          if (plannerData.class_subjects?.length > 0 && !taClassSubject) taClassSubject = plannerData.class_subjects[0].id;
        });
      });
    }
  });

  const fetchData = async () => {
    // SSR fallback for client-side updates
    try {
      const res = await fetch('/api/admin/schedule');
      const json = await res.json();
      data.plannerData = json;
    } catch (err) {
      console.error('Failed to load curriculum:', err);
    }
  };

  const handleCreate = async (endpoint: string, payload: any) => {
    loading = true;
    try {
      const res = await fetch(`http://localhost:8000/api/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      if (!res.ok) throw new Error(await res.text());
      await fetchData();
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event('schedule-updated'));
      }
    } catch (e: any) {
      alert(`Error: ${e.message || 'Item might already exist'}`);
    } finally {
      loading = false;
    }
  };

  const handleBulkEnroll = async () => {
    if (bulkClassIds.length === 0) {
      alert('Please select at least one cohort / class.');
      return;
    }
    if (bulkSelectedSubjectIds.length === 0) {
      alert('Please select at least one subject to enroll.');
      return;
    }

    loading = true;
    try {
      const subjectsPayload = bulkSelectedSubjectIds.map(sId => ({
        subject_id: sId,
        tier: bulkDefaultTier,
      }));

      const res = await fetch('http://localhost:8000/api/class-subjects/batch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          class_ids: bulkClassIds,
          subjects: subjectsPayload,
        }),
      });

      if (!res.ok) throw new Error(await res.text());
      const result = await res.json();
      alert(`Success! Created ${result.created_count} new offerings across ${bulkClassIds.length} classes (${result.skipped_count} existing pairings skipped).`);
      bulkSelectedSubjectIds = [];
      await fetchData();
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event('schedule-updated'));
      }
    } catch (err: any) {
      alert(`Bulk enrollment failed: ${err.message}`);
    } finally {
      loading = false;
    }
  };

  const handleCloneCurriculum = async () => {
    if (!cloneSourceClass) {
      alert('Please choose a source class to replicate from.');
      return;
    }
    if (cloneTargetClasses.length === 0) {
      alert('Please select at least one target class to copy the curriculum to.');
      return;
    }

    loading = true;
    try {
      const res = await fetch(`http://localhost:8000/api/classes/${cloneSourceClass}/clone-offerings`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          target_class_ids: cloneTargetClasses,
          copy_teacher_assignments: cloneCopyTeachers,
        }),
      });

      if (!res.ok) throw new Error(await res.text());
      const result = await res.json();
      alert(`Curriculum Replicated!\n\n• Replicated ${result.cloned_offerings_count} subject offerings\n• Copied ${result.cloned_assignments_count} faculty authorizations`);
      cloneTargetClasses = [];
      await fetchData();
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event('schedule-updated'));
      }
    } catch (err: any) {
      alert(`Curriculum replication failed: ${err.message}`);
    } finally {
      loading = false;
    }
  };

  const handleUpdate = async (e: Event) => {
    e.preventDefault();
    if (!editingItem || !editingItem.name.trim()) return;

    loading = true;
    const endpoint = editingItem.type === 'class' ? 'classes' : 'subjects';
    try {
      const res = await fetch(`http://localhost:8000/api/${endpoint}/${editingItem.id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: editingItem.name.trim() }),
      });
      if (!res.ok) throw new Error(await res.text());
      editingItem = null;
      await fetchData();
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event('schedule-updated'));
      }
    } catch (err: any) {
      alert(`Failed to update ${editingItem?.type}: ${err.message}`);
    } finally {
      loading = false;
    }
  };

  const handleDeleteClass = async (id: string, name: string) => {
    if (!confirm(`Are you sure you want to delete class "${name}"?\n\nThis will remove all associated curriculum offerings, teacher assignments, and schedule slots for this class.`)) {
      return;
    }
    loading = true;
    try {
      const res = await fetch(`http://localhost:8000/api/classes/${id}`, { method: 'DELETE' });
      if (!res.ok) throw new Error(await res.text());
      await fetchData();
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event('schedule-updated'));
      }
    } catch (err: any) {
      alert(`Failed to delete class: ${err.message}`);
    } finally {
      loading = false;
    }
  };

  const handleDeleteSubject = async (id: string, name: string) => {
    if (!confirm(`Are you sure you want to delete subject "${name}"?\n\nThis will remove all associated class mappings, qualifications, and scheduled slots for this subject.`)) {
      return;
    }
    loading = true;
    try {
      const res = await fetch(`http://localhost:8000/api/subjects/${id}`, { method: 'DELETE' });
      if (!res.ok) throw new Error(await res.text());
      await fetchData();
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event('schedule-updated'));
      }
    } catch (err: any) {
      alert(`Failed to delete subject: ${err.message}`);
    } finally {
      loading = false;
    }
  };

  const handleDeleteClassSubject = async (id: string, className: string, subjectName: string) => {
    if (!confirm(`Remove offering "${subjectName}" from "${className}"?\n\nThis will also remove teacher authorizations for this specific pairing.`)) {
      return;
    }
    loading = true;
    try {
      const res = await fetch(`http://localhost:8000/api/class-subjects/${id}`, { method: 'DELETE' });
      if (!res.ok) throw new Error(await res.text());
      await fetchData();
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event('schedule-updated'));
      }
    } catch (err: any) {
      alert(`Failed to delete class offering: ${err.message}`);
    } finally {
      loading = false;
    }
  };

  const toggleOfferingSelection = (id: string) => {
    if (selectedOfferingIds.includes(id)) {
      selectedOfferingIds = selectedOfferingIds.filter(item => item !== id);
    } else {
      selectedOfferingIds = [...selectedOfferingIds, id];
    }
  };

  const handleSelectAllDisplayedOfferings = (displayedIds: string[]) => {
    const allSelected = displayedIds.length > 0 && displayedIds.every(id => selectedOfferingIds.includes(id));
    if (allSelected) {
      selectedOfferingIds = selectedOfferingIds.filter(id => !displayedIds.includes(id));
    } else {
      selectedOfferingIds = Array.from(new Set([...selectedOfferingIds, ...displayedIds]));
    }
  };

  const handleDeleteBulkSelected = async () => {
    if (selectedOfferingIds.length === 0) return;
    if (!confirm(`Are you sure you want to delete ${selectedOfferingIds.length} selected subject offering(s)?\n\nThis will remove their faculty authorizations and update the timetable.`)) {
      return;
    }
    loading = true;
    try {
      const res = await fetch('http://localhost:8000/api/class-subjects/bulk-delete', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ids: selectedOfferingIds }),
      });
      if (!res.ok) throw new Error(await res.text());
      const result = await res.json();
      alert(`Successfully deleted ${result.deleted_count} subject offering(s).`);
      selectedOfferingIds = [];
      await fetchData();
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event('schedule-updated'));
      }
    } catch (err: any) {
      alert(`Bulk deletion failed: ${err.message}`);
    } finally {
      loading = false;
    }
  };

  const handleDeleteAllForClass = async (classId: string, className: string) => {
    if (!confirm(`⚠️ WARNING: Delete ALL subject offerings for "${className}"?\n\nThis will wipe all enrolled subjects and teacher qualifications for this class.`)) {
      return;
    }
    loading = true;
    try {
      const res = await fetch('http://localhost:8000/api/class-subjects/bulk-delete', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ class_id: classId }),
      });
      if (!res.ok) throw new Error(await res.text());
      const result = await res.json();
      alert(`Removed all ${result.deleted_count} offerings from "${className}".`);
      selectedOfferingIds = [];
      await fetchData();
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event('schedule-updated'));
      }
    } catch (err: any) {
      alert(`Class offerings deletion failed: ${err.message}`);
    } finally {
      loading = false;
    }
  };

  const handleDeleteAllOfferings = async () => {
    const confirmation = prompt(`🚨 DANGER: You are about to DELETE ALL subject offerings across the ENTIRE school!\n\nThis will reset all class curriculums and teacher qualifications.\n\nType "DELETE ALL" below to confirm:`);
    if (confirmation !== 'DELETE ALL') {
      if (confirmation !== null) {
        alert('Deletion cancelled. You must type "DELETE ALL" exactly to wipe the entire curriculum.');
      }
      return;
    }
    loading = true;
    try {
      const res = await fetch('http://localhost:8000/api/class-subjects/bulk-delete', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ delete_all: true }),
      });
      if (!res.ok) throw new Error(await res.text());
      const result = await res.json();
      alert(`Cleaned slate! Deleted all ${result.deleted_count} subject offerings across the school.`);
      selectedOfferingIds = [];
      await fetchData();
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event('schedule-updated'));
      }
    } catch (err: any) {
      alert(`Global deletion failed: ${err.message}`);
    } finally {
      loading = false;
    }
  };

  const handleUpdateTier = async (id: string, tier: number) => {
    try {
      const res = await fetch(`http://localhost:8000/api/class-subjects/${id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tier }),
      });
      if (!res.ok) throw new Error(await res.text());
      await fetchData();
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event('schedule-updated'));
      }
    } catch (err: any) {
      alert(`Failed to update tier: ${err.message}`);
    }
  };

  const deleteAssignment = async (id: string) => {
    if (!confirm('Remove this master teacher qualification?')) return;
    try {
      const res = await fetch(`http://localhost:8000/api/teacher-assignments/${id}`, { method: 'DELETE' });
      if (!res.ok) throw new Error(await res.text());
      await fetchData();
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event('schedule-updated'));
      }
    } catch (e: any) {
      alert(`Failed to delete assignment: ${e.message}`);
    }
  };

  const handleBulkTeacherAuthorize = async () => {
    if (!taTeacher) {
      alert('Please select a faculty member.');
      return;
    }
    if (taBulkSelectedOfferings.length === 0) {
      alert('Please select at least one subject offering to authorize.');
      return;
    }

    loading = true;
    try {
      const res = await fetch('http://localhost:8000/api/teacher-assignments/batch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          teacher_ids: [taTeacher],
          class_subject_ids: taBulkSelectedOfferings,
        }),
      });

      if (!res.ok) throw new Error(await res.text());
      const result = await res.json();
      const teacherName = staff?.find((t: any) => t.id === taTeacher)?.name || 'Teacher';
      alert(`Success! Authorized ${teacherName} for ${result.created_count} new offerings (${result.skipped_count} already existed).`);
      taBulkSelectedOfferings = [];
      await fetchData();
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event('schedule-updated'));
      }
    } catch (err: any) {
      alert(`Bulk teacher authorization failed: ${err.message}`);
    } finally {
      loading = false;
    }
  };

  const handleClearAllQualificationsForTeacher = async (teacherId: string, teacherName: string) => {
    if (!confirm(`Are you sure you want to remove ALL qualifications for "${teacherName}"?\n\nThis teacher will no longer be eligible to teach any classes in the timetable.`)) {
      return;
    }
    loading = true;
    try {
      const res = await fetch('http://localhost:8000/api/teacher-assignments/bulk-delete', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ teacher_id: teacherId }),
      });
      if (!res.ok) throw new Error(await res.text());
      const result = await res.json();
      alert(`Removed ${result.deleted_count} authorizations for ${teacherName}.`);
      await fetchData();
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event('schedule-updated'));
      }
    } catch (err: any) {
      alert(`Failed to clear qualifications: ${err.message}`);
    } finally {
      loading = false;
    }
  };

  let classes = $derived(plannerData?.classes || []);
  let subjects = $derived(plannerData?.subjects || []);
  let class_subjects = $derived(plannerData?.class_subjects || []);
  let teachers = $derived(staff || []);
  let assignments = $derived(plannerData?.assignments || []);

  let filteredClasses = $derived((classes).filter((c: any) =>
    c.name.toLowerCase().includes(classSearch.toLowerCase())
  ));
  let filteredSubjects = $derived((subjects).filter((s: any) =>
    s.name.toLowerCase().includes(subjectSearch.toLowerCase())
  ));

  let displayedClassSubjects = $derived((class_subjects).filter((cs: any) => {
    if (offeringClassFilter === 'ALL') return true;
    return cs.class_id === offeringClassFilter;
  }));

  const getClassName = (id: string) => classes.find((c: any) => c.id === id)?.name || 'Unknown Class';
  const getSubjectName = (id: string) => subjects.find((s: any) => s.id === id)?.name || 'Unknown Subject';
  const getTeacherName = (id: string) => teachers.find((t: any) => t.id === id)?.name || 'Unknown Teacher';

  // Toggle helper for bulk classes
  const toggleBulkClass = (id: string) => {
    if (bulkClassIds.includes(id)) {
      bulkClassIds = bulkClassIds.filter(x => x !== id);
    } else {
      bulkClassIds = [...bulkClassIds, id];
    }
  };

  // Toggle helper for bulk subjects
  const toggleBulkSubject = (id: string) => {
    if (bulkSelectedSubjectIds.includes(id)) {
      bulkSelectedSubjectIds = bulkSelectedSubjectIds.filter(x => x !== id);
    } else {
      bulkSelectedSubjectIds = [...bulkSelectedSubjectIds, id];
    }
  };

  // Toggle helper for clone targets
  const toggleCloneTarget = (id: string) => {
    if (cloneTargetClasses.includes(id)) {
      cloneTargetClasses = cloneTargetClasses.filter(x => x !== id);
    } else {
      cloneTargetClasses = [...cloneTargetClasses, id];
    }
  };
</script>


{#if !data}
  <div class="bg-card rounded-2xl shadow-sm border border-border h-96 flex items-center justify-center">
    <div class="flex flex-col items-center space-y-4">
      <div class="w-10 h-10 border-4 border-indigo-200 border-t-indigo-600 rounded-full animate-spin"></div>
      <p class="text-muted-foreground font-semibold animate-pulse text-sm">Loading Curriculum Planner...</p>
    </div>
  </div>
{:else}
  <div class="space-y-8">
    <!-- Top Row: Classes & Global Subjects -->
    <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
      <!-- Classes Box -->
      <div class="bg-card rounded-2xl shadow-sm border border-border p-6 space-y-5">
        <div class="flex items-center space-x-3">
          <div class="w-9 h-9 rounded-xl bg-indigo-50 text-indigo-700 flex items-center justify-center font-bold text-sm">
            <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
            </svg>
          </div>
          <div>
            <h3 class="text-lg font-extrabold text-card-foreground">Student Cohorts & Classes</h3>
            <p class="text-xs font-medium text-muted-foreground">Manage grade levels and classroom divisions</p>
          </div>
        </div>

        <form 
          onsubmit={(e) => {
            e.preventDefault();
            if (!newClass.trim() || loading) return;
            handleCreate('classes', { name: newClass.trim() });
            newClass = '';
          }}
          class="flex space-x-2"
        >
          <input 
            type="text" 
            placeholder="e.g. JSS 2 or Grade 10" 
            bind:value={newClass}
            class="flex-1 bg-muted/30 border border-border rounded-xl px-4 py-2.5 text-sm font-medium text-card-foreground placeholder:text-muted-foreground focus:bg-card focus:ring-2 focus:ring-ring focus:border-primary outline-none transition-all"
          />
          <button 
            type="submit"
            disabled={loading || !newClass.trim()}
            class="bg-primary hover:bg-primary/90 text-white px-5 py-2.5 rounded-xl text-sm font-bold transition-all shadow-sm hover:shadow disabled:opacity-50"
          >
            Add Class
          </button>
        </form>

        <!-- Class Search Bar -->
        {#if classes.length > 3}
          <div class="relative">
            <input
              type="text"
              placeholder="Search classes..."
              bind:value={classSearch}
              class="w-full bg-muted/50 border border-border rounded-xl pl-8 pr-7 py-1.5 text-xs font-semibold text-card-foreground placeholder:text-muted-foreground focus:bg-card focus:border-primary focus:ring-1 focus:ring-ring outline-none transition-all"
            />
            <svg class="w-3.5 h-3.5 text-muted-foreground absolute left-2.5 top-2.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
            {#if classSearch}
              <button
                type="button"
                onclick={() => classSearch = ''}
                class="absolute right-2 top-2 text-muted-foreground hover:text-muted-foreground p-0.5"
                title="Clear search"
              >
                <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            {/if}
          </div>
        {/if}

        <div class="flex flex-wrap gap-2.5 pt-1">
          {#each filteredClasses as c (c.id)}
            <div 
              class="group bg-muted hover:bg-slate-200/80 text-foreground pl-3 pr-1.5 py-1.5 rounded-xl text-xs font-bold border border-border flex items-center space-x-2 transition-all shadow-sm"
            >
              <span class="w-1.5 h-1.5 rounded-full bg-primary"></span>
              <span>{c.name}</span>
              <div class="flex items-center space-x-0.5 border-l border-border/80 pl-1.5">
                <button
                  type="button"
                  onclick={() => editingItem = { type: 'class', id: c.id, name: c.name }}
                  class="p-1 text-muted-foreground hover:text-primary rounded-lg hover:bg-accent transition-colors"
                  title="Edit Class Name"
                >
                  <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z" />
                  </svg>
                </button>
                <button
                  type="button"
                  onclick={() => handleDeleteClass(c.id, c.name)}
                  class="p-1 text-muted-foreground hover:text-destructive rounded-lg hover:bg-accent transition-colors"
                  title="Delete Class"
                >
                  <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
            </div>
          {/each}
          {#if classes.length === 0}
            <p class="text-xs text-muted-foreground italic">No classes defined yet.</p>
          {/if}
          {#if classes.length > 0 && filteredClasses.length === 0}
            <p class="text-xs text-muted-foreground italic py-1">
              No class matching <span class="font-bold text-foreground/80">"{classSearch}"</span> found.
            </p>
          {/if}
        </div>
      </div>

      <!-- Subjects Box -->
      <div class="bg-card rounded-2xl shadow-sm border border-border p-6 space-y-5">
        <div class="flex items-center space-x-3">
          <div class="w-9 h-9 rounded-xl bg-blue-50 text-blue-700 flex items-center justify-center font-bold text-sm">
            <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
            </svg>
          </div>
          <div>
            <h3 class="text-lg font-extrabold text-card-foreground">Master Subject Catalog</h3>
            <p class="text-xs font-medium text-muted-foreground">Global disciplines taught across the school</p>
          </div>
        </div>

        <form 
          onsubmit={(e) => {
            e.preventDefault();
            if (!newSubject.trim() || loading) return;
            handleCreate('subjects', { name: newSubject.trim() });
            newSubject = '';
          }}
          class="flex space-x-2"
        >
          <input 
            type="text" 
            placeholder="e.g. Chemistry or Economics" 
            bind:value={newSubject}
            class="flex-1 bg-muted/30 border border-border rounded-xl px-4 py-2.5 text-sm font-medium text-card-foreground placeholder:text-muted-foreground focus:bg-card focus:ring-2 focus:ring-ring focus:border-primary outline-none transition-all"
          />
          <button 
            type="submit"
            disabled={loading || !newSubject.trim()}
            class="bg-primary hover:bg-primary/90 text-white px-5 py-2.5 rounded-xl text-sm font-bold transition-all shadow-sm hover:shadow disabled:opacity-50"
          >
            Add Subject
          </button>
        </form>

        <!-- Subject Search Bar -->
        <div class="flex items-center justify-between gap-2 pt-1">
          <div class="relative flex-1">
            <input
              type="text"
              placeholder="Search catalog subjects (e.g. Math, Physics)..."
              bind:value={subjectSearch}
              class="w-full bg-muted/50 border border-border rounded-xl pl-8 pr-7 py-1.5 text-xs font-semibold text-card-foreground placeholder:text-muted-foreground focus:bg-card focus:border-primary focus:ring-1 focus:ring-ring outline-none transition-all"
            />
            <svg class="w-3.5 h-3.5 text-muted-foreground absolute left-2.5 top-2.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
            {#if subjectSearch}
              <button
                type="button"
                onclick={() => subjectSearch = ''}
                class="absolute right-2 top-2 text-muted-foreground hover:text-muted-foreground p-0.5"
                title="Clear search"
              >
                <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            {/if}
          </div>
          <span class="text-[11px] font-bold text-muted-foreground whitespace-nowrap bg-muted px-2.5 py-1 rounded-lg border border-border">
            {filteredSubjects.length} of {subjects.length}
          </span>
        </div>

        <div class="flex flex-wrap gap-2.5 pt-1">
          {#each filteredSubjects as s (s.id)}
            <div 
              class="group bg-blue-50 hover:bg-blue-100 text-blue-900 pl-3 pr-1.5 py-1.5 rounded-xl text-xs font-bold border border-blue-200 flex items-center space-x-2 transition-all shadow-sm"
            >
              <span class="w-1.5 h-1.5 rounded-full bg-primary"></span>
              <span>{s.name}</span>
              <div class="flex items-center space-x-0.5 border-l border-blue-200 pl-1.5">
                <button
                  type="button"
                  onclick={() => editingItem = { type: 'subject', id: s.id, name: s.name }}
                  class="p-1 text-primary/70 hover:text-primary rounded-lg hover:bg-accent transition-colors"
                  title="Edit Subject Name"
                >
                  <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z" />
                  </svg>
                </button>
                <button
                  type="button"
                  onclick={() => handleDeleteSubject(s.id, s.name)}
                  class="p-1 text-primary/70 hover:text-destructive rounded-lg hover:bg-accent transition-colors"
                  title="Delete Subject"
                >
                  <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
            </div>
          {/each}
          {#if subjects.length === 0}
            <p class="text-xs text-muted-foreground italic">No subjects defined yet.</p>
          {/if}
          {#if subjects.length > 0 && filteredSubjects.length === 0}
            <div class="w-full bg-muted/50 border border-dashed border-border rounded-xl p-3 text-center">
              <p class="text-xs text-muted-foreground">
                No subject matching <span class="font-bold text-foreground">"{subjectSearch}"</span> found in the catalog.
              </p>
              <button
                type="button"
                onclick={() => {
                  handleCreate('subjects', { name: subjectSearch.trim() });
                  subjectSearch = '';
                }}
                class="mt-2 text-xs font-bold text-primary hover:text-primary bg-blue-50 px-3 py-1 rounded-lg border border-blue-200 inline-flex items-center space-x-1"
              >
                <span>+ Add "{subjectSearch.trim()}" now</span>
              </button>
            </div>
          {/if}
        </div>
      </div>
    </div>

    <!-- Middle Section: Smart Curriculum Mapping & Multi-Cohort Offerings -->
    <div class="bg-card rounded-3xl shadow-sm border border-border p-6 sm:p-7 space-y-6">
      <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 border-b border-border/50 pb-5">
        <div class="flex items-center space-x-3.5">
          <div class="w-10 h-10 rounded-2xl bg-primary/10 text-emerald-700 flex items-center justify-center font-bold text-base shadow-sm">
            <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
            </svg>
          </div>
          <div>
            <h3 class="text-xl font-black text-card-foreground tracking-tight">Curriculum Mapping & Subject Offerings</h3>
            <p class="text-xs font-semibold text-muted-foreground mt-0.5">
              Batch-assign subjects across cohorts (e.g. JSS 1 - 3) or replicate entire grade-level curriculums in 1-click
            </p>
          </div>
        </div>

        <!-- Mode Switcher Tabs -->
        <div class="flex bg-muted p-1 rounded-xl border border-border text-xs font-bold self-stretch sm:self-auto">
          <button
            type="button"
            onclick={() => offeringMode = 'bulk'}
            class="flex-1 sm:flex-initial px-4 py-2 rounded-lg transition-all flex items-center justify-center space-x-1.5 {offeringMode === 'bulk' ? 'bg-card text-primary shadow-sm' : 'text-muted-foreground hover:text-card-foreground'}"
          >
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
            </svg>
            <span>Multi-Class Bulk Enroller</span>
          </button>
          <button
            type="button"
            onclick={() => offeringMode = 'clone'}
            class="flex-1 sm:flex-initial px-4 py-2 rounded-lg transition-all flex items-center justify-center space-x-1.5 {offeringMode === 'clone' ? 'bg-card text-primary shadow-sm' : 'text-muted-foreground hover:text-card-foreground'}"
          >
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7v8a2 2 0 002 2h6M8 7V5a2 2 0 012-2h4.586a1 1 0 01.707.293l4.414 4.414a1 1 0 01.293.707V15a2 2 0 01-2 2h-2M8 7H6a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2v-2" />
            </svg>
            <span>Replicate / Clone Class</span>
          </button>
          <button
            type="button"
            onclick={() => offeringMode = 'single'}
            class="flex-1 sm:flex-initial px-4 py-2 rounded-lg transition-all flex items-center justify-center space-x-1.5 {offeringMode === 'single' ? 'bg-card text-primary shadow-sm' : 'text-muted-foreground hover:text-card-foreground'}"
          >
            <span>Single Offering</span>
          </button>
        </div>
      </div>


      <!-- MODE 1: BULK MULTI-CLASS ENROLLER -->
      {#if offeringMode === 'bulk'}
        <div class="bg-muted/30 p-6 rounded-2xl border border-border space-y-6">
          <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
            <div>
              <h4 class="text-sm font-black text-card-foreground uppercase tracking-wide">
                Step 1: Select Target Cohorts / Classes
              </h4>
              <p class="text-xs font-medium text-muted-foreground">
                Select multiple classes that share the same curriculum (e.g. JSS 1, JSS 2, JSS 3)
              </p>
            </div>
            <div class="flex space-x-2">
              <button
                type="button"
                onclick={() => bulkClassIds = classes.map((c: any) => c.id)}
                class="text-xs font-bold text-primary bg-primary/10 hover:bg-primary/20 px-2.5 py-1 rounded-lg transition-colors"
              >
                Select All Classes
              </button>
              <button
                type="button"
                onclick={() => bulkClassIds = []}
                class="text-xs font-bold text-muted-foreground hover:bg-slate-200/70 px-2.5 py-1 rounded-lg transition-colors"
              >
                Clear
              </button>
            </div>
          </div>

          <!-- Class Selection Badges -->
          <div class="flex flex-wrap gap-2">
            {#each classes as c (c.id)}
              {@const selected = bulkClassIds.includes(c.id)}
              <button
                type="button"
                onclick={() => toggleBulkClass(c.id)}
                class="px-4 py-2 rounded-xl text-xs font-extrabold border transition-all flex items-center space-x-2 shadow-sm {selected ? 'bg-primary text-white border-primary ring-2 ring-ring' : 'bg-card text-foreground/80 border-border hover:border-primary hover:bg-muted'}"
              >
                <span class="w-2 h-2 rounded-full {selected ? 'bg-card' : 'bg-slate-400'}"></span>
                <span>{c.name}</span>
              </button>
            {/each}
          </div>

          <div class="border-t border-border pt-5 space-y-4">
            <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
              <div>
                <h4 class="text-sm font-black text-card-foreground uppercase tracking-wide">
                  Step 2: Select Subjects & Frequency Tier
                </h4>
                <p class="text-xs font-medium text-muted-foreground">
                  Pick the subjects taught in these classes and their weekly frequency priority
                </p>
              </div>
              <div class="flex items-center space-x-3">
                <div class="flex items-center space-x-2">
                  <span class="text-xs font-bold text-muted-foreground">Default Tier:</span>
                  <select
                    bind:value={bulkDefaultTier}
                    class="bg-card border border-border rounded-lg px-2.5 py-1 text-xs font-bold text-card-foreground outline-none focus:border-primary"
                  >
                    <option value={3}>Tier 3 (Core - High Frequency)</option>
                    <option value={2}>Tier 2 (Standard Frequency)</option>
                    <option value={1}>Tier 1 (Elective / Low)</option>
                  </select>
                </div>
                <button
                  type="button"
                  onclick={() => bulkSelectedSubjectIds = subjects.map((s: any) => s.id)}
                  class="text-xs font-bold text-primary bg-primary/10 hover:bg-primary/20 px-2.5 py-1 rounded-lg transition-colors"
                >
                  Select All
                </button>
                <button
                  type="button"
                  onclick={() => bulkSelectedSubjectIds = []}
                  class="text-xs font-bold text-muted-foreground hover:bg-slate-200/70 px-2.5 py-1 rounded-lg transition-colors"
                >
                  Clear
                </button>
              </div>
            </div>

            <!-- Subject Multi-Select Badges -->
            <div class="flex flex-wrap gap-2">
              {#each subjects as s (s.id)}
                {@const selected = bulkSelectedSubjectIds.includes(s.id)}
                <button
                  type="button"
                  onclick={() => toggleBulkSubject(s.id)}
                  class="px-3.5 py-2 rounded-xl text-xs font-extrabold border transition-all flex items-center space-x-2 shadow-sm {selected ? 'bg-primary text-white border-primary ring-2 ring-ring' : 'bg-card text-foreground/80 border-border hover:border-primary/50 hover:bg-muted'}"
                >
                  <span class="w-2 h-2 rounded-full {selected ? 'bg-card' : 'bg-slate-400'}"></span>
                  <span>{s.name}</span>
                </button>
              {/each}
            </div>
          </div>

          <!-- Action Bar -->
          <div class="pt-3 border-t border-border flex flex-col sm:flex-row items-center justify-between gap-4">
            <div class="text-xs font-bold text-foreground/80">
              Ready to assign <span class="text-blue-700 font-extrabold">{bulkSelectedSubjectIds.length} subjects</span> to <span class="text-emerald-700 font-extrabold">{bulkClassIds.length} cohorts</span> ({bulkSelectedSubjectIds.length * bulkClassIds.length} total possible pairings).
            </div>
            <button
              type="button"
              onclick={handleBulkEnroll}
              disabled={loading || bulkClassIds.length === 0 || bulkSelectedSubjectIds.length === 0}
              class="w-full sm:w-auto bg-primary hover:bg-primary/90 text-white px-7 py-3 rounded-xl text-sm font-extrabold shadow-md hover:shadow-lg transition-all disabled:opacity-50 flex items-center justify-center space-x-2"
            >
              <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
              </svg>
              <span>Enroll {bulkClassIds.length} Classes in {bulkSelectedSubjectIds.length} Subjects</span>
            </button>
          </div>
        </div>
      {/if}

      <!-- MODE 2: REPLICATE / CLONE CURRICULUM -->
      {#if offeringMode === 'clone'}
        <div class="bg-muted/30 p-6 rounded-2xl border border-border space-y-6">
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-6">
            <!-- Source Class -->
            <div class="space-y-2">
              <SearchableSelect
                label="1. Source Class (Replicate From)"
                bind:value={cloneSourceClass}
                placeholder="Type or select source class..."
                options={classes.map((c: any) => ({
                  value: c.id,
                  label: c.name,
                  subLabel: `${class_subjects.filter((cs: any) => cs.class_id === c.id).length} enrolled subjects`,
                }))}
              />
              <p class="text-xs text-muted-foreground font-medium">
                All subject offerings and tier weights from this class will be copied.
              </p>
            </div>

            <!-- Options -->
            <div class="space-y-3">
              <label class="block text-xs font-extrabold uppercase tracking-wider text-foreground/80">
                2. Configuration Options
              </label>
              <label class="flex items-center space-x-3 bg-card p-3 rounded-xl border border-border cursor-pointer hover:border-border">
                <input
                  type="checkbox"
                  bind:checked={cloneCopyTeachers}
                  class="w-4 h-4 text-primary rounded focus:ring-violet-500 border-border"
                />
                <div>
                  <p class="text-xs font-bold text-card-foreground">Also copy faculty assignments</p>
                  <p class="text-[11px] text-muted-foreground">Teachers authorized for the source class will automatically be authorized for the target classes.</p>
                </div>
              </label>
            </div>
          </div>

          <!-- Target Classes -->
          <div class="border-t border-border pt-5 space-y-3">
            <div class="flex justify-between items-center">
              <label class="block text-xs font-extrabold uppercase tracking-wider text-foreground/80">
                3. Select Target Classes (Replicate To)
              </label>
              <div class="flex space-x-2">
                <button
                  type="button"
                  onclick={() => cloneTargetClasses = classes.filter((c: any) => c.id !== cloneSourceClass).map((c: any) => c.id)}
                  class="text-xs font-bold text-primary bg-primary/10 hover:bg-primary/20 px-2.5 py-1 rounded-lg transition-colors"
                >
                  Select All Others
                </button>
                <button
                  type="button"
                  onclick={() => cloneTargetClasses = []}
                  class="text-xs font-bold text-muted-foreground hover:bg-slate-200/70 px-2.5 py-1 rounded-lg transition-colors"
                >
                  Clear
                </button>
              </div>
            </div>

            <div class="flex flex-wrap gap-2">
              {#each classes.filter((c: any) => c.id !== cloneSourceClass) as c (c.id)}
                {@const selected = cloneTargetClasses.includes(c.id)}
                {@const count = class_subjects.filter((cs: any) => cs.class_id === c.id).length}
                <button
                  type="button"
                  onclick={() => toggleCloneTarget(c.id)}
                  class="px-4 py-2.5 rounded-xl text-xs font-extrabold border transition-all flex items-center space-x-2 shadow-sm {selected ? 'bg-primary text-white border-primary ring-2 ring-ring' : 'bg-card text-foreground/80 border-border hover:border-primary/50 hover:bg-muted'}"
                >
                  <span class="w-2 h-2 rounded-full {selected ? 'bg-card' : 'bg-slate-400'}"></span>
                  <span>{c.name}</span>
                  <span class="text-[10px] px-1.5 py-0.5 rounded-md {selected ? 'bg-primary/90 text-violet-100' : 'bg-muted text-muted-foreground'}">
                    {count} curr
                  </span>
                </button>
              {/each}
            </div>
          </div>

          <!-- Replicate Button -->
          <div class="pt-3 border-t border-border flex justify-end">
            <button
              type="button"
              onclick={handleCloneCurriculum}
              disabled={loading || !cloneSourceClass || cloneTargetClasses.length === 0}
              class="w-full sm:w-auto bg-primary hover:bg-primary/90 text-white px-8 py-3 rounded-xl text-sm font-extrabold shadow-md hover:shadow-lg transition-all disabled:opacity-50 flex items-center justify-center space-x-2"
            >
              <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7v8a2 2 0 002 2h6M8 7V5a2 2 0 012-2h4.586a1 1 0 01.707.293l4.414 4.414a1 1 0 01.293.707V15a2 2 0 01-2 2h-2M8 7H6a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2v-2" />
              </svg>
              <span>Replicate Curriculum to {cloneTargetClasses.length} Target Classes</span>
            </button>
          </div>
        </div>
      {/if}

      <!-- MODE 3: SINGLE OFFERING CREATOR -->
      {#if offeringMode === 'single'}
        <div class="grid grid-cols-1 sm:grid-cols-4 gap-3 bg-muted/50/70 p-4 rounded-xl border border-border">
          <div>
            <SearchableSelect
              label="Target Class"
              bind:value={csClass}
              placeholder="Type or select class..."
              options={classes.map((c: any) => ({
                value: c.id,
                label: c.name,
                subLabel: `${class_subjects.filter((cs: any) => cs.class_id === c.id).length} active subjects`,
              }))}
            />
          </div>

          <div>
            <SearchableSelect
              label="Subject Offering"
              bind:value={csSubject}
              placeholder="Type or select subject..."
              options={subjects.map((s: any) => ({
                value: s.id,
                label: s.name,
              }))}
            />
          </div>

          <div>
            <label class="block text-xs font-bold text-muted-foreground mb-1">Priority Tier</label>
            <select 
              bind:value={csTier} 
              class="w-full bg-card border border-border rounded-xl px-3.5 py-2.5 text-sm font-semibold text-card-foreground outline-none focus:ring-2 focus:ring-ring focus:border-primary"
            >
              <option value={3}>Tier 3 (Core - High Frequency)</option>
              <option value={2}>Tier 2 (Standard Frequency)</option>
              <option value={1}>Tier 1 (Elective / Low)</option>
            </select>
          </div>

          <div class="flex items-end">
            <button 
              onclick={() => handleCreate('class-subjects', { class_id: csClass, subject_id: csSubject, tier: csTier })}
              disabled={loading || !csClass || !csSubject}
              class="w-full bg-primary hover:bg-primary/90 text-white px-5 py-2.5 rounded-xl text-sm font-bold transition-all shadow-sm hover:shadow whitespace-nowrap disabled:opacity-50"
            >
              + Create Offering
            </button>
          </div>
        </div>
      {/if}

      <!-- Offerings Header & Filter Bar -->
      <div class="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 pt-2 pb-1 border-b border-border">
        <div class="flex flex-wrap items-center gap-2.5">
          <div class="w-64">
            <SearchableSelect
              bind:value={offeringClassFilter}
              placeholder="Search / filter by class..."
              options={[
                { value: 'ALL', label: 'All Cohorts', subLabel: `${class_subjects.length} total offerings` },
                ...classes.map((c: any) => ({
                  value: c.id,
                  label: c.name,
                  subLabel: `${class_subjects.filter((cs: any) => cs.class_id === c.id).length} subjects`,
                })),
              ]}
            />
          </div>

          <!-- Quick Action: Clear Offerings for Selected Class -->
          {#if offeringClassFilter !== 'ALL'}
            <button
              type="button"
              onclick={() => handleDeleteAllForClass(offeringClassFilter, getClassName(offeringClassFilter))}
              class="text-xs font-bold text-rose-700 bg-rose-50 hover:bg-rose-100 border border-rose-200 px-3 py-1.5 rounded-xl transition-all flex items-center space-x-1.5 shadow-sm"
              title="Wipe all subject offerings for this specific class"
            >
              <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
              </svg>
              <span>Clear All for {getClassName(offeringClassFilter)}</span>
            </button>
          {/if}
        </div>

        <div class="flex flex-wrap items-center gap-3">
          <span class="text-xs font-bold text-muted-foreground bg-muted px-2.5 py-1 rounded-lg">
            Showing {displayedClassSubjects.length} of {class_subjects.length} mapped pairings
          </span>

          <!-- Global Wipe Offerings Button -->
          {#if class_subjects.length > 0}
            <button
              type="button"
              onclick={handleDeleteAllOfferings}
              class="text-xs font-extrabold text-destructive hover:text-red-700 bg-destructive/10 hover:bg-red-100/80 border border-red-200 px-3 py-1.5 rounded-xl transition-all flex items-center space-x-1.5 shadow-sm"
              title="Delete all offerings across the entire school"
            >
              <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
              <span>Delete All Offerings</span>
            </button>
          {/if}
        </div>
      </div>

      <!-- Bulk Selection Toolbar -->
      {#if displayedClassSubjects.length > 0}
        <div class="flex flex-wrap items-center justify-between gap-3 bg-muted/50/80 p-3 rounded-xl border border-border/80">
          <div class="flex items-center space-x-3">
            <label class="flex items-center space-x-2 cursor-pointer select-none">
              <input
                type="checkbox"
                checked={
                  displayedClassSubjects.length > 0 &&
                  displayedClassSubjects.every((cs: any) => selectedOfferingIds.includes(cs.id))
                }
                onchange={() => handleSelectAllDisplayedOfferings(displayedClassSubjects.map((cs: any) => cs.id))}
                class="w-4 h-4 text-primary rounded border-border focus:ring-indigo-500 cursor-pointer"
              />
              <span class="text-xs font-extrabold text-foreground/80">
                Select All Filtered ({displayedClassSubjects.length})
              </span>
            </label>

            {#if selectedOfferingIds.length > 0}
              <button
                type="button"
                onclick={() => selectedOfferingIds = []}
                class="text-xs font-bold text-muted-foreground hover:text-foreground underline transition-colors"
              >
                Clear Selection
              </button>
            {/if}
          </div>

          {#if selectedOfferingIds.length > 0}
            <div class="flex items-center space-x-3">
              <span class="text-xs font-extrabold text-rose-700 bg-rose-100 px-2.5 py-1 rounded-lg border border-rose-200">
                {selectedOfferingIds.length} offering{selectedOfferingIds.length > 1 ? 's' : ''} selected
              </span>
              <button
                type="button"
                onclick={handleDeleteBulkSelected}
                disabled={loading}
                class="bg-rose-600 hover:bg-rose-700 text-white text-xs font-extrabold px-4 py-2 rounded-xl shadow-sm hover:shadow transition-all flex items-center space-x-1.5 disabled:opacity-50"
              >
                <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                </svg>
                <span>Delete Selected ({selectedOfferingIds.length})</span>
              </button>
            </div>
          {/if}
        </div>
      {/if}

      <!-- Offerings Grid -->
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
        {#each displayedClassSubjects as cs (cs.id)}
          {@const className = getClassName(cs.class_id)}
          {@const subjectName = getSubjectName(cs.subject_id)}
          {@const isSelected = selectedOfferingIds.includes(cs.id)}

          <div
            class="bg-card border rounded-2xl p-4 shadow-sm transition-all flex flex-col justify-between group {isSelected ? 'border-destructive bg-destructive/10 ring-2 ring-destructive/20' : 'border-border hover:border-border'}"
          >
            <div>
              <div class="flex items-center justify-between mb-1.5">
                <label class="flex items-center space-x-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={isSelected}
                    onchange={() => toggleOfferingSelection(cs.id)}
                    class="w-4 h-4 text-rose-600 rounded border-border focus:ring-rose-500 cursor-pointer"
                  />
                  <span class="font-black text-card-foreground text-sm tracking-tight">{className}</span>
                </label>
                <button
                  type="button"
                  onclick={() => handleDeleteClassSubject(cs.id, className, subjectName)}
                  class="text-slate-300 hover:text-destructive p-1 rounded-lg hover:bg-destructive/10 transition-colors"
                  title="Remove Subject Offering"
                >
                  <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                  </svg>
                </button>
              </div>
              <p class="text-xs font-bold text-indigo-700 pl-6">{subjectName}</p>
            </div>

            <div class="mt-4 pt-3 border-t border-border/50 flex items-center justify-between pl-6">
              <span class="text-[11px] font-bold text-muted-foreground">Tier Priority</span>
              <select
                value={cs.tier}
                onchange={(e) => handleUpdateTier(cs.id, Number((e.target as HTMLSelectElement).value))}
                class="text-xs font-extrabold rounded-lg px-2 py-1 border outline-none cursor-pointer {cs.tier === 3 ? 'bg-indigo-50 text-indigo-700 border-indigo-200' : cs.tier === 2 ? 'bg-blue-50 text-blue-700 border-blue-200' : 'bg-muted/50 text-foreground/80 border-border'}"
              >
                <option value={3}>Tier 3 (Core)</option>
                <option value={2}>Tier 2 (Standard)</option>
                <option value={1}>Tier 1 (Elective)</option>
              </select>
            </div>
          </div>
        {/each}
        {#if displayedClassSubjects.length === 0}
          <div class="col-span-full py-8 text-center bg-muted/30 rounded-2xl border border-dashed border-border">
            <p class="text-xs text-muted-foreground font-medium">
              No subject offerings found for the selected filter. Use the Multi-Class Enroller or Replicate tab above to quickly assign subjects!
            </p>
          </div>
        {/if}
      </div>
    </div>


    <!-- Bottom Row: Master Teacher Qualifications -->
    <div class="bg-card rounded-2xl shadow-sm border border-border p-6 space-y-6">
      <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div class="flex items-center space-x-3">
          <div class="w-10 h-10 rounded-xl bg-violet-100/80 text-violet-700 flex items-center justify-center font-bold text-sm shadow-inner">
            <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
            </svg>
          </div>
          <div>
            <h3 class="text-lg font-extrabold text-card-foreground">Master Teacher Authorizations & Expertise</h3>
            <p class="text-xs font-medium text-muted-foreground">
              Grant permanent subject qualifications to faculty. Timetable solvers schedule teachers only for authorized offerings.
            </p>
          </div>
        </div>

        <!-- Mode Switcher -->
        <div class="bg-muted/90 p-1 rounded-xl flex space-x-1 border border-border/80 self-stretch sm:self-auto">
          <button
            type="button"
            onclick={() => taMode = 'bulk'}
            class="px-3.5 py-1.5 rounded-lg text-xs font-extrabold transition-all {taMode === 'bulk' ? 'bg-card text-primary shadow-xs border border-border' : 'text-muted-foreground hover:text-card-foreground'}"
          >
            Assign Multiple Offerings
          </button>
          <button
            type="button"
            onclick={() => taMode = 'single'}
            class="px-3.5 py-1.5 rounded-lg text-xs font-extrabold transition-all {taMode === 'single' ? 'bg-card text-primary shadow-xs border border-border' : 'text-muted-foreground hover:text-card-foreground'}"
          >
            Single Assignment
          </button>
        </div>
      </div>

      <!-- MODE 1: MULTI-OFFERING ASSIGNMENT FOR TEACHER -->
      {#if taMode === 'bulk'}
        <div class="bg-muted/30 p-6 rounded-2xl border border-border space-y-6">
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <!-- Teacher Selector -->
            <div>
              <SearchableSelect
                label="1. Select Faculty Member"
                bind:value={taTeacher}
                placeholder="Type teacher name..."
                options={teachers.map((t: any) => {
                  const count = assignments.filter((a: any) => a.teacher_id === t.id).length;
                  return {
                    value: t.id,
                    label: t.name,
                    subLabel: `${count} active qualifications`,
                    badge: t.is_absent ? 'Absent' : undefined,
                    badgeColor: 'bg-rose-100 text-rose-700',
                  };
                })}
              />
            </div>

            <!-- Offerings Real-Time Search -->
            <div>
              <label class="block text-xs font-bold text-foreground/80 mb-1">
                2. Search & Filter Offerings
              </label>
              <div class="relative">
                <input
                  type="text"
                  bind:value={taOfferingSearch}
                  placeholder="Search subject or class (e.g. Mathematics, JSS 1, Chemistry)..."
                  class="w-full bg-card border border-border rounded-xl pl-9 pr-8 py-2.5 text-xs font-bold text-card-foreground outline-none focus:ring-2 focus:ring-ring focus:border-primary shadow-sm"
                />
                <svg class="w-4 h-4 text-muted-foreground absolute left-3 top-1/2 -translate-y-1/2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                </svg>
                {#if taOfferingSearch}
                  <button
                    type="button"
                    onclick={() => taOfferingSearch = ''}
                    class="absolute right-2.5 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-muted-foreground p-0.5 rounded-md"
                    title="Clear search"
                  >
                    <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  </button>
                {/if}
              </div>
            </div>
          </div>

          <!-- Offerings Multi-Selection Area -->
          <div class="space-y-3 pt-2 border-t border-border">
            <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-2">
              <div class="flex items-center space-x-2">
                <label class="block text-xs font-extrabold uppercase tracking-wider text-foreground/80">
                  3. Select Offerings to Authorize ({taBulkSelectedOfferings.length} selected)
                </label>
                {#if taOfferingSearch.trim()}
                  <span class="text-[11px] font-bold text-violet-700 bg-violet-100/70 px-2 py-0.5 rounded-md">
                    Filtered: {class_subjects.filter((cs: any) => {
                      const q = taOfferingSearch.toLowerCase().trim();
                      return getClassName(cs.class_id).toLowerCase().includes(q) || getSubjectName(cs.subject_id).toLowerCase().includes(q);
                    }).length}
                  </span>
                {/if}
              </div>
              <div class="flex flex-wrap gap-2">
                <button
                  type="button"
                  onclick={() => {
                    const filteredIds = class_subjects
                      .filter((cs: any) => {
                        if (!taOfferingSearch.trim()) return true;
                        const q = taOfferingSearch.toLowerCase().trim();
                        return getClassName(cs.class_id).toLowerCase().includes(q) || getSubjectName(cs.subject_id).toLowerCase().includes(q);
                      })
                      .map((cs: any) => cs.id);
                    taBulkSelectedOfferings = Array.from(new Set([...taBulkSelectedOfferings, ...filteredIds]));
                  }}
                  class="text-xs font-bold text-primary bg-primary/10 hover:bg-primary/20 px-2.5 py-1 rounded-lg transition-colors"
                >
                  Select All Shown
                </button>
                <button
                  type="button"
                  onclick={() => taBulkSelectedOfferings = []}
                  class="text-xs font-bold text-muted-foreground hover:bg-slate-200/70 px-2.5 py-1 rounded-lg transition-colors"
                >
                  Clear Selection
                </button>
              </div>
            </div>

            <!-- Offerings Chips Grid -->
            <div class="flex flex-wrap gap-2 max-h-60 overflow-y-auto p-2 bg-card/60 rounded-xl border border-border">
              {#each class_subjects.filter((cs: any) => {
                if (!taOfferingSearch.trim()) return true;
                const q = taOfferingSearch.toLowerCase().trim();
                return getClassName(cs.class_id).toLowerCase().includes(q) || getSubjectName(cs.subject_id).toLowerCase().includes(q);
              }) as cs (cs.id)}
                {@const isSelected = taBulkSelectedOfferings.includes(cs.id)}
                {@const isAlreadyAssigned = assignments.some((a: any) => a.teacher_id === taTeacher && a.class_subject_id === cs.id)}

                <button
                  type="button"
                  onclick={() => {
                    if (taBulkSelectedOfferings.includes(cs.id)) {
                      taBulkSelectedOfferings = taBulkSelectedOfferings.filter(id => id !== cs.id);
                    } else {
                      taBulkSelectedOfferings = [...taBulkSelectedOfferings, cs.id];
                    }
                  }}
                  class="px-3 py-2 rounded-xl text-xs font-extrabold border transition-all flex items-center space-x-2 shadow-xs {isSelected ? 'bg-primary text-white border-primary ring-2 ring-ring' : isAlreadyAssigned ? 'bg-primary/10 text-primary border-primary' : 'bg-card text-foreground/80 border-border hover:border-primary/50 hover:bg-muted'}"
                >
                  <span class="w-2 h-2 rounded-full {isSelected ? 'bg-card' : isAlreadyAssigned ? 'bg-primary' : 'bg-slate-400'}"></span>
                  <span>{getClassName(cs.class_id)} — {getSubjectName(cs.subject_id)}</span>
                  {#if isAlreadyAssigned}
                    <span class="text-[10px] px-1.5 py-0.5 rounded-md {isSelected ? 'bg-primary/90 text-violet-100' : 'bg-emerald-100 text-primary'}">
                      ✓ Authorized
                    </span>
                  {/if}
                </button>
              {/each}
              {#if class_subjects.length === 0}
                <div class="py-6 text-center text-xs text-muted-foreground w-full">
                  No offerings found. Please enroll classes in subjects first.
                </div>
              {/if}
            </div>
          </div>

          <!-- Action Bar -->
          <div class="pt-3 border-t border-border flex flex-col sm:flex-row items-center justify-between gap-4">
            <div class="text-xs font-bold text-foreground/80">
              Authorizing <span class="text-violet-700 font-extrabold">{getTeacherName(taTeacher)}</span> for <span class="text-indigo-700 font-extrabold">{taBulkSelectedOfferings.length} offerings</span>.
            </div>
            <button
              type="button"
              onclick={handleBulkTeacherAuthorize}
              disabled={loading || !taTeacher || taBulkSelectedOfferings.length === 0}
              class="w-full sm:w-auto bg-primary hover:bg-primary/90 text-white px-7 py-3 rounded-xl text-sm font-extrabold shadow-md hover:shadow-lg transition-all disabled:opacity-50 flex items-center justify-center space-x-2"
            >
              <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
              </svg>
              <span>Authorize {taBulkSelectedOfferings.length} Offerings</span>
            </button>
          </div>
        </div>
      {/if}

      <!-- MODE 2: SINGLE ASSIGNMENT -->
      {#if taMode === 'single'}
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 bg-muted/50/70 p-4 rounded-xl border border-border">
          <div>
            <SearchableSelect
              label="Teacher"
              bind:value={taTeacher}
              placeholder="Search or select teacher..."
              options={teachers.map((t: any) => ({
                value: t.id,
                label: t.name,
                badge: t.is_absent ? 'Absent' : undefined,
                badgeColor: 'bg-rose-100 text-rose-700',
              }))}
            />
          </div>

          <div>
            <SearchableSelect
              label="Class Subject Offering"
              bind:value={taClassSubject}
              placeholder="Search class or subject..."
              options={class_subjects.map((cs: any) => ({
                value: cs.id,
                label: `${getClassName(cs.class_id)} — ${getSubjectName(cs.subject_id)}`,
                badge: `Tier ${cs.tier}`,
                badgeColor:
                  cs.tier === 3
                    ? 'bg-indigo-100 text-indigo-700'
                    : cs.tier === 2
                      ? 'bg-blue-100 text-blue-700'
                      : 'bg-muted text-foreground/80',
              }))}
            />
          </div>

          <div class="flex items-end">
            <button 
              onclick={() => handleCreate('teacher-assignments', { teacher_id: taTeacher, class_subject_id: taClassSubject })}
              disabled={loading || !taTeacher || !taClassSubject}
              class="w-full bg-primary hover:bg-primary/90 text-white px-5 py-2.5 rounded-xl text-sm font-bold transition-all shadow-sm hover:shadow whitespace-nowrap disabled:opacity-50"
            >
              + Authorize Teacher
            </button>
          </div>
        </div>
      {/if}

      <!-- Existing Qualifications Filter & List -->
      <div class="space-y-4 pt-2">
        <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 pb-2 border-b border-border">
          <div class="flex flex-wrap items-center gap-2.5">
            <div class="w-64">
              <SearchableSelect
                bind:value={taListFilterTeacher}
                placeholder="Filter by teacher..."
                options={[
                  { value: 'ALL', label: 'All Faculty Members', subLabel: `${assignments.length} total authorizations` },
                  ...teachers.map((t: any) => ({
                    value: t.id,
                    label: t.name,
                    subLabel: `${assignments.filter((a: any) => a.teacher_id === t.id).length} qualifications`,
                  })),
                ]}
              />
            </div>

            {#if taListFilterTeacher !== 'ALL'}
              <button
                type="button"
                onclick={() => handleClearAllQualificationsForTeacher(taListFilterTeacher, getTeacherName(taListFilterTeacher))}
                class="text-xs font-bold text-rose-700 bg-rose-50 hover:bg-rose-100 border border-rose-200 px-3 py-1.5 rounded-xl transition-all flex items-center space-x-1.5 shadow-sm"
                title="Clear all qualifications for this teacher"
              >
                <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                </svg>
                <span>Clear All for {getTeacherName(taListFilterTeacher)}</span>
              </button>
            {/if}
          </div>

          <span class="text-xs font-bold text-muted-foreground">
            Showing {assignments.filter((a: any) => taListFilterTeacher === 'ALL' || a.teacher_id === taListFilterTeacher).length} of {assignments.length} active authorizations
          </span>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {#each assignments.filter((a: any) => taListFilterTeacher === 'ALL' || a.teacher_id === taListFilterTeacher) as a (a.id)}
            {@const cs = class_subjects.find((c: any) => c.id === a.class_subject_id)}
            {#if cs}
              <div class="bg-card border border-border rounded-2xl p-4 flex items-center justify-between shadow-sm hover:border-border transition-all group">
                <div class="flex items-center space-x-3.5">
                  <div class="w-10 h-10 rounded-xl bg-muted flex items-center justify-center text-indigo-700 font-extrabold text-sm shadow-inner">
                    {getTeacherName(a.teacher_id).charAt(0)}
                  </div>
                  <div>
                    <p class="font-bold text-card-foreground text-sm">{getTeacherName(a.teacher_id)}</p>
                    <p class="text-xs font-semibold text-muted-foreground mt-0.5">
                      {getClassName(cs.class_id)} • <span class="text-primary">{getSubjectName(cs.subject_id)}</span>
                    </p>
                  </div>
                </div>
                <button 
                  onclick={() => deleteAssignment(a.id)}
                  class="text-muted-foreground hover:text-destructive hover:bg-destructive/10 p-2 rounded-xl transition-all"
                  title="Remove Qualification"
                >
                  <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                  </svg>
                </button>
              </div>
            {/if}
          {/each}
          {#if assignments.filter((a: any) => taListFilterTeacher === 'ALL' || a.teacher_id === taListFilterTeacher).length === 0}
            <div class="col-span-full py-8 text-center bg-muted/30 rounded-2xl border border-dashed border-border">
              <p class="text-xs text-muted-foreground font-medium">
                No teacher authorizations found for this filter. Use the tool above to authorize faculty in bulk!
              </p>
            </div>
          {/if}
        </div>
      </div>
    </div>

    <!-- Edit Class / Subject Modal -->
    {#if editingItem}
      <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-gray-900/50 backdrop-blur-sm">
        <div class="bg-card rounded-3xl shadow-2xl w-full max-w-md overflow-hidden border border-border">
          <div class="p-6 border-b border-border/50 bg-muted/50/60 flex justify-between items-center">
            <div>
              <h3 class="text-lg font-black text-card-foreground">
                Edit {editingItem.type === 'class' ? 'Class Name' : 'Subject Name'}
              </h3>
              <p class="text-xs font-semibold text-muted-foreground mt-0.5">
                Update identifier across all curriculums
              </p>
            </div>
            <button
              onclick={() => editingItem = null}
              class="text-muted-foreground hover:text-muted-foreground p-1.5 rounded-xl hover:bg-muted transition-colors"
            >
              <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <form onsubmit={handleUpdate} class="p-6 space-y-4">
            <div>
              <label class="block text-xs font-bold uppercase tracking-wider text-foreground/80 mb-1.5">
                {editingItem.type === 'class' ? 'Class / Cohort Name' : 'Subject Name'}
              </label>
              <input
                type="text"
                autofocus
                bind:value={editingItem.name}
                class="w-full bg-muted/50 border border-border px-4 py-2.5 rounded-xl text-sm font-semibold text-card-foreground focus:bg-card focus:ring-2 focus:ring-ring focus:border-primary outline-none transition-all"
                required
              />
            </div>

            <div class="flex justify-end space-x-3 pt-3 border-t border-border/50">
              <button
                type="button"
                onclick={() => editingItem = null}
                class="px-4 py-2 text-xs font-bold text-muted-foreground hover:bg-muted rounded-xl transition-colors"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={loading || !editingItem.name.trim()}
                class="bg-primary hover:bg-primary/90 text-white px-5 py-2.5 rounded-xl text-xs font-bold shadow-sm transition-all hover:shadow disabled:opacity-50"
              >
                {loading ? 'Saving...' : 'Save Changes'}
              </button>
            </div>
          </form>
        </div>
      </div>
    {/if}
  </div>
{/if}

