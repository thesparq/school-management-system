<script lang="ts">
	import PageHeader from '$lib/components/PageHeader.svelte';
	import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '$lib/components/ui/card';
	import { Book, CalendarBlank, Student, UsersThree } from 'phosphor-svelte';
</script>

<div class="space-y-6">
	<PageHeader title="Teacher Hub" />
	<p class="text-muted-foreground mt-1 text-sm font-medium -mt-2">
		Manage your classes, students, and timetable schedule.
	</p>

	<div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
		<a href="/my-classes" class="block group">
			<Card class="h-full transition-colors hover:bg-muted/50">
				<CardHeader>
					<div class="flex items-center gap-2">
						<UsersThree class="h-5 w-5 text-primary" />
						<CardTitle class="text-lg">My Classes</CardTitle>
					</div>
					<CardDescription>View your assigned classes, students, and manage attendance.</CardDescription>
				</CardHeader>
			</Card>
		</a>

		<a href="/teacher/timetable" class="block group">
			<Card class="h-full transition-colors hover:bg-muted/50">
				<CardHeader>
					<div class="flex items-center gap-2">
						<CalendarBlank class="h-5 w-5 text-primary" />
						<CardTitle class="text-lg">Timetable</CardTitle>
					</div>
					<CardDescription>View your weekly teaching schedule and upcoming periods.</CardDescription>
				</CardHeader>
			</Card>
		</a>

		<a href="/teacher/assessments" class="block group">
			<Card class="h-full transition-colors hover:bg-muted/50">
				<CardHeader>
					<div class="flex items-center gap-2">
						<Book class="h-5 w-5 text-primary" />
						<CardTitle class="text-lg">Assessments & Grading</CardTitle>
					</div>
					<CardDescription>Grade assignments, exams, and record continuous assessments.</CardDescription>
				</CardHeader>
			</Card>
		</a>
	</div>
</div>
