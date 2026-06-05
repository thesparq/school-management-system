<script lang="ts">
	import { toasts } from '$lib/stores/toast';
	import Toast from './toast.svelte';
</script>

{#if $toasts.length > 0}
	<div class="fixed top-16 right-4 z-[60] flex flex-col gap-2 w-80 pointer-events-none">
		{#each $toasts as toast (toast.id)}
			<Toast {toast} />
		{/each}
	</div>
{/if}
