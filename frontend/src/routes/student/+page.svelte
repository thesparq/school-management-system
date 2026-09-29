<script lang="ts">
	import PageHeader from '$lib/components/PageHeader.svelte';
	import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '$lib/components/ui/card';
	import { Book, CalendarBlank, Student } from 'phosphor-svelte';
</script>

<div class="space-y-6">
	<PageHeader title="Student Hub" />
	<p class="text-muted-foreground mt-1 text-sm font-medium -mt-2">
		Access your courses, schedule, and academic records.
	</p>

	<div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
		<a href="/" class="block group">
			<Card class="h-full transition-colors hover:bg-muted/50">
				<CardHeader>
					<div class="flex items-center gap-2">
						<Book class="h-5 w-5 text-primary" />
						<CardTitle class="text-lg">My Courses</CardTitle>
					</div>
					<CardDescription>Access learning materials, assignments, and curriculum.</CardDescription>
				</CardHeader>
			</Card>
		</a>

		<a href="/student/timetable" class="block group">
			<Card class="h-full transition-colors hover:bg-muted/50">
				<CardHeader>
					<div class="flex items-center gap-2">
						<CalendarBlank class="h-5 w-5 text-primary" />
						<CardTitle class="text-lg">Timetable</CardTitle>
					</div>
					<CardDescription>View your daily and weekly class schedule.</CardDescription>
				</CardHeader>
			</Card>
		</a>

		<a href="/student/grades" class="block group">
			<Card class="h-full transition-colors hover:bg-muted/50">
				<CardHeader>
					<div class="flex items-center gap-2">
						<Student class="h-5 w-5 text-primary" />
						<CardTitle class="text-lg">Grades & Reports</CardTitle>
					</div>
					<CardDescription>Check your continuous assessments and report cards.</CardDescription>
				</CardHeader>
			</Card>
		</a>
	</div>
</div>
