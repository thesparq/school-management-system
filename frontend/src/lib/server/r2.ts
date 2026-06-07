import { S3Client, PutObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

const ALLOWED_TYPES = ['image/jpeg', 'image/png'];
const MAX_SIZE_BYTES = 5 * 1024 * 1024;

let r2Client: S3Client | null = null;
let bucketName: string | null = null;
let publicUrlBase: string | null = null;

function getR2Client(): S3Client {
	if (r2Client) return r2Client;
	const endpoint = process.env.R2_ENDPOINT_URL;
	const keyId = process.env.R2_ACCESS_KEY_ID;
	const secretKey = process.env.R2_SECRET_ACCESS_KEY;
	if (!endpoint || !keyId || !secretKey) {
		throw new Error('Missing R2 configuration: R2_ENDPOINT_URL, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY must be set');
	}
	r2Client = new S3Client({
		region: 'auto',
		endpoint,
		credentials: { accessKeyId: keyId, secretAccessKey: secretKey }
	});
	return r2Client;
}

function getBucket(): string {
	if (bucketName) return bucketName;
	const b = process.env.R2_BUCKET_NAME;
	if (!b) throw new Error('Missing R2_BUCKET_NAME environment variable');
	bucketName = b;
	return bucketName;
}

function getPublicUrlBase(): string {
	if (publicUrlBase) return publicUrlBase;
	const u = process.env.R2_PUBLIC_URL;
	if (!u) throw new Error('Missing R2_PUBLIC_URL environment variable');
	publicUrlBase = u;
	return publicUrlBase;
}

export function getR2Key(profileType: string, userId: string, contentType: string): { key: string; ext: string } {
	const ext = contentType === 'image/png' ? 'png' : 'jpg';
	return { key: `passports/${profileType}/${userId}.${ext}`, ext };
}

export function validateUploadRequest(contentType: string, fileSize: number): string | null {
	if (!ALLOWED_TYPES.includes(contentType)) return 'File type must be JPEG or PNG';
	if (fileSize > MAX_SIZE_BYTES) return 'File size must not exceed 5 MB';
	return null;
}

export async function generatePresignedUploadUrl(profileType: string, userId: string, contentType: string, fileSize: number) {
	const error = validateUploadRequest(contentType, fileSize);
	if (error) throw new Error(error);
	const { key } = getR2Key(profileType, userId, contentType);
	const uploadUrl = await getSignedUrl(
		getR2Client(),
		new PutObjectCommand({ Bucket: getBucket(), Key: key, ContentType: contentType }),
		{ expiresIn: 300 }
	);
	const publicUrl = `${getPublicUrlBase()}/${key}`;
	return { uploadUrl, publicUrl, key };
}

export async function deleteR2Object(profileType: string, userId: string, contentType: string) {
	const { key } = getR2Key(profileType, userId, contentType);
	try {
		await getR2Client().send(new DeleteObjectCommand({ Bucket: getBucket(), Key: key }));
	} catch {
		// ignore delete errors — file may not exist
	}
}
