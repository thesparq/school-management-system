import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { generatePresignedUploadUrl } from '$lib/server/r2';

export const POST: RequestHandler = async ({ request, locals }) => {
	const user = locals.user;
	if (!user || !user.roles.includes('admin')) {
		return json({ error: { code: 'AUTH_FAILURE', message: 'Not authorized' } }, { status: 401 });
	}

	let body: { profileType?: string; userId?: string; contentType?: string; fileSize?: number };
	try {
		body = await request.json();
	} catch {
		return json({ error: { code: 'VALIDATION_ERROR', message: 'Invalid JSON body' } }, { status: 400 });
	}

	const { profileType, userId, contentType, fileSize } = body;
	if (!profileType || !userId || !contentType || fileSize === undefined) {
		return json({ error: { code: 'VALIDATION_ERROR', message: 'profileType, userId, contentType, and fileSize are required' } }, { status: 400 });
	}

	if (!['student', 'teacher', 'admin', 'parent'].includes(profileType)) {
		return json({ error: { code: 'VALIDATION_ERROR', message: 'Invalid profileType' } }, { status: 400 });
	}

	if (fileSize > 5 * 1024 * 1024) {
		return json({ error: { code: 'VALIDATION_ERROR', message: 'File size must not exceed 5 MB' } }, { status: 400 });
	}

	try {
		const { uploadUrl, publicUrl } = await generatePresignedUploadUrl(profileType, userId, contentType, fileSize);
		return json({ uploadUrl, publicUrl });
	} catch (e) {
		return json({ error: { code: 'SERVER_ERROR', message: e instanceof Error ? e.message : 'Upload failed' } }, { status: 500 });
	}
};
