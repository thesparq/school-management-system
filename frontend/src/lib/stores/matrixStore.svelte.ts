import { PUBLIC_MATRIX_URL } from '$env/static/public';


class MatrixStore {
    token = $state('');
    userId = $state('');
    rooms = $state<{ roomId: string; name: string; unread: number; lastMessage: string }[]>([]);
    messages = $state<Record<string, any[]>>({});
    
    // Status
    connected = $state(false);

    async init(userUuid: string, golemUserId: string) {
        if (this.connected) return;
        
        try {
            // Fetch token from SuperAdminAgent proxy
            const res = await (await window.fetch('/api/matrix/token')).json();
            if (res) {
                this.token = res;
                this.userId = `@${userUuid}:matrix.johnethel.school`;
                
                // Start polling /sync
                this.startSync();
                this.connected = true;
            }
        } catch (err) {
            console.error("Failed to init matrix", err);
        }
    }

    private async startSync(nextBatch: string = '') {
        if (!this.token) return;
        
        try {
            const url = new URL(`${PUBLIC_MATRIX_URL}/_matrix/client/v3/sync`);
            url.searchParams.set('timeout', '30000');
            if (nextBatch) {
                url.searchParams.set('since', nextBatch);
            }

            const res = await fetch(url.toString(), {
                headers: {
                    'Authorization': `Bearer ${this.token}`
                }
            });
            
            const data = await res.json();
            this.processSyncData(data);
            
            // Long poll loop
            setTimeout(() => this.startSync(data.next_batch), 1000);
            
        } catch (err) {
            console.error("Matrix sync error", err);
            // Retry
            setTimeout(() => this.startSync(nextBatch), 5000);
        }
    }

    private processSyncData(data: any) {
        if (!data.rooms || !data.rooms.join) return;
        
        for (const [roomId, roomData] of Object.entries<any>(data.rooms.join)) {
            // Check for new messages
            const events = roomData.timeline?.events || [];
            if (!this.messages[roomId]) {
                this.messages[roomId] = [];
            }
            
            for (const ev of events) {
                if (ev.type === 'm.room.message') {
                    this.messages[roomId].push(ev);
                }
            }
            
            // Update unread counts etc. (Simplified)
            let existingRoom = this.rooms.find(r => r.roomId === roomId);
            if (!existingRoom) {
                existingRoom = { roomId, name: 'Room', unread: 0, lastMessage: '' };
                this.rooms.push(existingRoom);
            }
            
            if (events.length > 0) {
                const lastEv = events[events.length - 1];
                if (lastEv.content && lastEv.content.body) {
                    existingRoom.lastMessage = lastEv.content.body;
                }
            }
        }
    }

    async sendMessage(roomId: string, text: string) {
        if (!this.token) return;
        const txnId = 'txn_' + Date.now();
        const url = `${PUBLIC_MATRIX_URL}/_matrix/client/v3/rooms/${roomId}/send/m.room.message/${txnId}`;
        
        await fetch(url, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${this.token}`
            },
            body: JSON.stringify({
                msgtype: 'm.text',
                body: text
            })
        });
    }
}

export const matrixStore = new MatrixStore();
