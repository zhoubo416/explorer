<script setup lang="ts">
import type { Goal, ViewId } from '~/composables/useExplore'

const props = defineProps<{ goal: Goal }>()
const emit = defineEmits<{ navigate: [view: ViewId] }>()
</script>

<template>
  <div class="created-view page-enter"><div class="created-sparkles"><span>✦</span><span>✧</span><span>✦</span></div><div class="created-icon"><Icon name="target" :size="34" /></div><span class="eyebrow">A NEW DIRECTION BEGINS</span><h1>目标创建！</h1><p>我们将一起努力，把它变成现实。<span>✦</span></p><div class="created-goal-card"><div class="goal-icon"><Icon name="target" :size="20" /></div><div><strong>{{ props.goal.title }}</strong><span>{{ props.goal.phase }} · {{ props.goal.status }}</span></div><Icon name="check" :size="18" /></div><div class="created-detail"><span class="eyebrow">{{ props.goal.phase }}</span><strong>{{ props.goal.description || '让方向在行动中逐渐清晰。' }}</strong><template v-if="props.goal.milestone"><span class="created-label">成功标准</span><ul><li><Icon name="check" :size="13" />{{ props.goal.milestone }}</li></ul></template></div><div class="created-actions"><button class="primary-button" type="button" @click="emit('navigate', 'goal-detail')">开始探索之旅 <Icon name="arrow" :size="16" /></button><button class="quiet-link" type="button" @click="emit('navigate', 'growth')">稍后再看</button></div></div>
</template>
