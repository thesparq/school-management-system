import { fetchAllUsers, fetchAllGroups } from '$lib/server/authentik';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals }) => {
	const user = locals.user;
	if (!user || !user.roles.includes('admin')) return { users: [], allGroups: [], role: 'parent', groupPk: '', error: 'Not authorized' };

	try {
		const [users, allGroups] = await Promise.all([fetchAllUsers(), fetchAllGroups()]);
		const parentGroup = allGroups.find((g) => g.name === 'parent');
		const parentUsers = parentGroup ? users.filter((u) => u.groups.includes(parentGroup.pk)) : [];
		return {
			users: parentUsers,
			allGroups,
			role: 'parent',
			groupPk: parentGroup?.pk ?? ''
		};
	} catch (e) {
		return { users: [], allGroups: [], role: 'parent', groupPk: '', error: e instanceof Error ? e.message : 'Failed to load data' };
	}
};
