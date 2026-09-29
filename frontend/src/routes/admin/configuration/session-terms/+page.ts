import type { PageLoad } from './$types';

export const load: PageLoad = ({ fetch }) => {
	return {
		title: 'Session Terms',
		breadcrumbs: [
			{ label: 'Dashboard', href: '/' },
			{ label: 'Configuration' },
			{ label: 'Session Terms' }
		],
		streamed: {
			sessionTermsRes: fetch('/api/admin/session-terms').then(res => res.json()),
			termsRes: fetch('/api/admin/terms').then(res => res.json())
		}
	};
};
