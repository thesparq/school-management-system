import type { PageLoad } from './$types';

export const load: PageLoad = ({ fetch }) => {
	return {
		title: 'Class Levels',
		breadcrumbs: [
			{ label: 'Dashboard', href: '/' },
			{ label: 'Configuration' },
			{ label: 'Class Levels' }
		],
		streamed: {
			classLevelsRes: fetch('/api/admin/class-levels').then(res => res.json())
		}
	};
};
