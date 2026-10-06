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

export const load: PageServerLoad = (event) => {
	const user = event.locals.user;
	if (!user) return { streamed: { dataPromise: Promise.resolve({ role: 'guest' }) } };

	if (user.roles.includes('superadmin') || user.roles.includes('admin')) {
		return { streamed: { dataPromise: Promise.resolve({ role: 'admin' }) } };
	}

	// Teacher dashboard: fetch my classes
	if (user.roles.includes('teacher') && !user.roles.includes('student')) {
    const dataPromise = proxyToTeacher(user.id, '/classes').then(classesResult => {
      if (classesResult.error) {
				return { role: 'teacher', teacherClassesError: classesResult.error.message };
			}
      try {
        const parsed = JSON.parse(classesResult.data);
        const teacherClasses: TeacherClassGroup[] = Array.isArray(parsed) ? parsed : [];
        return { role: 'teacher', teacherClasses };
      } catch {
        return { role: 'teacher', teacherClassesError: 'Invalid response' };
      }
    }).catch(() => ({ role: 'teacher', teacherClassesError: 'Failed to reach backend service.' }));
    
    return { streamed: { dataPromise } };
	}

	// Student (or teacher+student) dashboard: fetch subjects
  const dataPromise = proxyToStudent(user.id, '/subjects').then(subjResult => {
    if (subjResult.error) {
      return { role: 'student', subjectsError: subjResult.error.message, subjectsErrorCode: subjResult.error.code };
    }
    try {
      const parsed = JSON.parse(subjResult.data);
      const subjects: Subject[] = Array.isArray(parsed) ? parsed : [];
      return { role: 'student', subjects };
    } catch {
      return { role: 'student', subjectsError: 'Invalid response' };
    }
  }).catch(() => ({ role: 'student', subjectsError: 'Failed to reach backend service.' }));
  
	return { streamed: { dataPromise } };
};
