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
		const targetGroup = allGroups.find(g => g.name.toLowerCase() === 'parents' || g.name.toLowerCase() === 'parent');
		const groupPk = targetGroup?.pk ?? null;
		const filtered = groupPk
			? authentikUsers.filter(u => (u.groups ?? []).includes(groupPk))
			: authentikUsers;
		return { users: filtered, allGroups, groupPk: groupPk ?? '' };
	});

	return {
		role: 'parents',
		streamed: { usersPromise }
	};
};
