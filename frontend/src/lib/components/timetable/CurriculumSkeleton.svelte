<script lang="ts">
  import { Skeleton } from '$lib/components/ui/skeleton';
</script>

<div class="space-y-8 w-full animate-pulse">
  <!-- Card 1 Skeleton -->
  <div class="bg-card rounded-3xl shadow-sm border border-border p-6 sm:p-7 space-y-6">
    <div class="flex justify-between items-center border-b border-border pb-5">
      <div class="flex items-center space-x-3.5">
        <Skeleton class="w-10 h-10 rounded-2xl" />
        <div class="space-y-2">
          <Skeleton class="h-6 w-48" />
          <Skeleton class="h-4 w-64" />
        </div>
      </div>
      <Skeleton class="h-10 w-48 rounded-xl hidden sm:block" />
    </div>
    
    <div class="bg-muted/30 p-6 rounded-2xl border border-border space-y-6">
      <div class="space-y-3">
        <Skeleton class="h-4 w-32" />
        <Skeleton class="h-10 w-full rounded-xl" />
      </div>
      <div class="space-y-3 pt-4 border-t border-border">
        <Skeleton class="h-4 w-40" />
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <Skeleton class="h-10 w-full rounded-xl" />
          <Skeleton class="h-10 w-full rounded-xl" />
          <Skeleton class="h-10 w-full rounded-xl" />
          <Skeleton class="h-10 w-full rounded-xl" />
        </div>
      </div>
    </div>
  </div>

  <!-- Card 2 Skeleton -->
  <div class="bg-card rounded-3xl shadow-sm border border-border p-6 sm:p-7 space-y-6 opacity-80">
    <div class="flex justify-between items-center border-b border-border pb-5">
      <div class="flex items-center space-x-3.5">
        <Skeleton class="w-10 h-10 rounded-2xl" />
        <div class="space-y-2">
          <Skeleton class="h-6 w-48" />
          <Skeleton class="h-4 w-64" />
        </div>
      </div>
      <Skeleton class="h-10 w-48 rounded-xl hidden sm:block" />
    </div>
    <div class="h-[40vh] bg-muted/30 rounded-2xl border border-border"></div>
  </div>
</div>
