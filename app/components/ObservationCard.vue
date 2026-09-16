<script setup lang="ts">
import type { Observation } from '~/composables/useExplore'

const props = defineProps<{ observation: Observation }>()
const emit = defineEmits<{ markRead: [id: string] }>()
</script>

<template>
  <article class="observation-card" :class="`observation-${props.observation.tone}`">
    <div class="observation-icon"><Icon name="spark" :size="16" /></div>
    <span class="eyebrow">{{ props.observation.label }}</span>
    <h3>{{ props.observation.title }}</h3>
    <p>{{ props.observation.content }}</p>
    <button class="text-link" type="button" @click="emit('markRead', props.observation.id)">{{ props.observation.action }} <Icon name="arrow" :size="15" /></button>
  </article>
</template>
