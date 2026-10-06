<script lang="ts">
    import { matrixStore } from '$lib/stores/matrixStore.svelte';
    import { ChatCircle, X } from 'phosphor-svelte';
    import { fade, slide } from 'svelte/transition';

    let isOpen = $state(false);
    let selectedRoom = $state<string | null>(null);
    let text = $state('');

    async function send() {
        if (!text.trim() || !selectedRoom) return;
        await matrixStore.sendMessage(selectedRoom, text);
        text = '';
    }
</script>

<div class="fixed bottom-6 right-6 z-50 flex flex-col items-end">
    {#if isOpen}
        <div transition:slide={{duration: 200}} class="w-80 h-96 bg-card text-card-foreground shadow-2xl border border-border rounded-xl mb-4 flex flex-col overflow-hidden">
            <div class="bg-primary text-primary-foreground p-3 flex justify-between items-center">
                <h3 class="font-semibold">Messages</h3>
                <button onclick={() => isOpen = false}><X size={18}/></button>
            </div>
            
            <div class="flex-1 overflow-y-auto p-4 flex flex-col gap-3">
                {#if selectedRoom}
                    <button onclick={() => selectedRoom = null} class="text-xs text-blue-600 mb-2">&larr; Back to chats</button>
                    {#each (matrixStore.messages[selectedRoom] || []) as msg}
                        <div class="bg-muted p-2 rounded-lg text-sm self-start max-w-[80%]">
                            {msg.content.body}
                        </div>
                    {/each}
                {:else}
                    {#each matrixStore.rooms as room}
                        <button onclick={() => selectedRoom = room.roomId} class="w-full text-left p-3 hover:bg-muted/50 border-b">
                            <p class="font-medium text-card-foreground">{room.name}</p>
                            <p class="text-xs text-muted-foreground truncate">{room.lastMessage || 'No messages yet'}</p>
                        </button>
                    {/each}
                    {#if matrixStore.rooms.length === 0}
                        <p class="text-sm text-muted-foreground text-center mt-10">No chats available.</p>
                    {/if}
                {/if}
            </div>

            {#if selectedRoom}
                <form class="p-3 border-t bg-muted/50 flex gap-2" onsubmit={(e) => { e.preventDefault(); send(); }}>
                    <input bind:value={text} placeholder="Type a message..." class="flex-1 bg-card text-card-foreground border border-input rounded px-2 py-1 text-sm focus:outline-none focus:border-blue-500" />
                    <button type="submit" class="bg-blue-600 text-white px-3 rounded text-sm font-medium">Send</button>
                </form>
            {/if}
        </div>
    {/if}

    <button onclick={() => isOpen = !isOpen} class="bg-blue-600 text-white p-4 rounded-full shadow-lg hover:bg-blue-700 transition transform hover:scale-105 active:scale-95">
        <ChatCircle size={24} />
    </button>
</div>
