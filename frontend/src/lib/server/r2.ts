import { S3Client, PutObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

const ALLOWED_TYPES = ['image/jpeg', 'image/png'];
const MAX_SIZE_BYTES = 5 * 1024 * 1024;

const r2 = new S3Client({
	region: 'auto',
	endpoint: process.env.R2_ENDPOINT_URL!,
	credentials: {
		accessKeyId: process.env.R2_ACCESS_KEY_ID!,
		secretAccessKey: process.env.R2_SECRET_ACCESS_KEY!
	}
});

const BUCKET = process.env.R2_BUCKET_NAME!;
const PUBLIC_URL_BASE = process.env.R2_PUBLIC_URL!;

export function getR2Key(profileType: string, userId: string, contentType: string): { key: string; ext: string } {
	const ext = contentType === 'image/png' ? 'png' : 'jpg';
	return { key: `passports/${profileType}/${userId}.${ext}`, ext };
}

export function validateUploadRequest(contentType: string, fileSize: number): string | null {
	if (!ALLOWED_TYPES.includes(contentType)) return 'File type must be JPEG or PNG';
	if (fileSize > MAX_SIZE_BYTES) return 'File size must not exceed 5 MB';
	return null;
}

export async function generatePresignedUploadUrl(profileType: string, userId: string, contentType: string) {
	const error = validateUploadRequest(contentType, 0);
	if (error) throw new Error(error);
	const { key } = getR2Key(profileType, userId, contentType);
	const uploadUrl = await getSignedUrl(
		r2,
		new PutObjectCommand({ Bucket: BUCKET, Key: key, ContentType: contentType }),
		{ expiresIn: 300 }
	);
	const publicUrl = `${PUBLIC_URL_BASE}/${key}`;
	return { uploadUrl, publicUrl, key };
}

export async function deleteR2Object(profileType: string, userId: string, contentType: string) {
	const { key } = getR2Key(profileType, userId, contentType);
	try {
		await r2.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: key }));
	} catch {
		// ignore delete errors — file may not exist
	}
}
