<script lang="ts">
	import AppButton from '$lib/components/ui/app-button.svelte';
	import { Badge } from '$lib/components/ui/badge';
	import { Input } from '$lib/components/ui/input';
	import { Label } from '$lib/components/ui/label';
	import { Skeleton } from '$lib/components/ui/skeleton';
	import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
	import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '$lib/components/ui/table';
	import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';
	import { Dialog, DialogContent, DialogHeader, DialogTitle } from '$lib/components/ui/dialog';
	import PassportUpload from '../users-shared/PassportUpload.svelte';
	import NameFields from '../users-shared/NameFields.svelte';
	import { addToast } from '$lib/stores/toast';
	import type { UserRow } from '$lib/types/user';

	let { users = $bindable([] as UserRow[]), allGroups = $bindable([] as { pk: string; name: string }[]), showCreateDialog = $bindable(false), groupPk = '', isLoading = false, hasError = false, errorMessage = '' } = $props();
	let hasUsers = $derived(users.length > 0);
	let authStates = $state<Record<number, string>>({});
	let createForm = $state({ username: '', surname: '', firstName: '', middleName: '', email: '', password: '', showPassword: false, roleTitle: '', isActive: true });
	let createLoading = $state(false); let createError = $state(''); let passportFile = $state<File | null>(null); let passportUpload: PassportUpload | undefined = $state();
	let editForm = $state({ uuid: '', authentikPk: 0, username: '', surname: '', firstName: '', middleName: '', email: '', password: '', showPassword: false, roleTitle: '', currentPassport: '' });
	let editLoading = $state(false); let editError = $state(''); let editDialogOpen = $state(false); let editProfileLoading = $state(false); let editPassportFile = $state<File | null>(null); let editPassportUpload: PassportUpload | undefined = $state();
	let deleteTarget = $state<{ pk: number; uuid: string; name: string } | null>(null); let deleteLoading = $state(false); let deleteError = $state(''); let deleteDialogOpen = $state(false);

	let displayName = $derived([createForm.surname, createForm.firstName, createForm.middleName].filter(Boolean).join(' '));
	let editDisplayName = $derived([editForm.surname, editForm.firstName, editForm.middleName].filter(Boolean).join(' '));

	function generatePassword(): string { const c = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'; let p = ''; const a = new Uint8Array(16); crypto.getRandomValues(a); for (let i = 0; i < 16; i++) p += c[a[i] % c.length]; return p; }
	function handleRetry() { window.location.reload(); }
	function closeCreate() { showCreateDialog = false; createError = ''; passportFile = null; createForm = { username: '', surname: '', firstName: '', middleName: '', email: '', password: '', showPassword: false, roleTitle: '', isActive: true }; }
	function closeEdit() { editDialogOpen = false; editError = ''; editPassportFile = null; }

	async function handleCreate() {
		createLoading = true; createError = '';
		try { let passportUrl = ''; if (passportFile && passportUpload) { const u = await passportUpload.getPassportPublicUrl(passportFile, 'admin', ''); if (!u) { createLoading = false; return; } passportUrl = u; }
			const res = await fetch('/api/admin/users', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username: createForm.username, surname: createForm.surname, first_name: createForm.firstName, middle_name: createForm.middleName || undefined, display_name: displayName, email: createForm.email, password: createForm.password, is_active: createForm.isActive, group_pk: groupPk, role: 'admin', role_title: createForm.roleTitle || undefined, passport_url: passportUrl }) });
			const r = await res.json(); if (r.error) throw new Error(r.error.message ?? 'Failed'); const u = r.data; users = [...users, { pk: u.pk, uuid: u.uuid, username: u.username, name: u.name, email: u.email, groups: u.groups, is_active: u.is_active }]; addToast('success', 'Admin created', createForm.username); closeCreate(); }
		catch (e) { createError = e instanceof Error ? e.message : 'Failed'; addToast('error', 'Create failed', createError); } finally { createLoading = false; }
	}

	async function handleEdit() {
		editLoading = true; editError = '';
		try { let passportUrl = editForm.currentPassport; if (editPassportFile && editPassportUpload) { const u = await editPassportUpload.getPassportPublicUrl(editPassportFile, 'admin', editForm.uuid); if (!u) { editLoading = false; return; } passportUrl = u; }
			const res = await fetch(`/api/admin/users/${editForm.uuid}/edit-profile`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ authentik_pk: editForm.authentikPk, username: editForm.username, surname: editForm.surname, first_name: editForm.firstName, middle_name: editForm.middleName || undefined, display_name: editDisplayName, email: editForm.email, password: editForm.password || undefined, role: 'admin', role_title: editForm.roleTitle || undefined, passport_url: passportUrl }) });
			const r = await res.json(); if (r.error) throw new Error(r.error.message ?? 'Failed'); addToast('success', 'Admin updated', editForm.username); closeEdit(); }
		catch (e) { editError = e instanceof Error ? e.message : 'Failed'; addToast('error', 'Edit failed', editError); } finally { editLoading = false; }
	}

	async function handleDelete() { if (!deleteTarget) return; deleteLoading = true; deleteError = ''; try { const r = await fetch(`/api/admin/users/${deleteTarget.pk}?uuid=${deleteTarget.uuid}&role=admin`, { method: 'DELETE' }); const j = await r.json(); if (j.error) throw new Error(j.error.message ?? 'Failed'); users = users.filter(u => u.pk !== deleteTarget!.pk); addToast('success', 'Admin deleted', deleteTarget!.name); deleteDialogOpen = false; deleteTarget = null; } catch (e) { deleteError = e instanceof Error ? e.message : 'Failed'; addToast('error', 'Delete failed', deleteError); } finally { deleteLoading = false; } }

	async function toggleAuth(pk: number, activate: boolean) { authStates[pk] = 'loading'; try { const r = await fetch(`/api/admin/users/${pk}/${activate ? 'activate' : 'deactivate'}-authentik`, { method: 'POST' }); const j = await r.json(); if (j.error) throw new Error(j.error.message ?? 'Failed'); users = users.map(u => u.pk === pk ? { ...u, is_active: activate } : u); addToast('info', activate ? 'Activated' : 'Deactivated', ''); } catch (e) { addToast('error', 'Failed', e instanceof Error ? e.message : ''); } finally { delete authStates[pk]; } }

	async function openEditDialog(userObj: UserRow) { editForm = { uuid: userObj.uuid, authentikPk: userObj.pk, username: userObj.username, surname: '', firstName: '', middleName: '', email: userObj.email, password: '', showPassword: false, roleTitle: '', currentPassport: '' }; editProfileLoading = true; try { const r = await fetch(`/api/admin/users/${userObj.uuid}/profile?role=admin`); const b = await r.json(); const p = b?.data; if (p) { editForm.surname = p.surname ?? ''; editForm.firstName = p.first_name ?? ''; editForm.middleName = p.middle_name ?? ''; editForm.roleTitle = p.role_title ?? ''; editForm.currentPassport = p.passport ?? ''; } } catch { } finally { editProfileLoading = false; editDialogOpen = true; } }
	function openDeleteDialog(userObj: UserRow) { deleteTarget = { pk: userObj.pk, uuid: userObj.uuid, name: userObj.name || userObj.username }; deleteError = ''; deleteDialogOpen = true; }
