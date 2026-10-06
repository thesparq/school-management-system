import type { PageLoad } from './$types';

export const load: PageLoad = ({ fetch }) => {
	return {
		title: 'Subjects',
		breadcrumbs: [
			{ label: 'Dashboard', href: '/' },
			{ label: 'Configuration' },
			{ label: 'Subjects' }
		],
		streamed: {
			subjectsRes: fetch('/api/admin/subjects').then(res => res.json())
		}
	};
};
