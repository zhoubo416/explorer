<script setup lang="ts">
import type { Goal, ViewId } from '~/composables/useExplore'

const props = defineProps<{ goals: readonly Goal[]; currentGoalId: string }>()
const emit = defineEmits<{ setMainGoal: [id: string]; openGoal: [id: string]; createGoal: []; navigate: [view: ViewId] }>()

function selectGoal(goalId: string) {
  emit('setMainGoal', goalId)
  emit('openGoal', goalId)
}
</script>

<template>
  <div class="inner-view page-enter"><SectionHeading eyebrow="GOAL OS · 成长方向" title="我的成长方向" description="目标不是任务，而是你正在成为的那个人。"><button class="primary-button small" type="button" @click="emit('createGoal')"><Icon name="plus" :size="16" /> 创建新目标</button></SectionHeading><div class="goal-overview"><span class="eyebrow">当前专注</span><div class="overview-head"><h2>一条路，也可以走得很深。</h2><div class="overview-stats"><div class="overview-stat"><strong>{{ props.goals.length }}</strong><span>个成长方向</span></div><div class="overview-stat"><strong>{{ props.goals[0]?.progress ?? 0 }}%</strong><span>主目标进度</span></div></div></div><p>你可以拥有多个成长方向，但此刻只需要把注意力交给最重要的一个。</p></div><section class="goal-list-section"><div class="section-label-row"><div><span class="eyebrow">你的方向</span><h2>全部目标</h2></div><span class="soft-count">{{ props.goals.length }} 个方向</span></div><div class="goals-list"><GoalCard v-for="goal in props.goals" :key="goal.id" :goal="goal" :featured="goal.id === props.currentGoalId" @select="selectGoal" /></div></section><div class="goal-tip"><div class="tip-icon"><Icon name="spark" :size="18" /></div><div><span class="eyebrow">探境提醒</span><p>目标可以调整，方向也可以重新选择。重要的是，你始终知道自己为什么出发。</p></div></div></div>
</template>
