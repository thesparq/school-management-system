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

		const teachersGroup = allGroups.find(g => g.name === 'teacher');
		const teachersGroupPk = teachersGroup?.pk ?? null;
		const filtered = teachersGroupPk
			? authentikUsers.filter(u => (u.groups ?? []).includes(teachersGroupPk))
			: authentikUsers;

		return { users: filtered, allGroups, role: 'teachers', groupPk: teachersGroupPk ?? '' };
	} catch (err) {
		return {
			users: [],
			allGroups: [],
			role: 'teachers',
			groupPk: '',
			error: err instanceof Error ? err.message : 'Failed to fetch users.'
		};
	}
};
