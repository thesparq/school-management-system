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

	// Do NOT await the proxy call here so navigation is instant
	const termsPromise = proxy('/terms').then(result => {
		if (result.error) throw new Error(result.error.message);
		const parsed = JSON.parse(result.data);
		return (Array.isArray(parsed) ? parsed : []) as TermItem[];
	});

	return { 
		streamed: { termsPromise },
		breadcrumbs: [{ label: 'Configuration' }, { label: 'Terms' }] as { label: string; href?: string }[] 
	};
};
