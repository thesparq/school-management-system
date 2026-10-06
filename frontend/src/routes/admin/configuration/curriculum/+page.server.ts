import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { adminProxy } from '$lib/server/golem';
import { fetchAllUsers } from '$lib/server/authentik';

export const load: PageServerLoad = async (event) => {
    const user = event.locals.user;
    if (!user || !user.roles.includes('admin')) {
        error(401, 'Not authenticated or missing admin role');
    }

    try {
        const proxy = adminProxy(user, event.request.signal);
        
        // Fetch staff immediately (cached and fast)
        const authentikUsers = await fetchAllUsers();
        const staff = authentikUsers.filter(u => u.groups?.includes('Teachers'));
        
        // Use an ephemeral agent ID to prevent the 10-second query from blocking the main AdminAgent lock
        const ephemeralProxy = adminProxy({ id: `${user.id}-planner-${Date.now()}` }, event.request.signal);
        
        return {
            staff,
            // Stream the slow planner data so the page transitions instantly
            streamed: {
                plannerDataRes: ephemeralProxy('/curriculum-planner-data', undefined, 'GET').then(res => {
                    if (res.error) throw new Error(res.error.message);
                    return JSON.parse(res.data);
                })
            }
        };
    } catch (e: any) {
        console.error('Error in curriculum SSR:', e);
        throw error(500, e.message || 'Internal Server Error');
    }
};
