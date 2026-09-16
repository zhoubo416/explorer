<script setup lang="ts">
import type { Goal } from '~/composables/useExplore'

const props = defineProps<{ goal: Goal; featured?: boolean }>()
const emit = defineEmits<{ select: [id: string] }>()
</script>

<template>
  <button class="goal-card" :class="[`goal-${props.goal.accent}`, { featured: props.featured }]" type="button" @click="emit('select', props.goal.id)">
    <div class="goal-card-top"><div class="goal-icon"><Icon :name="props.goal.icon" :size="20" /></div><span v-if="props.featured" class="main-goal-label">当前主目标</span><span v-else class="goal-status"><i />{{ props.goal.status }}</span><Icon class="goal-arrow" name="chevron" :size="18" /></div>
    <div class="goal-card-title"><strong>{{ props.goal.title }}</strong><span>{{ props.goal.description }}</span></div>
    <div class="progress-line"><span :style="{ width: `${props.goal.progress}%` }" /></div>
    <div class="goal-card-bottom"><span>{{ props.goal.phase }}</span><strong>{{ props.goal.progress }}%</strong></div>
  </button>
</template>
