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
	import { onMount } from 'svelte';
	import type { LayoutData } from './$types';
	import type { Snippet } from 'svelte';

	let { children, data }: { children: Snippet; data: LayoutData } = $props();

	let sidebarOpen = $state(true);
	let isLoggingOut = $state(false);
	let error = $state('');

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
		const origFetch = window.fetch.bind(window);
		window.fetch = async (input, init) => {
			const res = await origFetch(input, init);
			if (res.status === 401) {
				// Only intercept same-origin requests (not third-party APIs)
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
						// Response body not JSON — not our structured 401, pass through
					}
				}
			}
			return res;
		};
		return () => {
			window.fetch = origFetch;
		};
	});
</script>

<svelte:head>
	<link rel="icon" href="/favicon.png" />
	<title>{$page.data.title ?? 'School Management System'}</title>
</svelte:head>

{#if $navigating}
	<div class="fixed top-0 left-0 right-0 z-50 h-0.5 bg-secondary-400 dark:bg-secondary-500 animate-pulse"></div>
{/if}

<SidebarProvider open={sidebarOpen} onOpenChange={(v) => sidebarOpen = v}>
		<Sidebar>
			<SidebarLogo />

		<SidebarContent>
			<SidebarGroup>
				<SidebarGroupLabel>Navigation</SidebarGroupLabel>
				<SidebarMenu>
					<SidebarMenuItem>
						<SidebarMenuButton isActive={$page.url.pathname === '/'}>
							{#snippet child({ props })}
								<a href="/" {...props}>LMS</a>
							{/snippet}
						</SidebarMenuButton>
					</SidebarMenuItem>
					{#if data.user.roles.includes('teacher')}
						<SidebarMenuItem>
							<SidebarMenuButton isActive={$page.url.pathname.startsWith('/my-classes')}>
								{#snippet child({ props })}
									<a href="/my-classes" {...props}>My Classes</a>
								{/snippet}
							</SidebarMenuButton>
						</SidebarMenuItem>
					{/if}
				</SidebarMenu>
			</SidebarGroup>

			{#if data.user.roles.includes('admin')}
				<SidebarGroup>
					<SidebarGroupLabel>Configuration</SidebarGroupLabel>
					<SidebarMenu>
						<SidebarMenuItem>
							<SidebarMenuButton isActive={$page.url.pathname.startsWith('/admin/configuration/session-terms')}>
								{#snippet child({ props })}
									<a href="/admin/configuration/session-terms" {...props}>Session Terms</a>
								{/snippet}
							</SidebarMenuButton>
						</SidebarMenuItem>
						<SidebarMenuItem>
							<SidebarMenuButton isActive={$page.url.pathname.startsWith('/admin/configuration/terms')}>
								{#snippet child({ props })}
									<a href="/admin/configuration/terms" {...props}>Terms</a>
								{/snippet}
							</SidebarMenuButton>
						</SidebarMenuItem>
					</SidebarMenu>
				</SidebarGroup>
			{/if}

			{#if data.user.roles.includes('admin')}
				<SidebarGroup>
					<SidebarGroupLabel>Users</SidebarGroupLabel>
					<SidebarMenu>
						<SidebarMenuItem>
							<SidebarMenuButton isActive={$page.url.pathname.startsWith('/admin/users/students')}>
								{#snippet child({ props })}
									<a href="/admin/users/students" {...props}>Students</a>
								{/snippet}
							</SidebarMenuButton>
						</SidebarMenuItem>
						<SidebarMenuItem>
							<SidebarMenuButton isActive={$page.url.pathname.startsWith('/admin/users/teachers')}>
								{#snippet child({ props })}
									<a href="/admin/users/teachers" {...props}>Teachers</a>
								{/snippet}
							</SidebarMenuButton>
						</SidebarMenuItem>
						<SidebarMenuItem>
							<SidebarMenuButton isActive={$page.url.pathname.startsWith('/admin/users/parents')}>
								{#snippet child({ props })}
									<a href="/admin/users/parents" {...props}>Parents</a>
								{/snippet}
							</SidebarMenuButton>
						</SidebarMenuItem>
						<SidebarMenuItem>
							<SidebarMenuButton isActive={$page.url.pathname.startsWith('/admin/users/admin-role')}>
								{#snippet child({ props })}
									<a href="/admin/users/admin-role" {...props}>Admin</a>
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
			<div
				class="transition-all duration-300 ease-in-out"
				class:opacity-0={sidebarOpen}
				class:opacity-100={!sidebarOpen}
				class:scale-75={sidebarOpen}
				class:scale-100={!sidebarOpen}
				class:pointer-events-none={sidebarOpen}
			>
				<img src={logo} alt="School MS" class="h-8" />
			</div>
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
<ToastContainer />
