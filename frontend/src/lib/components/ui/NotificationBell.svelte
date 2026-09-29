<script lang="ts">
    import { matrixStore } from '$lib/stores/matrixStore.svelte';
    import { Bell } from 'phosphor-svelte';
    import { Popover } from 'bits-ui';
    import { fade } from 'svelte/transition';

    let totalUnread = $derived(matrixStore.rooms.reduce((acc, r) => acc + r.unread, 0));
</script>

<Popover.Root>
    <Popover.Trigger>
        {#snippet child({ props })}
            <button {...props} class="relative p-2 rounded-full hover:bg-slate-100 transition">
                <Bell size={20} class="text-muted-foreground" />
                {#if totalUnread > 0}
                    <span class="absolute top-0 right-0 h-4 w-4 rounded-full bg-red-500 text-[10px] text-white flex items-center justify-center font-bold">
                        {totalUnread > 99 ? '99+' : totalUnread}
                    </span>
                {/if}
            </button>
        {/snippet}
    </Popover.Trigger>
    
    <Popover.Content transition={fade} class="w-80 p-4 bg-popover rounded-lg shadow-xl border border-border z-[100]">
        <h3 class="font-semibold text-popover-foreground mb-3">Notifications</h3>
        {#if matrixStore.rooms.length === 0}
            <p class="text-sm text-muted-foreground">No recent notifications.</p>
        {:else}
            <ul class="space-y-3">
                {#each matrixStore.rooms as room}
                    {#if room.lastMessage}
                        <li class="text-sm text-muted-foreground">
                            <span class="font-medium text-popover-foreground">{room.name}</span>: {room.lastMessage}
                        </li>
                    {/if}
                {/each}
            </ul>
        {/if}
        <div class="mt-4 pt-3 border-t text-center">
            <a href="https://element.johnethel.school" target="_blank" class="text-xs text-blue-600 hover:underline">Open Full Inbox</a>
        </div>
    </Popover.Content>
</Popover.Root>
