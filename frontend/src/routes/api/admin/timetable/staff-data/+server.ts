import { json, error } from '@sveltejs/kit';
import { adminProxy } from '$lib/server/golem';
import type { RequestEvent } from './$types';

export async function GET({ url, locals }: RequestEvent) {
  const sessionTerm = url.searchParams.get('session_term');
  if (!sessionTerm) {
    return json({ error: { message: 'session_term is required' } }, { status: 400 });
  }

  const user = locals.user;
  if (!user || !user.roles.includes('admin')) {
    error(403, 'Forbidden');
  }

  const proxy = adminProxy(user, event.request.signal);
  const result = await proxy(`/timetable-staff-data?session_term=${encodeURIComponent(sessionTerm)}`);

  if (result.error) {
    return json({ error: { message: result.error.message } }, { status: 400 });
  }

  try {
    return json({ data: JSON.parse(result.data) });
  } catch {
    return json({ error: { message: 'Failed to parse response' } }, { status: 502 });
  }
}
