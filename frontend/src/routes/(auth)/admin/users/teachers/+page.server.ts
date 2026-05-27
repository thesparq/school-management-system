import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { fetchAllUsers, fetchAllGroups, getGroupPkByName } from '$lib/server/authentik';

export const load: PageServerLoad = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) error(403, 'Forbidden');

	try {
		const [authentikUsers, initsResponse, allGroups] = await Promise.all([
			fetchAllUsers(),
			event.fetch('/api/admin/initializations'),
			fetchAllGroups()
		]);

		const initsBody = await initsResponse.json();
		const initMap: Record<string, string> = initsBody.data || {};

		const teachersGroupPk = await getGroupPkByName('teachers');
		const filtered = teachersGroupPk
			? authentikUsers.filter(u => (u.groups ?? []).includes(teachersGroupPk))
			: authentikUsers;

		return { users: filtered, initMap, allGroups, role: 'teachers' };
	} catch (err) {
		return {
			users: [],
			initMap: {},
			allGroups: [],
			role: 'teachers',
			error: err instanceof Error ? err.message : 'Failed to fetch users.'
		};
	}
};
