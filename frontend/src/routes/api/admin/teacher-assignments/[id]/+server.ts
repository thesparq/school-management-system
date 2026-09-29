import { adminProxy } from '$lib/server/golem';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const DELETE: RequestHandler = async (event) => {
  const user = event.locals.user;
  if (!user || !user.roles.includes('admin')) error(403, 'Forbidden');
  const proxy = adminProxy(user, event.request.signal);
  const result = await proxy(`/teacher-assignments/${event.params.id}`, 'DELETE');
  if (result.error) return new Response(JSON.stringify(result), { status: 502 });
  return new Response(JSON.stringify({}), { status: 200 });
};
