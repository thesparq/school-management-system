import { json } from '@sveltejs/kit';
import { adminProxy } from '$lib/server/golem';

export async function POST(event) {
  return adminProxy(event.locals.user, '/class-arms', { method: 'POST', body: await event.request.json() });
}
