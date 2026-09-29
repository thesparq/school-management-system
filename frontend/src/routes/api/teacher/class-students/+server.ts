import { json } from '@sveltejs/kit';
import { proxyToTeacher } from '$lib/server/golem';

export async function GET({ request, url, locals }) {
  const classId = url.searchParams.get('class_id');
  if (!classId) return json({ error: 'class_id required' }, { status: 400 });
  
  if (!locals.user?.id) {
    return json({ error: 'Unauthorized' }, { status: 401 });
  }

  const result = await proxyToTeacher(locals.user.id, '/class-students', { class_level_id: classId }, 'GET');
  if (result.error) {
    return json({ error: result.error.message }, { status: 400 });
  }
  return new Response(result.data, {
    headers: { 'Content-Type': 'application/json' }
  });
}
