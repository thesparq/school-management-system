import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';

export const POST: RequestHandler = async ({ request, cookies }) => {
	const authKey = cookies.get('auth_key');

	if (!authKey) {
		return json({ error: 'Unauthorized' }, { status: 401 });
	}

	try {
		const body = await request.json();
		
		const golemUrl = env.GOLEM_API_URL || 'http://localhost:9881/v1/api/admin';
		const res = await fetch(`${golemUrl}/generate-timetable`, {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
				'X-Golem-Auth-Key': authKey
			},
			body: JSON.stringify(body)
		});

		if (!res.ok) {
			const errorText = await res.text();
			return json({ error: 'Golem API error', details: errorText }, { status: res.status });
		}

		const data = await res.json();
		return json(data);
	} catch (err: any) {
		return json({ error: 'Internal server error', details: err.message }, { status: 500 });
	}
};
