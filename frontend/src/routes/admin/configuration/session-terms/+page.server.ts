import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { adminProxy } from '$lib/server/golem';

interface SessionTerm {
	id: string;
	session_name: string;
	term_name: string;
	active: boolean;
	created_at: string;
}

interface Term {
	id: string;
	name: string;
}

export const load: PageServerLoad = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) error(403, 'Forbidden');

	const proxy = adminProxy(user);

	const sessionTermsPromise = proxy('/session-terms').then(result => {
		if (result.error) throw new Error(result.error.message);
		const parsed = JSON.parse(result.data);
		return (Array.isArray(parsed) ? parsed : []) as SessionTerm[];
	});

	const termsPromise = proxy('/terms').then(result => {
		if (result.error) throw new Error(result.error.message);
		const parsed = JSON.parse(result.data);
		return (Array.isArray(parsed) ? parsed : []) as Term[];
	});

	return { 
		streamed: { sessionTermsPromise, termsPromise },
		breadcrumbs: [{ label: 'Configuration' }, { label: 'Session Terms' }] as { label: string; href?: string }[]
	};
};
