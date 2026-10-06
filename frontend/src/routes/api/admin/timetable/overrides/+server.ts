import { json, error } from '@sveltejs/kit';
import { adminProxy } from '$lib/server/golem';
import type { RequestEvent } from './$types';

export async function GET({ url, locals }: RequestEvent) {
  const timetableId = url.searchParams.get('timetable_id');
  if (!timetableId) {
    return json({ error: { message: 'timetable_id is required' } }, { status: 400 });
  }

  const user = locals.user;
  if (!user || !user.roles.includes('admin')) error(403, 'Forbidden');

  const proxy = adminProxy(user, event.request.signal);
  const result = await proxy(`/timetable-overrides?timetable_id=${encodeURIComponent(timetableId)}`);

  if (result.error) {
    return json({ error: { message: result.error.message } }, { status: 400 });
  }

  try {
    return json({ data: JSON.parse(result.data) });
  } catch {
    return json({ error: { message: 'Failed to parse response' } }, { status: 502 });
  }
}

export async function POST({ request, locals }: RequestEvent) {
  const body = await request.json();
  if (!body.timetable || !body.teacher) {
    return json({ error: { message: 'timetable and teacher are required' } }, { status: 400 });
  }

  const user = locals.user;
  if (!user || !user.roles.includes('admin')) error(403, 'Forbidden');

  const proxy = adminProxy(user, event.request.signal);
  const result = await proxy(`/timetable-override`, undefined, 'POST', body);

  if (result.error) {
    return json({ error: { message: result.error.message } }, { status: 400 });
  }

  try {
    return json({ data: JSON.parse(result.data) });
  } catch {
    return json({ data: result.data });
  }
}
