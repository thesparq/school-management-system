import { proxyToGateway } from '$lib/server/golem';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const GET: RequestHandler = async (event) => {
  const user = event.locals.user;
  if (!user) error(401, 'Not authenticated');
  if (!user.roles.includes('admin')) error(403, 'Forbidden');

  const uuid = event.params.uuid;

  const result = await proxyToGateway('/gateway/admin/teacher/subjects-read', user.id, {
    target_teacher_id: uuid
  });

  if (result.error) {
    return new Response(JSON.stringify(result), {
      status: 502,
      headers: { 'content-type': 'application/json' }
    });
  }

  let data: unknown;
  try {
    data = JSON.parse(result.data);
  } catch {
    return new Response(
      JSON.stringify({ error: { code: 'INVALID_RESPONSE', message: 'Failed to parse gateway response' } }),
      { status: 502, headers: { 'content-type': 'application/json' } }
    );
  }

  return new Response(
    JSON.stringify({ data }),
    { status: 200, headers: { 'content-type': 'application/json' } }
  );
};
