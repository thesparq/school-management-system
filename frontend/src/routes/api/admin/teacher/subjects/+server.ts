import { proxyToGateway } from '$lib/server/golem';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const POST: RequestHandler = async (event) => {
  const user = event.locals.user;
  if (!user) error(401, 'Not authenticated');
  if (!user.roles.includes('admin')) error(403, 'Forbidden');

  const body = await event.request.json().catch(() => ({}));
  const targetTeacherId = body.target_teacher_id;
  const pairs = body.pairs;
  if (!targetTeacherId || !Array.isArray(pairs)) {
    return new Response(
      JSON.stringify({ error: { code: 'BAD_REQUEST', message: 'Missing target_teacher_id or pairs array.' } }),
      { status: 400, headers: { 'content-type': 'application/json' } }
    );
  }

  const result = await proxyToGateway(
    '/gateway/admin/teacher/subjects',
    user.id,
    { target_teacher_id: targetTeacherId, pairs_json: JSON.stringify(pairs) }
  );

  if (result.error) {
    return new Response(JSON.stringify(result), {
      status: 502,
      headers: { 'content-type': 'application/json' }
    });
  }

  return new Response(
    JSON.stringify({ data: { saved: true } }),
    { status: 200, headers: { 'content-type': 'application/json' } }
  );
};
