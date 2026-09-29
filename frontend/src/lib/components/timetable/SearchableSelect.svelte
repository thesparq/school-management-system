<script lang="ts" module>
  export interface SearchableOption {
    value: string;
    label: string;
    subLabel?: string;
    badge?: string;
    badgeColor?: string;
  }
</script>

<script lang="ts">
  import { onMount } from 'svelte';

  let {
    options,
    value = $bindable(),
    onChange,
    placeholder = 'Type or select...',
    label,
    className = '',
    disabled = false,
    required = false,
    id = '',
  } = $props<{
    options: SearchableOption[];
    value: string;
    onChange?: (value: string) => void;
    placeholder?: string;
    label?: string;
    className?: string;
    disabled?: boolean;
    required?: boolean;
    id?: string;
  }>();

  let isOpen = $state(false);
  let searchTerm = $state('');
  let highlightedIndex = $state(0);
  
  let containerRef: HTMLDivElement;
  let inputRef: HTMLInputElement;

  let selectedOption = $derived(options.find((opt: any) => opt.value === value));

  $effect(() => {
    if (selectedOption) {
      searchTerm = selectedOption.label;
    } else if (!value) {
      searchTerm = '';
    }
  });

  let filteredOptions = $derived(options.filter((opt: any) => {
    if (!isOpen) return true;
    if (!searchTerm.trim()) return true;
    const query = searchTerm.toLowerCase().trim();
    return (
      opt.label.toLowerCase().includes(query) ||
      (opt.subLabel && opt.subLabel.toLowerCase().includes(query)) ||
      (opt.badge && opt.badge.toLowerCase().includes(query))
    );
  }));

  onMount(() => {
    const handleOutsideClick = (e: MouseEvent) => {
      if (containerRef && !containerRef.contains(e.target as Node)) {
        isOpen = false;
        if (selectedOption) {
          searchTerm = selectedOption.label;
        } else {
          searchTerm = '';
        }
      }
    };
    document.addEventListener('mousedown', handleOutsideClick);
    return () => document.removeEventListener('mousedown', handleOutsideClick);
  });

  const handleSelect = (opt: SearchableOption) => {
    value = opt.value;
    if (onChange) onChange(opt.value);
    searchTerm = opt.label;
    isOpen = false;
  };

  const handleInputChange = (e: Event) => {
    searchTerm = (e.target as HTMLInputElement).value;
    isOpen = true;
    highlightedIndex = 0;
  };

  const handleFocus = () => {
    if (disabled) return;
    isOpen = true;
    setTimeout(() => {
      inputRef?.select();
    }, 0);
  };

  const handleKeyDown = (e: KeyboardEvent) => {
    if (disabled) return;

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (!isOpen) {
        isOpen = true;
      } else {
        highlightedIndex = highlightedIndex + 1 < filteredOptions.length ? highlightedIndex + 1 : 0;
      }
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (isOpen) {
        highlightedIndex = highlightedIndex - 1 >= 0 ? highlightedIndex - 1 : filteredOptions.length - 1;
      }
    } else if (e.key === 'Enter') {
      if (isOpen && filteredOptions.length > 0) {
        e.preventDefault();
        const optionToSelect = filteredOptions[highlightedIndex] || filteredOptions[0];
        if (optionToSelect) {
          handleSelect(optionToSelect);
        }
      }
    } else if (e.key === 'Escape') {
      isOpen = false;
      if (selectedOption) {
        searchTerm = selectedOption.label;
      }
    }
  };
</script>

<div class="relative {className}" bind:this={containerRef}>
  {#if label}
    <label for={id} class="block text-xs font-bold text-slate-700 mb-1">
      {label} {#if required}<span class="text-red-500">*</span>{/if}
    </label>
  {/if}

  <div class="relative">
    <input
      bind:this={inputRef}
      {id}
      type="text"
      value={searchTerm}
      oninput={handleInputChange}
      onfocus={handleFocus}
      onkeydown={handleKeyDown}
      {placeholder}
      {disabled}
      autocomplete="off"
      class="w-full bg-white border border-slate-300 rounded-xl pl-3.5 pr-10 py-2.5 text-sm font-bold text-slate-900 outline-none transition-all focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-600 disabled:bg-slate-100 disabled:text-slate-400 disabled:cursor-not-allowed shadow-sm hover:border-slate-400"
    />

    <!-- Right Action Icons (Clear / Dropdown toggle) -->
    <div class="absolute right-2.5 top-1/2 -translate-y-1/2 flex items-center space-x-1">
      {#if searchTerm && !disabled}
        <button
          type="button"
          tabindex="-1"
          onclick={(e) => {
            e.stopPropagation();
            searchTerm = '';
            value = '';
            if (onChange) onChange('');
            isOpen = true;
            inputRef?.focus();
          }}
          class="text-slate-400 hover:text-slate-600 p-0.5 rounded-md hover:bg-slate-100 transition-colors"
          title="Clear input"
        >
          <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      {/if}

      <button
        type="button"
        tabindex="-1"
        onclick={() => {
          if (!disabled) {
            isOpen = !isOpen;
            if (!isOpen) {
              inputRef?.focus();
            }
          }
        }}
        class="text-slate-400 hover:text-slate-600 p-0.5"
      >
        <svg
          class="w-4 h-4 transition-transform duration-200 {isOpen ? 'rotate-180 text-indigo-600' : ''}"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
        </svg>
      </button>
    </div>
  </div>

  <!-- Floating Dropdown Menu -->
  {#if isOpen && !disabled}
    <div class="absolute z-50 mt-1 w-full bg-white border border-slate-200 rounded-xl shadow-xl max-h-60 overflow-y-auto py-1 animate-in fade-in zoom-in-95 duration-100">
      {#if filteredOptions.length > 0}
        {#each filteredOptions as opt, idx}
          {@const isSelected = opt.value === value}
          {@const isHighlighted = idx === highlightedIndex}

          <div
            role="button"
            tabindex="0"
            onmousedown={(e) => {
              e.preventDefault(); // Prevent blur before select
              handleSelect(opt);
            }}
            onmouseenter={() => highlightedIndex = idx}
            class="px-3.5 py-2.5 text-xs font-bold cursor-pointer flex items-center justify-between transition-colors {isSelected ? 'bg-indigo-50 text-indigo-900 font-extrabold' : isHighlighted ? 'bg-slate-100 text-slate-900' : 'text-slate-700 hover:bg-slate-50'}"
          >
            <div class="flex flex-col">
              <div class="flex items-center space-x-2">
                <span>{opt.label}</span>
                {#if isSelected}
                  <span class="w-1.5 h-1.5 rounded-full bg-indigo-600"></span>
                {/if}
              </div>
              {#if opt.subLabel}
                <span class="text-[11px] font-medium text-slate-500 mt-0.5">
                  {opt.subLabel}
                </span>
              {/if}
            </div>

            {#if opt.badge}
              <span class="text-[10px] font-black px-2 py-0.5 rounded-md {opt.badgeColor || 'bg-slate-100 text-slate-600'}">
                {opt.badge}
              </span>
            {/if}
          </div>
        {/each}
      {:else}
        <div class="px-4 py-3 text-xs text-slate-400 font-medium text-center">
          No matching options for "{searchTerm}"
        </div>
      {/if}
    </div>
  {/if}
</div>
