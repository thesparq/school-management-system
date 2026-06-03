<script lang="ts">
	import {
		Table,
		TableBody,
		TableCell,
		TableHead,
		TableHeader,
		TableRow
	} from '$lib/components/ui/table';
	import { Badge } from '$lib/components/ui/badge';
	import { Card, CardContent } from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { Alert, AlertDescription, AlertTitle } from '$lib/components/ui/alert';
	import { Skeleton } from '$lib/components/ui/skeleton';
	import { Label } from '$lib/components/ui/label';
	import {
		Dialog,
		DialogContent,
		DialogHeader,
		DialogTitle,
		DialogDescription
	} from '$lib/components/ui/dialog';
	import { onMount } from 'svelte';
	import { addToast } from '$lib/stores/toast';

	interface ClassLevel {
		name: string;
	}

	interface UserGroup {
		pk: string;
		name: string;
	}

	interface SubjectPair {
		edge_id: string;
		class_level_id: string;
		class_level_name: string;
		subject_id: string;
		subject_name: string;
		subject_code: string | null;
	}

	interface UserProfile {
		auth_id: string;
		role: string;
		class_level: string;
		created_at: string;
	}

	let {
		users = $bindable([]),
		allGroups = $bindable([] as UserGroup[]),
		role = 'students',
		groupPk = '',
		isLoading = false,
		hasError = false,
		errorMessage = '',
		showCreateDialog = $bindable(false)
	}: {
		users: Array<{
			pk: number;
			uuid: string;
			username: string;
			name: string;
			email: string;
			groups: string[];
			is_active: boolean;
		}>;
		allGroups: UserGroup[];
		role: string;
		groupPk?: string;
		isLoading?: boolean;
		hasError?: boolean;
		errorMessage?: string;
		showCreateDialog?: boolean;
	} = $props();

	let hasUsers = $derived(users.length > 0);

	let authStates = $state<Record<number, string>>({});
	let classLevels = $state<ClassLevel[]>([]);
	let classLevelsLoading = $state(true);

	let allSubjectPairs = $state<SubjectPair[]>([]);
	let subjectPairsError = $state('');
	let subjectPairsLoading = $state(true);
	let currentTeacherPairs = $state<Record<number, SubjectPair[]>>({});
	let selectedSubjectPair = $state<Record<number, SubjectPair | null>>({});
	let subjectPairSearch = $state<Record<number, string>>({});
	let subjectPairDropdownOpen = $state<Record<number, boolean>>({});
	let teacherSubjectLoading = $state<Record<number, string>>({});
	let teacherPairsLoading = $state<Record<number, boolean>>({});
	let activeSessionTerm = $state<{ id: string; session: string; term_name: string } | null>(null);

	function filterSubjectPairs(search: string, addedPairs: SubjectPair[]): SubjectPair[] {
		const q = search.toLowerCase().replace(/\s+/g, '');
		const addedSet = new Set(addedPairs.map(p => `${p.class_level_id}||${p.subject_id}`));
		let results = allSubjectPairs.filter(p => {
			if (addedSet.has(`${p.class_level_id}||${p.subject_id}`)) return false;
			if (!q) return true;
			const target = `${p.class_level_name} ${p.subject_name} ${p.subject_code || ''}`
				.toLowerCase()
				.replace(/\s+/g, '');
			for (let i = 0; i < q.length; i++) {
				if (!target.includes(q[i])) return false;
			}
			return true;
		});
		if (q) {
			results = results.sort((a, b) => {
				const na = `${a.class_level_name} ${a.subject_name}`.toLowerCase().replace(/\s+/g, '');
				const nb = `${b.class_level_name} ${b.subject_name}`.toLowerCase().replace(/\s+/g, '');
				const aSub = na.includes(q);
				const bSub = nb.includes(q);
				if (aSub && !bSub) return -1;
				if (!aSub && bSub) return 1;
				return na.indexOf(q) - nb.indexOf(q);
			});
		}
		return results;
	}

	let createForm = $state({ username: '', name: '', email: '', password: '', isActive: true, showPassword: false, role: '', classLevel: '' });
	let createLoading = $state(false);
	let createError = $state('');

	let editForm = $state({ uuid: '', authentikPk: 0, username: '', name: '', email: '', password: '', showPassword: false, role: '', classLevel: '' });
	let editLoading = $state(false);
	let editError = $state('');
	let editDialogOpen = $state(false);
	let editProfileLoading = $state(false);

	let classAssignDialogOpen = $state(false);
	let classAssignTeacherUuid = $state('');
	let classAssignTeacherPk = $state(0);

	let deleteLoading = $state(false);
	let deleteError = $state('');
	let deleteTarget = $state<{ pk: number; uuid: string; name: string } | null>(null);

	function generatePassword(): string {
		const upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
		const lower = 'abcdefghijklmnopqrstuvwxyz';
		const digits = '0123456789';
		const all = upper + lower + digits;
		let pw = '';
		const array = new Uint8Array(16);
		crypto.getRandomValues(array);
		for (let i = 0; i < 16; i++) {
			pw += all[array[i] % all.length];
		}
		return pw;
	}

	let roleLabel = $derived(
		role === 'students' ? 'student' : role === 'teachers' ? 'teacher' : 'admin'
	);

	let superAdminGroupPk = $derived(allGroups.find(g => g.name === 'superadmin')?.pk ?? '');

	let roleDisplayMap = $derived<Record<string, string>>({
		'student': 'student',
		'teacher': 'teacher',
		'admin': 'admin'
	});

	function getRoleFromGroups(userGroups: string[]): string {
		for (const g of allGroups) {
			if (userGroups.includes(g.pk) && g.name in roleDisplayMap) {
				return roleDisplayMap[g.name];
			}
		}
		return '';
	}

	async function loadAllSubjectPairs() {
		subjectPairsLoading = true;
		subjectPairsError = '';
		try {
			const res = await fetch('/api/admin/class-subjects');
			if (!res.ok) {
				const body = await res.json().catch(() => ({}));
				throw new Error(body.error?.message || `HTTP ${res.status}`);
			}
			const body = await res.json();
			if (body.data) {
				allSubjectPairs = (body.data as SubjectPair[]).slice().sort((a, b) => {
					const cl = a.class_level_name.localeCompare(b.class_level_name);
					if (cl !== 0) return cl;
					return a.subject_name.localeCompare(b.subject_name);
				});
			} else {
				throw new Error('Gateway returned empty response');
			}
		} catch (err) {
			allSubjectPairs = [];
			subjectPairsError = err instanceof Error ? err.message : 'Failed to load class-subjects';
		} finally {
			subjectPairsLoading = false;
		}
	}

	async function loadTeacherPairs(uuid: string, pk: number) {
		if (!uuid) return;
		teacherPairsLoading = { ...teacherPairsLoading, [pk]: true };
		try {
			const res = await fetch(`/api/admin/teacher/${uuid}/subjects`);
			if (!res.ok) throw new Error('Failed');
			const body = await res.json();
			if (body.data && Array.isArray(body.data)) currentTeacherPairs = { ...currentTeacherPairs, [pk]: body.data };
			else throw new Error('Invalid response');
		} catch {
			currentTeacherPairs = { ...currentTeacherPairs, [pk]: [] };
		} finally {
			teacherPairsLoading = { ...teacherPairsLoading, [pk]: false };
		}
	}

	async function handleSaveTeacherSubjects() {
		const pk = classAssignTeacherPk;
		const uuid = classAssignTeacherUuid;
		if (!pk || !uuid) return;
		teacherSubjectLoading = { ...teacherSubjectLoading, [pk]: 'loading' };
		try {
			const minimalPairs = (currentTeacherPairs[pk] || []).map(p => ({
				has_subject_id: p.edge_id,
				class_level_id: p.class_level_id,
				subject_id: p.subject_id
			}));
			const res = await fetch('/api/admin/teacher/subjects', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					target_teacher_id: uuid,
					pairs: minimalPairs
				})
			});
			const body = await res.json();
			if (!res.ok || body.error) throw new Error(body.error?.message || 'Save failed');
			classAssignDialogOpen = false;
			addToast('success', 'Assignments saved', 'Teacher assignments have been updated.');
		} catch (err) {
			addToast('error', 'Save failed', err instanceof Error ? err.message : 'Save failed');
		} finally {
			teacherSubjectLoading = { ...teacherSubjectLoading, [pk]: 'idle' };
		}
	}

	async function loadClassLevels() {
		classLevelsLoading = true;
		try {
			const res = await fetch('/api/admin/class-levels');
			if (!res.ok) throw new Error('Failed to load class levels');
			const body = await res.json();
			if (body.data) {
				classLevels = body.data;
			}
		} catch {
			classLevels = [];
		} finally {
			classLevelsLoading = false;
		}
	}

	onMount(() => {
		if (role === 'students') {
			loadClassLevels();
		}
		if (role === 'teachers') {
			loadAllSubjectPairs();
		}
	});

	function handleRetry() {
		window.location.reload();
	}

	function authentikStatusBadge(isActive: boolean) {
		return isActive
			? { variant: 'default' as const, label: 'Active' }
			: { variant: 'secondary' as const, label: 'Inactive' };
	}

	function getUser(pk: number) {
		return users.find(u => u.pk === pk);
	}

	async function openEditDialog(userObj: { pk: number; uuid: string; username: string; name: string; email: string; groups: string[] }) {
		const roleVal = getRoleFromGroups(userObj.groups) || roleLabel;
		editForm = {
			uuid: userObj.uuid,
			authentikPk: userObj.pk,
			username: userObj.username,
			name: userObj.name,
			email: userObj.email,
			password: '',
			showPassword: false,
			role: roleVal,
			classLevel: ''
		};
		editError = '';
		editDialogOpen = true;
		editProfileLoading = false;

		if (role === 'students') {
			editProfileLoading = true;
			try {
				const res = await fetch(`/api/admin/users/${userObj.uuid}/profile`);
				if (res.ok) {
					const body = await res.json();
					if (body.data) {
						const p = body.data as UserProfile;
						editForm.role = p.role || roleVal;
						editForm.classLevel = p.class_level || '';
					}
				}
			} catch {
			} finally {
				editProfileLoading = false;
			}
		}
	}

	async function handleEditUser() {
		if (!editForm.username || !editForm.name || !editForm.email || !editForm.role) return;
		editLoading = true;
		editError = '';
		try {
			const res = await fetch(`/api/admin/users/${editForm.uuid}/edit-profile`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					authentikPk: editForm.authentikPk,
					username: editForm.username,
					name: editForm.name,
					email: editForm.email,
					password: editForm.password || undefined,
					role: editForm.role,
					class_level: editForm.classLevel || undefined
				})
			});
			const body = await res.json();
			if (!res.ok || body.error) {
				throw new Error(body.error?.message || 'Save failed');
			}
			const userObj = users.find(u => u.uuid === editForm.uuid);
			if (userObj) {
				userObj.username = editForm.username;
				userObj.name = editForm.name;
				userObj.email = editForm.email;
			}
			editDialogOpen = false;
			addToast('success', 'User updated', editForm.name || editForm.username);
		} catch (err) {
			editError = err instanceof Error ? err.message : 'Save failed';
			addToast('error', 'Edit failed', err instanceof Error ? err.message : 'Save failed');
		} finally {
			editLoading = false;
		}
	}

	async function handleActivateAuthentik(pk: number) {
		const userObj = getUser(pk);
		if (!userObj) return;
		authStates = { ...authStates, [pk]: 'loading' };
		try {
			const res = await fetch(`/api/admin/users/${pk}/activate-authentik`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' }
			});
			const body = await res.json();
			if (!res.ok || body.error) {
				throw new Error(body.error?.message || 'Activation failed');
			}
			userObj.is_active = true;
			addToast('info', 'User activated', userObj.name || userObj.username);
		} catch (err) {
			addToast('error', 'Activation failed', err instanceof Error ? err.message : 'Activation failed');
		} finally {
			authStates = { ...authStates, [pk]: 'idle' };
		}
	}

	async function handleDeactivateAuthentik(pk: number) {
		const userObj = getUser(pk);
		if (!userObj) return;
		authStates = { ...authStates, [pk]: 'loading' };
		try {
			const res = await fetch(`/api/admin/users/${pk}/deactivate-authentik`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' }
			});
			const body = await res.json();
			if (!res.ok || body.error) {
				throw new Error(body.error?.message || 'Deactivation failed');
			}
			userObj.is_active = false;
			addToast('info', 'User deactivated', userObj.name || userObj.username);
		} catch (err) {
			addToast('error', 'Deactivation failed', err instanceof Error ? err.message : 'Deactivation failed');
		} finally {
			authStates = { ...authStates, [pk]: 'idle' };
		}
	}

	async function handleCreateUser() {
		if (!createForm.username || !createForm.name || !createForm.email || !createForm.password) return;
		createForm.role = roleLabel;
		createLoading = true;
		createError = '';
		try {
			const res = await fetch('/api/admin/users', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					username: createForm.username,
					name: createForm.name,
					email: createForm.email,
					password: createForm.password,
					is_active: createForm.isActive,
					group_pk: groupPk,
					role: createForm.role,
					class_level: createForm.classLevel || undefined
				})
			});
			const body = await res.json();
			if (!res.ok || body.error) {
				throw new Error(body.error?.message || 'Create failed');
			}
			users = [...users, body.data];
			showCreateDialog = false;
			addToast('success', 'User created', `${createForm.name} (${createForm.username})`);
			createForm = { username: '', name: '', email: '', password: '', isActive: true, showPassword: false, role: '', classLevel: '' };
		} catch (err) {
			createError = err instanceof Error ? err.message : 'Create failed';
			addToast('error', 'Create failed', err instanceof Error ? err.message : 'Create failed');
		} finally {
			createLoading = false;
		}
	}

	async function handleDeleteUser() {
		if (!deleteTarget) return;
		const pk = deleteTarget.pk;
		const userObj = getUser(pk);
		if (!userObj) return;
		deleteLoading = true;
		deleteError = '';
		try {
			const res = await fetch(`/api/admin/users/${pk}?uuid=${encodeURIComponent(deleteTarget.uuid)}`, {
				method: 'DELETE'
			});
			const body = await res.json();
			if (!res.ok || body.error) {
				throw new Error(body.error?.message || 'Delete failed');
			}
			users = users.filter(u => u.pk !== pk);
			addToast('success', 'User deleted', deleteTarget.name);
			deleteTarget = null;
		} catch (err) {
			deleteError = err instanceof Error ? err.message : 'Delete failed';
			addToast('error', 'Delete failed', err instanceof Error ? err.message : 'Delete failed');
		} finally {
			deleteLoading = false;
		}
	}

	async function openClassAssign(userObj: { pk: number; uuid: string }) {
		classAssignTeacherUuid = userObj.uuid;
		classAssignTeacherPk = userObj.pk;
		currentTeacherPairs = { ...currentTeacherPairs, [userObj.pk]: [] };
		teacherPairsLoading = { ...teacherPairsLoading, [userObj.pk]: true };
		subjectPairDropdownOpen = { ...subjectPairDropdownOpen, [userObj.pk]: false };
		subjectPairSearch = { ...subjectPairSearch, [userObj.pk]: '' };
		selectedSubjectPair = { ...selectedSubjectPair, [userObj.pk]: null };
		activeSessionTerm = null;
		try {
			const res = await fetch('/api/admin/active-session-term');
			if (res.ok) {
				const body = await res.json();
				if (body.data && body.data.id) activeSessionTerm = body.data;
			}
		} catch { /* ignore */ }
		loadTeacherPairs(userObj.uuid, userObj.pk);
		classAssignDialogOpen = true;
	}
