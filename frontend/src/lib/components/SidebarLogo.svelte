<script lang="ts">
  import { useSidebar } from '$lib/components/ui/sidebar/context.svelte.js';
  import { page } from '$app/stores';
  import logo from '$lib/assets/logo.jpg';

  const sb = useSidebar();

  $effect(() => {
    $page.url.pathname;
    sb.setOpenMobile(false);
  });
</script>

{#if sb.state === 'collapsed'}
  <div class="flex items-center justify-center px-2 py-4" data-sidebar="header">
    <img src="/favicon.png" alt="School MS" class="h-8 w-8" />
  </div>
{:else}
  <div class="flex items-center justify-center px-4 py-4" data-sidebar="header">
    <img src={logo} alt="School MS" class="h-10" />
  </div>
{/if}
