import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { fetchAllUsers } from '$lib/server/authentik';
import { proxyToGateway, parseActivations } from '$lib/server/golem';

export const load: PageServerLoad = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) {
		error(403, 'Forbidden');
	}

	try {
		const [authentikUsers, activationsResult] = await Promise.all([
			fetchAllUsers(),
			proxyToGateway('/gateway/admin/activations', user.id)
		]);

		const activationMap = activationsResult.data
			? parseActivations(activationsResult.data)
			: new Map<string, string>();

		const users = authentikUsers.map((u) => ({
			...u,
			activationStatus: activationMap.get(u.uuid) || 'not_found'
		}));

		return { users };
	} catch (err) {
		return {
			users: [],
			error: err instanceof Error ? err.message : 'Failed to fetch users.'
		};
	}
};
