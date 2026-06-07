<script lang="ts">
	import { onMount } from 'svelte';
	import AppButton from '$lib/components/ui/app-button.svelte';
	import { Badge } from '$lib/components/ui/badge';
	import SearchSelect from '$lib/components/ui/search-select/search-select.svelte';
	import { Input } from '$lib/components/ui/input';
	import { Label } from '$lib/components/ui/label';
	import PageSkeleton from '$lib/components/ui/skeleton/PageSkeleton.svelte';
	import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
	import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '$lib/components/ui/table';
	import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';
	import { Dialog, DialogContent, DialogHeader, DialogTitle } from '$lib/components/ui/dialog';
	import PassportUpload from '../users-shared/PassportUpload.svelte';
	import { addToast } from '$lib/stores/toast';
	import type { UserRow } from '$lib/types/user';
	import type { StudentListItem } from '$lib/types';

	let { users = $bindable([] as UserRow[]), allGroups = $bindable([] as { pk: string; name: string }[]), showCreateDialog = $bindable(false), groupPk = '', hasError = false, errorMessage = '' } = $props();
	let hasUsers = $derived(users.length > 0);
	let authStates = $state<Record<number, string>>({});

	let studentList = $state<StudentListItem[]>([]);
	let studentListLoading = $state(true);
	let createForm = $state({ username: '', name: '', email: '', password: '', showPassword: false, students: [] as string[], isActive: true });
	let createLoading = $state(false); let createError = $state(''); let passportFile = $state<File | null>(null); let passportUpload: PassportUpload | undefined = $state();
	let editForm = $state({ uuid: '', authentikPk: 0, username: '', name: '', email: '', password: '', showPassword: false, students: [] as string[], currentPassport: '' });
	let editLoading = $state(false); let editError = $state(''); let editDialogOpen = $state(false); let editProfileLoading = $state(false); let editPassportFile = $state<File | null>(null); let editPassportUpload: PassportUpload | undefined = $state();
	let deleteTarget = $state<{ pk: number; uuid: string; name: string } | null>(null); let deleteLoading = $state(false); let deleteError = $state(''); let deleteDialogOpen = $state(false);

	function generatePassword(): string { const c = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'; let p = ''; const a = new Uint8Array(16); crypto.getRandomValues(a); for (let i = 0; i < 16; i++) p += c[a[i] % c.length]; return p; }
	function handleRetry() { window.location.reload(); }
	function closeCreate() { showCreateDialog = false; createError = ''; passportFile = null; createForm = { username: '', name: '', email: '', password: '', showPassword: false, students: [], isActive: true }; }
	function closeEdit() { editDialogOpen = false; editError = ''; editPassportFile = null; }

	onMount(async () => { try { const r = await fetch('/api/admin/students/list'); const b = await r.json(); studentList = b?.data ?? []; } catch { studentList = []; } finally { studentListLoading = false; } });

	let selectedStudentNames = $derived(studentList.filter(s => createForm.students.includes(s.id)).map(s => ({ id: s.id, name: s.display_name })));
	let editSelectedNames = $derived(studentList.filter(s => editForm.students.includes(s.id)).map(s => ({ id: s.id, name: s.display_name })));

	function addStudent(id: string) { createForm.students = [...createForm.students, id]; }
	function removeStudent(id: string) { createForm.students = createForm.students.filter(s => s !== id); }
	function addEditStudent(id: string) { editForm.students = [...editForm.students, id]; }
	function removeEditStudent(id: string) { editForm.students = editForm.students.filter(s => s !== id); }

	async function handleCreate() {
		createLoading = true; createError = '';
		try { let passportUrl = ''; if (passportFile && passportUpload) { const u = await passportUpload.getPassportPublicUrl(passportFile, 'parent', ''); if (!u) { createLoading = false; return; } passportUrl = u; }
			if (createForm.students.length === 0) { createError = 'At least one student is required'; createLoading = false; return; }
			const res = await fetch('/api/admin/users', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username: createForm.username, name: createForm.name, display_name: createForm.name, email: createForm.email, password: createForm.password, is_active: createForm.isActive, group_pk: groupPk, role: 'parent', students: createForm.students, passport_url: passportUrl }) });
			const r = await res.json(); if (r.error) throw new Error(r.error.message ?? 'Failed'); const u = r.data; users = [...users, { pk: u.pk, uuid: u.uuid, username: u.username, name: u.name, email: u.email, groups: u.groups, is_active: u.is_active }]; addToast('success', 'Parent created', createForm.username); closeCreate(); }
		catch (e) { createError = e instanceof Error ? e.message : 'Failed'; addToast('error', 'Create failed', createError); } finally { createLoading = false; }
	}

	async function handleEdit() {
		editLoading = true; editError = '';
		try { let passportUrl = editForm.currentPassport; if (editPassportFile && editPassportUpload) { const u = await editPassportUpload.getPassportPublicUrl(editPassportFile, 'parent', editForm.uuid); if (!u) { editLoading = false; return; } passportUrl = u; }
			const res = await fetch(`/api/admin/users/${editForm.uuid}/edit-profile`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ authentik_pk: editForm.authentikPk, username: editForm.username, name: editForm.name, display_name: editForm.name, email: editForm.email, password: editForm.password || undefined, role: 'parent', students: editForm.students, passport_url: passportUrl }) });
			const r = await res.json(); if (r.error) throw new Error(r.error.message ?? 'Failed'); users = users.map(u => u.uuid === editForm.uuid ? { ...u, username: editForm.username, name: editForm.name, email: editForm.email } : u); addToast('success', 'Parent updated', editForm.username); closeEdit(); }
		catch (e) { editError = e instanceof Error ? e.message : 'Failed'; addToast('error', 'Edit failed', editError); } finally { editLoading = false; }
	}

	async function handleDelete() { if (!deleteTarget) return; deleteLoading = true; deleteError = ''; try { const r = await fetch(`/api/admin/users/${deleteTarget.pk}?uuid=${deleteTarget.uuid}&role=parent`, { method: 'DELETE' }); const j = await r.json(); if (j.error) throw new Error(j.error.message ?? 'Failed'); users = users.filter(u => u.pk !== deleteTarget!.pk); addToast('success', 'Parent deleted', deleteTarget!.name); deleteDialogOpen = false; deleteTarget = null; } catch (e) { deleteError = e instanceof Error ? e.message : 'Failed'; addToast('error', 'Delete failed', deleteError); } finally { deleteLoading = false; } }
	async function toggleAuth(pk: number, activate: boolean) { authStates = { ...authStates, [pk]: 'loading' }; try { const r = await fetch(`/api/admin/users/${pk}/${activate ? 'activate' : 'deactivate'}-authentik`, { method: 'POST' }); const j = await r.json(); if (j.error) throw new Error(j.error.message ?? 'Failed'); users = users.map(u => u.pk === pk ? { ...u, is_active: activate } : u); addToast('info', activate ? 'Activated' : 'Deactivated', ''); } catch (e) { addToast('error', 'Failed', e instanceof Error ? e.message : ''); } finally { const { [pk]: _, ...rest } = authStates; authStates = rest; } }

	async function openEditDialog(userObj: UserRow) { editForm = { uuid: userObj.uuid, authentikPk: userObj.pk, username: userObj.username, name: '', email: userObj.email, password: '', showPassword: false, students: [], currentPassport: '' }; editDialogOpen = true; editProfileLoading = true; try { const r = await fetch(`/api/admin/users/${userObj.uuid}/profile?role=parent`); const b = await r.json(); const p = b?.data; if (p) { editForm.name = p.name ?? ''; editForm.students = p.students ?? []; editForm.currentPassport = p.passport ?? ''; } } catch { } finally { editProfileLoading = false; } }
	function openDeleteDialog(userObj: UserRow) { deleteTarget = { pk: userObj.pk, uuid: userObj.uuid, name: userObj.name || userObj.username }; deleteError = ''; deleteDialogOpen = true; }
