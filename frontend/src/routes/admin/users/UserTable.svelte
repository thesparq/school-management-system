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
	import {
		AlertDialog,
		AlertDialogTrigger,
		AlertDialogContent,
		AlertDialogHeader,
		AlertDialogTitle,
		AlertDialogDescription,
		AlertDialogFooter,
		AlertDialogCancel,
		AlertDialogAction
	} from '$lib/components/ui/alert-dialog';
	import { onMount } from 'svelte';

	interface ClassLevel {
		name: string;
	}

	interface UserGroup {
		pk: string;
		name: string;
	}

	let {
		users = $bindable([]),
		initMap = $bindable({} as Record<string, string>),
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
		initMap: Record<string, string>;
		allGroups: UserGroup[];
		role: string;
		groupPk?: string;
		isLoading?: boolean;
		hasError?: boolean;
		errorMessage?: string;
		showCreateDialog?: boolean;
	} = $props();

	let hasUsers = $derived(users.length > 0);

	let expandedPk = $state<number | null>(null);
	let initStates = $state<Record<number, string>>({});
	let authStates = $state<Record<number, string>>({});
	let pwResetStates = $state<Record<number, string>>({});
	let actionErrors = $state<Record<number, string>>({});
	let classLevels = $state<ClassLevel[]>([]);
	let classLevelsLoading = $state(true);
	let selectedClassLevels = $state<Record<number, string>>({});
	let passwordInputs = $state<Record<number, string>>({});
	let passwordShowMap = $state<Record<number, boolean>>({});
	let groupSearchInputs = $state<Record<number, string>>({});
	let groupActionStates = $state<Record<number, string>>({});

	let createForm = $state({ username: '', name: '', email: '', password: '', isActive: true, showPassword: false });
	let createLoading = $state(false);
	let createError = $state('');

	let deleteLoading = $state(false);
	let deleteError = $state('');

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

	let groupMap = $derived(
		Object.fromEntries(allGroups.map(g => [g.pk, g.name]))
	);

	function getUserGroups(userPk: number): UserGroup[] {
		const userObj = users.find(u => u.pk === userPk);
		if (!userObj) return [];
		return userObj.groups
			.map(pk => allGroups.find(g => g.pk === pk))
			.filter((g): g is UserGroup => g !== undefined);
	}

	function filteredSuggestions(userPk: number): UserGroup[] {
		const userObj = users.find(u => u.pk === userPk);
		if (!userObj) return [];
		const search = (groupSearchInputs[userPk] || '').toLowerCase().trim();
		if (!search) return [];
		return allGroups.filter(
			g => g.name.toLowerCase().includes(search) && !userObj.groups.includes(g.pk)
		);
	}

	let showSuggestions = $state<Record<number, boolean>>({});

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
	});

	function handleRetry() {
		window.location.reload();
	}

	function toggleExpand(pk: number) {
		expandedPk = expandedPk === pk ? null : pk;
		if (expandedPk === pk && !(pk in selectedClassLevels)) {
			selectedClassLevels = { ...selectedClassLevels, [pk]: '' };
		}
	}

	function authentikStatusBadge(isActive: boolean) {
		return isActive
			? { variant: 'default' as const, label: 'Active' }
			: { variant: 'secondary' as const, label: 'Inactive' };
	}

	function initStatusBadge(uuid: string) {
		const initialized = uuid in initMap;
		return initialized
			? { variant: 'default' as const, label: 'Initialized' }
			: { variant: 'secondary' as const, label: 'Pending' };
	}

	function getUser(pk: number) {
		return users.find(u => u.pk === pk);
	}

	async function handleInitialize(pk: number) {
		const userObj = getUser(pk);
		if (!userObj) return;
		initStates = { ...initStates, [pk]: 'loading' };
		actionErrors = { ...actionErrors, [pk]: '' };
		initMap = { ...initMap, [userObj.uuid]: roleLabel };
		try {
			const res = await fetch(`/api/admin/users/${userObj.uuid}/initialize`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					role: roleLabel,
					...(selectedClassLevels[pk] ? { class_level: selectedClassLevels[pk] } : {})
				})
			});
			const body = await res.json();
			if (!res.ok || body.error) {
				throw new Error(body.error?.message || 'Initialization failed');
			}
		} catch (err) {
			const { [pk]: _, ...rest } = initMap;
			initMap = rest;
			actionErrors = { ...actionErrors, [pk]: err instanceof Error ? err.message : 'Initialization failed' };
		} finally {
			initStates = { ...initStates, [pk]: 'idle' };
		}
	}

	async function handleActivateAuthentik(pk: number) {
		const userObj = getUser(pk);
		if (!userObj) return;
		const origActive = userObj.is_active;
		authStates = { ...authStates, [pk]: 'loading' };
		actionErrors = { ...actionErrors, [pk]: '' };
		userObj.is_active = true;
		try {
			const res = await fetch(`/api/admin/users/${pk}/activate-authentik`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' }
			});
			const body = await res.json();
			if (!res.ok || body.error) {
				throw new Error(body.error?.message || 'Activation failed');
			}
		} catch (err) {
			userObj.is_active = origActive;
			actionErrors = { ...actionErrors, [pk]: err instanceof Error ? err.message : 'Activation failed' };
		} finally {
			authStates = { ...authStates, [pk]: 'idle' };
		}
	}

	async function handleDeactivateAuthentik(pk: number) {
		const userObj = getUser(pk);
		if (!userObj) return;
		const origActive = userObj.is_active;
		authStates = { ...authStates, [pk]: 'loading' };
		actionErrors = { ...actionErrors, [pk]: '' };
		userObj.is_active = false;
		try {
			const res = await fetch(`/api/admin/users/${pk}/deactivate-authentik`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' }
			});
			const body = await res.json();
			if (!res.ok || body.error) {
				throw new Error(body.error?.message || 'Deactivation failed');
			}
		} catch (err) {
			userObj.is_active = origActive;
			actionErrors = { ...actionErrors, [pk]: err instanceof Error ? err.message : 'Deactivation failed' };
		} finally {
			authStates = { ...authStates, [pk]: 'idle' };
		}
	}

	async function handleResetPassword(pk: number) {
		const userObj = getUser(pk);
		if (!userObj) return;
		const password = passwordInputs[pk];
		if (!password) return;
		pwResetStates = { ...pwResetStates, [pk]: 'loading' };
		actionErrors = { ...actionErrors, [pk]: '' };
		try {
			const res = await fetch(`/api/admin/users/${pk}/reset-password`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ password })
			});
			const body = await res.json();
			if (!res.ok || body.error) {
				throw new Error(body.error?.message || 'Password reset failed');
			}
			passwordInputs = { ...passwordInputs, [pk]: '' };
		} catch (err) {
			actionErrors = { ...actionErrors, [pk]: err instanceof Error ? err.message : 'Password reset failed' };
		} finally {
			pwResetStates = { ...pwResetStates, [pk]: 'idle' };
		}
	}

	async function handleAddGroup(pk: number, groupPk: string) {
		if (!groupPk) return;
		const userObj = getUser(pk);
		if (!userObj) return;
		const origGroups = [...userObj.groups];
		groupActionStates = { ...groupActionStates, [pk]: 'loading' };
		actionErrors = { ...actionErrors, [pk]: '' };
		try {
			const res = await fetch(`/api/admin/users/${pk}/add-group`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ group_pk: groupPk })
			});
			const body = await res.json();
			if (!res.ok || body.error) {
				throw new Error(body.error?.message || 'Add group failed');
			}
			userObj.groups = [...userObj.groups, groupPk];
			groupSearchInputs = { ...groupSearchInputs, [pk]: '' };
		} catch (err) {
			userObj.groups = origGroups;
			actionErrors = { ...actionErrors, [pk]: err instanceof Error ? err.message : 'Add group failed' };
		} finally {
			groupActionStates = { ...groupActionStates, [pk]: 'idle' };
		}
	}

	async function handleRemoveGroup(pk: number, groupPk: string) {
		if (!groupPk) return;
		const userObj = getUser(pk);
		if (!userObj) return;
		groupActionStates = { ...groupActionStates, [pk]: 'loading' };
		actionErrors = { ...actionErrors, [pk]: '' };
		try {
			const res = await fetch(`/api/admin/users/${pk}/remove-group`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ group_pk: groupPk })
			});
			const body = await res.json();
			if (!res.ok || body.error) {
				throw new Error(body.error?.message || 'Remove group failed');
			}
			userObj.groups = userObj.groups.filter(g => g !== groupPk);
		} catch (err) {
			actionErrors = { ...actionErrors, [pk]: err instanceof Error ? err.message : 'Remove group failed' };
		} finally {
			groupActionStates = { ...groupActionStates, [pk]: 'idle' };
		}
	}

	async function handleCreateUser() {
		if (!createForm.username || !createForm.name || !createForm.email || !createForm.password) return;
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
					group_pk: groupPk
				})
			});
			const body = await res.json();
			if (!res.ok || body.error) {
				throw new Error(body.error?.message || 'Create failed');
			}
			users = [...users, body.data];
			showCreateDialog = false;
			createForm = { username: '', name: '', email: '', password: '', isActive: true, showPassword: false };
		} catch (err) {
			createError = err instanceof Error ? err.message : 'Create failed';
		} finally {
			createLoading = false;
		}
	}

	async function handleDeleteUser(pk: number) {
		const userObj = getUser(pk);
		if (!userObj) return;
		deleteLoading = true;
		deleteError = '';
		try {
			const res = await fetch(`/api/admin/users/${userObj.pk}`, {
				method: 'DELETE'
			});
			const body = await res.json();
			if (!res.ok || body.error) {
				throw new Error(body.error?.message || 'Delete failed');
			}
			users = users.filter(u => u.pk !== pk);
			const { [userObj.uuid]: _, ...rest } = initMap;
			initMap = rest;
		} catch (err) {
			deleteError = err instanceof Error ? err.message : 'Delete failed';
		} finally {
			deleteLoading = false;
		}
	}

	function handleSuggestionClick(userPk: number, suggestion: UserGroup) {
		showSuggestions = { ...showSuggestions, [userPk]: false };
		groupSearchInputs = { ...groupSearchInputs, [userPk]: suggestion.name };
	}

	function handleAddButtonClick(userPk: number, search: string) {
		const match = allGroups.find(
			g => g.name.toLowerCase() === search.toLowerCase() || g.name.toLowerCase().includes(search.toLowerCase())
		);
		if (!match) return;
		handleAddGroup(userPk, match.pk);
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
						{#if role !== 'admin-role'}
							<TableHead>Init Status</TableHead>
						{/if}
						<TableHead class="w-24">Activate</TableHead>
						<TableHead class="w-20">Manage</TableHead>
					</TableRow>
				</TableHeader>
				<TableBody>
					{#each users as userObj (userObj.pk)}
						{@const authStatus = authentikStatusBadge(userObj.is_active)}
						{@const initStatus = initStatusBadge(userObj.uuid)}
						{@const isCurrentExpanded = expandedPk === userObj.pk}
						{@const isInitLoading = initStates[userObj.pk] === 'loading'}
						{@const isAuthLoading = authStates[userObj.pk] === 'loading'}
						{@const isPwResetLoading = pwResetStates[userObj.pk] === 'loading'}
						{@const anyActionLoading = isInitLoading || isAuthLoading || isPwResetLoading}
						{@const isGroupLoading = groupActionStates[userObj.pk] === 'loading'}
						{@const isPending = !(userObj.uuid in initMap)}
						{@const userGroups = getUserGroups(userObj.pk)}
						{@const suggestions = filteredSuggestions(userObj.pk)}
						{@const showSug = showSuggestions[userObj.pk] ?? false}
						<TableRow>
							<TableCell class="font-medium">
								{userObj.name || userObj.username}
							</TableCell>
							<TableCell class="text-surface-700">
								{userObj.email || '—'}
							</TableCell>
							<TableCell>
								<Badge variant={authStatus.variant}>{authStatus.label}</Badge>
							</TableCell>
							{#if role !== 'admin-role'}
								<TableCell>
									<Badge variant={initStatus.variant}>{initStatus.label}</Badge>
								</TableCell>
							{/if}
							<TableCell>
								<Button
									variant={userObj.is_active ? 'destructive' : 'default'}
									size="sm"
									class="cursor-pointer"
									onclick={() => userObj.is_active ? handleDeactivateAuthentik(userObj.pk) : handleActivateAuthentik(userObj.pk)}
									disabled={anyActionLoading}
								>
									{userObj.is_active ? 'Deactivate' : 'Activate'}
								</Button>
							</TableCell>
							<TableCell>
								<Button
									variant="outline"
									size="sm"
									class="cursor-pointer"
									onclick={() => toggleExpand(userObj.pk)}
								>
									{isCurrentExpanded ? 'Close' : 'Manage'}
								</Button>
							</TableCell>
						</TableRow>

						{#if isCurrentExpanded}
							<TableRow class="bg-surface-50">
								<TableCell colspan={role === 'admin-role' ? 5 : 6} class="p-0">
									<div class="px-6 py-4 space-y-4 border-t border-surface-200">
										<div class="flex flex-wrap justify-between items-start gap-6">
										{#if isPending && role !== 'admin-role'}
											<div class="flex flex-col gap-1.5 min-w-48">
												<span class="text-sm font-medium text-surface-700">Initialize</span>
												<div class="flex items-center gap-2">
													{#if role === 'students'}
														<select
															class="h-8 w-44 rounded-none border border-input bg-transparent px-2.5 py-1 text-sm text-surface-800 transition-colors focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-1 disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
															bind:value={selectedClassLevels[userObj.pk]}
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
													{/if}
													<Button
														variant="default"
														size="sm"
														class="cursor-pointer"
														onclick={() => handleInitialize(userObj.pk)}
														disabled={anyActionLoading}
													>
														{isInitLoading ? '...' : 'Initialize'}
													</Button>
												</div>
											</div>
										{/if}

										<div class="flex flex-col gap-1.5 min-w-48">
											<span class="text-sm font-medium text-surface-700">Reset Password</span>
											<div class="flex items-center gap-2">
												<div class="relative flex-1">
													<Input
														type={passwordShowMap[userObj.pk] ? 'text' : 'password'}
														placeholder="New password"
														class="h-8 w-44 text-sm cursor-text pr-10"
														bind:value={passwordInputs[userObj.pk]}
													/>
													<button
														type="button"
														class="absolute right-1 top-1/2 -translate-y-1/2 text-xs text-surface-500 hover:text-surface-700 cursor-pointer px-1"
														onclick={() => passwordShowMap = { ...passwordShowMap, [userObj.pk]: !passwordShowMap[userObj.pk] }}
													>
														{passwordShowMap[userObj.pk] ? 'Hide' : 'Show'}
													</button>
												</div>
												<Button
													variant="default"
													size="sm"
													class="cursor-pointer"
													onclick={() => handleResetPassword(userObj.pk)}
													disabled={anyActionLoading || !passwordInputs[userObj.pk]}
												>
													{isPwResetLoading ? '...' : 'Reset'}
												</Button>
											</div>
											<button
												type="button"
												class="text-xs text-primary-600 hover:text-primary-800 cursor-pointer self-start"
												onclick={() => passwordInputs = { ...passwordInputs, [userObj.pk]: generatePassword() }}
											>
												Generate random password
											</button>
										</div>

											<div class="flex flex-col gap-2 min-w-56">
												<span class="text-sm font-medium text-surface-700">Groups</span>

												<div class="flex flex-wrap gap-1.5">
													{#each userGroups as group (group.pk)}
														<span class="inline-flex items-center gap-1 rounded-md bg-primary-100 px-2 py-0.5 text-xs font-medium text-primary-700">
															{group.name}
															<button
																type="button"
																aria-label="Remove {group.name} group"
																class="inline-flex items-center justify-center rounded-full p-0.5 text-primary-500 hover:bg-primary-200 hover:text-primary-800 transition-colors cursor-pointer"
																onclick={() => handleRemoveGroup(userObj.pk, group.pk)}
																disabled={isGroupLoading}
															>
																<svg class="h-3 w-3" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
																	<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
																</svg>
															</button>
														</span>
													{/each}
													{#if userGroups.length === 0}
														<span class="text-xs text-surface-500 italic">No groups</span>
													{/if}
												</div>

												<div class="relative flex items-center gap-2">
													<Input
														type="text"
														placeholder="Search groups…"
														class="h-8 flex-1 text-sm cursor-text"
														bind:value={groupSearchInputs[userObj.pk]}
														onfocus={() => showSuggestions = { ...showSuggestions, [userObj.pk]: true }}
														onblur={() => setTimeout(() => showSuggestions = { ...showSuggestions, [userObj.pk]: false }, 200)}
													/>
													<Button
														variant="default"
														size="sm"
														class="cursor-pointer"
														disabled={isGroupLoading || !groupSearchInputs[userObj.pk]?.trim()}
														onclick={() => handleAddButtonClick(userObj.pk, groupSearchInputs[userObj.pk] || '')}
													>
														{#if isGroupLoading}
															<svg class="h-4 w-4 animate-spin" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
																<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
																<path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
															</svg>
														{:else}
															Add
														{/if}
													</Button>

													{#if showSug && suggestions.length > 0}
														<div class="absolute bottom-full left-0 right-0 mb-1 z-20 rounded-md border border-surface-200 bg-white shadow-lg max-h-40 overflow-y-auto flex flex-col">
															{#each suggestions as sg (sg.pk)}
																<button
																	type="button"
																	class="w-full shrink-0 px-3 py-1.5 text-left text-sm text-surface-800 hover:bg-surface-100 transition-colors cursor-pointer"
																	onmousedown={() => handleSuggestionClick(userObj.pk, sg)}
																>
																	{sg.name}
																</button>
															{/each}
														</div>
													{/if}
												</div>
											</div>
										</div>

										<div class="border-t border-surface-200 pt-3 flex justify-end">
											<AlertDialog>
												<AlertDialogTrigger>
												{#snippet child({ props })}
														<Button
															variant="destructive"
															size="sm"
															class="cursor-pointer"
															{...props}
														>
															Delete User
														</Button>
													{/snippet}
												</AlertDialogTrigger>
												<AlertDialogContent>
													<AlertDialogHeader>
														<AlertDialogTitle>Delete {userObj.name || userObj.username}?</AlertDialogTitle>
														<AlertDialogDescription>
															This permanently removes {userObj.name || userObj.username} from Authentik.
															The user will lose all access. This cannot be undone.
														</AlertDialogDescription>
													</AlertDialogHeader>
													{#if deleteError}
														<p class="text-sm text-error-500">{deleteError}</p>
													{/if}
													<AlertDialogFooter>
														<AlertDialogCancel onclick={() => { deleteError = ''; }}>
															Cancel
														</AlertDialogCancel>
														<AlertDialogAction
															disabled={deleteLoading}
															onclick={() => handleDeleteUser(userObj.pk)}
															class="bg-error-500 hover:bg-error-600 text-white"
														>
															{deleteLoading ? 'Deleting...' : 'Delete'}
														</AlertDialogAction>
													</AlertDialogFooter>
												</AlertDialogContent>
											</AlertDialog>
										</div>

										{#if actionErrors[userObj.pk]}
											<p class="text-sm text-error-500">{actionErrors[userObj.pk]}</p>
										{/if}
									</div>
								</TableCell>
							</TableRow>
						{/if}
					{/each}
				</TableBody>
			</Table>
		</CardContent>
	</Card>

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
{/if}