import type { PageLoad } from './$types';

export const load: PageLoad = ({ fetch }) => {
	return {
		title: 'Terms',
		breadcrumbs: [
			{ label: 'Dashboard', href: '/' },
			{ label: 'Configuration' },
			{ label: 'Terms' }
		],
		streamed: {
			termsRes: fetch('/api/admin/terms').then(res => res.json())
		}
	};
};
