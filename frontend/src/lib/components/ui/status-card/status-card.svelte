<script lang="ts">
	type Variant = 'info' | 'warning' | 'error';

	let {
		variant,
		title,
		description,
		onRetry = undefined as (() => void) | undefined
	}: {
		variant: Variant;
		title: string;
		description: string;
		onRetry?: () => void;
	} = $props();

	const styles: Record<Variant, { icon: string; wrapper: string }> = {
		info: {
			icon: 'text-surface-500',
			wrapper: 'bg-secondary-100 dark:bg-secondary-900/20'
		},
		warning: {
			icon: 'text-amber-500',
			wrapper: 'bg-amber-100 dark:bg-amber-900/20'
		},
		error: {
			icon: 'text-destructive',
			wrapper: 'bg-error-100 dark:bg-error-900/20'
		}
	};

	const svgPath: Record<Variant, string> = {
		info: 'M12 16v-4m0-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z',
		warning: 'M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z',
		error: 'M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z'
	};
</script>

<div class="mx-auto max-w-lg py-16 text-center space-y-6">
	<div class="rounded-full {styles[variant].wrapper} mx-auto w-fit p-4">
		<svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8 {styles[variant].icon}" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
			<path stroke-linecap="round" stroke-linejoin="round" d={svgPath[variant]} />
		</svg>
	</div>
	<div>
		<p class="text-lg font-medium text-card-foreground">{title}</p>
		<p class="mt-1 text-sm text-muted-foreground max-w-sm mx-auto">{description}</p>
	</div>
	{#if onRetry}
		<button
			onclick={onRetry}
			class="inline-flex items-center justify-center rounded-md border border-input bg-background px-4 py-2 text-sm font-medium shadow-sm hover:bg-muted transition-colors cursor-pointer"
		>
			Retry
		</button>
	{/if}
</div>
