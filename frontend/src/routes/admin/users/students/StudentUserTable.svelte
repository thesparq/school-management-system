<script lang="ts">
	import { onMount } from 'svelte';
	import AppButton from '$lib/components/ui/app-button.svelte';
	import { Badge } from '$lib/components/ui/badge';
	import { Input } from '$lib/components/ui/input';
	import { Label } from '$lib/components/ui/label';
	import { Skeleton } from '$lib/components/ui/skeleton';
	import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
	import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '$lib/components/ui/table';
	import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';
	import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '$lib/components/ui/dialog';
	import PassportUpload from '../users-shared/PassportUpload.svelte';
	import NameFields from '../users-shared/NameFields.svelte';
	import { addToast } from '$lib/stores/toast';
	import type { UserRow } from '$lib/types/user';

	let {
		users = $bindable([] as UserRow[]),
		allGroups = $bindable([] as { pk: string; name: string }[]),
		showCreateDialog = $bindable(false),
		groupPk = '',
		isLoading = false,
		hasError = false,
		errorMessage = ''
	} = $props();

	let hasUsers = $derived(users.length > 0);
	let authStates = $state<Record<number, string>>({});
	let classLevels = $state<{ name: string }[]>([]);
	let classLevelsLoading = $state(true);

	let createForm = $state({ username: '', surname: '', firstName: '', middleName: '', email: '', password: '', showPassword: false, dob: '', classLevel: '', isActive: true });
	let createLoading = $state(false);
	let createError = $state('');
	let passportFile = $state<File | null>(null);
	let passportUpload: PassportUpload | undefined = $state();

	let editForm = $state({ uuid: '', authentikPk: 0, username: '', surname: '', firstName: '', middleName: '', email: '', password: '', showPassword: false, dob: '', classLevel: '', currentPassport: '' });
	let editLoading = $state(false);
	let editError = $state('');
	let editDialogOpen = $state(false);
	let editProfileLoading = $state(false);
	let editPassportFile = $state<File | null>(null);
	let editPassportUpload: PassportUpload | undefined = $state();

	let deleteLoading = $state(false);
	let deleteError = $state('');
	let deleteTarget = $state<{ pk: number; uuid: string; name: string } | null>(null);
	let deleteDialogOpen = $state(false);

	let displayName = $derived(
		[createForm.surname, createForm.firstName, createForm.middleName].filter(Boolean).join(' ')
	);
	let editDisplayName = $derived(
		[editForm.surname, editForm.firstName, editForm.middleName].filter(Boolean).join(' ')
	);

	function generatePassword(): string {
		const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
		let pw = '';
		const arr = new Uint8Array(16);
		crypto.getRandomValues(arr);
		for (let i = 0; i < 16; i++) pw += chars[arr[i] % chars.length];
		return pw;
	}

	function handleRetry() { window.location.reload(); }

	onMount(async () => {
		try {
			const res = await fetch('/api/admin/class-levels');
			const body = await res.json();
			classLevels = body?.data ?? [];
		} catch { classLevels = []; } finally { classLevelsLoading = false; }
	});

	function closeCreate() { showCreateDialog = false; createError = ''; passportFile = null; createForm = { username: '', surname: '', firstName: '', middleName: '', email: '', password: '', showPassword: false, dob: '', classLevel: '', isActive: true }; }
	function closeEdit() { editDialogOpen = false; editError = ''; editPassportFile = null; }

	async function handleCreate() {
		createLoading = true; createError = '';
		try {
			let passportUrl = '';
			const file = passportFile;
			if (file && passportUpload) {
				const url = await passportUpload.getPassportPublicUrl(file, 'student', '');
				if (!url) { createLoading = false; return; }
				passportUrl = url;
			}

			const body = {
				username: createForm.username,
				surname: createForm.surname,
				first_name: createForm.firstName,
				middle_name: createForm.middleName || undefined,
				display_name: displayName,
				email: createForm.email,
				password: createForm.password,
				is_active: createForm.isActive,
				group_pk: groupPk,
				role: 'student',
				class_level: createForm.classLevel,
				date_of_birth: createForm.dob,
				passport_url: passportUrl
			};

			const res = await fetch('/api/admin/users', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
			const result = await res.json();
			if (result.error) throw new Error(result.error.message ?? 'Failed to create student');

			const newUser = result.data;
			users = [...users, { pk: newUser.pk, uuid: newUser.uuid, username: newUser.username, name: newUser.name, email: newUser.email, groups: newUser.groups, is_active: newUser.is_active }];
			addToast('success', 'Student created', createForm.username);
			closeCreate();
		} catch (e) {
			createError = e instanceof Error ? e.message : 'Failed to create student';
			addToast('error', 'Create failed', createError);
		} finally { createLoading = false; }
	}

	async function handleEdit() {
		editLoading = true; editError = '';
		try {
			let passportUrl = editForm.currentPassport;
			const file = editPassportFile;
			if (file && editPassportUpload) {
				const url = await editPassportUpload.getPassportPublicUrl(file, 'student', editForm.uuid);
				if (!url) { editLoading = false; return; }
				passportUrl = url;
			}

			const body = {
				authentik_pk: editForm.authentikPk,
				username: editForm.username,
				surname: editForm.surname,
				first_name: editForm.firstName,
				middle_name: editForm.middleName || undefined,
				display_name: editDisplayName,
				email: editForm.email,
				password: editForm.password || undefined,
				role: 'student',
				class_level: editForm.classLevel,
				date_of_birth: editForm.dob,
				passport_url: passportUrl
			};

			const res = await fetch(`/api/admin/users/${editForm.uuid}/edit-profile`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
			const result = await res.json();
			if (result.error) throw new Error(result.error.message ?? 'Failed to edit student');

			addToast('success', 'Student updated', editForm.username);
			closeEdit();
		} catch (e) {
			editError = e instanceof Error ? e.message : 'Failed to edit student';
			addToast('error', 'Edit failed', editError);
		} finally { editLoading = false; }
	}

	async function handleDelete() {
		if (!deleteTarget) return;
		deleteLoading = true; deleteError = '';
		try {
			const res = await fetch(`/api/admin/users/${deleteTarget.pk}?uuid=${deleteTarget.uuid}&role=student`, { method: 'DELETE' });
			const result = await res.json();
			if (result.error) throw new Error(result.error.message ?? 'Failed to delete student');
			users = users.filter(u => u.pk !== deleteTarget!.pk);
			addToast('success', 'Student deleted', deleteTarget!.name);
			deleteDialogOpen = false; deleteTarget = null;
		} catch (e) {
			deleteError = e instanceof Error ? e.message : 'Failed to delete student';
			addToast('error', 'Delete failed', deleteError);
		} finally { deleteLoading = false; }
	}

	async function handleActivate(pk: number) {
		authStates[pk] = 'loading';
		try {
			const res = await fetch(`/api/admin/users/${pk}/activate-authentik`, { method: 'POST' });
			const result = await res.json();
			if (result.error) throw new Error(result.error.message ?? 'Failed');
			users = users.map(u => u.pk === pk ? { ...u, is_active: true } : u);
			addToast('info', 'User activated', '');
		} catch (e) {
			addToast('error', 'Activation failed', e instanceof Error ? e.message : '');
		} finally { delete authStates[pk]; }
	}

	async function handleDeactivate(pk: number) {
		authStates[pk] = 'loading';
		try {
			const res = await fetch(`/api/admin/users/${pk}/deactivate-authentik`, { method: 'POST' });
			const result = await res.json();
			if (result.error) throw new Error(result.error.message ?? 'Failed');
			users = users.map(u => u.pk === pk ? { ...u, is_active: false } : u);
			addToast('info', 'User deactivated', '');
		} catch (e) {
			addToast('error', 'Deactivation failed', e instanceof Error ? e.message : '');
		} finally { delete authStates[pk]; }
	}

	async function openEditDialog(userObj: UserRow) {
		editForm = { uuid: userObj.uuid, authentikPk: userObj.pk, username: userObj.username, surname: '', firstName: '', middleName: '', email: userObj.email, password: '', showPassword: false, dob: '', classLevel: '', currentPassport: '' };
		editProfileLoading = true;
		try {
			const res = await fetch(`/api/admin/users/${userObj.uuid}/profile?role=student`);
			const body = await res.json();
			const profile = body?.data;
			if (profile) {
				editForm.surname = profile.surname ?? '';
				editForm.firstName = profile.first_name ?? '';
				editForm.middleName = profile.middle_name ?? '';
				editForm.dob = profile.date_of_birth ?? '';
				editForm.classLevel = profile.current_class ?? '';
				editForm.currentPassport = profile.passport ?? '';
			}
		} catch { /* pre-load fails gracefully */ }
		finally { editProfileLoading = false; editDialogOpen = true; }
	}

	function openDeleteDialog(userObj: UserRow) {
		deleteTarget = { pk: userObj.pk, uuid: userObj.uuid, name: userObj.name || userObj.username };
		deleteError = '';
		deleteDialogOpen = true;
	}
</script>

{#if isLoading}
	<div class="space-y-3">{#each Array(5) as _}<Skeleton class="h-12" />{/each}</div>
{:else if hasError}
	<StatusCard variant="error" title="Failed to load users" description={errorMessage} onRetry={handleRetry} />
{:else if !hasUsers}
	<StatusCard variant="info" title="No students yet" description="Create the first student to get started." />
{:else}
	<Table>
		<TableHeader>
			<TableRow>
				<TableHead>Name</TableHead>
				<TableHead>Email</TableHead>
				<TableHead>Class</TableHead>
				<TableHead>Auth Status</TableHead>
				<TableHead>Activate</TableHead>
				<TableHead>Action</TableHead>
			</TableRow>
		</TableHeader>
		<TableBody>
			{#each users as userObj (userObj.pk)}
				{@const userRole = userObj.groups?.map((g: string) => allGroups.find(ag => ag.pk === g)?.name).find((n: string | undefined) => n === 'superadmin') ? 'SuperAdmin' : 'User'}
				<TableRow>
					<TableCell>{userObj.name || userObj.username} {#if userRole === 'SuperAdmin'}<Badge variant="secondary" class="ml-1 text-xs">SuperAdmin</Badge>{/if}</TableCell>
					<TableCell>{userObj.email || '\u2014'}</TableCell>
					<TableCell></TableCell>
					<TableCell><Badge variant={userObj.is_active ? 'default' : 'secondary'}>{userObj.is_active ? 'Active' : 'Inactive'}</Badge></TableCell>
					<TableCell>
						{#if authStates[userObj.pk] === 'loading'}
							<div class="h-4 w-4 animate-spin rounded-full border-2 border-primary-500 border-t-transparent"></div>
						{:else}
							<AppButton variant="outline" size="sm" onclick={() => userObj.is_active ? handleDeactivate(userObj.pk) : handleActivate(userObj.pk)}>
								{userObj.is_active ? 'Deactivate' : 'Activate'}
							</AppButton>
						{/if}
					</TableCell>
					<TableCell>
						<div class="flex gap-2">
							<AppButton variant="outline" size="sm" onclick={() => openEditDialog(userObj)}>Edit</AppButton>
							<AppButton variant="outline" size="sm" class="text-destructive" onclick={() => openDeleteDialog(userObj)}>Delete</AppButton>
						</div>
					</TableCell>
				</TableRow>
			{/each}
		</TableBody>
	</Table>
{/if}

<!-- Create Dialog -->
<Dialog open={showCreateDialog} onOpenChange={(v: boolean) => v ? null : closeCreate()}>
	<DialogContent class="sm:max-w-lg">
		<DialogHeader><DialogTitle>Create Student</DialogTitle><DialogDescription>Fill in the student details below.</DialogDescription></DialogHeader>
		<div class="space-y-4">
			<div class="space-y-2"><Label for="c-username">Username <span class="text-destructive">*</span></Label><Input id="c-username" bind:value={createForm.username} required minlength={3} /></div>
			<NameFields bind:surname={createForm.surname} bind:firstName={createForm.firstName} bind:middleName={createForm.middleName} />
			<div class="space-y-2"><Label for="c-email">Email <span class="text-destructive">*</span></Label><Input id="c-email" type="email" bind:value={createForm.email} required /></div>
			<div class="space-y-2">
				<Label for="c-password">Password <span class="text-destructive">*</span></Label>
				<div class="flex gap-2">
					<Input id="c-password" type={createForm.showPassword ? 'text' : 'password'} bind:value={createForm.password} required minlength={8} />
					<AppButton variant="outline" size="sm" onclick={() => createForm.showPassword = !createForm.showPassword}>{createForm.showPassword ? 'Hide' : 'Show'}</AppButton>
					<AppButton variant="outline" size="sm" onclick={() => { createForm.password = generatePassword(); createForm.showPassword = true; }}>Generate</AppButton>
				</div>
			</div>
			<div class="space-y-2"><Label for="c-dob">Date of Birth <span class="text-destructive">*</span></Label><Input id="c-dob" type="date" bind:value={createForm.dob} required /></div>
			<div class="space-y-2">
				<Label for="c-class">Class Level <span class="text-destructive">*</span></Label>
				{#if classLevelsLoading}
					<div class="text-sm text-muted-foreground">Loading...</div>
				{:else}
					<select id="c-class" bind:value={createForm.classLevel} required class="w-full rounded-md border border-border bg-background px-3 py-2 text-sm dark:bg-surface-900">
						<option value="" disabled>Select class...</option>
						{#each classLevels as cl}<option value={cl.name}>{cl.name}</option>{/each}
					</select>
				{/if}
			</div>
			<div class="space-y-2"><Label>Passport Photo <span class="text-destructive">*</span></Label><PassportUpload bind:this={passportUpload} currentUrl={null} disabled={createLoading} /></div>
			<label class="flex items-center gap-2 text-sm"><input type="checkbox" bind:checked={createForm.isActive} class="rounded" /> Activate on creation</label>
			{#if createError}<p class="text-sm text-destructive">{createError}</p>{/if}
			<div class="flex justify-end gap-2"><AppButton variant="outline" onclick={closeCreate} disabled={createLoading}>Cancel</AppButton><AppButton onclick={handleCreate} loading={createLoading}>Create</AppButton></div>
		</div>
	</DialogContent>
</Dialog>

<!-- Edit Dialog -->
<Dialog open={editDialogOpen} onOpenChange={(v: boolean) => v ? null : closeEdit()}>
	<DialogContent class="sm:max-w-lg">
		<DialogHeader><DialogTitle>Edit Student</DialogTitle><DialogDescription>Update the student details.</DialogDescription></DialogHeader>
		<div class="space-y-4">
			{#if editProfileLoading}<div class="text-sm text-muted-foreground">Loading profile...</div>{/if}
			<div class="space-y-2"><Label for="e-username">Username <span class="text-destructive">*</span></Label><Input id="e-username" bind:value={editForm.username} required minlength={3} /></div>
			<NameFields bind:surname={editForm.surname} bind:firstName={editForm.firstName} bind:middleName={editForm.middleName} />
			<div class="space-y-2"><Label for="e-email">Email <span class="text-destructive">*</span></Label><Input id="e-email" type="email" bind:value={editForm.email} required /></div>
			<div class="space-y-2">
				<Label for="e-password">Password</Label>
				<div class="flex gap-2">
					<Input id="e-password" type={editForm.showPassword ? 'text' : 'password'} bind:value={editForm.password} minlength={8} placeholder="Leave blank to keep current" />
					<AppButton variant="outline" size="sm" onclick={() => editForm.showPassword = !editForm.showPassword}>{editForm.showPassword ? 'Hide' : 'Show'}</AppButton>
					<AppButton variant="outline" size="sm" onclick={() => { editForm.password = generatePassword(); editForm.showPassword = true; }}>Generate</AppButton>
				</div>
			</div>
			<div class="space-y-2"><Label for="e-dob">Date of Birth <span class="text-destructive">*</span></Label><Input id="e-dob" type="date" bind:value={editForm.dob} required /></div>
			<div class="space-y-2">
				<Label for="e-class">Class Level <span class="text-destructive">*</span></Label>
				<select id="e-class" bind:value={editForm.classLevel} required class="w-full rounded-md border border-border bg-background px-3 py-2 text-sm dark:bg-surface-900">
					<option value="" disabled>Select class...</option>
					{#each classLevels as cl}<option value={cl.name} selected={cl.name === editForm.classLevel}>{cl.name}</option>{/each}
				</select>
			</div>
			<div class="space-y-2"><Label>Passport Photo <span class="text-destructive">*</span></Label><PassportUpload bind:this={editPassportUpload} currentUrl={editForm.currentPassport || null} disabled={editLoading} /></div>
			{#if editError}<p class="text-sm text-destructive">{editError}</p>{/if}
			<div class="flex justify-end gap-2"><AppButton variant="outline" onclick={closeEdit} disabled={editLoading}>Cancel</AppButton><AppButton onclick={handleEdit} loading={editLoading}>Save</AppButton></div>
		</div>
	</DialogContent>
</Dialog>

<!-- Delete Dialog -->
<AlertDialog.Root open={deleteDialogOpen} onOpenChange={(v: boolean) => v ? null : deleteDialogOpen = false}>
	<AlertDialog.Content>
		<AlertDialog.Header><AlertDialog.Title>Delete Student</AlertDialog.Title><AlertDialog.Description>Are you sure you want to delete {deleteTarget?.name}? This action cannot be undone.</AlertDialog.Description></AlertDialog.Header>
		{#if deleteError}<p class="text-sm text-destructive px-4">{deleteError}</p>{/if}
		<AlertDialog.Footer><AlertDialog.Cancel disabled={deleteLoading}>Cancel</AlertDialog.Cancel><AlertDialog.Action onclick={handleDelete} class="bg-error-500 hover:bg-error-600" disabled={deleteLoading}>Delete</AlertDialog.Action></AlertDialog.Footer>
	</AlertDialog.Content>
</AlertDialog.Root>
