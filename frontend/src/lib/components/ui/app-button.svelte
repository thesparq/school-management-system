<script lang="ts">
  import Button from '$lib/components/ui/button/button.svelte';
  import type { Snippet } from 'svelte';

  type Variant = 'default' | 'outline' | 'ghost' | 'destructive' | 'secondary' | 'link';
  type Size = 'default' | 'sm' | 'xs' | 'lg' | 'icon' | 'icon-xs' | 'icon-sm' | 'icon-lg';

  let {
    loading = false,
    disabled = false,
    children,
    variant = 'default' as Variant,
    size = 'default' as Size,
    onclick,
    class: className = '',
    ...restProps
  }: {
    loading?: boolean;
    disabled?: boolean;
    children: Snippet;
    variant?: Variant;
    size?: Size;
    onclick?: (e: MouseEvent) => void;
    class?: string;
    [key: string]: unknown;
  } = $props();
</script>

<Button {variant} {size} disabled={disabled || loading} {onclick} class={className} {...restProps}>
  {#if loading}
    <svg class="animate-spin h-4 w-4 shrink-0" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
    </svg>
  {/if}
  {@render children()}
</Button>
