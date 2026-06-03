import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { fetchAllUsers, fetchAllGroups } from '$lib/server/authentik';

export const load: PageServerLoad = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) error(403, 'Forbidden');

	try {
		const [authentikUsers, allGroups] = await Promise.all([
			fetchAllUsers(),
			fetchAllGroups()
		]);

		const adminGroup = allGroups.find(g => g.name === 'admin');
		const adminGroupPk = adminGroup?.pk ?? null;
		const filtered = adminGroupPk
			? authentikUsers.filter(u => (u.groups ?? []).includes(adminGroupPk))
			: authentikUsers;

		return { users: filtered, allGroups, role: 'admin-role', groupPk: adminGroupPk ?? '' };
	} catch (err) {
		return {
			users: [],
			allGroups: [],
			role: 'admin-role',
			groupPk: '',
			error: err instanceof Error ? err.message : 'Failed to fetch users.'
		};
	}
};
