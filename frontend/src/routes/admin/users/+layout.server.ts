import { error } from '@sveltejs/kit';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async (event) => {
	const user = event.locals.user;
	if (!user) error(401, 'Unauthorized');
	if (!user.roles.includes('admin')) error(403, 'Forbidden');
	return {};
};
