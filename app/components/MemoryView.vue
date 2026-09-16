<script setup lang="ts">
import type { MemoryItem, ViewId } from '~/composables/useExplore'

const props = defineProps<{ memories: readonly MemoryItem[]; timelineSummary: string | null }>()
const emit = defineEmits<{ navigate: [view: ViewId]; generateSummary: [] }>()
const activeFilter = shallowRef('全部')
const filters = ['全部', '事件', '决定', '反思', '成就']
const filteredMemories = computed(() => activeFilter.value === '全部' ? props.memories : props.memories.filter((memory) => memory.type.includes(activeFilter.value)))
const typeCount = computed(() => new Set(props.memories.map((memory) => memory.type)).size)
const groups = computed(() => {
  const map = new Map<string, MemoryItem[]>()
  filteredMemories.value.forEach((memory: MemoryItem) => map.set(memory.month, [...(map.get(memory.month) ?? []), memory]))
  return [...map.entries()]
})
</script>

<template>
  <div class="inner-view page-enter">
    <SectionHeading eyebrow="MEMORY OS · 你的成长轨迹" title="记忆，是理解的开始" description="探境会记住那些真正重要的时刻，在未来合适的时候，把它们带回你身边。"><button class="quiet-link" type="button" @click="emit('navigate', 'chat')">写下此刻 <Icon name="plus" :size="16" /></button></SectionHeading>

    <div class="memory-hero"><div class="memory-hero-quote">“ 每一次诚实的表达，<br><em>都在帮我更了解你。</em> ”</div><div class="memory-hero-stats"><div><strong>{{ props.memories.length }}</strong><span>条重要记忆</span></div><div><strong>{{ typeCount }}</strong><span>种成长类型</span></div><div><strong>{{ filteredMemories.length }}</strong><span>当前可见</span></div></div></div>

    <div v-if="props.timelineSummary || props.memories.length >= 3" class="timeline-summary"><div><span class="eyebrow">成长阶段总结</span><p>{{ props.timelineSummary || '让探境帮你回顾这段成长轨迹。' }}</p></div><button class="quiet-link" type="button" @click="emit('generateSummary')">{{ props.timelineSummary ? '重新生成' : '生成总结' }} <Icon name="arrow" :size="14" /></button></div>

    <section class="timeline-section"><div class="timeline-head"><span class="eyebrow">成长时间线</span><div class="filter-pills"><button v-for="filter in filters" :key="filter" type="button" :class="{ active: activeFilter === filter }" @click="activeFilter = filter">{{ filter }}</button></div></div><template v-if="filteredMemories.length"><div v-for="[month, items] in groups" :key="month" class="timeline-group"><span class="timeline-month">{{ month }}</span><div class="timeline-items"><MemoryRow v-for="memory in items" :key="memory.id" :memory="memory" /></div></div></template><div v-else class="empty-state"><Icon name="spark" :size="22" /><p>{{ props.memories.length ? '这个分类还没有记忆。' : '还没有记忆，开始一次对话吧。' }}</p></div></section>
  </div>
</template>
