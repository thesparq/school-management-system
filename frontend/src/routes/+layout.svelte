<script lang="ts">
	import '../app.css';
	import logo from '$lib/assets/logo.jpg';
	import { Sidebar, SidebarContent, SidebarFooter, SidebarGroup, SidebarGroupLabel, SidebarInset, SidebarMenu, SidebarMenuButton, SidebarMenuItem, SidebarProvider, SidebarTrigger } from '$lib/components/ui/sidebar';
	import { Avatar, AvatarFallback } from '$lib/components/ui/avatar';
	import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from '$lib/components/ui/dropdown-menu';
	import { Breadcrumb, BreadcrumbList, BreadcrumbItem, BreadcrumbPage, BreadcrumbLink, BreadcrumbSeparator } from '$lib/components/ui/breadcrumb';
	import { Button } from '$lib/components/ui/button';
	import { Separator } from '$lib/components/ui/separator';
	import ToastContainer from '$lib/components/ui/toast/toast-container.svelte';
	import ThemeToggle from '$lib/components/ThemeToggle.svelte';
  import { page, navigating } from '$app/stores';
  import SidebarLogo from '$lib/components/SidebarLogo.svelte';
  import { Badge } from '$lib/components/ui/badge';
  import { addToast } from '$lib/stores/toast';
  import { onMount } from 'svelte';
  import { fade } from 'svelte/transition';
  import type { LayoutData } from './$types';
  import type { Snippet } from 'svelte';
  import NotificationBell from '$lib/components/ui/NotificationBell.svelte';
  import MiniChatWidget from '$lib/components/ui/MiniChatWidget.svelte';
  import { matrixStore } from '$lib/stores/matrixStore.svelte';


  let { children, data }: { children: Snippet; data: LayoutData } = $props();

  let sidebarOpen = $state(true);
  let isLoggingOut = $state(false);
  let error = $state('');
  let activeSessionTerm = $state<{ id: string; session_name: string; term_name: string } | null>(null);
  let activeStLoading = $state(false);

	$effect(() => {
		const stored = localStorage.getItem('sidebar_state');
		if (stored !== null) {
			sidebarOpen = stored === 'true';
		}
	});

	$effect(() => {
		localStorage.setItem('sidebar_state', String(sidebarOpen));
	});

	async function handleLogout() {
		if (isLoggingOut) return;
		isLoggingOut = true;
		error = '';

		try {
			const res = await fetch('/api/auth/logout', {
				method: 'POST',
				headers: { 'X-Requested-With': 'XMLHttpRequest' }
			});
			if (!res.ok) {
				error = 'Logout failed. Please try again.';
				isLoggingOut = false;
				return;
			}
			const contentType = res.headers.get('content-type');
			const body = contentType?.includes('application/json') ? await res.json() : {};
			if (body.url) {
				window.location.href = body.url;
			} else {
				window.location.href = '/';
			}
		} catch {
			error = 'An error occurred during logout. Please try again.';
			isLoggingOut = false;
		}
	}

	onMount(() => {
		if (data?.user?.id) {
			matrixStore.init(data.user.id, data.user.id);
		}
		const origFetch = window.fetch.bind(window);
		window.fetch = async (input, init) => {
			const res = await origFetch(input, init);
			if (res.status === 401) {
				const reqUrl = typeof input === 'string' ? input : input instanceof URL ? input.href : input instanceof Request ? input.url : '';
				const isSameOrigin = !reqUrl || new URL(reqUrl, window.location.origin).origin === window.location.origin;
				if (isSameOrigin) {
					try {
						const body = await res.clone().json();
						if (body?.error?.redirectUrl) {
							document.cookie = 'oauth_redirect=' + encodeURIComponent(window.location.pathname) + '; path=/; max-age=300; SameSite=Lax' + (location.protocol === 'https:' ? '; Secure' : '');
							window.location.href = body.error.redirectUrl;
							return new Promise<Response>(() => {});
						}
					} catch {
					}
				}
			}
			return res;
		};
		return () => {
			window.fetch = origFetch;
		};
	});

	$effect(() => {
		const _ = $page.url.pathname;
		activeStLoading = true;
		fetch('/api/admin/active-session-term').then(async (res) => {
			if (res.ok) {
				const json = await res.json();
				const newTerm = json.data ?? null;
				if (activeSessionTerm && newTerm && activeSessionTerm.id !== newTerm.id) {
					addToast('info', 'Active session term updated', `${newTerm.session_name} — ${newTerm.term_name}`);
				}
				activeSessionTerm = newTerm;
			}
			activeStLoading = false;
		}).catch(() => {
			activeStLoading = false;
		});
	});
