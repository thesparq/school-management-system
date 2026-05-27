export interface UserRow {
	pk: number;
	uuid: string;
	username: string;
	name: string;
	email: string;
	groups: string[];
	is_active: boolean;
}
