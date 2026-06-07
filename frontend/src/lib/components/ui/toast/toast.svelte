<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import type { Toast } from '$lib/stores/toast';
	import { dismissToast } from '$lib/stores/toast';

	let { toast }: { toast: Toast } = $props();

	let progress = $state(100);
	let exiting = $state(false);
	let timer: ReturnType<typeof setTimeout>;
	let frame: ReturnType<typeof requestAnimationFrame>;
	let remaining = toast.durationMs;
	let startedAt = 0;

	const variants: Record<Toast['variant'], { bg: string; bar: string; iconColor: string; iconPath: string }> = {
		success: {
			bg: 'bg-success-50 border-success-200 dark:bg-success-900 dark:border-success-700',
			bar: 'bg-success-500',
			iconColor: 'text-success-500',
			iconPath: 'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z'
		},
		info: {
			bg: 'bg-primary-50 border-primary-200 dark:bg-primary-900 dark:border-primary-700',
			bar: 'bg-primary-500',
			iconColor: 'text-primary-500',
			iconPath: 'M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z'
		},
		warning: {
			bg: 'bg-amber-50 border-amber-200 dark:bg-secondary-900 dark:border-secondary-700',
			bar: 'bg-amber-500',
			iconColor: 'text-amber-500',
			iconPath: 'M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z'
		},
		error: {
			bg: 'bg-error-50 border-error-200 dark:bg-error-900 dark:border-error-700',
			bar: 'bg-error-500',
			iconColor: 'text-destructive',
			iconPath: 'M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z'
		}
	};

	const v = variants[toast.variant];

	function tick() {
		const elapsed = Date.now() - startedAt;
		progress = Math.max(100 - (elapsed / toast.durationMs) * 100, 0);
		if (progress > 0) {
			frame = requestAnimationFrame(tick);
		}
	}

	function start() {
		if (exiting) return;
		startedAt = Date.now() - (toast.durationMs - remaining);
		tick();
		timer = setTimeout(() => dismiss(), remaining);
	}

	function pause() {
		cancelAnimationFrame(frame);
		clearTimeout(timer);
		remaining = Math.max(remaining - (Date.now() - startedAt), 0);
	}

	function dismiss() {
		exiting = true;
		setTimeout(() => dismissToast(toast.id), 200);
	}

	onMount(() => start());
	onDestroy(() => {
		cancelAnimationFrame(frame);
		clearTimeout(timer);
	});
</script>

<div
	class="pointer-events-auto flex items-start gap-3 rounded-lg border p-4 shadow-lg overflow-hidden relative {v.bg}"
	class:animate-toast-in={!exiting}
	class:animate-toast-out={exiting}
	onmouseenter={pause}
	onmouseleave={start}
>
	<div class="absolute top-0 left-0 h-1 {v.bar} transition-none" style="width: {progress}%"></div>
	<svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 shrink-0 {v.iconColor}" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
		<path stroke-linecap="round" stroke-linejoin="round" d={v.iconPath} />
	</svg>
	<div class="flex-1 min-w-0">
		<p class="text-sm font-medium text-foreground">{toast.title}</p>
		{#if toast.description}
			<p class="text-xs text-muted-foreground mt-0.5">{toast.description}</p>
		{/if}
	</div>
	<button
		type="button"
		class="shrink-0 text-muted-foreground hover:text-muted-foreground cursor-pointer"
		onclick={() => { cancelAnimationFrame(frame); clearTimeout(timer); dismiss(); }}
	>
		<svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
			<path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
		</svg>
	</button>
</div>

<style>
	@keyframes toast-in {
		from { opacity: 0; transform: translateX(16px); }
		to   { opacity: 1; transform: translateX(0); }
	}
	@keyframes toast-out {
		from { opacity: 1; transform: translateX(0); }
		to   { opacity: 0; transform: translateX(16px); }
	}
	.animate-toast-in {
		animation: toast-in 0.2s ease-out forwards;
	}
	.animate-toast-out {
		animation: toast-out 0.2s ease-in forwards;
	}
</style>
