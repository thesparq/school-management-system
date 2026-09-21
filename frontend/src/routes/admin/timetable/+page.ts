import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch }) => {
	const [timetablesRes, classesRes, teachersRes, subjectsRes] = await Promise.all([
		fetch('/api/admin/timetables').catch(() => null),
		fetch('/api/admin/class-levels').catch(() => null),
		fetch('/api/admin/teacher').catch(() => null),
		fetch('/api/admin/class-subjects').catch(() => null)
	]);

	let timetables = [];
	if (timetablesRes && timetablesRes.ok) {
		const json = await timetablesRes.json();
		timetables = json.data || [];
	}

	let classes = [];
	if (classesRes && classesRes.ok) {
		const json = await classesRes.json();
		classes = json.data || [];
	}

	let teachers = [];
	if (teachersRes && teachersRes.ok) {
		const json = await teachersRes.json();
		teachers = json.data || [];
	}

	let subjects = [];
	if (subjectsRes && subjectsRes.ok) {
		const json = await subjectsRes.json();
		// Extract subjects from class-subjects mappings or maybe there's a standalone subjects fetch
		subjects = json.data || [];
	}

	// For now, load slots for the first timetable
	let slots = [];
	let dayConfigs = [];
	if (timetables.length > 0) {
		const firstTtId = timetables[0].id;
		dayConfigs = timetables[0].day_configs || [];
		
		try {
			const slotsRes = await fetch(`/api/admin/schedule-slots?timetable_id=${encodeURIComponent(firstTtId)}`);
			if (slotsRes.ok) {
				const json = await slotsRes.json();
				slots = json.data || [];
			}
		} catch (e) {
			console.error('Failed to load slots', e);
		}
	}

	return {
		title: 'Timetable Dashboard',
		breadcrumbs: [
			{ label: 'Dashboard', href: '/' },
			{ label: 'Admin', href: '/admin' },
			{ label: 'Timetable Dashboard' }
		],
		timetables,
		classes,
		teachers,
		subjects,
		slots,
		dayConfigs
	};
};
