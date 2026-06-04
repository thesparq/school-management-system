import { proxyToTeacher, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async (event) => {
  const userId = event.locals.user?.id;
  if (!userId) {
    return new Response(
      JSON.stringify({ error: { code: 'UNAUTHENTICATED', message: 'Not authenticated.' } }),
      { status: 401, headers: { 'content-type': 'application/json' } }
    );
  }

  const body = await event.request.json().catch(() => ({}));
  const { term_id, active } = body;
  if (!term_id || typeof active !== 'boolean') {
    return new Response(
      JSON.stringify({ error: { code: 'BAD_REQUEST', message: 'Missing term_id or active.' } }),
      { status: 400, headers: { 'content-type': 'application/json' } }
    );
  }

  const result = await proxyToTeacher(userId, '/toggle-term-active', { term_id, active: String(active) }, 'POST');

  if (result.error) {
    return new Response(JSON.stringify(result), {
      status: mapErrorCodeToHttpStatus(result.error.code),
      headers: { 'content-type': 'application/json' }
    });
  }

  return new Response(
    JSON.stringify({ data: { success: true } }),
    { status: 200, headers: { 'content-type': 'application/json' } }
  );
};
