import { json } from '@sveltejs/kit';
import { adminProxy } from '$lib/server/golem';

export async function GET(event) {
  return adminProxy(event.locals.user, '/class-arms', { method: 'GET' });
}
