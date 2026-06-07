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

	let sessionTerms: SessionTerm[] = [];
	let sessionTermsError: string | null = null;
	let terms: Term[] = [];
	let termsError: string | null = null;

	// Fetch session terms (critical)
	try {
		const stResult = await proxy('/session-terms');
		if (stResult.error) {
			sessionTermsError = stResult.error.message;
		} else {
			try {
				const parsed = JSON.parse(stResult.data);
				sessionTerms = Array.isArray(parsed) ? parsed : [];
			} catch {
				sessionTermsError = 'Failed to parse session terms response.';
			}
		}
	} catch {
		sessionTermsError = 'Failed to reach backend service.';
	}

	// Fetch terms (optional — only used for create dialog dropdown)
	try {
		const termsResult = await proxy('/terms');
		if (termsResult.error) {
			termsError = termsResult.error.message;
		} else {
			try {
				const parsed = JSON.parse(termsResult.data);
				terms = Array.isArray(parsed) ? parsed : [];
			} catch {
				termsError = 'Failed to parse terms response.';
			}
		}
	} catch {
		termsError = 'Failed to load terms.';
	}

	return { sessionTerms, sessionTermsError, terms, termsError };
};