</script>

{#if isLoading}<div class="space-y-3">{#each Array(5) as _}<Skeleton class="h-12" />{/each}</div>
{:else if hasError}<StatusCard variant="error" title="Failed to load users" description={errorMessage} onRetry={handleRetry} />
{:else if !hasUsers}<StatusCard variant="info" title="No admins yet" description="Create the first admin to get started." />
{:else}
	<Table><TableHeader><TableRow><TableHead>Name</TableHead><TableHead>Email</TableHead><TableHead>Role Title</TableHead><TableHead>Auth Status</TableHead><TableHead>Activate</TableHead><TableHead>Action</TableHead></TableRow></TableHeader>
		<TableBody>{#each users as u (u.pk)}<TableRow><TableCell>{u.name || u.username}</TableCell><TableCell>{u.email || '\u2014'}</TableCell><TableCell></TableCell><TableCell><Badge variant={u.is_active ? 'default' : 'secondary'}>{u.is_active ? 'Active' : 'Inactive'}</Badge></TableCell><TableCell>{#if authStates[u.pk] === 'loading'}<div class="h-4 w-4 animate-spin rounded-full border-2 border-primary-500 border-t-transparent"></div>{:else}<AppButton variant="outline" size="sm" onclick={() => toggleAuth(u.pk, !u.is_active)}>{u.is_active ? 'Deactivate' : 'Activate'}</AppButton>{/if}</TableCell><TableCell><div class="flex gap-2"><AppButton variant="outline" size="sm" onclick={() => openEditDialog(u)}>Edit</AppButton><AppButton variant="outline" size="sm" class="text-error-500" onclick={() => openDeleteDialog(u)}>Delete</AppButton></div></TableCell></TableRow>{/each}</TableBody></Table>
{/if}

<Dialog open={showCreateDialog} onOpenChange={(v: boolean) => v ? null : closeCreate()}>
	<DialogContent class="sm:max-w-lg"><DialogHeader><DialogTitle>Create Admin</DialogTitle></DialogHeader>
		<div class="space-y-4">
			<div class="space-y-2"><Label>Username <span class="text-error-500">*</span></Label><Input bind:value={createForm.username} required /></div>
			<NameFields bind:surname={createForm.surname} bind:firstName={createForm.firstName} bind:middleName={createForm.middleName} />
			<div class="space-y-2"><Label>Email <span class="text-error-500">*</span></Label><Input type="email" bind:value={createForm.email} required /></div>
			<div class="space-y-2"><Label>Password <span class="text-error-500">*</span></Label><div class="flex gap-2"><Input type={createForm.showPassword ? 'text' : 'password'} bind:value={createForm.password} required /><AppButton variant="outline" size="sm" onclick={() => createForm.showPassword = !createForm.showPassword}>{createForm.showPassword ? 'Hide' : 'Show'}</AppButton><AppButton variant="outline" size="sm" onclick={() => { createForm.password = generatePassword(); createForm.showPassword = true; }}>Generate</AppButton></div></div>
			<div class="space-y-2"><Label>Role Title</Label><Input bind:value={createForm.roleTitle} placeholder="e.g. Bursar, Receptionist" /></div>
			<div class="space-y-2"><Label>Passport Photo <span class="text-error-500">*</span></Label><PassportUpload bind:this={passportUpload} currentUrl={null} disabled={createLoading} /></div>
			<label class="flex items-center gap-2 text-sm"><input type="checkbox" bind:checked={createForm.isActive} class="rounded" /> Activate on creation</label>
			{#if createError}<p class="text-sm text-error-500">{createError}</p>{/if}
			<div class="flex justify-end gap-2"><AppButton variant="outline" onclick={closeCreate} disabled={createLoading}>Cancel</AppButton><AppButton onclick={handleCreate} loading={createLoading}>Create</AppButton></div>
		</div>
	</DialogContent>
</Dialog>

<Dialog open={editDialogOpen} onOpenChange={(v: boolean) => v ? null : closeEdit()}>
	<DialogContent class="sm:max-w-lg"><DialogHeader><DialogTitle>Edit Admin</DialogTitle></DialogHeader>
		<div class="space-y-4">{#if editProfileLoading}<div class="text-sm text-surface-400">Loading...</div>{/if}
			<div class="space-y-2"><Label>Username <span class="text-error-500">*</span></Label><Input bind:value={editForm.username} required /></div>
			<NameFields bind:surname={editForm.surname} bind:firstName={editForm.firstName} bind:middleName={editForm.middleName} />
			<div class="space-y-2"><Label>Email <span class="text-error-500">*</span></Label><Input type="email" bind:value={editForm.email} required /></div>
			<div class="space-y-2"><Label>Password</Label><div class="flex gap-2"><Input type={editForm.showPassword ? 'text' : 'password'} bind:value={editForm.password} placeholder="Leave blank" /><AppButton variant="outline" size="sm" onclick={() => editForm.showPassword = !editForm.showPassword}>{editForm.showPassword ? 'Hide' : 'Show'}</AppButton><AppButton variant="outline" size="sm" onclick={() => { editForm.password = generatePassword(); editForm.showPassword = true; }}>Generate</AppButton></div></div>
			<div class="space-y-2"><Label>Role Title</Label><Input bind:value={editForm.roleTitle} /></div>
			<div class="space-y-2"><Label>Passport Photo <span class="text-error-500">*</span></Label><PassportUpload bind:this={editPassportUpload} currentUrl={editForm.currentPassport || null} disabled={editLoading} /></div>
			{#if editError}<p class="text-sm text-error-500">{editError}</p>{/if}
			<div class="flex justify-end gap-2"><AppButton variant="outline" onclick={closeEdit} disabled={editLoading}>Cancel</AppButton><AppButton onclick={handleEdit} loading={editLoading}>Save</AppButton></div>
		</div>
	</DialogContent>
</Dialog>

<AlertDialog.Root open={deleteDialogOpen} onOpenChange={(v: boolean) => v ? null : deleteDialogOpen = false}>
	<AlertDialog.Content><AlertDialog.Header><AlertDialog.Title>Delete Admin</AlertDialog.Title><AlertDialog.Description>Delete {deleteTarget?.name}? Cannot be undone.</AlertDialog.Description></AlertDialog.Header>
		{#if deleteError}<p class="text-sm text-error-500 px-4">{deleteError}</p>{/if}
		<AlertDialog.Footer><AlertDialog.Cancel disabled={deleteLoading}>Cancel</AlertDialog.Cancel><AlertDialog.Action onclick={handleDelete} class="bg-error-500 hover:bg-error-600" disabled={deleteLoading}>Delete</AlertDialog.Action></AlertDialog.Footer>
	</AlertDialog.Content>
</AlertDialog.Root>
