<script lang="ts">
	import type { PageData } from './$types';
	import { Card, CardContent, CardHeader, CardTitle } from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Alert, AlertTitle, AlertDescription, AlertAction } from '$lib/components/ui/alert';
	import { Skeleton } from '$lib/components/ui/skeleton';
	import { navigating } from '$app/stores';
	import { goto } from '$app/navigation';

	let { data }: { data: PageData } = $props();

	let pingResult = $state<string | null>(null);
	let pingError = $state<string | null>(null);
	let isPinging = $state(false);

	async function testConnection() {
		isPinging = true;
		pingResult = null;
		pingError = null;

		try {
			const res = await fetch('/api/ping');
			const body = await res.json();
			if (body.data) {
				pingResult = body.data;
			} else {
				pingError = body.error?.message ?? 'Unknown error';
			}
		} catch {
			pingError = 'Network error — could not reach server.';
		} finally {
			isPinging = false;
		}
	}
</script>

{#if data.initialized === false}
	<div class="mx-auto max-w-lg py-16 text-center space-y-6">
		<div class="rounded-full bg-warning-100 dark:bg-warning-900/20 mx-auto w-fit p-4">
			<svg
				xmlns="http://www.w3.org/2000/svg"
				class="h-8 w-8 text-warning-600 dark:text-warning-400"
				fill="none"
				viewBox="0 0 24 24"
				stroke="currentColor"
			>
				<path
					stroke-linecap="round"
					stroke-linejoin="round"
					stroke-width="2"
					d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4.5c-.77-.833-2.694-.833-3.464 0L3.34 16.5c-.77.833.192 2.5 1.732 2.5z"
				/>
			</svg>
		</div>
		<h1 class="text-2xl font-display font-bold text-surface-800 dark:text-surface-200">
			Account Not Initialized
		</h1>
		<p class="text-surface-700 dark:text-surface-400">
			Your account has not yet been initialized. Please contact your school administrator.
		</p>
	</div>
{:else if data.subjects !== null || data.subjectsError !== null}
	<div class="mx-auto max-w-6xl space-y-6">
		{#if $navigating && (!data.subjects || data.subjects.length === 0)}
			<h1 class="text-2xl font-display font-bold text-primary-700">Your Subjects</h1>
			<div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
				{#each Array(12) as _}
					<Skeleton class="h-28" />
				{/each}
			</div>
		{:else if data.subjectsError}
			<Alert variant="destructive">
				<AlertTitle>Failed to load subjects</AlertTitle>
				<AlertDescription>{data.subjectsError}</AlertDescription>
				<AlertAction>
					<Button variant="outline" onclick={() => goto('/')}>Retry</Button>
				</AlertAction>
			</Alert>
		{:else if data.subjects && data.subjects.length === 0}
			<div class="mx-auto max-w-lg py-16 text-center space-y-6">
				<div class="rounded-full bg-secondary-100 dark:bg-secondary-900/20 mx-auto w-fit p-4">
					<svg
						xmlns="http://www.w3.org/2000/svg"
						class="h-8 w-8 text-secondary-400"
						fill="none"
						viewBox="0 0 24 24"
						stroke="currentColor"
						stroke-width="2"
					>
						<circle cx="12" cy="12" r="10" />
						<path stroke-linecap="round" stroke-linejoin="round" d="M12 16v-4m0-4h.01" />
					</svg>
				</div>
				<h1 class="text-2xl font-display font-bold text-surface-800 dark:text-surface-200">
					No Subjects Assigned
				</h1>
				<p class="text-surface-700 dark:text-surface-400">
					No subjects have been assigned to you yet. Please contact your school administrator.
				</p>
			</div>
		{:else if data.subjects && data.subjects.length > 0}
			<div>
				<h1 class="text-2xl font-display font-bold text-primary-700">Your Subjects</h1>
			</div>
			<div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
				{#each data.subjects as subject (subject.id)}
					<a href="/lms/{subject.id}">
						<Card class="hover:bg-primary-50 dark:hover:bg-primary-950/30 hover:ring-primary-200 dark:hover:ring-primary-700 transition cursor-pointer">
							<CardHeader class="pb-0 min-h-[4.5rem]">
								<CardTitle class="flex flex-wrap items-center gap-x-2 gap-y-1 font-display text-base text-primary-700 dark:text-primary-300">
								<span class="truncate">{subject.name}</span>
								{#if subject.code}
									<span class="rounded bg-primary-100 dark:bg-primary-900/40 px-1.5 py-0.5 text-xs font-mono text-primary-600 dark:text-primary-400 shrink-0">{subject.code}</span>
								{/if}
							</CardTitle>
							</CardHeader>
						</Card>
					</a>
				{/each}
			</div>
		{/if}
	</div>
{:else}
	<div class="mx-auto max-w-4xl space-y-6">
		<div>
			<h1 class="text-2xl font-display font-bold text-primary-700">
				Welcome, {data.user.name}
			</h1>
			<p class="mt-1 text-sm text-surface-700">
				{data.user.roles[0] ?? 'User'} dashboard
			</p>
		</div>

		<div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
			<Card>
				<CardHeader>
					<CardTitle class="text-base">Quick Actions</CardTitle>
				</CardHeader>
				<CardContent>
					<p class="text-sm text-surface-700">Dashboard widgets will appear here.</p>
				</CardContent>
			</Card>

			<Card>
				<CardHeader>
					<CardTitle class="text-base">Connection Status</CardTitle>
				</CardHeader>
				<CardContent class="space-y-3">
					<Button onclick={testConnection} disabled={isPinging}>
						{isPinging ? 'Testing...' : 'Test Connection'}
					</Button>

					{#if pingResult}
						<p class="text-sm text-success-500">Gateway: {pingResult}</p>
					{/if}

					{#if pingError}
						<p class="text-sm text-error-500">{pingError}</p>
					{/if}
				</CardContent>
			</Card>
		</div>
	</div>
{/if}
