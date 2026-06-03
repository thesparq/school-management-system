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

		const studentsGroup = allGroups.find(g => g.name === 'student');
		const studentsGroupPk = studentsGroup?.pk ?? null;
		const filtered = studentsGroupPk
			? authentikUsers.filter(u => (u.groups ?? []).includes(studentsGroupPk))
			: authentikUsers;

		return { users: filtered, allGroups, role: 'students', groupPk: studentsGroupPk ?? '' };
	} catch (err) {
		return {
			users: [],
			allGroups: [],
			role: 'students',
			groupPk: '',
			error: err instanceof Error ? err.message : 'Failed to fetch users.'
		};
	}
};
