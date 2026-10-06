import { writable } from 'svelte/store';

export type ToastVariant = 'success' | 'info' | 'warning' | 'error';

export interface Toast {
	id: string;
	variant: ToastVariant;
	title: string;
	description: string;
	durationMs: number;
}

const { subscribe, update } = writable<Toast[]>([]);

let counter = 0;

export const toasts = { subscribe };

function sanitizeMessage(msg: string): string {
	try {
		const parsed = JSON.parse(msg);
		if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
			if (parsed.message) return parsed.message;
			if (parsed.errors?.[0]) return parsed.errors[0];
		}
	} catch {}
	return msg;
}

export function addToast(variant: ToastVariant, title: string, description: string, durationMs: number = 5000) {
	const id = (counter++).toFixed();
	update((t) => [...t, { id, variant, title, description: sanitizeMessage(description), durationMs }]);
}

export function dismissToast(id: string) {
	update((t) => t.filter((toast) => toast.id !== id));
}
