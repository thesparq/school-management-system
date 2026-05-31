import { proxyToGateway } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async (event) => {
  const userId = event.locals.user?.id;
  if (!userId) {
    return new Response(
      JSON.stringify({ error: { code: 'UNAUTHENTICATED', message: 'Not authenticated.' } }),
      { status: 401, headers: { 'content-type': 'application/json' } }
    );
  }

  const url = new URL(event.request.url);
  const class_level_id = url.searchParams.get('class_level_id');
  const subject_id = url.searchParams.get('subject_id');
  const term_id = url.searchParams.get('term_id');

  if (!class_level_id || !subject_id || !term_id) {
    return new Response(
      JSON.stringify({ error: { code: 'BAD_REQUEST', message: 'Missing class_level_id, subject_id, or term_id query params.' } }),
      { status: 400, headers: { 'content-type': 'application/json' } }
    );
  }

  const result = await proxyToGateway('/gateway/teacher/lessons', userId, {
    class_level_id,
    subject_id,
    term_id
  });

  if (result.error) {
    const status = result.error.code === 'NOT_INITIALIZED' ? 403 : 502;
    return new Response(JSON.stringify(result), { status, headers: { 'content-type': 'application/json' } });
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
