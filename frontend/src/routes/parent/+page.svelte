<script lang="ts">
	import PageHeader from '$lib/components/PageHeader.svelte';
	import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '$lib/components/ui/card';
	import { UsersThree, CreditCard, ChatTeardrop } from 'phosphor-svelte';
</script>

<div class="space-y-6">
	<PageHeader title="Parent Hub" />
	<p class="text-muted-foreground mt-1 text-sm font-medium -mt-2">
		Stay updated on your children's progress and school activities.
	</p>

	<div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
		<a href="/parent/wards" class="block group">
			<Card class="h-full transition-colors hover:bg-muted/50">
				<CardHeader>
					<div class="flex items-center gap-2">
						<UsersThree class="h-5 w-5 text-primary" />
						<CardTitle class="text-lg">My Children</CardTitle>
					</div>
					<CardDescription>View academic progress, attendance, and reports.</CardDescription>
				</CardHeader>
			</Card>
		</a>

		<a href="/parent/payments" class="block group">
			<Card class="h-full transition-colors hover:bg-muted/50">
				<CardHeader>
					<div class="flex items-center gap-2">
						<CreditCard class="h-5 w-5 text-primary" />
						<CardTitle class="text-lg">Payments</CardTitle>
					</div>
					<CardDescription>Manage tuition fees, bills, and payment history.</CardDescription>
				</CardHeader>
			</Card>
		</a>

		<a href="/parent/communications" class="block group">
			<Card class="h-full transition-colors hover:bg-muted/50">
				<CardHeader>
					<div class="flex items-center gap-2">
						<ChatTeardrop class="h-5 w-5 text-primary" />
						<CardTitle class="text-lg">Communications</CardTitle>
					</div>
					<CardDescription>Messages from teachers and school administration.</CardDescription>
				</CardHeader>
			</Card>
		</a>
	</div>
</div>