</script>

{#if hasError}<StatusCard variant="error" title="Failed to load users" description={errorMessage} onRetry={handleRetry} />
{:else if !hasUsers}<StatusCard variant="info" title="No parents yet" description="Create the first parent to get started." />
{:else}
	<Table><TableHeader><TableRow><TableHead>Name</TableHead><TableHead>Email</TableHead><TableHead>Students</TableHead><TableHead>Auth Status</TableHead><TableHead>Activate</TableHead><TableHead>Action</TableHead></TableRow></TableHeader>
		<TableBody>{#each users as u (u.pk)}<TableRow><TableCell>{u.name || u.username}</TableCell><TableCell>{u.email || '\u2014'}</TableCell><TableCell></TableCell><TableCell><Badge variant={u.is_active ? 'default' : 'secondary'}>{u.is_active ? 'Active' : 'Inactive'}</Badge></TableCell><TableCell>{#if authStates[u.pk] === 'loading'}<div class="h-4 w-4 animate-spin rounded-full border-2 border-primary-500 border-t-transparent"></div>{:else}<AppButton variant="outline" size="sm" onclick={() => toggleAuth(u.pk, !u.is_active)}>{u.is_active ? 'Deactivate' : 'Activate'}</AppButton>{/if}</TableCell><TableCell><div class="flex gap-2"><AppButton variant="outline" size="sm" onclick={() => openEditDialog(u)}>Edit</AppButton><AppButton variant="outline" size="sm" class="text-destructive" onclick={() => openDeleteDialog(u)}>Delete</AppButton></div></TableCell></TableRow>{/each}</TableBody></Table>
{/if}

<Dialog open={showCreateDialog} onOpenChange={(v: boolean) => v ? null : closeCreate()}>
	<DialogContent class="sm:max-w-lg"><DialogHeader><DialogTitle>Create Parent</DialogTitle></DialogHeader>
		<div class="space-y-4">
			<div class="space-y-2"><Label>Username <span class="text-destructive">*</span></Label><Input bind:value={createForm.username} required /></div>
			<div class="space-y-2"><Label>Full Name <span class="text-destructive">*</span></Label><Input bind:value={createForm.name} required /></div>
			<div class="space-y-2"><Label>Email <span class="text-destructive">*</span></Label><Input type="email" bind:value={createForm.email} required /></div>
			<div class="space-y-2"><Label>Password <span class="text-destructive">*</span></Label><div class="flex gap-2"><Input type={createForm.showPassword ? 'text' : 'password'} bind:value={createForm.password} required /><AppButton variant="outline" size="sm" onclick={() => createForm.showPassword = !createForm.showPassword}>{createForm.showPassword ? 'Hide' : 'Show'}</AppButton><AppButton variant="outline" size="sm" onclick={() => { createForm.password = generatePassword(); createForm.showPassword = true; }}>Generate</AppButton></div></div>
			<div class="space-y-2">
				<Label>Linked Students <span class="text-destructive">*</span></Label>
				{#if studentListLoading}<p class="text-sm text-muted-foreground">Loading students...</p>{:else}
					<div class="flex flex-wrap gap-1.5">{#each selectedStudentNames as student}<Badge variant="secondary" class="gap-1">{student.name}<button type="button" onclick={() => removeStudent(student.id)} class="ml-0.5 rounded-full hover:bg-surface-200"><svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg></button></Badge>{/each}</div>
					<SearchSelect
						items={studentList}
						placeholder="Search students..."
						filterFn={(s: StudentListItem, q: string) => !createForm.students.includes(s.id) && s.display_name.toLowerCase().includes(q.toLowerCase())}
						onSelect={(s: StudentListItem) => addStudent(s.id)}
					>
						{#snippet children({ item }: { item: StudentListItem })}
							{item.display_name}
						{/snippet}
					</SearchSelect>
				{/if}
			</div>
			<div class="space-y-2"><Label>Passport Photo <span class="text-destructive">*</span></Label><PassportUpload bind:this={passportUpload} currentUrl={null} disabled={createLoading} /></div>
			<label class="flex items-center gap-2 text-sm"><input type="checkbox" bind:checked={createForm.isActive} class="rounded" /> Activate on creation</label>
			{#if createError}<p class="text-sm text-destructive">{createError}</p>{/if}
			<div class="flex justify-end gap-2"><AppButton variant="outline" onclick={closeCreate} disabled={createLoading}>Cancel</AppButton><AppButton onclick={handleCreate} loading={createLoading}>Create</AppButton></div>
		</div>
	</DialogContent>
</Dialog>

<Dialog open={editDialogOpen} onOpenChange={(v: boolean) => v ? null : closeEdit()}>
	<DialogContent class="sm:max-w-lg"><DialogHeader><DialogTitle>Edit Parent</DialogTitle></DialogHeader>
		<div class="space-y-4">{#if editProfileLoading}<div class="flex items-center gap-2 text-sm text-muted-foreground"><svg class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/></svg>Loading profile data...</div>{/if}
			<div class="space-y-2"><Label>Username <span class="text-destructive">*</span></Label><Input bind:value={editForm.username} required /></div>
			<div class="space-y-2"><Label>Full Name <span class="text-destructive">*</span></Label><Input bind:value={editForm.name} required /></div>
			<div class="space-y-2"><Label>Email <span class="text-destructive">*</span></Label><Input type="email" bind:value={editForm.email} required /></div>
			<div class="space-y-2"><Label>Password</Label><div class="flex gap-2"><Input type={editForm.showPassword ? 'text' : 'password'} bind:value={editForm.password} placeholder="Leave blank" /><AppButton variant="outline" size="sm" onclick={() => editForm.showPassword = !editForm.showPassword}>{editForm.showPassword ? 'Hide' : 'Show'}</AppButton><AppButton variant="outline" size="sm" onclick={() => { editForm.password = generatePassword(); editForm.showPassword = true; }}>Generate</AppButton></div></div>
			<div class="space-y-2"><Label>Linked Students <span class="text-destructive">*</span></Label>
				<div class="flex flex-wrap gap-1.5">{#each editSelectedNames as student}<Badge variant="secondary" class="gap-1">{student.name}<button type="button" onclick={() => removeEditStudent(student.id)} class="ml-0.5 rounded-full hover:bg-surface-200"><svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg></button></Badge>{/each}</div>
				<SearchSelect
					items={studentList}
					placeholder="Search students..."
					filterFn={(s: StudentListItem, q: string) => !editForm.students.includes(s.id) && s.display_name.toLowerCase().includes(q.toLowerCase())}
					onSelect={(s: StudentListItem) => addEditStudent(s.id)}
				>
					{#snippet children({ item }: { item: StudentListItem })}
						{item.display_name}
					{/snippet}
				</SearchSelect>
			</div>
			<div class="space-y-2"><Label>Passport Photo <span class="text-destructive">*</span></Label><PassportUpload bind:this={editPassportUpload} currentUrl={editForm.currentPassport || null} disabled={editLoading} /></div>
			{#if editError}<p class="text-sm text-destructive">{editError}</p>{/if}
			<div class="flex justify-end gap-2"><AppButton variant="outline" onclick={closeEdit} disabled={editLoading}>Cancel</AppButton><AppButton onclick={handleEdit} loading={editLoading} disabled={editLoading || editProfileLoading}>Save</AppButton></div>
		</div>
	</DialogContent>
</Dialog>

<AlertDialog.Root open={deleteDialogOpen} onOpenChange={(v: boolean) => v ? null : deleteDialogOpen = false}>
	<AlertDialog.Content><AlertDialog.Header><AlertDialog.Title>Delete Parent</AlertDialog.Title><AlertDialog.Description>Delete {deleteTarget?.name}? Cannot be undone.</AlertDialog.Description></AlertDialog.Header>
		{#if deleteError}<p class="text-sm text-destructive px-4">{deleteError}</p>{/if}
		<AlertDialog.Footer><AlertDialog.Cancel disabled={deleteLoading}>Cancel</AlertDialog.Cancel><AlertDialog.Action onclick={handleDelete} class="bg-destructive hover:bg-destructive/90" disabled={deleteLoading}>Delete</AlertDialog.Action></AlertDialog.Footer>
	</AlertDialog.Content>
</AlertDialog.Root>
