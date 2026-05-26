import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { fetchAllUsers } from '$lib/server/authentik';

export const load: PageServerLoad = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) {
		error(403, 'Forbidden');
	}

	try {
		const users = await fetchAllUsers();
		return { users };
	} catch (err) {
		return {
			users: [],
			error: err instanceof Error ? err.message : 'Failed to fetch users from Authentik.'
		};
	}
};