</script>

<svelte:head>
	<link rel="icon" href="/favicon.png" />
	<title>{$page.data.title ?? 'School Management System'}</title>
</svelte:head>

{#if $navigating}
	<div class="fixed top-0 left-0 right-0 z-50 h-0.5 bg-secondary-600 dark:bg-secondary-500 animate-pulse shadow-[0_1px_4px_rgba(0,0,0,0.15)]"></div>
{/if}

<SidebarProvider open={sidebarOpen} onOpenChange={(v) => sidebarOpen = v}>
		<Sidebar>
			<SidebarLogo />

		<SidebarContent>
			<!-- 1. Dashboard & Learning (All Users) -->
			<SidebarGroup>
				<SidebarGroupLabel>Navigation</SidebarGroupLabel>
				<SidebarMenu>
					{#if data.user.roles.includes('student')}
						<SidebarMenuItem>
							<SidebarMenuButton isActive={$page.url.pathname.startsWith('/student')}>
								{#snippet child({ props })}
									<a href="/student" {...props}>Student Hub</a>
								{/snippet}
							</SidebarMenuButton>
						</SidebarMenuItem>
					{/if}
					{#if data.user.roles.includes('parent')}
						<SidebarMenuItem>
							<SidebarMenuButton isActive={$page.url.pathname.startsWith('/parent')}>
								{#snippet child({ props })}
									<a href="/parent" {...props}>Parent Hub</a>
								{/snippet}
							</SidebarMenuButton>
						</SidebarMenuItem>
					{/if}
					{#if data.user.roles.includes('teacher')}
						<SidebarMenuItem>
							<SidebarMenuButton isActive={$page.url.pathname.startsWith('/teacher') || $page.url.pathname.startsWith('/my-classes')}>
								{#snippet child({ props })}
									<a href="/teacher" {...props}>Teacher Hub</a>
								{/snippet}
							</SidebarMenuButton>
						</SidebarMenuItem>
					{/if}
				</SidebarMenu>
			</SidebarGroup>

			{#if data.user.roles.includes('admin')}
				<!-- 2. System Configuration & Setup (Admin Only) -->
				<SidebarGroup>
					<SidebarGroupLabel>System & Configuration</SidebarGroupLabel>
					<SidebarMenu>
						<SidebarMenuItem>
							<SidebarMenuButton isActive={$page.url.pathname.startsWith('/admin/timetable')}>
								{#snippet child({ props })}
									<a href="/admin/timetable" {...props}>Timetable Engine</a>
								{/snippet}
							</SidebarMenuButton>
						</SidebarMenuItem>
						<SidebarMenuItem>
							<SidebarMenuButton isActive={$page.url.pathname.startsWith('/admin/configuration')}>
								{#snippet child({ props })}
									<a href="/admin/configuration" {...props}>Configuration Hub</a>
								{/snippet}
							</SidebarMenuButton>
						</SidebarMenuItem>
					</SidebarMenu>
				</SidebarGroup>

				<!-- 3. User Management (Admin Only) -->
				<SidebarGroup>
					<SidebarGroupLabel>User Management</SidebarGroupLabel>
					<SidebarMenu>
						<SidebarMenuItem>
							<SidebarMenuButton isActive={$page.url.pathname.startsWith('/admin/users')}>
								{#snippet child({ props })}
									<a href="/admin/users" {...props}>Users Hub</a>
								{/snippet}
							</SidebarMenuButton>
						</SidebarMenuItem>
					</SidebarMenu>
				</SidebarGroup>
			{/if}
		</SidebarContent>

		<SidebarFooter>
			<Separator />
			<div class="p-4">
				<p class="text-sm font-medium text-sidebar-foreground">{data.user.name}</p>
				<p class="text-xs text-muted-foreground">{data.user.email}</p>
			</div>
		</SidebarFooter>
	</Sidebar>

	<SidebarInset>
		<header class="flex h-14 items-center gap-4 border-b border-border px-4">
			<SidebarTrigger />
			<Separator orientation="vertical" class="h-6" />
			{#if !sidebarOpen}
				<div transition:fade={{ duration: 200 }} class="flex items-center gap-4">
					<img src={logo} alt="School MS" class="h-8" />
					<Separator orientation="vertical" class="h-6" />
				</div>
			{/if}
			<Breadcrumb>
				<BreadcrumbList>
					{#each ($page.data.breadcrumbs ?? [{ label: 'Dashboard' }]) as crumb, i (i)}
						<BreadcrumbItem>
							{#if (crumb.href ?? false) && i < ($page.data.breadcrumbs?.length ?? 1) - 1}
								<BreadcrumbLink href={crumb.href}>{crumb.label}</BreadcrumbLink>
							{:else}
								<BreadcrumbPage>{crumb.label}</BreadcrumbPage>
							{/if}
						</BreadcrumbItem>
						{#if i < ($page.data.breadcrumbs?.length ?? 1) - 1}
							<BreadcrumbSeparator />
						{/if}
					{/each}
				</BreadcrumbList>
			</Breadcrumb>

      <div class="flex-1"></div>

			{#if activeStLoading}
				<div class="h-5 w-5 animate-spin rounded-full border-2 border-secondary-300 border-t-secondary-600 dark:border-secondary-700 dark:border-t-secondary-400"></div>
			{/if}
			{#if activeSessionTerm}
				<Badge class="text-sm bg-secondary-100 text-secondary-700 border-secondary-300 dark:bg-secondary-900 dark:text-secondary-300 dark:border-secondary-700">
					{activeSessionTerm.session_name} &mdash; {activeSessionTerm.term_name}
				</Badge>
			{/if}

			<NotificationBell />

			<ThemeToggle />

			<DropdownMenu>
				<DropdownMenuTrigger>
					{#snippet child({ props })}
						<Button variant="ghost" class="h-8 w-8 rounded-full p-0" {...props}>
							<Avatar class="h-8 w-8">
								<AvatarFallback class="bg-primary-100 text-primary-700 text-sm font-medium">
									{data.user.name.charAt(0).toUpperCase()}
								</AvatarFallback>
							</Avatar>
						</Button>
					{/snippet}
				</DropdownMenuTrigger>
				<DropdownMenuContent align="end" class="min-w-48">
					<DropdownMenuLabel class="font-normal">
						<div class="flex flex-col gap-1">
							<p class="text-sm font-medium">{data.user.name}</p>
							<p class="text-xs text-muted-foreground">{data.user.email}</p>
						</div>
					</DropdownMenuLabel>
					<DropdownMenuSeparator />
					<DropdownMenuItem onclick={handleLogout} disabled={isLoggingOut}>
						{isLoggingOut ? 'Signing out...' : 'Sign out'}
					</DropdownMenuItem>
				</DropdownMenuContent>
			</DropdownMenu>

			{#if error}
				<p class="text-xs text-destructive">{error}</p>
			{/if}
		</header>

		<main class="flex-1 p-6">
			{@render children()}
		</main>
	</SidebarInset>
</SidebarProvider>
<MiniChatWidget />
<ToastContainer />
