<script lang="ts">
	import { Sidebar, SidebarContent, SidebarFooter, SidebarGroup, SidebarGroupLabel, SidebarHeader, SidebarInset, SidebarProvider, SidebarTrigger } from '$lib/components/ui/sidebar';
	import { Avatar, AvatarFallback } from '$lib/components/ui/avatar';
	import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from '$lib/components/ui/dropdown-menu';
	import { Breadcrumb, BreadcrumbList, BreadcrumbItem, BreadcrumbPage } from '$lib/components/ui/breadcrumb';
	import { Button } from '$lib/components/ui/button';
	import { Separator } from '$lib/components/ui/separator';
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
				window.location.href = '/login';
			}
		} catch {
			error = 'An error occurred during logout. Please try again.';
			isLoggingOut = false;
		}
	}
</script>

<SidebarProvider open={sidebarOpen} onOpenChange={(v) => sidebarOpen = v}>
	<Sidebar>
		<SidebarHeader>
			<div class="flex items-center gap-2 px-4 py-2">
				<span class="text-lg font-display font-bold text-primary-700">School</span>
			</div>
		</SidebarHeader>

		<SidebarContent>
			<SidebarGroup>
				<SidebarGroupLabel>Navigation</SidebarGroupLabel>
			</SidebarGroup>
		</SidebarContent>

		<SidebarFooter>
			<Separator />
			<div class="p-4">
				<p class="text-sm font-medium text-surface-800">{data.user.name}</p>
				<p class="text-xs text-surface-700">{data.user.email}</p>
			</div>
		</SidebarFooter>
	</Sidebar>

	<SidebarInset>
		<header class="flex h-14 items-center gap-4 border-b border-border px-4">
			<SidebarTrigger />
			<Separator orientation="vertical" class="h-6" />
			<Breadcrumb>
				<BreadcrumbList>
					<BreadcrumbItem>
						<BreadcrumbPage>Dashboard</BreadcrumbPage>
					</BreadcrumbItem>
				</BreadcrumbList>
			</Breadcrumb>

      <div class="flex-1"></div>

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
				<p class="text-xs text-error-500">{error}</p>
			{/if}
		</header>

		<main class="flex-1 p-6">
			{@render children()}
		</main>
	</SidebarInset>
</SidebarProvider>
