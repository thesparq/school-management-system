import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { adminProxy, mapErrorCodeToHttpStatus } from '$lib/server/golem';

export const GET: RequestHandler = async ({ locals }) => {
    if (!locals.user) {
        return json({ error: 'Unauthorized' }, { status: 401 });
    }

    const { id: userUuid } = locals.user;
    
    // We'll just hardcode proxy to 'SuperAdminAgent' for token retrieval
    // since matrix admin endpoints are only on admin_agent
    const proxy = adminProxy({ id: 'SuperAdminAgent' });
    const result = await proxy(`/matrix/token?user_uuid=${encodeURIComponent(userUuid)}`);

    if (result.error) {
        return json({ error: result.error.message, detail: result.error.detail, code: result.error.code }, { status: mapErrorCodeToHttpStatus(result.error.code) });
    }

    try {
        return json(JSON.parse(result.data), { status: 200 });
    } catch {
        return json({ error: 'Failed to parse response' }, { status: 502 });
    }
};
