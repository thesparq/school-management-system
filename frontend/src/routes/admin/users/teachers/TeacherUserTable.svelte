<script lang="ts">
	import { onMount } from 'svelte';
	import AppButton from '$lib/components/ui/app-button.svelte';
	import { Badge } from '$lib/components/ui/badge';
	import { Input } from '$lib/components/ui/input';
	import { Label } from '$lib/components/ui/label';
	import PageSkeleton from '$lib/components/ui/skeleton/PageSkeleton.svelte';
	import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
	import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '$lib/components/ui/table';
	import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';
	import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '$lib/components/ui/dialog';
	import PassportUpload from '../users-shared/PassportUpload.svelte';
	import NameFields from '../users-shared/NameFields.svelte';
	import CredentialsSelect from '../users-shared/CredentialsSelect.svelte';
	import SearchSelect from '$lib/components/ui/search-select/search-select.svelte';
	import { addToast } from '$lib/stores/toast';
import type { UserRow } from '$lib/types/user';
import type { TeacherSubjectPair } from '$lib/types';

	let {
		users = $bindable([] as UserRow[]),
		allGroups = $bindable([] as { pk: string; name: string }[]),
		showCreateDialog = $bindable(false),
		groupPk = '',
		hasError = false,
		errorMessage = ''
	} = $props();

	let hasUsers = $derived(users.length > 0);
	let authStates = $state<Record<number, string>>({});

	let createForm = $state({ username: '', surname: '', firstName: '', middleName: '', email: '', password: '', showPassword: false, dateEmployed: '', qualifications: [] as string[], isActive: true });
	let createLoading = $state(false);
	let createError = $state('');
	let passportFile = $state<File | null>(null);
	let passportUpload: PassportUpload | undefined = $state();

	let editForm = $state({ uuid: '', authentikPk: 0, username: '', surname: '', firstName: '', middleName: '', email: '', password: '', showPassword: false, dateEmployed: '', qualifications: [] as string[], currentPassport: '' });
	let editLoading = $state(false);
	let editError = $state('');
	let editDialogOpen = $state(false);
	let editProfileLoading = $state(false);
	let editPassportFile = $state<File | null>(null);
	let editPassportUpload: PassportUpload | undefined = $state();

	let deleteTarget = $state<{ pk: number; uuid: string; name: string } | null>(null);
	let deleteLoading = $state(false);
	let deleteError = $state('');
	let deleteDialogOpen = $state(false);

	// Class assign dialog (teacher-specific)
	let classAssignDialogOpen = $state(false);
	let classAssignTeacherUuid = $state('');
	let classAssignTeacherPk = $state(0);
	let allSubjectPairs = $state<TeacherSubjectPair[]>([]);
	let subjectPairsLoading = $state(true);
	let currentTeacherPairs = $state<Record<number, TeacherSubjectPair[]>>({});
	let selectedSubjectPair = $state<Record<number, TeacherSubjectPair | null>>({});
	let subjectPairSearch = $state<Record<number, string>>({});
	let teacherSubjectLoading = $state<Record<number, string>>({});
	let teacherPairsLoading = $state<Record<number, boolean>>({});
	let activeSessionTerm = $state<{ id: string; session_name: string; term_name: string } | null>(null);
	let activeSessionTermLoading = $state(false);

	let displayName = $derived([createForm.surname, createForm.firstName, createForm.middleName].filter(Boolean).join(' '));
	let editDisplayName = $derived([editForm.surname, editForm.firstName, editForm.middleName].filter(Boolean).join(' '));

	function generatePassword(): string {
		const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
		let pw = ''; const arr = new Uint8Array(16); crypto.getRandomValues(arr);
		for (let i = 0; i < 16; i++) pw += chars[arr[i] % chars.length];
		return pw;
	}
	function handleRetry() { window.location.reload(); }
	function closeCreate() { showCreateDialog = false; createError = ''; passportFile = null; createForm = { username: '', surname: '', firstName: '', middleName: '', email: '', password: '', showPassword: false, dateEmployed: '', qualifications: [], isActive: true }; }
	function closeEdit() { editDialogOpen = false; editError = ''; editPassportFile = null; }

	onMount(async () => { try { const res = await fetch('/api/admin/class-subjects'); const body = await res.json(); allSubjectPairs = body?.data ?? []; } catch { allSubjectPairs = []; addToast('error', 'Failed to load class-subjects', ''); } finally { subjectPairsLoading = false; } });

	async function handleCreate() {
		createLoading = true; createError = '';
		try {
			let passportUrl = '';
			if (passportFile && passportUpload) { const url = await passportUpload.getPassportPublicUrl(passportFile, 'teacher', ''); if (!url) { createLoading = false; return; } passportUrl = url; }
			const body = { username: createForm.username, surname: createForm.surname, first_name: createForm.firstName, middle_name: createForm.middleName || undefined, display_name: displayName, email: createForm.email, password: createForm.password, is_active: createForm.isActive, group_pk: groupPk, role: 'teacher', qualifications: createForm.qualifications.length > 0 ? createForm.qualifications : undefined, date_employed: createForm.dateEmployed || undefined, passport_url: passportUrl };
			const res = await fetch('/api/admin/users', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
			const result = await res.json();
			if (result.error) throw new Error(result.error.message ?? 'Failed');
			const u = result.data; users = [...users, { pk: u.pk, uuid: u.uuid, username: u.username, name: u.name, email: u.email, groups: u.groups, is_active: u.is_active }];
			addToast('success', 'Teacher created', createForm.username); closeCreate();
		} catch (e) { createError = e instanceof Error ? e.message : 'Failed'; addToast('error', 'Create failed', createError); }
		finally { createLoading = false; }
	}

	async function handleEdit() {
		editLoading = true; editError = '';
		try {
			let passportUrl = editForm.currentPassport;
			if (editPassportFile && editPassportUpload) { const url = await editPassportUpload.getPassportPublicUrl(editPassportFile, 'teacher', editForm.uuid); if (!url) { editLoading = false; return; } passportUrl = url; }
			const body = { authentik_pk: editForm.authentikPk, username: editForm.username, surname: editForm.surname, first_name: editForm.firstName, middle_name: editForm.middleName || undefined, display_name: editDisplayName, email: editForm.email, password: editForm.password || undefined, role: 'teacher', qualifications: editForm.qualifications.length > 0 ? editForm.qualifications : undefined, date_employed: editForm.dateEmployed || undefined, passport_url: passportUrl };
			const res = await fetch(`/api/admin/users/${editForm.uuid}/edit-profile`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
			const result = await res.json();
			if (result.error) throw new Error(result.error.message ?? 'Failed');
			users = users.map(u => u.uuid === editForm.uuid ? { ...u, username: editForm.username, name: editDisplayName, email: editForm.email } : u);
			addToast('success', 'Teacher updated', editForm.username); closeEdit();
		} catch (e) { editError = e instanceof Error ? e.message : 'Failed'; addToast('error', 'Edit failed', editError); }
		finally { editLoading = false; }
	}

	async function handleDelete() { if (!deleteTarget) return; deleteLoading = true; deleteError = ''; try { const res = await fetch(`/api/admin/users/${deleteTarget.pk}?uuid=${deleteTarget.uuid}&role=teacher`, { method: 'DELETE' }); const result = await res.json(); if (result.error) throw new Error(result.error.message ?? 'Failed'); users = users.filter(u => u.pk !== deleteTarget!.pk); addToast('success', 'Teacher deleted', deleteTarget!.name); deleteDialogOpen = false; deleteTarget = null; } catch (e) { deleteError = e instanceof Error ? e.message : 'Failed'; addToast('error', 'Delete failed', deleteError); } finally { deleteLoading = false; } }

	async function toggleAuth(pk: number, activate: boolean) {
		authStates = { ...authStates, [pk]: 'loading' };
		try { const res = await fetch(`/api/admin/users/${pk}/${activate ? 'activate' : 'deactivate'}-authentik`, { method: 'POST' }); const result = await res.json(); if (result.error) throw new Error(result.error.message ?? 'Failed'); users = users.map(u => u.pk === pk ? { ...u, is_active: activate } : u); addToast('info', activate ? 'User activated' : 'User deactivated', ''); }
		catch (e) { addToast('error', 'Failed', e instanceof Error ? e.message : ''); }
		finally { const { [pk]: _, ...rest } = authStates; authStates = rest; }
	}

	async function openEditDialog(userObj: UserRow) {
		editForm = { uuid: userObj.uuid, authentikPk: userObj.pk, username: userObj.username, surname: '', firstName: '', middleName: '', email: userObj.email, password: '', showPassword: false, dateEmployed: '', qualifications: [], currentPassport: '' };
		editDialogOpen = true;
		editProfileLoading = true;
		try { const res = await fetch(`/api/admin/users/${userObj.uuid}/profile?role=teacher`); const body = await res.json(); const p = body?.data; if (p) { editForm.surname = p.surname ?? ''; editForm.firstName = p.first_name ?? ''; editForm.middleName = p.middle_name ?? ''; editForm.dateEmployed = p.date_employed ?? ''; editForm.qualifications = p.qualifications ?? []; editForm.currentPassport = p.passport ?? ''; } } catch { }
		finally { editProfileLoading = false; }
	}

	function openDeleteDialog(userObj: UserRow) { deleteTarget = { pk: userObj.pk, uuid: userObj.uuid, name: userObj.name || userObj.username }; deleteError = ''; deleteDialogOpen = true; }

	async function openClassAssign(userObj: UserRow) {
		const pk = userObj.pk; const uuid = userObj.uuid;
		classAssignTeacherUuid = uuid; classAssignTeacherPk = pk;
		selectedSubjectPair[pk] = null; subjectPairSearch[pk] = '';
		currentTeacherPairs[pk] = [];
		teacherPairsLoading[pk] = true;

		classAssignDialogOpen = true;

		if (!activeSessionTerm) {
			activeSessionTermLoading = true;
			fetch('/api/admin/active-session-term')
				.then(r => r.json())
				.then(body => { activeSessionTerm = body?.data ?? null; })
				.catch(() => {})
				.finally(() => { activeSessionTermLoading = false; });
		}

		try {
			const res = await fetch(`/api/admin/teacher/${uuid}/subjects`);
			const body = await res.json();
			currentTeacherPairs[pk] = body?.data ?? [];
		} catch {
			currentTeacherPairs[pk] = [];
		} finally {
			teacherPairsLoading[pk] = false;
		}
	}

	async function handleSaveTeacherSubjects(pk: number) {
		teacherSubjectLoading = { ...teacherSubjectLoading, [pk]: 'saving' };
		try { const pairs = currentTeacherPairs[pk] ?? []; const body = pairs.map((p: TeacherSubjectPair) => ({ has_subject_id: p.edge_id, class_level_id: p.class_level_id, class_level_name: p.class_level_name, subject_id: p.subject_id, subject_name: p.subject_name, subject_code: p.subject_code ?? null })); const res = await fetch('/api/admin/teacher/subjects', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ target_teacher_id: classAssignTeacherUuid, pairs_json: JSON.stringify(body) }) }); const result = await res.json(); if (result.error) throw new Error(result.error.message ?? 'Failed'); addToast('success', 'Subjects saved', ''); classAssignDialogOpen = false; }
		catch (e) { addToast('error', 'Failed to save subjects', e instanceof Error ? e.message : ''); }
		finally { const { [pk]: _, ...rest } = teacherSubjectLoading; teacherSubjectLoading = rest; }
	}

	function addSubjectPair(pk: number, pair: TeacherSubjectPair) {
		currentTeacherPairs[pk] = [...(currentTeacherPairs[pk] ?? []), pair]; selectedSubjectPair[pk] = null; subjectPairSearch[pk] = '';
	}
