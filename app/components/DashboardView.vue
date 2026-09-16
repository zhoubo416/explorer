<script setup lang="ts">
import type { Goal, MemoryItem, Observation, ViewId } from '~/composables/useExplore'

const props = defineProps<{ currentGoal: Goal; observations: readonly Observation[]; memories: readonly MemoryItem[]; dailySuggestion: string }>()
const emit = defineEmits<{ navigate: [view: ViewId]; markObservationRead: [id: string] }>()

const today = computed(() =>
  new Date().toLocaleDateString('zh-CN', { month: 'long', day: 'numeric', weekday: 'long' }),
)
const greeting = computed(() => {
  const hour = new Date().getHours()
  if (hour < 11) return '早上好'
  if (hour < 18) return '下午好'
  return '晚上好'
})
const hasGoal = computed(() => props.currentGoal.id !== '')
</script>

<template>
  <div class="dashboard-view page-enter">
    <section class="welcome-row"><div><span class="eyebrow">{{ today }}</span><h1>{{ greeting }} <span class="wave">✦</span></h1><p>今天也和自己靠近一点。</p></div><button class="streak-badge" type="button" @click="emit('navigate', 'memory')"><span>成长记录</span><strong>{{ props.memories.length }} <small>条</small></strong><Icon name="spark" :size="16" /></button></section>

    <section class="hero-grid"><div><span class="eyebrow">{{ hasGoal ? '正在靠近' : '欢迎来到探境' }}</span><template v-if="hasGoal"><h2>你正在靠近<br><em>「{{ props.currentGoal.title }}」。</em></h2><p>下一步：{{ props.dailySuggestion || props.currentGoal.milestone || '从一个小行动开始' }}。</p><button class="primary-button" type="button" @click="emit('navigate', 'chat')">和我聊聊 <Icon name="arrow" :size="16" /></button></template><template v-else><h2>让我们先<br><em>认识彼此。</em></h2><p>从一次对话开始，我会了解你、帮你发现方向，再一起定下第一个目标。</p><button class="primary-button" type="button" @click="emit('navigate', 'goal-create')">开始认识我 <Icon name="arrow" :size="16" /></button></template></div><div class="hero-visual"><div class="hero-orb"><span /><i /><b /></div></div></section>

    <section class="dashboard-grid"><div class="dashboard-main"><div class="section-label-row"><div><span class="eyebrow">AI 今日观察</span><h2>给你的一个发现</h2></div><button class="quiet-link" type="button" @click="emit('navigate', 'report')">查看周报 <Icon name="arrow" :size="15" /></button></div><div v-if="props.observations.length" class="observation-grid"><ObservationCard v-for="observation in props.observations" :key="observation.id" :observation="observation" @mark-read="(id: string) => emit('markObservationRead', id)" /></div><div v-else class="dashboard-empty"><Icon name="spark" :size="20" /><p>还没有新的观察。</p></div></div><aside class="goal-panel"><div class="section-label-row"><div><span class="eyebrow">正在靠近</span><h2>当前主目标</h2></div><button class="round-button" type="button" @click="emit('navigate', 'growth')"><Icon name="arrow" :size="16" /></button></div><GoalCard :goal="props.currentGoal" featured @select="emit('navigate', 'growth')" /></aside></section>

    <section class="recent-section"><div class="section-label-row"><div><span class="eyebrow">留下来的痕迹</span><h2>最近成长记录</h2></div><button class="quiet-link" type="button" @click="emit('navigate', 'memory')">查看全部 <Icon name="arrow" :size="15" /></button></div><div v-if="props.memories.length" class="memory-list"><MemoryRow v-for="memory in props.memories.slice(0, 3)" :key="memory.id" :memory="memory" /></div><div v-else class="dashboard-empty"><Icon name="memory" :size="20" /><p>还没有成长记录。</p></div></section>
  </div>
</template>
