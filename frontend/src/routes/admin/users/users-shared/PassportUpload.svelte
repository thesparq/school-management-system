<script lang="ts">
	import { addToast } from '$lib/stores/toast';

	let {
		currentUrl = null,
		disabled = false
	}: {
		currentUrl: string | null;
		disabled: boolean;
	} = $props();

	let publicUrl = $state<string | null>(currentUrl);
	let contentType = $state<string | null>(null);
	let uploading = $state(false);
	let error = $state<string | null>(null);
	let previewUrl = $state<string | null>(currentUrl);
	let fileInput: HTMLInputElement | undefined = $state();

	const ALLOWED_TYPES = ['image/jpeg', 'image/png'];
	const MAX_SIZE = 5 * 1024 * 1024;

	function validateFile(file: File): string | null {
		if (!ALLOWED_TYPES.includes(file.type)) return 'File must be JPEG or PNG';
		if (file.size > MAX_SIZE) return 'File must be under 5 MB';
		return null;
	}

	function handleFileSelect(e: Event) {
		const input = e.target as HTMLInputElement;
		const file = input.files?.[0];
		if (!file) return;

		const err = validateFile(file);
		if (err) {
			error = err;
			return;
		}

		error = null;
		previewUrl = URL.createObjectURL(file);
		contentType = file.type;
		publicUrl = null;
	}

	function handleRemove() {
		publicUrl = null;
		contentType = null;
		previewUrl = null;
		error = null;
		if (fileInput) fileInput.value = '';
	}

	async function uploadToR2(file: File, profileType: string, userId: string): Promise<string> {
		const res = await fetch('/api/admin/generate-passport-upload-url', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({
				profileType,
				userId,
				contentType: file.type,
				fileSize: file.size
			})
		});

		if (!res.ok) {
			const body = await res.json().catch(() => ({}));
			throw new Error(body?.error?.message ?? 'Failed to generate upload URL');
		}

		const { uploadUrl, publicUrl: r2PublicUrl } = await res.json();

		const putRes = await fetch(uploadUrl, {
			method: 'PUT',
			body: file,
			headers: { 'Content-Type': file.type }
		});

		if (!putRes.ok) throw new Error('Failed to upload passport');
		return r2PublicUrl;
	}

	export async function getPassportPublicUrl(
		file: File | null,
		profileType: string,
		userId: string
	): Promise<string | null> {
		if (!file) {
			return publicUrl;
		}
		uploading = true;
		error = null;
		try {
			const url = await uploadToR2(file, profileType, userId);
			publicUrl = url;
			return url;
		} catch (e) {
			error = e instanceof Error ? e.message : 'Upload failed';
			addToast('error', 'Passport upload failed', error);
			return null;
		} finally {
			uploading = false;
		}
	}

	export function getContentType(): string | null {
		return contentType;
	}
</script>

<div class="space-y-2">
	{#if error}
		<div class="rounded-md border border-error-500 bg-error-50 p-3 text-sm text-error-600 dark:bg-error-950/20 dark:text-error-400">
			{error}
		</div>
	{/if}

	{#if previewUrl}
		<div class="relative inline-block">
			<img src={previewUrl} alt="Passport preview" class="h-48 w-48 rounded-lg border object-cover" />
			{#if uploading}
				<div class="absolute inset-0 flex items-center justify-center rounded-lg bg-black/30">
					<div class="h-8 w-8 animate-spin rounded-full border-2 border-white border-t-transparent"></div>
				</div>
			{/if}
			{#if !disabled}
				<button
					type="button"
					onclick={handleRemove}
					class="absolute -right-2 -top-2 rounded-full bg-error-500 p-1 text-white shadow-sm hover:bg-error-600"
				>
					<svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
						<path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
					</svg>
				</button>
			{/if}
		</div>
	{:else if !disabled}
		<label
			class="flex cursor-pointer flex-col items-center gap-2 rounded-lg border-2 border-dashed border-border p-8 text-center transition hover:border-primary-300 hover:bg-primary-50/50 dark:hover:border-primary-700 dark:hover:bg-primary-950/10"
		>
			<svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8 text-muted-foreground" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
				<path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5m-13.5-9L12 3m0 0l4.5 4.5M12 3v13.5" />
			</svg>
			<span class="text-sm font-medium text-muted-foreground dark:text-muted-foreground">Click or drag passport photo</span>
			<span class="text-xs text-muted-foreground">JPEG or PNG, max 5 MB</span>
			<input
				type="file"
				accept="image/jpeg,image/png"
				onchange={handleFileSelect}
				bind:this={fileInput}
				class="hidden"
				disabled={disabled}
			/>
		</label>
	{/if}
</div>
