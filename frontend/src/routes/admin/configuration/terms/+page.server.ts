import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { adminProxy } from '$lib/server/golem';

interface TermItem {
	id: string;
	name: string;
	active: boolean;
	sort_order: number;
}

export const load: PageServerLoad = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) error(403, 'Forbidden');

	const proxy = adminProxy(user);
	let terms: TermItem[] = [];
	let termsError: string | null = null;

	try {
		const result = await proxy('/terms');
		if (result.error) {
			termsError = result.error.message;
		} else {
			try {
				const parsed = JSON.parse(result.data);
				terms = Array.isArray(parsed) ? parsed : [];
			} catch {
				termsError = 'Failed to parse terms response.';
			}
		}
	} catch {
		termsError = 'Failed to reach backend service.';
	}

	return { terms, termsError, breadcrumbs: [{ label: 'Configuration' }, { label: 'Terms' }] as { label: string; href?: string }[] };
};