</script>

{#if isLoading}
	<Card>
		<CardContent class="p-4 space-y-3">
			{#each Array(5) as _}
				<div class="flex gap-4">
					<Skeleton class="h-4 flex-1" />
					<Skeleton class="h-4 flex-1" />
					<Skeleton class="h-4 w-24" />
					<Skeleton class="h-4 w-24" />
					<Skeleton class="h-4 w-20" />
					<Skeleton class="h-4 w-16" />
				</div>
			{/each}
		</CardContent>
	</Card>

{:else if hasError}
	<Alert variant="destructive">
		<AlertTitle>Failed to load users</AlertTitle>
		<AlertDescription>{errorMessage}</AlertDescription>
		<Button onclick={handleRetry} variant="outline" class="mt-3 cursor-pointer">Retry</Button>
	</Alert>

{:else if !hasUsers}
	<Card>
		<CardContent class="py-12 text-center space-y-4">
			<div class="mx-auto w-fit rounded-full bg-surface-100 p-4">
				<svg class="h-8 w-8 text-surface-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
					<path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z" />
				</svg>
			</div>
			<div>
				<p class="text-lg font-medium text-surface-800">No {role} yet</p>
				<p class="mt-1 text-sm text-surface-600 max-w-sm mx-auto">
					Assign users to the &quot;{role}&quot; group in Authentik, then reload this page. Users must be internal members of the group to appear here.
				</p>
			</div>
		</CardContent>
	</Card>

{:else}
	<Card>
		<CardContent class="p-0">
			<Table>
				<TableHeader>
					<TableRow>
						<TableHead>Name</TableHead>
						<TableHead>Email</TableHead>
						<TableHead>Auth Status</TableHead>
						<TableHead class="w-24">Activate</TableHead>
						<TableHead class="w-28">Action</TableHead>
						{#if role === 'teachers'}
							<TableHead class="w-28">Classes</TableHead>
						{/if}
					</TableRow>
				</TableHeader>
				<TableBody>
					{#each users as userObj (userObj.pk)}
						{@const authStatus = authentikStatusBadge(userObj.is_active)}
						{@const isSuperAdmin = superAdminGroupPk && userObj.groups.includes(superAdminGroupPk)}
						{@const isAuthLoading = authStates[userObj.pk] === 'loading'}
						<TableRow>
							<TableCell class="font-medium">
								<span>{userObj.name || userObj.username}</span>
								{#if isSuperAdmin}
									<Badge variant="outline" class="ml-1 text-xs">SuperAdmin</Badge>
								{/if}
							</TableCell>
							<TableCell class="text-surface-700">
								{userObj.email || '—'}
							</TableCell>
							<TableCell>
								<Badge variant={authStatus.variant}>{authStatus.label}</Badge>
							</TableCell>
							<TableCell>
								<Button
									variant={userObj.is_active ? 'destructive' : 'default'}
									size="sm"
									class="cursor-pointer"
									onclick={() => userObj.is_active ? handleDeactivateAuthentik(userObj.pk) : handleActivateAuthentik(userObj.pk)}
									disabled={isAuthLoading}
								>
									{userObj.is_active ? 'Deactivate' : 'Activate'}
								</Button>
							</TableCell>
							<TableCell>
								<Button
									variant="outline"
									size="sm"
									class="cursor-pointer"
									onclick={() => openEditDialog(userObj)}
								>
									Edit
								</Button>
							</TableCell>
							{#if role === 'teachers'}
								<TableCell>
									<Button
										variant="outline"
										size="sm"
										class="cursor-pointer"
										onclick={() => openClassAssign(userObj)}
									>
										{#if teacherPairsLoading[userObj.pk]}
											<span class="inline-block h-4 w-4 animate-spin rounded-full border-2 border-surface-300 border-t-surface-700 mr-1"></span> Loading
										{:else}
											Assign
										{/if}
									</Button>
								</TableCell>
							{/if}
						</TableRow>
					{/each}
				</TableBody>
			</Table>
		</CardContent>
	</Card>
{/if}

<Dialog open={editDialogOpen} onOpenChange={(o) => { editDialogOpen = o; if (!o) editError = ''; }}>
	<DialogContent>
		<DialogHeader>
			<DialogTitle>Edit User</DialogTitle>
			<DialogDescription>
				Update user details. Changes are saved to both Authentik and the database.
			</DialogDescription>
		</DialogHeader>
		<form class="space-y-4" onsubmit={(e) => { e.preventDefault(); handleEditUser(); }}>
			<div class="space-y-2">
				<Label for="edit-username">Username</Label>
				<Input id="edit-username" bind:value={editForm.username} required minlength={3} />
			</div>
			<div class="space-y-2">
				<Label for="edit-name">Full Name</Label>
				<Input id="edit-name" bind:value={editForm.name} required />
			</div>
			<div class="space-y-2">
				<Label for="edit-email">Email</Label>
				<Input id="edit-email" type="email" bind:value={editForm.email} required />
			</div>
			<div class="space-y-2">
				<Label for="edit-password">Password (leave blank to keep current)</Label>
				<div class="relative">
					<Input
						id="edit-password"
						type={editForm.showPassword ? 'text' : 'password'}
						bind:value={editForm.password}
						minlength={8}
					/>
					<button
						type="button"
						class="absolute right-2 top-1/2 -translate-y-1/2 text-surface-500 hover:text-surface-700 cursor-pointer"
						onclick={() => editForm.showPassword = !editForm.showPassword}
					>
						{editForm.showPassword ? 'Hide' : 'Show'}
					</button>
				</div>
				<button
					type="button"
					class="text-xs text-primary-600 hover:text-primary-800 cursor-pointer"
					onclick={() => { editForm.password = generatePassword(); editForm.showPassword = true; }}
				>
					Generate random password
				</button>
			</div>
			<div class="space-y-2">
				<Label for="edit-role">Role</Label>
				<select
					id="edit-role"
					class="flex h-9 w-full rounded-none border border-input bg-transparent px-3 py-1 text-sm text-surface-800 transition-colors focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-1 cursor-not-allowed"
					bind:value={editForm.role}
					disabled
				>
					<option value="admin">Admin</option>
					<option value="teacher">Teacher</option>
					<option value="student">Student</option>
				</select>
			</div>
			{#if editForm.role === 'student'}
				<div class="space-y-2">
					<Label for="edit-class-level">Class Level</Label>
					<select
						id="edit-class-level"
						class="flex h-9 w-full rounded-none border border-input bg-transparent px-3 py-1 text-sm text-surface-800 transition-colors focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-1 disabled:opacity-50 cursor-pointer"
						bind:value={editForm.classLevel}
						disabled={classLevelsLoading}
					>
						{#if classLevelsLoading}
							<option value="" disabled>Loading…</option>
						{:else if classLevels.length === 0}
							<option value="" disabled>No classes available</option>
						{:else}
							<option value="" disabled>Select class…</option>
							{#each classLevels as cl}
								<option value={cl.name}>{cl.name}</option>
							{/each}
						{/if}
					</select>
				</div>
			{/if}
			{#if editError}
				<p class="text-sm text-error-500">{editError}</p>
			{/if}
			<div class="flex justify-end gap-2">
				<Button
					type="button"
					variant="destructive"
					onclick={() => { deleteTarget = { pk: editForm.authentikPk, uuid: editForm.uuid, name: editForm.name }; editDialogOpen = false; }}
					class="cursor-pointer"
					disabled={editProfileLoading}
				>
					Delete User
				</Button>
				<Button
					type="button"
					variant="outline"
					onclick={() => { editDialogOpen = false; editError = ''; }}
					class="cursor-pointer"
				>
					Cancel
				</Button>
				<Button
					type="submit"
					variant="default"
					disabled={editLoading || editProfileLoading || !editForm.username || !editForm.name || !editForm.email || !editForm.role}
					class="cursor-pointer"
				>
					{editLoading ? 'Saving...' : 'Save'}
				</Button>
			</div>
		</form>
	</DialogContent>
</Dialog>

<Dialog open={classAssignDialogOpen} onOpenChange={(o) => { classAssignDialogOpen = o; }}>
	<DialogContent class="max-w-lg">
		<DialogHeader>
			<DialogTitle>Class Subjects</DialogTitle>
			<DialogDescription>Manage class-subject assignments for this teacher.</DialogDescription>
		</DialogHeader>
		<div class="space-y-4">
			{#if activeSessionTerm}
				<div class="space-y-1">
					<span class="text-xs font-medium text-surface-500">Session Term</span>
					<input
						type="text"
						value="{activeSessionTerm.session} — {activeSessionTerm.term_name}"
						disabled
						class="h-9 w-full rounded-none border border-input bg-surface-100 px-3 py-1 text-sm text-surface-700"
					/>
				</div>
			{:else}
				<div class="rounded border border-amber-200 bg-amber-50 px-3 py-2">
					<p class="text-xs text-amber-700">No active session term. Assignments cannot be saved until a session term is set.</p>
				</div>
			{/if}
			<div class="flex flex-wrap gap-1.5">
				{#each (currentTeacherPairs[classAssignTeacherPk] || []) as pair}
					<span class="inline-flex items-center gap-1 rounded-md bg-primary-100 px-2 py-0.5 text-xs font-medium text-primary-700">
						{pair.class_level_name} — {pair.subject_name}
						<button
							type="button"
							aria-label="Remove {pair.subject_name}"
							class="inline-flex items-center justify-center rounded-full p-0.5 text-primary-500 hover:bg-primary-200 hover:text-primary-800 transition-colors cursor-pointer"
							onclick={() => {
								currentTeacherPairs = {
									...currentTeacherPairs,
									[classAssignTeacherPk]: (currentTeacherPairs[classAssignTeacherPk] || []).filter(
										(p: SubjectPair) => !(p.class_level_id === pair.class_level_id && p.subject_id === pair.subject_id)
									)
								};
							}}
						>
							<svg class="h-3 w-3" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
								<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
							</svg>
						</button>
					</span>
				{/each}
				{#if (currentTeacherPairs[classAssignTeacherPk] || []).length === 0}
					{#if teacherPairsLoading[classAssignTeacherPk]}
						<span class="text-xs text-surface-500 italic">Loading…</span>
					{:else}
						<span class="text-xs text-surface-500 italic">No subjects assigned</span>
					{/if}
				{/if}
			</div>

			{#if subjectPairsLoading}
				<div class="text-xs text-surface-500 italic">Loading class-subject pairs…</div>
			{:else if subjectPairsError}
				<div class="text-xs text-error-500">{subjectPairsError}</div>
			{:else if allSubjectPairs.length === 0}
				<div class="text-xs text-surface-500 italic">No class-subject pairs available in database</div>
			{:else}
				<div class="relative">
					<div class="flex items-center gap-2">
						<div class="relative flex-1">
							<input
								type="text"
								placeholder="Search class level or subject…"
								class="h-8 w-full rounded-none border border-input bg-transparent px-2.5 py-1 pr-8 text-sm text-surface-800 transition-colors placeholder:text-surface-400 focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-1"
								value={subjectPairSearch[classAssignTeacherPk] || ''}
								onfocus={() => { subjectPairDropdownOpen = { ...subjectPairDropdownOpen, [classAssignTeacherPk]: true }; }}
								oninput={(e) => {
									subjectPairSearch = { ...subjectPairSearch, [classAssignTeacherPk]: e.currentTarget.value };
									subjectPairDropdownOpen = { ...subjectPairDropdownOpen, [classAssignTeacherPk]: true };
								}}
								onblur={() => {
									setTimeout(() => { subjectPairDropdownOpen = { ...subjectPairDropdownOpen, [classAssignTeacherPk]: false }; }, 200);
								}}
							/>
							{#if subjectPairDropdownOpen[classAssignTeacherPk]}
								<div class="absolute left-0 right-0 top-full z-10 mt-0.5 max-h-48 overflow-y-auto border border-input bg-white shadow-lg">
									{#each filterSubjectPairs(subjectPairSearch[classAssignTeacherPk] || '', currentTeacherPairs[classAssignTeacherPk] || []) as pair}
										<button
											type="button"
											class="block w-full px-2.5 py-1.5 text-left text-sm hover:bg-surface-100 cursor-pointer"
											onmousedown={() => {
												selectedSubjectPair = { ...selectedSubjectPair, [classAssignTeacherPk]: pair };
												subjectPairSearch = { ...subjectPairSearch, [classAssignTeacherPk]: `${pair.class_level_name} — ${pair.subject_name}` };
												subjectPairDropdownOpen = { ...subjectPairDropdownOpen, [classAssignTeacherPk]: false };
											}}
										>
											{pair.class_level_name} — {pair.subject_name}
										</button>
									{:else}
										<div class="px-2.5 py-1.5 text-xs text-surface-500 italic">No matches</div>
									{/each}
								</div>
							{/if}
						</div>
						<Button
							variant="default"
							size="sm"
							class="cursor-pointer shrink-0"
							disabled={!selectedSubjectPair[classAssignTeacherPk] || !activeSessionTerm || teacherSubjectLoading[classAssignTeacherPk] === 'loading'}
							onclick={() => {
								const pair = selectedSubjectPair[classAssignTeacherPk];
								if (!pair) return;
								currentTeacherPairs = {
									...currentTeacherPairs,
									[classAssignTeacherPk]: [...(currentTeacherPairs[classAssignTeacherPk] || []), pair]
								};
								selectedSubjectPair = { ...selectedSubjectPair, [classAssignTeacherPk]: null };
								subjectPairSearch = { ...subjectPairSearch, [classAssignTeacherPk]: '' };
							}}
						>
							Add
						</Button>
					</div>
				</div>
			{/if}

			<div class="flex justify-end gap-2">
				<Button
					type="button"
					variant="outline"
					onclick={() => { classAssignDialogOpen = false; }}
					class="cursor-pointer"
				>
					Cancel
				</Button>
				<Button
					variant="default"
					class="cursor-pointer"
					disabled={teacherSubjectLoading[classAssignTeacherPk] === 'loading' || teacherPairsLoading[classAssignTeacherPk] || !activeSessionTerm}
					onclick={handleSaveTeacherSubjects}
				>
					{teacherSubjectLoading[classAssignTeacherPk] === 'loading' ? 'Saving...' : 'Save'}
				</Button>
			</div>
		</div>
	</DialogContent>
</Dialog>

<Dialog open={showCreateDialog} onOpenChange={(o) => { showCreateDialog = o; if (!o) createError = ''; }}>
	<DialogContent>
		<DialogHeader>
			<DialogTitle>Create {role === 'admin-role' ? 'Admin' : roleLabel}</DialogTitle>
			<DialogDescription>
				Add a new user to Authentik and assign them to the {role} group.
			</DialogDescription>
		</DialogHeader>
		<form class="space-y-4" onsubmit={(e) => { e.preventDefault(); handleCreateUser(); }}>
			<div class="space-y-2">
				<Label for="create-username">Username</Label>
				<Input id="create-username" bind:value={createForm.username} required minlength={3} />
			</div>
			<div class="space-y-2">
				<Label for="create-name">Full Name</Label>
				<Input id="create-name" bind:value={createForm.name} required />
			</div>
			<div class="space-y-2">
				<Label for="create-email">Email</Label>
				<Input id="create-email" type="email" bind:value={createForm.email} required />
			</div>
			<div class="space-y-2">
				<Label for="create-password">Password</Label>
				<div class="relative">
					<Input
						id="create-password"
						type={createForm.showPassword ? 'text' : 'password'}
						bind:value={createForm.password}
						required
						minlength={8}
					/>
					<button
						type="button"
						class="absolute right-2 top-1/2 -translate-y-1/2 text-surface-500 hover:text-surface-700 cursor-pointer"
						onclick={() => createForm.showPassword = !createForm.showPassword}
					>
						{createForm.showPassword ? 'Hide' : 'Show'}
					</button>
				</div>
				<button
					type="button"
					class="text-xs text-primary-600 hover:text-primary-800 cursor-pointer"
					onclick={() => { createForm.password = generatePassword(); createForm.showPassword = true; }}
				>
					Generate random password
				</button>
			</div>
			{#if role === 'students'}
				<div class="space-y-2">
					<Label for="create-class-level">Class Level</Label>
					<select
						id="create-class-level"
						class="flex h-9 w-full rounded-none border border-input bg-transparent px-3 py-1 text-sm text-surface-800 transition-colors focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-1 disabled:opacity-50 cursor-pointer"
						bind:value={createForm.classLevel}
						disabled={classLevelsLoading}
					>
						{#if classLevelsLoading}
							<option value="" disabled>Loading…</option>
						{:else if classLevels.length === 0}
							<option value="" disabled>No classes available</option>
						{:else}
							<option value="" disabled>Select class…</option>
							{#each classLevels as cl}
								<option value={cl.name}>{cl.name}</option>
							{/each}
						{/if}
					</select>
				</div>
			{/if}
			<div class="flex items-center gap-2">
				<input
					id="create-active"
					type="checkbox"
					checked={createForm.isActive}
					onchange={(e) => createForm.isActive = e.currentTarget.checked}
					class="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500 cursor-pointer"
				/>
				<Label for="create-active">Activate user on creation</Label>
			</div>
			{#if createError}
				<p class="text-sm text-error-500">{createError}</p>
			{/if}
			<div class="flex justify-end gap-2">
				<Button
					type="button"
					variant="outline"
					onclick={() => { showCreateDialog = false; createError = ''; }}
					class="cursor-pointer"
				>
					Cancel
				</Button>
				<Button
					type="submit"
					variant="default"
					disabled={createLoading || !createForm.username || !createForm.name || !createForm.email || !createForm.password}
					class="cursor-pointer"
				>
					{createLoading ? 'Creating...' : 'Create'}
				</Button>
			</div>
		</form>
	</DialogContent>
</Dialog>

{#if deleteTarget}
	<div class="fixed inset-0 z-50 flex items-center justify-center bg-black/30" onclick={() => deleteTarget = null}>
		<div class="bg-white rounded-lg shadow-xl max-w-md w-full p-6 space-y-4" onclick={(e) => e.stopPropagation()}>
			<h3 class="text-lg font-semibold">Delete {deleteTarget.name}?</h3>
			<p class="text-sm text-surface-600">
				This permanently removes the user from Authentik. The user will lose all access. This cannot be undone.
			</p>
			{#if deleteError}
				<p class="text-sm text-error-500">{deleteError}</p>
			{/if}
			<div class="flex justify-end gap-2">
				<Button
					type="button"
					variant="outline"
					onclick={() => { deleteTarget = null; deleteError = ''; }}
					class="cursor-pointer"
				>
					Cancel
				</Button>
				<Button
					variant="destructive"
					disabled={deleteLoading}
					onclick={handleDeleteUser}
					class="cursor-pointer"
				>
					{deleteLoading ? 'Deleting...' : 'Delete'}
				</Button>
			</div>
		</div>
	</div>
{/if}
