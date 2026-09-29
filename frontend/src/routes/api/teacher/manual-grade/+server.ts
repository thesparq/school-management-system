import { json } from '@sveltejs/kit';
import { proxyToTeacher } from '$lib/server/golem';

export async function POST({ request, locals }) {
  if (!locals.user?.id) {
    return json({ error: 'Unauthorized' }, { status: 401 });
  }

  const body = await request.json();
  const result = await proxyToTeacher(locals.user.id, '/manual-grade', undefined, 'POST', body);
  if (result.error) {
    return json({ error: result.error.message }, { status: 400 });
  }
  return new Response(result.data, {
    headers: { 'Content-Type': 'application/json' }
  });
}
