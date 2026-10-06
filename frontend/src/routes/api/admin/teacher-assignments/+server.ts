import { adminProxy } from '$lib/server/golem';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const POST: RequestHandler = async (event) => {
  const user = event.locals.user;
  if (!user || !user.roles.includes('admin')) error(403, 'Forbidden');
  
  const payload = await event.request.json();
  const proxy = adminProxy(user, event.request.signal);
  const result = await proxy('/teacher-assignments', 'POST', payload);
  
  if (result.error) return new Response(JSON.stringify(result), { status: 502 });
  return new Response(JSON.stringify(JSON.parse(result.data || "{}")), { status: 200 });
};
