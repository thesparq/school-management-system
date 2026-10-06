import type { PageLoad } from './$types';

export const load: PageLoad = ({ fetch }) => {
	const loadData = async () => {
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
			subjects = json.data || [];
		}

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
		
		return { timetables, classes, teachers, subjects, slots, dayConfigs };
	};

	return {
		title: 'Timetable Dashboard',
		breadcrumbs: [
			{ label: 'Dashboard', href: '/' },
			{ label: 'Timetable Dashboard' }
		],
		streamed: {
			timetableData: loadData()
		}
	};
};
