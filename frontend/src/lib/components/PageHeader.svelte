<script lang="ts">
	import AppButton from './ui/app-button.svelte';

	let {
		title,
		createLabel = undefined as string | undefined,
		onCreate = undefined as (() => void) | undefined,
		backHref = undefined as string | undefined
	} = $props();
</script>

<div class="flex items-center justify-between">
	<div class="flex items-center gap-3">
		{#if backHref}
			<a href={backHref} class="rounded-md p-1 text-muted-foreground hover:text-foreground hover:bg-accent dark:hover:text-foreground dark:hover:bg-accent transition" aria-label="Back">
				<svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" /></svg>
			</a>
		{/if}
		<h1 class="text-2xl font-display font-bold text-primary-700 dark:text-primary-300">{title}</h1>
	</div>
	{#if createLabel && onCreate}
		<AppButton onclick={onCreate}>{createLabel}</AppButton>
	{/if}
</div>
