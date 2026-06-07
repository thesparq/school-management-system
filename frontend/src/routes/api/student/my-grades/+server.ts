import { proxyToStudent, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async (event) => {
  const userId = event.locals.user?.id;
  if (!userId) {
    return new Response(JSON.stringify({ error: { code: 'UNAUTHENTICATED', message: 'Not authenticated.' } }), { status: 401, headers: { 'content-type': 'application/json' } });
  }

  const url = new URL(event.request.url);
  const assessment_type = url.searchParams.get('assessment_type');
  const assessment_id = url.searchParams.get('assessment_id');
  if (!assessment_type || !assessment_id) {
    return new Response(JSON.stringify({ error: { code: 'BAD_REQUEST', message: 'Missing assessment_type or assessment_id query params.' } }), { status: 400, headers: { 'content-type': 'application/json' } });
  }

  const result = await proxyToStudent(userId, '/my-grades', { assessment_type, assessment_id });
  if (result.error) {
    return new Response(JSON.stringify(result), { status: mapErrorCodeToHttpStatus(result.error.code), headers: { 'content-type': 'application/json' } });
  }

  let data: unknown;
  try { data = JSON.parse(result.data); } catch {
    return new Response(JSON.stringify({ error: { code: 'INVALID_RESPONSE', message: 'Failed to parse gateway response' } }), { status: 502, headers: { 'content-type': 'application/json' } });
  }
  return new Response(JSON.stringify({ data }), { status: 200, headers: { 'content-type': 'application/json' } });
};
