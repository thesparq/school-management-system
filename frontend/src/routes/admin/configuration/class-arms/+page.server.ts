import { adminProxy } from '$lib/server/golem';
import type { PageServerLoad } from './$types';
import { error } from '@sveltejs/kit';

export const load: PageServerLoad = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) {
		error(401, 'Not authenticated or missing admin role');
	}

	const proxy = adminProxy(user, event.request.signal);
	
	return {
		streamed: {
			classArmsRes: proxy('/class-arms').then(res => res.error ? [] : (JSON.parse(res.data) || [])),
			classLevelsRes: proxy('/class-levels').then(res => res.error ? [] : (JSON.parse(res.data) || []))
		}
	};
};
