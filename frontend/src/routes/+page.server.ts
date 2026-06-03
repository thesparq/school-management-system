import { proxyToStudent, proxyToTeacher } from '$lib/server/golem';
import type { PageServerLoad } from './$types';
import type { Subject, TeacherClassGroup } from '$lib/types';

interface PageData {
	subjects: Subject[] | null;
	subjectsError: string | null;
	subjectsErrorCode: string | null;
	teacherClasses: TeacherClassGroup[] | null;
	teacherClassesError: string | null;
}

export const load: PageServerLoad = async (event) => {
	const user = event.locals.user;
	if (!user) return { subjects: null, subjectsError: null, subjectsErrorCode: null, teacherClasses: null, teacherClassesError: null } as PageData;

	if (user.roles.includes('superadmin') || user.roles.includes('admin')) {
		return { subjects: null, subjectsError: null, subjectsErrorCode: null, teacherClasses: null, teacherClassesError: null } as PageData;
	}

	// Teacher dashboard: fetch my classes
	if (user.roles.includes('teacher') && !user.roles.includes('student')) {
		try {
			const classesResult = await proxyToTeacher(user.id, '/classes');
			if (classesResult.error) {
				return { teacherClasses: null, teacherClassesError: classesResult.error.message, subjects: null, subjectsError: null, subjectsErrorCode: null } as PageData;
			}
			const parsed = JSON.parse(classesResult.data);
			const teacherClasses: TeacherClassGroup[] = Array.isArray(parsed) ? parsed : [];
			return { teacherClasses, teacherClassesError: null, subjects: null, subjectsError: null, subjectsErrorCode: null } as PageData;
		} catch {
			return { teacherClasses: null, teacherClassesError: 'Failed to reach backend service.', subjects: null, subjectsError: null, subjectsErrorCode: null } as PageData;
		}
	}

	// Student (or teacher+student) dashboard: fetch subjects
	let subjects: Subject[] | null = null;
	let subjectsError: string | null = null;
	let subjectsErrorCode: string | null = null;

	try {
		const subjResult = await proxyToStudent(user.id, '/subjects');
		if (subjResult.error) {
			subjectsError = subjResult.error.message;
			subjectsErrorCode = subjResult.error.code;
		} else {
			const parsed = JSON.parse(subjResult.data);
			subjects = Array.isArray(parsed) ? parsed : [];
		}
	} catch {
		subjectsError = 'Failed to reach backend service.';
	}

	return { subjects, subjectsError, subjectsErrorCode, teacherClasses: null, teacherClassesError: null } as PageData;
};
