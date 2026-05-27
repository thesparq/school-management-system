import { proxyToGateway, parseActivations } from '$lib/server/golem';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const GET: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) error(401, 'Not authenticated');
	if (!user.roles.includes('admin')) error(403, 'Forbidden');

	const result = await proxyToGateway('/gateway/admin/activations', user.id);

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: 502,
			headers: { 'content-type': 'application/json' }
		});
	}

	const activationMap = parseActivations(result.data);
	const obj: Record<string, string> = {};
	for (const [key, val] of activationMap) {
		obj[key] = val;
	}

	return new Response(
		JSON.stringify({ data: obj }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
