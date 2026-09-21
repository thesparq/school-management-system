<script lang="ts">
  import { Button } from '$lib/components/ui/button';
  import { Input } from '$lib/components/ui/input';
  import { Label } from '$lib/components/ui/label';
  import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '$lib/components/ui/dialog';

  let { isOpen = false, onClose = () => {}, onCreated = (id: string) => {} }: { isOpen?: boolean, onClose?: () => void, onCreated?: (id: string) => void } = $props();
    
  let name = $state('');
  let description = $state('');
  let loading = $state(false);

  async function handleSubmit(e: Event) {
    e.preventDefault();
    if (!name.trim()) return;

    loading = true;
    try {
      const res = await fetch('/api/admin/timetables/create', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, description })
      });
      if (!res.ok) throw new Error(await res.text());
      const data = await res.json();
      name = '';
      description = '';
      onCreated(data.id || data.data?.id);
      onClose();
    } catch (err: any) {
      alert(`Failed to create timetable: ${err.message}`);
    } finally {
      loading = false;
    }
  }
</script>

<Dialog bind:open={isOpen} onOpenChange={(v) => !v && onClose()}>
  <DialogContent class="sm:max-w-[425px]">
    <DialogHeader>
      <DialogTitle>Create New Timetable</DialogTitle>
      <DialogDescription>
        Start a fresh allocation matrix. Day configs will default to standard weekday periods.
      </DialogDescription>
    </DialogHeader>

    <form on:submit={handleSubmit} class="space-y-4">
      <div class="space-y-2">
        <Label for="name">Name</Label>
        <Input id="name" bind:value={name} placeholder="e.g. 2026 First Term Final" required />
      </div>
      
      <div class="space-y-2">
        <Label for="desc">Description (Optional)</Label>
        <Input id="desc" bind:value={description} placeholder="Notes..." />
      </div>

      <DialogFooter>
        <Button variant="outline" type="button" onclick={onClose}>Cancel</Button>
        <Button type="submit" disabled={loading}>
          {loading ? 'Creating...' : 'Create Timetable'}
        </Button>
      </DialogFooter>
    </form>
  </DialogContent>
</Dialog>
