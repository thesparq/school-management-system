export interface BaseUser {
	pk: number;
	uuid: string;
	username: string;
	email: string;
	groups: string[];
	is_active: boolean;
}

export interface StudentUser extends BaseUser {
	surname: string;
	first_name: string;
	middle_name?: string;
	display_name: string;
	date_of_birth: string;
	class_enrolled: string;
	current_class: string;
	passport: string;
}

export interface TeacherUser extends BaseUser {
	surname: string;
	first_name: string;
	middle_name?: string;
	display_name: string;
	qualifications?: string[];
	date_employed?: string;
	passport: string;
}

export interface AdminUser extends BaseUser {
	surname: string;
	first_name: string;
	middle_name?: string;
	display_name: string;
	role_title?: string;
	passport: string;
}

export interface ParentUser extends BaseUser {
	name: string;
	display_name: string;
	students: string[];
	passport: string;
}

/** Minimal user row for table display (backward compat with existing code) */
export interface UserRow {
	pk: number;
	uuid: string;
	username: string;
	name: string;
	email: string;
	groups: string[];
	is_active: boolean;
}
