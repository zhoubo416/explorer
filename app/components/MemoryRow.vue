<script setup lang="ts">
import type { MemoryItem } from '~/composables/useExplore'

const props = defineProps<{ memory: MemoryItem }>()
</script>

<template>
  <article class="memory-row"><div class="memory-row-icon" :class="`tone-${props.memory.tone}`"><Icon :name="props.memory.icon" :size="16" /></div><div class="memory-row-copy"><span class="memory-type">{{ props.memory.type }}</span><strong>{{ props.memory.title }}</strong><p>{{ props.memory.detail }}</p></div><time>{{ props.memory.date }}</time></article>
</template>
