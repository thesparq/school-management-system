# Cloudflare R2 Setup Guide

## 1. Create R2 Bucket

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com) → **R2**
2. Click **Create bucket**
3. Name: `school-management` (or your preferred name)
4. Click **Create bucket**

## 2. Configure CORS

In your bucket settings → **CORS** tab, add a rule:

```json
[
  {
    "AllowedOrigins": ["*"],
    "AllowedMethods": ["PUT", "DELETE"],
    "AllowedHeaders": ["Content-Type"],
    "MaxAgeSeconds": 3600
  }
]
```

**For production**, replace `"*"` with your actual frontend origin (e.g., `"https://portal.yourschool.com"`).

## 3. Create API Token

1. **Manage R2 API Tokens** → **Create API Token**
2. Permissions: **Object Read & Write**
3. Specify bucket: `school-management`
4. Save the token — copy:
   - **Access Key ID**
   - **Secret Access Key**

## 4. Get Endpoint URL

Your R2 endpoint URL is:

```
https://{account_id}.r2.cloudflarestorage.com
```

Find your `{account_id}` in the R2 dashboard URL or Cloudflare dashboard → **Account Home** → **Account ID** in the right sidebar.

## 5. Public URL (Custom Domain)

Option A — **r2.dev subdomain** (simplest):
1. In your bucket settings, enable `r2.dev` access
2. Public URL will be: `https://pub-{hash}.r2.dev`

Option B — **Custom domain** (recommended for production):
1. Add your domain to Cloudflare
2. Under bucket **Settings → Public access → Custom domains**, connect it
3. Public URL: `https://files.yourschool.com`

## 6. Environment Variables

Add to `frontend/.env`:

```bash
R2_ACCESS_KEY_ID=your-access-key-id
R2_SECRET_ACCESS_KEY=your-secret-access-key
R2_BUCKET_NAME=school-management
R2_PUBLIC_URL=https://pub-{hash}.r2.dev
R2_ENDPOINT_URL=https://{account_id}.r2.cloudflarestorage.com
```

## 7. Verification

Test presigned URL generation:

```bash
# Start SvelteKit and POST to the endpoint
curl -X POST http://localhost:5173/api/admin/generate-passport-upload-url \
  -H "Content-Type: application/json" \
  -d '{"profileType":"student","userId":"test-uuid","contentType":"image/jpeg","fileSize":1000}'
```

Expected response:
```json
{
  "uploadUrl": "https://...",
  "publicUrl": "https://..."
}
```

Test file upload via presigned URL:
```bash
curl -X PUT "{uploadUrl}" \
  -H "Content-Type: image/jpeg" \
  --data-binary @test-image.jpg
```

Should return `200 OK`. File visible in R2 dashboard under `student/test-uuid/passport.jpg`.

## Object Key Structure

```
{profileType}/{userUuid}/passport.{ext}

Examples:
  student/a1b2c3d4-e5f6-7890-abcd-ef1234567890/passport.jpg
  teacher/b2c3d4e5-f6a7-8901-bcde-f12345678901/passport.png
  admin/c3d4e5f6-a7b8-9012-cdef-123456789012/passport.jpg
  parent/d4e5f6a7-b8c9-0123-defa-234567890123/passport.jpg
```

## Delete Compensation (Saga)

On user creation failure, the SvelteKit API route calls `deleteR2Object()` to remove the orphaned file:

```typescript
import { deleteR2Object } from '$lib/server/r2';
await deleteR2Object('student', uuid, 'image/jpeg');
```

On edit failure: no compensation needed — deterministic key means retry overwrites same file.
