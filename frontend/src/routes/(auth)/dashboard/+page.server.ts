import { proxyToGateway } from '$lib/server/golem';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async (event) => {
	const userId = event.locals.user?.id;
	if (!userId) return { activated: true };

	const result = await proxyToGateway('/gateway/check-activation', userId);
	if (result.error?.code === 'NOT_ACTIVATED') {
		return { activated: false };
	}
	return { activated: true };
};
