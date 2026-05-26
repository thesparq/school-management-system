declare global {
	namespace App {
		interface User {
			id: string;
			name: string;
			email: string;
			roles: string[];
		}

		interface Locals {
			user: User | null;
		}

		// interface Error {}
		// interface PageData {}
		// interface PageState {}
		// interface Platform {}
	}
}

export {};
