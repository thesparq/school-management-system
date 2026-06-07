import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { adminProxy } from '$lib/server/golem';

interface Qualification {
	id: string;
	name: string;
	active: boolean;
}

export const load: PageServerLoad = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) error(403, 'Forbidden');

	const proxy = adminProxy(user);
	let qualifications: Qualification[] = [];
	let qualificationsError: string | null = null;

	try {
		const result = await proxy('/credentials');
		if (result.error) {
			qualificationsError = result.error.message;
		} else {
			try {
				const parsed = JSON.parse(result.data);
				qualifications = Array.isArray(parsed) ? parsed : [];
			} catch {
				qualificationsError = 'Failed to parse qualifications response.';
			}
		}
	} catch {
		qualificationsError = 'Failed to reach backend service.';
	}

	return { qualifications, qualificationsError, breadcrumbs: [{ label: 'Configuration' }, { label: 'Qualifications' }] as { label: string; href?: string }[] };
};
