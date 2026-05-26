<script lang='ts'>
	import { enhance } from '$app/forms';
	import type { ActionData } from './$types';

	let { form }: { form: ActionData } = $props();
</script>

<h1>Login</h1>
<form method="post" action="?/signInSocial" use:enhance>
	<input type="hidden" name="provider" value="github" />
	<input type="hidden" name="callbackURL" value="/demo/better-auth" />
	<button class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition">Sign in with GitHub</button>
</form>