</script>

{#if hasError}<StatusCard variant="error" title="Failed to load users" description={errorMessage} onRetry={handleRetry} />
{:else if !hasUsers}<StatusCard variant="info" title="No teachers yet" description="Create the first teacher to get started." />
{:else}
	<Table><TableHeader><TableRow><TableHead>Name</TableHead><TableHead>Email</TableHead><TableHead>Auth Status</TableHead><TableHead>Activate</TableHead><TableHead>Action</TableHead><TableHead>Classes</TableHead></TableRow></TableHeader>
		<TableBody>
			{#each users as userObj (userObj.pk)}
				<TableRow>
					<TableCell>{userObj.name || userObj.username}</TableCell>
					<TableCell>{userObj.email || '\u2014'}</TableCell>
					<TableCell><Badge variant={userObj.is_active ? 'default' : 'secondary'}>{userObj.is_active ? 'Active' : 'Inactive'}</Badge></TableCell>
					<TableCell>
						{#if authStates[userObj.pk] === 'loading'}<div class="h-4 w-4 animate-spin rounded-full border-2 border-primary-500 border-t-transparent"></div>
						{:else}<AppButton variant="outline" size="sm" onclick={() => toggleAuth(userObj.pk, !userObj.is_active)}>{userObj.is_active ? 'Deactivate' : 'Activate'}</AppButton>{/if}
					</TableCell>
					<TableCell><div class="flex gap-2"><AppButton variant="outline" size="sm" onclick={() => openEditDialog(userObj)}>Edit</AppButton><AppButton variant="outline" size="sm" class="text-destructive" onclick={() => openDeleteDialog(userObj)}>Delete</AppButton></div></TableCell>
					<TableCell><AppButton variant="outline" size="sm" onclick={() => openClassAssign(userObj)}>Assign</AppButton></TableCell>
				</TableRow>
			{/each}
		</TableBody>
	</Table>
{/if}

<!-- Create dialog -->
<Dialog open={showCreateDialog} onOpenChange={(v: boolean) => v ? null : closeCreate()}>
	<DialogContent class="sm:max-w-lg"><DialogHeader><DialogTitle>Create Teacher</DialogTitle></DialogHeader>
		<div class="space-y-4">
			<div class="space-y-2"><Label>Username <span class="text-destructive">*</span></Label><Input bind:value={createForm.username} required minlength={3} /></div>
			<NameFields bind:surname={createForm.surname} bind:firstName={createForm.firstName} bind:middleName={createForm.middleName} />
			<div class="space-y-2"><Label>Email <span class="text-destructive">*</span></Label><Input type="email" bind:value={createForm.email} required /></div>
			<div class="space-y-2"><Label>Password <span class="text-destructive">*</span></Label><div class="flex gap-2"><Input type={createForm.showPassword ? 'text' : 'password'} bind:value={createForm.password} required minlength={8} /><AppButton variant="outline" size="sm" onclick={() => createForm.showPassword = !createForm.showPassword}>{createForm.showPassword ? 'Hide' : 'Show'}</AppButton><AppButton variant="outline" size="sm" onclick={() => { createForm.password = generatePassword(); createForm.showPassword = true; }}>Generate</AppButton></div></div>
			<div class="space-y-2"><Label>Date Employed</Label><Input type="date" bind:value={createForm.dateEmployed} /></div>
			<CredentialsSelect bind:selected={createForm.qualifications} />
			<div class="space-y-2"><Label>Passport Photo <span class="text-destructive">*</span></Label><PassportUpload bind:this={passportUpload} currentUrl={null} disabled={createLoading} /></div>
			<label class="flex items-center gap-2 text-sm"><input type="checkbox" bind:checked={createForm.isActive} class="rounded" /> Activate on creation</label>
			{#if createError}<p class="text-sm text-destructive">{createError}</p>{/if}
			<div class="flex justify-end gap-2"><AppButton variant="outline" onclick={closeCreate} disabled={createLoading}>Cancel</AppButton><AppButton onclick={handleCreate} loading={createLoading}>Create</AppButton></div>
		</div>
	</DialogContent>
</Dialog>

<!-- Edit + Class Assign + Delete dialogs follow same pattern as Student. Keeping them concise -->
<!-- Edit Dialog -->
<Dialog open={editDialogOpen} onOpenChange={(v: boolean) => v ? null : closeEdit()}>
	<DialogContent class="sm:max-w-lg"><DialogHeader><DialogTitle>Edit Teacher</DialogTitle></DialogHeader>
		<div class="space-y-4">
			{#if editProfileLoading}<div class="flex items-center gap-2 text-sm text-muted-foreground"><svg class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/></svg>Loading profile data...</div>{/if}
			<div class="space-y-2"><Label>Username <span class="text-destructive">*</span></Label><Input bind:value={editForm.username} required /></div>
			<NameFields bind:surname={editForm.surname} bind:firstName={editForm.firstName} bind:middleName={editForm.middleName} />
			<div class="space-y-2"><Label>Email <span class="text-destructive">*</span></Label><Input type="email" bind:value={editForm.email} required /></div>
			<div class="space-y-2"><Label>Password</Label><div class="flex gap-2"><Input type={editForm.showPassword ? 'text' : 'password'} bind:value={editForm.password} placeholder="Leave blank" /><AppButton variant="outline" size="sm" onclick={() => editForm.showPassword = !editForm.showPassword}>{editForm.showPassword ? 'Hide' : 'Show'}</AppButton><AppButton variant="outline" size="sm" onclick={() => { editForm.password = generatePassword(); editForm.showPassword = true; }}>Generate</AppButton></div></div>
			<div class="space-y-2"><Label>Date Employed</Label><Input type="date" bind:value={editForm.dateEmployed} /></div>
			<CredentialsSelect bind:selected={editForm.qualifications} />
			<div class="space-y-2"><Label>Passport Photo <span class="text-destructive">*</span></Label><PassportUpload bind:this={editPassportUpload} currentUrl={editForm.currentPassport || null} disabled={editLoading} /></div>
			{#if editError}<p class="text-sm text-destructive">{editError}</p>{/if}
			<div class="flex justify-end gap-2"><AppButton variant="outline" onclick={closeEdit} disabled={editLoading}>Cancel</AppButton><AppButton onclick={handleEdit} loading={editLoading} disabled={editLoading || editProfileLoading}>Save</AppButton></div>
		</div>
	</DialogContent>
</Dialog>

<!-- Delete -->
<AlertDialog.Root open={deleteDialogOpen} onOpenChange={(v: boolean) => v ? null : deleteDialogOpen = false}>
	<AlertDialog.Content><AlertDialog.Header><AlertDialog.Title>Delete Teacher</AlertDialog.Title><AlertDialog.Description>Delete {deleteTarget?.name}? This cannot be undone.</AlertDialog.Description></AlertDialog.Header>
		{#if deleteError}<p class="text-sm text-destructive px-4">{deleteError}</p>{/if}
		<AlertDialog.Footer><AlertDialog.Cancel disabled={deleteLoading}>Cancel</AlertDialog.Cancel><AlertDialog.Action onclick={handleDelete} class="bg-destructive hover:bg-destructive/90" disabled={deleteLoading}>Delete</AlertDialog.Action></AlertDialog.Footer>
	</AlertDialog.Content>
</AlertDialog.Root>

<!-- Class Assign -->
<Dialog open={classAssignDialogOpen} onOpenChange={(v: boolean) => v ? null : classAssignDialogOpen = false}>
	<DialogContent class="sm:max-w-lg"><DialogHeader><DialogTitle>Assign Classes</DialogTitle></DialogHeader>
		<div class="space-y-4">
			{#if activeSessionTermLoading}<p class="text-sm text-muted-foreground">Loading session term...</p>
			{:else if activeSessionTerm}
				<div class="text-sm text-muted-foreground">Active session: <span class="font-medium">{activeSessionTerm.session_name} — {activeSessionTerm.term_name}</span></div>
				{@const pk = classAssignTeacherPk}
				{#if teacherPairsLoading[pk]}<p class="text-sm text-muted-foreground">Loading...</p>{:else}
					<div class="flex flex-wrap gap-1.5">
						{#each currentTeacherPairs[pk] ?? [] as pair (pair.edge_id)}
							<Badge variant="secondary" class="gap-1">{pair.class_level_name} / {pair.subject_name}<button type="button" onclick={() => currentTeacherPairs[pk] = (currentTeacherPairs[pk] ?? []).filter((p: TeacherSubjectPair) => p.edge_id !== pair.edge_id)} class="ml-0.5 rounded-full hover:bg-surface-200"><svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg></button></Badge>
						{/each}
					</div>
					<SearchSelect
						items={allSubjectPairs}
						bind:search={subjectPairSearch[pk]}
						placeholder="Search class subjects..."
						filterFn={(p: TeacherSubjectPair, q: string) => {
							const added = currentTeacherPairs[pk] ?? [];
							const addedSet = new Set(added.map((a: TeacherSubjectPair) => `${a.class_level_id}||${a.subject_id}`));
							const lower = q.toLowerCase().replace(/\s+/g, '');
							return !addedSet.has(`${p.class_level_id}||${p.subject_id}`) && (!lower || `${p.class_level_name} ${p.subject_name}`.toLowerCase().replace(/\s+/g, '').includes(lower));
						}}
						onSelect={(p: TeacherSubjectPair) => addSubjectPair(pk, p)}
					>
						{#snippet children({ item }: { item: TeacherSubjectPair })}
							{item.class_level_name} / {item.subject_name}
							{#if item.subject_code}<span class="text-muted-foreground">[{item.subject_code}]</span>{/if}
						{/snippet}
					</SearchSelect>
				{/if}
				<div class="flex justify-end gap-2"><AppButton variant="outline" onclick={() => classAssignDialogOpen = false}>Cancel</AppButton><AppButton onclick={() => handleSaveTeacherSubjects(pk)} loading={teacherSubjectLoading[pk] === 'saving'}>Save</AppButton></div>
			{:else}<p class="text-sm text-amber-600">No active session term. Set one in Configuration → Session Terms.</p>
			{/if}
		</div>
	</DialogContent>
</Dialog>
