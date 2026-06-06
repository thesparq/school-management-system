<script lang="ts">
	import { Input } from '$lib/components/ui/input';
	import { Label } from '$lib/components/ui/label';

	let {
		surname = $bindable(''),
		firstName = $bindable(''),
		middleName = $bindable('')
	}: {
		surname: string;
		firstName: string;
		middleName: string;
	} = $props();
</script>

<div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
	<div class="space-y-2">
		<Label for="surname">Surname <span class="text-error-500">*</span></Label>
		<Input id="surname" bind:value={surname} required placeholder="Okonkwo" />
	</div>
	<div class="space-y-2">
		<Label for="first_name">First Name <span class="text-error-500">*</span></Label>
		<Input id="first_name" bind:value={firstName} required placeholder="Chukwuemeka" />
	</div>
	<div class="space-y-2">
		<Label for="middle_name">Middle Name</Label>
		<Input id="middle_name" bind:value={middleName} placeholder="John" />
	</div>
</div>
