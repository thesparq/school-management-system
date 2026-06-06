<script lang="ts">
	import type { PageData } from './$types';
	import { Card, CardContent, CardHeader, CardTitle } from '$lib/components/ui/card';
	import AppButton from '$lib/components/ui/app-button.svelte';
	import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
	import PageHeader from '$lib/components/PageHeader.svelte';
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

{#if data.teacherClasses !== null || data.teacherClassesError !== null}
	<div class="space-y-6">
		{#if $navigating && (!data.teacherClasses || data.teacherClasses.length === 0)}
			<PageHeader title="My Classes" />
			<div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
				{#each Array(6) as _}
					<Skeleton class="h-32" />
				{/each}
			</div>
		{:else if data.teacherClassesError}
			<StatusCard variant="error" title="Failed to load classes" description={data.teacherClassesError} onRetry={() => goto('/')} />
		{:else if (!data.teacherClasses || data.teacherClasses.length === 0)}
			<StatusCard variant="info" title="No Classes Assigned" description="No classes have been assigned to you yet. Please contact your school administrator." />
		{:else}
			<PageHeader title="My Classes" />
			<div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
				{#each (data.teacherClasses || []) as group (group.class_level_id)}
					<a href="/my-classes/{group.class_level_id}">
						<Card class="hover:bg-primary-50 dark:hover:bg-primary-950/30 hover:ring-primary-200 dark:hover:ring-primary-700 transition cursor-pointer">
							<CardHeader>
								<CardTitle class="font-display text-base text-primary-700 dark:text-primary-300">
									{group.class_level_name}
								</CardTitle>
							</CardHeader>
							<CardContent>
								<p class="text-sm text-muted-foreground dark:text-muted-foreground">
									{group.subjects.length} {group.subjects.length === 1 ? 'subject' : 'subjects'}
								</p>
							</CardContent>
						</Card>
					</a>
				{/each}
			</div>
		{/if}
	</div>
{:else if data.subjects !== null || data.subjectsError !== null}
	<div class="space-y-6">
		{#if $navigating && (!data.subjects || data.subjects.length === 0)}
			<PageHeader title="Your Subjects" />
			<div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
				{#each Array(12) as _}
					<Skeleton class="h-28" />
				{/each}
			</div>
		{:else if data.subjectsErrorCode === 'NOT_INITIALIZED'}
			<StatusCard variant="info" title="Account Not Initialized" description={data.subjectsError ?? ''} />
		{:else if data.subjectsError}
			<StatusCard variant="error" title="Failed to load subjects" description={data.subjectsError} onRetry={() => goto('/')} />
		{:else if data.subjects && data.subjects.length === 0}
			<StatusCard variant="info" title="No Subjects Assigned" description="No subjects have been assigned to you yet. Please contact your school administrator." />
		{:else if data.subjects && data.subjects.length > 0}
			<div>
				<PageHeader title="Your Subjects" />
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
	<div class="space-y-6">
		<div>
			<PageHeader title="Dashboard" />
			<p class="mt-1 text-sm text-muted-foreground">Welcome</p>
		</div>

		<div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
			<Card>
				<CardHeader>
					<CardTitle class="text-base">Quick Actions</CardTitle>
				</CardHeader>
				<CardContent>
					<p class="text-sm text-muted-foreground">Dashboard widgets will appear here.</p>
				</CardContent>
			</Card>

			<Card>
				<CardHeader>
					<CardTitle class="text-base">Connection Status</CardTitle>
				</CardHeader>
				<CardContent class="space-y-3">
					<AppButton onclick={testConnection} loading={isPinging}>
						{isPinging ? 'Testing...' : 'Test Connection'}
					</AppButton>

					{#if pingResult}
						<p class="text-sm text-success-500">Gateway: {pingResult}</p>
					{/if}

					{#if pingError}
						<p class="text-sm text-destructive">{pingError}</p>
					{/if}
				</CardContent>
			</Card>
		</div>
	</div>
{/if}
