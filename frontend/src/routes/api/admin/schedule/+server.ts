import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { adminProxy, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import { fetchAllUsers } from '$lib/server/authentik';

export const GET: RequestHandler = async (event) => {
    const user = event.locals.user;
	if (!user) {
		return new Response(
			JSON.stringify({ error: { code: 'UNAUTHORIZED', message: 'Not authenticated' } }),
			{ status: 401, headers: { 'content-type': 'application/json' } }
		);
	}
	if (!user.roles.includes('admin')) {
		return new Response(
			JSON.stringify({ error: { code: 'FORBIDDEN', message: 'Forbidden' } }),
			{ status: 403, headers: { 'content-type': 'application/json' } }
		);
	}

    try {
        const proxy = adminProxy(user);
        const [plannerDataRes, authentikUsers] = await Promise.all([
            proxy('/curriculum-planner-data', undefined, 'GET'),
            fetchAllUsers()
        ]);
        
        if (plannerDataRes.error) {
            return new Response(JSON.stringify(plannerDataRes), { 
                status: mapErrorCodeToHttpStatus(plannerDataRes.error.code), 
                headers: { 'content-type': 'application/json' } 
            });
        }

        const plannerData = JSON.parse(plannerDataRes.data);
        const staff = authentikUsers.filter(u => u.groups?.includes('Teachers'));
        
        return json({
            ...plannerData,
            staff
        });
    } catch (e: any) {
        console.error('Schedule config error:', e);
        return new Response(e.message || 'Internal error', { status: 500 });
    }
};
