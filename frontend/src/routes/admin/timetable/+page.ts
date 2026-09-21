import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch }) => {
	// Let's return some basic mock/empty arrays for now so the UI renders
	// without breaking until we fully build out the data loading endpoints.
	return {
		title: 'Timetable Dashboard',
		breadcrumbs: [
			{ label: 'Dashboard', href: '/' },
			{ label: 'Admin', href: '/admin' },
			{ label: 'Timetable Dashboard' }
		],
		timetables: [],
		classes: [],
		slots: [],
	};
};
