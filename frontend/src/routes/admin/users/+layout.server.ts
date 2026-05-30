import { error, redirect } from '@sveltejs/kit';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async (event) => {
	const user = event.locals.user;
	if (!user) redirect(302, '/');
	if (!user.roles.includes('admin')) error(403, 'Forbidden');
	return {};
};
