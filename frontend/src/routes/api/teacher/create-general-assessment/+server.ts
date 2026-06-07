import { proxyToTeacher, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async (event) => {
  const userId = event.locals.user?.id;
  if (!userId) {
    return new Response(JSON.stringify({ error: { code: 'UNAUTHENTICATED', message: 'Not authenticated.' } }), { status: 401, headers: { 'content-type': 'application/json' } });
  }

  const body = await event.request.json().catch(() => ({}));
  if (!body.session_term_id || !body.subject_id || !body.title) {
    return new Response(JSON.stringify({ error: { code: 'BAD_REQUEST', message: 'Missing session_term_id, subject_id, or title.' } }), { status: 400, headers: { 'content-type': 'application/json' } });
  }

  const result = await proxyToTeacher(userId, '/create-general-assessment', undefined, 'POST', body);
  if (result.error) {
    return new Response(JSON.stringify(result), { status: mapErrorCodeToHttpStatus(result.error.code), headers: { 'content-type': 'application/json' } });
  }

  let data: unknown;
  try { data = JSON.parse(result.data); } catch {
    return new Response(JSON.stringify({ error: { code: 'INVALID_RESPONSE', message: 'Failed to parse gateway response' } }), { status: 502, headers: { 'content-type': 'application/json' } });
  }
  return new Response(JSON.stringify({ data }), { status: 200, headers: { 'content-type': 'application/json' } });
};
