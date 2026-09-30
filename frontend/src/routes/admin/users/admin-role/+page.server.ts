import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { fetchAllUsers, fetchAllGroups } from '$lib/server/authentik';

export const load: PageServerLoad = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) error(403, 'Forbidden');

	const usersPromise = Promise.all([
		fetchAllUsers(),
		fetchAllGroups()
	]).then(([authentikUsers, allGroups]) => {
		const adminGroup = allGroups.find(g => g.name.toLowerCase() === 'administrators' || g.name.toLowerCase() === 'admin');
		const adminGroupPk = adminGroup?.pk ?? null;
		const filtered = adminGroupPk
			? authentikUsers.filter(u => (u.groups ?? []).includes(adminGroupPk))
			: authentikUsers;
		return { users: filtered, allGroups, groupPk: adminGroupPk ?? '' };
	});

	return {
		role: 'admin-role',
		streamed: { usersPromise }
	};
};
