import { proxyToGateway } from '$lib/server/golem';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async (event) => {
	const user = event.locals.user;
	if (!user) return { initialized: true };

	if (user.roles.includes('admin')) return { initialized: true };

	const result = await proxyToGateway('/gateway/check-initialization', user.id);
	if (result.error?.code === 'NOT_INITIALIZED') {
		return { initialized: false };
	}
	return { initialized: true };
};
