import { proxyToGateway } from '$lib/server/golem';
import type { PageServerLoad } from './$types';
import type { Subject, TeacherClassGroup } from '$lib/types';

interface PageData {
	initialized: boolean;
	subjects: Subject[] | null;
	subjectsError: string | null;
	teacherClasses: TeacherClassGroup[] | null;
	teacherClassesError: string | null;
}

export const load: PageServerLoad = async (event) => {
	const user = event.locals.user;
	if (!user) return { initialized: true, subjects: null, subjectsError: null, teacherClasses: null, teacherClassesError: null } as PageData;

	if (user.roles.includes('admin')) {
		return { initialized: true, subjects: null, subjectsError: null, teacherClasses: null, teacherClassesError: null } as PageData;
	}

	const initResult = await proxyToGateway('/gateway/check-initialization', user.id);
	if (initResult.error?.code === 'NOT_INITIALIZED') {
		return { initialized: false, subjects: null, subjectsError: null, teacherClasses: null, teacherClassesError: null } as PageData;
	}

	// Teacher dashboard: fetch my classes
	if (user.roles.includes('teachers') && !user.roles.includes('students')) {
		try {
			const classesResult = await proxyToGateway('/gateway/teacher/classes', user.id);
			if (classesResult.error) {
				return { initialized: true, teacherClasses: null, teacherClassesError: classesResult.error.message, subjects: null, subjectsError: null } as PageData;
			}
			const parsed = JSON.parse(classesResult.data);
			const teacherClasses: TeacherClassGroup[] = Array.isArray(parsed) ? parsed : [];
			return { initialized: true, teacherClasses, teacherClassesError: null, subjects: null, subjectsError: null } as PageData;
		} catch {
			return { initialized: true, teacherClasses: null, teacherClassesError: 'Failed to reach backend service.', subjects: null, subjectsError: null } as PageData;
		}
	}

	// Student (or teacher+student) dashboard: fetch subjects
	let subjects: Subject[] | null = null;
	let subjectsError: string | null = null;

	try {
		const subjResult = await proxyToGateway('/gateway/student/subjects', user.id);
		if (subjResult.error) {
			subjectsError = subjResult.error.message;
		} else {
			const parsed = JSON.parse(subjResult.data);
			subjects = Array.isArray(parsed) ? parsed : [];
		}
	} catch {
		subjectsError = 'Failed to reach backend service.';
	}

	return { initialized: true, subjects, subjectsError, teacherClasses: null, teacherClassesError: null } as PageData;
};
